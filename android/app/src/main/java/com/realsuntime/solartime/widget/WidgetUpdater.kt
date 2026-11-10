package com.realsuntime.solartime.widget

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.view.View
import android.widget.RemoteViews
import com.realsuntime.solartime.MainActivity
import com.realsuntime.solartime.R
import com.realsuntime.solartime.data.AppSettings
import com.realsuntime.solartime.data.CityIndex
import com.realsuntime.solartime.data.DistrictResolver
import com.realsuntime.solartime.data.LocationTracker
import com.realsuntime.solartime.data.Place
import com.realsuntime.solartime.data.PlaceSource
import com.realsuntime.solartime.data.WeatherRepository
import com.realsuntime.solartime.ui.TimeText
import com.realsuntime.solartime.map.CoordinateTransform
import com.realsuntime.solartime.solar.Shichen
import com.realsuntime.solartime.solar.SolarTimeMath
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime
import java.util.Locale
import kotlin.math.roundToLong

/**
 * 桌面小组件：左侧为所在国标准时间（跟随设备时区）、日期与星期，
 * 右侧为当地真太阳时与时辰。
 *
 * 时间由 Chronometer 自行逐秒走时（时数写成文字、分秒交给 Chronometer），
 * 这里按分钟对齐刷新其余内容（日期、时辰、坐标、昼夜底色）并校正时间；
 * 定位优先取系统最近一次定位，没有权限或没有定位记录时退回 App 保存的位置。
 */
object WidgetUpdater {

    const val ACTION_TICK = "com.realsuntime.solartime.action.WIDGET_TICK"
    private const val REQUEST_TICK = 7301
    private const val MINUTE_MILLIS = 60_000L
    private const val TICK_MARGIN_MILLIS = 250L

    fun refreshAll(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        val ids = manager.getAppWidgetIds(ComponentName(context, SolarWidgetProvider::class.java))
        if (ids.isEmpty()) {
            cancelTick(context)
            return
        }
        val place = resolvePlace(context)
        val views = buildViews(context, place)
        ids.forEach { manager.updateAppWidget(it, views) }
        scheduleNextTick(context, place)
        // 区县名与天气都要联网，命中缓存时不会重复请求；失败则用离线城市表／旧天气。
        DistrictResolver.requestRefresh(context, place)
        WeatherRepository.requestRefresh(context, place)
    }

    fun buildViews(context: Context, place: Place = resolvePlace(context)): RemoteViews {
        val now = Instant.now()
        val zone = civilZoneOf(place)
        val civil = now.atZone(zone)
        val civilOffset = civilOffsetMillis(now, zone)
        val solarOffset = solarOffsetMillis(now, place)
        val trueSolarSeconds = SolarTimeMath.trueSolarSecondsOfDay(now, place.longitude)
        val shichenIndex = Shichen.indexOf(trueSolarSeconds)
        val isDay = SolarTimeMath.solarAltitudeDegrees(now, place.latitude, place.longitude) > -0.833
        // 时:分由刷新写入；秒交给 ViewFlipper 每秒自动翻页（60 个孩子循环），
        // 每次刷新把显示位置对齐到当前秒，消除累积误差。
        val civilSeconds = secondsOfDay(now, civilOffset)
        val solarSeconds = secondsOfDay(now, solarOffset)

        return RemoteViews(context.packageName, R.layout.widget_solar_time).apply {
            setInt(
                R.id.widget_root,
                "setBackgroundResource",
                if (isDay) R.drawable.widget_background_day else R.drawable.widget_background_night,
            )
            setTextViewText(R.id.widget_civil_time, clockText(civilSeconds))
            setInt(R.id.widget_civil_sec, "setDisplayedChild", (civilSeconds % 60).toInt())
            setTextViewText(R.id.widget_civil_date, dateText(context, civil, place))
            setTextViewText(
                R.id.widget_city,
                DistrictResolver.cachedName(context)
                    ?: CityIndex.nearest(place.latitude, place.longitude, Locale.getDefault().language)?.name.orEmpty(),
            )
            setTextViewText(R.id.widget_solar_time, clockText(solarSeconds))
            setInt(R.id.widget_solar_sec, "setDisplayedChild", (solarSeconds % 60).toInt())
            setTextViewText(R.id.widget_solar_shichen, TimeText.shichenName(context, shichenIndex))
            setTextViewText(
                R.id.widget_coordinates,
                TimeText.coordinates(context, place.latitude, place.longitude),
            )
            bindHourly(context, now, zone, this)
            setOnClickPendingIntent(R.id.widget_root, openApp(context))
        }
    }

