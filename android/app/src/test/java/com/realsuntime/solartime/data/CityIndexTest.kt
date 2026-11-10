package com.realsuntime.solartime.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CityIndexTest {

    @Test
    fun resolvesMainlandCities() {
        assertEquals("北京", CityIndex.nearest(39.9042, 116.4074, "zh")?.name)
        assertEquals("上海", CityIndex.nearest(31.3117, 121.3792, "zh")?.name)
        assertEquals("乌鲁木齐", CityIndex.nearest(43.8256, 87.6168, "zh")?.name)
        assertEquals("拉萨", CityIndex.nearest(29.6520, 91.1721, "zh")?.name)
        assertEquals("成都", CityIndex.nearest(30.5728, 104.0668, "zh")?.name)
        assertEquals("广州", CityIndex.nearest(23.1291, 113.2644, "zh")?.name)
        assertEquals("深圳", CityIndex.nearest(22.5431, 114.0579, "zh")?.name)
        assertEquals("香港", CityIndex.nearest(22.3193, 114.1694, "zh")?.name)
    }

    @Test
    fun resolvesCitiesOutsideChina() {
        assertEquals("London", CityIndex.nearest(51.5072, -0.1276, "en")?.name)
        assertEquals("Paris", CityIndex.nearest(48.8566, 2.3522, "en")?.name)
        assertEquals("New York", CityIndex.nearest(40.7128, -74.0060, "en")?.name)
        assertEquals("悉尼", CityIndex.nearest(-33.8688, 151.2093, "zh")?.name)
    }

    @Test
    fun chineseNameIsUsedForAnyChineseLocale() {
        assertEquals("上海", CityIndex.nearest(31.23, 121.47, "zh")?.name)
        assertEquals("上海", CityIndex.nearest(31.23, 121.47, "zh-Hant")?.name)
        assertEquals("Shanghai", CityIndex.nearest(31.23, 121.47, "en")?.name)
    }

    @Test
    fun distanceIsSmallForCityCentres() {
        val beijing = CityIndex.nearest(39.9042, 116.4074, "zh")
        assertTrue("distance was ${beijing?.distanceKm}", (beijing?.distanceKm ?: Double.MAX_VALUE) < 5.0)
    }

    @Test
    fun remotePlacesHaveNoCity() {
        assertNull(CityIndex.nearest(0.0, -140.0, "en"))
        assertNull(CityIndex.nearest(-45.0, -30.0, "en"))
    }
}
