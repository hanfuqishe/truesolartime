package com.realsuntime.solartime.solar

import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneOffset
import kotlin.math.acos
import kotlin.math.asin
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.pow
import kotlin.math.roundToInt
import kotlin.math.roundToLong
import kotlin.math.sin
import kotlin.math.tan

/**
 * 真太阳时计算。
 *
 * 真太阳时 = 平太阳时 + 均时差，其中
 *   平太阳时(小时) = UTC 时刻 + 经度 / 15
 *   均时差 = 由地球轨道偏心率与黄赤交角引起的日差，采用 NOAA Solar Calculator 的近似公式，
 *            精度约 ±0.5 分钟，足够民用太阳时显示。
 */
object SolarTimeMath {

    private const val RAD = Math.PI / 180.0
    private const val DEG = 180.0 / Math.PI
    private const val SECONDS_PER_DAY = 86_400.0

    /** 北京时间所在的东八区经度。 */
    const val BEIJING_LONGITUDE = 120.0

    /** 北京时间的标准时区偏移（秒）。 */
    const val BEIJING_OFFSET_SECONDS: Int = 8 * 3600

    /** 太阳上中天时的天顶角修正（含大气折射与太阳视半径）。 */
    private const val SUNRISE_ZENITH_DEGREES = 90.833

    enum class PolarState { NORMAL, MIDNIGHT_SUN, POLAR_NIGHT }

    data class SolarPosition(
        /** 均时差：真太阳时减去平太阳时，单位秒。为正值表示日晷快于钟表。 */
        val equationOfTimeSeconds: Double,
        /** 太阳赤纬，单位度。 */
        val declinationDegrees: Double,
    )

    data class SunTimes(
        val sunrise: Instant?,
        val sunset: Instant?,
        val solarNoon: Instant,
        val polar: PolarState,
    )

    /** 由儒略世纪数推求太阳位置（均时差与赤纬）。 */
    fun solarPosition(instant: Instant): SolarPosition {
        val jd = instant.toEpochMilli() / 86_400_000.0 + 2_440_587.5
        val t = (jd - 2_451_545.0) / 36_525.0

        val meanLongitude = normalizeDegrees(280.46646 + t * (36_000.76983 + t * 0.0003032))
        val meanAnomaly = normalizeDegrees(357.52911 + t * (35_999.05029 - 0.0001537 * t))
        val eccentricity = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
        val omega = 125.04 - 1934.136 * t

        val meanObliquity = 23.0 + (26.0 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60.0) / 60.0
        val obliquity = meanObliquity + 0.00256 * cos(omega * RAD)

        val y = tan(obliquity * RAD / 2).pow(2)
        val l0 = meanLongitude * RAD
        val m = meanAnomaly * RAD
        // 括号内的量以弧度表示；乘以 DEG 得"度"，再乘 4 分/度、60 秒/分即为秒。
        val equationOfTimeRadians = y * sin(2 * l0) -
            2 * eccentricity * sin(m) +
            4 * eccentricity * y * sin(m) * cos(2 * l0) -
            0.5 * y * y * sin(4 * l0) -
            1.25 * eccentricity * eccentricity * sin(2 * m)

        val equationOfCenter = sin(m) * (1.914602 - t * (0.004817 + 0.000014 * t)) +
            sin(2 * m) * (0.019993 - 0.000101 * t) +
            sin(3 * m) * 0.000289
        val apparentLongitude = meanLongitude + equationOfCenter - 0.00569 - 0.00478 * sin(omega * RAD)
        val declination = asin(sin(obliquity * RAD) * sin(apparentLongitude * RAD)) * DEG

        return SolarPosition(
            equationOfTimeSeconds = equationOfTimeRadians * 240.0 * DEG,
            declinationDegrees = declination,
        )
    }

    /** 某瞬间在给定经度上的真太阳时，返回当天的秒数 [0, 86400)。 */
    fun trueSolarSecondsOfDay(instant: Instant, longitude: Double): Double {
        val utcMillisOfDay = ((instant.toEpochMilli() % 86_400_000L) + 86_400_000L) % 86_400_000L
        val utcSeconds = utcMillisOfDay / 1000.0
        val equationOfTime = solarPosition(instant).equationOfTimeSeconds
        return normalizeSeconds(utcSeconds + longitude * 240.0 + equationOfTime)
    }

    fun trueSolarTime(instant: Instant, longitude: Double): LocalTime =
        LocalTime.ofSecondOfDay(floor(trueSolarSecondsOfDay(instant, longitude)).toLong().coerceIn(0, 86_399))

    /** 北京时间（东八区固定偏移）当天的秒数。 */
    fun beijingSecondsOfDay(instant: Instant): Double =
        normalizeSeconds(instant.toEpochMilli() / 1000.0 + 8 * 3600.0)

