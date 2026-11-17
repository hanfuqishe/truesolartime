package com.realsuntime.solartime.ui.theme

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 太阳圆盘的几何常量断言（纯 Kotlin，不依赖 Compose）：线宽 / 虚线、太阳点与时间轴圆点。
 *
 * 常量都放在 [SunColors] 里：颜色、线宽、圆点尺寸是同一张「圆盘外观规格表」，绘制代码只取常量。
 */
class SunDialStyleTest {

    /** 白天弧 1.6dp、夜晚虚线 1.5dp：都比最初的 2.5dp 细一档。 */
    @Test
    fun trajectoryLinesAreThin() {
        assertEquals(1.6f, SunColors.DAY_ARC_STROKE_DP, 1e-6f)
        assertEquals(1.5f, SunColors.NIGHT_ARC_STROKE_DP, 1e-6f)
        // 两条都不许再回到 2.5dp 那档「粗棒」。
        assertTrue(SunColors.DAY_ARC_STROKE_DP < 2.0f)
        assertTrue(SunColors.NIGHT_ARC_STROKE_DP < 2.0f)
    }

    /** 虚线间隔跟着线宽缩小：6/6dp → 4/4dp。 */
    @Test
    fun nightDashIntervalsShrinkWithTheLine() {
        assertEquals(4f, SunColors.NIGHT_DASH_ON_DP, 1e-6f)
        assertEquals(4f, SunColors.NIGHT_DASH_OFF_DP, 1e-6f)
        assertTrue(
            "实线段不该短于线宽，否则虚线会被画成一串点：${SunColors.NIGHT_DASH_ON_DP}dp",
            SunColors.NIGHT_DASH_ON_DP >= SunColors.NIGHT_ARC_STROKE_DP,
        )
    }

    /**
     * 用户最终裁定：太阳点与时间轴「现在」圆点**完全同参**，只允许颜色不同。
     *
     * 半径是同一个常量（[SunColors.SUN_DOT_RADIUS_DP] = [SunColors.SOFT_DOT_RADIUS_DP]），
     * 色标位置数组、alpha 数组也必须是同一份。
     */
    @Test
    fun sunDotUsesTheSameRadiusAsTheTimelineDot() {
        assertEquals(5.5f, SunColors.SOFT_DOT_RADIUS_DP, 1e-6f)
        assertEquals(
            "太阳点半径必须等于时间轴圆点半径（同一个常量）",
            SunColors.SOFT_DOT_RADIUS_DP,
            SunColors.SUN_DOT_RADIUS_DP,
            1e-6f,
        )
        // 实心内圈的外沿：5.5 × 0.55 = 3.025dp。
        assertEquals(3.025f, SunColors.SOFT_DOT_MID_RADIUS_DP, 1e-4f)
    }

    /** 色标位置数组完全相同：0 / 0.55 / 1（不是从核心半径起，而是从圆心 0 起）。 */
    @Test
    fun sunDotStopPositionsMatchTheTimelineDot() {
        val shared = SunColors.softDotStopPositions()
        assertEquals(listOf(0f, 0.55f, 1f), shared)
        for (night in listOf(false, true)) {
            val stops = SunColors.sunDotStops(night)
            assertEquals("夜=$night 应有三档色标", 3, stops.size)
            assertEquals("夜=$night 色标位置必须与时间轴相同", shared, stops.map { it.position })
            assertEquals(0f, stops.first().position, 1e-6f)
            assertEquals("渐变必须从圆心 0 开始", 0f, stops.first().position, 1e-6f)
        }
    }

    /** alpha 数组完全相同：1 / 1 / 0（内圈 55% 完全不透明，之后线性渐隐）。 */
    @Test
    fun sunDotStopAlphasMatchTheTimelineDot() {
        val shared = SunColors.softDotStopAlphas()
        assertEquals(listOf(1f, 1f, 0f), shared)
        for (night in listOf(false, true)) {
            val stops = SunColors.sunDotStops(night)
            assertEquals("夜=$night alpha 数组必须与时间轴相同", shared, stops.map { it.alpha })
            assertEquals(1f, stops.first().alpha, 1e-6f)
            assertEquals(1f, stops[1].alpha, 1e-6f)
            assertEquals(0f, stops.last().alpha, 1e-6f)
        }
    }

    /**
     * **半径一半（0.5）处仍然完全不透明**：这是这轮改动的核心。
     *
     * 旧曲线 0 / 0.5 / 1 + 1 / 0.45 / 0，半径一半就已经 45%；新曲线在 0.55 之前都是 1.0，
     * 所以圆点有一个实实在在的实心内圈，不会在米白卡片上散成一片。
     */
    @Test
    fun dotIsStillFullyOpaqueAtHalfTheRadius() {
        assertEquals("半径 0.5 处必须完全不透明", 1f, SunColors.softDotAlphaAt(0.5f), 1e-6f)
        assertEquals("实心内圈外沿 0.55 处仍是满色", 1f, SunColors.softDotAlphaAt(0.55f), 1e-6f)
        assertEquals(1f, SunColors.softDotAlphaAt(0f), 1e-6f)
        // 0.55 → 1 线性渐隐：0.775（正中）应是 0.5，边缘 0。
        assertEquals(0.5f, SunColors.softDotAlphaAt(0.775f), 1e-3f)
        assertEquals(0f, SunColors.softDotAlphaAt(1f), 1e-6f)
        // 整条曲线单调不增 —— 不许出现「先亮后暗再亮」的怪曲线。
        var previous = SunColors.softDotAlphaAt(0f)
        var position = 0f
        while (position <= 1f) {
            val alpha = SunColors.softDotAlphaAt(position)
            assertTrue("alpha 曲线必须单调不增：@$position -> $alpha < $previous", alpha <= previous + 1e-6f)
            previous = alpha
            position += 0.01f
        }
    }

    /** 唯一允许的差异是颜色：白天 `#D9A520`、夜间 `#F5D68A`，各自整颗点只有一个色。 */
    @Test
    fun sunDotColorsAreGoldAndNightGold() {
        SunColors.sunDotStops(night = false).forEach {
            assertEquals(SunColors.DAY_SUN, it.argb)
        }
        SunColors.sunDotStops(night = true).forEach {
            assertEquals(SunColors.NIGHT_SUN, it.argb)
        }
        assertEquals(0xFFD9A520.toInt(), SunColors.DAY_SUN)
        assertEquals(0xFFF5D68A.toInt(), SunColors.NIGHT_SUN)
    }
}
