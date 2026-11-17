package com.realsuntime.solartime.data

import com.realsuntime.solartime.solar.SolarTimeMath
import java.time.Instant
import java.time.ZoneId

/**
 * 「所在国的标准时间」的**唯一判定入口**：界面左栏的标准时钟、`UTC+8` 标签、日出/上中天/日落、
 * 以及真太阳时换算的基准偏移，全都走这里，避免同一块界面出现两个来源的时区。
 *
 * 为什么不直接用坐标所在的 tzdata 时区：一个国家常有多块时区，但**官方时间**往往全国统一。
 * 最典型的是中国 —— `Asia/Shanghai` 是 +8、`Asia/Urumqi` 是 +6，而中国全境官方时间都是 +8；
 * 若按 tzdata 走，乌鲁木齐会显示成 UTC+6，与用户预期不符。南极考察站同理：中国四个站
 * 官方都按北京时间（+8）。
 *
 * 判定顺序：
 *  1. 中国境内（国家码 cn/hk/mo/tw，或没有国家码时落在 [SolarTimeMath.isInChinaBbox] 内）→ +480；
 *  2. 中国南极考察站（中山 / 长城 / 昆仑 / 泰山，按站点坐标 ±0.5° 判定）→ +480；
 *  3. 其它国家：有 IANA `tzId` 就用它的规则（含夏令时）；没有就退回 [ZoneTable] 的
 *     国家表 + 多时区大国按经度分段 —— 那同样是「国家标准时间」，不是地理经度。
 *
 * 纯函数、不碰 Android SDK（`ZoneId` 是 java.time），可以直接单测。
 */
object CivicTime {

    /** 中国官方标准时间：UTC+8，单位分钟。 */
    const val CHINA_MINUTES = 480

    private val CHINA_CODES = setOf("cn", "hk", "mo", "tw")

    /**
     * 中国南极考察站（站名仅用于排查）。坐标取各站生活区/主楼附近，
     * 判定半径 [STATION_HALF_SPAN_DEG]（0.5°，约 55 km）足以覆盖站区与周边作业点。
     */
    private data class Station(val name: String, val latitude: Double, val longitude: Double)

    private val ANTARCTIC_STATIONS = listOf(
        Station("中山站", -69.3733, 76.3800),
        Station("长城站", -62.2167, -58.9667),
        Station("昆仑站", -80.4167, 77.1167),
        Station("泰山站", -73.8667, 76.9667),
    )

    private const val STATION_HALF_SPAN_DEG = 0.5

    /**
     * 观测点所在国的标准时间偏移（分钟）。
     *
     * @param countryCode ISO 3166-1 alpha-2；未知传 null / 空串（此时才用中国包围盒兜底）
     * @param tzId 可选的 IANA 时区 ID（如 `America/New_York`）。数据层目前拿不到城市级 ID，
     *   调用方通常传 null，退回 [ZoneTable]；将来逆地理给出 tzId 时它的优先级最高。
     * @param now 计算夏令时用的时刻（时区规则按它取偏移）；默认当前时刻。
     */
    fun standardOffsetMinutes(
        latitude: Double,
        longitude: Double,
        countryCode: String?,
        tzId: String? = null,
        now: Instant = Instant.now(),
    ): Int {
        if (isChina(latitude, longitude, countryCode)) return CHINA_MINUTES
        if (isChineseAntarcticStation(latitude, longitude)) return CHINA_MINUTES
        val zone = tzId?.let { runCatching { ZoneId.of(it) }.getOrNull() }
        if (zone != null) {
            return zone.rules.getOffset(now).totalSeconds / 60
        }
        return ZoneTable.offsetSeconds(
            countryCode = countryCode,
            longitude = longitude,
            fallbackSeconds = SolarTimeMath.standardZoneOffsetSeconds(latitude, longitude),
        ) / 60
    }

    /** 同上，单位秒 —— 界面与太阳计算都用秒。 */
    fun standardOffsetSeconds(
        latitude: Double,
        longitude: Double,
        countryCode: String?,
        tzId: String? = null,
        now: Instant = Instant.now(),
    ): Int = standardOffsetMinutes(latitude, longitude, countryCode, tzId, now) * 60

    /**
     * 是不是中国境内（含港澳台）。
     *
     * 有国家码时**以国家码为准**（新德里在包围盒里，但不是中国）；没有国家码才退回包围盒。
     * 与鸿蒙 `SolarTimeMath.isInChina`、iOS `GeoRegion.isInChina` 同一套规则。
     */
    fun isChina(latitude: Double, longitude: Double, countryCode: String?): Boolean {
        val code = countryCode?.trim()?.lowercase().orEmpty()
        if (code.length == 2) return code in CHINA_CODES
        return SolarTimeMath.isInChinaBbox(latitude, longitude)
    }

    /** 是否落在中国南极考察站附近（站务时间按北京时间，与 tzdata 的 Antarctica 各区域时区无关）。 */
    fun isChineseAntarcticStation(latitude: Double, longitude: Double): Boolean =
        ANTARCTIC_STATIONS.any { station ->
            kotlin.math.abs(latitude - station.latitude) <= STATION_HALF_SPAN_DEG &&
                kotlin.math.abs(longitude - station.longitude) <= STATION_HALF_SPAN_DEG
        }
}
