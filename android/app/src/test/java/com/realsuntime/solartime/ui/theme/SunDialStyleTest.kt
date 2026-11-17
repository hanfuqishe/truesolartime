package com.realsuntime.solartime.ui.theme

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 太阳圆盘「线更细 + 太阳点变柔和」这轮的几何常量断言（纯 Kotlin，不依赖 Compose）。
 *
 * 常量都放在 [SunColors] 里：颜色与线宽是同一张「圆盘外观规格表」，绘制代码只取常量，
 * 改粗细 / 改柔光半径要连这里、注释和测试一起改。
 */
class SunDialStyleTest {

    /** 白天弧 1.6dp、夜晚虚线 1.5dp：都比上一版的 2.5dp 细一档。 */
    @Test
    fun trajectoryLinesAreThin() {
        assertEquals(1.6f, SunColors.DAY_ARC_STROKE_DP, 1e-6f)
        assertEquals(1.5f, SunColors.NIGHT_ARC_STROKE_DP, 1e-6f)
        // 两条都不许再回到 2.5dp 那档「粗棒」。
        assertTrue(SunColors.DAY_ARC_STROKE_DP < 2.0f)
        assertTrue(SunColors.NIGHT_ARC_STROKE_DP < 2.0f)
    }

    /** 虚线间隔跟着线宽缩小：6/6dp → 4/4dp，否则线细了、间隔还大，看着仍是一段段粗点。 */
    @Test
    fun nightDashIntervalsShrinkWithTheLine() {
        assertEquals(4f, SunColors.NIGHT_DASH_ON_DP, 1e-6f)
        assertEquals(4f, SunColors.NIGHT_DASH_OFF_DP, 1e-6f)
        assertTrue(
            "实线段不该短于线宽，否则虚线会被画成一串点：${SunColors.NIGHT_DASH_ON_DP}dp",
            SunColors.NIGHT_DASH_ON_DP >= SunColors.NIGHT_ARC_STROKE_DP,
        )
    }

    /** 太阳点：核心实心 4dp，柔光外沿 2.1 倍（8.4dp），落在要求的 2.0~2.2 倍 / 8~9dp 区间。 */
    @Test
    fun sunDotCoreAndGlowRadiiMatchTheSpec() {
        assertEquals(4f, SunColors.SUN_DOT_CORE_RADIUS_DP, 1e-6f)
        assertEquals(2.1f, SunColors.SUN_DOT_GLOW_RATIO, 1e-6f)
        assertTrue(
            "柔光倍数应在 2.0~2.2 之间：${SunColors.SUN_DOT_GLOW_RATIO}",
            SunColors.SUN_DOT_GLOW_RATIO in 2.0f..2.2f,
        )
        assertEquals(8.4f, SunColors.SUN_DOT_GLOW_RADIUS_DP, 1e-4f)
        assertTrue(
            "柔光外沿应在 8~9dp 之间：${SunColors.SUN_DOT_GLOW_RADIUS_DP}",
            SunColors.SUN_DOT_GLOW_RADIUS_DP in 8f..9f,
        )
    }

    /**
     * 色标位置把核心半径翻译成渐变里的 0–1：`核心色标 × 柔光半径 = 4dp`。
     *
     * 0 到核心色标之间 alpha 恒为 1，所以 4dp 以内是实心的，4dp 之外才开始化开。
     */
    @Test
    fun gradientStopMarksTheCoreEdge() {
        assertEquals(1f / 2.1f, SunColors.SUN_DOT_CORE_STOP, 1e-6f)
        assertEquals(
            SunColors.SUN_DOT_CORE_RADIUS_DP,
            SunColors.SUN_DOT_CORE_STOP * SunColors.SUN_DOT_GLOW_RADIUS_DP,
            1e-4f,
        )
        assertTrue("核心色标必须在 0–1 之间：${SunColors.SUN_DOT_CORE_STOP}", SunColors.SUN_DOT_CORE_STOP in 0f..1f)
    }

    /** 色标按位置递增、首 0 尾 1：否则 `Brush.radialGradient` 会抛异常或画反。 */
    @Test
    fun gradientStopsAreOrderedFromCenterToEdge() {
        for (night in listOf(false, true)) {
            val stops = SunColors.sunDotStops(night)
            assertEquals("夜=$night 应有三档色标", 3, stops.size)
            assertEquals(0f, stops.first().position, 1e-6f)
            assertEquals(1f, stops.last().position, 1e-6f)
            stops.zipWithNext().forEach { (a, b) ->
                assertTrue("色标位置必须严格递增：${a.position} -> ${b.position}", b.position > a.position)
            }
            // 核心到中段完全不透明：4dp 以内必须是实心的。
            assertEquals("核心 alpha 应为 1", 0xFF, stops[0].argb ushr 24)
            assertEquals("中段 alpha 应为 1", 0xFF, stops[1].argb ushr 24)
            assertEquals("外沿 alpha 应为 0", 0, stops[2].argb ushr 24)
        }
    }
}
