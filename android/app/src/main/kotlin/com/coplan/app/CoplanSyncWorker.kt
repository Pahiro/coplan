package com.coplan.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.work.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.time.LocalDate
import java.time.LocalTime
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.concurrent.TimeUnit

/**
 * Periodic background worker (every 15 min, network required).
 *
 * Mirrors the Dart [ResolutionEngine] for the active household:
 *  1. Reads the PocketBase auth token + URL from Flutter's SharedPreferences.
 *  2. Loads the user's active household config (rotation anchor, pattern-based
 *     scheme, mode, parent/helper names + colours).
 *  3. Resolves the next 3 days — base rules, manual overrides, accepted custody
 *     requests, AND virtual occurrences expanded from recurring arrangements.
 *  4. Writes resolved events to HomeWidgetPlugin prefs and updates the widgets.
 *  5. Notifies for new pending requests addressed to the current user.
 */
class CoplanSyncWorker(
    private val ctx: Context,
    params: WorkerParameters
) : CoroutineWorker(ctx, params) {

    private val flutterPrefs by lazy {
        ctx.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
    }
    private val workerPrefs by lazy {
        ctx.getSharedPreferences("CoplanWorkerPrefs", Context.MODE_PRIVATE)
    }
    private val widgetPrefs by lazy {
        ctx.getSharedPreferences("HomeWidgetPlugin", Context.MODE_PRIVATE)
    }

    /** Resolved household configuration used to mirror the Dart engine. */
    private class Cfg(
        val anchor: LocalDate,
        val pattern: IntArray,
        val mode: String,            // "custody" | "shared"
        val evenName: String,
        val oddName: String,
        val colorByName: Map<String, Long>,
    )

    // ── Entry point ──────────────────────────────────────────────────────────

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        try {
            val authStr = flutterPrefs.getString("flutter.pb_auth", null)
                ?: return@withContext Result.success() // not logged in

            val auth  = JSONObject(authStr)
            val token = auth.optString("token").takeIf { it.isNotEmpty() }
                ?: return@withContext Result.success()

            val model = auth.optJSONObject("model") ?: auth.optJSONObject("record")
            val myId  = model?.optString("id") ?: ""

            val pbUrl = flutterPrefs.getString("flutter.pb_url", "http://localhost:8090")
                ?.trimEnd('/') ?: "http://localhost:8090"
            val anchorFallback = parseDate(
                flutterPrefs.getString("flutter.rotation_anchor", "2026-05-18")
            ) ?: LocalDate.of(2026, 5, 18)

            // ── 1. Resolve the active household config ───────────────────
            val hid = if (myId.isNotEmpty())
                fetchRecord(pbUrl, token, "users", myId)
                    ?.optString("active_household")?.takeIf { it.isNotEmpty() }
            else null
            val cfg = buildCfg(pbUrl, token, hid, anchorFallback)

            // ── 2. Resolve schedule for next 3 days ──────────────────────
            val rules        = fetchCollection(pbUrl, token, "rules_base")
            val weekdayRules = fetchCollection(pbUrl, token, "custody_weekday_rules",
                filter = "active=true")
            val recurring    = fetchCollection(pbUrl, token, "custody_recurring",
                filter = "active=true")

            val today     = LocalDate.now()
            val allEvents = mutableListOf<JSONObject>()

            // Fetch absences once; filter per-day below.
            val allAbsences = fetchCollection(pbUrl, token, "absence_periods")

            repeat(3) { i ->
                val date    = today.plusDays(i.toLong())
                val dateStr = date.format(DateTimeFormatter.ISO_LOCAL_DATE)
                val overrides = fetchCollection(
                    pbUrl, token, "manual_overrides",
                    filter = "target_date='$dateStr'"
                )
                val realCustody = fetchCollection(
                    pbUrl, token, "custody_requests",
                    filter = "date='$dateStr'&&status='accepted'"
                )
                // Merge real custody with virtual recurring occurrences, exactly
                // like the Dart engine's effectiveCustodyFor().
                val custody = JSONArray()
                for (k in 0 until realCustody.length()) custody.put(realCustody.getJSONObject(k))
                val dayAbsences = absencesForDate(date, allAbsences)
                for (v in virtualRecurring(date, cfg, recurring, weekdayRules, realCustody, dayAbsences)) {
                    custody.put(v)
                }
                allEvents += resolveDay(date, rules, overrides, weekdayRules, cfg, custody, dayAbsences)
            }

            // Keep only events that haven't happened yet today (take first 3)
            val nowTime = LocalTime.now()
            val upcoming = JSONArray()
            for (e in allEvents) {
                val eDate = LocalDate.parse(e.getString("date"))
                val (h, m) = e.getString("time").split(":").map { it.toIntOrNull() ?: 0 }
                val isFuture = eDate.isAfter(today) ||
                    (eDate == today && h * 60 + m >= nowTime.hour * 60 + nowTime.minute)
                if (isFuture) upcoming.put(e)
                if (upcoming.length() >= 3) break
            }

            // ── 3. Update all widget styles ──────────────────────────────
            // Only overwrite when we have events — avoids blanking the widget
            // due to a transient network/auth failure (mirrors Dart guard).
            if (upcoming.length() > 0) {
                widgetPrefs.edit().putString("coplan_widget_events", upcoming.toString()).apply()
                val manager = GlanceAppWidgetManager(ctx)
                manager.getGlanceIds(CoplanWidget::class.java)
                    .forEach { id -> CoplanWidget().update(ctx, id) }
                manager.getGlanceIds(CoplanWidget2::class.java)
                    .forEach { id -> CoplanWidget2().update(ctx, id) }
                manager.getGlanceIds(CoplanWidget3::class.java)
                    .forEach { id -> CoplanWidget3().update(ctx, id) }
            }

            // ── 4. Notify for new pending requests ───────────────────────
            if (myId.isNotEmpty()) notifyNewRequests(pbUrl, token, myId)

            Result.success()
        } catch (_: Exception) {
            Result.retry()
        }
    }

    // ── Household config ──────────────────────────────────────────────────────

    private fun buildCfg(
        pbUrl: String, token: String, hid: String?, anchorFallback: LocalDate
    ): Cfg {
        // Legacy fallback when there's no household (pre-migration installs).
        if (hid == null) {
            return Cfg(
                anchor = anchorFallback,
                pattern = presetFor("weekly"),
                mode = "custody",
                evenName = "Bennet",
                oddName = "Jana",
                colorByName = mapOf("Bennet" to 0xFF1565C0L, "Jana" to 0xFFD81B60L),
            )
        }

        val h = fetchRecord(pbUrl, token, "households", hid)
        val anchor = parseDate(h?.optString("rotation_anchor")) ?: anchorFallback
        val mode = h?.optString("mode")?.takeIf { it.isNotEmpty() } ?: "custody"

        val patArr = h?.optJSONArray("rotation_pattern")
        val pattern = if (patArr != null && patArr.length() > 0)
            IntArray(patArr.length()) { patArr.optInt(it) }
        else presetFor(h?.optString("rotation_scheme_type") ?: "weekly")

        // Members → name, role, user id (colour from each user's preferred_color,
        // fetched per-member to match the Dart side and respect view rules).
        val members = fetchCollection(pbUrl, token, "household_members",
            filter = "household='$hid'")

        val palette = longArrayOf(0xFF1565C0L, 0xFFD81B60L, 0xFF00897BL, 0xFFFF8F00L)
        val colorByName = mutableMapOf<String, Long>()
        val nameByUserId = mutableMapOf<String, String>()
        val parentNames = mutableListOf<String>()
        var pi = 0
        for (i in 0 until members.length()) {
            val m   = members.getJSONObject(i)
            val uid = m.optString("user")
            val nm  = m.optString("display_name")
            if (nm.isEmpty()) continue
            nameByUserId[uid] = nm
            val userColor = parseHex(
                fetchRecord(pbUrl, token, "users", uid)?.optString("preferred_color"))
            colorByName[nm] = userColor ?: palette[pi % palette.size]
            pi++
            if (m.optString("role") == "parent") parentNames += nm
        }

        val evenName = nameByUserId[h?.optString("rotation_parent_even")]
            ?: parentNames.getOrNull(0) ?: "Parent A"
        val oddName = nameByUserId[h?.optString("rotation_parent_odd")]
            ?: parentNames.getOrNull(1) ?: "Parent B"

        return Cfg(anchor, pattern, mode, evenName, oddName, colorByName)
    }

    /** Rotation patterns mirroring Dart RotationScheme (0 = even, 1 = odd). */
    private fun presetFor(type: String): IntArray = when (type) {
        "2-2-5-5"             -> intArrayOf(0,0,1,1,0,0,0,0,0,1,1,1,1,1)
        "2-2-3"               -> intArrayOf(0,0,1,1,0,0,0,1,1,0,0,1,1,1)
        "alternating_weekends" -> intArrayOf(0,0,0,0,0,0,0,0,0,0,0,0,1,1)
        else                   -> intArrayOf(0,0,0,0,0,0,0,1,1,1,1,1,1,1) // weekly
    }

    // ── Owner resolution (mirrors Dart weekOwner / baseOwner) ────────────────

    private fun rotationOwner(date: LocalDate, cfg: Cfg): String {
        if (cfg.mode == "shared") return "Both"
        val len = cfg.pattern.size.takeIf { it > 0 } ?: 14
        val daysSince = ChronoUnit.DAYS.between(cfg.anchor, date)
        val idx = (((daysSince % len) + len) % len).toInt()
        return if (cfg.pattern[idx] == 0) cfg.evenName else cfg.oddName
    }

    private fun baseOwner(date: LocalDate, cfg: Cfg, weekdayRules: JSONArray): String {
        if (cfg.mode == "shared") return "Both"
        val dow = date.dayOfWeek.value
        for (j in 0 until weekdayRules.length()) {
            val wr = weekdayRules.getJSONObject(j)
            if (wr.optInt("day_of_week") == dow) {
                if (pastEndDate(wr, date)) continue // rule has lapsed → rotation
                val p = wr.optString("assigned_parent")
                if (p.isNotEmpty()) return p
            }
        }
        return rotationOwner(date, cfg)
    }

    private fun colorFor(name: String, cfg: Cfg): Long =
        if (name == "Both") 0xFF7E57C2L else (cfg.colorByName[name] ?: 0xFF607D8BL)

    /** "All" → "All", "Henri" → "Henri", "Henri,Chris" → "Henri & Chris". */
    private fun custodyChildLabel(childName: String): String {
        if (childName == "All") return "All"
        val parts = childName.split(",").map { it.trim() }.filter { it.isNotEmpty() }
        if (parts.size <= 1) return childName
        return "${parts.dropLast(1).joinToString(", ")} & ${parts.last()}"
    }

    // ── Recurring expansion (mirrors Dart _virtualRecurringFor) ──────────────

    private fun virtualRecurring(
        date: LocalDate, cfg: Cfg, recurring: JSONArray,
        weekdayRules: JSONArray, realCustody: JSONArray,
        dayAbsences: JSONArray = JSONArray(),
    ): List<JSONObject> {
        if (date.isBefore(LocalDate.now())) return emptyList()
        val dow  = date.dayOfWeek.value
        val base = baseOwner(date, cfg, weekdayRules)
        val out  = mutableListOf<JSONObject>()

        for (i in 0 until recurring.length()) {
            val a = recurring.getJSONObject(i)
            if (a.optInt("day_of_week") != dow) continue
            val start = parseDate(a.optString("start_date")) ?: continue
            if (date.isBefore(start)) continue
            if (pastEndDate(a, date)) continue // arrangement has lapsed
            val toParent = a.optString("to_parent").takeIf { it.isNotEmpty() } ?: continue
            if (base == toParent) continue   // recipient already owns the day
            if (isAbsent(toParent, date, dayAbsences)) continue  // absent — can't take kids

            val child = a.optString("child_name", "All")
            var covered = false
            for (k in 0 until realCustody.length()) {
                val r = realCustody.getJSONObject(k)
                val c = r.optString("child_name", "All")
                val sameRecipient = r.optString("to_parent") == toParent
                if (sameRecipient && (c == child || c == "All" || child == "All")) {
                    covered = true; break
                }
            }
            if (covered) continue

            out += JSONObject().apply {
                put("from_parent",      base)
                put("to_parent",        toParent)
                put("date",             date.format(DateTimeFormatter.ISO_LOCAL_DATE))
                put("child_name",       child)
                put("pickup_time",      a.optString("pickup_time", "00:00"))
                put("return_time",      a.optString("return_time", ""))
                put("return_time_tbd",  a.optBoolean("return_time_tbd", false))
                put("status",           "accepted")
            }
        }
        return out
    }

    // ── Absence helpers (mirrors Dart AbsencePeriod.coversDate / _applyAbsence) ─

    private fun absencesForDate(date: LocalDate, absences: JSONArray): JSONArray {
        val out = JSONArray()
        for (i in 0 until absences.length()) {
            val a = absences.getJSONObject(i)
            val start = parseDate(a.optString("start_date")) ?: continue
            val end   = parseDate(a.optString("end_date"))   ?: continue
            if (!date.isBefore(start) && !date.isAfter(end)) out.put(a)
        }
        return out
    }

    /** True when [parent] has an active absence on this day. */
    private fun isAbsent(parent: String, date: LocalDate, dayAbsences: JSONArray): Boolean {
        for (i in 0 until dayAbsences.length()) {
            if (dayAbsences.getJSONObject(i).optString("absent_parent") == parent) return true
        }
        return false
    }

    /** If [scheduled] is absent on this day, flip to the other rotation parent. */
    private fun applyAbsence(scheduled: String, cfg: Cfg, dayAbsences: JSONArray): String {
        for (i in 0 until dayAbsences.length()) {
            val a = dayAbsences.getJSONObject(i)
            if (a.optString("absent_parent") == scheduled) {
                return if (scheduled == cfg.evenName) cfg.oddName else cfg.evenName
            }
        }
        return scheduled
    }

    // ── Schedule resolution (mirrors Dart ResolutionEngine.resolveDay) ───────

    /** Returns the custody-request parent who owns [time] on a given day, or null if none applies. */
    private fun parentAtTime(time: String, custodyRequests: JSONArray): String? {
        val parts  = time.split(":")
        val timeMin = (parts[0].toIntOrNull() ?: 0) * 60 + (parts[1].toIntOrNull() ?: 0)
        // Windows first (pickup ≤ time < return)
        for (k in 0 until custodyRequests.length()) {
            val r     = custodyRequests.getJSONObject(k)
            val rt    = r.optString("return_time").takeIf { it.isNotEmpty() }
            val rtTbd = r.optBoolean("return_time_tbd", false)
            if (rt == null && !rtTbd) continue
            val pParts    = r.optString("pickup_time", "00:00").split(":")
            val pickupMin = (pParts[0].toIntOrNull() ?: 0) * 60 + (pParts[1].toIntOrNull() ?: 0)
            val returnMin = if (rtTbd || rt == null) 24 * 60 else {
                val rp = rt.split(":")
                (rp[0].toIntOrNull() ?: 0) * 60 + (rp[1].toIntOrNull() ?: 0)
            }
            if (timeMin >= pickupMin && timeMin < returnMin)
                return r.optString("to_parent").takeIf { it.isNotEmpty() }
        }
        // Then day transfers (time ≥ pickup)
        for (k in 0 until custodyRequests.length()) {
            val r     = custodyRequests.getJSONObject(k)
            val rt    = r.optString("return_time").takeIf { it.isNotEmpty() }
            val rtTbd = r.optBoolean("return_time_tbd", false)
            if (rt != null || rtTbd) continue
            val pParts    = r.optString("pickup_time", "00:00").split(":")
            val pickupMin = (pParts[0].toIntOrNull() ?: 0) * 60 + (pParts[1].toIntOrNull() ?: 0)
            if (timeMin >= pickupMin)
                return r.optString("to_parent").takeIf { it.isNotEmpty() }
        }
        return null
    }

    private fun resolveDay(
        date: LocalDate,
        rules: JSONArray,
        overrides: JSONArray,
        weekdayRules: JSONArray,
        cfg: Cfg,
        custodyRequests: JSONArray,
        dayAbsences: JSONArray = JSONArray(),
    ): List<JSONObject> {
        val dow     = date.dayOfWeek.value
        val results = mutableListOf<JSONObject>()

        for (i in 0 until rules.length()) {
            val rule = rules.getJSONObject(i)
            if (rule.optInt("day_of_week") != dow) continue
            if (pastEndDate(rule, date)) continue // standing event has lapsed
            // Directional handover rules only render when the named parent is
            // the outgoing custody holder (mirrors Dart resolveDay).
            val handoverFrom = rule.optString("handover_from")
            if (handoverFrom.isNotEmpty() && handoverFrom != rotationOwner(date, cfg)) continue

            val childName = rule.optString("child_name", "All")
            val time      = rule.optString("event_time", "08:00")
            val activity  = rule.optString("activity", "")
            val location  = rule.optString("location", "")

            // Priority 1 — non-adhoc manual override
            var parent: String? = null
            for (j in 0 until overrides.length()) {
                val ov       = overrides.getJSONObject(j)
                val ovReason = ov.optString("reason")
                val ovAdhoc  = ov.optBoolean("is_adhoc", false) || ovReason.isNotEmpty()
                if (ovAdhoc) continue
                val ovChild  = ov.optString("child_name", "All")
                if (ovChild == childName || ovChild == "All" || childName == "All") {
                    parent = ov.optString("assigned_parent")
                    break
                }
            }

            // Priority 2 — absence flip; priority 3 — weekday rule / rotation
            if (parent == null) {
                val base = baseOwner(date, cfg, weekdayRules)
                parent = applyAbsence(base, cfg, dayAbsences)
            }

            // Priority 4 — accepted custody (real + virtual recurring)
            val finalParent = parentAtTime(time, custodyRequests) ?: parent!!

            results += JSONObject().apply {
                put("date",             date.format(DateTimeFormatter.ISO_LOCAL_DATE))
                put("time",             time)
                put("activity",         activity)
                put("location",         location)
                put("childName",        childName)
                put("parent",           finalParent)
                put("parentColorValue", colorFor(finalParent, cfg))
            }
        }

        // ── Ad-hoc one-off events ─────────────────────────────────────────
        for (j in 0 until overrides.length()) {
            val ov     = overrides.getJSONObject(j)
            val reason = ov.optString("reason")
            val isAdhoc = ov.optBoolean("is_adhoc", false) || reason.isNotEmpty()
            if (!isAdhoc) continue

            val rawParent = ov.optString("assigned_parent").takeIf { it.isNotEmpty() }
                ?: baseOwner(date, cfg, weekdayRules)
            val activity = ov.optString("activity").ifEmpty { reason }
            val time     = ov.optString("override_time", "09:00")

            // Apply the same custody-request override that rule-based events use.
            val parent = parentAtTime(time, custodyRequests) ?: rawParent

            results += JSONObject().apply {
                put("date",             date.format(DateTimeFormatter.ISO_LOCAL_DATE))
                put("time",             time)
                put("activity",         activity)
                put("location",         ov.optString("location", ""))
                put("childName",        ov.optString("child_name", "All"))
                put("parent",           parent)
                put("parentColorValue", colorFor(parent, cfg))
            }
        }

        // ── Accepted custody-request banners (real + virtual recurring) ──────
        for (j in 0 until custodyRequests.length()) {
            val r        = custodyRequests.getJSONObject(j)
            val toParent = r.optString("to_parent")
            if (toParent.isEmpty()) continue
            val childName     = r.optString("child_name", "All")
            val pickupTime    = r.optString("pickup_time", "08:00")
            val returnTime    = r.optString("return_time").takeIf { it.isNotEmpty() }
            val returnTbd     = r.optBoolean("return_time_tbd", false)
            val isDayTransfer = returnTime == null && !returnTbd

            val who   = custodyChildLabel(childName)
            val label = if (isDayTransfer)
                "$who in $toParent's care"
            else {
                val end = if (returnTbd) "TBD" else (returnTime ?: "TBD")
                "$who in $toParent's care · $pickupTime–$end"
            }

            results += JSONObject().apply {
                put("date",             date.format(DateTimeFormatter.ISO_LOCAL_DATE))
                put("time",             pickupTime)
                put("activity",         label)
                put("location",         "")
                put("childName",        childName)
                put("parent",           toParent)
                put("parentColorValue", colorFor(toParent, cfg))
                put("isCustody",        true)
            }
        }

        // Sort by time; custody banners sort before others at the same minute.
        results.sortWith { a, b ->
            fun mins(o: JSONObject): Int {
                val p = o.getString("time").split(":")
                return (p[0].toIntOrNull() ?: 0) * 60 + (p[1].toIntOrNull() ?: 0)
            }
            val cmp = mins(a).compareTo(mins(b))
            if (cmp != 0) return@sortWith cmp
            val aCust = a.optBoolean("isCustody", false)
            val bCust = b.optBoolean("isCustody", false)
            when {
                aCust == bCust -> 0
                aCust          -> -1
                else           ->  1
            }
        }
        return results
    }

    // ── Custody request notification ─────────────────────────────────────────

    private fun notifyNewRequests(pbUrl: String, token: String, myId: String) {
        val pending = fetchCollection(
            pbUrl, token, "custody_requests",
            filter = "status='pending'&&requested_from='$myId'"
        )
        if (pending.length() == 0) return

        val seenRaw = workerPrefs.getString("seen_request_ids", "[]") ?: "[]"
        val seen    = (0 until JSONArray(seenRaw).length())
            .map { JSONArray(seenRaw).getString(it) }.toMutableSet()

        var firstBody = ""
        val newIds    = mutableListOf<String>()

        for (i in 0 until pending.length()) {
            val r  = pending.getJSONObject(i)
            val id = r.optString("id")
            if (id !in seen) {
                newIds += id
                if (firstBody.isEmpty()) {
                    val child = r.optString("child_name", "the children")
                    val date  = r.optString("date", "an upcoming date")
                    firstBody = "You're asked to handle $child on $date"
                }
            }
        }

        if (newIds.isEmpty()) return

        val allIds = JSONArray().also {
            for (i in 0 until pending.length()) it.put(pending.getJSONObject(i).optString("id"))
        }
        workerPrefs.edit().putString("seen_request_ids", allIds.toString()).apply()

        showNotification(
            id    = 1,
            title = "New Pickup Request" + if (newIds.size > 1) " (${newIds.size})" else "",
            body  = firstBody
        )
    }

    private fun showNotification(id: Int, title: String, body: String) {
        val channelId = "coplan_requests"

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(channelId, "Pickup Requests", NotificationManager.IMPORTANCE_HIGH)
                .apply { description = "CoPlan pickup request notifications" }
            (ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(ch)
        }

        val pi = PendingIntent.getActivity(
            ctx, 0,
            ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)
                ?.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        NotificationManagerCompat.from(ctx).notify(
            id,
            NotificationCompat.Builder(ctx, channelId)
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentTitle(title)
                .setContentText(body)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setContentIntent(pi)
                .setAutoCancel(true)
                .build()
        )
    }

    // ── PocketBase REST helpers ───────────────────────────────────────────────

    private fun fetchCollection(
        pbUrl: String, token: String, collection: String, filter: String = ""
    ): JSONArray {
        val query = if (filter.isNotEmpty())
            "?filter=${URLEncoder.encode(filter, "UTF-8")}&perPage=200"
        else "?perPage=200"
        return try {
            val conn = URL("$pbUrl/api/collections/$collection/records$query")
                .openConnection() as HttpURLConnection
            conn.setRequestProperty("Authorization", token)
            conn.connectTimeout = 10_000
            conn.readTimeout    = 10_000
            JSONObject(conn.inputStream.bufferedReader().readText())
                .optJSONArray("items") ?: JSONArray()
        } catch (_: Exception) {
            JSONArray()
        }
    }

    private fun fetchRecord(
        pbUrl: String, token: String, collection: String, id: String
    ): JSONObject? = try {
        val conn = URL("$pbUrl/api/collections/$collection/records/$id")
            .openConnection() as HttpURLConnection
        conn.setRequestProperty("Authorization", token)
        conn.connectTimeout = 10_000
        conn.readTimeout    = 10_000
        JSONObject(conn.inputStream.bufferedReader().readText())
    } catch (_: Exception) {
        null
    }

    private fun parseDate(s: String?): LocalDate? =
        try { if (s.isNullOrEmpty()) null else LocalDate.parse(s.substring(0, 10)) }
        catch (_: Exception) { null }

    /** True when [rec] carries an end_date and [date] is past it (inclusive end).
     *  Mirrors the Dart engine's optional repeat end-date. */
    private fun pastEndDate(rec: JSONObject, date: LocalDate): Boolean {
        val end = parseDate(rec.optString("end_date")) ?: return false
        return date.isAfter(end)
    }

    private fun parseHex(s: String?): Long? {
        if (s == null || !s.startsWith("#") || s.length != 7) return null
        return try { 0xFF000000L or s.substring(1).toLong(16) } catch (_: Exception) { null }
    }

    // ── Companion ────────────────────────────────────────────────────────────

    companion object {
        const val WORK_NAME = "coplan_periodic_sync"

        fun schedule(context: Context) {
            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                WORK_NAME,
                ExistingPeriodicWorkPolicy.UPDATE,
                PeriodicWorkRequestBuilder<CoplanSyncWorker>(15, TimeUnit.MINUTES)
                    .setConstraints(
                        Constraints.Builder()
                            .setRequiredNetworkType(NetworkType.CONNECTED)
                            .build()
                    )
                    .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 15, TimeUnit.MINUTES)
                    .build()
            )
        }

        fun cancel(context: Context) =
            WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME)

        /** Trigger an immediate one-shot sync — use when a widget is first added. */
        fun runOnce(context: Context) {
            WorkManager.getInstance(context).enqueue(
                OneTimeWorkRequestBuilder<CoplanSyncWorker>()
                    .setConstraints(
                        Constraints.Builder()
                            .setRequiredNetworkType(NetworkType.CONNECTED)
                            .build()
                    )
                    .build()
            )
        }
    }
}
