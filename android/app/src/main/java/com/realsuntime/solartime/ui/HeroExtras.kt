package com.realsuntime.solartime.ui

import android.content.Context
import com.realsuntime.solartime.R
import com.realsuntime.solartime.data.LocalZone
import com.realsuntime.solartime.data.Place
import com.realsuntime.solartime.data.TakeBand
import com.realsuntime.solartime.data.TakeTemperature
import com.realsuntime.solartime.data.TakeTimeRepository
import com.realsuntime.solartime.data.WeatherRepository
import java.time.Instant
import java.time.ZoneOffset

/**
 * 日期与逐时预报按**当地标准时**算，跟左栏那个时钟同一口径（见 [LocalZone]）：
 * 人在纽约时日期是纽约的日期、逐时格子的整点也是纽约的整点，不会出现「时钟写着 12:00、
 * 日期却是北京那天的」这种错位。
 *
 * 逐秒变化的部分（两个时钟、时间轴上的圆点、关键时间配色）不在这里，由 Compose 直接按 [Instant] 算，
 * 免得每秒都去读一次 SharedPreferences。
 */
internal data class HourCell(
    /** 该格的时刻标签：「现在」或「23时」。 */
    val label: String,
    /** 图标下面那一行：该格气温（如 `18°`），缺读数时是占位符 `-`。 */
    val temperature: String,
    /** 天气图标；null = 不画图标（未知态没有天气，但要占住同一格位置保持行高）。 */
    val iconRes: Int?,
)

internal data class HeroExtras(
    val dateText: String,
    val weatherText: String,
    val rangeText: String,
    val hourly: List<HourCell>,
    val bands: List<TakeBand>,
    val temperature: TakeTemperature?,
)

/** 逐时预报的格数：**永远是 6 格**，格与格之间的步长跟随数据源（1 小时或 3 小时）。 */
private const val HOUR_CELLS = 6

internal fun loadHeroExtras(
    context: Context,
    place: Place,
    now: Instant,
    zoneOffsetSeconds: Int,
): HeroExtras {
    val zone = LocalZone.zoneOffset(zoneOffsetSeconds)
    val civil = now.atZone(zone)
    val date = civil.toLocalDate()
    val schedule = TakeTimeRepository.schedule(context)
    val cached = WeatherRepository.cached(context, place)
    val hourly = WeatherRepository.hourly(context, place)
    val range = WeatherRepository.temperatureRange(hourly.points, date, civil.zone)

    val condition = cached?.let { WeatherRepository.conditionOf(it.code) }
    val temperatureText = cached?.let { context.getString(R.string.weather_temp, it.temperatureC) }.orEmpty()
    val weatherText = if (condition == null) {
        // 没有有效天气时用占位符，别让这一格空着（也别沿用上一个地点的读数）。
        context.getString(R.string.weather_unknown)
    } else if (temperatureText.isEmpty()) {
        TimeText.conditionLabel(context, condition)
    } else {
        context.getString(R.string.hero_weather, temperatureText, TimeText.conditionLabel(context, condition))
    }
    val rangeText = range?.let { context.getString(R.string.hero_temp_range, it.second, it.first) }.orEmpty()

    return HeroExtras(
        dateText = TimeText.dateShortWithWeekday(context, date),
        weatherText = weatherText,
        rangeText = rangeText,
        hourly = hourCells(context, hourly, now, cached?.code, cached?.temperatureC, zone),
        bands = schedule?.bands.orEmpty(),
        temperature = schedule?.temperature,
    )
}

/**
 * 未知态（定位不可用）的附加数据：**日期与逐时行照常**（按系统时区），天气读数留空。
 *
 * 没有坐标就没有天气，但**逐时行的结构要留住**：六格时间标签照常按系统时间往后推，
 * 图标不画、温度写 `--°` —— 卡片高度与正常态一致，不会因为少了一行而突然变矮。
 * 关键时段的色段不画（那需要真实的天气温度）。
 */
