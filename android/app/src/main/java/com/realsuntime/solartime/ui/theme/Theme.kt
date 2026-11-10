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
    primary = Color(0xFFFFB870),
    onPrimary = Color(0xFF4A2600),
    primaryContainer = Color(0xFF6A3B00),
    onPrimaryContainer = Color(0xFFFFDDB8),
    secondary = Color(0xFFD9C4A8),
    onSecondary = Color(0xFF3B2F1F),
    secondaryContainer = Color(0xFF52443A),
    onSecondaryContainer = Color(0xFFF6E4CC),
    background = Color(0xFF151210),
    onBackground = Color(0xFFEDE0D6),
    surface = Color(0xFF1D1916),
    onSurface = Color(0xFFEDE0D6),
    surfaceVariant = Color(0xFF3A2F27),
    onSurfaceVariant = Color(0xFFD8C6B8),
    outline = Color(0xFF9F8D80),
    outlineVariant = Color(0xFF4A3F37),
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