    /**
     * 真太阳时相对北京时间的偏差，单位秒，范围 (-43200, 43200]。
     * 正值表示真太阳时走得快。
     */
    fun offsetFromBeijingSeconds(instant: Instant, longitude: Double): Double {
        val delta = trueSolarSecondsOfDay(instant, longitude) - beijingSecondsOfDay(instant)
        var normalized = (delta + SECONDS_PER_DAY * 1.5) % SECONDS_PER_DAY
        if (normalized <= 0) normalized += SECONDS_PER_DAY
        return normalized - SECONDS_PER_DAY / 2
    }

    /** 经度修正：当地经度相对东经 120° 的时差，单位秒。 */
    fun longitudeOffsetSeconds(longitude: Double): Double =
        (longitude - BEIJING_LONGITUDE) * 240.0

    /**
     * 粗略判断坐标是否在中国境内（含港澳台），用于时区兜底与逆地理编码分流。
     *
     * 只要经度 73–135、纬度 18–54，就当作中国：这样乌鲁木齐（87°E）不会因为
     * 按经度取整而被算成 UTC+6。
     */
    fun isInChinaBbox(latitude: Double, longitude: Double): Boolean =
        longitude in 73.0..135.0 && latitude in 18.0..54.0

    /**
     * 观测点所在地的**标准时区偏移**（相对 UTC，秒），不含夏令时。
     *
     * 中国全境统一 +8（含港澳台与新疆、西藏）；境外按经度每 15° 取整，限制在 UTC−12…+14。
     * 只知道坐标、不知道国家时可用的近似值；有国家码时优先用 `data.ZoneTable`（多时区大国要靠它）。
     */
    fun standardZoneOffsetSeconds(latitude: Double, longitude: Double): Int {
        if (isInChinaBbox(latitude, longitude)) return BEIJING_OFFSET_SECONDS
        val hours = (longitude / 15.0).roundToInt().coerceIn(-12, 14)
        return hours * 3600
    }

    /**
     * 当地真太阳时相对 **UTC** 的偏移，单位秒 = 经度 × 4 分/度 + 均时差。
     * 「系统时刻 + 该偏移」即以真太阳时读出的时刻（小组件时钟用它逐秒显示）。
     */
    fun trueSolarOffsetSeconds(instant: Instant, longitude: Double): Double =
        longitude * 240.0 + solarPosition(instant).equationOfTimeSeconds

    /** 太阳高度角，单位度（不含大气折射修正）。 */
    fun solarAltitudeDegrees(instant: Instant, latitude: Double, longitude: Double): Double {
        val position = solarPosition(instant)
        val hourAngle = (trueSolarSecondsOfDay(instant, longitude) / 3600.0 - 12.0) * 15.0 * RAD
        val lat = latitude * RAD
        val dec = position.declinationDegrees * RAD
        val sinAltitude = sin(lat) * sin(dec) + cos(lat) * cos(dec) * cos(hourAngle)
        return asin(sinAltitude.coerceIn(-1.0, 1.0)) * DEG
    }

    /** 计算某日（以其北京日期为准）的日出、日落与正午真太阳时。 */
    fun sunTimes(date: LocalDate, latitude: Double, longitude: Double): SunTimes {
        val reference = date.atTime(12, 0).toInstant(ZoneOffset.UTC)
        val position = solarPosition(reference)
        val lat = latitude * RAD
        val dec = position.declinationDegrees * RAD
        val equationOfTimeMinutes = position.equationOfTimeSeconds / 60.0

        val midnightUtc = date.atStartOfDay(ZoneOffset.UTC).toInstant()
        val solarNoonMinutes = 720.0 - 4.0 * longitude - equationOfTimeMinutes
        val solarNoon = midnightUtc.plusSeconds((solarNoonMinutes * 60).roundToLong())

        val cosHourAngle = cos(SUNRISE_ZENITH_DEGREES * RAD) / (cos(lat) * cos(dec)) - tan(lat) * tan(dec)
        if (cosHourAngle > 1.0 || cosHourAngle < -1.0) {
            return SunTimes(
                sunrise = null,
                sunset = null,
                solarNoon = solarNoon,
                polar = if (cosHourAngle > 1.0) PolarState.POLAR_NIGHT else PolarState.MIDNIGHT_SUN,
            )
        }

        val hourAngleDegrees = acos(cosHourAngle) * DEG
        val sunriseMinutes = 720.0 - 4.0 * (longitude + hourAngleDegrees) - equationOfTimeMinutes
        val sunsetMinutes = 720.0 + 4.0 * (hourAngleDegrees - longitude) - equationOfTimeMinutes

        return SunTimes(
            sunrise = midnightUtc.plusSeconds((sunriseMinutes * 60).roundToLong()),
            sunset = midnightUtc.plusSeconds((sunsetMinutes * 60).roundToLong()),
            solarNoon = solarNoon,
            polar = PolarState.NORMAL,
        )
    }

    private fun normalizeDegrees(value: Double): Double = ((value % 360.0) + 360.0) % 360.0

    private fun normalizeSeconds(value: Double): Double = ((value % SECONDS_PER_DAY) + SECONDS_PER_DAY) % SECONDS_PER_DAY
}
