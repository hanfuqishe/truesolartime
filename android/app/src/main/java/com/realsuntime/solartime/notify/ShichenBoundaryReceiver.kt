package com.realsuntime.solartime.notify

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.realsuntime.solartime.data.AppSettings

class ShichenBoundaryReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val settings = AppSettings(context)
        if (!settings.remindersEnabled) return

        // 与关键时间报时一样，用 goAsync 保住进程直到播放结束，锁屏时也不会被截断。
        val pending = goAsync()
        ShiChenReminder.chime { pending.finish() }
        ShiChenReminder.schedule(context, settings.place)
    }
}
