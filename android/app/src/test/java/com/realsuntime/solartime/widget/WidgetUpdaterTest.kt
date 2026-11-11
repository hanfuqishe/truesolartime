package com.realsuntime.solartime.widget

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WidgetUpdaterTest {

    @Test
    fun ticksRightAfterTheUpcomingMinuteBoundary() {
        // 刚过整分 59 秒 → 1 秒后刷新，另加写入余量
        assertEquals(
            1_000L + WidgetUpdater.TICK_MARGIN_MILLIS,
            WidgetUpdater.nextTickDelayMillis(nowMillis = 59_000L, civilOffsetMillis = 0L, solarOffsetMillis = 0L),
        )
    }

    @Test
    fun ticksOnWhicheverMinuteBoundaryComesFirst() {
        // 标准时间边界在 20 秒后，真太阳时偏移 +25 秒 → 真太阳时边界在 55 秒后：取标准时间那个
        assertEquals(
            20_000L + WidgetUpdater.TICK_MARGIN_MILLIS,
            WidgetUpdater.nextTickDelayMillis(nowMillis = 40_000L, civilOffsetMillis = 0L, solarOffsetMillis = 25_000L),
        )
        // 真太阳时偏移 +15 秒 → 真太阳时已过 55 秒，5 秒后就是它的边界：取真太阳时那个
        assertEquals(
            5_000L + WidgetUpdater.TICK_MARGIN_MILLIS,
            WidgetUpdater.nextTickDelayMillis(nowMillis = 40_000L, civilOffsetMillis = 0L, solarOffsetMillis = 15_000L),
        )
    }

    @Test
    fun ticksImmediatelyWhenAlreadyExactlyOnTheBoundary() {
        assertEquals(
            WidgetUpdater.TICK_MARGIN_MILLIS,
            WidgetUpdater.nextTickDelayMillis(nowMillis = 60_000L, civilOffsetMillis = 0L, solarOffsetMillis = 0L),
        )
    }

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
