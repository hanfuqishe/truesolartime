package com.realsuntime.solartime.data

import com.realsuntime.solartime.solar.SolarTimeMath
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
        // 22 个常用城市：前 10 个是中国境内（含香港）；第 11 个起是境外城市，
        // 末尾两个是极圈城市（摩尔曼斯克 / 中山站），用来验证极昼／极夜。
        assertEquals(22, Place.PRESETS.size)
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
            3 * 3600,   // 摩尔曼斯克：ru + 经度 33.08°E < 40°E → UTC+3
            8 * 3600,   // 中山站：国家码 cn → UTC+8（站上惯例，不用经度取整的 +5）
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

    @Test
    fun polarPresetsResolveToTheirDocumentedZones() {
        val murmansk = Place.PRESETS.first { it.labelResName == "city_murmansk" }
        assertEquals(68.97, murmansk.latitude, 1e-9)
        assertEquals(33.08, murmansk.longitude, 1e-9)
        assertEquals("ru", murmansk.countryCode)
        // 摩尔曼斯克在北极圈内，但不在俄罗斯的「+4 及以上」经度段：仍是莫斯科时间 UTC+3。
        assertEquals(3 * 3600, ZoneTable.offsetSeconds(murmansk.countryCode, murmansk.longitude, fallback))

        val zhongshan = Place.PRESETS.first { it.labelResName == "city_zhongshan" }
        assertEquals(-69.37, zhongshan.latitude, 1e-9)
        assertEquals(76.38, zhongshan.longitude, 1e-9)
        // 显式用 cn：中山站按中国站务惯例使用 UTC+8；若按经度取整会得到 +5。
        assertEquals("cn", zhongshan.countryCode)
        assertEquals(8 * 3600, ZoneTable.offsetSeconds(zhongshan.countryCode, zhongshan.longitude, fallback))
        assertEquals(5 * 3600, SolarTimeMath.standardZoneOffsetSeconds(zhongshan.latitude, zhongshan.longitude))
    }
}
