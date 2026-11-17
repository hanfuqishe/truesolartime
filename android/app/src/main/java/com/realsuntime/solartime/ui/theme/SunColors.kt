package com.realsuntime.solartime.ui.theme

/**
 * 太阳卡圆盘在白天的「暖金色」配色 + 一套纯 Kotlin 的配色计算（WCAG 对比度 / 暖度 / RGB 距离），
 * 以及圆盘的线宽 / 太阳点柔光参数（这些数值都要能在 JVM 单测里直接断言，见 `SunColorsTest` /
 * `SunDialStyleTest`）。
 *
 * 为什么单独放一份、还用 ARGB Int 而不是 Compose 的 `Color`：这些数值要能在 JVM 单测里直接断言，
 * 而 `Color` 依赖 Compose 的图形库；UI 侧只需 `Color(SunColors.DAY_ARC)`。
 *
 * 取值来由（都叠在浅色主题的卡片底色 [CARD_SURFACE_LIGHT] = `#FFFBF6` 上）：
 *
 * | 用途 | hex | 对白卡对比度 | 说明 |
 * |---|---|---|---|
 * | 白天弧 [DAY_ARC] | `#E6CB9C` | ≈1.52 | 淡金，只做「路径示意」；比最初的 `#D09464`（≈2.52）轻得多 |
 * | 白天太阳点核心 [DAY_SUN_CORE] | `#F5C842` | ≈1.54 | 径向渐变**中心**：只有中心一点是满色，往外立刻淡下去 |
 * | 太阳点中段 [DAY_SUN_MID] | `#D9A520` | ≈2.18 | 一半半径处的 45% 金；与弧的对比度 ≈1.43，靠它把点「压」出来 |
 * | 夜晚太阳点（暗色主题） | `#F5D68A` | — | 与 `DarkColors.primary` 同一档夜金，核心 / 中段同色，只靠 alpha 渐隐 |
 * | 日出/日落刻度 [DAY_SUN] @ 70% | `#D9A520` | ≈1.7（合成） | 与太阳点中段同色系、更淡更小 |
 * | 夜晚虚线（`LightColors.outline`） | `#857468` | ≈4.34 | 中性灰，靠**色相**与暖金弧区分，不再靠「更深」 |
 *
 * 上一轮给太阳点加的那圈深金硬描边（`#8A6508` @ 0.5）已经**整圈删掉**：换成径向渐变后，
 * 硬边会在柔光外沿切出一道生硬的「铁圈」，反而把「柔和边缘的金色点」又变回「描边点」。
 * [SUN_DOT_RING_ALPHA] = 0 是钉住这件事的常量（0 = 不绘制），没有别的用途。
 *
 * 太阳点的**大小与柔化方式**不再自己定：与逐时时间轴上的「现在」圆点共用同一组常量
 * （[SOFT_DOT_RADIUS_DP] / [SOFT_DOT_MID_STOP] / [SOFT_DOT_MID_ALPHA] / [SOFT_DOT_EDGE_ALPHA]），
 * 两处点必须一模一样大 —— 见下面「柔光圆点」一节。
 *
 * 弧与虚线不再比「谁更深」：用户明确要求弧更淡，所以区分方式改成色相 ——
 * 金的 `r − b` 比灰大 0.17 左右（见 [warmthGap]）。夜间主题的配色不走这里，仍用主题主色。
 */
internal object SunColors {

    /** 浅色主题的卡片底色（`LightColors.surface`）：所有对比度都以它为背景。 */
    const val CARD_SURFACE_LIGHT = 0xFFFFFBF6.toInt()

    /** 浅色主题里的夜晚虚线（`LightColors.outline`）：中性灰，用来做色相区分的参照。 */
    const val NIGHT_DASH_LIGHT = 0xFF857468.toInt()

    /** 白天弧：淡金，白卡上对比度 ≈1.52（要求 ≥1.4，只是「路径示意」）。 */
    const val DAY_ARC = 0xFFE6CB9C.toInt()

