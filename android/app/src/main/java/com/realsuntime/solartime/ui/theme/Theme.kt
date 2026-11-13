package com.realsuntime.solartime.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
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

@Composable
fun TrueSolarTimeTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    MaterialTheme(
        colorScheme = if (darkTheme) DarkColors else LightColors,
        typography = AppTypography,
        content = content,
    )
}
