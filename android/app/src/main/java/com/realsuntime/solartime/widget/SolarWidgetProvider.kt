package com.realsuntime.solartime.widget

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.os.Bundle
import com.realsuntime.solartime.data.AppSettings

class SolarWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        WidgetUpdater.refreshAll(context)
    }

    /** 桌面拖拽改变尺寸后立刻按新宽度重排，避免时钟与日期被裁切。 */
    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        WidgetUpdater.refreshAll(context)
    }

    override fun onEnabled(context: Context) {
        WidgetUpdater.refreshAll(context)
        val settings = AppSettings(context)
        if (settings.keyTimeChimeEnabled) {
            KeyTimeChime.schedule(context)
        }
    }

    override fun onDisabled(context: Context) {
        WidgetUpdater.cancelTick(context)
        KeyTimeChime.cancel(context)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        when (intent.action) {
            WidgetUpdater.ACTION_TICK -> {
                // 闹钟提前醒来，等真正的整分边界再刷新；goAsync 保住广播不被提前回收。
                val pending = goAsync()
                WidgetUpdater.refreshAtTick(
                    context = context,
                    atMillis = intent.getLongExtra(WidgetUpdater.EXTRA_TICK_AT, 0L),
                    onDone = { pending.finish() },
                )
            }
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            Intent.ACTION_DATE_CHANGED,
            Intent.ACTION_LOCALE_CHANGED,
            -> WidgetUpdater.refreshAll(context)
        }
    }
}
