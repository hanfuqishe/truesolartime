package com.realsuntime.solartime.ui.theme

/**
 * 太阳卡圆盘在白天的「暖金色」配色 + 一套纯 Kotlin 的配色计算（WCAG 对比度 / 暖度 / RGB 距离），
 * 以及圆盘的线宽 / 太阳点与时间轴圆点共用的参数（这些数值都要能在 JVM 单测里直接断言，见 `SunColorsTest` /
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
 * | 白天太阳点 [DAY_SUN] | `#D9A520` | ≈2.18 | 与时间轴「现在」圆点**同款**（半径 / 色标 / alpha 全同），只换颜色 |
 * | 夜晚太阳点 [NIGHT_SUN] | `#F5D68A` | — | 与 `DarkColors.primary` 同一档夜金 |
 * | 日出/日落刻度 [DAY_SUN] @ 70% | `#D9A520` | ≈1.7（合成） | 与太阳点同色系、更淡更小 |
 * | 夜晚虚线（`LightColors.outline`） | `#857468` | ≈4.34 | 中性灰，靠**色相**与暖金弧区分，不再靠「更深」 |
 *
 * 太阳点的画法**不再自创**：直接把时间轴「现在」圆点原样搬过来 —— 半径、三档色标位置、alpha 曲线
 * 全部共用同一组常量（[SOFT_DOT_RADIUS_DP] / [SOFT_DOT_MID_STOP] / [SOFT_DOT_MID_ALPHA] /
 * [SOFT_DOT_EDGE_ALPHA]），唯一区别是颜色（金）。
 *
 * 硬描边没有回来：时间轴的点本来就不画描边，照搬过来自然也不画；[SUN_DOT_RING_ALPHA] = 0 钉住这件事。
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

    /** 白天太阳点的颜色（也是日出 / 日落刻度的颜色）：`#D9A520`，白卡上对比度 ≈2.18。 */
    const val DAY_SUN = 0xFFD9A520.toInt()

    /** 夜间太阳点的颜色：夜金 `#F5D68A`（= `DarkColors.primary`，深蓝底上对比度 ≈11.4）。 */
    const val NIGHT_SUN = 0xFFF5D68A.toInt()

    /**
     * 太阳点硬描边的透明度：**0 = 已删除**。
     *
     * 时间轴圆点本来就不画描边，照搬过来自然也不画；再套一圈实色边会把柔和的边缘切成硬边。
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

    // ---- 柔光圆点（逐时时间轴「现在」点 与 太阳点共用同一套画法）----
    // 用户最终裁定：时间轴与太阳点同款、只换颜色；随后又确认问题不在颜色，而在 **alpha 曲线**。
    // 画布 11dp 高，圆点半径 5.5dp（正好占满整高）、**一个**径向渐变圆、色标 0 / 0.55 / 1，
    // alpha 1.0 / 1.0 / 0：内圈 55%（到 3.025dp）完全不透明，之后线性渐隐到 0。
    // 没有实心核心、没有第二层光晕、没有中心高光、没有描边；渐变从圆心 0 开始。
    // `SunDial` 用的就是这同一组位置 / alpha 常量与同一个半径（[SUN_DOT_RADIUS_DP] = [SOFT_DOT_RADIUS_DP]）。

    /** 时间轴「现在」圆点的半径：5.5dp（时间轴画布 11dp 高，点正好占满整高）。 */
    const val SOFT_DOT_RADIUS_DP = 5.5f

    /** 三档色标的中间位置：0 / 0.55 / 1（55% 以内都是实心）。 */
    const val SOFT_DOT_MID_STOP = 0.55f

    /** 中心 alpha：满色（渐变从圆心开始）。 */
    const val SOFT_DOT_CENTER_ALPHA = 1f

    /** 中段 alpha：**仍是满色** —— 这一档就是「实心内圈」的外沿，从这里才开始渐隐。 */
    const val SOFT_DOT_MID_ALPHA = 1f

    /** 外沿 alpha：完全透明。 */
    const val SOFT_DOT_EDGE_ALPHA = 0f

    /** 实心内圈的外沿半径：5.5 × 0.55 = 3.025dp（再往外才开始变透明）。 */
    val SOFT_DOT_MID_RADIUS_DP: Float get() = SOFT_DOT_RADIUS_DP * SOFT_DOT_MID_STOP

    /** 太阳点半径：**就是时间轴圆点的半径**，不允许单独调（用户要求两处完全一致）。 */
    const val SUN_DOT_RADIUS_DP = SOFT_DOT_RADIUS_DP

    /** 三档色标的位置（时间轴与太阳点共用）：0 / 0.55 / 1。 */
    fun softDotStopPositions(): List<Float> = listOf(0f, SOFT_DOT_MID_STOP, 1f)

    /** 三档色标的 alpha（共用）：1 / 1 / 0。 */
    fun softDotStopAlphas(): List<Float> =
        listOf(SOFT_DOT_CENTER_ALPHA, SOFT_DOT_MID_ALPHA, SOFT_DOT_EDGE_ALPHA)

    /**
     * 圆点在 0–1 半径比例 [position] 处的 alpha（按色标做分段线性插值）。
     *
     * 单测用它钉住「半径一半（0.5）处仍然完全不透明」这件事 —— 光看色标数组只能看到 0.55 是实心，
     * 而 0 → 0.55 之间也是满色，这个函数把整条曲线显式化。
     */
    fun softDotAlphaAt(position: Float): Float {
        val positions = softDotStopPositions()
        val alphas = softDotStopAlphas()
        if (position <= positions.first()) return alphas.first()
        for (index in 1 until positions.size) {
            if (position <= positions[index]) {
                val span = positions[index] - positions[index - 1]
                val t = if (span <= 0f) 1f else (position - positions[index - 1]) / span
                return alphas[index - 1] + (alphas[index] - alphas[index - 1]) * t
            }
        }
        return alphas.last()
    }

    /**
     * 径向渐变的一个色标：[position] 是 0–1（相对圆点半径），[argb] 是满不透明的 RGB，[alpha] 单独给。
     *
     * 只用纯 Kotlin 类型、不碰 Compose 的 `Color`：这样色标也能在 JVM 单测里逐项断言。
     */
    data class SunDotStop(val position: Float, val argb: Int, val alpha: Float)

    /**
     * 太阳点的三个色标：位置 / alpha 与时间轴圆点**完全同一组数组**，整颗点用同一个金色。
     *
     * 白天 `#D9A520`、夜间 `#F5D68A`；0 → 0.55 是满色实心内圈，0.55 → 1 才线性渐隐到全透明。
     */
    fun sunDotStops(night: Boolean): List<SunDotStop> {
        val color = if (night) NIGHT_SUN else DAY_SUN
        val positions = softDotStopPositions()
        val alphas = softDotStopAlphas()
        return positions.mapIndexed { index, position -> SunDotStop(position, color, alphas[index]) }
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
