package com.realsuntime.solartime.widget

import com.realsuntime.solartime.data.DistrictResolver
import com.realsuntime.solartime.data.PlaceSource
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
    fun keepsLabelsWhenTheNameFitsTheColumn() {
        val plan = WidgetUpdater.planCityLabel(
            DistrictResolver.DistrictNames("上海市宝山区", "宝山区"),
            fallback = "",
            maxNarrow = 10,
            maxNoLabel = 14,
            maxWide = 30,
        )
        assertEquals("上海市宝山区", plan.text)
        assertFalse(plan.wide)
        assertTrue(plan.showCivilLabel)
        assertTrue(plan.showSolarLabel)
    }

    @Test
    fun givesUpTheCivilLabelFirst() {
        // 12 字：左栏放不下（10），让出「标准时间」后（14）放得下
        val plan = WidgetUpdater.planCityLabel(
            DistrictResolver.DistrictNames("克孜勒苏柯尔克孜自治州", "克孜勒苏柯尔克孜自治州"),
            fallback = "",
            maxNarrow = 10,
            maxNoLabel = 14,
            maxWide = 30,
        )
        assertEquals("克孜勒苏柯尔克孜自治州", plan.text)
        assertFalse(plan.wide)
        assertFalse(plan.showCivilLabel)
        assertTrue(plan.showSolarLabel)
    }

    @Test
    fun spansBothColumnsWhenStillTooLong() {
        // 15 字：让出「标准时间」也不够，连「真太阳时」一起让出，改成跨栏一行
        val plan = WidgetUpdater.planCityLabel(
            DistrictResolver.DistrictNames("克孜勒苏柯尔克孜自治州阿图什市", "阿图什市"),
            fallback = "",
            maxNarrow = 10,
            maxNoLabel = 14,
            maxWide = 30,
        )
        assertEquals("克孜勒苏柯尔克孜自治州阿图什市", plan.text)
        assertTrue(plan.wide)
        assertFalse(plan.showCivilLabel)
        assertFalse(plan.showSolarLabel)
    }

    @Test
    fun fallsBackToDistrictWhenEvenTheWideRowOverflows() {
        val plan = WidgetUpdater.planCityLabel(
            DistrictResolver.DistrictNames("某个特别特别特别长的自治州某某自治县", "某某自治县"),
            fallback = "",
            maxNarrow = 10,
            maxNoLabel = 14,
            maxWide = 12,
        )
        assertEquals("某某自治县", plan.text)
        assertTrue(plan.wide)
    }

    @Test
    fun keepsBothLabelsForOfflineFallbackNames() {
        val plan = WidgetUpdater.planCityLabel(null, fallback = "乌鲁木齐", maxNarrow = 10, maxNoLabel = 14, maxWide = 30)
        assertEquals("乌鲁木齐", plan.text)
        assertTrue(plan.showCivilLabel)
        assertTrue(plan.showSolarLabel)
        assertFalse(plan.wide)
    }

    @Test
    fun manualPlaceIgnoresTheSystemFix() {
        // 手工指定坐标后，即便系统里有最近定位也不采用
        assertFalse(WidgetUpdater.followsSystemFix(PlaceSource.MANUAL))
        assertTrue(WidgetUpdater.followsSystemFix(PlaceSource.GPS))
        assertTrue(WidgetUpdater.followsSystemFix(PlaceSource.DEFAULT))
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
