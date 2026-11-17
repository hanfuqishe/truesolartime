package com.realsuntime.solartime.ui.theme

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 太阳卡白天配色的断言（`SunColors` 是纯 Kotlin，测试不依赖 Compose）。
 *
 * 这版的要求：太阳点分成**两层** —— 纯色实心核心（2.75dp、alpha 1.0）+ 外圈光晕（2.75→5.5dp、
 * alpha 0.35→0）；单层渐变的画法在真机上被渲染成均匀半透明，已废弃。
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

    /** 硬描边仍然没有回来：alpha 常量必须是 0（不再有一圈实色边）。 */
    @Test
    fun sunDotHasNoHardRing() {
        assertTrue(
            "硬描边必须删除或 alpha < 0.15：${SunColors.SUN_DOT_RING_ALPHA}",
            SunColors.SUN_DOT_RING_ALPHA < 0.15f,
        )
        assertEquals("描边应已删除（0 = 不绘制）", 0f, SunColors.SUN_DOT_RING_ALPHA, 1e-6f)
    }

    /**
     * 核心是**不透明纯色**：两套主题的核心色 ARGB 高字节都是 0xFF，alpha 常量算出来必须等于 1.0。
     *
     * 这就是真机上「弧线从点下面透出来」的修复点 —— 核心不再经过任何渐变 / alpha 混合。
     */
    @Test
    fun sunDotCoreIsOpaqueGold() {
        assertEquals(0xFF, SunColors.DAY_SUN ushr 24)
        assertEquals(0xFF, SunColors.NIGHT_SUN ushr 24)
        assertEquals(1f, SunColors.SUN_DOT_CORE_ALPHA, 1e-6f)
        assertEquals(SunColors.DAY_SUN, SunColors.sunDotCoreColor(night = false))
        assertEquals(SunColors.NIGHT_SUN, SunColors.sunDotCoreColor(night = true))
    }

    /** 光晕是同一个金的两档：内沿（核心外沿）alpha 0.35 → 外沿 0，位置从 2.75/5.5 = 0.5 起。 */
    @Test
    fun sunDotGlowFadesFromGoldToTransparent() {
        val innerStop = SunColors.SUN_DOT_GLOW_INNER_STOP

        val dayStops = SunColors.sunDotGlowStops(night = false)
        assertEquals(2, dayStops.size)
        assertEquals(innerStop, dayStops.first().position, 1e-6f)
        assertEquals(0.35f, dayStops.first().alpha, 1e-6f)
        assertEquals(SunColors.DAY_SUN, dayStops.first().argb)
        assertEquals(1f, dayStops.last().position, 1e-6f)
        assertEquals("外沿必须是 alpha 0", 0f, dayStops.last().alpha, 1e-6f)
        assertEquals(SunColors.DAY_SUN, dayStops.last().argb)

        SunColors.sunDotGlowStops(night = true).forEach {
            assertEquals("夜间光晕应同为夜金", SunColors.NIGHT_SUN, it.argb)
        }
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
