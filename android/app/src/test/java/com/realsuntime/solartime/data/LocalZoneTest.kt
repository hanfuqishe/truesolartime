package com.realsuntime.solartime.data

import org.junit.Assert.assertEquals
import org.junit.Test
import java.time.ZoneOffset

class LocalZoneTest {

    @Test
    fun gmtLabelIsUnderstoodByTextClock() {
        // 纯 "-05:00" 会被 TimeZone.getTimeZone 当成 GMT；"GMT-5:00" 又会被 ZoneId.of 拒绝，
        // 所以必须带 GMT 前缀并把小时补成两位。
        assertEquals("GMT-05:00", LocalZone.gmtLabel(-5 * 3600))
        assertEquals("GMT+08:00", LocalZone.gmtLabel(8 * 3600))
        assertEquals("GMT+05:30", LocalZone.gmtLabel(5 * 3600 + 30 * 60))
        assertEquals("GMT+00:00", LocalZone.gmtLabel(0))
    }

    @Test
    fun labeledZoneKeepsTheOffset() {
        val zone = java.time.ZoneId.of(LocalZone.gmtLabel(-5 * 3600))
        assertEquals(-5 * 3600, zone.rules.getOffset(java.time.Instant.EPOCH).totalSeconds)
        val halfPast = java.time.ZoneId.of(LocalZone.gmtLabel(5 * 3600 + 30 * 60))
        assertEquals(5 * 3600 + 30 * 60, halfPast.rules.getOffset(java.time.Instant.EPOCH).totalSeconds)
    }

    @Test
    fun zoneOffsetClampsToTheJavaTimeRange() {
        assertEquals(14 * 3600, LocalZone.zoneOffset(14 * 3600).totalSeconds)
        assertEquals(-12 * 3600, LocalZone.zoneOffset(-12 * 3600).totalSeconds)
        assertEquals(18 * 3600, LocalZone.zoneOffset(30 * 3600).totalSeconds)
        assertEquals(ZoneOffset.ofHours(8), LocalZone.zoneOffset(8 * 3600))
    }
}
