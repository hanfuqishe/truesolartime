package com.realsuntime.solartime.solar

import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneOffset
import kotlin.math.floor
import kotlin.math.roundToLong

/** 某一瞬间、某一地点的完整太阳时快照，UI 只消费这个对象。 */
data class SolarSnapshot(
    val trueSolarTime: LocalTime,
    /** 北京时间（东八区固定偏移）此刻的读数，与 [localStandardTime] 是同一时刻的两种读法。 */
    val beijingTime: LocalTime,
    val beijingDate: LocalDate,
    /** 观测点所在地的**法定标准时间**（按 [localOffsetSeconds] 换算），界面左栏显示它。 */
    val localStandardTime: LocalTime,
    /** 观测点所在地标准时区相对 UTC 的偏移（秒）。 */
    val localOffsetSeconds: Int,
    /** 真太阳时比北京时间快多少秒，可正可负。 */
    val offsetSeconds: Double,
    val longitudeOffsetSeconds: Double,
    val equationOfTimeSeconds: Double,
    val shichenIndex: Int,
    val shichenName: String,
    val shichenRange: String,
    val shichenHalf: String,

    /** 时正（后一小时）为 true，时初为 false。 */
    val secondHalf: Boolean,
    val shichenQuarter: Int,
    val secondsToNextShichen: Long,
    val sunriseTrueSolar: LocalTime?,
    val sunsetTrueSolar: LocalTime?,
    val solarNoonTrueSolar: LocalTime?,
    /** 北京时间口径的日出／上中天／日落（保留给需要「与手机时钟一致」的场合）。 */
    val sunriseBeijing: LocalTime?,
    val sunsetBeijing: LocalTime?,
    val solarNoonBeijing: LocalTime?,
    /** 当地标准时口径的日出／上中天／日落，界面上的太阳卡片显示这三个。 */
    val sunriseLocal: LocalTime?,
    val sunsetLocal: LocalTime?,
    val solarNoonLocal: LocalTime?,
    val daylightSeconds: Long?,
    val polar: SolarTimeMath.PolarState,
    val altitudeDegrees: Double,
) {
    val isDay: Boolean get() = altitudeDegrees > -0.833
}

object SolarTimeSnapshot {

    private val BEIJING: ZoneOffset = ZoneOffset.ofHours(8)

    /**
     * @param zoneOffsetSeconds 观测点所在地的标准时区偏移（秒）。传 −1 表示由调用方没算过，
     *   这里按坐标兜底（中国境内 +8，境外按经度取整）。有国家码的调用方应先用
     *   `data.LocalZone.offsetSeconds` 算好再传进来，多时区大国才不会偏一个小时。
     */
    fun compute(
        instant: Instant,
        latitude: Double,
        longitude: Double,
        zoneOffsetSeconds: Int = -1,
    ): SolarSnapshot {
        val trueSolarSeconds = SolarTimeMath.trueSolarSecondsOfDay(instant, longitude)
        val beijingDateTime = instant.atZone(BEIJING)
        val sunTimes = SolarTimeMath.sunTimes(beijingDateTime.toLocalDate(), latitude, longitude)
        val localOffset = if (zoneOffsetSeconds >= 0) {
            zoneOffsetSeconds
        } else {
            SolarTimeMath.standardZoneOffsetSeconds(latitude, longitude)
        }
        val localZone = ZoneOffset.ofTotalSeconds(localOffset.coerceIn(-18 * 3600, 18 * 3600))
        val localDateTime = instant.atZone(localZone)

        fun toTrueSolarTime(value: Instant?): LocalTime? = value?.let {
            LocalTime.ofSecondOfDay(
                SolarTimeMath.trueSolarSecondsOfDay(it, longitude).roundToLong().coerceIn(0, 86_399),
            )
        }

        fun toBeijingTime(value: Instant?): LocalTime? = value?.atZone(BEIJING)?.toLocalTime()

        fun toLocalTime(value: Instant?): LocalTime? = value?.atZone(localZone)?.toLocalTime()

        val shichenIndex = Shichen.indexOf(trueSolarSeconds)
        val daylightSeconds = if (sunTimes.sunrise != null && sunTimes.sunset != null) {
            sunTimes.sunset.epochSecond - sunTimes.sunrise.epochSecond
        } else {
            null
        }

        return SolarSnapshot(
            trueSolarTime = LocalTime.ofSecondOfDay(floor(trueSolarSeconds).toLong().coerceIn(0, 86_399)),
            beijingTime = beijingDateTime.toLocalTime(),
            beijingDate = beijingDateTime.toLocalDate(),
            localStandardTime = localDateTime.toLocalTime(),
            localOffsetSeconds = localOffset,
            offsetSeconds = SolarTimeMath.offsetFromBeijingSeconds(instant, longitude),
            longitudeOffsetSeconds = SolarTimeMath.longitudeOffsetSeconds(longitude),
            equationOfTimeSeconds = SolarTimeMath.solarPosition(instant).equationOfTimeSeconds,
            shichenIndex = shichenIndex,
            shichenName = Shichen.name(shichenIndex),
            shichenRange = Shichen.rangeText(shichenIndex),
            shichenHalf = Shichen.halfLabel(trueSolarSeconds),
            secondHalf = Shichen.halfLabel(trueSolarSeconds) == "正",
            shichenQuarter = Shichen.quarterOfHalf(trueSolarSeconds),
            secondsToNextShichen = Shichen.secondsToNextShichen(trueSolarSeconds).roundToLong(),
            sunriseTrueSolar = toTrueSolarTime(sunTimes.sunrise),
            sunsetTrueSolar = toTrueSolarTime(sunTimes.sunset),
            solarNoonTrueSolar = toTrueSolarTime(sunTimes.solarNoon),
            sunriseBeijing = toBeijingTime(sunTimes.sunrise),
            sunsetBeijing = toBeijingTime(sunTimes.sunset),
            solarNoonBeijing = toBeijingTime(sunTimes.solarNoon),
            sunriseLocal = toLocalTime(sunTimes.sunrise),
            sunsetLocal = toLocalTime(sunTimes.sunset),
            solarNoonLocal = toLocalTime(sunTimes.solarNoon),
            daylightSeconds = daylightSeconds,
            polar = sunTimes.polar,
            altitudeDegrees = SolarTimeMath.solarAltitudeDegrees(instant, latitude, longitude),
        )
    }
}
