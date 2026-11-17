package com.realsuntime.solartime.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

private val LightColors = lightColorScheme(
    primary = Color(0xFFB4550A),
    onPrimary = Color.White,
    primaryContainer = Color(0xFFFFDDB8),
    onPrimaryContainer = Color(0xFF3A1B00),
    secondary = Color(0xFF6E5A3F),
    onSecondary = Color.White,
    secondaryContainer = Color(0xFFF6E4CC),
    onSecondaryContainer = Color(0xFF26190A),
    background = Color(0xFFFFF8F1),
    onBackground = Color(0xFF211A15),
    surface = Color(0xFFFFFBF6),
    onSurface = Color(0xFF211A15),
    surfaceVariant = Color(0xFFF2E3D3),
    onSurfaceVariant = Color(0xFF52443A),
    outline = Color(0xFF857468),
    outlineVariant = Color(0xFFD7C4B5),
)

private val DarkColors = darkColorScheme(
    primary = Color(0xFFF5D68A),
    onPrimary = Color(0xFF0B1220),
    primaryContainer = Color(0xFF24304F),
    onPrimaryContainer = Color(0xFFF5D68A),
    secondary = Color(0xFF9AA7BF),
    onSecondary = Color(0xFF0B1220),
    secondaryContainer = Color(0xFF24304F),
    onSecondaryContainer = Color(0xFFE8EDF7),
    background = Color(0xFF0B1220),
    onBackground = Color(0xFFE8EDF7),
    surface = Color(0xFF16203A),
    onSurface = Color(0xFFE8EDF7),
    surfaceVariant = Color(0xFF24304F),
    onSurfaceVariant = Color(0xFF9AA7BF),
    outline = Color(0xFF3A4763),
    outlineVariant = Color(0xFF24304F),
)

private val AppTypography = Typography(
    displayLarge = TextStyle(
        fontWeight = FontWeight.Light,
        fontSize = 76.sp,
        lineHeight = 84.sp,
        letterSpacing = (-2).sp,
    ),
)

/**
 * 白天／夜间两套主题。
 *
 * [darkTheme] **必须由调用方按太阳高度角决定**（见 `MainScreen` 里 `!snapshot.isDay`），
 * 不看系统的深色开关：太阳落山的那一刻就换主题，与鸿蒙版一致。所以这里不提供
 * 「跟随系统」的默认值 —— 默认值一旦是 `isSystemInDarkTheme()`，忘了传就会静默退回跟系统走。
 */
@Composable
fun TrueSolarTimeTheme(
    darkTheme: Boolean,
    content: @Composable () -> Unit,
) {
    MaterialTheme(
        colorScheme = if (darkTheme) DarkColors else LightColors,
        typography = AppTypography,
        content = content,
    )
}

/**
 * 太阳卡圆盘的配色（派生自色板 / 新增的 `SunColors`，见 [SunColors]）。
 *
 * - **亮色主题**：白天弧 = 淡金 [SunColors.DAY_ARC]（`#E6CB9C`，白卡上对比度 ≈1.52，只做「路径示意」）；
 *   太阳点 = **柔和边缘的金色点**，尺寸与柔化方式跟逐时时间轴上「现在」的圆点完全一致
 *   （半径 5.5dp、三档色标 0 / 0.5 / 1、alpha 1.0 / 0.45 / 0，见 [SunColors.SOFT_DOT_RADIUS_DP]），
 *   只是颜色换成亮金 → 中段金 `#F5C842 → #D9A520`；不再画深金硬描边（见 [SunColors.SUN_DOT_RING_ALPHA]）；
 *   日出 / 日落刻度 = 太阳金、70% 透明（比点淡一档）。
 * - **暗色主题**：白天弧仍是实色主色（深蓝底上那档金色正好，调淡反而糊）；太阳点同样用径向渐变，
 *   但色板换成夜金 [SunColors.NIGHT_SUN_CORE]（`#F5D68A`，与 `DarkColors.primary` 同色）。
 *
 * 亮色主题里「白天弧 vs 夜晚虚线」不再靠深浅区分（弧故意更淡），而是靠色相：
 * 暖金的 `r − b` 比中性灰大 0.17 左右（`SunColorsTest` 里有断言）。
 *
 * 判断依据是当前 `surface` 的亮度（主题函数只换 colorScheme，没有额外的暗色标志）；
 * `#FFFBF6` 与 `#16203A` 亮度差距极大，不会误判。
 */
