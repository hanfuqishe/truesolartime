package com.realsuntime.solartime.notify

import android.Manifest
import android.annotation.SuppressLint
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.realsuntime.solartime.MainActivity
import com.realsuntime.solartime.R
import com.realsuntime.solartime.data.Place
import com.realsuntime.solartime.ui.TimeText
import com.realsuntime.solartime.solar.Shichen
import com.realsuntime.solartime.solar.SolarTimeMath
import com.realsuntime.solartime.solar.TimeFormat
import java.time.Instant
import kotlin.math.roundToInt

/** 时辰交接提醒：在进入下一个时辰前 5 分钟发出通知。 */
object ShiChenReminder {

    const val CHANNEL_ID = "shichen_boundary"
    const val EXTRA_BOUNDARY_MILLIS = "boundary_millis"

    private const val ALARM_REQUEST_CODE = 4201
    private const val NOTIFICATION_ID = 4201
    private const val LEAD_SECONDS = 300L

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

    /** 高版本系统需用户授予"闹钟和提醒"权限才允许精确定时，否则退化为可延迟的闹钟。 */
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

    @SuppressLint("MissingPermission")
    fun notifyUpcoming(context: Context, place: Place, boundary: Instant) {
        if (!hasNotificationPermission(context)) return
        ensureChannel(context)

        val boundarySeconds = SolarTimeMath.trueSolarSecondsOfDay(boundary, place.longitude)
        val shichenName = TimeText.shichenName(context, Shichen.indexOf(boundarySeconds))
        val minutesLeft = ((boundary.toEpochMilli() - System.currentTimeMillis()) / 60_000.0).roundToInt()
        val title = if (minutesLeft in 1..10) context.getString(R.string.notif_upcoming_title, shichenName) else context.getString(R.string.notif_started_title, shichenName)
        val body = if (minutesLeft in 1..10) {
            context.getString(R.string.notif_upcoming_body, minutesLeft, TimeFormat.clockWithSeconds(toLocalTime(boundarySeconds)))
        } else {
            context.getString(R.string.notif_started_body, TimeFormat.clockWithSeconds(toLocalTime(boundarySeconds)), shichenName)
        }

        val contentIntent = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_sun)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setAutoCancel(true)
            .setContentIntent(contentIntent)
            .build()

        NotificationManagerCompat.from(context).notify(NOTIFICATION_ID, notification)
    }

    private fun toLocalTime(secondsOfDay: Double) = java.time.LocalTime.ofSecondOfDay(
        kotlin.math.floor(secondsOfDay).toLong().coerceIn(0, 86_399),
    )

    private fun hasNotificationPermission(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.POST_NOTIFICATIONS,
            ) == PackageManager.PERMISSION_GRANTED

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, context.getString(R.string.channel_shichen), NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = context.getString(R.string.channel_shichen_desc)
            },
        )
    }
}
