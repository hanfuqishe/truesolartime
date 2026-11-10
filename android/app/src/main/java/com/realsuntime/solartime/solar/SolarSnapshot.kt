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
    val beijingTime: LocalTime,
    val beijingDate: LocalDate,
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
    val sunriseBeijing: LocalTime?,
    val sunsetBeijing: LocalTime?,
    val solarNoonBeijing: LocalTime?,
    val daylightSeconds: Long?,
    val polar: SolarTimeMath.PolarState,
    val altitudeDegrees: Double,
) {
    val isDay: Boolean get() = altitudeDegrees > -0.833
}

object SolarTimeSnapshot {

    private val BEIJING: ZoneOffset = ZoneOffset.ofHours(8)

    fun compute(instant: Instant, latitude: Double, longitude: Double): SolarSnapshot {
        val trueSolarSeconds = SolarTimeMath.trueSolarSecondsOfDay(instant, longitude)
        val beijingDateTime = instant.atZone(BEIJING)
        val sunTimes = SolarTimeMath.sunTimes(beijingDateTime.toLocalDate(), latitude, longitude)

        fun toTrueSolarTime(value: Instant?): LocalTime? = value?.let {
            LocalTime.ofSecondOfDay(
                SolarTimeMath.trueSolarSecondsOfDay(it, longitude).roundToLong().coerceIn(0, 86_399),
            )
        }

        fun toBeijingTime(value: Instant?): LocalTime? = value?.atZone(BEIJING)?.toLocalTime()

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
            daylightSeconds = daylightSeconds,
            polar = sunTimes.polar,
            altitudeDegrees = SolarTimeMath.solarAltitudeDegrees(instant, latitude, longitude),
        )
    }
}
