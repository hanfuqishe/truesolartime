package com.realsuntime.solartime.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.ZoneOffset

class WeatherRepositoryTest {

    @Test
    fun temperatureRangeUsesOnlyRequestedLocalDay() {
        val zone = ZoneId.of("Asia/Shanghai")
        // base = 2026-11-10T00:00Z = 本地 11-10 08:00
        val base = LocalDateTime.of(2026, 11, 10, 0, 0).toEpochSecond(ZoneOffset.UTC)
        val points = listOf(
            WeatherRepository.HourPoint(base - 9 * 3600, 8, 3), // 本地 11-09 23:00，不属于当天
            WeatherRepository.HourPoint(base, 11, 3), // 本地 11-10 08:00
            WeatherRepository.HourPoint(base + 3600, 16, 0), // 本地 11-10 09:00
            WeatherRepository.HourPoint(base + 86400, 5, 0), // 本地 11-11 08:00，不属于当天
        )
        val range = WeatherRepository.temperatureRange(points, LocalDate.of(2026, 11, 10), zone)
        assertEquals(16 to 11, range)
    }

    @Test
    fun temperatureRangeIsNullWithoutCoverage() {
        val zone = ZoneId.of("Asia/Shanghai")
        val base = LocalDateTime.of(2026, 11, 10, 0, 0).toEpochSecond(ZoneOffset.UTC)
        val points = listOf(WeatherRepository.HourPoint(base + 86400, 5, 0))
        assertNull(WeatherRepository.temperatureRange(points, LocalDate.of(2026, 11, 10), zone))
        assertNull(WeatherRepository.temperatureRange(emptyList(), LocalDate.of(2026, 11, 10), zone))
    }

    @Test
    fun parsesOpenMeteoResponse() {
        val json = """
            {"latitude":31.3181,"longitude":121.430275,"timezone":"Asia/Shanghai",
             "current":{"time":"2026-11-10T18:45","interval":900,
             "temperature_2m":9.3,"weather_code":2}}
        """.trimIndent()
        val snapshot = WeatherRepository.parse(json)
        assertEquals(9, snapshot?.temperatureC)
        assertEquals(2, snapshot?.code)
    }

    @Test
    fun roundsTemperature() {
        val json = """{"current":{"temperature_2m":-3.6,"weather_code":71}}"""
        assertEquals(-4, WeatherRepository.parse(json)?.temperatureC)
    }

    @Test
    fun ignoresMalformedOrEmptyPayloads() {
        assertNull(WeatherRepository.parse("not json"))
        assertNull(WeatherRepository.parse("""{"current":{}}"""))
        assertNull(WeatherRepository.parse("""{"latitude":1}"""))
    }

    @Test
    fun mapsWmoCodesToConditions() {
        assertEquals(WeatherRepository.Condition.CLEAR, WeatherRepository.conditionOf(0))
        assertEquals(WeatherRepository.Condition.PARTLY_CLOUDY, WeatherRepository.conditionOf(2))
        assertEquals(WeatherRepository.Condition.OVERCAST, WeatherRepository.conditionOf(3))
        assertEquals(WeatherRepository.Condition.FOG, WeatherRepository.conditionOf(45))
        assertEquals(WeatherRepository.Condition.DRIZZLE, WeatherRepository.conditionOf(53))
        assertEquals(WeatherRepository.Condition.RAIN, WeatherRepository.conditionOf(63))
        assertEquals(WeatherRepository.Condition.HEAVY_RAIN, WeatherRepository.conditionOf(65))
        assertEquals(WeatherRepository.Condition.SHOWERS, WeatherRepository.conditionOf(80))
        assertEquals(WeatherRepository.Condition.SHOWERS, WeatherRepository.conditionOf(81))
        assertEquals(WeatherRepository.Condition.HEAVY_RAIN, WeatherRepository.conditionOf(82))
        assertEquals(WeatherRepository.Condition.SNOW, WeatherRepository.conditionOf(71))
        assertEquals(WeatherRepository.Condition.HEAVY_SNOW, WeatherRepository.conditionOf(75))
        assertEquals(WeatherRepository.Condition.THUNDER, WeatherRepository.conditionOf(95))
        assertEquals(WeatherRepository.Condition.OVERCAST, WeatherRepository.conditionOf(1234))
    }

    @Test
    fun refreshesAfterThirtyMinutesOrFiveKilometres() {
        val fresh = 60_000L
        assertFalse(WeatherRepository.shouldRefresh(ageMillis = fresh, movedKm = 0.0))
        assertFalse(WeatherRepository.shouldRefresh(ageMillis = fresh, movedKm = 5.0))
        assertTrue(WeatherRepository.shouldRefresh(ageMillis = fresh, movedKm = 5.1))
        assertTrue(WeatherRepository.shouldRefresh(ageMillis = 31L * 60 * 1000, movedKm = 0.0))
        assertTrue(WeatherRepository.shouldRefresh(ageMillis = -1L, movedKm = 0.0))
    }

