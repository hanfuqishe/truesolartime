package com.realsuntime.solartime.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

class CivicTimeTest {

    /** 冬令时基准时刻：纽约 EST、俄罗斯无夏令时。 */
    private val winter = Instant.parse("2026-01-15T12:00:00Z")

    @Test
    fun chinaUsesOneStandardTimeNotTheRegionalTzdataZone() {
        // 乌鲁木齐：tzdata 里 Asia/Urumqi 是 +6，官方时间仍是 +8（不能采信区域时区）。
        assertEquals(480, CivicTime.standardOffsetMinutes(43.83, 87.62, "cn", "Asia/Urumqi", winter))
        assertEquals(480, CivicTime.standardOffsetMinutes(39.90, 116.40, "cn", "Asia/Shanghai", winter))
        // 没有国家码时退回中国包围盒：乌鲁木齐仍在 +8。
        assertEquals(480, CivicTime.standardOffsetMinutes(43.83, 87.62, null, "Asia/Urumqi", winter))
        // 港澳台同样 +8。
        assertEquals(480, CivicTime.standardOffsetMinutes(22.32, 114.17, "hk", "Asia/Hong_Kong", winter))
        assertEquals(480, CivicTime.standardOffsetMinutes(25.03, 121.57, "tw", "Asia/Taipei", winter))
    }

    @Test
    fun chineseAntarcticStationsUseBeijingTime() {
        // 中山站：tzdata 的 Antarctica/Davis 是 +7，但中国站务按北京时间 +8。
        assertEquals(480, CivicTime.standardOffsetMinutes(-69.37, 76.38, "aq", "Antarctica/Davis", winter))
        // 长城站（Antarctica/Palmer 是 −3）、昆仑站、泰山站同为国家标准 +8。
        assertEquals(480, CivicTime.standardOffsetMinutes(-62.22, -58.96, "aq", null, winter))
        assertEquals(480, CivicTime.standardOffsetMinutes(-80.42, 77.12, "aq", null, winter))
        assertEquals(480, CivicTime.standardOffsetMinutes(-73.86, 76.97, "aq", null, winter))
        assertTrue(CivicTime.isChineseAntarcticStation(-69.37, 76.38))
        // 别国的南极站（如挪威 Troll，72.0°S 2.5°E）不套用中国站规则。
        assertFalse(CivicTime.isChineseAntarcticStation(-72.01, 2.53))
    }

    @Test
    fun otherCountriesUseTheirNationalStandardTime() {
        // 摩尔曼斯克：俄罗斯按经度分段（33.08°E < 40°E）→ UTC+3。
        assertEquals(180, CivicTime.standardOffsetMinutes(68.97, 33.08, "ru", null, winter))
        // 纽约：给了 tzId 就按 tzdata 规则 —— 冬令时 −300、夏令时 −240。
        assertEquals(-300, CivicTime.standardOffsetMinutes(40.71, -74.01, "us", "America/New_York", winter))
        assertEquals(
            -240,
            CivicTime.standardOffsetMinutes(
                40.71,
                -74.01,
                "us",
                "America/New_York",
                Instant.parse("2026-07-15T12:00:00Z"),
            ),
        )
        // 加德满都：+5:45，不能被取整成整小时。
        assertEquals(345, CivicTime.standardOffsetMinutes(27.70, 85.30, "np", null, winter))
        assertEquals(345, CivicTime.standardOffsetMinutes(27.70, 85.30, "np", "Asia/Kathmandu", winter))
    }

    @Test
    fun unknownCountryWithoutTzIdFallsBackToLongitude() {
        // 无国家码、无 tzId：按经度每 15° 取整（76.38°E → +5）。
        assertEquals(300, CivicTime.standardOffsetMinutes(10.0, 76.38, null, null, winter))
        assertEquals(28800, CivicTime.standardOffsetSeconds(43.83, 87.62, "cn", "Asia/Urumqi", winter))
    }
}
