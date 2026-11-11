package com.realsuntime.solartime.data

import android.content.Context
import com.realsuntime.solartime.widget.WidgetUpdater
import java.net.HttpURLConnection
import java.net.URL
import java.time.LocalDate
import java.time.ZoneId
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.random.Random

/**
 * 一段关键时间，按真太阳时的当日分钟数表示。
 *
 * [endMinute] 小于 [startMinute] 时表示这一段跨过午夜。
 */
data class TakeBand(val startMinute: Int, val endMinute: Int) {

    fun lengthMinutes(): Int = Math.floorMod(endMinute - startMinute, MINUTES_PER_DAY)

    /** [minuteOfDay] 是否落在这段关键时间里（含起点、不含终点，跨午夜的段也支持）。 */
    fun contains(minuteOfDay: Double): Boolean {
        val offset = (minuteOfDay - startMinute).mod(MINUTES_PER_DAY.toDouble())
        return offset < lengthMinutes()
    }

    companion object {
        const val MINUTES_PER_DAY = 24 * 60
    }
}

/** 关键时间的要求：冻或温用绿色，热或温用红色。 */
enum class TakeTemperature { COLD_OR_MILD, HOT_OR_MILD }

/** 网页上抓到的关键时间。 */
data class TakeTimeSchedule(val bands: List<TakeBand>, val temperature: TakeTemperature?)

/**
 * 抓取「西格瑪食療」页面上的「服用時間 Take Time」，我们称之为**关键时间**，供小组件的时间轴着色。
 * 页面给出的时间一律当作真太阳时使用，不做时区或经度换算。
 *
 * 页面只有一个固定地址，内容变化很慢，因此：
 * 成功一次就把结果连时间戳一起存下来；后续刷新只用缓存，距上次尝试超过
 * [RETRY_MILLIS] 才重新联网。缓存超过 [VALID_MILLIS]（7 天）即视为无效 ——
 * 于是「从未打开过」和「7 天内没打开过」都只画轴线、不着色。
 */
object TakeTimeRepository {

    private const val PREFS = "take_time_cache"
    private const val KEY_BANDS = "bands"
    private const val KEY_TEMP = "temp"
    private const val KEY_FETCHED = "fetched"
    private const val KEY_ATTEMPT = "attempt"
    private const val KEY_SUCCESS_DAY = "success_day"
    private const val KEY_TARGET_DAY = "target_day"
    private const val KEY_TARGET_MILLIS = "target_millis"

    private const val PAGE_URL = "https://www.duosuccess.com/tcm/001a01080301b01a.htm"

    /** 上次成功抓取的结果最多沿用 7 天，超过就当作从未抓取过。 */
    private const val VALID_MILLIS = 7L * 24 * 60 * 60 * 1000

    /**
     * 每天只在 [SYNC_WINDOW_START_MINUTE, SYNC_WINDOW_END_MINUTE) 之间挑一个随机时刻同步，
     * 免得所有人都卡在同一点上访问；错过了（比如整夜关机）就在下一次刷新时补上。
     */
    private const val SYNC_WINDOW_START_MINUTE = 60
    private const val SYNC_WINDOW_END_MINUTE = 300

    /** 当天同步失败后每个小时重试一次。 */
    private const val RETRY_MILLIS = 60L * 60 * 1000

    private const val TIMEOUT_MILLIS = 10_000

    /** 「Take Time」后面这段文字里就是时间段与温度要求。 */
    private const val WINDOW_CHARS = 400

    private val inFlight = AtomicBoolean(false)

    /** 当前可用的关键时间；缓存缺失或超过 7 天返回 null（此时不着色）。 */
    fun schedule(context: Context): TakeTimeSchedule? {
        val prefs = prefs(context)
        val bands = decodeBands(prefs.getString(KEY_BANDS, null)) ?: return null
        if (bands.isEmpty()) return null
        val age = System.currentTimeMillis() - prefs.getLong(KEY_FETCHED, 0L)
        if (!isFresh(age)) return null
        return TakeTimeSchedule(bands, temperatureOf(prefs.getString(KEY_TEMP, null)))
    }

