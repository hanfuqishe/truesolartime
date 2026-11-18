package com.realsuntime.solartime.data

import java.time.Instant
import java.time.LocalTime
import java.time.ZoneId

/**
 * 「定位不可用（未知态）」的判定与未知态下的时间口径。
 *
 * 为什么需要这一层：用户选了「实时跟随 GPS」却没授权、或授权了却一直拿不到 fix 时，
 * 老版本会**继续沿用上一个地点**（预设城市／上一次定位）的经纬度，于是界面照常显示那个
 * 城市的真太阳时、天气、地图 —— 看起来像「定位到了那里」。未知态就是把这个猜测收起来：
 * 太阳相关的读数一律留空，标准时间改用**系统时区**，地图缩到全球底图且不打标记。
 *
 * 这里全是纯逻辑（不碰 Android），单测可以直接钉住判定与占位口径。
 */
object LocationAvailability {

    /**
     * 未知态正文的判定：**跟随 GPS** 且**没有有效定位**。
     *
     * 预设城市与手动坐标都是用户明确指定的位置（[PlaceSource.MANUAL]），永远不会是未知态；
     * 默认坐标（[PlaceSource.DEFAULT]）只是「还没选过」的占位，仍按跟随 GPS 处理。
     *
     * @param followGps 用户是否处于「跟随 GPS」（见 [followsGps] 与 `AppSettings.followGps`）
     * @param hasFix 当前是否已有可信定位（本次跟随拿到的 fix，或刚启动时手上的上一次 GPS 地点）
     */
    fun isUnknown(followGps: Boolean, hasFix: Boolean): Boolean = followGps && !hasFix

    /**
     * 这个地点来源算不算「跟随 GPS」。
     *
     * 只有 [PlaceSource.MANUAL]（预设城市 / 手动坐标）是用户明确选的位置；GPS 与默认坐标都跟随定位。
     */
    fun followsGps(source: PlaceSource): Boolean = source != PlaceSource.MANUAL

    /**
     * 未知态下标准时间的时区偏移（秒）：**系统时区**。
     *
     * 不能再用上一次地点的时区（那正是「看起来像定位到了那个城市」的一部分）。
     *
     * @param now 计算夏令时用的时刻
     * @param zoneId 默认取系统时区；单测传固定时区，断言不同时区下的偏移
     */
    fun systemOffsetSeconds(now: Instant, zoneId: ZoneId = ZoneId.systemDefault()): Int =
        zoneId.rules.getOffset(now).totalSeconds

    /** 未知态下标准时钟的读数：系统时区的当地时间（与 [systemOffsetSeconds] 同一口径）。 */
    fun systemStandardTime(now: Instant, zoneId: ZoneId = ZoneId.systemDefault()): LocalTime =
        now.atZone(zoneId).toLocalTime()

    /**
     * 未知态没有太阳高度角，主题（白天／夜间）只能按钟点粗判：06:00–18:00 算白天。
     *
     * 刻意不用上一次地点的 [com.realsuntime.solartime.solar.SolarSnapshot.isDay]：
     * 那等于继续用旧坐标推断「现在是白天」，与未知态自相矛盾。
     */
    fun isDaytime(localStandardTime: LocalTime): Boolean = localStandardTime.hour in 6..17
}
