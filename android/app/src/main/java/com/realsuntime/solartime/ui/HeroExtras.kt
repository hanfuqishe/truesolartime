package com.realsuntime.solartime.ui

import android.content.Context
import com.realsuntime.solartime.R
import com.realsuntime.solartime.data.TakeBand
import com.realsuntime.solartime.data.TakeTemperature
import com.realsuntime.solartime.data.TakeTimeRepository
import com.realsuntime.solartime.data.WeatherRepository
import java.time.Instant
import java.time.ZoneOffset

/**
 * 首页大卡片里那些「慢变量」的一次性读数：日期、天气与温度区间、六格逐时预报、关键时段。
 *
 * 逐秒变化的部分（两个时钟、时间轴上的圆点、关键时间配色）不在这里，由 Compose 直接按 [Instant] 算，
 * 免得每秒都去读一次 SharedPreferences。
 */
internal data class HourCell(val label: String, val condition: String, val iconRes: Int)

internal data class HeroExtras(
    val dateText: String,
    val weatherText: String,
    val rangeText: String,
    val hourly: List<HourCell>,
    val bands: List<TakeBand>,
    val temperature: TakeTemperature?,
)

/** 与卡片左栏的「标准时间」一致：北京时间。 */
private val BEIJING: ZoneOffset = ZoneOffset.ofHours(8)

/** 逐时预报的格数与步长（小时），与桌面卡片保持一致。 */
private const val HOUR_CELLS = 6
private const val HOUR_STEP = 1

internal fun loadHeroExtras(context: Context, now: Instant): HeroExtras {
    val civil = now.atZone(BEIJING)
    val date = civil.toLocalDate()
    val schedule = TakeTimeRepository.schedule(context)
    val cached = WeatherRepository.cached(context)
    val hourly = WeatherRepository.hourly(context)
    val range = WeatherRepository.temperatureRange(hourly, date, civil.zone)

    val condition = cached?.let { WeatherRepository.conditionOf(it.code) }
    val temperatureText = cached?.let { context.getString(R.string.weather_temp, it.temperatureC) }.orEmpty()
    val weatherText = if (condition == null) {
        temperatureText
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
        hourly = hourCells(context, now, cached?.code),
        bands = schedule?.bands.orEmpty(),
        temperature = schedule?.temperature,
    )
}

/** 从当前整点起的六格逐时预报；首格标「现在」并用实时天气码，与桌面卡片同一套规则。 */
private fun hourCells(context: Context, now: Instant, currentCode: Int?): List<HourCell> {
    val hourly = WeatherRepository.hourly(context).associateBy { it.epochSeconds }
    val slots = WeatherRepository.slots(
        nowEpochSeconds = now.epochSecond,
        zoneOffsetSeconds = BEIJING.totalSeconds,
        count = HOUR_CELLS,
        stepHours = HOUR_STEP,
    )
    val current = WeatherRepository.cached(context)
    return slots.mapIndexed { index, epoch ->
        val point = hourly[epoch]
        val code = if (index == 0) current?.code ?: currentCode ?: point?.code else point?.code
        val condition = code?.let { WeatherRepository.conditionOf(it) }
        val hour = Instant.ofEpochSecond(epoch).atZone(BEIJING).hour
        HourCell(
            label = when {
                index == 0 -> context.getString(R.string.weather_now)
                point == null -> ""
                else -> context.getString(R.string.weather_hour, hour)
            },
            condition = condition?.let { TimeText.conditionLabel(context, it) }.orEmpty(),
            iconRes = condition?.let { weatherIconRes(it, isDay = hour in 6..17) } ?: R.drawable.ic_wx_unknown,
        )
    }
}

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