    /** 需要且允许时联网刷新一次。 */
    fun requestRefresh(context: Context) {
        val app = context.applicationContext
        val now = System.currentTimeMillis()
        if (!shouldSyncNow(app, now)) return
        if (!inFlight.compareAndSet(false, true)) return
        // 先记下尝试时刻：失败后要等一小时再试。
        markAttempt(app, now)
        Thread {
            try {
                val html = fetch() ?: return@Thread
                val parsed = parse(html) ?: return@Thread
                save(app, parsed, now)
                WidgetUpdater.refreshAll(app)
            } catch (ignored: Exception) {
                // 打不开就继续沿用 7 天内的旧数据（若有），一小时后重试。
            } finally {
                inFlight.set(false)
            }
        }.apply { isDaemon = true }.start()
    }

    /**
     * 今天是否该联网同步。
     *
     * 每天的目标时刻落在 01:00–05:00 之间的随机分钟上：今天已成功就跳过；
     * 目标时刻没到也跳过；失败后每小时重试一次，直到成功。
     */
    private fun shouldSyncNow(context: Context, now: Long): Boolean {
        val today = LocalDate.now().toString()
        val target = targetMillisForToday(context, today)
        val prefs = prefs(context)
        return shouldSync(
            nowMillis = now,
            targetMillis = target,
            today = today,
            lastSuccessDay = prefs.getString(KEY_SUCCESS_DAY, null),
            lastAttemptMillis = prefs.getLong(KEY_ATTEMPT, 0L),
        )
    }

    internal fun shouldSync(
        nowMillis: Long,
        targetMillis: Long,
        today: String,
        lastSuccessDay: String?,
        lastAttemptMillis: Long,
    ): Boolean {
        if (lastSuccessDay == today) return false
        if (nowMillis < targetMillis) return false
        return nowMillis - lastAttemptMillis !in 0..RETRY_MILLIS
    }

    /** 当天在 01:00–05:00 之间挑一个随机分钟；跨天时重新挑并保存。 */
    private fun targetMillisForToday(context: Context, today: String): Long {
        val prefs = prefs(context)
        if (prefs.getString(KEY_TARGET_DAY, null) == today) {
            val saved = prefs.getLong(KEY_TARGET_MILLIS, 0L)
            if (saved > 0L) return saved
        }
        val offsetMinutes = SYNC_WINDOW_START_MINUTE +
            Random.nextInt(SYNC_WINDOW_END_MINUTE - SYNC_WINDOW_START_MINUTE)
        val target = pickTargetMillis(LocalDate.parse(today), ZoneId.systemDefault(), offsetMinutes)
        prefs.edit()
            .putString(KEY_TARGET_DAY, today)
            .putLong(KEY_TARGET_MILLIS, target)
            .apply()
        return target
    }

    /** 当天 00:00 之后 [offsetMinutes] 分钟的时刻。 */
    internal fun pickTargetMillis(day: LocalDate, zone: ZoneId, offsetMinutes: Int): Long =
        day.atStartOfDay(zone).plusMinutes(offsetMinutes.toLong()).toInstant().toEpochMilli()

    /** 随机时刻始终落在 01:00–05:00 之间（含 01:00，不含 05:00）。 */
    internal fun isInsideSyncWindow(offsetMinutes: Int): Boolean =
        offsetMinutes >= SYNC_WINDOW_START_MINUTE && offsetMinutes < SYNC_WINDOW_END_MINUTE

    internal fun isFresh(ageMillis: Long): Boolean = ageMillis in 0..VALID_MILLIS

