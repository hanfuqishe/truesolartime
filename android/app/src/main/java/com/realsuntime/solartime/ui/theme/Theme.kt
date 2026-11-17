package com.realsuntime.solartime.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
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
 *   太阳点 = **亮金** [SunColors.DAY_SUN]（`#D9A520`，用户要的金色，是主角），外加一圈
 *   50% 的深金细描边 [SunColors.DAY_SUN_RING]（`#8A6508`，与弧的对比度 ≈3.39）把点从淡金弧里切出来；
 *   日出 / 日落刻度 = 同太阳金、70% 透明（比点淡一档）。
 * - **暗色主题**：全部保持原来的实色主色（深蓝底上那档金色正好，调淡反而糊），也不加描边。
 *
 * 亮色主题里「白天弧 vs 夜晚虚线」不再靠深浅区分（弧故意更淡），而是靠色相：
 * 暖金的 `r − b` 比中性灰大 0.17 左右（`SunColorsTest` 里有断言）。
 *
 * 判断依据是当前 `surface` 的亮度（主题函数只换 colorScheme，没有额外的暗色标志）；
 * `#FFFBF6` 与 `#16203A` 亮度差距极大，不会误判。
 */
@Composable
fun sunDayArcColor(): Color = if (isLightSunPalette()) Color(SunColors.DAY_ARC) else MaterialTheme.colorScheme.primary

/** 太阳点的填充色：亮色主题是亮金 `#D9A520`；暗色主题仍是主色。 */
@Composable
fun sunDotColor(): Color = if (isLightSunPalette()) Color(SunColors.DAY_SUN) else MaterialTheme.colorScheme.primary

/**
 * 太阳点外圈的细描边（亮色主题：深金 `#8A6508` @ 50%）。
 *
 * 亮金点与淡金弧只差 ≈1.43 的对比度，靠这圈深边把点「框」出来；暗色主题不画描边，返回 null。
 */
@Composable
fun sunDotRingColor(): Color? = if (isLightSunPalette()) {
    Color(SunColors.DAY_SUN_RING).copy(alpha = SunColors.DAY_SUN_RING_ALPHA)
} else {
    null
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
