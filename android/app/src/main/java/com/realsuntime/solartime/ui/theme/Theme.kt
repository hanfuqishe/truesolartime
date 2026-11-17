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
 * 太阳卡圆盘「白天弧」的颜色（主题色板里的派生色，不新增硬编码 hex）。
 *
 * - **亮色主题**：主色的 **62% 不透明度**。白底卡片上主色 `#B4550A` 这类橙棕实色太沉、
 *   太重，压住了整张卡片；调到 62% 后合成出来约 `#D19464`，仍是暖色、仍和夜晚的灰色虚线
 *   （`outline` + 虚线）一眼能分开。
 * - **暗色主题**：保持实色主色（深蓝底上现在这档金色正合适，调淡反而糊）。
 *
 * 只改白天弧：地平线（`outline`）、太阳点与日出日落刻度（`primary` 实色）、
 * 运动箭头（`onSurfaceVariant`）都保持原样 —— 弧变浅之后，实色太阳点正好形成层次。
 *
 * 判断依据是当前 `surface` 的亮度（主题函数只换 colorScheme，没有额外的暗色标志），
 * 亮色主题的 `#FFFBF6` 与暗色主题的 `#16203A` 亮度差距极大，不会误判。
 */
@Composable
fun sunDayArcColor(): Color {
    val scheme = MaterialTheme.colorScheme
    return if (scheme.surface.luminance() > 0.5f) {
        scheme.primary.copy(alpha = 0.62f)
    } else {
        scheme.primary
    }
}
