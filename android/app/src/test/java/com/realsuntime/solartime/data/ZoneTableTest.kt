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

    @Test
    fun presetsCarryCountryCodesThatResolveToTheirRealOffsets() {
        // 每个预设城市都必须带国家码：选中后标准时区靠它当场查表，不依赖逆地理编码。
        for (preset in Place.PRESETS) {
            assertTrue("${preset.labelResName} 缺少国家码", preset.countryCode != null)
            assertTrue("${preset.countryCode} 不在表里", ZoneTable.knows(preset.countryCode))
        }
        // 20 个常用城市：前 10 个是中国境内（含香港），后 10 个按 UTC 偏移从西到东排列。
        assertEquals(20, Place.PRESETS.size)
        val expected = listOf(
            -10 * 3600, // 檀香山
            -8 * 3600,  // 洛杉矶
            -5 * 3600,  // 纽约
            0,          // 伦敦
            3600,       // 巴黎
            4 * 3600,   // 迪拜
            5 * 3600 + 30 * 60, // 新德里
            9 * 3600,   // 东京
            8 * 3600,   // 新加坡
            10 * 3600,  // 悉尼
        )
        val overseas = Place.PRESETS.drop(10)
        assertEquals(expected.size, overseas.size)
        for ((index, preset) in overseas.withIndex()) {
            assertEquals(
                expected[index],
                ZoneTable.offsetSeconds(preset.countryCode, preset.longitude, fallback),
            )
        }
    }
}