    /** 取数失败后按 5 分钟节流重试：刚失败过就先等一等，别每次回到前台都打一次网络。 */
    @Test
    fun retriesFailedFetchAfterFiveMinutes() {
        val stale = 40L * 60 * 1000
        assertFalse(
            WeatherRepository.shouldRefresh(stale, movedKm = 0.0, sinceAttemptMillis = 2L * 60 * 1000),
        )
        assertTrue(
            WeatherRepository.shouldRefresh(stale, movedKm = 0.0, sinceAttemptMillis = 6L * 60 * 1000),
        )
        // 从没尝试过（sinceAttempt 极大）→ 立刻取
        assertTrue(
            WeatherRepository.shouldRefresh(stale, movedKm = 0.0, sinceAttemptMillis = Long.MAX_VALUE),
        )
        // 没过期就永远不取，哪怕刚失败过
        assertFalse(
            WeatherRepository.shouldRefresh(60_000L, movedKm = 0.0, sinceAttemptMillis = 60_000L),
        )
    }

    @Test
    fun parsesHourlySeries() {
        val json = """
            {"hourly":{"time":["2026-11-10T00:00","2026-11-10T01:00"],
             "temperature_2m":[8.2,7.6],"weather_code":[1,2]}}
        """.trimIndent()
        val points = WeatherRepository.parseHourly(json)
        assertEquals(2, points.size)
        assertEquals(8, points[0].temperatureC)
        assertEquals(1_794_268_800L, points[0].epochSeconds)
        assertEquals(2, points[1].code)
    }

    @Test
    fun ignoresBrokenHourlyPayloads() {
        assertTrue(WeatherRepository.parseHourly("not json").isEmpty())
        assertTrue(WeatherRepository.parseHourly("""{"current":{}}""").isEmpty())
    }

    @Test
    fun hourlyCacheRoundTrips() {
        val points = listOf(
            WeatherRepository.HourPoint(1_762_732_800L, -3, 71),
            WeatherRepository.HourPoint(1_762_740_000L, 12, 0),
        )
        assertEquals(points, WeatherRepository.decodeHourly(WeatherRepository.encodeHourly(points)))
        assertTrue(WeatherRepository.decodeHourly("garbage").isEmpty())
    }

    @Test
    fun slotsStartAtCurrentHour() {
        // 2026-11-10 18:55 +08:00 → 本地对齐到 18:00，之后每小时一格
        val slots = WeatherRepository.slots(
            nowEpochSeconds = 1_794_308_100L,
            zoneOffsetSeconds = 8 * 3600,
            count = 6,
            stepHours = 1,
        )
        assertEquals(6, slots.size)
        assertEquals(1_794_304_800L, slots[0])
        assertEquals(3600L, slots[1] - slots[0])
        assertEquals(5 * 3600L, slots[5] - slots[0])
    }

    // ---------------------------------------------------------------- 逐时行：步长跟数据源走

    /** 2026-11-16 的某一 UTC 时刻（测试里都用它算偏移，避免手写魔数出错）。 */
    private fun utc(hour: Int, minute: Int = 0, day: Int = 16, month: Int = 11): Long =
        LocalDateTime.of(2026, month, day, hour, minute).toEpochSecond(ZoneOffset.UTC)

    private fun hourlyPoints(fromEpoch: Long, count: Int, stepHours: Int): List<WeatherRepository.HourPoint> =
        (0 until count).map {
            WeatherRepository.HourPoint(fromEpoch + it * stepHours * 3600L, 10 + it, 1)
        }

    /**
     * 主源（1 小时）：现在/22时/23时/0时/1时/2时。
     *
     * 本地（+08:00）21:55 → 首格是 21:00 那条读数（标「现在」），之后每小时一格。
     */
    @Test
    fun oneHourlySourceStepsOneHourPerSlot() {
        val now = utc(hour = 13, minute = 55) // 本地 21:55
        val points = hourlyPoints(fromEpoch = utc(hour = 12), count = 12, stepHours = 1) // 本地 20:00 起
        val slots = WeatherRepository.visibleSlots(
            points = points,
            nowEpochSeconds = now,
            zoneOffsetSeconds = 8 * 3600,
            count = 6,
            stepHours = 1,
        )
        assertEquals(6, slots.size)
        assertEquals(listOf(21, 22, 23, 0, 1, 2), slots.map { localHour(it.epochSeconds) })
        // 首格恒为「现在」，其余都不是
        assertEquals(listOf(true, false, false, false, false, false), slots.map { it.isNow })
        // 相邻格子正好 1 小时
        assertEquals(3600L, slots[1].epochSeconds - slots[0].epochSeconds)
    }

    /**
     * 备用源（3 小时）：现在/23时/2时/5时/8时/11时。
     *
     * 7Timer 的点落在 UTC 0/3/6/…/21 的网格上，换成 +08:00 就是本地的 2/5/8/…/23 点；
     * 本地 21:55 的「现在」是 20 点那一条读数（最近一个不晚于当前时刻的采样点）。
     */
    @Test
    fun threeHourlySourceStepsThreeHoursPerSlot() {
        val now = utc(hour = 13, minute = 55) // 本地 21:55
        val points = hourlyPoints(fromEpoch = utc(hour = 12), count = 8, stepHours = 3) // 本地 20:00 起
        val slots = WeatherRepository.visibleSlots(
            points = points,
            nowEpochSeconds = now,
            zoneOffsetSeconds = 8 * 3600,
            count = 6,
            stepHours = 3,
        )
        assertEquals(listOf(20, 23, 2, 5, 8, 11), slots.map { localHour(it.epochSeconds) })
        assertEquals(listOf(true, false, false, false, false, false), slots.map { it.isNow })
        assertEquals(3 * 3600L, slots[1].epochSeconds - slots[0].epochSeconds)
    }

