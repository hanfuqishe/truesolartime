package com.realsuntime.solartime.solar

/**
 * 定位不可用（未知态）时各个读数的占位符。
 *
 * 放在代码里而不是 `strings.xml`：它们不是「文案」而是**版式的一部分** ——
 * 时钟占位符必须和真实时间**同字号、同高、同宽**（`HH:mm` + 半高 `:ss`），
 * 翻译或加格式参数只会把版式搅乱。可见文案（「定位不可用」等）仍在三份 `strings.xml` 里。
 */
object Placeholders {

    /** 真太阳时：三组 `--`，宽度与 `12:34:56` 对齐（主字号 `--:--` + 半高 `:--`）。 */
    const val TIME = "--:--:--"

    /** 时辰、日出／日落等短读数（半角连字符，与 [TIME] 同一套字符）。 */
    const val SHORT = "--"

    /** 高度角、白昼时长、天气、经纬度：表示「没有这个值」。 */
    const val DASH = "—"

    /**
     * 逐时行的温度占位：`--°`。
     *
     * 不能在 `weather_temp`（`%1$d°`）里塞字符串，所以度数符号跟着占位符一起写在这里。
     */
    const val TEMPERATURE = "--°"

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
