package com.realsuntime.solartime.ui

import com.realsuntime.solartime.data.Place
import com.realsuntime.solartime.data.PlaceSource
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class HeaderBadgeTest {

    private val gpsLabel = "GPS"

    @Test
    fun showsGpsBadgeWhenFollowingGps() {
        assertTrue(HeaderBadge.showsGps(PlaceSource.GPS))
        assertEquals(gpsLabel, HeaderBadge.textFor(PlaceSource.GPS, gpsLabel))
    }

    @Test
    fun hidesBadgeForPresetCities() {
        // 预设城市的来源就是 MANUAL：标题行什么都不显示，地名只在大卡片里。
        val preset = Place.PRESETS.first()
        assertEquals(PlaceSource.MANUAL, preset.source)
        assertFalse(HeaderBadge.showsGps(preset.source))
        assertNull(HeaderBadge.textFor(preset.source, gpsLabel))
    }

    @Test
    fun hidesBadgeForManualCoordinates() {
        assertFalse(HeaderBadge.showsGps(PlaceSource.MANUAL))
        assertNull(HeaderBadge.textFor(PlaceSource.MANUAL, gpsLabel))
    }

    @Test
    fun hidesBadgeForDefaultPlaceBeforeFirstFix() {
        // 首启动还没拿到定位时是 DEFAULT：也不显示，等 GPS 定位到了再出现。
        assertFalse(HeaderBadge.showsGps(PlaceSource.DEFAULT))
        assertNull(HeaderBadge.textFor(PlaceSource.DEFAULT, gpsLabel))
    }
}
