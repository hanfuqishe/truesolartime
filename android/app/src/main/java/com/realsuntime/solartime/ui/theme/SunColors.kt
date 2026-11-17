package com.realsuntime.solartime.ui.theme

/**
 * 太阳卡圆盘在白天的「暖金色」配色 + 一套纯 Kotlin 的配色计算（WCAG 对比度 / 暖度 / RGB 距离），
 * 以及圆盘的线宽 / 太阳点与时间轴圆点的参数（这些数值都要能在 JVM 单测里直接断言，见 `SunColorsTest` /
 * `SunDialStyleTest`）。
 *
 * 为什么单独放一份、还用 ARGB Int 而不是 Compose 的 `Color`：这些数值要能在 JVM 单测里直接断言，
 * 而 `Color` 依赖 Compose 的图形库；UI 侧只需 `Color(SunColors.DAY_ARC)`。
 *
 * 取值来由（都叠在浅色主题的卡片底色 [CARD_SURFACE_LIGHT] = `#FFFBF6` 上）：
 *
 * | 用途 | hex | 对白卡对比度 | 说明 |
 * |---|---|---|---|
 * | 白天弧 [DAY_ARC] | `#EAD095` | ≈1.46 | 淡金，只做「路径示意」；比最初的 `#D09464`（≈2.52）轻得多 |
 * | 白天太阳点 [DAY_SUN] | `#D9AC1C` | ≈2.07 | **纯色实心核心** 2.75dp（alpha 1.0），外圈光晕同色 0.35→0 到 5.5dp |
 * | 夜晚太阳点 [NIGHT_SUN] | `#F5D68A` | — | 与 `DarkColors.primary` 同一档夜金，核心同样纯色不透明 |
 * | 日出/日落刻度 [DAY_SUN] @ 70% | `#D9AC1C` | ≈1.7（合成） | 与太阳点同色系、更淡更小 |
 * | 夜晚虚线（`LightColors.outline`） | `#857468` | ≈4.34 | 中性灰，靠**色相**与暖金弧区分，不再靠「更深」 |
 *
 * 太阳点曾经照搬时间轴「现在」圆点的单个渐变圆，但真机截图放大后 alpha 阶梯没有生效：
 * 整颗点均匀半透明、轨迹弧从点下面透出来。现在改成**两层绘制**：
 * 先画外圈光晕（2.75→5.5dp，alpha 0.35→0），再画半径 2.75dp 的**纯色核心**（alpha 1.0）压在上面。
 * 核心不参与任何渐变 / alpha 混合，弧线不可能透出来。
 * 尺寸与时间轴圆点对齐：核心 2.75dp = 时间轴半径 × 0.5，光晕外沿 5.5dp = 时间轴半径。
 *
 * 硬描边没有回来：[SUN_DOT_RING_ALPHA] = 0 钉住这件事。
 *
 * 弧与虚线不再比「谁更深」：用户明确要求弧更淡，所以区分方式改成色相 ——
 * 金的 `r − b` 比灰大 0.22 左右（见 [warmthGap]）。夜间主题的配色不走这里，仍用主题主色。
 */
internal object SunColors {

    /** 浅色主题的卡片底色（`LightColors.surface`）：所有对比度都以它为背景。 */
    const val CARD_SURFACE_LIGHT = 0xFFFFFBF6.toInt()

    /** 浅色主题里的夜晚虚线（`LightColors.outline`）：中性灰，用来做色相区分的参照。 */
    const val NIGHT_DASH_LIGHT = 0xFF857468.toInt()

    /** 白天弧：淡金（比上一版 `#E6CB9C` 更黄、更少褐），白卡上对比度 ≈1.46（要求 1.4~1.9，只是「路径示意」）。 */
    const val DAY_ARC = 0xFFEAD095.toInt()

    /** 白天太阳点的颜色（也是日出 / 日落刻度的颜色）：`#D9AC1C`，白卡上对比度 ≈2.07，色相 H46° / S87%。 */
    const val DAY_SUN = 0xFFD9AC1C.toInt()

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

    // ---- 逐时时间轴「现在」圆点（单个渐变圆；太阳点已改成两层，见下一节）----
    // **恢复原来的曲线**（用户说上一轮为了统一改成 0.55/1.0 之后「效果没以前好了」）：
    // 画布 11dp 高，圆点半径 5.5dp（正好占满整高）、**一个**径向渐变圆、色标 0 / 0.5 / 1，
    // alpha 1.0 / 0.45 / 0：只有圆心完全不透明，到一半半径（2.75dp）已经是 45%，边缘 0。
    // 时间轴的点不要再动它。

    /** 时间轴「现在」圆点的半径：5.5dp（时间轴画布 11dp 高，点正好占满整高）。 */
    const val SOFT_DOT_RADIUS_DP = 5.5f

    /** 三档色标的中间位置：0 / 0.5 / 1（一半半径）。 */
    const val SOFT_DOT_MID_STOP = 0.5f

    /** 中心 alpha：满色（渐变从圆心开始）。 */
    const val SOFT_DOT_CENTER_ALPHA = 1f

