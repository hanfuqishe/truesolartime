package com.realsuntime.solartime.solar

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.time.LocalTime

class SolarSnapshotTest {

    @Test
    fun snapshotCombinesAllSignalsForBeijing() {
        val snapshot = SolarTimeSnapshot.compute(
            instant = Instant.parse("2026-11-02T04:03:00Z"),
            latitude = 39.9042,
            longitude = 116.4074,
        )

        assertEquals(LocalTime.of(12, 3, 0), snapshot.beijingTime)
        assertEquals(6, snapshot.shichenIndex)
        assertEquals("午时", snapshot.shichenName)
        assertEquals("正", snapshot.shichenHalf)
        assertTrue(snapshot.offsetSeconds in 60.0..200.0)
        assertTrue(snapshot.secondsToNextShichen in 1L..7200L)
        assertNotNull(snapshot.sunriseTrueSolar)
        assertNotNull(snapshot.sunsetTrueSolar)
        assertTrue(snapshot.isDay)
    }

    @Test
    fun sunriseInTrueSolarTimeTracksTheSeasons() {
        // 春分前后太阳赤纬接近 0，日出真太阳时约 05:56（折射使日出略早于 6 点）
        val equinox = SolarTimeSnapshot.compute(
            instant = Instant.parse("2026-03-20T04:00:00Z"),
            latitude = 39.9042,
            longitude = 116.4074,
        )
        val equinoxSunrise = equinox.sunriseTrueSolar ?: error("missing equinox sunrise")
        assertTrue("equinox sunrise was $equinoxSunrise", minutesFromSix(equinoxSunrise) <= 10)

        // 11 月初太阳赤纬约 -15°，北京日出真太阳时在 06:46 附近
        val november = SolarTimeSnapshot.compute(
            instant = Instant.parse("2026-11-02T04:03:00Z"),
            latitude = 39.9042,
            longitude = 116.4074,
        )
        val novemberSunrise = november.sunriseTrueSolar ?: error("missing sunrise")
        assertTrue(
            "november sunrise was $novemberSunrise",
            kotlin.math.abs(minutesFromSix(novemberSunrise) - 46) <= 10,
        )
    }

    private fun minutesFromSix(time: LocalTime): Int =
        kotlin.math.abs(time.hour * 60 + time.minute - 6 * 60)

    @Test
    fun solarNoonInBeijingTimeDependsOnLongitude() {
        // 成都偏西约 16°，正午要在北京时间 12:47 左右才到来。
        val chengdu = SolarTimeSnapshot.compute(
            instant = Instant.parse("2026-11-03T04:00:00Z"),
            latitude = 30.5728,
            longitude = 104.0668,
        )
        assertEquals(LocalTime.of(12, 0), chengdu.solarNoonTrueSolar)
        assertTrue(chengdu.solarNoonBeijing!! in LocalTime.of(12, 40)..LocalTime.of(12, 55))

        // 北京几乎就在东八区中央经线附近，正午接近北京时间 12:00。
        val beijing = SolarTimeSnapshot.compute(
            instant = Instant.parse("2026-11-03T04:00:00Z"),
            latitude = 39.9042,
            longitude = 116.4074,
        )
        assertEquals(LocalTime.of(12, 0), beijing.solarNoonTrueSolar)
        assertTrue(beijing.solarNoonBeijing!! in LocalTime.of(11, 50)..LocalTime.of(12, 5))
    }

    @Test
    fun longitudesEastOf120RunAheadAndWestOf120RunBehind() {
        val instant = Instant.parse("2026-06-01T00:00:00Z")
        val sydney = SolarTimeSnapshot.compute(instant, -33.8688, 151.2093)
        val london = SolarTimeSnapshot.compute(instant, 51.5072, -0.1276)

        assertTrue(sydney.offsetSeconds > 0)
        assertTrue(london.offsetSeconds < 0)
        assertEquals(LocalTime.of(8, 0, 0), london.beijingTime)
    }
}
