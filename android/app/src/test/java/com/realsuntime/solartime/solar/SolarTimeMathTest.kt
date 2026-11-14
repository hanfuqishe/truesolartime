package com.realsuntime.solartime.solar

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneOffset
import kotlin.math.abs

class SolarTimeMathTest {

    private val beijing = ZoneOffset.ofHours(8)

    @Test
    fun equationOfTimeMatchesPublishedValues() {
        val cases = mapOf(
            "2024-02-11T12:00:00Z" to -14.2,
            "2024-05-14T12:00:00Z" to 3.7,
            "2024-06-21T12:00:00Z" to -1.8,
            "2024-07-26T12:00:00Z" to -6.5,
            "2024-11-03T12:00:00Z" to 16.5,
        )
        cases.forEach { (iso, expectedMinutes) ->
            val seconds = SolarTimeMath.solarPosition(Instant.parse(iso)).equationOfTimeSeconds
            assertEquals(iso, expectedMinutes, seconds / 60.0, 0.5)
        }
    }

    @Test
    fun trueSolarOffsetInBeijingIsAboutTwoMinutesAheadInEarlyNovember() {
        val instant = Instant.parse("2026-11-02T04:03:00Z")
        val offset = SolarTimeMath.offsetFromBeijingSeconds(instant, 116.4074)
        assertEquals(127.0, offset, 20.0)
    }

    @Test
    fun offsetEqualsLongitudeCorrectionPlusEquationOfTime() {
        val instant = Instant.parse("2026-11-02T04:03:00Z")
        val position = SolarTimeMath.solarPosition(instant)
        val expected = SolarTimeMath.longitudeOffsetSeconds(116.4074) + position.equationOfTimeSeconds
        assertEquals(expected, SolarTimeMath.offsetFromBeijingSeconds(instant, 116.4074), 1e-6)
    }

    @Test
    fun trueSolarTimeAdvancesWithOneSecondPerSecond() {
        val longitude = 121.4737
        val start = Instant.parse("2026-11-02T00:00:00Z")
        val first = SolarTimeMath.trueSolarTime(start, longitude)
        val later = SolarTimeMath.trueSolarTime(start.plusSeconds(3600), longitude)
        val delta = Duration.between(first, later).seconds
        assertTrue("delta was $delta", delta in 3595L..3605L)
    }

    @Test
    fun beijingSunriseAndSunsetMatchAlmanac() {
        val june = SolarTimeMath.sunTimes(LocalDate.of(2024, 6, 21), 39.9042, 116.4074)
        assertEquals(SolarTimeMath.PolarState.NORMAL, june.polar)
        val sunriseInstant = requireInstant(june.sunrise)
        val sunsetInstant = requireInstant(june.sunset)
        val sunrise = sunriseInstant.atZone(beijing).toLocalTime()
        val sunset = sunsetInstant.atZone(beijing).toLocalTime()
        assertWithinMinutes(LocalTime.of(4, 46), sunrise, 3.0)
        assertWithinMinutes(LocalTime.of(19, 46), sunset, 3.0)

        val daylightHours = Duration.between(sunriseInstant, sunsetInstant).seconds / 3600.0
        assertEquals(15.0, daylightHours, 0.1)

        val december = SolarTimeMath.sunTimes(LocalDate.of(2024, 12, 21), 39.9042, 116.4074)
        val winterSunrise = requireInstant(december.sunrise).atZone(beijing).toLocalTime()
        assertWithinMinutes(LocalTime.of(7, 32), winterSunrise, 3.0)
    }

    @Test
    fun solarNoonMatchesTrueSolarNoonDefinition() {
        val times = SolarTimeMath.sunTimes(LocalDate.of(2026, 11, 2), 39.9042, 116.4074)
        val noonTrueSolar = SolarTimeMath.trueSolarTime(times.solarNoon, 116.4074)
        assertWithinMinutes(LocalTime.NOON, noonTrueSolar, 0.1)
    }

    @Test
    fun polarRegionsReportMidnightSunAndPolarNight() {
        val summer = SolarTimeMath.sunTimes(LocalDate.of(2024, 6, 21), 78.0, 15.0)
        assertEquals(SolarTimeMath.PolarState.MIDNIGHT_SUN, summer.polar)
        assertNull(summer.sunrise)

        val winter = SolarTimeMath.sunTimes(LocalDate.of(2024, 12, 21), 78.0, 15.0)
        assertEquals(SolarTimeMath.PolarState.POLAR_NIGHT, winter.polar)
        assertNull(winter.sunset)
    }