    /**
     * 真实 7Timer! 返回（2026-11-16 抓取，上海坐标）走一遍完整链路：
     * `init=2026111606` + `timepoint=3,6,…` → 6 个槽位 → 现在/23时/2时/5时/8时/11时。
     */
    @Test
    fun realSevenTimerPayloadProducesTheExpectedSixSlots() {
        val json = """
            {"product":"civil","init":"2026111606","dataseries":[
              {"timepoint":3,"temp2m":16,"weather":"cloudynight"},
              {"timepoint":6,"temp2m":15,"weather":"cloudynight"},
              {"timepoint":9,"temp2m":14,"weather":"cloudynight"},
              {"timepoint":12,"temp2m":14,"weather":"cloudynight"},
              {"timepoint":15,"temp2m":13,"weather":"cloudynight"},
              {"timepoint":18,"temp2m":13,"weather":"cloudyday"},
              {"timepoint":21,"temp2m":15,"weather":"cloudyday"}
            ]}
        """.trimIndent()
        val points = WeatherRepository.parseSevenTimer(json)
        assertEquals(7, points.size)
        // init 06:00Z + timepoint 小时数
        assertEquals(utc(hour = 9), points[0].epochSeconds)
        assertEquals(utc(hour = 12), points[1].epochSeconds)

        // 本地 21:26（UTC 13:26）：最近一个不晚于现在的采样点是 UTC 12:00（本地 20:00）
        val now = utc(hour = 13, minute = 26)
        val slots = WeatherRepository.visibleSlots(
            points = points,
            nowEpochSeconds = now,
            zoneOffsetSeconds = 8 * 3600,
            count = 6,
            stepHours = WeatherRepository.Source.SEVEN_TIMER.stepHours,
        )
        assertEquals(listOf(20, 23, 2, 5, 8, 11), slots.map { localHour(it.epochSeconds) })
        assertEquals(listOf(true, false, false, false, false, false), slots.map { it.isNow })

        // 「现在」那一格取的是 15°，不是第一个点（09:00Z 的 16°）：两者差 3 小时就是 3 小时源的代价。
        val snapshot = WeatherRepository.snapshotAt(points, now)
        assertEquals(15, snapshot?.temperatureC)
        // 采样点上的天气码（cloudynight / cloudyday 都映射到「阴」）
        val byEpoch = points.associateBy { it.epochSeconds }
        assertEquals(
            List(6) { 3 },
            slots.map { byEpoch[it.epochSeconds]?.code },
        )
    }

    /** 桌面卡片的第二排逐时行：按「格数」跳过前 6 格，不能按小时数硬挪（3 小时源的 6 格是 18 小时）。 */
    @Test
    fun secondHourRowSkipsBySlotsNotByHours() {        val now = utc(hour = 13, minute = 55)
        val points = hourlyPoints(fromEpoch = utc(hour = 12), count = 14, stepHours = 3)
        val second = WeatherRepository.visibleSlots(
            points = points,
            nowEpochSeconds = now,
            zoneOffsetSeconds = 8 * 3600,
            count = 6,
            stepHours = 3,
            skip = 6,
        )
        // 首格本地 20:00 + 6 × 3 小时 = 18 小时后 → 本地 14:00
        assertEquals(listOf(14, 17, 20, 23, 2, 5), second.map { localHour(it.epochSeconds) })
        // 第二排永远没有「现在」那一格
        assertTrue(second.none { it.isNow })
    }

    /** 一个采样点都没有时也要排满 6 格（内容由界面填占位符），且按数据源的网格对齐。 */
    @Test
    fun slotsFallBackToTheoreticalGridWithoutData() {
        val now = utc(hour = 13, minute = 55) // 本地 21:55
        val slots = WeatherRepository.visibleSlots(
            points = emptyList(),
            nowEpochSeconds = now,
            zoneOffsetSeconds = 8 * 3600,
            count = 6,
            stepHours = 3,
        )
        assertEquals(6, slots.size)
        // 3 小时源按 UTC 0/3/6/…/21 对齐：UTC 12:00 → 本地 20:00，与 7Timer 的采样网格一致
        assertEquals(listOf(20, 23, 2, 5, 8, 11), slots.map { localHour(it.epochSeconds) })
        assertTrue(slots.first().isNow)
        // 1 小时源仍按本地整点对齐
        val hourly = WeatherRepository.visibleSlots(
            points = emptyList(),
            nowEpochSeconds = now,
            zoneOffsetSeconds = 8 * 3600,
            count = 6,
            stepHours = 1,
        )
        assertEquals(listOf(21, 22, 23, 0, 1, 2), hourly.map { localHour(it.epochSeconds) })
        assertTrue(hourly.first().isNow)
    }

    /** 所有采样点都在未来时，「现在」退回第一个点（宁可显示最近的预报，也不要空格）。 */
    @Test
    fun slotsUseFirstPointWhenAllAreInTheFuture() {
        val now = utc(hour = 0)
        val points = listOf(
            WeatherRepository.HourPoint(utc(hour = 3), 5, 1),
            WeatherRepository.HourPoint(utc(hour = 6), 6, 1),
        )
        val slots = WeatherRepository.visibleSlots(
            points = points,
            nowEpochSeconds = now,
            zoneOffsetSeconds = 0,
            count = 3,
            stepHours = 3,
        )
        assertEquals(utc(hour = 3), slots[0].epochSeconds)
        assertEquals(utc(hour = 9), slots[2].epochSeconds)
    }

