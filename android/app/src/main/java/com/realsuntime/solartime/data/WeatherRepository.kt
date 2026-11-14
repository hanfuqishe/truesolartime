package com.realsuntime.solartime.data

import android.content.Context
import com.realsuntime.solartime.widget.WidgetUpdater
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.ZoneOffset
import java.util.Locale
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import kotlin.math.roundToInt

/**
 * 当前天气（气温 + WMO 天气码），数据来自 Open-Meteo：免费、无需 Key、全球可用。
 *
 * 天气变化慢，缓存 30 分钟；只有缓存过期或位置移动超过 5 km 才请求一次，
 * 请求失败时沿用旧值（没有旧值就只显示日期）。
 *
 * 数据来源需要在界面上标注：Open-Meteo（CC BY 4.0）。
 */
object WeatherRepository {

    data class Snapshot(val temperatureC: Int, val code: Int)

    /** 某个整点的小时预报。 */
    data class HourPoint(val epochSeconds: Long, val temperatureC: Int, val code: Int)

    /** WMO 天气码归类，便于本地化文案。 */
    enum class Condition {
        CLEAR, PARTLY_CLOUDY, OVERCAST, FOG, DRIZZLE, RAIN, HEAVY_RAIN, SHOWERS, SNOW, HEAVY_SNOW, THUNDER
    }

    private const val PREFS = "weather_cache"
    private const val KEY_TEMP = "temp"
    private const val KEY_CODE = "code"
    private const val KEY_LAT = "lat"
    private const val KEY_LON = "lon"
    private const val KEY_TIME = "time"
    private const val KEY_HOURLY = "hourly"
    private const val KEY_SCHEMA = "schema"

    /** 缓存格式版本；请求参数变化（如新增 past_days）时递增，强制重新取数。 */
    private const val SCHEMA = 2

    /** 需要重新取数的时限：超过它就发起一次网络请求（不是「超过它就不显示」）。 */
    private const val TTL_MILLIS = 30L * 60 * 1000

    /**
     * 显示用的时限：**24 小时**。
     *
     * 取数失败时（夜间 Doze、闹钟被冻结、网络刚醒还没通、上游 CDN 的某个节点不可达……）
     * 卡片继续显示最近一次成功取到的天气，总比整块变成 `--` 强；超过一天才当作没有数据。
     */
    private const val DISPLAY_MAX_AGE_MILLIS = 24L * 60 * 60 * 1000

    /** 小时预报沿用同样的时限：与「当前天气」一起出现、一起消失，不要一半有一半空。 */
    private const val HOURLY_MAX_AGE_MILLIS = 24L * 60 * 60 * 1000

    /**
     * 取数失败后的重试间隔：成功后的刷新节奏是 30 分钟（[TTL_MILLIS]），
     * 但失败时不该等半小时——用户可能就盯着这几分钟的空白。
     */
    private const val RETRY_AFTER_FAILURE_MILLIS = 5L * 60 * 1000

    /** 上次尝试取数的时刻（无论成败），用于失败后的 5 分钟节流。 */
    private const val KEY_ATTEMPT = "attempt"

    private const val MOVE_THRESHOLD_KM = 5.0

    private val inFlight = AtomicBoolean(false)

    /** 每成功写一次缓存就 +1：界面靠它发现「天气换过了」，不用等半分钟的刷新节拍。 */
    private val revisionCount = AtomicInteger(0)

    internal fun revision(): Int = revisionCount.get()

    fun cached(context: Context): Snapshot? {
        val prefs = prefs(context)
        if (!prefs.contains(KEY_TEMP)) return null
        val age = System.currentTimeMillis() - prefs.getLong(KEY_TIME, 0L)
        if (age !in 0..DISPLAY_MAX_AGE_MILLIS) return null
        return Snapshot(prefs.getInt(KEY_TEMP, 0), prefs.getInt(KEY_CODE, 0))
    }

    /**
     * 同上，但要求缓存是当前这个地点取的。
     *
     * 换城市后新数据回来之前（或者取数一直失败），不能把上一个城市的天气安到新位置上；
     * 相距超过 5 km 就当没有数据。
     */
    fun cached(context: Context, place: Place): Snapshot? {
        val snapshot = cached(context) ?: return null
        return if (belongsTo(context, place)) snapshot else null
    }

    /** 缓存的小时预报；过期太久则返回空列表。 */
    fun hourly(context: Context): List<HourPoint> {
        val prefs = prefs(context)
        val encoded = prefs.getString(KEY_HOURLY, null) ?: return emptyList()
        val age = System.currentTimeMillis() - prefs.getLong(KEY_TIME, 0L)
        if (age !in 0..HOURLY_MAX_AGE_MILLIS) return emptyList()
        return decodeHourly(encoded)
    }

