package com.realsuntime.solartime.data

import android.content.Context
import com.realsuntime.solartime.solar.SolarTimeMath
import java.time.Instant
import java.time.ZoneId
import java.time.ZoneOffset

/**
 * 「观测点所在地的法定标准时间」这一层口径的唯一入口，首页与桌面卡片都走这里，避免两处口径不一致。
 *
 * 规则（与鸿蒙版一致，只是多照顾了一点夏令时）：
 *  1. 中国境内（含港澳台与新疆）恒为 UTC+8，钉在 `Asia/Shanghai`，不按经度算；
 *  2. 境外优先用**设备时区** —— 人在当地时手机通常已自动切换，还能顺带照顾夏令时；
 *  3. 设备时区与观测点的标准偏移对不上时（人在国内、手工指定了纽约坐标），退到固定的
 *     `GMT±H:MM`，由 [ZoneTable] 按国家码 + 经度给出偏移（多时区大国按经度分段）。
 *
 * 没有国家码（未联网、没配 Key、刚启动）时，[ZoneTable] 的兜底是按经度每 15° 取整。
 */
object LocalZone {

    /**
     * 观测点的标准时区偏移（秒，相对 UTC，**不含夏令时**）。
     *
     * 用于「换个地方就是另一个时区」这类粗判断；界面显示请用 [offsetSeconds]（含夏令时）。
     */
    fun standardOffsetSeconds(context: Context, place: Place): Int = ZoneTable.offsetSeconds(
        countryCode = DistrictResolver.cachedCountryCode(context, place),
        longitude = place.longitude,
        fallbackSeconds = SolarTimeMath.standardZoneOffsetSeconds(place.latitude, place.longitude),
    )

    /** 观测点此刻的法定时区；`TextClock#setTimeZone` 也吃它的 [ZoneId.id]。 */
    fun zoneIdFor(context: Context, place: Place, now: Instant): ZoneId {
        if (SolarTimeMath.isInChinaBbox(place.latitude, place.longitude)) return ZoneId.of("Asia/Shanghai")
        val standard = standardOffsetSeconds(context, place)
        val system = ZoneId.systemDefault()
        // 比的是**标准**偏移而不是当前偏移：德国夏天设备时区是 +2、表里是 +1，按当前偏移比会
        // 误判成「设备时区跟这里不是一个地方」，把 CEST 显示成 CET。标准偏移一致就说明
        // 设备就在这个时区里（或紧邻），直接用它，顺带把夏令时也算对。
        if (system.rules.getStandardOffset(now).totalSeconds == standard) return system
        return ZoneId.of(gmtLabel(standard))
    }

    /** 观测点此刻的标准时间相对 UTC 的偏移（秒）；夏令时地区会跟着设备时区走。 */
    fun offsetSeconds(context: Context, place: Place, now: Instant): Int =
        zoneIdFor(context, place, now).rules.getOffset(now).totalSeconds

    /** 该偏移对应的 [ZoneOffset]；超出手动换算范围时夹到 ±18 小时（java.time 的上限）。 */
    fun zoneOffset(offsetSeconds: Int): ZoneOffset =
        ZoneOffset.ofTotalSeconds(offsetSeconds.coerceIn(-18 * 3600, 18 * 3600))

    /**
     * `-18000` → `"GMT-05:00"`。
     *
     * `TextClock#setTimeZone` 与 `ZoneId.of` 都只认带 `GMT` 前缀、且**小时补零**的写法：
     * 纯 `-05:00` 会被 `TimeZone.getTimeZone` 当成 GMT，`GMT-5:00` 则会被 `ZoneId.of` 拒绝。
     */
    internal fun gmtLabel(offsetSeconds: Int): String {
        val minutes = offsetSeconds / 60
        val sign = if (minutes < 0) "-" else "+"
        val abs = kotlin.math.abs(minutes)
        return "GMT$sign%02d:%02d".format(abs / 60, abs % 60)
    }
}