    /**
     * 从页面里解析「服用時間 Take Time」（关键时间）。
     *
     * 页面形如：
     * `服用時間 Take Time : 15:00-17:00　20:00-22:00　10:00-12:00　(凍或溫 Cold or Mild)`
     * 标签可能被 `<br>`／`&nbsp;` 拆开，所以先去标签再在「Take Time」附近取一段窗口匹配。
     */
    internal fun parse(html: String): TakeTimeSchedule? {
        val text = html.replace(Regex("<[^>]*>"), " ")
            .replace("&nbsp;", " ")
            .replace("&#160;", " ")
            .replace("&amp;", "&")
        val anchor = text.indexOf(TIME_ANCHOR, ignoreCase = true)
        val source = if (anchor >= 0) text.substring(anchor, minOf(text.length, anchor + WINDOW_CHARS)) else text
        val bands = RANGE_REGEX.findAll(source)
            .mapNotNull { match ->
                val start = minuteOf(match.groupValues[1].toIntOrNull(), match.groupValues[2].toIntOrNull())
                val end = minuteOf(match.groupValues[3].toIntOrNull(), match.groupValues[4].toIntOrNull())
                if (start == null || end == null || start == end) null else TakeBand(start, end)
            }
            .filter { it.lengthMinutes() in 1..(TakeBand.MINUTES_PER_DAY - 1) }
            .toList()
        if (bands.isEmpty()) return null
        return TakeTimeSchedule(bands, parseTemperature(source))
    }

    /** 只认英文标记：Cold 用绿色，Hot 用红色；两者都没有就当作没标注。 */
    internal fun parseTemperature(text: String): TakeTemperature? = when {
        text.contains("Cold or Mild", ignoreCase = true) -> TakeTemperature.COLD_OR_MILD
        text.contains("Hot or Mild", ignoreCase = true) -> TakeTemperature.HOT_OR_MILD
        else -> null
    }

    private fun minuteOf(hour: Int?, minute: Int?): Int? {
        if (hour == null || minute == null) return null
        if (hour !in 0..24 || minute !in 0..59) return null
        return (hour * 60 + minute) % TakeBand.MINUTES_PER_DAY
    }

    private fun temperatureOf(raw: String?): TakeTemperature? = when (raw) {
        "cold" -> TakeTemperature.COLD_OR_MILD
        "hot" -> TakeTemperature.HOT_OR_MILD
        else -> null
    }

    internal fun encodeBands(bands: List<TakeBand>): String =
        bands.joinToString(",") { "${it.startMinute}-${it.endMinute}" }

    internal fun decodeBands(encoded: String?): List<TakeBand>? {
        if (encoded.isNullOrBlank()) return null
        return encoded.split(',').mapNotNull { part ->
            val pair = part.split('-')
            if (pair.size != 2) return@mapNotNull null
            val start = pair[0].toIntOrNull() ?: return@mapNotNull null
            val end = pair[1].toIntOrNull() ?: return@mapNotNull null
            TakeBand(start, end)
        }
    }

    private fun fetch(): String? {
        val connection = (URL(PAGE_URL).openConnection() as HttpURLConnection).apply {
            connectTimeout = TIMEOUT_MILLIS
            readTimeout = TIMEOUT_MILLIS
            requestMethod = "GET"
        }
        return try {
            if (connection.responseCode != HttpURLConnection.HTTP_OK) return null
            connection.inputStream.bufferedReader().use { it.readText() }
        } finally {
            connection.disconnect()
        }
    }

    private fun markAttempt(context: Context, now: Long) {
        prefs(context).edit().putLong(KEY_ATTEMPT, now).apply()
    }

    private fun save(context: Context, schedule: TakeTimeSchedule, now: Long) {
        prefs(context).edit()
            .putString(KEY_BANDS, encodeBands(schedule.bands))
            .putString(
                KEY_TEMP,
                when (schedule.temperature) {
                    TakeTemperature.COLD_OR_MILD -> "cold"
                    TakeTemperature.HOT_OR_MILD -> "hot"
                    null -> ""
                },
            )
            .putLong(KEY_FETCHED, now)
            .putString(KEY_SUCCESS_DAY, LocalDate.now().toString())
            .apply()
    }

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private val RANGE_REGEX =
        Regex("""(\d{1,2}):(\d{2})\s*[-~–—至]\s*(\d{1,2}):(\d{2})""")

    private const val TIME_ANCHOR = "Take Time"
}
