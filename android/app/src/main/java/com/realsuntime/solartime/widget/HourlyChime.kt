package com.realsuntime.solartime.widget

import android.Manifest
import android.annotation.SuppressLint
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.realsuntime.solartime.MainActivity
import com.realsuntime.solartime.R
import com.realsuntime.solartime.data.AppSettings
import com.realsuntime.solartime.data.Place
import com.realsuntime.solartime.ui.TimeText
import com.realsuntime.solartime.solar.Shichen
import com.realsuntime.solartime.solar.SolarTimeMath
import java.time.Instant
import kotlin.math.roundToLong

/** 真太阳时整点报时：每到真太阳时的整点发一条带提示音的通知。 */
object HourlyChime {

    const val CHANNEL_ID = "hourly_chime"
    private const val REQUEST_CODE = 7302
    private const val NOTIFICATION_ID = 7302

    /** 下一个真太阳时整点。 */
    fun nextBoundary(place: Place, now: Instant): Instant {
        val seconds = SolarTimeMath.trueSolarSecondsOfDay(now, place.longitude)
        val remaining = 3600.0 - seconds % 3600.0
        return now.plusMillis((remaining * 1000).roundToLong())
    }

    fun schedule(context: Context, place: Place) {
        val manager = context.getSystemService(AlarmManager::class.java) ?: return
        val trigger = nextBoundary(place, Instant.now())
        val intent = Intent(context, HourlyChimeReceiver::class.java)
            .putExtra(HourlyChimeReceiver.EXTRA_BOUNDARY_MILLIS, trigger.toEpochMilli())
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            REQUEST_CODE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        if (canScheduleExact(manager)) {
            manager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, trigger.toEpochMilli(), pendingIntent)
        } else {
            manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, trigger.toEpochMilli(), pendingIntent)
        }
    }

    fun cancel(context: Context) {
        val manager = context.getSystemService(AlarmManager::class.java) ?: return
        manager.cancel(
            PendingIntent.getBroadcast(
                context,
                REQUEST_CODE,
                Intent(context, HourlyChimeReceiver::class.java),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            ),
        )
    }

    @SuppressLint("MissingPermission")
    fun chime(context: Context, place: Place, boundary: Instant) {
        if (!hasNotificationPermission(context)) return
        ensureChannel(context)

        val trueSolarSeconds = SolarTimeMath.trueSolarSecondsOfDay(boundary, place.longitude)
        val total = trueSolarSeconds.toLong().coerceIn(0, 86_399)
        val hour = total / 3600
        val shichenName = TimeText.shichenName(context, Shichen.indexOf(trueSolarSeconds))
        val body = context.getString(R.string.chime_body, "%02d:00".format(hour), shichenName)

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
            .setContentTitle(context.getString(R.string.chime_title_notif))
            .setContentText(body)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setAutoCancel(true)
            .setContentIntent(contentIntent)
            .build()

        NotificationManagerCompat.from(context).notify(NOTIFICATION_ID, notification)
    }

    private fun canScheduleExact(manager: AlarmManager): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S || manager.canScheduleExactAlarms()

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
            NotificationChannel(CHANNEL_ID, context.getString(R.string.channel_chime), NotificationManager.IMPORTANCE_HIGH).apply {
                description = context.getString(R.string.channel_chime_desc)
            },
        )
    }
}

class HourlyChimeReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val settings = AppSettings(context)
        if (!settings.hourlyChimeEnabled) return

        val place = settings.place
        val boundaryMillis = intent.getLongExtra(EXTRA_BOUNDARY_MILLIS, 0L)
        val boundary = if (boundaryMillis > 0L) Instant.ofEpochMilli(boundaryMillis) else Instant.now()

        HourlyChime.chime(context, place, boundary)
        HourlyChime.schedule(context, place)
    }

    companion object {
        const val EXTRA_BOUNDARY_MILLIS = "boundary_millis"
    }
}