    /** 中段 alpha：0.45 —— 到一半半径就散掉一半多，这是时间轴原来的柔化手感。 */
    const val SOFT_DOT_MID_ALPHA = 0.45f

    /** 外沿 alpha：完全透明。 */
    const val SOFT_DOT_EDGE_ALPHA = 0f

    /** 中段所在的半径：5.5 × 0.5 = 2.75dp。 */
    val SOFT_DOT_MID_RADIUS_DP: Float get() = SOFT_DOT_RADIUS_DP * SOFT_DOT_MID_STOP

    /** 三档色标的位置：0 / 0.5 / 1。 */
    fun softDotStopPositions(): List<Float> = listOf(0f, SOFT_DOT_MID_STOP, 1f)

    /** 三档色标的 alpha：1 / 0.45 / 0。 */
    fun softDotStopAlphas(): List<Float> =
        listOf(SOFT_DOT_CENTER_ALPHA, SOFT_DOT_MID_ALPHA, SOFT_DOT_EDGE_ALPHA)

    /**
     * 圆点在 0–1 半径比例 [position] 处的 alpha（按色标做分段线性插值）。
     *
     * 单测用它把整条曲线显式化：0 处 1.0、0.5 处 0.45、1 处 0。
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

    // ---- 太阳点（两层：纯色实心核心 + 只在外圈的光晕）----
    // 真机截图放大 4 倍后发现：单个渐变圆的 alpha 阶梯在设备上没生效 —— 整颗点均匀半透明、
    // 轨迹弧从点下面透出来。用户裁定改成两层绘制，**核心用纯色、不依赖 Brush**：
    //   ① 光晕：半径 5.5dp 的径向渐变，内沿 2.75dp（= 核心半径）处 alpha 0.35、外沿 0；
    //   ② 核心：半径 2.75dp 的纯色圆，alpha 1.0，**最后**画、压在最上面，核心区 100% 不透明。
    // 尺寸对齐时间轴圆点：核心 2.75dp = 时间轴半径 × 0.5（那颗点视觉上的实心区），
    // 光晕外沿 5.5dp = 时间轴半径，所以两颗点整体一样大（直径 11dp），实心部分也一样大。

    /** 实心核心半径：2.75dp（= 时间轴圆点半径 5.5 × 0.5，视觉实心区同大）。 */
    const val SUN_DOT_CORE_RADIUS_DP = 2.75f

    /** 外圈光晕的外沿半径：5.5dp（= 时间轴圆点半径，两颗点整体一样大）。 */
    const val SUN_DOT_GLOW_RADIUS_DP = 5.5f

    /** 光晕在内沿（= 核心外沿）的 alpha。 */
    const val SUN_DOT_GLOW_ALPHA = 0.35f

    /** 光晕在外沿的 alpha。 */
    const val SUN_DOT_GLOW_EDGE_ALPHA = 0f

    /** 核心颜色的 alpha：从 [DAY_SUN] 的 ARGB 高字节算出来，必须是 1.0（不许半透明）。 */
    val SUN_DOT_CORE_ALPHA: Float get() = ((DAY_SUN ushr 24) and 0xFF) / 255f

    /** 光晕内沿在 0–1 渐变里的位置：核心半径 / 光晕半径 = 2.75 / 5.5 = 0.5。 */
    val SUN_DOT_GLOW_INNER_STOP: Float get() = SUN_DOT_CORE_RADIUS_DP / SUN_DOT_GLOW_RADIUS_DP

    /** 太阳点核心的颜色：白天纯金 `#D9AC1C`、夜间 `#F5D68A`，都是 alpha 0xFF。 */
    fun sunDotCoreColor(night: Boolean): Int = if (night) NIGHT_SUN else DAY_SUN

    /** 光晕色标的位置（相对光晕半径 5.5dp）：内沿 0.5、外沿 1。 */
    fun sunDotGlowStopPositions(): List<Float> = listOf(SUN_DOT_GLOW_INNER_STOP, 1f)

    /** 光晕色标的 alpha：0.35 → 0。 */
    fun sunDotGlowStopAlphas(): List<Float> = listOf(SUN_DOT_GLOW_ALPHA, SUN_DOT_GLOW_EDGE_ALPHA)

    /**
     * 径向渐变的一个色标：[position] 是 0–1（相对圆点半径），[argb] 是满不透明的 RGB，[alpha] 单独给。
     *
     * 只用纯 Kotlin 类型、不碰 Compose 的 `Color`：这样色标也能在 JVM 单测里逐项断言。
     */
    data class SunDotStop(val position: Float, val argb: Int, val alpha: Float)

    /**
     * 太阳点外圈光晕的两个色标：内沿（核心外沿，alpha 0.35）→ 外沿（alpha 0）。
     *
     * 内沿位置 0.5 而不是 0：渐变从 2.75dp 才开始，核心那一段不参与（核心用纯色单独画）。
     */
    fun sunDotGlowStops(night: Boolean): List<SunDotStop> {
        val color = sunDotCoreColor(night)
        val positions = sunDotGlowStopPositions()
        val alphas = sunDotGlowStopAlphas()
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
