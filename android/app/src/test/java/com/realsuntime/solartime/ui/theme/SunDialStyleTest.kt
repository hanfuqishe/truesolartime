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
        // 时间轴点：一半半径 2.75dp 处 alpha 0.45。
        assertEquals(2.75f, SunColors.SOFT_DOT_MID_RADIUS_DP, 1e-4f)
    }

    /** 色标位置数组完全相同：0 / 0.5 / 1（不是从核心半径起，而是从圆心 0 起）。 */
    @Test
    fun sunDotStopPositionsMatchTheTimelineDot() {
        val shared = SunColors.softDotStopPositions()
        assertEquals(listOf(0f, 0.5f, 1f), shared)
        for (night in listOf(false, true)) {
            val stops = SunColors.sunDotStops(night)
            assertEquals("夜=$night 应有三档色标", 3, stops.size)
            assertEquals("夜=$night 色标位置必须与时间轴相同", shared, stops.map { it.position })
            assertEquals(0f, stops.first().position, 1e-6f)
            assertEquals("渐变必须从圆心 0 开始", 0f, stops.first().position, 1e-6f)
        }
    }

    /** alpha 数组完全相同：1 / 0.45 / 0。 */
    @Test
    fun sunDotStopAlphasMatchTheTimelineDot() {
        val shared = SunColors.softDotStopAlphas()
        assertEquals(listOf(1f, 0.45f, 0f), shared)
        for (night in listOf(false, true)) {
            val stops = SunColors.sunDotStops(night)
            assertEquals("夜=$night alpha 数组必须与时间轴相同", shared, stops.map { it.alpha })
            assertEquals(1f, stops.first().alpha, 1e-6f)
            assertEquals(0.45f, stops[1].alpha, 1e-6f)
            assertEquals(0f, stops.last().alpha, 1e-6f)
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
