package com.coplan.app

import android.content.Context
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
 * Periodic background worker (every 15 min, network required) that refreshes
 * the home-screen widgets with the next three events.
 *
 * Mirrors the Dart ResolutionEngine for the active household — change one,
 * update the other:
 *   who has the kids = accepted day transfer (from its pickup time)
 *                      > absence flip > holiday block > rotation
 *   per event        = manual override > the above; accepted time windows and
 *                      transfers win by time of day. One-off events resolve
 *                      their parent live.
 *
 * Notifications are not sent from here — FCM push (pb_hooks) is the single
 * source of OS notifications.
 */
class CoplanSyncWorker(
    private val ctx: Context,
    params: WorkerParameters
) : CoroutineWorker(ctx, params) {

    private val flutterPrefs by lazy {
        ctx.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
    }
    private val widgetPrefs by lazy {
        ctx.getSharedPreferences("HomeWidgetPlugin", Context.MODE_PRIVATE)
    }

    /** Household configuration used to mirror the Dart engine. */
    private class Cfg(
        val anchor: LocalDate,
        val pattern: IntArray,
        val mode: String,            // "custody" | "shared"
        val evenName: String,
        val oddName: String,
        val colorByName: Map<String, Long>,
    )

    /** The per-date inputs for one day of resolution. */
    private class Day(
        val date: LocalDate,
        val overrides: List<JSONObject>,
        val custody: List<JSONObject>,
        val absences: List<JSONObject>,
        val holidayOwner: String?,
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
            val myId  = model?.optString("id").orEmpty()
            val pbUrl = flutterPrefs.getString("flutter.pb_url", null)?.trimEnd('/')
            if (myId.isEmpty() || pbUrl == null) return@withContext Result.success()

            val hid = fetchRecord(pbUrl, token, "users", myId)
                ?.optString("active_household")?.takeIf { it.isNotEmpty() }
                ?: return@withContext Result.success()
            val cfg = buildCfg(pbUrl, token, hid) ?: return@withContext Result.retry()

            val today = LocalDate.now()
            val from  = today.format(ISO)
            val to    = today.plusDays(2).format(ISO)
            val mine  = "household='$hid'"

            val rules     = fetchCollection(pbUrl, token, "rules_base", mine).objects()
            val overrides = fetchCollection(pbUrl, token, "manual_overrides",
                "$mine&&target_date>='$from'&&target_date<='$to'").objects()
            val custody   = fetchCollection(pbUrl, token, "custody_requests",
                "$mine&&status='accepted'&&date>='$from'&&date<='$to'").objects()
            val absences  = fetchCollection(pbUrl, token, "absence_periods",
                "$mine&&start_date<='$to'&&end_date>='$from'").objects()
            val holidays  = fetchCollection(pbUrl, token, "holiday_blocks",
                "$mine&&start_date<='$to'&&end_date>='$from'").objects()

            val nowMin   = LocalTime.now().let { it.hour * 60 + it.minute }
            val upcoming = JSONArray()
            for (i in 0..2) {
                val date = today.plusDays(i.toLong())
                val ds   = date.format(ISO)
                val day  = Day(
                    date         = date,
                    overrides    = overrides.filter { it.optString("target_date").take(10) == ds },
                    custody      = custody.filter { it.optString("date").take(10) == ds },
                    absences     = absences.filter { covers(it, date) },
                    holidayOwner = holidays.firstOrNull { covers(it, date) }
                        ?.optString("assigned_parent")?.takeIf { it.isNotEmpty() },
                )
                for (e in resolveDay(day, rules, cfg)) {
                    if (i == 0 && minutes(e.getString("time")) < nowMin) continue
                    upcoming.put(e)
                    if (upcoming.length() >= 3) break
                }
                if (upcoming.length() >= 3) break
            }

            widgetPrefs.edit().putString("coplan_widget_events", upcoming.toString()).apply()
            val manager = GlanceAppWidgetManager(ctx)
            manager.getGlanceIds(CoplanWidget::class.java)
                .forEach { id -> CoplanWidget().update(ctx, id) }
            manager.getGlanceIds(CoplanWidget2::class.java)
                .forEach { id -> CoplanWidget2().update(ctx, id) }
            manager.getGlanceIds(CoplanWidget3::class.java)
                .forEach { id -> CoplanWidget3().update(ctx, id) }

            Result.success()
        } catch (_: Exception) {
            // Keep the last good widget data; try again later.
            Result.retry()
        }
    }

    // ── Household config ──────────────────────────────────────────────────────

    private fun buildCfg(pbUrl: String, token: String, hid: String): Cfg? {
        val h = fetchRecord(pbUrl, token, "households", hid) ?: return null
        val anchor = parseDate(h.optString("rotation_anchor")) ?: LocalDate.of(2025, 1, 6)
        val mode = h.optString("mode").ifEmpty { "custody" }

        val patArr = h.optJSONArray("rotation_pattern")
        val pattern = if (patArr != null && patArr.length() > 0)
            IntArray(patArr.length()) { patArr.optInt(it) }
        else presetFor(h.optString("rotation_scheme_type"))

        val evenId = h.optString("rotation_parent_even")
        val oddId  = h.optString("rotation_parent_odd")
        val members = fetchCollection(pbUrl, token, "household_members",
            "household='$hid'").objects()

        // Mirrors Dart AppColors.forHousehold: preferred colour, else blue for
        // the even parent, pink for the odd parent, else the palette in order.
        val colorByName = mutableMapOf<String, Long>()
        var evenName = "Parent A"
        var oddName  = "Parent B"
        for (m in members) {
            val name = m.optString("display_name")
            if (name.isEmpty()) continue
            val uid = m.optString("user")
            if (uid == evenId) evenName = name
            if (uid == oddId) oddName = name
            colorByName[name] = parseHex(m.optString("preferred_color")) ?: when (uid) {
                evenId -> PALETTE[0]
                oddId  -> PALETTE[1]
                else   -> PALETTE[colorByName.size % PALETTE.size]
            }
        }
        return Cfg(anchor, pattern, mode, evenName, oddName, colorByName)
    }

    /** Rotation patterns mirroring Dart RotationScheme (0 = even, 1 = odd). */
    private fun presetFor(type: String): IntArray = when (type) {
        "2-2-5-5"              -> intArrayOf(0,0,1,1,0,0,0,0,0,1,1,1,1,1)
        "2-2-3"                -> intArrayOf(0,0,1,1,0,0,0,1,1,0,0,1,1,1)
        "alternating_weekends" -> intArrayOf(0,0,0,0,0,0,0,0,0,0,0,0,1,1)
        else                   -> intArrayOf(0,0,0,0,0,0,0,1,1,1,1,1,1,1) // weekly
    }

    // ── Owner resolution (mirrors ResolutionEngine) ──────────────────────────

    /** Dart `weekOwner`. */
    private fun rotationOwner(date: LocalDate, cfg: Cfg): String {
        if (cfg.mode == "shared") return "Both"
        val len = cfg.pattern.size.takeIf { it > 0 } ?: return cfg.evenName
        val daysSince = ChronoUnit.DAYS.between(cfg.anchor, date)
        val idx = (((daysSince % len) + len) % len).toInt()
        return if (cfg.pattern[idx] == 0) cfg.evenName else cfg.oddName
    }

    /** Dart `_scheduledOwner`: holiday block, else rotation. */
    private fun scheduledOwner(day: Day, cfg: Cfg): String =
        day.holidayOwner ?: rotationOwner(day.date, cfg)

    /** Dart `baseOwner`. */
    private fun baseOwner(day: Day, cfg: Cfg): String =
        if (cfg.mode == "shared") "Both" else scheduledOwner(day, cfg)

    /** Dart `_applyAbsence`. */
    private fun applyAbsence(scheduled: String, day: Day, cfg: Cfg): String {
        val absence = day.absences.firstOrNull() ?: return scheduled
        if (absence.optString("absent_parent") != scheduled) return scheduled
        return when (scheduled) {
            cfg.evenName -> cfg.oddName
            cfg.oddName  -> cfg.evenName
            else         -> scheduled
        }
    }

    private fun isDayTransfer(r: JSONObject): Boolean =
        r.optString("return_time").isEmpty() && !r.optBoolean("return_time_tbd", false)

    /** Dart `_requestMatchesChild`. */
    private fun matchesChild(r: JSONObject, child: String?): Boolean {
        val rc = r.optString("child_name", "All")
        if (child == null || child == "All" || rc == "All") return true
        return rc.split(",").map { it.trim() }.contains(child)
    }

    private fun dayTransfer(day: Day, child: String?): JSONObject? =
        day.custody.firstOrNull { isDayTransfer(it) && matchesChild(it, child) }

    private fun windowBounds(r: JSONObject): Pair<Int, Int> {
        val rt = r.optString("return_time")
        val ret = if (r.optBoolean("return_time_tbd", false) || rt.isEmpty()) 24 * 60 else minutes(rt)
        return minutes(r.optString("pickup_time")) to ret
    }

    /** Dart `dayOwner`. */
    private fun dayOwner(day: Day, cfg: Cfg): String {
        dayTransfer(day, null)?.let { return it.optString("to_parent") }
        if (cfg.mode == "shared") return "Both"
        return applyAbsence(scheduledOwner(day, cfg), day, cfg)
    }

    /** Dart `parentAtTime`. */
    private fun parentAtTime(day: Day, time: Int, child: String?, cfg: Cfg): String {
        for (r in day.custody) {
            if (isDayTransfer(r) || !matchesChild(r, child)) continue
            val (pickup, ret) = windowBounds(r)
            if (time in pickup until ret) return r.optString("to_parent")
        }
        dayTransfer(day, child)?.let {
            if (time >= minutes(it.optString("pickup_time"))) return it.optString("to_parent")
        }
        // Scheduled owner — not dayOwner(), which would apply a sibling's transfer.
        if (cfg.mode == "shared") return "Both"
        return applyAbsence(scheduledOwner(day, cfg), day, cfg)
    }

    /** Dart `_custodyNoteAt(...) != null`. */
    private fun custodyAffects(day: Day, time: Int, child: String?): Boolean {
        for (r in day.custody) {
            if (isDayTransfer(r) || !matchesChild(r, child)) continue
            val (pickup, ret) = windowBounds(r)
            if (time in pickup until ret) return true
        }
        val transfer = dayTransfer(day, child) ?: return false
        return time >= minutes(transfer.optString("pickup_time"))
    }

    /** Dart `ManualOverride.fromRecord` adhoc inference. */
    private fun isAdhoc(ov: JSONObject): Boolean =
        if (ov.has("is_adhoc") && !ov.isNull("is_adhoc")) ov.optBoolean("is_adhoc")
        else ov.optString("reason").isNotEmpty()

    // ── Schedule resolution (mirrors ResolutionEngine.resolveDay) ────────────

    private fun resolveDay(day: Day, rules: List<JSONObject>, cfg: Cfg): List<JSONObject> {
        val ds  = day.date.format(ISO)
        val dow = day.date.dayOfWeek.value
        val out = mutableListOf<JSONObject>()

        fun event(time: String, activity: String, location: String, child: String,
                  parent: String, isCustody: Boolean = false) = JSONObject().apply {
            put("date", ds)
            put("time", time)
            put("activity", activity)
            put("location", location)
            put("childName", child)
            put("parent", parent)
            put("parentColorValue", colorFor(parent, cfg))
            if (isCustody) put("isCustody", true)
        }

        // Standing events
        for (rule in rules) {
            if (rule.optInt("day_of_week") != dow) continue
            if (pastEndDate(rule, day.date)) continue
            val handoverFrom = rule.optString("handover_from")
            if (handoverFrom.isNotEmpty() && handoverFrom != baseOwner(day, cfg)) continue

            val child = rule.optString("child_name", "All")
            val override = day.overrides.firstOrNull { ov ->
                val oc = ov.optString("child_name", "All")
                !isAdhoc(ov) && (oc == child || oc == "All" || child == "All")
            }
            val time = override?.optString("override_time")?.takeIf { it.isNotEmpty() }
                ?: rule.optString("event_time", "08:00")
            val scheduled = override?.optString("assigned_parent")
                ?: applyAbsence(scheduledOwner(day, cfg), day, cfg)
            val childArg = if (child == "All") null else child
            val t = minutes(time)
            val parent = if (custodyAffects(day, t, childArg)) parentAtTime(day, t, childArg, cfg) else scheduled
            out += event(time, rule.optString("activity"), rule.optString("location"), child, parent)
        }

        // One-off events (including exams)
        for (ov in day.overrides) {
            if (!isAdhoc(ov)) continue
            val time = ov.optString("override_time").ifEmpty { "09:00" }
            val child = ov.optString("child_name", "All")
            val activity = ov.optString("activity").ifEmpty { ov.optString("reason") }
            val label = if (ov.optString("kind") == "exam") "Exam · $activity" else activity
            val parent = parentAtTime(day, minutes(time), if (child == "All") null else child, cfg)
            out += event(time, label, ov.optString("location"), child, parent)
        }

        // Accepted custody banners (handovers, swaps, windows)
        for (r in day.custody) {
            val to = r.optString("to_parent")
            if (to.isEmpty()) continue
            val child = r.optString("child_name", "All")
            val who = custodyChildLabel(child)
            val label = when {
                r.optString("swap_group").isNotEmpty() -> "$who in $to's care · swap"
                isDayTransfer(r) -> "$who in $to's care"
                else -> {
                    val rt = r.optString("return_time")
                    val end = if (r.optBoolean("return_time_tbd", false) || rt.isEmpty()) "TBD" else rt
                    "$who in $to's care · ${r.optString("pickup_time")}–$end"
                }
            }
            out += event(r.optString("pickup_time").ifEmpty { "00:00" }, label, "", child, to, isCustody = true)
        }

        // By time; custody banners before other events at the same minute.
        out.sortWith(compareBy<JSONObject> { minutes(it.getString("time")) }
            .thenBy { if (it.optBoolean("isCustody", false)) 0 else 1 })
        return out
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private fun colorFor(name: String, cfg: Cfg): Long =
        if (name == "Both") 0xFF7E57C2L else (cfg.colorByName[name] ?: 0xFF607D8BL)

    /** "All" → "All", "Henri" → "Henri", "Henri,Chris" → "Henri & Chris". */
    private fun custodyChildLabel(childName: String): String {
        if (childName == "All") return "All"
        val parts = childName.split(",").map { it.trim() }.filter { it.isNotEmpty() }
        if (parts.size <= 1) return childName
        return "${parts.dropLast(1).joinToString(", ")} & ${parts.last()}"
    }

    private fun minutes(hhmm: String): Int {
        val p = hhmm.split(":")
        return (p.getOrNull(0)?.toIntOrNull() ?: 0) * 60 + (p.getOrNull(1)?.toIntOrNull() ?: 0)
    }

    private fun parseDate(s: String?): LocalDate? =
        try { if (s.isNullOrEmpty()) null else LocalDate.parse(s.substring(0, 10)) }
        catch (_: Exception) { null }

    /** True when [rec]'s start_date..end_date (inclusive) covers [date]. */
    private fun covers(rec: JSONObject, date: LocalDate): Boolean {
        val start = parseDate(rec.optString("start_date")) ?: return false
        val end   = parseDate(rec.optString("end_date")) ?: return false
        return !date.isBefore(start) && !date.isAfter(end)
    }

    /** True when [rec] has an end_date and [date] is after it (inclusive end). */
    private fun pastEndDate(rec: JSONObject, date: LocalDate): Boolean {
        val end = parseDate(rec.optString("end_date")) ?: return false
        return date.isAfter(end)
    }

    private fun parseHex(s: String?): Long? {
        if (s == null || !s.startsWith("#") || s.length != 7) return null
        return try { 0xFF000000L or s.substring(1).toLong(16) } catch (_: Exception) { null }
    }

    private fun JSONArray.objects(): List<JSONObject> =
        (0 until length()).map { getJSONObject(it) }

    // ── PocketBase REST ───────────────────────────────────────────────────────

    /** Lists records; throws on any failure so stale data is never written. */
    private fun fetchCollection(
        pbUrl: String, token: String, collection: String, filter: String
    ): JSONArray {
        val query = "?perPage=500&filter=${URLEncoder.encode(filter, "UTF-8")}"
        val conn = URL("$pbUrl/api/collections/$collection/records$query")
            .openConnection() as HttpURLConnection
        conn.setRequestProperty("Authorization", token)
        conn.connectTimeout = 10_000
        conn.readTimeout    = 10_000
        if (conn.responseCode != 200) {
            throw IllegalStateException("HTTP ${conn.responseCode} listing $collection")
        }
        return JSONObject(conn.inputStream.bufferedReader().readText())
            .optJSONArray("items") ?: JSONArray()
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

    // ── Companion ────────────────────────────────────────────────────────────

    companion object {
        const val WORK_NAME = "coplan_periodic_sync"

        private val ISO: DateTimeFormatter = DateTimeFormatter.ISO_LOCAL_DATE
        private val PALETTE = longArrayOf(0xFF1565C0L, 0xFFD81B60L, 0xFF00897BL, 0xFFFF8F00L)

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