    @Test
    fun altitudeIsHighestNearTrueSolarNoon() {
        val noon = Instant.parse("2026-11-02T04:00:00Z")
        val noonAltitude = SolarTimeMath.solarAltitudeDegrees(noon, 39.9042, 116.4074)
        val midnightAltitude = SolarTimeMath.solarAltitudeDegrees(noon.plusSeconds(43_200), 39.9042, 116.4074)
        assertTrue(noonAltitude > midnightAltitude)
        assertTrue(noonAltitude in 20.0..40.0)
    }

    @Test
    fun offsetStaysWithinHalfADayAcrossTheWorld() {
        val instant = Instant.parse("2026-03-20T06:00:00Z")
        listOf(-179.9, -120.0, 0.0, 60.0, 116.4, 179.9).forEach { longitude ->
            val offset = SolarTimeMath.offsetFromBeijingSeconds(instant, longitude)
            assertTrue("offset $offset for $longitude", abs(offset) <= 43_200.0)
        }
    }

    @Test
    fun trueSolarOffsetRebuildsTrueSolarTimeFromEpoch() {
        // 小组件即用「系统时刻 + 该偏移」读出真太阳时，两者必须等价。
        val instant = Instant.parse("2026-11-02T04:03:00Z")
        val longitude = 87.6168
        val utcSecondsOfDay = instant.epochSecond % 86_400
        val expected = SolarTimeMath.trueSolarSecondsOfDay(instant, longitude)
        val rebuilt = ((utcSecondsOfDay + SolarTimeMath.trueSolarOffsetSeconds(instant, longitude)) % 86_400.0 + 86_400.0) % 86_400.0
        assertEquals(expected, rebuilt, 1e-6)
    }

    @Test
    fun chinaBoundingBoxCoversTheWholeCountry() {
        assertTrue(SolarTimeMath.isInChinaBbox(39.9042, 116.4074))
        assertTrue(SolarTimeMath.isInChinaBbox(43.8256, 87.6168))   // 乌鲁木齐
        assertTrue(SolarTimeMath.isInChinaBbox(22.3193, 114.1694))  // 香港
        assertTrue(SolarTimeMath.isInChinaBbox(31.2304, 121.4737))  // 上海
        assertTrue(SolarTimeMath.isInChinaBbox(18.5, 109.5))        // 海南南端
        assertFalse(SolarTimeMath.isInChinaBbox(35.6762, 139.6503)) // 东京
        assertFalse(SolarTimeMath.isInChinaBbox(1.3521, 103.8198))  // 新加坡（纬度在框外）
        assertFalse(SolarTimeMath.isInChinaBbox(55.7558, 37.6173))  // 莫斯科
    }

    @Test
    fun standardZoneOffsetUsesChinaRuleThenLongitude() {
        // 中国境内恒为 +8，即使按经度该是 +6
        assertEquals(8 * 3600, SolarTimeMath.standardZoneOffsetSeconds(43.8256, 87.6168))
        assertEquals(8 * 3600, SolarTimeMath.standardZoneOffsetSeconds(39.9042, 116.4074))
        // 境外按经度每 15° 取整
        assertEquals(9 * 3600, SolarTimeMath.standardZoneOffsetSeconds(35.6762, 139.6503))
        assertEquals(0, SolarTimeMath.standardZoneOffsetSeconds(51.5072, -0.1276))
        assertEquals(-5 * 3600, SolarTimeMath.standardZoneOffsetSeconds(40.7128, -74.0060))
        // 按经度取整后落在 UTC−12…+12，永远不会超出 java.time 的范围
        assertEquals(12 * 3600, SolarTimeMath.standardZoneOffsetSeconds(-16.5, 179.9))
        assertEquals(-12 * 3600, SolarTimeMath.standardZoneOffsetSeconds(0.0, -179.9))
    }

    private fun assertWithinMinutes(expected: LocalTime, actual: LocalTime, toleranceMinutes: Double) {
        val diff = abs(expected.toSecondOfDay() - actual.toSecondOfDay()).toDouble() / 60.0
        assertTrue("expected $expected but was $actual", diff <= toleranceMinutes)
    }

    private fun assertNotNull(instant: Instant?): Instant = requireInstant(instant)

    private fun requireInstant(instant: Instant?): Instant =
        instant ?: error("expected a non-null instant")
}
