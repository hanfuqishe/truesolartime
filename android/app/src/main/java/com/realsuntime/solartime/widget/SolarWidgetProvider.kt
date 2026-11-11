package com.realsuntime.solartime.widget

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.util.Log
import com.realsuntime.solartime.data.AppSettings

class SolarWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        // 桌面刚绑定视图，秒数的基准必须重新下发一次。
        WidgetUpdater.refreshAll(context, forceChronometer = true)
    }

    /** 桌面拖拽改变尺寸后立刻按新宽度重排，避免时钟与日期被裁切。 */
    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        WidgetUpdater.refreshAll(context, forceChronometer = true)
    }

    override fun onEnabled(context: Context) {
        WidgetUpdater.refreshAll(context, forceChronometer = true)
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
            WidgetUpdater.ACTION_TICK, WidgetUpdater.ACTION_WATCHDOG -> {
                // 闹钟可能被系统迟到投递，甚至整条链被清掉；这里只管立刻写一遍，
                // 下一次排程由 refreshAll 负责，不依赖任何进程内的延时任务。
                runCatching { WidgetUpdater.refreshAll(context) }
                    .onFailure { Log.w("SolarWidget", "refresh on $intent failed", it) }
            }
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            Intent.ACTION_DATE_CHANGED,
            Intent.ACTION_LOCALE_CHANGED,
            -> WidgetUpdater.refreshAll(context, forceChronometer = true)
        }
    }
}
