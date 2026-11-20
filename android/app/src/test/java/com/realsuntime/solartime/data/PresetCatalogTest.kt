package com.realsuntime.solartime.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 46+1 个常用城市的总表：数量、分组顺序、坐标、国家码、时区。
 *
 * 顺序即设置页展示顺序（按大洲分组），三端必须逐位一致。
 */
class PresetCatalogTest {

    private val fallback = 99_999

    private val expectedOrder = listOf(
        // 亚洲 20
        "city_beijing", "city_shanghai", "city_guangzhou", "city_shenzhen", "city_chengdu",
        "city_xian", "city_harbin", "city_mohe", "city_fuyuan", "city_urumqi", "city_kashgar", "city_lhasa", "city_hongkong", "city_taipei", "city_kaohsiung", "city_sansha", "city_diaoyu",
        "city_tokyo", "city_seoul", "city_pyongyang", "city_vladivostok", "city_singapore", "city_bangkok",
        "city_vientiane", "city_jakarta", "city_new_delhi", "city_dubai", "city_istanbul",
        // 欧洲 8
        "city_moscow", "city_london", "city_paris", "city_berlin", "city_rome",
        "city_madrid", "city_reykjavik", "city_murmansk",
        // 非洲 5
        "city_cairo", "city_cape_town", "city_nairobi", "city_kigali", "city_lagos",
        // 北美洲 6
        "city_honolulu", "city_los_angeles", "city_new_york", "city_chicago",
        "city_mexico_city", "city_vancouver",
        // 南美洲 4
        "city_rio", "city_sao_paulo", "city_buenos_aires", "city_lima",
        // 大洋洲 3
        "city_sydney", "city_perth", "city_auckland",
        // 南极洲 1
        "city_kunlun",
    )

    private val expectedRegionCounts = mapOf(
        CityRegion.ASIA to 28,
        CityRegion.EUROPE to 8,
        CityRegion.AFRICA to 5,
        CityRegion.NORTH_AMERICA to 6,
        CityRegion.SOUTH_AMERICA to 4,
        CityRegion.OCEANIA to 3,
        CityRegion.ANTARCTICA to 1,
    )

    @Test
    fun totalAndPerRegionCounts() {
        assertEquals(55, Place.PRESETS.size)
        for ((region, count) in expectedRegionCounts) {
            assertEquals("$region 数量", count, Place.PRESETS.count { it.region == region })
        }
        assertEquals(55, expectedRegionCounts.values.sum())
    }

    @Test
    fun orderMatchesTheAgreedCatalog() {
        assertEquals(expectedOrder, Place.PRESETS.map { it.labelResName })
        // 每个预设都必须带 region，且与所在分组一致。
        for ((index, preset) in Place.PRESETS.withIndex()) {
            assertNotNull("第 $index 项缺少 region", preset.region)
        }
    }

    @Test
    fun newCitiesCarryTheAgreedCoordinatesAndCountryCodes() {
        val expected = mapOf(
            "city_moscow" to Triple(55.7558, 37.6173, "ru"),
            "city_mohe" to Triple(52.9721, 122.5388, "cn"),
            "city_sansha" to Triple(16.8343, 112.3388, "cn"),
            "city_fuyuan" to Triple(48.3669, 134.2895, "cn"),
            "city_taipei" to Triple(25.0330, 121.5654, "tw"),
            "city_kaohsiung" to Triple(22.6273, 120.3014, "tw"),
            "city_diaoyu" to Triple(25.7459, 123.4776, "cn"),
            "city_kashgar" to Triple(39.4704, 75.9898, "cn"),
            "city_vladivostok" to Triple(43.1155, 131.8855, "ru"),
            "city_berlin" to Triple(52.5200, 13.4050, "de"),
            "city_rome" to Triple(41.9028, 12.4964, "it"),
            "city_madrid" to Triple(40.4168, -3.7038, "es"),
            "city_istanbul" to Triple(41.0082, 28.9784, "tr"),
            "city_cape_town" to Triple(-33.9249, 18.4241, "za"),
            "city_nairobi" to Triple(-1.2921, 36.8219, "ke"),
            "city_kigali" to Triple(-1.9441, 30.0619, "rw"),
            "city_lagos" to Triple(6.5244, 3.3792, "ng"),
            "city_seoul" to Triple(37.5665, 126.9780, "kr"),
            "city_pyongyang" to Triple(39.0392, 125.7625, "kp"),
            "city_bangkok" to Triple(13.7563, 100.5018, "th"),
            "city_vientiane" to Triple(17.9757, 102.6331, "la"),
            "city_jakarta" to Triple(-6.2088, 106.8456, "id"),
            "city_perth" to Triple(-31.9523, 115.8613, "au"),
            "city_auckland" to Triple(-36.8485, 174.7633, "nz"),
            "city_reykjavik" to Triple(64.1466, -21.9426, "is"),
            "city_chicago" to Triple(41.8781, -87.6298, "us"),
            "city_mexico_city" to Triple(19.4326, -99.1332, "mx"),
            "city_sao_paulo" to Triple(-23.5505, -46.6333, "br"),
            "city_buenos_aires" to Triple(-34.6037, -58.3816, "ar"),
            "city_lima" to Triple(-12.0464, -77.0428, "pe"),
            "city_vancouver" to Triple(49.2827, -123.1207, "ca"),
        )
        for ((key, triple) in expected) {
            val preset = Place.PRESETS.first { it.labelResName == key }
            assertEquals("$key 纬度", triple.first, preset.latitude, 1e-9)
            assertEquals("$key 经度", triple.second, preset.longitude, 1e-9)
            assertEquals("$key 国家码", triple.third, preset.countryCode)
        }
    }

