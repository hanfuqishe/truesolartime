package com.realsuntime.solartime.ui.theme

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 太阳卡白天配色的断言（`SunColors` 是纯 Kotlin，测试不依赖 Compose）。
 *
 * 这版的要求：白天弧改成很淡的「路径示意」金，太阳点改成更实的金；
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

    /**
     * 太阳点是**亮金**（用户点名要的金色），与淡金弧的对比度只要求 ≥1.3；
     * 真正把点从弧里「切」出来的是外面那圈深金描边（见下一条）。
     */
    @Test
    fun sunDotStandsOutFromThePaleArc() {
        val sunVsArc = SunColors.contrastRatio(SunColors.DAY_SUN, SunColors.DAY_ARC)
        assertTrue("亮金点与弧的对比度太低：$sunVsArc", sunVsArc >= 1.3)
        val sunVsCard = SunColors.contrastRatio(SunColors.DAY_SUN, cardSurface)
        val arcVsCard = SunColors.contrastRatio(SunColors.DAY_ARC, cardSurface)
        assertTrue("太阳点应比弧更明显：$sunVsCard vs $arcVsCard", sunVsCard > arcVsCard)
    }

    /** 亮金点靠 50% 的深金细描边与淡金弧分离：描边色与弧的对比度 ≥2.5。 */
    @Test
    fun sunDotRingSeparatesTheDotFromTheArc() {
        val ringVsArc = SunColors.contrastRatio(SunColors.DAY_SUN_RING, SunColors.DAY_ARC)
        assertTrue("描边与弧的对比度不够，点会糊进弧里：$ringVsArc", ringVsArc >= 2.5)
        // 描边比填充深：这样「金点 + 深边」才有层次，而不是整点变暗。
        assertTrue(
            "描边应该比填充更深",
            SunColors.relativeLuminance(SunColors.DAY_SUN_RING) <
                SunColors.relativeLuminance(SunColors.DAY_SUN),
        )
        assertEquals(0.5f, SunColors.DAY_SUN_RING_ALPHA, 1e-6f)
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
        assertEquals(0xFF8A6508.toInt(), SunColors.DAY_SUN_RING)
        assertEquals(0xFFFFFBF6.toInt(), SunColors.CARD_SURFACE_LIGHT)
        assertEquals(0xFF857468.toInt(), SunColors.NIGHT_DASH_LIGHT)
        assertEquals(0.5f, SunColors.DAY_SUN_RING_ALPHA, 1e-6f)
        assertEquals(0.7f, SunColors.DAY_TICK_ALPHA, 1e-6f)
        assertEquals(0.15, SunColors.MIN_WARMTH_GAP, 1e-9)
    }
}