    /** 同上，但要求这份预报是当前地点取的：换城市后不能拿旧城市的预报顶上。 */
    fun hourly(context: Context, place: Place): List<HourPoint> {
        if (!belongsTo(context, place)) return emptyList()
        return hourly(context)
    }

    /** 缓存里的坐标是否属于当前地点（相距不超过 5 km）。 */
    private fun belongsTo(context: Context, place: Place): Boolean {
        val prefs = prefs(context)
        if (!prefs.contains(KEY_LAT) || !prefs.contains(KEY_LON)) return false
        val lat = prefs.getFloat(KEY_LAT, Float.NaN).toDouble()
        val lon = prefs.getFloat(KEY_LON, Float.NaN).toDouble()
        if (lat.isNaN() || lon.isNaN()) return false
        return CityIndex.distanceKm(lat, lon, place.latitude, place.longitude) <= MOVE_THRESHOLD_KM
    }

    /** 需要时在后台刷新，成功后重绘小组件。 */
    /** @param force 忽略 30 分钟窗口直接取数（用户手工换了地点时用）。 */
    fun requestRefresh(context: Context, place: Place, force: Boolean = false) {
        if (!force && !needsRefresh(context, place)) return
        if (!inFlight.compareAndSet(false, true)) return

        val app = context.applicationContext
        prefs(app).edit().putLong(KEY_ATTEMPT, System.currentTimeMillis()).apply()
        Thread {
            try {
                val body = fetch(place.latitude, place.longitude) ?: return@Thread
                val snapshot = parse(body) ?: return@Thread
                save(app, place, snapshot, parseHourly(body))
                WidgetUpdater.refreshAll(app)
            } catch (ignored: Exception) {
                // 网络异常时继续用旧值。
            } finally {
                inFlight.set(false)
            }
        }.apply { isDaemon = true }.start()
    }

    /**
     * 缓存过期、或与上次取数的坐标相距超过阈值。
     *
     * [sinceAttemptMillis] 是距上一次**尝试**取数的时长：过期后仍按 [RETRY_AFTER_FAILURE_MILLIS]
     * 节流，避免失败时每次回到前台都立刻打一次网络；取数成功会连带刷新尝试时刻。
     */
    internal fun shouldRefresh(
        ageMillis: Long,
        movedKm: Double,
        sinceAttemptMillis: Long = Long.MAX_VALUE,
    ): Boolean {
        if (movedKm > MOVE_THRESHOLD_KM) return true
        if (ageMillis in 0..TTL_MILLIS) return false
        // 已过期：上次尝试不足 5 分钟就再等等（失败重试的节流）。
        return sinceAttemptMillis !in 0..RETRY_AFTER_FAILURE_MILLIS
    }

    internal fun parse(json: String): Snapshot? = runCatching {
        val current = JSONObject(json).optJSONObject("current") ?: return null
        if (!current.has("temperature_2m")) return null
        Snapshot(
            temperatureC = current.getDouble("temperature_2m").roundToInt(),
            code = current.optInt("weather_code", 0),
        )
    }.getOrNull()

    /** 解析 hourly 序列（请求时指定 timezone=UTC，时间因此可直接当 UTC 解析）。 */
    internal fun parseHourly(json: String): List<HourPoint> = runCatching {
        val hourly = JSONObject(json).optJSONObject("hourly") ?: return emptyList()
        val times = hourly.optJSONArray("time") ?: return emptyList()
        val temps = hourly.optJSONArray("temperature_2m") ?: return emptyList()
        val codes = hourly.optJSONArray("weather_code") ?: return emptyList()
        val count = minOf(times.length(), temps.length())
        (0 until count).mapNotNull { index ->
            val epoch = runCatching {
                LocalDateTime.parse(times.getString(index)).toEpochSecond(ZoneOffset.UTC)
            }.getOrNull() ?: return@mapNotNull null
            HourPoint(
                epochSeconds = epoch,
                temperatureC = temps.optDouble(index, Double.NaN).let {
                    if (it.isNaN()) return@mapNotNull null else it.roundToInt()
                },
                code = codes.optInt(index, 0),
            )
        }
    }.getOrDefault(emptyList())

