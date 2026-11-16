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
import java.time.format.DateTimeFormatter
import java.util.Locale
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import kotlin.math.roundToInt

/**
 * 当前天气（气温 + WMO 天气码）与逐时预报。
 *
 * 主源是 Open-Meteo：免费、无需 Key、全球可用，**逐时粒度 1 小时**。
 * 主源请求失败（网络错误/超时/非 2xx/JSON 解析失败，且 2 秒后重试一次仍失败）时，
 * 自动降级到备用源 7Timer!（**逐时粒度 3 小时**）。
 *
 * 「步长」是随数据一起缓存的一等公民（[Hourly.stepHours]）：界面永远只画 6 个槽位，
 * 但槽位之间的间隔跟着数据源走 —— 拿 1 小时的网格去配 3 小时的数据，标签就会和实际读数错位。
 *
 * 天气变化慢，缓存 30 分钟；只有缓存过期或位置移动超过 5 km 才请求一次，
 * 请求失败时沿用旧值（没有旧值就只显示日期）。
 *
 * 数据来源需要在界面上标注：Open-Meteo（CC BY 4.0）/ 7Timer!（见 [Source]）。
 */
object WeatherRepository {

    data class Snapshot(val temperatureC: Int, val code: Int)

    /** 某个整点的小时预报。 */
    data class HourPoint(val epochSeconds: Long, val temperatureC: Int, val code: Int)

    /** 逐时数据的来源；步长跟着来源走（主源 1 小时、备用源 3 小时）。 */
    enum class Source(val id: String, val stepHours: Int) {
        OPEN_METEO("open-meteo", 1),
        SEVEN_TIMER("7timer", 3),
        ;

        companion object {
            /** 缓存里的来源字符串（可能来自旧版本或被人为改坏）→ 枚举，认不出来一律当主源。 */
            fun of(id: String?): Source = entries.firstOrNull { it.id == id } ?: OPEN_METEO
        }
    }

    /**
     * 一份逐时预报：采样点、来源、步长、取数时刻。
     *
     * 这四样必须一起用：只取 [points] 而不知道 [stepHours]，槽位标签就会和实际读数错位。
     */
    data class Hourly(
        val points: List<HourPoint>,
        val source: Source,
        val stepHours: Int,
        /** 这份数据是多久以前取的（毫秒）；没有缓存时为 null。 */
        val ageMillis: Long?,
    )

    /** 界面上的一格：用哪个采样点，以及它是不是「现在」那一格。 */
    data class Slot(val epochSeconds: Long, val isNow: Boolean)

    /** 主源失败后的处理方案。 */
    enum class Fallback {
        /** 缓存还没过期：什么都不做，界面继续用缓存（不清空）。 */
        KEEP_CACHE,

        /** 缓存已过期，或根本没有缓存：去问备用源 7Timer!。 */
        TRY_SEVEN_TIMER,
    }

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
    private const val KEY_STEP = "step_hours"
    private const val KEY_SOURCE = "source"

    /** 缓存格式版本；请求参数变化（新增天气源/步长）时递增，强制重新取数。 */
    private const val SCHEMA = 3

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

    /**
     * 「低精度（3 小时粒度）」数据的升级重试间隔：**最多每 10 分钟一次**。
     *
     * 备用源 7Timer! 只有 3 小时一格，比主源粗；只要当前显示的是它，即使还没到 30 分钟
     * 也值得再问一次主源，好尽早换回 1 小时粒度。但也不能每分钟都打——
     * 主源挂掉时那会把请求量放大十倍，所以按这个间隔节流。
     */
    private const val LOW_PRECISION_RETRY_MILLIS = 10L * 60 * 1000

    /**
     * 主源失败后**立刻**重试一次前的等待时长。
     *
     * 只重试一次：一次握手超时/一个坏节点不该让整张卡从 1 小时粒度掉到 3 小时粒度，
     * 但也不该为了主源把降级拖太久（用户可能正盯着 `--`）。
     */
    private const val PRIMARY_RETRY_DELAY_MILLIS = 2_000L

    /** 单次 HTTP 请求的超时（连接 / 读取各自 5 秒）。 */
    private const val HTTP_TIMEOUT_MILLIS = 5_000

    /** 上次尝试取数的时刻（无论成败），用于失败后的 5 分钟节流。 */
    private const val KEY_ATTEMPT = "attempt"

    private const val MOVE_THRESHOLD_KM = 5.0