    private fun localHour(epochSeconds: Long): Int =
        java.time.Instant.ofEpochSecond(epochSeconds).atOffset(java.time.ZoneOffset.ofHours(8)).hour

    // ---------------------------------------------------------------- 7Timer! 备用源

    @Test
    fun alignsEpochsToTheThreeHourUtcGrid() {
        // UTC 04:00 对齐到 03:00；已经对齐的不动
        assertEquals(utc(hour = 3), WeatherRepository.alignToStep(utc(hour = 4), 3))
        assertEquals(utc(hour = 3), WeatherRepository.alignToStep(utc(hour = 3), 3))
        assertEquals(utc(hour = 21), WeatherRepository.alignToStep(utc(hour = 23, minute = 59), 3))
        // 1 小时粒度只对齐到整点
        assertEquals(utc(hour = 4), WeatherRepository.alignToStep(utc(hour = 4, minute = 59), 1))
    }

    /**
     * 官方 `api.pl` 只给 `init`（起报时刻）+ `timepoint`（相对小时数），**没有** `time` 字段；
     * 旧文档里的 `time` 字段两种都认 —— 这里两个都覆盖。
     */
    @Test
    fun parsesSevenTimerTimepointSeries() {
        val json = """
            {"product":"civil","init":"2026111606","dataseries":[
              {"timepoint":3,"temp2m":16,"weather":"cloudynight"},
              {"timepoint":6,"temp2m":15,"weather":"clearday"}
            ]}
        """.trimIndent()
        val points = WeatherRepository.parseSevenTimer(json)
        assertEquals(2, points.size)
        // init 06:00Z + 3h / 6h
        assertEquals(utc(hour = 9), points[0].epochSeconds)
        assertEquals(utc(hour = 12), points[1].epochSeconds)
        assertEquals(16, points[0].temperatureC)
        // cloudynight → 阴（WMO 3）；clearday → 晴（WMO 0）
        assertEquals(3, points[0].code)
        assertEquals(0, points[1].code)
    }

    @Test
    fun parsesSevenTimerAbsoluteTimeFieldAndRealignsIt() {
        // 04:00 不在 3 小时网格上 → 向下对齐到 03:00
        val json = """
            {"dataseries":[{"time":"2025111604","temp2m":9,"weather":"rain"}]}
        """.trimIndent()
        val points = WeatherRepository.parseSevenTimer(json)
        assertEquals(1, points.size)
        assertEquals(
            LocalDateTime.of(2025, 11, 16, 3, 0).toEpochSecond(ZoneOffset.UTC),
            points[0].epochSeconds,
        )
        assertEquals(63, points[0].code) // rain → 中雨
    }

    @Test
    fun sevenTimerSeriesIsSortedAndSkipsBrokenItems() {
        val json = """
            {"init":"2026111606","dataseries":[
              {"timepoint":6,"temp2m":15,"weather":"clearday"},
              {"weather":"rain"},
              {"timepoint":3,"temp2m":16,"weather":"cloudyday"}
            ]}
        """.trimIndent()
        val points = WeatherRepository.parseSevenTimer(json)
        assertEquals(2, points.size) // 缺 temp2m 的那条被跳过
        assertEquals(utc(hour = 9), points[0].epochSeconds)
        assertEquals(utc(hour = 12), points[1].epochSeconds)
    }

    @Test
    fun ignoresBrokenSevenTimerPayloads() {
        assertTrue(WeatherRepository.parseSevenTimer("not json").isEmpty())
        assertTrue(WeatherRepository.parseSevenTimer("""{"product":"civil"}""").isEmpty())
        assertTrue(WeatherRepository.parseSevenTimer("""{"dataseries":[]}""").isEmpty())
        // 没有 init 也没有 time：算不出时刻，整条丢掉
        assertTrue(WeatherRepository.parseSevenTimer("""{"dataseries":[{"timepoint":3,"temp2m":1}]}""").isEmpty())
    }

    @Test
    fun mapsSevenTimerWeatherWordsToWmoCodes() {
        // 昼夜后缀不影响分类
        assertEquals(0, WeatherRepository.wmoCodeOfSevenTimer("clearday"))
        assertEquals(0, WeatherRepository.wmoCodeOfSevenTimer("clearnight"))
        assertEquals(2, WeatherRepository.wmoCodeOfSevenTimer("pcloudyday"))
        assertEquals(3, WeatherRepository.wmoCodeOfSevenTimer("mcloudynight"))
        assertEquals(3, WeatherRepository.wmoCodeOfSevenTimer("cloudyday"))
        assertEquals(45, WeatherRepository.wmoCodeOfSevenTimer("humidday"))
        assertEquals(45, WeatherRepository.wmoCodeOfSevenTimer("fog"))
        assertEquals(80, WeatherRepository.wmoCodeOfSevenTimer("lightrainday"))
        assertEquals(80, WeatherRepository.wmoCodeOfSevenTimer("ishowernight"))
        assertEquals(63, WeatherRepository.wmoCodeOfSevenTimer("rain"))
        assertEquals(65, WeatherRepository.wmoCodeOfSevenTimer("heavyrain"))
        assertEquals(71, WeatherRepository.wmoCodeOfSevenTimer("lightsnowday"))
        assertEquals(73, WeatherRepository.wmoCodeOfSevenTimer("snownight"))
        assertEquals(95, WeatherRepository.wmoCodeOfSevenTimer("tsday"))
        // 表外的值、空值、大小写混乱 → 多云（WMO 2）
        assertEquals(2, WeatherRepository.wmoCodeOfSevenTimer("sandstorm"))
        assertEquals(2, WeatherRepository.wmoCodeOfSevenTimer(""))
        assertEquals(2, WeatherRepository.wmoCodeOfSevenTimer(null))
        assertEquals(2, WeatherRepository.wmoCodeOfSevenTimer("PCLOUDYDAY"))
        // 映射出来的码要能被现有的 WMO 分类器认识
        assertEquals(
            WeatherRepository.Condition.PARTLY_CLOUDY,
            WeatherRepository.conditionOf(WeatherRepository.wmoCodeOfSevenTimer("sandstorm")),
        )
        assertEquals(
            WeatherRepository.Condition.CLEAR,
            WeatherRepository.conditionOf(WeatherRepository.wmoCodeOfSevenTimer("clearday")),
        )
    }