    /** 白天太阳点的**中段金**（= 上一版的实心点色）：白卡上对比度 ≈2.18，与弧 ≈1.43。 */
    const val DAY_SUN = 0xFFD9A520.toInt()

    /** 白天太阳点的**核心亮金**：径向渐变从它开始，比中段更亮一档，点才会有「鼓起来」的球感。 */
    const val DAY_SUN_CORE = 0xFFF5C842.toInt()

    /** 渐变中段色：一半半径处那档 45% 的金，正好是太阳点原来的实心色。 */
    const val DAY_SUN_MID = DAY_SUN

    /** 夜间太阳点的核心 / 中段：`DarkColors.primary` 那档夜金 `#F5D68A`，与现有夜间风格一致。 */
    const val NIGHT_SUN_CORE = 0xFFF5D68A.toInt()

    /** 夜间渐变中段与核心同色（夜间只用 alpha 做柔化，不再额外造一个色）。 */
    const val NIGHT_SUN_MID = NIGHT_SUN_CORE

    /**
     * 太阳点硬描边的透明度：**0 = 已删除**。
     *
     * 上一版是 `#8A6508` @ 0.5；换成径向渐变后这圈边会把柔光外沿切成硬边，所以整圈去掉。
     * 常量留着只为单测能钉住「不许再加回来」。
     */
    const val SUN_DOT_RING_ALPHA = 0f

    /** 日出 / 日落刻度点：同太阳金、更淡（只有点的一半存在感，不与太阳点抢主次）。 */
    const val DAY_TICK_ALPHA = 0.7f

    // ---- 圆盘线宽（dp）----
    // 上一条轨迹线是 2.5dp 的实线 / 2.5dp + 6/6dp 的虚线，在 194dp 高的画布上显得又粗又重；
    // 用户要求「画细一点」，于是：白天实线 1.6dp、夜晚虚线 1.5dp + 4/4dp 间隔（间隔按线宽比例缩小）。
    // 地平线（1dp）与运动方向箭头（1.5dp）已经很细，保持不动。

    /** 白天弧的线宽。 */
    const val DAY_ARC_STROKE_DP = 1.6f

    /** 夜晚虚线的线宽（比白天弧再细 0.1dp，虚线才不显粗）。 */
    const val NIGHT_ARC_STROKE_DP = 1.5f

    /** 夜晚虚线的实线段长度：与 [NIGHT_DASH_OFF_DP] 一起从 6/6dp 缩到 4/4dp。 */
    const val NIGHT_DASH_ON_DP = 4f

    /** 夜晚虚线的空白段长度。 */
    const val NIGHT_DASH_OFF_DP = 4f

    // ---- 柔光圆点（逐时时间轴「现在」点 与 太阳点共用同一组参数）----
    // 用户要求太阳点「和大卡片时间轴上那个『现在』圆点一样」：两处必须一模一样，所以数值只在这里定义一次，
    // `MainScreen.HeroAxis` 与 `SunDial` 都从这里取。HeroAxis 的实测参数：画布 11dp 高，圆点半径 5.5dp
    // （正好占满整高）、径向渐变三档等距色标（0 / 0.5 / 1）、alpha 1.0 / 0.45 / 0。
    // 没有「实心核心 + 外圈柔光」两层，就**一个**渐变圆：中心满色，到一半半径已掉到 45%，到边缘全透明。

    /** 「现在」圆点 / 太阳点的半径：5.5dp（时间轴画布 11dp 高，点正好占满整高）。 */
    const val SOFT_DOT_RADIUS_DP = 5.5f

    /** 三档色标的中间位置：与 HeroAxis 的等距色标一致（0 / 0.5 / 1）。 */
    const val SOFT_DOT_MID_STOP = 0.5f

    /** 中段 alpha：HeroAxis 的 0.45。 */
    const val SOFT_DOT_MID_ALPHA = 0.45f

    /** 外沿 alpha：完全透明。 */
    const val SOFT_DOT_EDGE_ALPHA = 0f

