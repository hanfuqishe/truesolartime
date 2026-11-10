package com.realsuntime.solartime.solar

import java.time.Instant
import kotlin.math.roundToLong

/**
 * 十二时辰：以真太阳时为准，每个时辰两小时，子时自 23:00 起。
 */
object Shichen {

    val NAMES = listOf("子", "丑", "寅", "卯", "辰", "巳", "午", "未", "申", "酉", "戌", "亥")
    private const val SECONDS_PER_SICHEN = 7200.0

    /** 返回 0..11，0 为子时。传入真太阳时当天的秒数。 */
    fun indexOf(trueSolarSecondsOfDay: Double): Int {
        val shifted = ((trueSolarSecondsOfDay + 3600.0) % 86_400.0 + 86_400.0) % 86_400.0
        return (shifted / SECONDS_PER_SICHEN).toInt() % 12
    }

    fun name(index: Int): String = NAMES[index] + "时"

    /** 例如 "23:00 – 01:00"。 */
    fun rangeText(index: Int): String {
        val start = (index * 2 + 23) % 24
        val end = (start + 2) % 24
        return "%02d:00 – %02d:00".format(start, end)
    }

    fun secondsIntoShichen(trueSolarSecondsOfDay: Double): Double {
        val shifted = ((trueSolarSecondsOfDay + 3600.0) % 86_400.0 + 86_400.0) % 86_400.0
        return shifted % SECONDS_PER_SICHEN
    }

    fun secondsToNextShichen(trueSolarSecondsOfDay: Double): Double =
        SECONDS_PER_SICHEN - secondsIntoShichen(trueSolarSecondsOfDay)

    /** 时初 / 时正，各占一个时辰的前后一小时。 */
    fun halfLabel(trueSolarSecondsOfDay: Double): String =
        if (secondsIntoShichen(trueSolarSecondsOfDay) < 3600.0) "初" else "正"

    /** 刻：每 15 分钟一刻，每半个时辰四刻，返回 1..4。 */
    fun quarterOfHalf(trueSolarSecondsOfDay: Double): Int {
        val into = secondsIntoShichen(trueSolarSecondsOfDay)
        return (((into % 3600.0) / 900.0).toInt()) + 1
    }

    /** 下一个时辰交接的绝对时刻（均时差变化率极小，线性外推误差在 1 秒内）。 */
    fun nextBoundary(after: Instant, longitude: Double): Instant {
        val remaining = secondsToNextShichen(SolarTimeMath.trueSolarSecondsOfDay(after, longitude))
        return after.plusMillis((remaining * 1000).roundToLong())
    }
}
