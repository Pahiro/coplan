package com.coplan.app

import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.*
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.appWidgetBackground
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.layout.*
import androidx.glance.text.*
import androidx.glance.unit.ColorProvider
import org.json.JSONArray
import org.json.JSONObject

// ── Three concrete widget classes (one per style) ────────────────────────────

/** Style 1 — Sleek Minimalist (dark #121212, accent bar + time column) */
class CoplanWidget  : CoplanWidgetBase() { override val widgetStyle = 1 }

/** Style 2 — Modern Material (dark #1E1E1E, rounded date token, dividers) */
class CoplanWidget2 : CoplanWidgetBase() { override val widgetStyle = 2 }

/** Style 3 — Edge-to-Edge Timeline (adaptive bg, node + connecting line) */
class CoplanWidget3 : CoplanWidgetBase() { override val widgetStyle = 3 }

// ── Abstract base — all rendering and parsing logic lives here ────────────────

abstract class CoplanWidgetBase : GlanceAppWidget() {

    /** Determines which visual style is rendered. Override in each subclass. */
    protected abstract val widgetStyle: Int

    override val sizeMode = SizeMode.Responsive(
        setOf(DpSize(180.dp, 110.dp), DpSize(270.dp, 110.dp))
    )

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent { WidgetContent(context) }
    }

    // ── Root dispatcher ───────────────────────────────────────────────────────

    @Composable
    private fun WidgetContent(context: Context) {
        val prefs: SharedPreferences =
            context.getSharedPreferences("HomeWidgetPlugin", Context.MODE_PRIVATE)
        val json   = prefs.getString("coplan_widget_events", "[]") ?: "[]"
        val events = parseEvents(json)

        when (widgetStyle) {
            2    -> Style2Content(context, events)
            3    -> Style3Content(context, events)
            else -> Style1Content(context, events)
        }
    }

    // ── Shared colour helpers ─────────────────────────────────────────────────

    private fun accentColor(parent: String): Color =
        if (parent == "Bennet") Color(0xFF64B5F6) else Color(0xFFF48FB1)

    private fun buildSubtitle(event: WidgetEvent): String {
        val parts = mutableListOf<String>()
        if (event.parent.isNotEmpty()) parts += event.parent
        if (event.childName.isNotEmpty() && event.childName != "All") parts += event.childName
        return parts.joinToString(" · ")
    }

    // ── Style 1 — Sleek Minimalist ────────────────────────────────────────────
    //
    // Dark #121212 bg. Each event: 4 dp coloured accent bar on the left,
    // then a narrow time+day column, then activity title + subtitle.

    @Composable
    private fun Style1Content(context: Context, events: List<WidgetEvent>) {
        Box(
            modifier = GlanceModifier
                .fillMaxSize()
                .appWidgetBackground()
                .background(ColorProvider(Color(0xFF121212)))
                .padding(12.dp)
                .cornerRadius(16.dp)
                .clickable(actionStartActivity(Intent(context, MainActivity::class.java)))
        ) {
            if (events.isEmpty()) {
                Text(
                    "No upcoming events",
                    style = TextStyle(color = ColorProvider(Color(0xFF9E9E9E)), fontSize = 13.sp)
                )
            } else {
                Column(modifier = GlanceModifier.fillMaxSize()) {
                    events.forEachIndexed { i, event ->
                        if (i > 0) Spacer(GlanceModifier.height(8.dp))
                        Style1Row(event)
                    }
                }
            }
        }
    }

    @Composable
    private fun Style1Row(event: WidgetEvent) {
        val accent    = if (event.isLogistics) Color(0xFF616161) else accentColor(event.parent)
        val textColor = if (event.isLogistics) Color(0xFF757575) else Color(0xFFEEEEEE)
        val subColor  = Color(0xFF757575)
        Row(
            modifier = GlanceModifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically
        ) {
            // Coloured 4 dp vertical accent bar
            Box(
                modifier = GlanceModifier
                    .width(4.dp)
                    .height(36.dp)
                    .background(ColorProvider(accent))
                    .cornerRadius(2.dp)
            ) {}
            Spacer(GlanceModifier.width(10.dp))
            // Narrow time + day-abbr column
            Column(
                modifier = GlanceModifier.width(38.dp),
                horizontalAlignment = Alignment.Horizontal.CenterHorizontally
            ) {
                Text(
                    event.time,
                    style = TextStyle(
                        color = ColorProvider(accent),
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Bold
                    )
                )
                if (event.dayAbbr.isNotEmpty()) {
                    Text(
                        event.dayAbbr,
                        style = TextStyle(
                            color = ColorProvider(subColor),
                            fontSize = 9.sp
                        )
                    )
                }
            }
            Spacer(GlanceModifier.width(10.dp))
            // Activity title + subtitle
            Column(modifier = GlanceModifier.defaultWeight()) {
                Text(
                    event.activity,
                    maxLines = 1,
                    style = TextStyle(
                        color = ColorProvider(textColor),
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Bold
                    )
                )
                val sub = buildSubtitle(event)
                if (sub.isNotEmpty()) {
                    Text(
                        sub,
                        maxLines = 1,
                        style = TextStyle(
                            color = ColorProvider(subColor),
                            fontSize = 10.sp
                        )
                    )
                }
            }
        }
    }

    // ── Style 2 — Modern Material ─────────────────────────────────────────────
    //
    // Dark #1E1E1E bg. Each event: rounded square date token on left (parent
    // colour at low opacity), activity + subtitle on right. Hairline dividers.

    @Composable
    private fun Style2Content(context: Context, events: List<WidgetEvent>) {
        Column(
            modifier = GlanceModifier
                .fillMaxSize()
                .appWidgetBackground()
                .background(ColorProvider(Color(0xFF1E1E1E)))
                .padding(10.dp)
                .cornerRadius(16.dp)
                .clickable(actionStartActivity(Intent(context, MainActivity::class.java)))
        ) {
            if (events.isEmpty()) {
                Text(
                    "No upcoming events",
                    style = TextStyle(color = ColorProvider(Color(0xFF9E9E9E)), fontSize = 13.sp)
                )
            } else {
                events.forEachIndexed { i, event ->
                    if (i > 0) {
                        Box(
                            modifier = GlanceModifier
                                .fillMaxWidth()
                                .height(1.dp)
                                .background(ColorProvider(Color(0xFF303030)))
                        ) {}
                    }
                    Style2Row(event)
                }
            }
        }
    }

    @Composable
    private fun Style2Row(event: WidgetEvent) {
        val isBennet  = event.parent == "Bennet"
        val baseColor = if (event.isLogistics) Color(0xFF424242)
                        else if (isBennet) Color(0xFF1565C0) else Color(0xFFD81B60)
        val tokenBg   = baseColor.copy(alpha = 0.20f)
        val tokenText = if (event.isLogistics) Color(0xFF757575)
                        else if (isBennet) Color(0xFF90CAF9) else Color(0xFFF48FB1)
        val textColor = if (event.isLogistics) Color(0xFF757575) else Color(0xFFEEEEEE)

        Row(
            modifier = GlanceModifier.fillMaxWidth().padding(vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Box(
                modifier = GlanceModifier
                    .width(52.dp)
                    .height(48.dp)
                    .background(ColorProvider(tokenBg))
                    .cornerRadius(10.dp),
                contentAlignment = Alignment.Center
            ) {
                Column(horizontalAlignment = Alignment.Horizontal.CenterHorizontally) {
                    if (event.dayAbbr.isNotEmpty()) {
                        Text(
                            event.dayAbbr,
                            style = TextStyle(
                                color = ColorProvider(tokenText),
                                fontSize = 8.sp,
                                fontWeight = FontWeight.Bold
                            )
                        )
                    }
                    Text(
                        event.time,
                        style = TextStyle(
                            color = ColorProvider(tokenText),
                            fontSize = 12.sp,
                            fontWeight = FontWeight.Bold
                        )
                    )
                }
            }
            Spacer(GlanceModifier.width(10.dp))
            Column(modifier = GlanceModifier.defaultWeight()) {
                Text(
                    event.activity,
                    maxLines = 1,
                    style = TextStyle(
                        color = ColorProvider(textColor),
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Bold
                    )
                )
                val sub = buildSubtitle(event)
                if (sub.isNotEmpty()) {
                    Text(
                        sub,
                        maxLines = 1,
                        style = TextStyle(
                            color = ColorProvider(Color(0xFF9E9E9E)),
                            fontSize = 10.sp
                        )
                    )
                }
            }
        }
    }

    // ── Style 3 — Edge-to-Edge Timeline ──────────────────────────────────────
    //
    // Adaptive bg. Left: day + time. Centre: circle node + connecting line.
    // Right: activity + subtitle.

    @Composable
    private fun Style3Content(context: Context, events: List<WidgetEvent>) {
        Box(
            modifier = GlanceModifier
                .fillMaxSize()
                .appWidgetBackground()
                .background(GlanceTheme.colors.background)
                .padding(horizontal = 10.dp, vertical = 8.dp)
                .cornerRadius(16.dp)
                .clickable(actionStartActivity(Intent(context, MainActivity::class.java)))
        ) {
            if (events.isEmpty()) {
                Text(
                    "No upcoming events",
                    style = TextStyle(color = ColorProvider(Color(0xFF9E9E9E)), fontSize = 13.sp)
                )
            } else {
                Column(modifier = GlanceModifier.fillMaxSize()) {
                    events.forEachIndexed { i, event ->
                        Style3Row(event, showLine = i < events.size - 1)
                    }
                }
            }
        }
    }

    @Composable
    private fun Style3Row(event: WidgetEvent, showLine: Boolean) {
        val accent    = if (event.isLogistics) Color(0xFF616161) else accentColor(event.parent)
        val textColor = if (event.isLogistics) Color(0xFF757575) else null
        Row(
            modifier = GlanceModifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically
        ) {
            // Left: day abbr + time
            Column(
                modifier = GlanceModifier.width(44.dp),
                horizontalAlignment = Alignment.Horizontal.End
            ) {
                if (event.dayAbbr.isNotEmpty()) {
                    Text(
                        event.dayAbbr,
                        style = TextStyle(
                            color = GlanceTheme.colors.onSurface,
                            fontSize = 9.sp,
                            fontWeight = FontWeight.Bold
                        )
                    )
                }
                Text(
                    event.time,
                    style = TextStyle(
                        color = ColorProvider(accent),
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Bold
                    )
                )
            }
            Spacer(GlanceModifier.width(6.dp))
            // Centre: node + connecting line
            Column(
                modifier = GlanceModifier.width(14.dp),
                horizontalAlignment = Alignment.Horizontal.CenterHorizontally
            ) {
                Box(
                    modifier = GlanceModifier
                        .width(8.dp)
                        .height(8.dp)
                        .background(ColorProvider(accent))
                        .cornerRadius(4.dp)
                ) {}
                if (showLine) {
                    Spacer(GlanceModifier.height(2.dp))
                    Box(
                        modifier = GlanceModifier
                            .width(2.dp)
                            .height(20.dp)
                            .background(ColorProvider(Color(0xFF424242)))
                    ) {}
                }
            }
            Spacer(GlanceModifier.width(8.dp))
            // Right: activity + subtitle
            Column(modifier = GlanceModifier.defaultWeight()) {
                Text(
                    event.activity,
                    maxLines = 1,
                    style = TextStyle(
                        color = if (textColor != null) ColorProvider(textColor)
                                else GlanceTheme.colors.onSurface,
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Bold
                    )
                )
                val sub = buildSubtitle(event)
                if (sub.isNotEmpty()) {
                    Text(
                        sub,
                        maxLines = 1,
                        style = TextStyle(
                            color = ColorProvider(Color(0xFF9E9E9E)),
                            fontSize = 10.sp
                        )
                    )
                }
            }
        }
    }

    // ── Event parsing ─────────────────────────────────────────────────────────

    private fun parseEvents(json: String): List<WidgetEvent> =
        runCatching {
            val arr = JSONArray(json)
            (0 until arr.length()).map { i ->
                val o       = arr.getJSONObject(i)
                val dateStr = o.optString("date", "")
                val dayAbbr = runCatching {
                    val today    = java.time.LocalDate.now()
                    val tomorrow = today.plusDays(1)
                    val date     = java.time.LocalDate.parse(dateStr)
                    when (date) {
                        today    -> "Today"
                        tomorrow -> "Tmrw"
                        else     -> date.dayOfWeek.getDisplayName(
                            java.time.format.TextStyle.SHORT,
                            java.util.Locale.getDefault()
                        )
                    }
                }.getOrElse { "" }

                WidgetEvent(
                    dayAbbr      = dayAbbr,
                    time         = o.optString("time", ""),
                    activity     = o.optString("activity", ""),
                    location     = o.optString("location", ""),
                    childName    = o.optString("childName", ""),
                    parent       = o.optString("parent", ""),
                    isLogistics  = o.optBoolean("isLogistics", false)
                )
            }
        }.getOrElse { emptyList() }
}

data class WidgetEvent(
    val dayAbbr: String,
    val time: String,
    val activity: String,
    val location: String,
    val childName: String,
    val parent: String,
    val isLogistics: Boolean = false
)