internal fun unknownHeroExtras(
    context: Context,
    now: Instant,
    zoneOffsetSeconds: Int,
    weatherPlaceholder: String,
    temperaturePlaceholder: String,
): HeroExtras {
    val zone = LocalZone.zoneOffset(zoneOffsetSeconds)
    val civil = now.atZone(zone)
    return HeroExtras(
        dateText = TimeText.dateShortWithWeekday(context, civil.toLocalDate()),
        weatherText = weatherPlaceholder,
        rangeText = "",
        hourly = placeholderHourCells(
            nowHour = civil.hour,
            nowLabel = context.getString(R.string.weather_now),
            hourLabel = { hour -> context.getString(R.string.weather_hour, hour) },
            temperature = temperaturePlaceholder,
        ),
        bands = emptyList(),
        temperature = null,
    )
}

/**
 * 未知态的六格逐时占位（**纯函数**，便于单测）。
 *
 * 规则与正常态一致：首格是「现在」，之后每小时一格，跨午夜回绕到 0 点；
 * 每格温度都是占位符，图标为 null（行内照样留出 22dp 的图标位，行高不变）。
 *
 * @param nowHour 系统时区此刻的小时（0–23）
 */
internal fun placeholderHourCells(
    nowHour: Int,
    nowLabel: String,
    hourLabel: (Int) -> String,
    temperature: String,
    count: Int = HOUR_CELLS,
): List<HourCell> = (0 until count).map { offset ->
    val hour = Math.floorMod(nowHour + offset, 24)
    HourCell(
        label = if (offset == 0) nowLabel else hourLabel(hour),
        temperature = temperature,
        iconRes = null,
    )
}

/**
 * 从「现在」那一格起的六格逐时预报；首格标「现在」并用实时天气码，与桌面卡片同一套规则。
 *
 * 步长跟着数据源走：主源（Open-Meteo）1 小时一格 → 现在/22时/23时/0时/1时/2时；
 * 备用源（7Timer!）3 小时一格 → 现在/23时/2时/5时/8时/11时。
 * 标签一律用**该采样点的实际本地小时数**，不按「现在 + n 小时」推算。
 *
 * @param currentCode 实时天气码：只用于判定「现在」那一格的图标（采样点可能已经过时）。
 * @param currentTemperature 实时气温：只用于「现在」那一格的温度（见 [hourTemperatures]）。
 */
private fun hourCells(
    context: Context,
    hourly: WeatherRepository.Hourly,
    now: Instant,
    currentCode: Int?,
    currentTemperature: Int?,
    zone: ZoneOffset,
): List<HourCell> {
    val points = hourly.points.associateBy { it.epochSeconds }
    val slots = WeatherRepository.visibleSlots(
        points = hourly.points,
        nowEpochSeconds = now.epochSecond,
        zoneOffsetSeconds = zone.totalSeconds,
        count = HOUR_CELLS,
        stepHours = hourly.stepHours,
    )
    val temperatures = hourTemperatures(
        points = hourly.points,
        nowEpochSeconds = now.epochSecond,
        zoneOffsetSeconds = zone.totalSeconds,
        stepHours = hourly.stepHours,
        currentTemperatureC = currentTemperature,
    )
    val unknown = context.getString(R.string.weather_unknown)
    val degrees: (Int) -> String = { context.getString(R.string.weather_temp, it) }
    return slots.mapIndexed { index, slot ->
        val point = points[slot.epochSeconds]
        val code = if (slot.isNow) currentCode ?: point?.code else point?.code
        val condition = code?.let { WeatherRepository.conditionOf(it) }
        val hour = Instant.ofEpochSecond(slot.epochSeconds).atZone(zone).hour
        HourCell(
            label = if (slot.isNow) {
                context.getString(R.string.weather_now)
            } else {
                context.getString(R.string.weather_hour, hour)
            },
            temperature = temperatureLabel(temperatures[index], degrees, unknown),
            iconRes = condition?.let { weatherIconRes(it, isDay = hour in 6..17) } ?: R.drawable.ic_wx_unknown,
        )
    }
}

