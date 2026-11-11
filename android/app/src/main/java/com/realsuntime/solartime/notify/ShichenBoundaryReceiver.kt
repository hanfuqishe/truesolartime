package com.realsuntime.solartime.notify

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.realsuntime.solartime.data.AppSettings

class ShichenBoundaryReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val settings = AppSettings(context)
        if (!settings.remindersEnabled) return

        ShiChenReminder.chime()
        ShiChenReminder.schedule(context, settings.place)
    }
}
