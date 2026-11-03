package com.realsuntime.solartime.solar

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Duration
import java.time.Instant

class ShichenTest {

    private fun seconds(hour: Int, minute: Int, second: Int = 0): Double =
        (hour * 3600 + minute * 60 + second).toDouble()

    @Test
    fun ziStartsAt23() {
        assertEquals(0, Shichen.indexOf(seconds(23, 0, 0)))
        assertEquals(0, Shichen.indexOf(seconds(0, 30, 0)))
        assertEquals(0, Shichen.indexOf(seconds(0, 59, 59)))
        assertEquals(1, Shichen.indexOf(seconds(1, 0, 0)))
        assertEquals(6, Shichen.indexOf(seconds(11, 0, 0)))
        assertEquals(6, Shichen.indexOf(seconds(12, 59, 59)))
        assertEquals(7, Shichen.indexOf(seconds(13, 0, 0)))
        assertEquals(11, Shichen.indexOf(seconds(22, 59, 59)))
    }

    @Test
    fun namesAndRangesFollowTheTraditionalOrder() {
        assertEquals("子时", Shichen.name(0))
        assertEquals("午时", Shichen.name(6))
        assertEquals("亥时", Shichen.name(11))
        assertEquals("23:00 – 01:00", Shichen.rangeText(0))
        assertEquals("11:00 – 13:00", Shichen.rangeText(6))
        assertEquals("21:00 – 23:00", Shichen.rangeText(11))
    }

    @Test
    fun halfAndQuarterWithinAShichen() {
        assertEquals("初", Shichen.halfLabel(seconds(11, 0, 0)))
        assertEquals(1, Shichen.quarterOfHalf(seconds(11, 0, 0)))
        assertEquals(4, Shichen.quarterOfHalf(seconds(11, 50, 0)))
        assertEquals("正", Shichen.halfLabel(seconds(12, 0, 0)))
        assertEquals(1, Shichen.quarterOfHalf(seconds(12, 0, 0)))
        assertEquals(2, Shichen.quarterOfHalf(seconds(12, 20, 0)))
    }

    @Test
    fun countdownToNextShichen() {
        assertEquals(5400.0, Shichen.secondsToNextShichen(seconds(23, 30, 0)), 1e-6)
        assertEquals(7200.0, Shichen.secondsToNextShichen(seconds(23, 0, 0)), 1e-6)
        assertEquals(60.0, Shichen.secondsToNextShichen(seconds(2, 59, 0)), 1e-6)
    }

    @Test
    fun nextBoundaryLandsOnAnOddHourOfTrueSolarTime() {
        val longitude = 116.4074
        val now = Instant.parse("2026-11-02T04:03:00Z")
        val boundary = Shichen.nextBoundary(now, longitude)

        val delta = Duration.between(now, boundary).seconds
        assertTrue("delta was $delta", delta in 1L..7200L)

        val trueSolarAtBoundary = SolarTimeMath.trueSolarSecondsOfDay(boundary, longitude)
        val toBoundary = (trueSolarAtBoundary + 3600.0) % 7200.0
        assertEquals(0.0, toBoundary, 2.0)
    }
}
