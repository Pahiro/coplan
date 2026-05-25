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
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.LocalTime
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.concurrent.TimeUnit

/**
 * Periodic background worker (every 15 min, network required).
 *
 * What it does each run:
 *  1. Reads the PocketBase auth token + URL from Flutter's SharedPreferences.
 *  2. Fetches base rules + overrides for the next 3 days from PocketBase.
 *  3. Runs the same 3-tier resolution logic as the Dart engine.
 *  4. Writes the resolved events to HomeWidgetPlugin prefs and updates the widget.
 *  5. Polls for new pickup requests addressed to the current user and fires
 *     a local notification if any appear that haven't been notified before.
 */
class CoplanSyncWorker(
    private val ctx: Context,
    params: WorkerParameters
) : CoroutineWorker(ctx, params) {

    // Flutter's shared_preferences stores keys with the "flutter." prefix
    private val flutterPrefs by lazy {
        ctx.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
    }
    // Kotlin-only state (seen request IDs, etc.)
    private val workerPrefs by lazy {
        ctx.getSharedPreferences("CoplanWorkerPrefs", Context.MODE_PRIVATE)
    }
    // home_widget reads events from this file
    private val widgetPrefs by lazy {
        ctx.getSharedPreferences("HomeWidgetPlugin", Context.MODE_PRIVATE)
    }

    // ── Entry point ──────────────────────────────────────────────────────────

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        try {
            val authStr = flutterPrefs.getString("flutter.pb_auth", null)
                ?: return@withContext Result.success() // not logged in

            val auth  = JSONObject(authStr)
            val token = auth.optString("token").takeIf { it.isNotEmpty() }
                ?: return@withContext Result.success()

            val model  = auth.optJSONObject("model") ?: auth.optJSONObject("record")
            val myId   = model?.optString("id") ?: ""

            val pbUrl  = flutterPrefs.getString("flutter.pb_url", "http://localhost:8090")
                ?.trimEnd('/') ?: "http://localhost:8090"
            val anchor = LocalDate.parse(
                flutterPrefs.getString("flutter.rotation_anchor", "2026-05-18")
                    ?: "2026-05-18"
            )

            // ── 1. Resolve schedule for next 3 days ──────────────────────
            val rules         = fetchCollection(pbUrl, token, "rules_base")
            val weekdayRules  = fetchCollection(pbUrl, token, "custody_weekday_rules",
                filter = "active=true")
            val today   = LocalDate.now()
            val allEvents = mutableListOf<JSONObject>()

            repeat(3) { i ->
                val date    = today.plusDays(i.toLong())
                val dateStr = date.format(DateTimeFormatter.ISO_LOCAL_DATE)
                val overrides = fetchCollection(
                    pbUrl, token, "manual_overrides",
                    filter = "target_date='$dateStr'"
                )
                val custodyRequests = fetchCollection(
                    pbUrl, token, "custody_requests",
                    filter = "date='$dateStr'&&status='accepted'"
                )
                allEvents += resolveDay(date, rules, overrides, weekdayRules, anchor, custodyRequests)
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

            // ── 2. Update all widget styles ──────────────────────────────
            widgetPrefs.edit().putString("coplan_widget_events", upcoming.toString()).apply()
            val manager = GlanceAppWidgetManager(ctx)
            manager.getGlanceIds(CoplanWidget::class.java)
                .forEach { id -> CoplanWidget().update(ctx, id) }
            manager.getGlanceIds(CoplanWidget2::class.java)
                .forEach { id -> CoplanWidget2().update(ctx, id) }
            manager.getGlanceIds(CoplanWidget3::class.java)
                .forEach { id -> CoplanWidget3().update(ctx, id) }

            // ── 3. Notify for new pickup requests ────────────────────────
            if (myId.isNotEmpty()) notifyNewRequests(pbUrl, token, myId)

            Result.success()
        } catch (_: Exception) {
            Result.retry()
        }
    }

    // ── Schedule resolution (mirrors Dart ResolutionEngine) ──────────────────

    private fun resolveDay(
        date: LocalDate,
        rules: JSONArray,
        overrides: JSONArray,
        weekdayRules: JSONArray,
        anchor: LocalDate,
        custodyRequests: JSONArray = JSONArray()
    ): List<JSONObject> {
        val dow     = date.dayOfWeek.value   // ISO: 1=Mon … 7=Sun
        val results = mutableListOf<JSONObject>()

        for (i in 0 until rules.length()) {
            val rule = rules.getJSONObject(i)
            if (rule.optInt("day_of_week") != dow) continue

            val childName = rule.optString("child_name", "All")
            val time      = rule.optString("event_time", "08:00")
            val activity  = rule.optString("activity", "")
            val location  = rule.optString("location", "")

            // Priority 1 — non-adhoc manual override only
            // Adhoc overrides are standalone one-off events, not parent substitutions —
            // mirroring Dart's _resolveRule which filters with !o.isAdhoc.
            var parent: String? = null
            for (j in 0 until overrides.length()) {
                val ov       = overrides.getJSONObject(j)
                val ovReason = ov.optString("reason")
                val ovAdhoc  = ov.optBoolean("is_adhoc", false) || ovReason.isNotEmpty()
                if (ovAdhoc) continue
                val ovChild  = ov.optString("child_name", "All")
                if (ovChild == childName || ovChild == "All") {
                    parent = ov.optString("assigned_parent")
                    break
                }
            }

            // Priority 2 — recurring weekday rule (from custody_weekday_rules)
            if (parent == null) {
                val dow = date.dayOfWeek.value // ISO: 1=Mon … 7=Sun
                for (j in 0 until weekdayRules.length()) {
                    val wr = weekdayRules.getJSONObject(j)
                    if (wr.optInt("day_of_week") == dow) {
                        parent = wr.optString("assigned_parent").takeIf { it.isNotEmpty() }
                        break
                    }
                }
            }

            // Priority 3 — base rotation (even weeks = Bennet, from anchor Monday)
            if (parent == null) {
                val monday       = date.with(DayOfWeek.MONDAY)
                val anchorMonday = anchor.with(DayOfWeek.MONDAY)
                val weeks        = ChronoUnit.WEEKS.between(anchorMonday, monday)
                parent           = if (weeks % 2 == 0L) "Bennet" else "Jana"
            }

            // Priority 4 — accepted custody request (mirrors Dart parentAtTime)
            // A window or day-transfer may hand responsibility to the other parent
            // at or after the event time, exactly as ResolutionEngine does in Dart.
            val eventMin = run {
                val parts = time.split(":")
                (parts[0].toIntOrNull() ?: 0) * 60 + (parts[1].toIntOrNull() ?: 0)
            }
            var custodyParent: String? = null
            // Check windows first (pickup ≤ event < return)
            for (k in 0 until custodyRequests.length()) {
                val r      = custodyRequests.getJSONObject(k)
                val rt     = r.optString("return_time").takeIf { it.isNotEmpty() }
                val rtTbd  = r.optBoolean("return_time_tbd", false)
                if (rt == null && !rtTbd) continue   // day transfer — skip here
                val pParts    = r.optString("pickup_time", "00:00").split(":")
                val pickupMin = (pParts[0].toIntOrNull() ?: 0) * 60 + (pParts[1].toIntOrNull() ?: 0)
                val returnMin = if (rtTbd || rt == null) 24 * 60 else {
                    val rp = rt.split(":")
                    (rp[0].toIntOrNull() ?: 0) * 60 + (rp[1].toIntOrNull() ?: 0)
                }
                if (eventMin >= pickupMin && eventMin < returnMin) {
                    custodyParent = r.optString("to_parent").takeIf { it.isNotEmpty() }
                    break
                }
            }
            // Then day transfers (event time ≥ pickup time → to_parent takes over)
            if (custodyParent == null) {
                for (k in 0 until custodyRequests.length()) {
                    val r     = custodyRequests.getJSONObject(k)
                    val rt    = r.optString("return_time").takeIf { it.isNotEmpty() }
                    val rtTbd = r.optBoolean("return_time_tbd", false)
                    if (rt != null || rtTbd) continue  // window — already handled
                    val pParts    = r.optString("pickup_time", "00:00").split(":")
                    val pickupMin = (pParts[0].toIntOrNull() ?: 0) * 60 + (pParts[1].toIntOrNull() ?: 0)
                    if (eventMin >= pickupMin) {
                        custodyParent = r.optString("to_parent").takeIf { it.isNotEmpty() }
                        break
                    }
                }
            }
            val finalParent = custodyParent ?: parent!!

            results += JSONObject().apply {
                put("date",            date.format(DateTimeFormatter.ISO_LOCAL_DATE))
                put("time",            time)
                put("activity",        activity)
                put("location",        location)
                put("childName",       childName)
                put("parent",          finalParent)
                put("parentColorValue",
                    if (finalParent == "Bennet") 0xFF1565C0.toLong()
                    else                         0xFFD81B60.toLong()
                )
            }
        }

        // ── Ad-hoc one-off events ─────────────────────────────────────────
        // These are standalone events not tied to any base rule — they come
        // from the "One-off event" form on the calendar screen.
        //
        // PocketBase may silently drop the `is_adhoc` field if it isn't in
        // the collection schema.  Use a reliable fallback: createSharedEvent()
        // always writes a non-empty `reason` field, so treat any override with
        // a non-empty reason as an ad-hoc event.
        for (j in 0 until overrides.length()) {
            val ov     = overrides.getJSONObject(j)
            val reason = ov.optString("reason")
            val isAdhoc = ov.optBoolean("is_adhoc", false) || reason.isNotEmpty()
            if (!isAdhoc) continue

            // Prefer the explicit assigned_parent; fall back to weekday rule / rotation.
            var parent: String? = ov.optString("assigned_parent").takeIf { it.isNotEmpty() }
            if (parent == null) {
                for (k in 0 until weekdayRules.length()) {
                    val wr = weekdayRules.getJSONObject(k)
                    if (wr.optInt("day_of_week") == dow) {
                        parent = wr.optString("assigned_parent").takeIf { it.isNotEmpty() }
                        break
                    }
                }
            }
            if (parent == null) {
                val monday       = date.with(DayOfWeek.MONDAY)
                val anchorMonday = anchor.with(DayOfWeek.MONDAY)
                val weeks        = ChronoUnit.WEEKS.between(anchorMonday, monday)
                parent           = if (weeks % 2 == 0L) "Bennet" else "Jana"
            }

            // `reason` is a required schema field that createSharedEvent() always
            // mirrors the activity name into.  Prefer `activity` if present
            // (it may not be in the schema), otherwise fall back to `reason`.
            val activity = ov.optString("activity").ifEmpty { reason }

            results += JSONObject().apply {
                put("date",     date.format(DateTimeFormatter.ISO_LOCAL_DATE))
                put("time",     ov.optString("override_time", "09:00"))
                put("activity", activity)
                put("location", ov.optString("location", ""))
                put("childName", ov.optString("child_name", "All"))
                put("parent",   parent)
                put("parentColorValue",
                    if (parent == "Bennet") 0xFF1565C0.toLong()
                    else                    0xFFD81B60.toLong()
                )
            }
        }

        // ── Accepted custody-request events ──────────────────────────────────
        // Each accepted request produces a banner event identical to what the
        // Dart ResolutionEngine emits (e.g. "Bennet has Henri" or
        // "Bennet has Henri · 16:00–18:00" for a windowed transfer).
        for (j in 0 until custodyRequests.length()) {
            val r            = custodyRequests.getJSONObject(j)
            val toParent     = r.optString("to_parent")
            if (toParent.isEmpty()) continue
            val childName    = r.optString("child_name", "All")
            val pickupTime   = r.optString("pickup_time", "08:00")
            val returnTime   = r.optString("return_time").takeIf { it.isNotEmpty() }
            val returnTbd    = r.optBoolean("return_time_tbd", false)
            val isDayTransfer = returnTime == null && !returnTbd

            val label = if (isDayTransfer)
                "$toParent has $childName"
            else {
                val end = if (returnTbd) "TBD" else (returnTime ?: "TBD")
                "$toParent has $childName · $pickupTime–$end"
            }

            results += JSONObject().apply {
                put("date",            date.format(DateTimeFormatter.ISO_LOCAL_DATE))
                put("time",            pickupTime)
                put("activity",        label)
                put("location",        "")
                put("childName",       childName)
                put("parent",          toParent)
                put("parentColorValue",
                    if (toParent == "Bennet") 0xFF1565C0.toLong()
                    else                      0xFFD81B60.toLong()
                )
                put("isCustody",       true)
            }
        }

        // Sort by time; tie-break: custody banners sort before other events at the
        // same minute (mirrors Dart ResolutionEngine sort with custody-first tie-break).
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

    // ── Pickup request notification ──────────────────────────────────────────

    private fun notifyNewRequests(pbUrl: String, token: String, myId: String) {
        val pending = fetchCollection(
            pbUrl, token, "pickup_requests",
            filter = "status='pending'&&requested_from='$myId'"
        )
        if (pending.length() == 0) return

        // Compare with IDs we already notified about
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
                    val date  = r.optString("target_date", "an upcoming date")
                    firstBody = "Your co-parent requests you handle $child on $date"
                }
            }
        }

        if (newIds.isEmpty()) return

        // Persist all current pending IDs as "seen" so we don't re-fire next cycle
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

    // ── PocketBase REST helper ────────────────────────────────────────────────

    private fun fetchCollection(
        pbUrl: String,
        token: String,
        collection: String,
        filter: String = ""
    ): JSONArray {
        val query = if (filter.isNotEmpty())
            "?filter=${URLEncoder.encode(filter, "UTF-8")}&perPage=200"
        else "?perPage=200"

        val conn = URL("$pbUrl/api/collections/$collection/records$query")
            .openConnection() as HttpURLConnection
        conn.setRequestProperty("Authorization", token)
        conn.connectTimeout = 10_000
        conn.readTimeout    = 10_000
        return JSONObject(conn.inputStream.bufferedReader().readText())
            .optJSONArray("items") ?: JSONArray()
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
    }
}
