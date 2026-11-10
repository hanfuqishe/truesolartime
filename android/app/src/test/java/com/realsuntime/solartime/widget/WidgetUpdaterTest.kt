package com.realsuntime.solartime.widget

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WidgetUpdaterTest {

    @Test
    fun hidesSolarTimeWhileFollowingGpsWithoutAnyFix() {
        // 跟随 GPS，但从未拿到定位，当前也取不到 → 不显示真太阳时
        assertFalse(WidgetUpdater.hasValidFix(followingGps = true, hadFix = false, fixNow = false))
    }

    @Test
    fun showsSolarTimeOnceAFixIsAvailable() {
        assertTrue(WidgetUpdater.hasValidFix(followingGps = true, hadFix = false, fixNow = true))
        assertTrue(WidgetUpdater.hasValidFix(followingGps = true, hadFix = true, fixNow = false))
        assertTrue(WidgetUpdater.hasValidFix(followingGps = true, hadFix = true, fixNow = true))
    }

    @Test
    fun manualPlaceDoesNotNeedAnyFix() {
        assertTrue(WidgetUpdater.hasValidFix(followingGps = false, hadFix = false, fixNow = false))
    }
}