    /** 7Timer 没有 `current` 块：实时读数取「不晚于当前时刻的最后一个点」。 */
    @Test
    fun snapshotComesFromTheLatestPointNotInTheFuture() {
        val points = listOf(
            WeatherRepository.HourPoint(utc(hour = 3), 7, 3),
            WeatherRepository.HourPoint(utc(hour = 6), 12, 1),
            WeatherRepository.HourPoint(utc(hour = 9), 15, 0),
        )
        assertEquals(12, WeatherRepository.snapshotAt(points, utc(hour = 7))?.temperatureC)
        // 全部在未来 → 第一个点
        assertEquals(7, WeatherRepository.snapshotAt(points, utc(hour = 0))?.temperatureC)
        assertNull(WeatherRepository.snapshotAt(emptyList(), utc(hour = 0)))
    }

    @Test
    fun rejectsPrimaryPayloadsWithoutHourlyData() {
        // 只有 current、没有 hourly：当主源失败处理（否则会拿到「有气温没逐时」的半残数据）
        assertNull(WeatherRepository.parsePrimary("""{"current":{"temperature_2m":9,"weather_code":2}}"""))
        assertNull(WeatherRepository.parsePrimary("not json"))
        val full = """
            {"current":{"temperature_2m":9,"weather_code":2},
             "hourly":{"time":["2026-11-10T00:00"],"temperature_2m":[8.2],"weather_code":[1]}}
        """.trimIndent()
        val parsed = WeatherRepository.parsePrimary(full)
        assertEquals(9, parsed?.first?.temperatureC)
        assertEquals(1, parsed?.second?.size)
    }

    // ---------------------------------------------------------------- 降级 / 旧数据保留

    @Test
    fun keepsFreshCacheWhenThePrimarySourceFails() {
        // 缓存还没过期：什么都不做，界面继续用缓存（不清空）
        assertEquals(
            WeatherRepository.Fallback.KEEP_CACHE,
            WeatherRepository.fallbackFor(hasCache = true, cacheAgeMillis = 5L * 60 * 1000),
        )
        assertEquals(
            WeatherRepository.Fallback.KEEP_CACHE,
            WeatherRepository.fallbackFor(hasCache = true, cacheAgeMillis = 30L * 60 * 1000),
        )
        // 过期了才去问备用源
        assertEquals(
            WeatherRepository.Fallback.TRY_SEVEN_TIMER,
            WeatherRepository.fallbackFor(hasCache = true, cacheAgeMillis = 31L * 60 * 1000),
        )
        // 根本没有缓存 → 直接问备用源
        assertEquals(
            WeatherRepository.Fallback.TRY_SEVEN_TIMER,
            WeatherRepository.fallbackFor(hasCache = false, cacheAgeMillis = 0L),
        )
    }

    @Test
    fun oldDataStaysVisibleForADayAndIsLabelledAsStale() {
        assertTrue(WeatherRepository.isDisplayable(0L))
        assertTrue(WeatherRepository.isDisplayable(23L * 60 * 60 * 1000))
        // 超过一天的旧数据才当「没有」
        assertFalse(WeatherRepository.isDisplayable(24L * 60 * 60 * 1000 + 1))
        // 诊断里的过期说明
        assertEquals("数据过期 0 分钟", WeatherRepository.staleLabel(30_000L))
        assertEquals("数据过期 45 分钟", WeatherRepository.staleLabel(45L * 60 * 1000))
        assertEquals("数据过期 1500 分钟", WeatherRepository.staleLabel(25L * 60 * 60 * 1000))
        assertNull(WeatherRepository.staleLabel(null))
        assertNull(WeatherRepository.staleLabel(-1L))
    }

    @Test
    fun sourceIdsRoundTripThroughTheCache() {
        assertEquals(WeatherRepository.Source.OPEN_METEO, WeatherRepository.Source.of("open-meteo"))
        assertEquals(WeatherRepository.Source.SEVEN_TIMER, WeatherRepository.Source.of("7timer"))
        // 旧缓存（没有 source 字段）或坏值 → 主源，步长 1
        assertEquals(WeatherRepository.Source.OPEN_METEO, WeatherRepository.Source.of(null))
        assertEquals(WeatherRepository.Source.OPEN_METEO, WeatherRepository.Source.of(""))
        assertEquals(WeatherRepository.Source.OPEN_METEO, WeatherRepository.Source.of("noaa"))
        assertEquals(1, WeatherRepository.Source.OPEN_METEO.stepHours)
        assertEquals(3, WeatherRepository.Source.SEVEN_TIMER.stepHours)
    }

