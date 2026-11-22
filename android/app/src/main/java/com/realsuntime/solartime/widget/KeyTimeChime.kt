package com.realsuntime.solartime.widget

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import com.realsuntime.solartime.data.AppSettings
import com.realsuntime.solartime.data.Place
import com.realsuntime.solartime.data.TakeBand
import com.realsuntime.solartime.data.TakeTimeRepository
import com.realsuntime.solartime.solar.SolarTimeMath
import java.time.Instant
import kotlin.math.roundToLong

/**
 * 「进入关键时间」报时：每到一段关键时间的起点蜂鸣一次。
 *
 * 关键时间来自「西格瑪食療」页面，本身按真太阳时计；所以闹钟按真太阳时刻度对齐，
 * 换算成系统时刻后再交给 AlarmManager。只播提示音，不发通知。
 */
object KeyTimeChime {

    private const val REQUEST_CODE = 7302

    /** 蜂鸣时长。 */
    internal const val BEEP_MILLIS = 500

    /** 旧版本「整点报时」的 receiver（已删除），仅用于清掉它留下的闹钟。 */
    private const val LEGACY_RECEIVER = "com.realsuntime.solartime.widget.HourlyChimeReceiver"

    private const val SECONDS_PER_DAY = 86_400.0

    /**
     * 响过之后重排时先跨过的秒数。
     *
     * 关键时间按真太阳时算，边界不是整秒；闹钟若比边界早到一点点，
     * 触发后就地重排会算回「同一段还差 0.3 秒」，于是隔一秒又响一声（用户反馈的「响两声」）。
     * 重排时把参考时刻往后推 [SETTLE_SECONDS]，这一声就必定算作已响过。
     */
    private const val SETTLE_SECONDS = 2L

    /**
     * 距离下一个关键时间起点还有多少秒（按真太阳时计）。
     *
     * 没有关键时间（页面没抓到过或已超过 7 天）时返回 null —— 此时不报时。
     */
    internal fun secondsToNextStart(solarSecondsOfDay: Double, bands: List<TakeBand>): Double? {
        if (bands.isEmpty()) return null
        return bands.minOf { band ->
            val target = band.startMinute * 60.0
            val delta = (target - solarSecondsOfDay).mod(SECONDS_PER_DAY)
            // 正好落在边界上时等明天，避免「刚响过又立刻再响」。
            if (delta < 0.001) SECONDS_PER_DAY else delta
        }
    }

    /**
     * 由「距离下一段起点还有多少秒」算出触发时刻（毫秒）。
     *
     * **向上取整**：`roundToLong` 有一半概率把触发点排到边界之前，闹钟就会在边界前
     * 零点几秒响，响完重排又把同一段算回来 —— 这就是「响两声」的来源。
     * 提取成纯函数是为了能被单测盯住。
     */
    internal fun triggerFrom(nowMillis: Long, deltaSeconds: Double): Long =
        nowMillis + kotlin.math.ceil(deltaSeconds * 1000.0).toLong()

    /**
     * 重排下一次报时；关闭时顺带取消已有闹钟。
     *
     * @param firedAtMillis 刚刚响过的那次计划时刻（接收器传入）。给了它就把参考时刻往后推
     *   [SETTLE_SECONDS]，避免「同一段边界再响一次」—— 这是「报时会响两声」的根因。
     */
    fun schedule(context: Context, firedAtMillis: Long = 0L) {
        cancelLegacy(context)
        val settings = AppSettings(context)
        if (!settings.keyTimeChimeEnabled) {
            cancel(context)
            return
        }
        val manager = context.getSystemService(AlarmManager::class.java) ?: return
        val place = settings.place
        val now = if (firedAtMillis > 0L) {
            Instant.ofEpochMilli(firedAtMillis).plusSeconds(SETTLE_SECONDS)
        } else {
            Instant.now()
        }
        val deltaSeconds = secondsToNextStart(
            solarSecondsOfDay = SolarTimeMath.trueSolarSecondsOfDay(now, place.longitude),
            bands = TakeTimeRepository.schedule(context)?.bands.orEmpty(),
        )
        if (deltaSeconds == null) {
            cancel(context)
            return
        }
        val trigger = triggerFrom(now.toEpochMilli(), deltaSeconds)
        ChimeAlarm.schedule(context, trigger, alarmIntent(context, trigger))
    }

    fun cancel(context: Context) {
        val manager = context.getSystemService(AlarmManager::class.java) ?: return
        manager.cancel(alarmIntent(context, 0L))
    }

    /**
     * 清掉旧版本「整点报时」留下的闹钟。
     *
     * 那个 receiver 类已经删了，闹钟再触发只会报「找不到组件」；用组件名（而不是类）
     * 就能把它找出来取消。目标不存在时 getBroadcast 返回 null，这里没有副作用。
     */
    private fun cancelLegacy(context: Context) {
        val manager = context.getSystemService(AlarmManager::class.java) ?: return
        val legacy = Intent().setClassName(context, LEGACY_RECEIVER)
        val pending = runCatching {
            PendingIntent.getBroadcast(
                context,
                REQUEST_CODE,
                legacy,
                PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
            )
        }.getOrNull() ?: return
        runCatching { manager.cancel(pending) }
        runCatching { pending.cancel() }
    }

    /** 蜂鸣 500 ms；[onDone] 在播放结束后回调。 */
    fun beep(onDone: () -> Unit = {}) {
        Chime.beep(BEEP_MILLIS, onDone = onDone)
    }

    private fun alarmIntent(context: Context, triggerMillis: Long): PendingIntent {
        val intent = Intent(context, KeyTimeChimeReceiver::class.java)
            .putExtra(KeyTimeChimeReceiver.EXTRA_START_MILLIS, triggerMillis)
        return PendingIntent.getBroadcast(
            context,
            REQUEST_CODE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun canScheduleExact(manager: AlarmManager): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S || manager.canScheduleExactAlarms()
}

class KeyTimeChimeReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (!AppSettings(context).keyTimeChimeEnabled) return
        // 用 goAsync 保住进程直到播放结束：onReceive 一返回进程就可能被回收，
        // 音轨随之销毁，蜂鸣会被截断（锁屏/后台时尤其明显）。
        val pending = goAsync()
        KeyTimeChime.beep {
            pending.finish()
        }
        // 排下一次；把自己这次的计划时刻传回去，重排时会跨过这条边界（否则可能再响一声）。
        KeyTimeChime.schedule(
            context,
            firedAtMillis = intent.getLongExtra(EXTRA_START_MILLIS, 0L),
        )
    }

    companion object {
        const val EXTRA_START_MILLIS = "start_millis"
    }
}
