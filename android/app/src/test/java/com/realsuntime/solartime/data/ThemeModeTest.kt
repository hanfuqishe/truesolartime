package com.realsuntime.solartime.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 主题模式：首页与桌面卡片共用同一套判定（[ThemeMode.isDark]），所以规则本身要有单测钉住。
 */
class ThemeModeTest {

    @Test
    fun autoFollowsSunriseAndSunset() {
        // 默认行为：白天亮色、夜晚暗色 —— 与改动前完全一致
        assertFalse(ThemeMode.AUTO.isDark(sunIsUp = true))
        assertTrue(ThemeMode.AUTO.isDark(sunIsUp = false))
    }

    @Test
    fun lightIsForcedRegardlessOfTheSun() {
        assertFalse(ThemeMode.LIGHT.isDark(sunIsUp = true))
        // 深夜强制亮色：忽略日出日落
        assertFalse(ThemeMode.LIGHT.isDark(sunIsUp = false))
    }

    @Test
    fun darkIsForcedRegardlessOfTheSun() {
        // 正午强制暗色：忽略日出日落
        assertTrue(ThemeMode.DARK.isDark(sunIsUp = true))
        assertTrue(ThemeMode.DARK.isDark(sunIsUp = false))
    }

    @Test
    fun autoIsTheDefaultForMissingOrBrokenValues() {
        assertEquals(ThemeMode.AUTO, ThemeMode.fromName(null))
        assertEquals(ThemeMode.AUTO, ThemeMode.fromName(""))
        assertEquals(ThemeMode.AUTO, ThemeMode.fromName("SYSTEM"))
        assertEquals(ThemeMode.AUTO, ThemeMode.fromName("light"))
    }

    @Test
    fun storedNamesRoundTrip() {
        ThemeMode.entries.forEach { mode ->
            assertEquals(mode, ThemeMode.fromName(mode.name))
        }
        // 正好三个选项：自动 / 亮色 / 暗色
        assertEquals(listOf(ThemeMode.AUTO, ThemeMode.LIGHT, ThemeMode.DARK), ThemeMode.entries.toList())
    }
}