    // ---------------------------------------------------------------- 刷新触发：低精度（3 小时）升级

    /** 低精度数据的升级轮询间隔：60 秒（原来是 10 分钟）。 */
    private val pollInterval = 60L * 1000

    /** 低精度数据**没到 30 分钟**也要刷新：目的就是尽快升级回主源的 1 小时粒度。 */
    @Test
    fun lowPrecisionDataTriggersRefreshBeforeItExpires() {
        val fresh = 2L * 60 * 1000
        // 主源（1 小时粒度）新鲜 → 不刷新
        assertFalse(WeatherRepository.shouldRefresh(fresh, movedKm = 0.0, sinceAttemptMillis = pollInterval))
        // 同一份新鲜数据，但来源是 7Timer!（3 小时粒度）→ 刷新
        assertTrue(
            WeatherRepository.shouldRefresh(
                ageMillis = fresh,
                movedKm = 0.0,
                sinceAttemptMillis = pollInterval,
                lowPrecision = true,
            ),
        )
    }

    /** 「低精度触发」按 **60 秒**节流：59 秒还不行，满 60 秒就再打一次主源。 */
    @Test
    fun lowPrecisionRefreshIsThrottledToSixtySeconds() {
        val fresh = 2L * 60 * 1000
        fun lowPrecision(sinceAttempt: Long) = WeatherRepository.shouldRefresh(
            ageMillis = fresh,
            movedKm = 0.0,
            sinceAttemptMillis = sinceAttempt,
            lowPrecision = true,
        )
        // 距上次尝试 1 秒 / 30 秒 / 59 秒 → 不刷新
        assertFalse(lowPrecision(1L * 1000))
        assertFalse(lowPrecision(30L * 1000))
        assertFalse(lowPrecision(pollInterval - 1_000))
        // 满 60 秒 → 允许再来一次
        assertTrue(lowPrecision(pollInterval))
        assertTrue(lowPrecision(pollInterval + 1_000))
        // 从没尝试过（KEY_ATTEMPT 为 0）→ 立刻升级
        assertTrue(lowPrecision(Long.MAX_VALUE))
    }

    /** 一旦升级成功（来源变回 OPEN_METEO / 步长 1），就不再按 60 秒轮询，回到 30 分钟过期逻辑。 */
    @Test
    fun upgradedDataNoLongerTriggersEarlyRefresh() {
        val fresh = 2L * 60 * 1000
        // 刚切回主源 61 秒：低精度规则已失效，数据还没过期 → 不刷新
        assertFalse(
            WeatherRepository.shouldRefresh(
                ageMillis = fresh,
                movedKm = 0.0,
                sinceAttemptMillis = pollInterval + 1_000,
                lowPrecision = false,
            ),
        )
        // 一直到 30 分钟过期才会再取
        assertFalse(WeatherRepository.shouldRefresh(30L * 60 * 1000, movedKm = 0.0, lowPrecision = false))
        assertTrue(WeatherRepository.shouldRefresh(31L * 60 * 1000, movedKm = 0.0, lowPrecision = false))
        assertFalse(WeatherRepository.isLowPrecision(WeatherRepository.Source.OPEN_METEO, stepHours = 1))
        assertTrue(WeatherRepository.isLowPrecision(WeatherRepository.Source.SEVEN_TIMER, stepHours = 3))
        // 来源字段是旧的/坏的、但步长写着 3，也按低精度算（宁可多试一次主源）
        assertTrue(WeatherRepository.isLowPrecision(WeatherRepository.Source.OPEN_METEO, stepHours = 3))
    }

    /** 「过期」与「低精度」是两条互不干扰的规则：各自的节流窗口独立生效。 */
    @Test
    fun expiryAndLowPrecisionRulesAreIndependent() {
        val expired = 45L * 60 * 1000
        val fresh = 2L * 60 * 1000
        // 过期 + 主源：仍按 5 分钟失败节流（老规则不变）
        assertTrue(
            WeatherRepository.shouldRefresh(expired, 0.0, sinceAttemptMillis = 6L * 60 * 1000),
        )
        assertFalse(
            WeatherRepository.shouldRefresh(expired, 0.0, sinceAttemptMillis = 2L * 60 * 1000),
        )
        // 过期 + 低精度：60 秒轮询在 2 分钟时就已放行 → 刷新（以前 10 分钟节流会挡住）
        assertTrue(
            WeatherRepository.shouldRefresh(
                expired, 0.0, sinceAttemptMillis = 2L * 60 * 1000, lowPrecision = true,
            ),
        )
        // 过期 + 低精度 + 刚试过 30 秒：两条都被节流 → 不刷新
        assertFalse(
            WeatherRepository.shouldRefresh(
                expired, 0.0, sinceAttemptMillis = 30_000, lowPrecision = true,
            ),
        )
        // 过期 + 低精度 + 90 秒 → 60 秒轮询放行
        assertTrue(
            WeatherRepository.shouldRefresh(
                expired, 0.0, sinceAttemptMillis = 90_000, lowPrecision = true,
            ),
        )
        // 新鲜 + 主源 + 11 分钟：两条都不成立 → 不刷新（不会白打网络）
        assertFalse(WeatherRepository.shouldRefresh(fresh, 0.0, sinceAttemptMillis = 11L * 60 * 1000))
        // 回到前台 / 换地点：允许立即升级一次，不受 60 秒限制
        assertTrue(
            WeatherRepository.shouldRefresh(
                fresh,
                movedKm = 0.0,
                sinceAttemptMillis = 1L * 1000,
                lowPrecision = true,
                ignoreLowPrecisionThrottle = true,
            ),
        )
        // 但「立即升级」不会把新鲜的主源数据也一并重取
        assertFalse(
            WeatherRepository.shouldRefresh(
                fresh,
                movedKm = 0.0,
                sinceAttemptMillis = 1L * 1000,
                lowPrecision = false,
                ignoreLowPrecisionThrottle = true,
            ),
        )
        // 换地点永远立即刷新（A 城市的天气绝不能挂在 B 城市下）
        assertTrue(
            WeatherRepository.shouldRefresh(
                fresh, movedKm = 5.1, sinceAttemptMillis = 1_000, lowPrecision = false,
            ),
        )
    }