    /** 底部小时预报：从当前三小时块起，每格显示时刻与天气状况；没有数据时整行隐藏。 */
    private fun bindHourly(context: Context, now: Instant, zone: ZoneId, views: RemoteViews) {
        val hourly = WeatherRepository.hourly(context).associateBy { it.epochSeconds }
        views.setViewVisibility(R.id.widget_hour_row, if (hourly.isEmpty()) View.GONE else View.VISIBLE)
        if (hourly.isEmpty()) return

        val slots = WeatherRepository.slots(
            nowEpochSeconds = now.epochSecond,
            zoneOffsetSeconds = zone.rules.getOffset(now).totalSeconds,
            count = HOUR_LABEL_IDS.size,
            stepHours = HOUR_STEP,
        )
        // 第一格标「现在」，用实时天气码，与日期行的读数保持一致。
        val currentCode = WeatherRepository.cached(context)?.code
        slots.forEachIndexed { index, epoch ->
            val point = hourly[epoch]
            val label = when {
                point == null -> ""
                index == 0 -> context.getString(R.string.weather_now)
                else -> context.getString(
                    R.string.weather_hour,
                    Instant.ofEpochSecond(epoch).atZone(zone).hour,
                )
            }
            val code = if (index == 0) currentCode ?: point?.code else point?.code
            views.setTextViewText(HOUR_LABEL_IDS[index], label)
            val condition = code?.let { WeatherRepository.conditionOf(it) }
            val hour = Instant.ofEpochSecond(epoch).atZone(zone).hour
            views.setImageViewResource(
                HOUR_ICON_IDS[index],
                condition?.let { conditionIcon(it, isDay = hour in 6..17) } ?: R.drawable.ic_wx_unknown,
            )
            views.setTextViewText(
                HOUR_COND_IDS[index],
                condition?.let { TimeText.conditionLabel(context, it) }.orEmpty(),
            )
        }
    }

    /** 逐时格子的天气图标；夜间用月亮区分晴与多云。 */
    private fun conditionIcon(condition: WeatherRepository.Condition, isDay: Boolean): Int =
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

    /** 系统时刻加上偏移后，落在当天的第几秒。 */
    private fun secondsOfDay(now: Instant, offsetMillis: Long): Long =
        Math.floorMod(now.toEpochMilli() + offsetMillis, 86_400_000L) / 1000L

    /** 标准时间相对 UTC 的偏移。 */
    private fun civilOffsetMillis(now: Instant, zone: ZoneId): Long =
        zone.rules.getOffset(now).totalSeconds * 1000L

    /** 真太阳时相对 UTC 的偏移。 */
    private fun solarOffsetMillis(now: Instant, place: Place): Long =
        (SolarTimeMath.trueSolarOffsetSeconds(now, place.longitude) * 1000.0).roundToLong()

    private fun clockText(secondsOfDay: Long): String =
        "%02d:%02d".format(Locale.ROOT, secondsOfDay / 3600, secondsOfDay / 60 % 60)

