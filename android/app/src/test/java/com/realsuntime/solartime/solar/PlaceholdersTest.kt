package com.realsuntime.solartime.solar

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 未知态（定位不可用）的占位符格式 —— 产品最终统一的口径：
 *
 * | 位置 | 占位符 |
 * |---|---|
 * | 温度（逐时行每格） | `-°`（一个半角连字符 + 度数符号）|
 * | 其它所有占位（高度角 / 经纬度 / 天气 / 白昼） | `--`（两个半角连字符）|
 * | 时辰 | `--` |
 * | 真太阳时 | `--:--:--` |
 *
 * 这个测试把每个常量的**字符构成**钉死：只允许半角连字符、冒号、度数符号三种字符，
 * 并且必须**不含** U+2014（—）/ U+2012（‒）/ U+FF0D（－）。
 */
class PlaceholdersTest {

    /** 未知态允许出现的三种字符：半角连字符、冒号、度数符号。 */
    private val allowedChars = setOf('-', ':', '°')

    /** 明确禁用的「像长横」的字符：全角减号、短破折号、长破折号。 */
    private val forbiddenChars = setOf('\uFF0D', '\u2012', '\u2014')

    /** 所有占位常量/函数的一张表（新增占位符时必须补进来，否则下面的断言就漏掉了）。 */
    private fun allPlaceholders(): List<Pair<String, String>> = listOf(
        "TIME" to Placeholders.TIME,
        "SHORT" to Placeholders.SHORT,
        "DASH" to Placeholders.DASH,
        "TEMPERATURE" to Placeholders.TEMPERATURE,
        "trueSolarTime()" to Placeholders.trueSolarTime(),
        "shichen()" to Placeholders.shichen(),
        "altitude()" to Placeholders.altitude(),
        "daylight()" to Placeholders.daylight(),
        "weather()" to Placeholders.weather(),
        "temperature()" to Placeholders.temperature(),
        "coordinates()" to Placeholders.coordinates(),
        "trueSolarClockMain()" to Placeholders.trueSolarClockMain(),
        "trueSolarClockSeconds()" to Placeholders.trueSolarClockSeconds(),
    )

    @Test
    fun everyPlaceholderUsesOnlyAsciiHyphensColonsAndDegree() {
        for ((name, value) in allPlaceholders()) {
            assertTrue("$name 是空的", value.isNotEmpty())
            val bad = value.filter { it !in allowedChars }
            assertEquals("$name = \"$value\" 含不允许的字符", "", bad)
            for (forbidden in forbiddenChars) {
                assertEquals(
                    "$name = \"$value\" 含 U+${forbidden.code.toString(16).uppercase()}",
                    0,
                    value.count { it == forbidden },
                )
            }
        }
    }

    /** 温度占位：`-°`（1 个半角连字符 + 度数符号）。 */
    @Test
    fun temperaturePlaceholderIsOneHyphenAndADegree() {
        assertEquals("-°", Placeholders.temperature())
        assertEquals("-°", Placeholders.TEMPERATURE)
        assertEquals("只有一个连字符", 1, Placeholders.TEMPERATURE.count { it == '-' })
        assertEquals("长度是 2", 2, Placeholders.TEMPERATURE.length)
        assertTrue("以度数符号结尾", Placeholders.TEMPERATURE.endsWith("°"))
    }

    /** 其它占位：`--`（2 个半角连字符）—— 高度角、经纬度、天气、白昼都用它。 */
    @Test
    fun dashPlaceholderIsTwoAsciiHyphens() {
        assertEquals("--", Placeholders.DASH)
        assertEquals(2, Placeholders.DASH.length)
        assertEquals(2, Placeholders.DASH.count { it == '-' })
        // 四个「没有这个值」的读数全部指向同一个常量。
        assertEquals(Placeholders.DASH, Placeholders.altitude())
        assertEquals(Placeholders.DASH, Placeholders.daylight())
        assertEquals(Placeholders.DASH, Placeholders.weather())
        assertEquals(Placeholders.DASH, Placeholders.coordinates())
        // 温度区间没有读数时整段不显示（不是画一个占位）。
        assertEquals("", Placeholders.temperatureRange())
    }

    /** 时辰：保持 `--`（与 [Placeholders.SHORT] 同一个值）。 */
    @Test
    fun shichenPlaceholderIsTwoHyphens() {
        assertEquals("--", Placeholders.shichen())
        assertEquals("--", Placeholders.SHORT)
        assertEquals(Placeholders.SHORT, Placeholders.shichen())
    }

    /** 真太阳时：三组 `--`（`--:--:--`），主段 + 半高秒段拼起来正好是完整占位。 */
    @Test
    fun trueSolarTimePlaceholderHasThreeGroups() {
        assertEquals("--:--:--", Placeholders.trueSolarTime())
        assertEquals("--:--:--", Placeholders.TIME)
        assertEquals(
            Placeholders.TIME,
            Placeholders.trueSolarClockMain() + Placeholders.trueSolarClockSeconds(),
        )
        assertEquals("--:--", Placeholders.trueSolarClockMain())
        assertEquals(":--", Placeholders.trueSolarClockSeconds())
        assertEquals("六个半角连字符", 6, Placeholders.TIME.count { it == '-' })
        assertEquals("两个冒号", 2, Placeholders.TIME.count { it == ':' })
        assertEquals("总长度是 8 个字符（HH:mm:ss）", 8, Placeholders.TIME.length)
    }
}
