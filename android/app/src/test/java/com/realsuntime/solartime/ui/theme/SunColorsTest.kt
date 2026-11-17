package com.realsuntime.solartime.ui.theme

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 太阳卡白天配色的断言（`SunColors` 是纯 Kotlin，测试不依赖 Compose）。
 *
 * 这版的要求：白天弧改成很淡的「路径示意」金，太阳点改成**柔和边缘的金色点**
 * （径向渐变，中心 `#F5C842` → 中段 `#D9A520` → 全透明），上一版那圈深金硬描边已删除；
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
     * 太阳点的**中段色**（4dp 核心的外缘，也是原来的实心色）要比淡金弧明显：
     * 与弧的对比度 ≥1.3；整点又比弧在白卡上更显眼。
     */
    @Test
    fun sunDotStandsOutFromThePaleArc() {
        val sunVsArc = SunColors.contrastRatio(SunColors.DAY_SUN_MID, SunColors.DAY_ARC)
        assertTrue("亮金点与弧的对比度太低：$sunVsArc", sunVsArc >= 1.3)
        val sunVsCard = SunColors.contrastRatio(SunColors.DAY_SUN, cardSurface)
        val arcVsCard = SunColors.contrastRatio(SunColors.DAY_ARC, cardSurface)
        assertTrue("太阳点应比弧更明显：$sunVsCard vs $arcVsCard", sunVsCard > arcVsCard)
    }

    /** 渐变中心必须比中段更亮：点才有「鼓起」的球感，而不是一块平的色块。 */
    @Test
    fun sunDotCoreIsBrighterThanItsMidStop() {
        val core = SunColors.relativeLuminance(SunColors.DAY_SUN_CORE)
        val mid = SunColors.relativeLuminance(SunColors.DAY_SUN_MID)
        assertTrue("中心色应该比中段更亮：核心 $core vs 中段 $mid", core > mid)
    }

    /** 上一版的深金硬描边已整圈删除：alpha 常量必须是 0（不再有一圈实色边）。 */
    @Test
    fun sunDotHasNoHardRing() {
        assertTrue(
            "硬描边必须删除或 alpha < 0.15：${SunColors.SUN_DOT_RING_ALPHA}",
            SunColors.SUN_DOT_RING_ALPHA < 0.15f,
        )
        assertEquals("描边应已删除（0 = 不绘制）", 0f, SunColors.SUN_DOT_RING_ALPHA, 1e-6f)
    }

    /**
     * 太阳点的三个色标：中心 `#F5C842`、中段 `#D9A520` @45%、外沿同一个金 @0。
     *
     * 外沿不换色相、只把 alpha 打到 0：这样柔光拖尾是「金在散开」，不会在边缘偏成灰色。
     * alpha 曲线与时间轴「现在」点共用（1.0 / 0.45 / 0），见 `SunDialStyleTest`。
     */
    @Test
    fun sunDotGradientFadesFromBrightGoldToTransparent() {
        assertEquals(0xFFF5C842.toInt(), SunColors.DAY_SUN_CORE)
        assertEquals(0xFFD9A520.toInt(), SunColors.DAY_SUN_MID)

        val dayStops = SunColors.sunDotStops(night = false)
        assertEquals(3, dayStops.size)
        assertEquals(0f, dayStops.first().position, 1e-6f)
        assertEquals(SunColors.DAY_SUN_CORE, dayStops.first().argb)
        assertEquals(1f, dayStops.first().alpha, 1e-6f)
        assertEquals(SunColors.DAY_SUN_MID, dayStops[1].argb)
        assertEquals(SunColors.SOFT_DOT_MID_ALPHA, dayStops[1].alpha, 1e-6f)
        assertEquals(1f, dayStops.last().position, 1e-6f)
        assertEquals("外沿色相必须仍是中段金", SunColors.DAY_SUN_MID, dayStops.last().argb)
        assertEquals("外沿必须是 alpha 0", 0f, dayStops.last().alpha, 1e-6f)
    }

    /** 夜间用同一套色标位置与 alpha，色值换成夜金 `#F5D68A`（与 `DarkColors.primary` 一致）。 */
    @Test
    fun nightGradientUsesTheNightGold() {
        assertEquals(0xFFF5D68A.toInt(), SunColors.NIGHT_SUN_CORE)
        assertEquals(SunColors.NIGHT_SUN_CORE, SunColors.NIGHT_SUN_MID)

        val nightStops = SunColors.sunDotStops(night = true)
        assertEquals(3, nightStops.size)
        nightStops.forEach {
            assertEquals("夜间所有色标应同为夜金", SunColors.NIGHT_SUN_CORE, it.argb)
        }
        assertEquals(1f, nightStops.first().alpha, 1e-6f)
        assertEquals(SunColors.SOFT_DOT_MID_ALPHA, nightStops[1].alpha, 1e-6f)
        assertEquals("夜间外沿也必须 alpha 0", 0f, nightStops.last().alpha, 1e-6f)
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
        assertEquals(0xFFF5C842.toInt(), SunColors.DAY_SUN_CORE)
        assertEquals(0xFFD9A520.toInt(), SunColors.DAY_SUN_MID)
        assertEquals(0xFFF5D68A.toInt(), SunColors.NIGHT_SUN_CORE)
        assertEquals(0xFFFFFBF6.toInt(), SunColors.CARD_SURFACE_LIGHT)
        assertEquals(0xFF857468.toInt(), SunColors.NIGHT_DASH_LIGHT)
        assertEquals(0.0f, SunColors.SUN_DOT_RING_ALPHA, 1e-6f)
        assertEquals(0.7f, SunColors.DAY_TICK_ALPHA, 1e-6f)
        assertEquals(0.15, SunColors.MIN_WARMTH_GAP, 1e-9)
    }
}
