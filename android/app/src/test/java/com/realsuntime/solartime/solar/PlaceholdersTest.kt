package com.realsuntime.solartime.solar

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 未知态（定位不可用）的占位符格式。
 *
 * 口径：
 * * 真太阳时是**三组两个半角连字符**（`--:--:--`），宽度与 `12:34:56` 一致；
 * * 时辰是 `--`；
 * * 高度角 / 白昼 / 天气是 `—`（em dash，不是减号也不是空串）；
 * * 逐时温度是 `--°`。
 */
class PlaceholdersTest {

    /** 占位符必须是**半角** `-`，不能是用户明确否掉的全角 `－`（U+FF0D）或 em dash。 */
    @Test
    fun clockPlaceholderUsesAsciiHyphensOnly() {
        assertEquals("--:--:--", Placeholders.trueSolarTime())
        assertEquals("--:--:--", Placeholders.TIME)
        assertEquals(0, Placeholders.TIME.count { it == '\uFF0D' })
        assertEquals(0, Placeholders.TIME.count { it == '\u2014' })
        assertEquals(0, Placeholders.TIME.count { it == '\u2012' })
        assertEquals("六条半角连字符", 6, Placeholders.TIME.count { it == '-' })
    }

    @Test
    fun trueSolarTimePlaceholderHasThreeGroups() {
        // 主字号两段 + 半高一段拼起来正好是完整占位符（UI 就是这么分两段画的）。
        assertEquals(
            Placeholders.TIME,
            Placeholders.trueSolarClockMain() + Placeholders.trueSolarClockSeconds(),
        )
        assertEquals("--:--", Placeholders.trueSolarClockMain())
        assertEquals(":--", Placeholders.trueSolarClockSeconds())
        // 三组占位：恰好两个冒号、六个破折号。
        assertEquals(2, Placeholders.TIME.count { it == ':' })
        assertEquals("总长度是 8 个字符（HH:mm:ss）", 8, Placeholders.TIME.length)
    }

    @Test
    fun shichenPlaceholderIsTwoDashes() {
        assertEquals("--", Placeholders.shichen())
        assertEquals("--", Placeholders.SHORT)
    }

    @Test
    fun dashPlaceholdersAreEmDashes() {
        assertEquals("—", Placeholders.altitude())
        assertEquals("—", Placeholders.daylight())
        assertEquals("—", Placeholders.weather())
        assertEquals("—", Placeholders.coordinates())
        assertEquals("—", Placeholders.DASH)
        // 破折号不能被写成 ASCII 的 '-'（那是「缺一位数字」的样子，会读成 0）。
        assertNotEquals("-", Placeholders.DASH)
        assertTrue("破折号是单个字符", Placeholders.DASH.length == 1)
        // 温度区间没有读数时整段不显示（不是画一个 `—`）。
        assertEquals("", Placeholders.temperatureRange())
    }

    /** 逐时行的温度占位：`--°`（两个半角连字符 + 度数符号，不带 C）。 */
    @Test
    fun temperaturePlaceholderIsTwoDashesAndADegree() {
        assertEquals("--°", Placeholders.temperature())
        assertEquals("--°", Placeholders.TEMPERATURE)
        assertEquals(2, Placeholders.TEMPERATURE.count { it == '-' })
        assertTrue("以度数符号结尾", Placeholders.TEMPERATURE.endsWith("°"))
    }
}
