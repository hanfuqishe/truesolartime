package com.realsuntime.solartime.widget

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import com.realsuntime.solartime.data.AppSettings

class SolarWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        WidgetUpdater.refreshAll(context)
    }

    override fun onEnabled(context: Context) {
        WidgetUpdater.refreshAll(context)
        val settings = AppSettings(context)
        if (settings.hourlyChimeEnabled) {
            HourlyChime.schedule(context, settings.place)
        }
    }

    override fun onDisabled(context: Context) {
        WidgetUpdater.cancelTick(context)
        HourlyChime.cancel(context)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        when (intent.action) {
            WidgetUpdater.ACTION_TICK,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            Intent.ACTION_DATE_CHANGED,
            Intent.ACTION_LOCALE_CHANGED,
            -> WidgetUpdater.refreshAll(context)
        }
    }
}
