package com.realsuntime.solartime.ui.theme

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 太阳圆盘的几何常量断言（纯 Kotlin，不依赖 Compose）：线宽 / 虚线、太阳点两层、时间轴圆点。
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

    /** 太阳点核心：半径 2.75dp 的**纯色**圆，颜色 alpha 必须是 1.0（真机上单层渐变曾整颗半透明）。 */
    @Test
    fun sunDotCoreIsSolidAndFullyOpaque() {
        assertEquals(2.75f, SunColors.SUN_DOT_CORE_RADIUS_DP, 1e-6f)
        assertEquals("核心颜色的 alpha 必须是 1.0", 1f, SunColors.SUN_DOT_CORE_ALPHA, 1e-6f)
        // 两套主题的核心色都在 ARGB 高字节写死 0xFF。
        assertEquals(0xFF, SunColors.DAY_SUN ushr 24)
        assertEquals(0xFF, SunColors.NIGHT_SUN ushr 24)
        assertEquals(SunColors.DAY_SUN, SunColors.sunDotCoreColor(night = false))
        assertEquals(SunColors.NIGHT_SUN, SunColors.sunDotCoreColor(night = true))
    }

    /**
     * 尺寸对齐时间轴：太阳核心 = 时间轴半径 × 0.5（2.75dp），光晕外沿 = 时间轴半径（5.5dp）。
     *
     * 这样两颗点整体一样大（直径 11dp），太阳点的实心部分也和时间轴点的实心部分一样大。
     */
    @Test
    fun sunDotMatchesTheTimelineDotSolidPart() {
        assertEquals(
            "太阳核心半径必须等于时间轴半径的一半",
            SunColors.SOFT_DOT_RADIUS_DP * 0.5f,
            SunColors.SUN_DOT_CORE_RADIUS_DP,
            1e-6f,
        )
        assertEquals(
            "太阳光晕外沿必须等于时间轴半径",
            SunColors.SOFT_DOT_RADIUS_DP,
            SunColors.SUN_DOT_GLOW_RADIUS_DP,
            1e-6f,
        )
    }

    /**
     * 外圈光晕：从**核心外沿 2.75dp** 开始（不是从圆心），到 5.5dp 结束，alpha 0.35 → 0。
     *
     * 渐变位置 0.5 = 2.75 / 5.5；换算回 dp 必须正好是核心半径，否则光晕会盖住核心或离得太远。
     */
    @Test
    fun sunDotGlowStartsAtTheCoreEdge() {
        val innerStop = SunColors.SUN_DOT_GLOW_INNER_STOP
        assertTrue("光晕起点不能是 0（那就盖住核心了）：$innerStop", innerStop > 0f)
        assertEquals(
            "起点位置 = 核心半径 / 光晕半径",
            SunColors.SUN_DOT_CORE_RADIUS_DP / SunColors.SUN_DOT_GLOW_RADIUS_DP,
            innerStop,
            1e-6f,
        )
        assertEquals("起点位置 = 0.5", 0.5f, innerStop, 1e-6f)
        assertEquals(
            "起点换算回 dp 必须正好是核心半径",
            SunColors.SUN_DOT_CORE_RADIUS_DP,
            innerStop * SunColors.SUN_DOT_GLOW_RADIUS_DP,
            1e-4f,
        )
        assertEquals(0.35f, SunColors.SUN_DOT_GLOW_ALPHA, 1e-6f)

        for (night in listOf(false, true)) {
            val stops = SunColors.sunDotGlowStops(night)
            assertEquals("夜=$night 光晕应有两个色标", 2, stops.size)
            assertEquals(innerStop, stops.first().position, 1e-6f)
            assertEquals(0.35f, stops.first().alpha, 1e-6f)
            assertEquals(1f, stops.last().position, 1e-6f)
            assertEquals("外沿 alpha 必须 0", 0f, stops.last().alpha, 1e-6f)
            assertTrue("色标位置必须严格递增", stops.last().position > stops.first().position)
            assertEquals(SunColors.sunDotCoreColor(night), stops.first().argb)
        }
    }

    /**
     * 时间轴「现在」圆点**恢复原曲线**：色标 0 / 0.5 / 1、alpha 1 / 0.45 / 0。
     *
     * 上一轮为了统一改成 0.55 / 1.0，用户说效果没以前好；这里钉住「只有圆心完全不透明」。
     */
    @Test
    fun timelineDotIsBackToItsOriginalCurve() {
        assertEquals(5.5f, SunColors.SOFT_DOT_RADIUS_DP, 1e-6f)
        assertEquals(listOf(0f, 0.5f, 1f), SunColors.softDotStopPositions())
        assertEquals(listOf(1f, 0.45f, 0f), SunColors.softDotStopAlphas())
        assertEquals(1f, SunColors.softDotAlphaAt(0f), 1e-6f)
        assertEquals("半径一半处应为 0.45", 0.45f, SunColors.softDotAlphaAt(0.5f), 1e-6f)
        assertEquals(0f, SunColors.softDotAlphaAt(1f), 1e-6f)
    }
}