    // ---------------------------------------------------------------- 取数时序：一次失败即降级

    /** 主源失败**一次**就立刻试备用源：没有「2 秒后重试一次」，主源只被调用一次。 */
    @Test
    fun primaryFailureFallsBackImmediatelyWithoutRetry() {
        val calls = mutableListOf<String>()
        val result = WeatherRepository.fetchWeather(
            fetchPrimary = {
                calls += "primary"
                null
            },
            keepCache = { false },
            fetchFallback = {
                calls += "fallback"
                "7timer-payload"
            },
        )
        assertEquals("主源只该试一次，然后立刻落到备用源", listOf("primary", "fallback"), calls)
        assertEquals(
            listOf(WeatherRepository.Source.OPEN_METEO, WeatherRepository.Source.SEVEN_TIMER),
            result.attempts,
        )
        assertEquals(WeatherRepository.Source.SEVEN_TIMER, result.source)
        assertEquals("7timer-payload", result.payload)
        assertFalse(result.keptCache)
    }

    /** 缓存还新鲜时，主源失败不会去打备用源（界面继续用旧数据，省一次请求）。 */
    @Test
    fun freshCacheSkipsTheFallbackRequest() {
        val calls = mutableListOf<String>()
        val result = WeatherRepository.fetchWeather(
            fetchPrimary = {
                calls += "primary"
                null
            },
            keepCache = { true },
            fetchFallback = {
                calls += "fallback"
                "should-not-happen"
            },
        )
        assertEquals(listOf("primary"), calls)
        assertEquals(listOf(WeatherRepository.Source.OPEN_METEO), result.attempts)
        assertNull(result.source)
        assertTrue(result.keptCache)
    }

    /** 主源成功时绝不碰缓存判断与备用源。 */
    @Test
    fun primarySuccessNeverTouchesTheFallback() {
        val calls = mutableListOf<String>()
        val result = WeatherRepository.fetchWeather(
            fetchPrimary = {
                calls += "primary"
                "primary-payload"
            },
            keepCache = { error("主源成功时不该问缓存") },
            fetchFallback = { error("主源成功时不该降级") },
        )
        assertEquals(listOf("primary"), calls)
        assertEquals(WeatherRepository.Source.OPEN_METEO, result.source)
        assertEquals("primary-payload", result.payload)
        assertEquals(listOf(WeatherRepository.Source.OPEN_METEO), result.attempts)
    }

    /** 主源单次请求的超时必须短到 5 秒：失败要快，才能「一次失败就降级」。 */
    @Test
    fun primaryTimeoutIsFiveSeconds() {
        assertEquals(5_000, WeatherRepository.PRIMARY_TIMEOUT_MILLIS)
    }

    /** 诊断里的「下次重试」倒计时：三条规则与 shouldRefresh 同源。 */
    @Test
    fun nextRetryLabelDescribesTheCountdown() {
        // 低精度 + 前台第 1 次失败（60 秒退避）：距上次尝试 42 秒 → 还有 18 秒
        assertEquals(
            "约 18 秒后（前台低精度退避 60 秒）",
            WeatherRepository.nextRetryLabel(
                ageMillis = 2L * 60 * 1000,
                sinceAttemptMillis = 42_000,
                lowPrecision = true,
                lowPrecisionFailures = 1,
                isForeground = true,
            ),
        )
        // 低精度退避已到点
        assertEquals(
            "现在（已到点，前台低精度退避 60 秒）",
            WeatherRepository.nextRetryLabel(
                ageMillis = 2L * 60 * 1000,
                sinceAttemptMillis = pollInterval,
                lowPrecision = true,
                lowPrecisionFailures = 1,
                isForeground = true,
            ),
        )
        // 后台：10 分钟节奏
        assertEquals(
            "约 5 分钟后（后台低精度 10 分钟）",
            WeatherRepository.nextRetryLabel(
                ageMillis = 2L * 60 * 1000,
                sinceAttemptMillis = 5L * 60 * 1000,
                lowPrecision = true,
                lowPrecisionFailures = 1,
                isForeground = false,
            ),
        )
        // 主源新鲜：等数据自然到期
        assertEquals(
            "约 27 分钟后（主源数据到期才重取）",
            WeatherRepository.nextRetryLabel(
                ageMillis = 3L * 60 * 1000,
                sinceAttemptMillis = 5L * 60 * 1000,
                lowPrecision = false,
            ),
        )
        // 已过期：按 5 分钟失败节流
        assertEquals(
            "约 1 分 30 秒后（失败后 5 分钟节流）",
            WeatherRepository.nextRetryLabel(
                ageMillis = 45L * 60 * 1000,
                sinceAttemptMillis = 3L * 60 * 1000 + 30_000,
                lowPrecision = false,
            ),
        )
    }