/**
 * 六格逐时气温：**首格（「现在」）用实时读数**，其余格用各自采样点的温度；没有该格采样点时是 null。
 *
 * 「现在」为什么不用采样点温度：备用源（7Timer!）3 小时才有一个采样点，那一格可能是几小时前的
 * 读数；而卡片日期行里那个温度（`WeatherRepository.cached(...).temperatureC`）是此刻的实时读数。
 * 两处挨着显示，若「现在」格写着 15°、日期行写着 18°，看上去就像其中一个错了 —— 所以首格跟着
 * 日期行走。主源（Open-Meteo）也照同一规则：首格取 `current`，不取整点采样点。
 * iOS 版（`HeroCard.HourlyRow`）与鸿蒙版是同一条规则。
 *
 * @param currentTemperatureC 卡片日期行用的那个实时温度；没有实时读数时退回该采样点的温度。
 * @param skip 跳过前面几格（桌面卡片的第二排逐时行接在第一排后面）。
 * @param hasFix false = 还没有有效定位：这份天气属于兜底的默认坐标，宁可全画占位符。
 */
internal fun hourTemperatures(
    points: List<WeatherRepository.HourPoint>,
    nowEpochSeconds: Long,
    zoneOffsetSeconds: Int,
    stepHours: Int,
    currentTemperatureC: Int?,
    count: Int = HOUR_CELLS,
    skip: Int = 0,
    hasFix: Boolean = true,
): List<Int?> {
    if (!hasFix) return List(count) { null }
    val pointsByEpoch = points.associateBy { it.epochSeconds }
    return WeatherRepository.visibleSlots(
        points = points,
        nowEpochSeconds = nowEpochSeconds,
        zoneOffsetSeconds = zoneOffsetSeconds,
        count = count,
        stepHours = stepHours,
        skip = skip,
    ).map { slot ->
        val point = pointsByEpoch[slot.epochSeconds]
        if (slot.isNow) (currentTemperatureC ?: point?.temperatureC) else point?.temperatureC
    }
}

/**
 * 一格温度的文字：有读数时按 `18°`（数字 + 度符号，不带 C），缺读数时是占位符 `-`。
 *
 * 占位符沿用 `R.string.weather_unknown`（就是 `-`），不是 `--`：温度只有「有」和「没有」两种，
 * 写成两个字符在 22dp 的图标下面会挤成一条看不清的横线。度数格式也走资源
 * （`R.string.weather_temp` = `%1$d°`），本地化口径与日期行那个温度完全一致。
 */
internal fun temperatureLabel(
    temperatureC: Int?,
    degrees: (Int) -> String,
    placeholder: String,
): String = temperatureC?.let(degrees) ?: placeholder

/** 逐时格子的天气图标；夜间用月亮区分晴与多云。 */
private fun weatherIconRes(condition: WeatherRepository.Condition, isDay: Boolean): Int =
    when (condition) {
        WeatherRepository.Condition.CLEAR ->
            if (isDay) R.drawable.ic_wx_clear_day else R.drawable.ic_wx_clear_night
        WeatherRepository.Condition.PARTLY_CLOUDY ->
            if (isDay) R.drawable.ic_wx_partly_day else R.drawable.ic_wx_partly_night
        WeatherRepository.Condition.OVERCAST -> R.drawable.ic_wx_overcast
        WeatherRepository.Condition.FOG -> R.drawable.ic_wx_fog
        WeatherRepository.Condition.DRIZZLE -> R.drawable.ic_wx_drizzle
        WeatherRepository.Condition.RAIN -> R.drawable.ic_wx_rain
        WeatherRepository.Condition.HEAVY_RAIN -> R.drawable.ic_wx_heavy_rain
        WeatherRepository.Condition.SHOWERS -> R.drawable.ic_wx_showers
        WeatherRepository.Condition.SNOW -> R.drawable.ic_wx_snow
        WeatherRepository.Condition.HEAVY_SNOW -> R.drawable.ic_wx_heavy_snow
        WeatherRepository.Condition.THUNDER -> R.drawable.ic_wx_thunder
    }
