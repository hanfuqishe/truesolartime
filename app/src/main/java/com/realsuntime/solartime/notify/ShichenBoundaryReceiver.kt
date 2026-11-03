package com.realsuntime.solartime.notify

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.realsuntime.solartime.data.AppSettings
import java.time.Instant

class ShichenBoundaryReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val settings = AppSettings(context)
        if (!settings.remindersEnabled) return

        val place = settings.place
        val boundaryMillis = intent.getLongExtra(ShiChenReminder.EXTRA_BOUNDARY_MILLIS, 0L)
        val boundary = if (boundaryMillis > 0L) {
            Instant.ofEpochMilli(boundaryMillis)
        } else {
            ShiChenReminder.nextTrigger(place, Instant.now()).plusSeconds(300)
        }

        ShiChenReminder.notifyUpcoming(context, place, boundary)
        ShiChenReminder.schedule(context, place)
    }
}
