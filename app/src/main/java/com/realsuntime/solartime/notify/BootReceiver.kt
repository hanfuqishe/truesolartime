package com.realsuntime.solartime.notify

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.realsuntime.solartime.data.AppSettings

/** 重启后 AlarmManager 中的闹钟会丢失，这里重新排程。 */
class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        val settings = AppSettings(context)
        if (settings.remindersEnabled) {
            ShiChenReminder.schedule(context, settings.place)
        }
    }
}
