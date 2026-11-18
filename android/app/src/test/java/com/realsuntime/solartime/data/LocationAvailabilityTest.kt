package com.realsuntime.solartime.data

import com.realsuntime.solartime.solar.SolarTimeSnapshot
import com.realsuntime.solartime.solar.TimeFormat
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.time.LocalTime
import java.time.ZoneId
import java.util.TimeZone

/**
 * 「定位不可用（未知态）」的判定与未知态下的标准时间口径。
 *
 * 这里钉的是产品定义：
 * * 跟随 GPS + 没有 fix → 未知态；
 * * 跟随 GPS + 有 fix / 预设城市 / 手动坐标 → **不是**未知态（保持现状）；
 * * 未知态的标准时间用**系统时区**（不是上一次地点的时区）。
 */
class LocationAvailabilityTest {

    private val winter = Instant.parse("2026-01-15T03:00:00Z")

    @Test
    fun followingGpsWithoutFixIsUnknown() {
        assertTrue("跟随 GPS + 没定位 = 未知态", LocationAvailability.isUnknown(followGps = true, hasFix = false))
        assertFalse("跟随 GPS + 有定位 = 正常", LocationAvailability.isUnknown(followGps = true, hasFix = true))
        assertFalse("不跟随 GPS 时永远不会是未知态", LocationAvailability.isUnknown(followGps = false, hasFix = false))
        assertFalse(LocationAvailability.isUnknown(followGps = false, hasFix = true))
    }

    /** 预设城市与手动坐标都是用户明确选的位置：永远不进未知态。 */
    @Test
    fun presetCityAndManualCoordinatesNeverFallIntoUnknown() {
        assertFalse("预设城市 / 手动坐标（MANUAL）不跟随 GPS", LocationAvailability.followsGps(PlaceSource.MANUAL))
        assertTrue("GPS 地点就是跟随 GPS", LocationAvailability.followsGps(PlaceSource.GPS))
        // 默认坐标只是「还没选过」的占位：App 默认跟随 GPS，所以它算跟随。
        assertTrue("默认坐标算跟随 GPS", LocationAvailability.followsGps(PlaceSource.DEFAULT))

        // 用一个预设城市走一遍真实判定链：followGps=false 时即便 hasFix=false 也不是未知态。
        val preset = Place.PRESETS.first()
        assertFalse(LocationAvailability.isUnknown(LocationAvailability.followsGps(preset.source), false))
        val manual = Place(30.0, 120.0, PlaceSource.MANUAL, "手动设置")
        assertFalse(LocationAvailability.isUnknown(LocationAvailability.followsGps(manual.source), false))
        val gps = Place(31.2, 121.5, PlaceSource.GPS, "GPS")
        assertTrue(LocationAvailability.isUnknown(LocationAvailability.followsGps(gps.source), false))
        assertFalse(LocationAvailability.isUnknown(LocationAvailability.followsGps(gps.source), true))
    }

    /** 未知态的标准时间取系统时区：同一瞬间在不同默认时区下偏移不同。 */
    @Test
    fun standardTimeOffsetComesFromTheSystemZone() {
        assertEquals(9 * 3600, LocationAvailability.systemOffsetSeconds(winter, ZoneId.of("Asia/Tokyo")))
        assertEquals(8 * 3600, LocationAvailability.systemOffsetSeconds(winter, ZoneId.of("Asia/Shanghai")))
        assertEquals(-5 * 3600, LocationAvailability.systemOffsetSeconds(winter, ZoneId.of("America/New_York")))
        // 夏令时也照系统时区走：纽约 7 月是 −4。
        assertEquals(
            -4 * 3600,
            LocationAvailability.systemOffsetSeconds(
                Instant.parse("2026-07-15T12:00:00Z"),
                ZoneId.of("America/New_York"),
            ),
        )
        // 半时区不能被取整成整小时（加德满都 +5:45）。
        assertEquals(5 * 3600 + 45 * 60, LocationAvailability.systemOffsetSeconds(winter, ZoneId.of("Asia/Kathmandu")))
        assertEquals(LocalTime.of(12, 0), LocationAvailability.systemStandardTime(winter, ZoneId.of("Asia/Tokyo")))
        assertEquals(LocalTime.of(22, 0), LocationAvailability.systemStandardTime(winter, ZoneId.of("America/New_York")))
    }

    /**
     * 换掉 JVM 的默认时区，断言「标准时钟 + UTC 标签」在未知态真的跟着系统时区走。
     *
     * 这正是需求里那句「构造不同默认时区断言」：太阳相关的读数全部留空，但左栏那个标准时钟
     * 必须还是一个**诚实的**时刻 —— 系统时区的时刻（同一瞬间，东京 12:00 / 纽约 22:00 前一天）。
     */
    @Test
    fun unknownModeStandardClockFollowsTheDefaultTimeZone() {
        val original = TimeZone.getDefault()
        try {
            TimeZone.setDefault(TimeZone.getTimeZone("Asia/Tokyo"))
            val offset = LocationAvailability.systemOffsetSeconds(winter)
            assertEquals("默认时区换成东京后偏移应是 +9", 9 * 3600, offset)
            // 未知态就是拿这个偏移去构造 SolarSnapshot（lat/lon 传 0，太阳值不显示）。
            val snapshot = SolarTimeSnapshot.compute(winter, 0.0, 0.0, offset)
            assertEquals(LocalTime.of(12, 0), snapshot.localStandardTime)
            assertEquals("UTC 标签也要用系统时区", "UTC+9", TimeFormat.utcOffsetLabel(snapshot.localOffsetSeconds))

            TimeZone.setDefault(TimeZone.getTimeZone("America/New_York"))
            val nyOffset = LocationAvailability.systemOffsetSeconds(winter)
            assertEquals("默认时区换成纽约后偏移应是 −5", -5 * 3600, nyOffset)
            val ny = SolarTimeSnapshot.compute(winter, 0.0, 0.0, nyOffset)
            assertEquals("同一瞬间：纽约前一天 22:00", LocalTime.of(22, 0), ny.localStandardTime)
            assertEquals("UTC-5", TimeFormat.utcOffsetLabel(ny.localOffsetSeconds))
        } finally {
            TimeZone.setDefault(original)
        }
    }

    /** 未知态没有高度角，主题只能按钟点粗判昼夜：06:00–18:00 算白天。 */
    @Test
    fun daytimeIsJudgedByTheClockHour() {
        assertFalse(LocationAvailability.isDaytime(LocalTime.of(5, 59)))
        assertTrue(LocationAvailability.isDaytime(LocalTime.of(6, 0)))
        assertTrue(LocationAvailability.isDaytime(LocalTime.of(12, 0)))
        assertTrue(LocationAvailability.isDaytime(LocalTime.of(17, 59)))
        assertFalse(LocationAvailability.isDaytime(LocalTime.of(18, 0)))
        assertFalse(LocationAvailability.isDaytime(LocalTime.of(23, 30)))
    }
}