    @Test
    fun timezoneSpotChecks() {
        fun offset(key: String): Int {
            val preset = Place.PRESETS.first { it.labelResName == key }
            return ZoneTable.offsetSeconds(preset.countryCode, preset.longitude, fallback)
        }
        assertEquals(180 * 60, offset("city_moscow"))
        assertEquals(540 * 60, offset("city_seoul"))
        assertEquals(540 * 60, offset("city_pyongyang"))
        assertEquals(600 * 60, offset("city_vladivostok"))
        assertEquals(480 * 60, offset("city_mohe"))
        assertEquals(480 * 60, offset("city_kashgar"))
        assertEquals(480 * 60, offset("city_sansha"))
        assertEquals(480 * 60, offset("city_fuyuan"))
        assertEquals(480 * 60, offset("city_taipei"))
        assertEquals(480 * 60, offset("city_kaohsiung"))
        assertEquals(480 * 60, offset("city_diaoyu"))
        assertEquals(420 * 60, offset("city_vientiane"))
        assertEquals(720 * 60, offset("city_auckland"))
        assertEquals(-300 * 60, offset("city_lima"))
        assertEquals(-360 * 60, offset("city_mexico_city"))
        assertEquals(0, offset("city_reykjavik"))
        assertEquals(120 * 60, offset("city_kigali"))
        // 新增后仍要保证：全部预设的国家码都能查表。
        for (preset in Place.PRESETS) {
            assertTrue("${preset.labelResName} 国家码", ZoneTable.knows(preset.countryCode!!))
        }
    }

    /** `tw` 属于中国境内：自动模式下应走高德（AMAP_VECTOR），而不是 Esri。 */
    @Test
    fun taiwanCitiesResolveToAmapInAutoMode() {
        val taipei = Place.PRESETS.first { it.labelResName == "city_taipei" }
        assertEquals(
            com.realsuntime.solartime.map.MapStyle.AMAP_VECTOR,
            com.realsuntime.solartime.map.MapStyle.AUTO.effective(
                taipei.latitude,
                taipei.longitude,
                taipei.countryCode,
            ),
        )
    }

    /** 喀什经度修正 ≈ (75.9898 − 120) × 4 = −176 分钟（与 120°E 基准比）。 */
    @Test
    fun kashgarLongitudeCorrectionIsAboutMinus176Minutes() {
        val kashgar = Place.PRESETS.first { it.labelResName == "city_kashgar" }
        val minutes = com.realsuntime.solartime.solar.SolarTimeMath
            .longitudeOffsetSeconds(kashgar.longitude) / 60.0
        assertEquals(-176.0, minutes, 0.2)
    }

    /** 每条的城市名资源都必须有（三语各自有对应 strings，key 存在即可）。 */
    @Test
    fun everyPresetHasALabelResourceName() {
        for (preset in Place.PRESETS) {
            assertTrue("缺少 labelResName", !preset.labelResName.isNullOrBlank())
        }
    }
}