    /** 7Timer! 的地址。**https 实测可用**（见 README / 交付说明），因此不必开明文 HTTP。 */
    private const val SEVEN_TIMER_URL =
        "https://www.7timer.info/bin/api.pl?lon=%.4f&lat=%.4f&product=civil&output=json"

    /** 7Timer! 的 `init` / `time` 都是 `yyyyMMddHH` 的 UTC 时刻。 */
    private val SEVEN_TIMER_STAMP: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyyMMddHH", Locale.ROOT)

    private val inFlight = AtomicBoolean(false)

    /** 每成功写一次缓存就 +1：界面靠它发现「天气换过了」，不用等半分钟的刷新节拍。 */
    private val revisionCount = AtomicInteger(0)

    internal fun revision(): Int = revisionCount.get()

    fun cached(context: Context): Snapshot? {
        val prefs = prefs(context)
        if (!prefs.contains(KEY_TEMP)) return null
        val age = System.currentTimeMillis() - prefs.getLong(KEY_TIME, 0L)
        if (!isDisplayable(age)) return null
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

    /** 缓存里的逐时预报（含步长与来源）；过期太久则返回空列表（但步长/来源照旧返回）。 */
    fun hourly(context: Context): Hourly {
        val prefs = prefs(context)
        val age = System.currentTimeMillis() - prefs.getLong(KEY_TIME, 0L)
        val source = Source.of(prefs.getString(KEY_SOURCE, null))
        val step = prefs.getInt(KEY_STEP, source.stepHours).takeIf { it > 0 } ?: source.stepHours
        val hasCache = prefs.contains(KEY_TEMP)
        val encoded = prefs.getString(KEY_HOURLY, null)
        if (encoded == null || age !in 0..HOURLY_MAX_AGE_MILLIS) {
            return Hourly(emptyList(), source, step, if (hasCache) age else null)
        }
        return Hourly(decodeHourly(encoded), source, step, age)
    }

    /** 同上，但要求这份预报是当前地点取的：换城市后不能拿旧城市的预报顶上。 */
    fun hourly(context: Context, place: Place): Hourly {
        if (!belongsTo(context, place)) return hourly(context).copy(points = emptyList())
        return hourly(context)
    }

    /** 缓存数据的来源（界面底部署名跟着它切换）；没有缓存时按主源算。 */
    fun source(context: Context): Source =
        Source.of(prefs(context).getString(KEY_SOURCE, null))

    /** 缓存数据的步长（1 或 3 小时）。 */
    fun stepHours(context: Context): Int = prefs(context).getInt(KEY_STEP, source(context).stepHours)
        .takeIf { it > 0 } ?: source(context).stepHours

    /** 缓存有多旧（毫秒）；没有缓存时返回 null。诊断页用它标注「数据过期 N 分钟」。 */
    fun ageMillis(context: Context): Long? {
        val prefs = prefs(context)
        if (!prefs.contains(KEY_TIME)) return null
        return (System.currentTimeMillis() - prefs.getLong(KEY_TIME, 0L)).coerceAtLeast(0L)
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

    /**
     * 需要时在后台刷新，成功后重绘小组件。
     *
     * @param force 忽略一切判定直接取数（用户手工换了地点时用）。
     * @param ignoreLowPrecisionThrottle 只放宽「低精度升级」的 10 分钟节流：回到前台时可以立刻试一次，
     *   但新鲜的主源数据仍然不会白打一次网络。切换地点走 [force]，本来就不受限。
     */
    fun requestRefresh(
        context: Context,
        place: Place,
        force: Boolean = false,
        ignoreLowPrecisionThrottle: Boolean = false,
    ) {
        if (!force && !needsRefresh(context, place, ignoreLowPrecisionThrottle)) return
        if (!inFlight.compareAndSet(false, true)) return

        val app = context.applicationContext
        // 这次尝试之前是不是「低精度」数据：失败时要在诊断里如实写成「升级失败」，而不是「刷新失败」。
        val upgradingFromLowPrecision = isLowPrecision(source(app), stepHours(app))
        prefs(app).edit().putLong(KEY_ATTEMPT, System.currentTimeMillis()).apply()
        Thread {
            try {
                // ① 主源。失败后隔 2 秒再试**一次**：一次超时/一个坏节点不值得把粒度从 1 小时降到 3 小时。
                var body = fetchPrimary(place)
                if (body == null) {
                    Thread.sleep(PRIMARY_RETRY_DELAY_MILLIS)
                    body = fetchPrimary(place)
                }
                val primary = body?.let(::parsePrimary)
                if (primary != null) {
                    save(app, place, primary.first, primary.second, Source.OPEN_METEO)
                    record(
                        app, Source.OPEN_METEO, primary.second,
                        if (upgradingFromLowPrecision) "主源成功，已从 3 小时粒度升级回 1 小时" else "主源成功",
                    )
                    WidgetUpdater.refreshAll(app)
                    return@Thread
                }

                // ② 主源失败：缓存还没过期就什么都不动，界面继续用缓存（低精度数据也原样保留）。
                val age = ageMillis(app)
                if (age != null && belongsTo(app, place) &&
                    fallbackFor(hasCache = true, cacheAgeMillis = age) == Fallback.KEEP_CACHE
                ) {
                    record(
                        app, source(app), hourly(app).points,
                        if (upgradingFromLowPrecision) {
                            "低精度升级失败，保留 7Timer! 的 3 小时数据（${ageNote(age)}）"
                        } else {
                            "主源失败，沿用未过期的缓存"
                        },
                    )
                    return@Thread
                }

                // ③ 缓存已过期（或根本没有）：问备用源 7Timer!，成功就整份换掉。
                val points = fetchSevenTimer(place)?.let(::parseSevenTimer).orEmpty()
                val snapshot = snapshotAt(points, System.currentTimeMillis() / 1000)
                if (snapshot != null) {
                    save(app, place, snapshot, points, Source.SEVEN_TIMER)
                    record(app, Source.SEVEN_TIMER, points, "主源失败，已降级到 7Timer!")
                    WidgetUpdater.refreshAll(app)
                    return@Thread
                }

                // ④ 两个源都失败：旧数据继续显示（哪怕过期），诊断里标注过期时长。
                record(
                    app, source(app), hourly(app).points,
                    "主源与备用源都失败，保留旧数据（${ageNote(age)}）",
                )
            } catch (ignored: Exception) {
                // 网络异常时继续用旧值。
            } finally {
                inFlight.set(false)
            }
        }.apply { isDaemon = true }.start()
    }

    /**
     * 需不需要重新取数。**满足任意一条就刷新**：
     *
     * 1. 位置移动超过 5 km（换了城市，缓存里的天气不属于当前地点）；
     * 2. 当前数据是**低精度**的（[lowPrecision]，即备用源 3 小时粒度）—— 即使还没过期也要试，
     *    目的是尽快升级回主源的 1 小时粒度；但最多每 [LOW_PRECISION_RETRY_MILLIS]（10 分钟）一次，
     *    免得主源一直挂着时把请求量放大十倍；
     * 3. 天气数据已过期（[TTL_MILLIS]，30 分钟）—— 过期后按 [RETRY_AFTER_FAILURE_MILLIS]（5 分钟）
     *    节流，避免失败时每次回到前台都立刻打一次网络。
     *
     * [sinceAttemptMillis] 是距上一次**尝试**取数的时长（成功或失败都算）。
     *
     * @param ignoreLowPrecisionThrottle 回到前台 / 换了地点时，允许**立即**升级一次，不受 10 分钟限制
     *   （此时仍不会为「新鲜的主源数据」白打一次网络，那条由过期规则决定）。
     */
    internal fun shouldRefresh(
        ageMillis: Long,
        movedKm: Double,
        sinceAttemptMillis: Long = Long.MAX_VALUE,
        lowPrecision: Boolean = false,
        ignoreLowPrecisionThrottle: Boolean = false,
    ): Boolean {
        if (movedKm > MOVE_THRESHOLD_KM) return true
        // 低精度：间隔够久（或允许立即升级）就去问主源，不必等 30 分钟。
        if (lowPrecision && (ignoreLowPrecisionThrottle || sinceAttemptMillis >= LOW_PRECISION_RETRY_MILLIS)) {
            return true
        }
        if (ageMillis in 0..TTL_MILLIS) return false
        // 已过期：上次尝试不足 5 分钟就再等等（失败重试的节流）。
        return sinceAttemptMillis !in 0..RETRY_AFTER_FAILURE_MILLIS
    }

    /** 当前缓存是不是「低精度」数据（备用源 7Timer!，3 小时粒度）。 */
    internal fun isLowPrecision(source: Source, stepHours: Int): Boolean =
        source == Source.SEVEN_TIMER || stepHours > Source.OPEN_METEO.stepHours

    /**
     * 主源失败之后怎么办（纯判定，便于单测）。
     *
     * - 没有缓存 → 去问备用源；
     * - 缓存还没过期（30 分钟内）→ **什么都不做**，界面继续显示缓存，不清空；
     * - 缓存过期 → 去问备用源（7Timer!）。
     */
    internal fun fallbackFor(hasCache: Boolean, cacheAgeMillis: Long): Fallback = when {
        !hasCache -> Fallback.TRY_SEVEN_TIMER
        cacheAgeMillis in 0..TTL_MILLIS -> Fallback.KEEP_CACHE
        else -> Fallback.TRY_SEVEN_TIMER
    }

    /** 这份缓存还值不值得显示（24 小时内都算「旧数据但可显示」）。 */
    internal fun isDisplayable(cacheAgeMillis: Long): Boolean =
        cacheAgeMillis in 0..DISPLAY_MAX_AGE_MILLIS

    /** 诊断用的「数据过期 N 分钟」；没有缓存时返回 null。 */
    internal fun staleLabel(cacheAgeMillis: Long?): String? {
        if (cacheAgeMillis == null || cacheAgeMillis < 0) return null
        return "数据过期 ${cacheAgeMillis / 60_000} 分钟"
    }

    /**
     * 诊断用的一句话缓存状态：过期了是「数据过期 N 分钟」，还没过期是「缓存仍有效（N 分钟）」。
     *
     * 低精度升级失败时缓存通常还新鲜（2 分钟前刚写进去的），这时写「数据过期」会把人看糊涂。
     */
    internal fun ageNote(cacheAgeMillis: Long?): String {
        if (cacheAgeMillis == null || cacheAgeMillis < 0) return "无缓存"
        return if (cacheAgeMillis <= TTL_MILLIS) {
            "缓存仍有效（${cacheAgeMillis / 60_000} 分钟）"
        } else {
            staleLabel(cacheAgeMillis).orEmpty()
        }
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
     * 主源的一份完整结果：实时读数 + 逐时序列。
     *
     * 两者缺一都算失败：只有 `current` 没有 `hourly`（或 JSON 被截断）时降级到备用源，
     * 否则界面会拿到一份「有气温、没有逐时」的半残数据。
     */
    internal fun parsePrimary(json: String): Pair<Snapshot, List<HourPoint>>? {
        val snapshot = parse(json) ?: return null
        val hourly = parseHourly(json)
        if (hourly.isEmpty()) return null
        return snapshot to hourly
    }

    /**
     * 解析 7Timer! 的 `dataseries`。
     *
     * 官方 `api.pl` **不给每个点的绝对时刻**，只给「模式起报时刻 `init`」+「相对 init 的小时数
     * `timepoint`」（实测 2026-11 的返回：`init=2026111606`、`timepoint=3,6,9,…`）；
     * 旧文档/部分镜像里还出现过 `time` 字段（形如 `2025111603`）。两种都认，且都**向下对齐到
     * 0/3/6/…/21 点的整 3 小时 UTC 网格**，免得界面上出现 `22时`、`1时` 这种不在网格上的标签。
     */
    internal fun parseSevenTimer(json: String): List<HourPoint> = runCatching {
        val root = JSONObject(json)
        val series = root.optJSONArray("dataseries") ?: return emptyList()
        val initEpoch = sevenTimerStampEpoch(root.optString("init"))
        (0 until series.length()).mapNotNull { index ->
            val item = series.optJSONObject(index) ?: return@mapNotNull null
            if (!item.has("temp2m")) return@mapNotNull null
            val epoch = sevenTimerStampEpoch(item.optString("time")) ?: run {
                val base = initEpoch ?: return@mapNotNull null
                val timepoint = item.optLong("timepoint", Long.MIN_VALUE)
                if (timepoint == Long.MIN_VALUE) return@mapNotNull null
                base + timepoint * 3600L
            }
            HourPoint(
                epochSeconds = alignToStep(epoch, Source.SEVEN_TIMER.stepHours),
                temperatureC = item.optDouble("temp2m", Double.NaN).let {
                    if (it.isNaN()) return@mapNotNull null else it.roundToInt()
                },
                code = wmoCodeOfSevenTimer(item.optString("weather")),
            )
        }.sortedBy { it.epochSeconds }
    }.getOrDefault(emptyList())

    /** `2025111603` / `2026111606` 这类 UTC 时刻串 → epoch 秒；解析不了返回 null。 */
    internal fun sevenTimerStampEpoch(stamp: String?): Long? = runCatching {
        val text = stamp?.trim().orEmpty()
        if (text.length != 10) return null
        LocalDateTime.parse(text, SEVEN_TIMER_STAMP).toEpochSecond(ZoneOffset.UTC)
    }.getOrNull()

    /**
     * 7Timer! 的天气词 → WMO 天气码（与主源共用同一套文案与图标）。
     *
     * 7Timer 用 `day`/`night` 后缀区分昼夜（`clearday` / `cloudynight`），先剥掉后缀再查表；
     * 表外的值按「多云」处理（宁可少报一个极端天气，也不要显示成晴）。
     */
    internal fun wmoCodeOfSevenTimer(weather: String?): Int {
        val key = weather.orEmpty().trim().lowercase(Locale.ROOT)
            .removeSuffix("day")
            .removeSuffix("night")
        return when (key) {
            "clear", "sunny" -> 0 // 晴
            "pcloudy" -> 2 // 多云
            "mcloudy", "cloudy", "overcast" -> 3 // 阴
            "humid", "fog", "foggy" -> 45 // 雾
            "lightrain", "drizzle", "oshower", "ishower", "shower", "showers" -> 80 // 阵雨/小雨
            "rain" -> 63 // 中雨
            "heavyrain" -> 65 // 大雨
            "lightsnow" -> 71 // 小雪
            "snow", "snowrain", "rainsnow", "sleet" -> 73 // 雪 / 雨夹雪
            "ts", "thunder", "thunderstorm" -> 95 // 雷雨
            else -> 2 // 未知 → 多云
        }
    }

    /** 从逐时序列里取「现在」的读数（7Timer 没有 current 块）：不晚于当前时刻的最后一个点。 */
    internal fun snapshotAt(points: List<HourPoint>, nowEpochSeconds: Long): Snapshot? {
        val point = points.lastOrNull { it.epochSeconds <= nowEpochSeconds } ?: points.firstOrNull() ?: return null
        return Snapshot(point.temperatureC, point.code)
    }

    /** 把时刻向下对齐到 [stepHours] 小时的整倍（UTC 网格：0/3/6/…/21 点）。 */
    internal fun alignToStep(epochSeconds: Long, stepHours: Int): Long {
        val step = stepHours.coerceAtLeast(1) * 3600L
        return epochSeconds - Math.floorMod(epochSeconds, step)
    }

    /**
     * 小组件要显示的时刻：从当前所在的 [stepHours] 小时块开始，按步长取 [count] 个（本地时区对齐）。
     * 返回的是 UTC 秒，可直接与 [HourPoint.epochSeconds] 对应。
     *
     * 只用于「一格数据都没有」时排占位符；有数据时用 [visibleSlots]。
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

    /**
     * 界面真正要画的那 6 格（首页大卡片与桌面卡片共用这一条规则）。
     *
     * - **首格永远是「现在」**：当前时刻之前最近的那个采样点（全都在未来时取第一个点）。
     *   它不是「当前整点」——3 小时源在 21:30 的「现在」是 20 点那一条读数。
     * - 之后按**数据源自己的步长**往后取：1 小时源是 现在/22时/23时/0时…，
     *   3 小时源是 现在/23时/2时/5时/8时/11时（取决于采样网格）。标签一律用该点的实际本地小时数。
     * - 没有数据时退回按步长对齐的理论网格，让格子照样排出来（内容显示占位符）。
     *
     * @param skip 跳过前面几格（桌面卡片的第二排逐时行接在第一排后面）。
     */
    internal fun visibleSlots(
        points: List<HourPoint>,
        nowEpochSeconds: Long,
        zoneOffsetSeconds: Int,
        count: Int,
        stepHours: Int,
        skip: Int = 0,
    ): List<Slot> {
        val step = stepHours.coerceAtLeast(1).toLong() * 3600L
        val offset = skip.coerceAtLeast(0) * step
        val anchor = points.lastOrNull { it.epochSeconds <= nowEpochSeconds }?.epochSeconds
            ?: points.firstOrNull()?.epochSeconds
        if (anchor == null) {
            // 没有数据：照样排 6 格占位符（内容由界面填 `-`）。
            // 1 小时源按**本地整点**对齐（用户看到的就是整点）；3 小时源按 UTC 的 0/3/6/…/21 点对齐
            // —— 与 7Timer! 的采样网格一致，数据一到标签不会整体跳一格。
            val shifted = nowEpochSeconds + offset
            val start = if (stepHours <= 1) {
                val local = shifted + zoneOffsetSeconds
                local - Math.floorMod(local, 3600L) - zoneOffsetSeconds
            } else {
                alignToStep(shifted, stepHours)
            }
            return (0 until count).map { index ->
                Slot(start + index * step, isNow = skip == 0 && index == 0)
            }
        }
        val start = anchor + offset
        return (0 until count).map { index ->
            Slot(start + index * step, isNow = skip == 0 && index == 0)
        }
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

    private fun needsRefresh(context: Context, place: Place, ignoreLowPrecisionThrottle: Boolean = false): Boolean {
        val prefs = prefs(context)
        // 没有实时值、或旧版本缓存里缺小时序列/来源/步长，都重新取一次。
        if (!prefs.contains(KEY_TEMP) || !prefs.contains(KEY_HOURLY)) return true
        if (prefs.getInt(KEY_SCHEMA, 0) < SCHEMA) return true
        if (!prefs.contains(KEY_SOURCE) || !prefs.contains(KEY_STEP)) return true
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
        // 低精度（备用源 3 小时粒度）：没到 30 分钟也想升级回 1 小时，按 10 分钟节流。
        val lowPrecision = isLowPrecision(
            source = Source.of(prefs.getString(KEY_SOURCE, null)),
            stepHours = prefs.getInt(KEY_STEP, Source.OPEN_METEO.stepHours),
        )
        return shouldRefresh(
            ageMillis = age,
            movedKm = moved,
            sinceAttemptMillis = sinceAttempt,
            lowPrecision = lowPrecision,
            ignoreLowPrecisionThrottle = ignoreLowPrecisionThrottle,
        )
    }

    /** 主源：Open-Meteo（1 小时粒度）。 */
    private fun fetchPrimary(place: Place): String? = httpGet(
        String.format(
            Locale.ROOT,
            "https://api.open-meteo.com/v1/forecast?latitude=%.4f&longitude=%.4f" +
                "&current=temperature_2m,weather_code" +
                "&hourly=temperature_2m,weather_code&forecast_days=2&past_days=1&timezone=UTC",
            place.latitude,
            place.longitude,
        ),
    )

    /** 备用源：7Timer!（civil 产品，3 小时粒度）。 */
    private fun fetchSevenTimer(place: Place): String? = httpGet(
        String.format(Locale.ROOT, SEVEN_TIMER_URL, place.longitude, place.latitude),
    )

    /** 取一段文本；网络错误 / 超时 / 非 2xx / 读流失败一律返回 null（都不抛给调用方）。 */
    private fun httpGet(url: String): String? = runCatching {
        val connection = (URL(url).openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = HTTP_TIMEOUT_MILLIS
            readTimeout = HTTP_TIMEOUT_MILLIS
        }
        try {
            if (connection.responseCode != HttpURLConnection.HTTP_OK) return null
            connection.inputStream.bufferedReader().use { it.readText() }
        } finally {
            connection.disconnect()
        }
    }.getOrNull()

    private fun save(
        context: Context,
        place: Place,
        snapshot: Snapshot,
        hourly: List<HourPoint>,
        source: Source,
    ) {
        prefs(context).edit()
            .putInt(KEY_TEMP, snapshot.temperatureC)
            .putInt(KEY_CODE, snapshot.code)
            .putString(KEY_HOURLY, encodeHourly(hourly))
            .putString(KEY_SOURCE, source.id)
            .putInt(KEY_STEP, source.stepHours)
            .putInt(KEY_SCHEMA, SCHEMA)
            .putFloat(KEY_LAT, place.latitude.toFloat())
            .putFloat(KEY_LON, place.longitude.toFloat())
            .putLong(KEY_TIME, System.currentTimeMillis())
            .apply()
        revisionCount.incrementAndGet()
    }

    /** 把这一次取数的结果写进诊断（`weather_source` / `weather_step` / `weather_age_minutes`）。 */
    private fun record(context: Context, source: Source, points: List<HourPoint>, result: String) {
        val age = ageMillis(context)
        DiagStore.recordWeather(
            context,
            listOf(
                "时间" to DiagStore.now(),
                "结果" to result,
                "weather_source" to source.id,
                "weather_step" to source.stepHours.toString(),
                "weather_age_minutes" to ((age ?: 0L) / 60_000L).toString(),
                "逐时点数" to points.size.toString(),
                "缓存状态" to ageNote(age),
            ),
        )
    }

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
