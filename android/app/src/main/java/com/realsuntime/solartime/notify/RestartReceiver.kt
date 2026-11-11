package com.realsuntime.solartime.notify

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.realsuntime.solartime.data.AppSettings
import com.realsuntime.solartime.widget.KeyTimeChime
import com.realsuntime.solartime.widget.WidgetUpdater

/**
 * 开机或应用升级后 AlarmManager 里排好的闹钟都会被清空，这里重新排程。
 *
 * 升级完往往没人打开应用，若不在这里补排，小组件会一直停在升级前的时刻
 * （只有系统的定时刷新最晚 30 分钟后才把它拉回来），报时也要等下次开机。
 */
class RestartReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED -> Unit
            else -> return
        }
        val settings = AppSettings(context)
        if (settings.remindersEnabled) {
            ShiChenReminder.schedule(context, settings.place)
        }
        if (settings.keyTimeChimeEnabled) {
            KeyTimeChime.schedule(context)
        }
        WidgetUpdater.refreshAll(context, forceChronometer = true)
    }
}
