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

    // ---- 顶部标签行：地名四档（与首页 SmallRowLayout.cityRowTier 一一对应）----
    // 统一取值：档 0 上限 12 个字宽（em）、档 1 上限 17、档 2 上限 21；再宽就是档 3。
    // 档 0 贴右 → 档 1 居中（收起「真太阳时」）→ 档 2 贴左（再收起 UTC）→ 档 3 同档 2 + 省略号。

    /** n 个字宽的纯汉字地名：每个汉字正好 1 em，用来卡边界值。 */
    private fun cjkEm(n: Int): String = "汉".repeat(n)

    private fun planFor(
        full: String,
        short: String = full,
        tier0: Float = 12f,
        tier1: Float = 17f,
        tier2: Float = 21f,
    ) = WidgetUpdater.planCityLabel(
        DistrictResolver.DistrictNames(full, short),
        fallback = "",
        maxTier0 = tier0,
        maxTier1 = tier1,
        maxTier2 = tier2,
    )

    @Test
    fun cityTextEmCountsFullWidthAsOneAndLatinAsNarrower() {
        // 汉字 = 1 个字宽，拉丁字母 = 0.55，空格 = 0.3
        assertEquals(4f, WidgetUpdater.cityTextEm("真太阳时"), 0.001f)
        assertEquals(2.2f, WidgetUpdater.cityTextEm("UTC+"), 0.001f)
        // 24 个拉丁字符 + 2 个汉字 + 4 个空格 ≈ 16.4 个字宽：
        // 以拉丁字母为主的长名字比同字数的汉字串窄得多，分档看宽度而不是字符数。
        val ny = WidgetUpdater.cityTextEm("Manhattan, 纽约, New York County")
        assertEquals(16.4f, ny, 0.01f)
        assertTrue(ny < WidgetUpdater.cityTextEm(cjkEm(22)))
    }

    @Test
    fun cityRowBudgetsFollowTheSameGeometryAsTheHeroCard() {
        // 400dp 的卡片、常规内边距 14dp：整行 372dp = 33.82 个字宽，左右两半各 16.91。
        // 档 0 要再从「左半」里扣掉 UTC(34dp)、两段之间的间距(8dp) 与地区与竖线之间的
        // 间隙(6dp, 与布局里 widget_city_default 的 marginEnd 一致)：16.91 − 3.09 − 0.73 − 0.55。
        val budgets = WidgetUpdater.cityRowBudgets(400f, compact = false)
        assertEquals(12.55f, budgets.tier0, 0.02f)
        assertEquals(24.55f, budgets.tier1, 0.02f)
        assertEquals(28.36f, budgets.tier2, 0.02f)
        // 档 0 的上限确实来自「左半」：比档 1 窄得多，同一段地名会先在档 0 放不下。
        assertTrue(budgets.tier0 < budgets.tier1)
        assertTrue(budgets.tier1 < budgets.tier2)
        // 极窄的卡片连右半都装不下「真太阳时 + 时辰」：档 0 不可能成立。
        assertTrue(WidgetUpdater.cityRowBudgets(120f, compact = false).tier0 < 0f)
        // 没量到宽度时按默认 5x2 卡片宽估算，给出的上限仍然可用。
        assertTrue(WidgetUpdater.cityRowBudgets(0f, compact = true).tier1 > 0f)
    }

    @Test
    fun tierZeroKeepsBothLabelsAndAlignsRight() {
        val plan = planFor("上海市黄浦区")
        assertEquals("上海市黄浦区", plan.text)
        assertEquals(0, plan.tier)
        assertTrue(plan.showUtc)
        assertTrue(plan.showSolarLabel)
        assertEquals(WidgetUpdater.CityAlign.END, plan.align)
    }

    @Test
    fun tierZeroAtExactFitBoundary() {
        // 正好 12 个字宽：UTC + 地区 + 真太阳时 + 时辰 都还放得下
        assertEquals(0, planFor(cjkEm(12)).tier)
    }

    @Test
    fun tierOneJustOverTheTierZeroBoundary() {
        // 13 个字宽：收起「真太阳时」，地区在 UTC 与时辰之间居中（UTC 还在）
        val plan = planFor(cjkEm(13))
        assertEquals(1, plan.tier)
        assertTrue(plan.showUtc)
        assertFalse(plan.showSolarLabel)
        assertEquals(WidgetUpdater.CityAlign.CENTER, plan.align)
    }

    @Test
    fun tierOneAtExactFitBoundary() {
        assertEquals(1, planFor(cjkEm(17)).tier)
    }

    @Test
    fun tierTwoJustOverTheTierOneBoundary() {
        // 18 个字宽：连 UTC 也收起，地区贴左、时辰仍贴整行最右
        val plan = planFor(cjkEm(18))
        assertEquals(2, plan.tier)
        assertFalse(plan.showUtc)
        assertFalse(plan.showSolarLabel)
        assertEquals(WidgetUpdater.CityAlign.START, plan.align)
    }

    @Test
    fun tierTwoAtExactFitBoundary() {
        assertEquals(2, planFor(cjkEm(21)).tier)
    }

    @Test
    fun tierThreeKeepsTheFullNameAndEllipsizes() {
        // 22 个字宽：连「地区 + 时辰」都放不下 —— 保持贴左，交给 ellipsize 的省略号，
        // 不再退成区县短名（与首页档 3 一致）。
        val long = cjkEm(22)
        val plan = planFor(long, short = "十九")
        assertEquals(3, plan.tier)
        assertEquals(long, plan.text)
        assertEquals(WidgetUpdater.CityAlign.START, plan.align)
        assertFalse(plan.showUtc)
        assertFalse(plan.showSolarLabel)
    }

    @Test
    fun latinHeavyNameIsJudgedByWidthNotCharacterCount() {
        // 29 个字符，但只有约 16.4 个字宽：按宽度是档 1，而不是按字符数（29 字）判成档 3。
        assertEquals(1, planFor("Manhattan, 纽约, New York County").tier)
    }

    @Test
    fun offlineFallbackNameUsesTierZero() {
        val plan = WidgetUpdater.planCityLabel(
            null,
            fallback = "乌鲁木齐",
            maxTier0 = 12f,
            maxTier1 = 17f,
            maxTier2 = 21f,
        )
        assertEquals("乌鲁木齐", plan.text)
        assertEquals(0, plan.tier)
        assertTrue(plan.showUtc)
        assertTrue(plan.showSolarLabel)
        assertEquals(WidgetUpdater.CityAlign.END, plan.align)
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