    /**
     * 对齐到下一次「整分」或「真太阳时整分」，取更早的那个再多留 0.25 秒。
     *
     * 两个时钟的分钟边界相差 0~59 秒，只按整分刷新会让真太阳时的分钟最多滞后近一分钟，
     * 所以两者各自的边界都要刷新一次（一小时里两者交替，约每 30 秒一次）。
     */
    fun scheduleNextTick(context: Context, place: Place = resolvePlace(context)) {
        val manager = context.getSystemService(AlarmManager::class.java) ?: return
        val nowMillis = System.currentTimeMillis()
        val now = Instant.ofEpochMilli(nowMillis)
        val toCivil = millisToNextMinute(nowMillis, civilOffsetMillis(now, civilZoneOf(place)))
        val toSolar = millisToNextMinute(nowMillis, solarOffsetMillis(now, place))
        val next = nowMillis + minOf(toCivil, toSolar) + TICK_MARGIN_MILLIS
        val pendingIntent = tickIntent(context)
        // 用 RTC（不唤醒），熄屏时不刷新也无妨，亮屏后系统会补发。
        if (canScheduleExact(manager)) {
            manager.setExact(AlarmManager.RTC, next, pendingIntent)
        } else {
            manager.set(AlarmManager.RTC, next, pendingIntent)
        }
    }

    /** 显示时刻距离下一个整分还有多少毫秒。 */
    private fun millisToNextMinute(nowMillis: Long, offsetMillis: Long): Long =
        MINUTE_MILLIS - Math.floorMod(nowMillis + offsetMillis, MINUTE_MILLIS)

    private val HOUR_LABEL_IDS = intArrayOf(
        R.id.widget_hour_label_0,
        R.id.widget_hour_label_1,
        R.id.widget_hour_label_2,
        R.id.widget_hour_label_3,
        R.id.widget_hour_label_4,
        R.id.widget_hour_label_5,
    )

    private val HOUR_ICON_IDS = intArrayOf(
        R.id.widget_hour_icon_0,
        R.id.widget_hour_icon_1,
        R.id.widget_hour_icon_2,
        R.id.widget_hour_icon_3,
        R.id.widget_hour_icon_4,
        R.id.widget_hour_icon_5,
    )

    private val HOUR_COND_IDS = intArrayOf(
        R.id.widget_hour_cond_0,
        R.id.widget_hour_cond_1,
        R.id.widget_hour_cond_2,
        R.id.widget_hour_cond_3,
        R.id.widget_hour_cond_4,
        R.id.widget_hour_cond_5,
    )

    /** 每格代表 1 小时。 */
    private const val HOUR_STEP = 1

    fun cancelTick(context: Context) {
        val manager = context.getSystemService(AlarmManager::class.java) ?: return
        manager.cancel(tickIntent(context))
    }

    /** 请求把小组件固定到桌面（Android 8.0+ 且启动器支持时）。 */
    fun requestPin(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(AppWidgetManager::class.java) ?: return
        if (!manager.isRequestPinAppWidgetSupported) return
        val provider = ComponentName(context, SolarWidgetProvider::class.java)
        manager.requestPinAppWidget(provider, null, null)
    }

    private fun tickIntent(context: Context): PendingIntent {
        val intent = Intent(context, SolarWidgetProvider::class.java).setAction(ACTION_TICK)
        return PendingIntent.getBroadcast(
            context,
            REQUEST_TICK,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun canScheduleExact(manager: AlarmManager): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S || manager.canScheduleExactAlarms()

    /**
     * 所在地的法定时区。中国全境统一为东八区，直接固定；
     * 其他地区跟随设备时区（人在当地时手机通常已自动切换）。
     */
    private fun civilZoneOf(place: Place): ZoneId =
        if (CoordinateTransform.isInChina(place.latitude, place.longitude)) {
            ZoneId.of("Asia/Shanghai")
        } else {
            ZoneId.systemDefault()
        }

    private fun resolvePlace(context: Context): Place {
        val fix = LocationTracker(context).lastKnownLocation()
        if (fix != null) {
            return Place(fix.latitude, fix.longitude, PlaceSource.GPS, context.getString(R.string.gps_label))
        }
        return AppSettings(context).place
    }

    private fun openApp(context: Context): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        return PendingIntent.getActivity(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun dateText(context: Context, civil: ZonedDateTime, place: Place): String {
        val date = TimeText.dateShortWithWeekday(context, civil.toLocalDate())
        val range = WeatherRepository.temperatureRange(
            WeatherRepository.hourly(context),
            civil.toLocalDate(),
            civil.zone,
        ) ?: return date
        return context.getString(R.string.date_high_low, date, range.second, range.first)
    }
}
