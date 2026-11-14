package com.realsuntime.solartime.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.ZoneOffset

class WeatherRepositoryTest {

    @Test
    fun temperatureRangeUsesOnlyRequestedLocalDay() {
        val zone = ZoneId.of("Asia/Shanghai")
        // base = 2026-11-10T00:00Z = 本地 11-10 08:00
        val base = LocalDateTime.of(2026, 11, 10, 0, 0).toEpochSecond(ZoneOffset.UTC)
        val points = listOf(
            WeatherRepository.HourPoint(base - 9 * 3600, 8, 3), // 本地 11-09 23:00，不属于当天
            WeatherRepository.HourPoint(base, 11, 3), // 本地 11-10 08:00
            WeatherRepository.HourPoint(base + 3600, 16, 0), // 本地 11-10 09:00
            WeatherRepository.HourPoint(base + 86400, 5, 0), // 本地 11-11 08:00，不属于当天
        )
        val range = WeatherRepository.temperatureRange(points, LocalDate.of(2026, 11, 10), zone)
        assertEquals(16 to 11, range)
    }

    @Test
    fun temperatureRangeIsNullWithoutCoverage() {
        val zone = ZoneId.of("Asia/Shanghai")
        val base = LocalDateTime.of(2026, 11, 10, 0, 0).toEpochSecond(ZoneOffset.UTC)
        val points = listOf(WeatherRepository.HourPoint(base + 86400, 5, 0))
        assertNull(WeatherRepository.temperatureRange(points, LocalDate.of(2026, 11, 10), zone))
        assertNull(WeatherRepository.temperatureRange(emptyList(), LocalDate.of(2026, 11, 10), zone))
    }

    @Test
    fun parsesOpenMeteoResponse() {
        val json = """
            {"latitude":31.3181,"longitude":121.430275,"timezone":"Asia/Shanghai",
             "current":{"time":"2026-11-10T18:45","interval":900,
             "temperature_2m":9.3,"weather_code":2}}
        """.trimIndent()
        val snapshot = WeatherRepository.parse(json)
        assertEquals(9, snapshot?.temperatureC)
        assertEquals(2, snapshot?.code)
    }

    @Test
    fun roundsTemperature() {
        val json = """{"current":{"temperature_2m":-3.6,"weather_code":71}}"""
        assertEquals(-4, WeatherRepository.parse(json)?.temperatureC)
    }

    @Test
    fun ignoresMalformedOrEmptyPayloads() {
        assertNull(WeatherRepository.parse("not json"))
        assertNull(WeatherRepository.parse("""{"current":{}}"""))
        assertNull(WeatherRepository.parse("""{"latitude":1}"""))
    }

    @Test
    fun mapsWmoCodesToConditions() {
        assertEquals(WeatherRepository.Condition.CLEAR, WeatherRepository.conditionOf(0))
        assertEquals(WeatherRepository.Condition.PARTLY_CLOUDY, WeatherRepository.conditionOf(2))
        assertEquals(WeatherRepository.Condition.OVERCAST, WeatherRepository.conditionOf(3))
        assertEquals(WeatherRepository.Condition.FOG, WeatherRepository.conditionOf(45))
        assertEquals(WeatherRepository.Condition.DRIZZLE, WeatherRepository.conditionOf(53))
        assertEquals(WeatherRepository.Condition.RAIN, WeatherRepository.conditionOf(63))
        assertEquals(WeatherRepository.Condition.HEAVY_RAIN, WeatherRepository.conditionOf(65))
        assertEquals(WeatherRepository.Condition.SHOWERS, WeatherRepository.conditionOf(80))
        assertEquals(WeatherRepository.Condition.SHOWERS, WeatherRepository.conditionOf(81))
        assertEquals(WeatherRepository.Condition.HEAVY_RAIN, WeatherRepository.conditionOf(82))
        assertEquals(WeatherRepository.Condition.SNOW, WeatherRepository.conditionOf(71))
        assertEquals(WeatherRepository.Condition.HEAVY_SNOW, WeatherRepository.conditionOf(75))
        assertEquals(WeatherRepository.Condition.THUNDER, WeatherRepository.conditionOf(95))
        assertEquals(WeatherRepository.Condition.OVERCAST, WeatherRepository.conditionOf(1234))
    }

