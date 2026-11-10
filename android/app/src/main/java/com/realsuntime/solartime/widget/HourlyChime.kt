package com.realsuntime.solartime.widget

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.Ringtone
import android.media.RingtoneManager
import android.media.ToneGenerator
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.realsuntime.solartime.data.AppSettings
import com.realsuntime.solartime.data.Place
import com.realsuntime.solartime.solar.SolarTimeMath
import java.time.Instant
import kotlin.math.roundToLong

/**
 * 真太阳时整点报时：每到真太阳时整点「嘀」一声。
 *
 * 只播提示音，不发通知 —— 报时是瞬时提醒，不该在通知栏留下条目。
 */
object HourlyChime {

    private const val REQUEST_CODE = 7302
    private const val BEEP_MILLIS = 150
    private const val TONE_VOLUME = 90

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

    /** 播一声短促的「嘀」。 */
    fun chime(context: Context) {
        val tone = runCatching {
            ToneGenerator(AudioManager.STREAM_NOTIFICATION, TONE_VOLUME).also {
                it.startTone(ToneGenerator.TONE_PROP_BEEP, BEEP_MILLIS)
            }
        }.getOrNull()
        if (tone != null) {
            // ToneGenerator 持有音频资源，播完必须释放，否则会一直占着音频通道。
            Handler(Looper.getMainLooper()).postDelayed({ tone.release() }, BEEP_MILLIS + 200L)
            return
        }
        playNotificationRingtone(context)
    }

    /** 少数机型上 ToneGenerator 不可用，退回系统通知音（只响一次）。 */
    private fun playNotificationRingtone(context: Context) {
        val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION) ?: return
        val ringtone = runCatching { RingtoneManager.getRingtone(context, uri) }.getOrNull() ?: return
        ringtone.audioAttributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION_EVENT)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        runCatching { ringtone.play() }.onSuccess { stopLater(ringtone) }
    }

    private fun stopLater(ringtone: Ringtone) {
        Handler(Looper.getMainLooper()).postDelayed({ runCatching { ringtone.stop() } }, BEEP_MILLIS + 800L)
    }

    private fun canScheduleExact(manager: AlarmManager): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S || manager.canScheduleExactAlarms()
}

class HourlyChimeReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val settings = AppSettings(context)
        if (!settings.hourlyChimeEnabled) return

        val place = settings.place
        HourlyChime.chime(context)
        HourlyChime.schedule(context, place)
    }

    companion object {
        const val EXTRA_BOUNDARY_MILLIS = "boundary_millis"
    }
}
