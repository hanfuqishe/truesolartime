package com.realsuntime.solartime.widget

import com.realsuntime.solartime.data.TakeTimeSchedule
import com.realsuntime.solartime.data.TakeTemperature
import com.realsuntime.solartime.data.TakeBand
import com.realsuntime.solartime.data.DistrictResolver
import com.realsuntime.solartime.data.PlaceSource
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
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
    fun colorsSolarTimeOnlyInsideAKeyBand() {
        val schedule = TakeTimeSchedule(
            bands = listOf(TakeBand(900, 1020)),
            temperature = TakeTemperature.COLD_OR_MILD,
        )
        // 16:00 在 15:00-17:00 之内 → 绿色（白天用暗一档）
        assertEquals(KeyTimePalette.COLD_INK, WidgetUpdater.activeKeyColor(schedule, 16 * 3600.0, isDay = true))
        // 13:00 不在 → 默认色（null）
        assertNull(WidgetUpdater.activeKeyColor(schedule, 13 * 3600.0, isDay = true))
        // 没有关键时间数据 → 默认色
        assertNull(WidgetUpdater.activeKeyColor(null, 16 * 3600.0, isDay = true))
        // 没有温度标记 → 不着色
        assertNull(WidgetUpdater.activeKeyColor(schedule.copy(temperature = null), 16 * 3600.0, isDay = true))
    }

    @Test
    fun nightBandsUseBrighterShades() {
        val schedule = TakeTimeSchedule(
            bands = listOf(TakeBand(900, 1020)),
            temperature = TakeTemperature.COLD_OR_MILD,
        )
        // 同一时段，夜间换成亮一档的绿，与首页大卡片一致
        assertEquals(KeyTimePalette.COLD_NIGHT, WidgetUpdater.activeKeyColor(schedule, 16 * 3600.0, isDay = false))
    }

    @Test
    fun hotBandsUseRed() {
        val schedule = TakeTimeSchedule(
            bands = listOf(TakeBand(600, 720)),
            temperature = TakeTemperature.HOT_OR_MILD,
        )
        assertEquals(KeyTimePalette.HOT_INK, WidgetUpdater.activeKeyColor(schedule, 11 * 3600.0, isDay = true))
        assertEquals(KeyTimePalette.HOT_NIGHT, WidgetUpdater.activeKeyColor(schedule, 11 * 3600.0, isDay = false))
    }

    @Test
    fun domesticLaunchersNeedTheManualPinPath() {
        // 小米/红米：requestPinAppWidget 返回 true 但桌面不真的添加
        assertTrue(WidgetUpdater.pinNeedsManualFallback("Xiaomi", "Redmi"))
        assertTrue(WidgetUpdater.pinNeedsManualFallback("Redmi", "Redmi"))
        assertTrue(WidgetUpdater.pinNeedsManualFallback("POCO", "POCO"))
        // 华为/荣耀：桌面只提示「当前窗口已满」
        assertTrue(WidgetUpdater.pinNeedsManualFallback("HUAWEI", "HUAWEI"))
        assertTrue(WidgetUpdater.pinNeedsManualFallback("HONOR", "HONOR"))
        // 原生/其他厂商：仍按「桌面没空间」提示
        assertFalse(WidgetUpdater.pinNeedsManualFallback("Google", "google"))
        assertFalse(WidgetUpdater.pinNeedsManualFallback("samsung", "samsung"))
        assertFalse(WidgetUpdater.pinNeedsManualFallback(null, null))
    }

    @Test
    fun manualPlaceIgnoresTheSystemFix() {
        // 手工指定坐标后，即便系统里有最近定位也不采用
        assertFalse(WidgetUpdater.followsSystemFix(PlaceSource.MANUAL))
        assertTrue(WidgetUpdater.followsSystemFix(PlaceSource.GPS))
        assertTrue(WidgetUpdater.followsSystemFix(PlaceSource.DEFAULT))
    }

    @Test
    fun solarSecondMatchesTheChronometer() {
        // Chronometer 在整秒边界翻页、两次翻页之间保持旧值，等价于向下取整
        assertEquals(32L, WidgetUpdater.solarSecondOf(32_400L))
        assertEquals(32L, WidgetUpdater.solarSecondOf(32_500L))
        assertEquals(32L, WidgetUpdater.solarSecondOf(32_671L))
        assertEquals(0L, WidgetUpdater.solarSecondOf(499L))
        assertEquals(0L, WidgetUpdater.solarSecondOf(500L))
        assertEquals(0L, WidgetUpdater.solarSecondOf(999L))
        // 整分边界
        assertEquals(59L, WidgetUpdater.solarSecondOf(59_400L))
        // 一天的最后一刻不能溢出成 86400
        assertEquals(86_399L, WidgetUpdater.solarSecondOf(86_399_600L))
        assertEquals(0L, WidgetUpdater.solarSecondOf(0L))
    }

    @Test
    fun keepsChronometerBaseWhileThePhaseIsUnchanged() {
        val base = 1_234_000L
        // 同一分钟内相差几毫秒：相位没变，不能重发（重发会让秒提前跳一下）
        assertFalse(WidgetUpdater.shouldResetChronometer(base + 7, base, force = false))
        assertFalse(WidgetUpdater.shouldResetChronometer(base - 30, base, force = false))
        // 跨过整分：基准相差一个整分，相位仍然一致
        assertFalse(WidgetUpdater.shouldResetChronometer(base, base - 60_000L, force = false))
        assertFalse(WidgetUpdater.shouldResetChronometer(base, base + 60_000L, force = false))
        // 偏移量真的变了（换位置 / 时区设置）：必须重发
        assertTrue(WidgetUpdater.shouldResetChronometer(base + 600, base, force = false))
        assertTrue(WidgetUpdater.shouldResetChronometer(base - 900, base, force = false))
        // 首次下发、以及宿主强制重建
        assertTrue(WidgetUpdater.shouldResetChronometer(base, null, force = false))
        assertTrue(WidgetUpdater.shouldResetChronometer(base, base, force = true))
    }

    /**
     * 模拟 `Chronometer` 的算术，验证「不重发 base」确实消除了秒忽大忽小。
     *
     * `Chronometer.updateText` = `Math.round((now - base) / 1000f)`，走时回调按
     * `1000 - ((now - base) % 1000) + 1` 排下一次，即永远落在「base + 整秒 + 1ms」。
     * 界面每秒只看得到两个值：我们下发 base 的那一刻，以及之后的每次走时回调。
     */
    private fun chronometerSecondDurations(alwaysReset: Boolean, refreshPhaseMillis: Long): List<Long> {
        val minuteStart = 0L
        var base = minuteStart
        var shownAt = 0L
        var shown = 0L
        val durations = mutableListOf<Long>()
        var nextRefresh = refreshPhaseMillis
        var nextTick = 1L
        while (nextRefresh < 60_000L) {
            val at = minOf(nextRefresh, nextTick)
            if (at == nextRefresh) {
                // 刷新时算出的基准永远是「当前真太阳时整分」，相位本身并没有变
                val desired = at - at % 60_000L
                if (alwaysReset || WidgetUpdater.shouldResetChronometer(desired, base, force = false)) {
                    base = desired
                    val value = Math.round((at - base) / 1000.0)
                    if (value != shown) {
                        durations += at - shownAt
                        shownAt = at
                        shown = value
                    }
                    // setBase 会立刻 updateText，并重新按时基排下一次走时
                    nextTick = base + (Math.floorDiv(at - base, 1000L) + 1) * 1000L + 1
                }
                nextRefresh += 15_000L
            } else {
                val value = Math.round((at - base) / 1000.0)
                if (value != shown) {
                    durations += at - shownAt
                    shownAt = at
                    shown = value
                }
                nextTick += 1000L
            }
        }
        return durations
    }

    @Test
    fun extraRefreshesNoLongerStretchOrShrinkTheSecond() {
        // 每次刷新都无条件重发 base：刷新点落在某一秒的后半段时，下一秒被提前显示
        val jittery = chronometerSecondDurations(alwaysReset = true, refreshPhaseMillis = 700L)
        assertEquals(listOf(700L, 1301L, 1000L), jittery.take(3))

        // 相位不变就不重发：每一秒都稳稳占满 1 秒
        val steady = chronometerSecondDurations(alwaysReset = false, refreshPhaseMillis = 700L)
        assertTrue("秒长应均匀，实际 $steady", steady.all { it == 1_000L || it == 1_001L })
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
