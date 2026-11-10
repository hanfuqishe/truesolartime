package com.realsuntime.solartime.ui

import android.content.Context
import com.realsuntime.solartime.R
import com.realsuntime.solartime.data.Place
import com.realsuntime.solartime.map.MapStyle
import java.time.LocalDate
import kotlin.math.abs

/** 按当前系统语言格式化时间、时长与时辰文案。 */
object TimeText {

    fun signedDuration(context: Context, seconds: Double): String =
        (if (seconds < 0) "-" else "+") + minutesSeconds(context, seconds)

    fun minutesSeconds(context: Context, seconds: Double): String {
        val total = abs(seconds).toLong()
        val hours = total / 3600
        val minutes = (total % 3600) / 60
        val rest = total % 60
        return when {
            hours > 0 -> context.getString(R.string.duration_hours_minutes, hours.toInt(), minutes.toInt())
            minutes > 0 -> context.getString(R.string.duration_minutes_seconds, minutes.toInt(), rest.toInt())
            else -> context.getString(R.string.duration_seconds, rest.toInt())
        }
    }

    fun duration(context: Context, seconds: Long?): String {
        if (seconds == null) return "--"
        return context.getString(
            R.string.duration_hours_minutes,
            (seconds / 3600).toInt(),
            ((seconds % 3600) / 60).toInt(),
        )
    }

    fun coordinates(context: Context, latitude: Double, longitude: Double): String = context.getString(
        R.string.coordinates,
        abs(latitude),
        if (latitude >= 0) "N" else "S",
        abs(longitude),
        if (longitude >= 0) "E" else "W",
    )

    fun dateWithWeekday(context: Context, date: LocalDate): String {
        val weekdays = context.resources.getStringArray(R.array.weekdays)
        val weekday = weekdays[date.dayOfWeek.value % 7]
        return context.getString(R.string.date_weekday, date.monthValue, date.dayOfMonth, weekday)
    }

    fun shichenName(context: Context, index: Int): String {
        val names = context.resources.getStringArray(R.array.shichen_names)
        return context.getString(R.string.shichen_name_format, names[index % names.size])
    }

    fun shichenHalf(context: Context, secondHalf: Boolean): String = context.getString(
        if (secondHalf) R.string.shichen_half_second else R.string.shichen_half_first,
    )

    fun shichenQuarter(context: Context, quarter: Int): String = context.getString(
        R.string.shichen_quarter_format,
        if (context.resources.getBoolean(R.bool.shichen_quarter_numerals)) {
            chineseNumeral(quarter)
        } else {
            quarter.toString()
        },
    )

    fun placeLabel(context: Context, place: Place): String =
        place.labelResName?.let { name ->
            val id = context.resources.getIdentifier(name, "string", context.packageName)
            if (id != 0) context.getString(id) else place.label
        } ?: place.label

    private fun chineseNumeral(value: Int): String = when (value) {
        1 -> "一"
        2 -> "二"
        3 -> "三"
        4 -> "四"
        else -> value.toString()
    }
}
/** 地图底图的本地化名称与版权说明。 */
object MapText {

    fun label(context: Context, style: MapStyle): String = context.getString(
        when (style) {
            MapStyle.AUTO -> R.string.map_style_auto
            MapStyle.OSM -> R.string.map_style_osm
            MapStyle.AMAP_VECTOR -> R.string.map_style_amap_vector
            MapStyle.AMAP_SATELLITE -> R.string.map_style_amap_satellite
        },
    )

    fun attribution(context: Context, style: MapStyle): String = context.getString(
        when (style) {
            MapStyle.AMAP_VECTOR, MapStyle.AMAP_SATELLITE -> R.string.map_attribution_amap
            else -> R.string.map_attribution_osm
        },
    )
}