    /** 中段所在的半径（视觉上「核心」的边缘）：5.5 × 0.5 = 2.75dp，再往外就是柔光。 */
    val SOFT_DOT_MID_RADIUS_DP: Float get() = SOFT_DOT_RADIUS_DP * SOFT_DOT_MID_STOP

    /**
     * 径向渐变的一个色标：[position] 是 0–1（相对圆点半径），[argb] 是满不透明的 RGB，[alpha] 单独给。
     *
     * 只用纯 Kotlin 类型、不碰 Compose 的 `Color`：这样色标也能在 JVM 单测里逐项断言。
     */
    data class SunDotStop(val position: Float, val argb: Int, val alpha: Float)

    /**
     * 太阳点的三个色标：中心亮金 → 中段金 @45% → 外沿同色 @0。
     *
     * 位置与 alpha 曲线和时间轴「现在」点完全一致（[SOFT_DOT_MID_STOP] / [SOFT_DOT_MID_ALPHA] /
     * [SOFT_DOT_EDGE_ALPHA]），只有颜色不同：时间轴是单色 dotColor，太阳点是「亮金中心 + 中段金」。
     */
    fun sunDotStops(night: Boolean): List<SunDotStop> = if (night) {
        listOf(
            SunDotStop(0f, NIGHT_SUN_CORE, 1f),
            SunDotStop(SOFT_DOT_MID_STOP, NIGHT_SUN_MID, SOFT_DOT_MID_ALPHA),
            SunDotStop(1f, NIGHT_SUN_MID, SOFT_DOT_EDGE_ALPHA),
        )
    } else {
        listOf(
            SunDotStop(0f, DAY_SUN_CORE, 1f),
            SunDotStop(SOFT_DOT_MID_STOP, DAY_SUN_MID, SOFT_DOT_MID_ALPHA),
            SunDotStop(1f, DAY_SUN_MID, SOFT_DOT_EDGE_ALPHA),
        )
    }

    /** 暖度差的门槛：暖金弧与中性灰虚线的 `r − b` 至少差这么多（归一化到 0–1）。 */
    const val MIN_WARMTH_GAP = 0.15

    private fun channel(argb: Int, shift: Int): Int = (argb shr shift) and 0xFF

    /** 0–255 的 sRGB 通道 → 线性光（WCAG 2.x 的定义）。 */
    private fun linear(value: Int): Double {
        val c = value / 255.0
        return if (c <= 0.03928) c / 12.92 else Math.pow((c + 0.055) / 1.055, 2.4)
    }

    /** WCAG 相对亮度（0 = 黑，1 = 白）。 */
    fun relativeLuminance(argb: Int): Double =
        0.2126 * linear(channel(argb, 16)) +
            0.7152 * linear(channel(argb, 8)) +
            0.0722 * linear(channel(argb, 0))

    /** WCAG 对比度（1.0 = 完全相同，21 = 黑白）。 */
    fun contrastRatio(a: Int, b: Int): Double {
        val la = relativeLuminance(a)
        val lb = relativeLuminance(b)
        val lighter = maxOf(la, lb)
        val darker = minOf(la, lb)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /** 暖度：`(r − b) / 255`，金/橙为正、中性灰接近 0、蓝为负。 */
    fun warmth(argb: Int): Double = (channel(argb, 16) - channel(argb, 0)) / 255.0

    /** 两个颜色的暖度差（取绝对值）：用来断言「暖金 vs 中性灰」确实分得开。 */
    fun warmthGap(a: Int, b: Int): Double = kotlin.math.abs(warmth(a) - warmth(b))

    /** 两个颜色的 RGB 欧氏距离（0–441）：报告里衡量「三者差多远」。 */
    fun rgbDistance(a: Int, b: Int): Double {
        val dr = channel(a, 16) - channel(b, 16)
        val dg = channel(a, 8) - channel(b, 8)
        val db = channel(a, 0) - channel(b, 0)
        return kotlin.math.sqrt((dr * dr + dg * dg + db * db).toDouble())
    }
}
