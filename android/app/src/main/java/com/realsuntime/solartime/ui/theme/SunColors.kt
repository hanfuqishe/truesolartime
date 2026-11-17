package com.realsuntime.solartime.ui.theme

/**
 * 太阳卡圆盘在白天的「暖金色」配色 + 一套纯 Kotlin 的配色计算（WCAG 对比度 / 暖度 / RGB 距离）。
 *
 * 为什么单独放一份、还用 ARGB Int 而不是 Compose 的 `Color`：这些数值要能在 JVM 单测里直接断言
 * （`SunColorsTest`），而 `Color` 依赖 Compose 的图形库；UI 侧只需 `Color(SunColors.DAY_ARC)`。
 *
 * 取值来由（都叠在浅色主题的卡片底色 [CARD_SURFACE_LIGHT] = `#FFFBF6` 上）：
 *
 * | 用途 | hex | 对白卡对比度 | 说明 |
 * |---|---|---|---|
 * | 白天弧 [DAY_ARC] | `#E6CB9C` | ≈1.52 | 淡金，只做「路径示意」；比原来的 `#D09464`（≈2.52）轻得多 |
 * | 白天太阳点 [DAY_SUN] | `#B8860B` | ≈3.16 | 深金，与弧的对比度 ≈2.07，形成「弧很淡、点很实」 |
 * | 夜晚虚线（原来的 `outline`） | `#857468` | ≈4.34 | 中性灰，靠**色相**与暖金弧区分，不再靠「更深」 |
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

    /** 白天太阳点：深金，白卡上对比度 ≈3.16，与弧的对比度 ≈2.07（要求 ≥2.0）。 */
    const val DAY_SUN = 0xFFB8860B.toInt()

    /** 日出 / 日落刻度点：同太阳金、更淡（只有点的一半存在感，不与太阳点抢主次）。 */
    const val DAY_TICK_ALPHA = 0.7f

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
