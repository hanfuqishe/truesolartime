package com.realsuntime.solartime.ui.theme

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 太阳圆盘「线更细 + 太阳点与时间轴「现在」点同款」这轮的几何常量断言（纯 Kotlin，不依赖 Compose）。
 *
 * 常量都放在 [SunColors] 里：颜色、线宽、柔光点尺寸是同一张「圆盘外观规格表」，绘制代码只取常量；
 * 时间轴 `HeroAxis` 与圆盘 `SunDial` 用的还是**同一组** [SunColors.SOFT_DOT_*]，两处点不会各走各的。
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
     * 太阳点与时间轴「现在」点同尺寸：半径 5.5dp（时间轴画布 11dp 高，点正好占满整高）。
     *
     * 上一版太阳点是「4dp 核心 + 2.1 倍柔光（8.4dp）」，明显比时间轴的点大，用户要求缩到同款。
     */
    @Test
    fun softDotRadiusMatchesTheTimelineDot() {
        assertEquals(5.5f, SunColors.SOFT_DOT_RADIUS_DP, 1e-6f)
        // 视觉上的「核心边缘」= 一半半径 = 2.75dp；再往外就是 alpha < 0.45 的柔光。
        assertEquals(2.75f, SunColors.SOFT_DOT_MID_RADIUS_DP, 1e-4f)
        assertTrue(
            "圆点直径应和时间轴画布一样高（11dp）：${SunColors.SOFT_DOT_RADIUS_DP * 2}dp",
            SunColors.SOFT_DOT_RADIUS_DP * 2f in 10.9f..11.1f,
        )
    }

    /** alpha 曲线与 HeroAxis 一致：0 → 1.0，一半半径 → 0.45，边缘 → 0。 */
    @Test
    fun softDotAlphaCurveMatchesHeroAxis() {
        assertEquals(0.5f, SunColors.SOFT_DOT_MID_STOP, 1e-6f)
        assertEquals(0.45f, SunColors.SOFT_DOT_MID_ALPHA, 1e-6f)
        assertEquals(0f, SunColors.SOFT_DOT_EDGE_ALPHA, 1e-6f)
    }

    /** 色标按位置递增、首 0 尾 1，alpha 依次 1 / 0.45 / 0：否则 `Brush.radialGradient` 会画反或抛异常。 */
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
            assertEquals("中心 alpha 应为 1", 1f, stops[0].alpha, 1e-6f)
            assertEquals("中段 alpha 应为 0.45", 0.45f, stops[1].alpha, 1e-6f)
            assertEquals("外沿 alpha 应为 0", 0f, stops[2].alpha, 1e-6f)
        }
    }
}