@Composable
fun sunDayArcColor(): Color = if (isLightSunPalette()) Color(SunColors.DAY_ARC) else MaterialTheme.colorScheme.primary

/** 太阳点的中段色：亮色主题是亮金 `#D9A520`（渐变中段）；暗色主题是夜金 `#F5D68A`。 */
@Composable
fun sunDotColor(): Color = if (isLightSunPalette()) Color(SunColors.DAY_SUN_MID) else Color(SunColors.NIGHT_SUN_MID)

/**
 * 柔光圆点的三档色标（**逐时时间轴「现在」点与太阳点共用**）：满色 → 45% → 全透明。
 *
 * 位置取 [SunColors.SOFT_DOT_MID_STOP]（0.5，等距）、alpha 取 [SunColors.SOFT_DOT_MID_ALPHA] /
 * [SunColors.SOFT_DOT_EDGE_ALPHA]：这就是 HeroAxis 圆点原来的 alpha 曲线，两处不能再各写一套。
 */
fun softDotStops(color: Color): List<Pair<Float, Color>> = listOf(
    0f to color,
    SunColors.SOFT_DOT_MID_STOP to color.copy(alpha = SunColors.SOFT_DOT_MID_ALPHA),
    1f to color.copy(alpha = SunColors.SOFT_DOT_EDGE_ALPHA),
)

/**
 * 太阳点的径向渐变：**中心亮金 → 中段金 @45% → 外沿同色 @0**（色标见 [SunColors.sunDotStops]）。
 *
 * 尺寸与柔化方式跟时间轴「现在」圆点一模一样：半径 [SunColors.SOFT_DOT_RADIUS_DP]（5.5dp）、
 * 三档等距色标、alpha 1.0 / 0.45 / 0。没有「实心核心 + 外圈柔光」两层，就是一个渐变圆：
 * 中心满色，到 2.75dp（一半半径）已是 45%，到 5.5dp 完全散尽。
 *
 * 这里不传 `center` / `radius`：`Brush.radialGradient` 会按**实际绘制圆的大小**铺开，
 * 所以 `drawCircle(brush = sunDotBrush(), radius = 5.5dp)` 里 0–1 的色标正好对应 0–5.5dp。
 *
 * 不再有硬描边（上一版 `#8A6508` @ 0.5 已删除）：边缘交给渐变自己化开。
 */
@Composable
fun sunDotBrush(): Brush {
    val stops = SunColors.sunDotStops(night = !isLightSunPalette())
    // Compose 的径向渐变只提供 `(位置, 颜色)` 变长参数这一种写法（没有单独的 colorStops 列表重载）。
    return Brush.radialGradient(
        *stops.map { it.position to Color(it.argb).copy(alpha = it.alpha) }.toTypedArray(),
    )
}

/** 日出 / 日落刻度点：亮色主题用太阳金 + 70% 透明（比太阳点淡一档），暗色主题仍是主色。 */
@Composable
fun sunTickColor(): Color = if (isLightSunPalette()) {
    Color(SunColors.DAY_SUN).copy(alpha = SunColors.DAY_TICK_ALPHA)
} else {
    MaterialTheme.colorScheme.primary
}

/** 当前是不是亮色主题：按卡片底色（surface）的亮度判断。 */
@Composable
private fun isLightSunPalette(): Boolean = MaterialTheme.colorScheme.surface.luminance() > 0.5f
