package com.realsuntime.solartime.solar

/**
 * 定位不可用（未知态）时各个读数的占位符。
 *
 * 统一口径（产品最终确认）：
 * * **温度**（逐时行每格）是 `-°`（一个半角连字符 + 度数符号）；
 * * **其它所有占位**都是 `--`（两个半角连字符）；
 * * 真太阳时的时钟是 `--:--:--`（半角，三组，与真实时间同版式）。
 *
 * 一律用**半角连字符** U+002D：全角 `－`（U+FF0D）、短破折号 `‒`（U+2012）、长破折号 `—`（U+2014）
 * 在字体里会被画成一条长横或与数字不同宽的字形 —— 既不像「空位」，也会把版式撑歪。
 *
 * 这些常量放在代码里而不是 `strings.xml`：它们不是「文案」而是**版式的一部分** ——
 * 时钟占位符必须和真实时间**同字号、同高、同宽**，翻译或加格式参数只会把版式搅乱。
 * 可见文案（「定位不可用」等）仍在三份 `strings.xml` 里。
 */
object Placeholders {

    /** 真太阳时：三组 `--`，宽度与 `12:34:56` 对齐（主字号 `--:--` + 半高 `:--`）。 */
    const val TIME = "--:--:--"

    /** 时辰、日出／日落等短读数：两个半角连字符。 */
    const val SHORT = "--"

    /** 高度角、白昼时长、天气、经纬度等「没有这个值」的占位：两个半角连字符。 */
    const val DASH = "--"

    /**
     * 逐时行的温度占位：`-°`（一个半角连字符 + 度数符号）。
     *
     * 温度只有「有」和「没有」两种，一个连字符就够 —— 两个连字符在 22dp 的格子里会挤成一条线。
     * 度数符号跟着占位符一起写在这里（`weather_temp` 是 `%1$d°`，塞不进字符串）。
     */
    const val TEMPERATURE = "-°"

    fun trueSolarTime(): String = TIME

    fun shichen(): String = SHORT

    fun altitude(): String = DASH

    fun daylight(): String = DASH

    fun weather(): String = DASH

    fun temperature(): String = TEMPERATURE

    fun temperatureRange(): String = ""

    fun coordinates(): String = DASH

    /** 真太阳时钟表那一行：主字号的 `--:--`（半高的秒另由 UI 补 `:--`）。 */
    fun trueSolarClockMain(): String = "--:--"

    /** 真太阳时半高的秒那一组（含冒号），与真实时间的 `:ss` 占同样的宽度。 */
    fun trueSolarClockSeconds(): String = ":--"
}
