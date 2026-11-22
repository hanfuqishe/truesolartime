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
        WidgetUpdater.rememberWidgetIds(context, appWidgetIds)
        safeRefresh(context, "onUpdate")
    }

    /** 桌面拖拽改变尺寸后立刻按新宽度重排，避免时钟与日期被裁切。 */
    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        WidgetUpdater.rememberWidgetIds(context, intArrayOf(appWidgetId))
        safeRefresh(context, "onOptionsChanged")
    }

    override fun onEnabled(context: Context) {
        safeRefresh(context, "onEnabled")
        val settings = AppSettings(context)
        if (settings.keyTimeChimeEnabled) {
            KeyTimeChime.schedule(context)
        }
    }

    /**
     * 任何一次刷新都不允许把异常抛回系统：provider 一抛异常，桌面就会把整个小组件
     * 标成「加载失败」，用户连降级版面都看不到。
     */
    private fun safeRefresh(context: Context, from: String) {
        runCatching { WidgetUpdater.refreshAll(context, forceChronometer = true) }
            .onFailure { Log.w(TAG, "refreshAll from $from failed", it) }
    }

    override fun onDisabled(context: Context) {
        WidgetUpdater.cancelTick(context)
        KeyTimeChime.cancel(context)
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        appWidgetIds.forEach(WidgetUpdater::forgetWidget)
        // **故意不清「记录过的 id」**：对一个已解绑的 id 调 updateAppWidget 是无害的（系统直接忽略），
        // 但如果桌面留了幽灵卡片（荣耀实测：删掉 3 张里的 2 张后，系统 `getAppWidgetIds` 返回 0，
        // 屏幕上却还留着一张不再更新的卡片），保留 id 才能让它继续走字。
        // 真正需要清的是每张卡片的缓存（上一行的 forgetWidget）。
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        when (intent.action) {
            WidgetUpdater.ACTION_TICK, WidgetUpdater.ACTION_WATCHDOG -> {
                // 闹钟可能被系统迟到投递，甚至整条链被清掉；这里只管立刻写一遍，
                // 下一次排程由 refreshAll 负责，不依赖任何进程内的延时任务。
                runCatching { WidgetUpdater.refreshAll(context) }
                    .onFailure { Log.w(TAG, "refresh on $intent failed", it) }
            }
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            Intent.ACTION_DATE_CHANGED,
            Intent.ACTION_LOCALE_CHANGED,
            -> safeRefresh(context, "timeChanged")
        }
    }

    private companion object {
        const val TAG = "SolarWidget"
    }
}
