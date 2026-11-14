package com.realsuntime.solartime.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ZoneTableTest {

    private val fallback = 99_999

    @Test
    fun chinaIsAlwaysEightHoursWhateverTheLongitudeSays() {
        // 乌鲁木齐 87.6°E 按经度算会得到 +6，必须是 +8。
        assertEquals(8 * 3600, ZoneTable.offsetSeconds("cn", 87.6168, fallback))
        assertEquals(8 * 3600, ZoneTable.offsetSeconds("cn", 116.4074, fallback))
        assertEquals(8 * 3600, ZoneTable.offsetSeconds("hk", 114.1694, fallback))
    }

    @Test
    fun singleZoneCountriesComeStraightFromTheTable() {
        assertEquals(9 * 3600, ZoneTable.offsetSeconds("jp", 139.6917, fallback))
        assertEquals(5 * 3600 + 30 * 60, ZoneTable.offsetSeconds("in", 77.2090, fallback))
        assertEquals(0, ZoneTable.offsetSeconds("gb", -0.1276, fallback))
    }

    @Test
    fun multiZoneCountriesSplitByLongitude() {
        // 美国：纽约东岸 −5，洛杉矶西岸 −8
        assertEquals(-5 * 3600, ZoneTable.offsetSeconds("us", -74.0060, fallback))
        assertEquals(-8 * 3600, ZoneTable.offsetSeconds("us", -118.2437, fallback))
        assertEquals(-10 * 3600, ZoneTable.offsetSeconds("us", -157.8583, fallback))
        // 俄罗斯：莫斯科 +3，符拉迪沃斯托克 +10
        assertEquals(3 * 3600, ZoneTable.offsetSeconds("ru", 37.6173, fallback))
        assertEquals(10 * 3600, ZoneTable.offsetSeconds("ru", 131.8855, fallback))
        // 澳大利亚：珀斯 +8、达尔文 +9:30、悉尼 +10
        assertEquals(8 * 3600, ZoneTable.offsetSeconds("au", 115.8605, fallback))
        assertEquals(9 * 3600 + 30 * 60, ZoneTable.offsetSeconds("au", 130.8411, fallback))
        assertEquals(10 * 3600, ZoneTable.offsetSeconds("au", 151.2093, fallback))
        // 加拿大与巴西
        assertEquals(-8 * 3600, ZoneTable.offsetSeconds("ca", -123.1207, fallback))
        assertEquals(-5 * 3600, ZoneTable.offsetSeconds("ca", -79.3832, fallback))
        assertEquals(-3 * 3600, ZoneTable.offsetSeconds("br", -43.1729, fallback))
    }

    @Test
    fun unknownOrMissingCountryFallsBackToLongitude() {
        assertEquals(fallback, ZoneTable.offsetSeconds(null, 0.0, fallback))
        assertEquals(fallback, ZoneTable.offsetSeconds("", 0.0, fallback))
        assertEquals(fallback, ZoneTable.offsetSeconds("zz", 0.0, fallback))
        // 高德偶尔给纯数字 adcode，不能当成国家码
        assertEquals(fallback, ZoneTable.offsetSeconds("310000", 121.4737, fallback))
    }

    @Test
    fun countryCodeIsCaseAndWhitespaceInsensitive() {
        assertEquals(-5 * 3600, ZoneTable.offsetSeconds(" US ", -74.0060, fallback))
        assertEquals(8 * 3600, ZoneTable.offsetSeconds("CN", 116.4074, fallback))
    }

    @Test
    fun knowsOnlyRealCodes() {
        assertTrue(ZoneTable.knows("cn"))
        assertTrue(ZoneTable.knows("us"))
        assertFalse(ZoneTable.knows("zz"))
        assertFalse(ZoneTable.knows(null))
    }
}
