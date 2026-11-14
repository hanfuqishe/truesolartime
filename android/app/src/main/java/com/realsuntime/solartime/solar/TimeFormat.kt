package com.realsuntime.solartime.solar

import java.time.LocalDate
import java.time.LocalTime
import java.time.format.DateTimeFormatter

object TimeFormat {

    private val clock = DateTimeFormatter.ofPattern("HH:mm")
    private val clockWithSeconds = DateTimeFormatter.ofPattern("HH:mm:ss")

    fun clock(time: LocalTime?): String = time?.format(clock) ?: "--:--"

    fun clockWithSeconds(time: LocalTime): String = time.format(clockWithSeconds)

    /** 时区偏移（秒）→ `UTC+8` / `UTC-3:30`。左栏标准时钟的标签用它，免得「标准时间」到底是哪里的。 */
    fun utcOffsetLabel(offsetSeconds: Int): String {
        val minutes = Math.round(offsetSeconds / 60.0).toInt()
        val sign = if (minutes < 0) "-" else "+"
        val abs = kotlin.math.abs(minutes)
        val hours = abs / 60
        val rest = abs % 60
        return if (rest == 0) "UTC$sign$hours" else "UTC$sign$hours:%02d".format(rest)
    }

    /** 带正负号的时长，例如 "+14 分 22 秒"、"-2 分 05 秒"。 */
    fun signedDuration(seconds: Double): String {
        val sign = if (seconds < 0) "-" else "+"
        return sign + minutesSeconds(seconds)
    }

    /** 不带符号的时长，例如 "14 分 22 秒"、"13 小时 0 分"。 */
    fun minutesSeconds(seconds: Double): String {
        val total = kotlin.math.abs(seconds).toLong()
        val hours = total / 3600
        val minutes = (total % 3600) / 60
        val rest = total % 60
        return when {
            hours > 0 -> "$hours 小时 $minutes 分"
            minutes > 0 -> "$minutes 分 %02d 秒".format(rest)
            else -> "$rest 秒"
        }
    }

    /** 例如 "13 小时 42 分"。 */
    fun duration(seconds: Long?): String {
        if (seconds == null) return "--"
        val hours = seconds / 3600
        val minutes = (seconds % 3600) / 60
        return "$hours 小时 %02d 分".format(minutes)
    }

    /** 倒计时，例如 "01:23:45"。 */
    fun countdown(seconds: Long): String {
        val safe = seconds.coerceAtLeast(0)
        return "%02d:%02d:%02d".format(safe / 3600, (safe % 3600) / 60, safe % 60)
    }

    fun dateWithWeekday(date: LocalDate): String {
        val weekdays = listOf("星期一", "星期二", "星期三", "星期四", "星期五", "星期六", "星期日")
        return "%d 月 %d 日 · %s".format(date.monthValue, date.dayOfMonth, weekdays[date.dayOfWeek.value - 1])
    }

    fun coordinates(latitude: Double, longitude: Double): String =
        "%.4f°%s  %.4f°%s".format(
            kotlin.math.abs(latitude), if (latitude >= 0) "N" else "S",
            kotlin.math.abs(longitude), if (longitude >= 0) "E" else "W",
        )
}
