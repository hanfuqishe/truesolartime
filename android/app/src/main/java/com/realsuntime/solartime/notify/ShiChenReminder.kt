package com.realsuntime.solartime.notify

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import com.realsuntime.solartime.data.Place
import com.realsuntime.solartime.solar.Shichen
import com.realsuntime.solartime.widget.Chime
import java.time.Instant

/**
 * 时辰交接提醒：在进入下一个时辰前 5 分钟蜂鸣一声（250 ms）。
 *
 * 只播提示音，不发通知 —— 提醒是瞬时事件，不该在通知栏留下条目。
 */
object ShiChenReminder {

    const val EXTRA_BOUNDARY_MILLIS = "boundary_millis"

    private const val ALARM_REQUEST_CODE = 4201
    private const val LEAD_SECONDS = 300L

    /** 时辰交接的提示音比关键时间报时更短，便于区分两种提醒。 */
    internal const val BEEP_MILLIS = 250

    fun nextTrigger(place: Place, now: Instant): Instant {
        val boundary = Shichen.nextBoundary(now.plusSeconds(LEAD_SECONDS + 1), place.longitude)
        return boundary.minusSeconds(LEAD_SECONDS)
    }

    fun schedule(context: Context, place: Place) {
        val alarmManager = context.getSystemService(AlarmManager::class.java) ?: return
        val trigger = nextTrigger(place, Instant.now())
        val intent = Intent(context, ShichenBoundaryReceiver::class.java)
            .putExtra(EXTRA_BOUNDARY_MILLIS, trigger.plusSeconds(LEAD_SECONDS).toEpochMilli())
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            ALARM_REQUEST_CODE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        if (canScheduleExact(alarmManager)) {
            alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, trigger.toEpochMilli(), pendingIntent)
        } else {
            alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, trigger.toEpochMilli(), pendingIntent)
        }
    }

    /** 高版本系统需用户授予「闹钟和提醒」权限才允许精确定时，否则退化为可延迟的闹钟。 */
    private fun canScheduleExact(alarmManager: AlarmManager): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarmManager.canScheduleExactAlarms()

    fun cancel(context: Context) {
        val alarmManager = context.getSystemService(AlarmManager::class.java) ?: return
        alarmManager.cancel(
            PendingIntent.getBroadcast(
                context,
                ALARM_REQUEST_CODE,
                Intent(context, ShichenBoundaryReceiver::class.java),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            ),
        )
    }

    /** 蜂鸣提醒：进入下一个时辰的 5 分钟前响一声。 */
    fun chime() {
        Chime.beep(BEEP_MILLIS)
    }
}