    /** 低精度重试的退避表：前台 60 / 120 / 300 秒（封顶），后台一律 10 分钟。 */
    @Test
    fun lowPrecisionRetryBacksOffAndSlowsDownInBackground() {
        // 前台：1 → 60，2 → 120，3 → 300，之后封顶 300
        assertEquals(60_000L, WeatherRepository.nextLowPrecisionRetryDelayMillis(1, true))
        assertEquals(120_000L, WeatherRepository.nextLowPrecisionRetryDelayMillis(2, true))
        assertEquals(300_000L, WeatherRepository.nextLowPrecisionRetryDelayMillis(3, true))
        assertEquals(300_000L, WeatherRepository.nextLowPrecisionRetryDelayMillis(4, true))
        assertEquals(300_000L, WeatherRepository.nextLowPrecisionRetryDelayMillis(99, true))
        // 刚降级、还没失败过（0）按第 1 档算
        assertEquals(60_000L, WeatherRepository.nextLowPrecisionRetryDelayMillis(0, true))
        // 后台：任意次数都是 10 分钟
        for (failures in 0..6) {
            assertEquals(
                "后台第 $failures 次",
                600_000L,
                WeatherRepository.nextLowPrecisionRetryDelayMillis(failures, false),
            )
        }
        // 常量本身
        assertEquals(60_000L, WeatherRepository.LOW_PRECISION_FIRST_RETRY_MILLIS)
        assertEquals(120_000L, WeatherRepository.LOW_PRECISION_SECOND_RETRY_MILLIS)
        assertEquals(300_000L, WeatherRepository.LOW_PRECISION_MAX_RETRY_MILLIS)
        assertEquals(600_000L, WeatherRepository.LOW_PRECISION_BACKGROUND_RETRY_MILLIS)
    }

    /** 退避表要真的作用在 shouldRefresh 上：前台按阶梯、后台 10 分钟、回前台立即放行。 */
    @Test
    fun shouldRefreshHonoursTheBackoffTable() {
        val fresh = 2L * 60 * 1000
        fun refresh(
            sinceAttempt: Long,
            failures: Int,
            foreground: Boolean = true,
            immediate: Boolean = false,
        ) = WeatherRepository.shouldRefresh(
            ageMillis = fresh,
            movedKm = 0.0,
            sinceAttemptMillis = sinceAttempt,
            lowPrecision = true,
            ignoreLowPrecisionThrottle = immediate,
            lowPrecisionFailures = failures,
            isForeground = foreground,
        )

        // 第 1 次失败：59 秒不动，60 秒放行
        assertFalse(refresh(59_000, failures = 1))
        assertTrue(refresh(60_000, failures = 1))
        // 第 2 次失败：60 秒还不够，120 秒才放行
        assertFalse(refresh(60_000, failures = 2))
        assertTrue(refresh(120_000, failures = 2))
        // 第 3 次失败：要 300 秒
        assertFalse(refresh(120_000, failures = 3))
        assertTrue(refresh(300_000, failures = 3))
        // 后台：5 分钟不够（10 分钟最小间隔），10 分钟才放行
        assertFalse(refresh(5L * 60 * 1000, failures = 1, foreground = false))
        assertTrue(refresh(10L * 60 * 1000, failures = 1, foreground = false))
        // 回前台立即触发一次：不受剩余秒数限制
        assertTrue(refresh(1_000, failures = 3, immediate = true))
        assertTrue(refresh(1_000, failures = 3, foreground = false, immediate = true))
        // 已切回主源（lowPrecision = false）：回到 30 分钟过期 / 5 分钟失败节流
        assertFalse(
            WeatherRepository.shouldRefresh(
                ageMillis = fresh,
                movedKm = 0.0,
                sinceAttemptMillis = 61_000,
                lowPrecision = false,
                lowPrecisionFailures = 3,
            ),
        )
        assertTrue(
            WeatherRepository.shouldRefresh(
                ageMillis = 31L * 60 * 1000,
                movedKm = 0.0,
                // 过期后由「5 分钟失败节流」决定：6 分钟已经放行。
                sinceAttemptMillis = 6L * 60 * 1000,
                lowPrecision = false,
                lowPrecisionFailures = 3,
            ),
        )
    }

    /** 诊断里的缓存状态：没过期就别写「数据过期」（低精度升级失败时缓存通常是刚写的）。 */
    @Test
    fun ageNoteDistinguishesFreshCacheFromStaleOne() {
        assertEquals("缓存仍有效（2 分钟）", WeatherRepository.ageNote(2L * 60 * 1000))
        assertEquals("缓存仍有效（30 分钟）", WeatherRepository.ageNote(30L * 60 * 1000))
        assertEquals("数据过期 45 分钟", WeatherRepository.ageNote(45L * 60 * 1000))
        assertEquals("无缓存", WeatherRepository.ageNote(null))
    }
}