    @Test
    fun refreshesAfterThirtyMinutesOrFiveKilometres() {
        val fresh = 60_000L
        assertFalse(WeatherRepository.shouldRefresh(ageMillis = fresh, movedKm = 0.0))
        assertFalse(WeatherRepository.shouldRefresh(ageMillis = fresh, movedKm = 5.0))
        assertTrue(WeatherRepository.shouldRefresh(ageMillis = fresh, movedKm = 5.1))
        assertTrue(WeatherRepository.shouldRefresh(ageMillis = 31L * 60 * 1000, movedKm = 0.0))
        assertTrue(WeatherRepository.shouldRefresh(ageMillis = -1L, movedKm = 0.0))
    }

    /** 取数失败后按 5 分钟节流重试：刚失败过就先等一等，别每次回到前台都打一次网络。 */
    @Test
    fun retriesFailedFetchAfterFiveMinutes() {
        val stale = 40L * 60 * 1000
        assertFalse(
            WeatherRepository.shouldRefresh(stale, movedKm = 0.0, sinceAttemptMillis = 2L * 60 * 1000),
        )
        assertTrue(
            WeatherRepository.shouldRefresh(stale, movedKm = 0.0, sinceAttemptMillis = 6L * 60 * 1000),
        )
        // 从没尝试过（sinceAttempt 极大）→ 立刻取
        assertTrue(
            WeatherRepository.shouldRefresh(stale, movedKm = 0.0, sinceAttemptMillis = Long.MAX_VALUE),
        )
        // 没过期就永远不取，哪怕刚失败过
        assertFalse(
            WeatherRepository.shouldRefresh(60_000L, movedKm = 0.0, sinceAttemptMillis = 60_000L),
        )
    }

    @Test
    fun parsesHourlySeries() {
        val json = """
            {"hourly":{"time":["2026-11-10T00:00","2026-11-10T01:00"],
             "temperature_2m":[8.2,7.6],"weather_code":[1,2]}}
        """.trimIndent()
        val points = WeatherRepository.parseHourly(json)
        assertEquals(2, points.size)
        assertEquals(8, points[0].temperatureC)
        assertEquals(1_794_268_800L, points[0].epochSeconds)
        assertEquals(2, points[1].code)
    }

    @Test
    fun ignoresBrokenHourlyPayloads() {
        assertTrue(WeatherRepository.parseHourly("not json").isEmpty())
        assertTrue(WeatherRepository.parseHourly("""{"current":{}}""").isEmpty())
    }

    @Test
    fun hourlyCacheRoundTrips() {
        val points = listOf(
            WeatherRepository.HourPoint(1_762_732_800L, -3, 71),
            WeatherRepository.HourPoint(1_762_740_000L, 12, 0),
        )
        assertEquals(points, WeatherRepository.decodeHourly(WeatherRepository.encodeHourly(points)))
        assertTrue(WeatherRepository.decodeHourly("garbage").isEmpty())
    }

    @Test
    fun slotsStartAtCurrentHour() {
        // 2026-11-10 18:55 +08:00 → 本地对齐到 18:00，之后每小时一格
        val slots = WeatherRepository.slots(
            nowEpochSeconds = 1_794_308_100L,
            zoneOffsetSeconds = 8 * 3600,
            count = 6,
            stepHours = 1,
        )
        assertEquals(6, slots.size)
        assertEquals(1_794_304_800L, slots[0])
        assertEquals(3600L, slots[1] - slots[0])
        assertEquals(5 * 3600L, slots[5] - slots[0])
    }
}
