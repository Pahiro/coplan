package com.coplan.app

import android.content.Context
import androidx.glance.appwidget.GlanceAppWidgetReceiver

class CoplanWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = CoplanWidget()

    override fun onEnabled(context: Context) {
        super.onEnabled(context)
        CoplanSyncWorker.schedule(context)
        CoplanSyncWorker.runOnce(context)
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        CoplanSyncWorker.cancel(context)
    }
}

class CoplanWidget2Receiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = CoplanWidget2()

    override fun onEnabled(context: Context) {
        super.onEnabled(context)
        CoplanSyncWorker.schedule(context)
        CoplanSyncWorker.runOnce(context)
    }
}

class CoplanWidget3Receiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = CoplanWidget3()

    override fun onEnabled(context: Context) {
        super.onEnabled(context)
        CoplanSyncWorker.schedule(context)
        CoplanSyncWorker.runOnce(context)
    }
}