    /**
     * 小组件要显示的时刻：从当前所在的 [stepHours] 小时块开始，按步长取 [count] 个（本地时区对齐）。
     * 返回的是 UTC 秒，可直接与 [HourPoint.epochSeconds] 对应。
     */
    internal fun slots(
        nowEpochSeconds: Long,
        zoneOffsetSeconds: Int,
        count: Int,
        stepHours: Int,
    ): List<Long> {
        val step = stepHours * 3600L
        val local = nowEpochSeconds + zoneOffsetSeconds
        val blockStart = local - Math.floorMod(local, step)
        return (0 until count).map { blockStart + it * step - zoneOffsetSeconds }
    }

    internal fun encodeHourly(points: List<HourPoint>): String =
        points.joinToString(";") { "${it.epochSeconds},${it.temperatureC},${it.code}" }

    internal fun decodeHourly(encoded: String): List<HourPoint> =
        encoded.split(';').mapNotNull { item ->
            val parts = item.split(',')
            if (parts.size != 3) return@mapNotNull null
            val epoch = parts[0].toLongOrNull() ?: return@mapNotNull null
            val temp = parts[1].toIntOrNull() ?: return@mapNotNull null
            HourPoint(epoch, temp, parts[2].toIntOrNull() ?: 0)
        }

    /** 本地某一天的最高/最低温度；小时序列没覆盖这一天时返回 null。 */
    internal fun temperatureRange(points: List<HourPoint>, date: LocalDate, zone: ZoneId): Pair<Int, Int>? {
        val temps = points
            .filter { Instant.ofEpochSecond(it.epochSeconds).atZone(zone).toLocalDate() == date }
            .map { it.temperatureC }
        if (temps.isEmpty()) return null
        return temps.max() to temps.min()
    }

    /** WMO 天气码 → 分类。 */
    internal fun conditionOf(code: Int): Condition = when (code) {        0 -> Condition.CLEAR
        1, 2 -> Condition.PARTLY_CLOUDY
        3 -> Condition.OVERCAST
        45, 48 -> Condition.FOG
        51, 53, 55, 56, 57 -> Condition.DRIZZLE
        61, 63, 66, 67 -> Condition.RAIN
        65, 82 -> Condition.HEAVY_RAIN
        80, 81 -> Condition.SHOWERS
        71, 73, 77, 85, 86 -> Condition.SNOW
        75 -> Condition.HEAVY_SNOW
        95, 96, 99 -> Condition.THUNDER
        else -> Condition.OVERCAST
    }

    private fun needsRefresh(context: Context, place: Place): Boolean {
        val prefs = prefs(context)
        // 没有实时值、或旧版本缓存里缺小时序列，都重新取一次。
        if (!prefs.contains(KEY_TEMP) || !prefs.contains(KEY_HOURLY)) return true
        if (prefs.getInt(KEY_SCHEMA, 0) < SCHEMA) return true
        val lat = prefs.getFloat(KEY_LAT, Float.NaN).toDouble()
        val lon = prefs.getFloat(KEY_LON, Float.NaN).toDouble()
        val moved = if (lat.isNaN() || lon.isNaN()) {
            Double.MAX_VALUE
        } else {
            CityIndex.distanceKm(lat, lon, place.latitude, place.longitude)
        }
        val now = System.currentTimeMillis()
        val sinceAttempt = now - prefs.getLong(KEY_ATTEMPT, 0L)
        val age = now - prefs.getLong(KEY_TIME, 0L)
        return shouldRefresh(age, moved, sinceAttempt)
    }

    private fun fetch(latitude: Double, longitude: Double): String? {
        val url = String.format(
            Locale.ROOT,
            "https://api.open-meteo.com/v1/forecast?latitude=%.4f&longitude=%.4f" +
                "&current=temperature_2m,weather_code" +
                "&hourly=temperature_2m,weather_code&forecast_days=2&past_days=1&timezone=UTC",
            latitude,
            longitude,
        )
        val connection = (URL(url).openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = 5_000
            readTimeout = 5_000
        }
        return try {
            if (connection.responseCode != HttpURLConnection.HTTP_OK) return null
            connection.inputStream.bufferedReader().use { it.readText() }
        } finally {
            connection.disconnect()
        }
    }

    private fun save(context: Context, place: Place, snapshot: Snapshot, hourly: List<HourPoint>) {
        prefs(context).edit()
            .putInt(KEY_TEMP, snapshot.temperatureC)
            .putInt(KEY_CODE, snapshot.code)
            .putString(KEY_HOURLY, encodeHourly(hourly))
            .putInt(KEY_SCHEMA, SCHEMA)
            .putFloat(KEY_LAT, place.latitude.toFloat())
            .putFloat(KEY_LON, place.longitude.toFloat())
            .putLong(KEY_TIME, System.currentTimeMillis())
            .apply()
        revisionCount.incrementAndGet()
    }

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
