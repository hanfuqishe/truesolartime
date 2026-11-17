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
 *   太阳点 = **纯色实心核心 2.75dp**（太阳金 [SunColors.DAY_SUN] `#D9A520`，alpha 1.0）
 *   \+ 外圈光晕（同色 alpha 0.35 → 0，2.75→5.5dp）；核心画在光晕之上，弧线不会透出来；
 *   日出 / 日落刻度 = 同样的金、70% 透明（比点淡一档）。
 * - **暗色主题**：白天弧仍是实色主色（深蓝底上那档金色正好，调淡反而糊）；太阳点结构相同，
 *   颜色换成夜金 [SunColors.NIGHT_SUN]（`#F5D68A`，与 `DarkColors.primary` 同色）。
 *
 * 亮色主题里「白天弧 vs 夜晚虚线」不再靠深浅区分（弧故意更淡），而是靠色相：
 * 暖金的 `r − b` 比中性灰大 0.17 左右（`SunColorsTest` 里有断言）。
 *
 * 判断依据是当前 `surface` 的亮度（主题函数只换 colorScheme，没有额外的暗色标志）；
 * `#FFFBF6` 与 `#16203A` 亮度差距极大，不会误判。
 */
@Composable
fun sunDayArcColor(): Color = if (isLightSunPalette()) Color(SunColors.DAY_ARC) else MaterialTheme.colorScheme.primary

/**
 * 太阳点核心（实心、不透明）的颜色：亮色主题 `#D9A520`、暗色主题 `#F5D68A`。
 *
 * 调用方把它**直接**传给 `drawCircle(color = ...)`：不套 Brush、不 `copy(alpha = ...)`，
 * 保证核心 alpha 恒为 1.0（真机上曾经因为整颗点走渐变而变成半透明，弧线透出来）。
 */
@Composable
fun sunDotColor(): Color = if (isLightSunPalette()) Color(SunColors.DAY_SUN) else Color(SunColors.NIGHT_SUN)

/**
 * 柔光圆点的三档色标（**逐时时间轴「现在」圆点**用）：满色 → 45% → 全透明。
 *
 * 位置 / alpha 直接取 [SunColors.softDotStopPositions] / [SunColors.softDotStopAlphas]：
 * 0 / 0.5 / 1 与 1.0 / 0.45 / 0，就是时间轴圆点原来的曲线（上一轮改成 0.55/1.0 后用户说变差了，已恢复）。
 */
fun softDotStops(color: Color): List<Pair<Float, Color>> {
    val positions = SunColors.softDotStopPositions()
    val alphas = SunColors.softDotStopAlphas()
    return positions.mapIndexed { index, position -> position to color.copy(alpha = alphas[index]) }
}

/**
 * 太阳点**外圈光晕**的色标：内沿（= 核心半径 2.75dp）alpha 0.35 → 外沿（5.5dp）0。
 *
 * 光晕的圆心 / 半径由绘制处显式传给 `Brush.radialGradient(center = 太阳点, radius = 5.5dp)`，
 * 所以这里只给色标；渐变起点落在 0.5（2.75 / 5.5），核心那一段不参与光晕。
 */
fun sunDotGlowStops(color: Color): List<Pair<Float, Color>> {
    val positions = SunColors.sunDotGlowStopPositions()
    val alphas = SunColors.sunDotGlowStopAlphas()
    return positions.mapIndexed { index, position -> position to color.copy(alpha = alphas[index]) }
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
