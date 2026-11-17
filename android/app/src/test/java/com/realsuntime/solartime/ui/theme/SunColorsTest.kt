package com.realsuntime.solartime.ui.theme

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 太阳卡白天配色的断言（`SunColors` 是纯 Kotlin，测试不依赖 Compose）。
 *
 * 这版的要求：太阳点**照搬时间轴「现在」圆点**的画法（一个渐变圆、三档色标 0/0.55/1、
 * alpha 1/1/0，内圈 55% 实心），
 * 只有颜色不同（白天 `#D9A520`、夜间 `#F5D68A`）；上一版的三层结构与硬描边都不许再出现。
 * 弧与夜晚虚线**不再比「谁更深」**，而是靠色相（暖金 vs 中性灰）区分。
 */
class SunColorsTest {

    private val cardSurface = SunColors.CARD_SURFACE_LIGHT
    private val nightDash = SunColors.NIGHT_DASH_LIGHT

    /** 弧再淡也要看得见：白卡上对比度 ≥ 1.4（用户下限），同时不能再回到「太沉」。 */
    @Test
    fun dayArcStaysVisibleOnTheWhiteCard() {
        val contrast = SunColors.contrastRatio(SunColors.DAY_ARC, cardSurface)
        assertTrue("白天弧对比度太低，看不见了：$contrast", contrast >= 1.4)
        // 上一版是 #D09464（≈2.52），这版必须明显更轻，但也不能淡到只剩一层白。
        assertTrue("白天弧还是偏重：$contrast", contrast <= 2.2)
    }

    /** 白天弧现在比夜晚虚线**更淡**（有意为之），两者靠色相区分：暖金的 r−b 比灰大 ≥ 0.15。 */
    @Test
    fun dayArcIsDistinguishedFromTheNightDashByHueNotDepth() {
        val arcContrast = SunColors.contrastRatio(SunColors.DAY_ARC, cardSurface)
        val dashContrast = SunColors.contrastRatio(nightDash, cardSurface)
        assertTrue(
            "白天弧现在应该比夜晚虚线更淡：弧 $arcContrast vs 虚线 $dashContrast",
            arcContrast < dashContrast,
        )
        val gap = SunColors.warmthGap(SunColors.DAY_ARC, nightDash)
        assertTrue("暖度差太小，色相上分不开：$gap", gap >= SunColors.MIN_WARMTH_GAP)
    }

    /** 太阳金点要比淡金弧明显：与弧的对比度 ≥1.3，且在白卡上比弧更显眼。 */
    @Test
    fun sunDotStandsOutFromThePaleArc() {
        val sunVsArc = SunColors.contrastRatio(SunColors.DAY_SUN, SunColors.DAY_ARC)
        assertTrue("亮金点与弧的对比度太低：$sunVsArc", sunVsArc >= 1.3)
        val sunVsCard = SunColors.contrastRatio(SunColors.DAY_SUN, cardSurface)
        val arcVsCard = SunColors.contrastRatio(SunColors.DAY_ARC, cardSurface)
        assertTrue("太阳点应比弧更明显：$sunVsCard vs $arcVsCard", sunVsCard > arcVsCard)
    }

    /** 上一版（三层结构）的硬描边已经整圈删除：alpha 常量必须是 0（不再有一圈实色边）。 */
    @Test
    fun sunDotHasNoHardRing() {
        assertTrue(
            "硬描边必须删除或 alpha < 0.15：${SunColors.SUN_DOT_RING_ALPHA}",
            SunColors.SUN_DOT_RING_ALPHA < 0.15f,
        )
        assertEquals("描边应已删除（0 = 不绘制）", 0f, SunColors.SUN_DOT_RING_ALPHA, 1e-6f)
    }

    /**
     * 太阳点就是**一个**单色渐变圆：三档色标全是同一个金，位置 / alpha 与时间轴圆点共用同一组数组。
     *
     * alpha 从中心到 55% 半径都是 1.0，之后线性降到 0：圆点中间是实心的，只有边缘柔化，
     * 不是「实心核心 + 外圈」两层。
     */
    @Test
    fun sunDotIsASingleGoldSoftDot() {
        assertEquals(0xFFD9A520.toInt(), SunColors.DAY_SUN)

        val stops = SunColors.sunDotStops(night = false)
        assertEquals(3, stops.size)
        stops.forEach {
            assertEquals("整颗点应只有一个金色", SunColors.DAY_SUN, it.argb)
        }
        assertEquals(SunColors.softDotStopPositions(), stops.map { it.position })
        assertEquals(SunColors.softDotStopAlphas(), stops.map { it.alpha })
        assertEquals(0f, stops.first().position, 1e-6f)
        assertEquals(1f, stops.first().alpha, 1e-6f)
        assertEquals(1f, stops.last().position, 1e-6f)
        assertEquals(0f, stops.last().alpha, 1e-6f)
    }

    /** 夜间换成夜金 `#F5D68A`（与 `DarkColors.primary` 一致），位置 / alpha 数组一个不许变。 */
    @Test
    fun nightDotUsesTheNightGoldWithTheSameShape() {
        assertEquals(0xFFF5D68A.toInt(), SunColors.NIGHT_SUN)

        val stops = SunColors.sunDotStops(night = true)
        assertEquals(3, stops.size)
        stops.forEach { assertEquals("夜间整颗点应只有一个夜金", SunColors.NIGHT_SUN, it.argb) }
        assertEquals(SunColors.softDotStopPositions(), stops.map { it.position })
        assertEquals(SunColors.softDotStopAlphas(), stops.map { it.alpha })
        assertEquals(0f, stops.last().alpha, 1e-6f)
    }

    /** 三个颜色的 RGB 距离：弧 / 点 / 虚线两两分得开（报告里也给出这组数）。 */
    @Test
    fun arcDotAndDashAreFarApartInRgb() {
        assertTrue(
            "弧与太阳点太接近：${SunColors.rgbDistance(SunColors.DAY_ARC, SunColors.DAY_SUN)}",
            SunColors.rgbDistance(SunColors.DAY_ARC, SunColors.DAY_SUN) > 120.0,
        )
        assertTrue(
            "弧与夜晚虚线太接近：${SunColors.rgbDistance(SunColors.DAY_ARC, nightDash)}",
            SunColors.rgbDistance(SunColors.DAY_ARC, nightDash) > 100.0,
        )
        assertTrue(
            "太阳点与夜晚虚线太接近：${SunColors.rgbDistance(SunColors.DAY_SUN, nightDash)}",
            SunColors.rgbDistance(SunColors.DAY_SUN, nightDash) > 80.0,
        )
    }

    /** 常量钉死：hex 与透明度别再被随手改掉（改配色要连注释与测试一起改）。 */
    @Test
    fun paletteConstantsArePinned() {
        assertEquals(0xFFE6CB9C.toInt(), SunColors.DAY_ARC)
        assertEquals(0xFFD9A520.toInt(), SunColors.DAY_SUN)
        assertEquals(0xFFF5D68A.toInt(), SunColors.NIGHT_SUN)
        assertEquals(0xFFFFFBF6.toInt(), SunColors.CARD_SURFACE_LIGHT)
        assertEquals(0xFF857468.toInt(), SunColors.NIGHT_DASH_LIGHT)
        assertEquals(0.0f, SunColors.SUN_DOT_RING_ALPHA, 1e-6f)
        assertEquals(0.7f, SunColors.DAY_TICK_ALPHA, 1e-6f)
        assertEquals(0.15, SunColors.MIN_WARMTH_GAP, 1e-9)
    }
}
