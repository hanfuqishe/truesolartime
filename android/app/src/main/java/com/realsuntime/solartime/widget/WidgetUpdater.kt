package com.realsuntime.solartime.widget

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Paint
import android.graphics.Typeface
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.text.TextPaint
import android.util.DisplayMetrics
import android.util.TypedValue
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
import com.realsuntime.solartime.data.TakeTimeRepository
import com.realsuntime.solartime.data.TakeTimeSchedule
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
 * 标准时间由布局里的 TextClock 自走（含秒），真太阳时由刷新写入时分、ViewFlipper 自走秒数；
 * 这里按「整分」与「真太阳时整分」刷新日期、时辰、坐标、天气与昼夜底色。
 * 定位优先取系统最近一次定位，没有权限或没有定位记录时退回 App 保存的位置。
 */
object WidgetUpdater {

    const val ACTION_TICK = "com.realsuntime.solartime.action.WIDGET_TICK"

    /** 刷新闹钟携带的目标写入时刻（epoch 毫秒），接收方据此等到整分边界再刷新。 */
    const val EXTRA_TICK_AT = "com.realsuntime.solartime.extra.TICK_AT"
    private const val REQUEST_TICK = 7301
    private const val REQUEST_APP = 7302
    private const val REQUEST_ALARM = 7303
    private const val REQUEST_WEATHER = 7304
    private const val REQUEST_CALENDAR = 7305
    private const val MINUTE_MILLIS = 60_000L

    /** 写入落在这个整分边界之后多少毫秒：小到肉眼看来就是「秒数跳到 00 的同一刻」。 */
    internal const val TICK_MARGIN_MILLIS = 30L

    /**
     * 闹钟提前醒来、等真正的边界再写入的提前量。
     * 精确闹钟只有几十毫秒抖动；未授予精确闹钟权限时系统闹钟可能迟到近 1 秒，需要多留一些。
     */
    private const val TICK_LEAD_EXACT_MILLIS = 200L
    private const val TICK_LEAD_INEXACT_MILLIS = 1_000L

    /** 等待上限，兜住异常的时间戳，避免广播一直不结束。 */
    private const val TICK_MAX_LEAD_MILLIS = TICK_LEAD_INEXACT_MILLIS + TICK_MARGIN_MILLIS

    /** 外部应用（闹钟/天气）的解析结果缓存时长。 */
    private const val RESOLVE_TTL_MILLIS = 10L * 60 * 1000

    /**
     * 桌面回报的高度（OPTION_APPWIDGET_MIN_HEIGHT）普遍小于实际可用的单元格高度
     * （实测 2 行回报 131dp、实际约 165dp；3 行回报 180dp、实际约 224dp），
     * 按这个系数折算后再决定用哪套布局。
     */
    private const val HEIGHT_SCALE = 1.25f

    /** 折算后低于这个高度就用紧凑间距布局（常规内容约 170dp）。 */
    private const val REGULAR_MIN_CONTENT_DP = 170f

    /** 折算后低于这个高度时连逐时行都放不下，先隐藏它把空间留给时钟。 */
    private const val MIN_HEIGHT_WITH_HOURLY_DP = 145f

    /** 桌面没给出宽度时按默认 5x2 小组件的宽度（dp）估算字号。 */
    private const val DEFAULT_WIDGET_WIDTH_DP = 320f

    /** 两栏之间的分隔线（1dp）与内边距/外边距：常规版 14+14+12+1+12，紧凑版 10+10+8+1+8。 */
    private const val COLUMN_CHROME_DP = 53f
    private const val COMPACT_COLUMN_CHROME_DP = 37f

    private const val TEXT_GAP_DP = 2f

    /** 地名那一行：字号与左侧「标准时间」标签的宽度（4 个汉字）估算用。 */
    private const val CITY_TEXT_SP = 11f
    private const val CITY_LABEL_CHARS = 4
    private const val CITY_LABEL_GAP_DP = 6f

    /** 跨栏显示地名时，右端要给「时辰」两个字留出的宽度。 */
    private const val CITY_WIDE_END_RESERVE_DP = 26f

    /** 时间轴的左右内边距（与布局里 widget_root 的 paddingStart/End 一致）与高度。 */
    private const val AXIS_PADDING_DP = 14f
    private const val COMPACT_AXIS_PADDING_DP = 10f
    private const val AXIS_HEIGHT_DP = 13f
    private const val COMPACT_AXIS_HEIGHT_DP = 11f
    private const val MAIN_TEXT_SAMPLE = "00:00"
    private const val SECOND_SAMPLE = "00"

    /** 秒数宽度的余量：等宽字体下切点本就精确，只留一点防亚像素裁边。 */
    private const val SECOND_WIDTH_SLACK_DP = 0.25f
    private const val MAX_MAIN_TEXT_SP = 48f
    private const val MIN_MAIN_TEXT_SP = 20f
    private const val SECOND_TEXT_SP = 23f
    private const val DATE_TEXT_SP = 11f
    private const val MIN_DATE_TEXT_SP = 8f

    /** 真太阳时的默认颜色；进入关键时间段时改用 KeyTimePalette 里的绿或红。 */
    private const val SOLAR_TIME_COLOR = 0xFFFFC65C.toInt()

    /** 还没有有效 GPS 定位时真太阳时的占位符。 */
    private const val SOLAR_PLACEHOLDER = "--:--"

    /**
     * 小组件用的定位结果。
     *
     * [hasFix] 为 false 表示「跟随 GPS 但还没拿到过有效定位」，此时真太阳时无从计算，
     * 只能显示占位，不能拿默认坐标或旧坐标冒充。
     */
    data class LocationState(val place: Place, val hasFix: Boolean)

    /**
     * 决定能否显示真太阳时。
     *
     * @param followingGps 是否处于 GPS 跟随模式（手动指定位置时为 false）
     * @param hadFix 此前是否真的拿到过 GPS 定位（设置里保存的位置来自 GPS）
     * @param fixNow 当前是否能取到系统最近一次定位
     */
    internal fun hasValidFix(followingGps: Boolean, hadFix: Boolean, fixNow: Boolean): Boolean =
        fixNow || !followingGps || hadFix


    fun refreshAll(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        val ids = manager.getAppWidgetIds(ComponentName(context, SolarWidgetProvider::class.java))
        if (ids.isEmpty()) {
            cancelTick(context)
            return
        }
        val location = resolveLocation(context)
        val place = location.place
        // 各机型/桌面给到的尺寸不同：按可用宽度与折算后的高度换算字号，2 行高时压缩留白。
        ids.forEach { id ->
            val options = manager.getAppWidgetOptions(id)
            val widthDp = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH)
            val heightDp = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT)
            manager.updateAppWidget(id, buildViews(context, location, widthDp, heightDp))
        }
        scheduleNextTick(context, place)
        // 区县名与天气都要联网，命中缓存时不会重复请求；失败则用离线城市表／旧天气。
        DistrictResolver.requestRefresh(context, place)
        WeatherRepository.requestRefresh(context, place)
        // 关键时间每天在 01:00–05:00 随机时刻同步一次，失败每小时重试，结果缓存 7 天。
        TakeTimeRepository.requestRefresh(context)
        // 关键时间可能刚更新，重排「进入关键时间」报时（关闭时这里是空操作）。
        KeyTimeChime.schedule(context)
    }

    fun buildViews(
        context: Context,
        location: LocationState = resolveLocation(context),
        widthDp: Int = 0,
        heightDp: Int = 0,
    ): RemoteViews {
        val place = location.place
        val now = Instant.now()
        val zone = civilZoneOf(place)
        val civil = now.atZone(zone)
        val solarOffset = solarOffsetMillis(now, place)
        val trueSolarSeconds = SolarTimeMath.trueSolarSecondsOfDay(now, place.longitude)
        val shichenIndex = Shichen.indexOf(trueSolarSeconds)
        val isDay = SolarTimeMath.solarAltitudeDegrees(now, place.latitude, place.longitude) > -0.833
        // 时:分由刷新写入；秒交给 ViewFlipper 每秒自动翻页（60 个孩子循环），
        // 每次刷新把显示位置对齐到当前秒，消除累积误差。
        // 标准时间改由布局里的 TextClock 自走（含秒），不再依赖刷新。
        val solarSeconds = secondsOfDay(now, solarOffset)
        val date = dateText(context, civil, place, location.hasFix)
        // 桌面回报的高度比实际单元格小，先折算成近似可用高度。
        val effectiveHeightDp = if (heightDp > 0) heightDp * HEIGHT_SCALE else 0f
        // 折算后放不下常规布局的内容（如默认 5x2）时，改用只压缩留白的紧凑间距布局。
        val compact = effectiveHeightDp > 0f && effectiveHeightDp < REGULAR_MIN_CONTENT_DP
        // 关键时间只在刷新时读一次：时间轴着色与真太阳时的数字都要用。
        val keyTime = TakeTimeRepository.schedule(context)
        val solarSecondsOfDay = solarSeconds.toDouble()
        val keyColor = if (location.hasFix) activeKeyColor(keyTime, solarSecondsOfDay) else null
        // 再矮就连逐时行都放不下，先让位给时钟。
        val showHourly = effectiveHeightDp <= 0f || effectiveHeightDp >= MIN_HEIGHT_WITH_HOURLY_DP
        val layout = if (compact) R.layout.widget_solar_time_compact else R.layout.widget_solar_time

        return RemoteViews(context.packageName, layout).apply {
            setInt(
                R.id.widget_root,
                "setBackgroundResource",
                if (isDay) R.drawable.widget_background_day else R.drawable.widget_background_night,
            )
            // 主时间字号按栏宽换算（桌面回报的宽度与实际一致），保证填满栏宽又不被裁切。
            applyClockSizing(context, widthDp, date, compact, this)
            bindAxis(context, widthDp, compact, now, location.hasFix, solarOffset, keyTime, this)
            setString(R.id.widget_civil_time, "setTimeZone", zone.id)
            setString(R.id.widget_civil_sec, "setTimeZone", zone.id)
            setTextViewText(R.id.widget_civil_date, date)
            val city = cityLabel(context, place, widthDp, compact)
            setTextViewText(R.id.widget_city, if (location.hasFix) city.text else "")
            setTextViewText(R.id.widget_city_wide, if (location.hasFix) city.text else "")
            setViewVisibility(R.id.widget_city, if (location.hasFix && !city.wide) View.VISIBLE else View.GONE)
            setViewVisibility(
                R.id.widget_city_wide,
                if (location.hasFix && city.wide) View.VISIBLE else View.GONE,
            )
            // 名字太长时先把标签的位置让出去，版面才装得下完整地名。
            setViewVisibility(
                R.id.widget_label_civil,
                if (city.showCivilLabel) View.VISIBLE else View.GONE,
            )
            setViewVisibility(
                R.id.widget_label_solar,
                if (city.showSolarLabel) View.VISIBLE else View.GONE,
            )
            if (location.hasFix) {
                setTextViewText(R.id.widget_solar_time, clockText(solarSeconds))
                // 秒数交给 Chronometer 自走：base 取「当前真太阳时整分的时刻」，
                // 它每秒按 base 重算到下一整秒的延时，因此永远落在整秒边界上，不会累积漂移。
                val minuteStartElapsed =
                    SystemClock.elapsedRealtime() - Math.floorMod(now.toEpochMilli() + solarOffset, MINUTE_MILLIS)
                setChronometer(R.id.widget_solar_sec, minuteStartElapsed, null, true)
                setViewVisibility(R.id.widget_solar_colon, View.VISIBLE)
                setViewVisibility(R.id.widget_solar_sec, View.VISIBLE)
                // 处在关键时间段里时，时:分、冒号与秒一起换成关键时间的配色。
                applySolarColor(keyColor ?: SOLAR_TIME_COLOR, this)
                setTextViewText(R.id.widget_solar_shichen, TimeText.shichenName(context, shichenIndex))
                setTextViewText(
                    R.id.widget_coordinates,
                    TimeText.coordinates(context, place.latitude, place.longitude),
                )
            } else {
                // 跟随 GPS 但还没有有效定位：真太阳时无从计算，显示占位而不是拿旧位置冒充。
                setTextViewText(R.id.widget_solar_time, SOLAR_PLACEHOLDER)
                setViewVisibility(R.id.widget_solar_colon, View.GONE)
                setViewVisibility(R.id.widget_solar_sec, View.GONE)
                applySolarColor(SOLAR_TIME_COLOR, this)
                setTextViewText(R.id.widget_solar_shichen, "")
                setTextViewText(R.id.widget_coordinates, context.getString(R.string.widget_waiting_gps))
            }
            bindHourly(context, now, zone, showHourly && location.hasFix, this)
            bindClicks(context, place, this)
        }
    }

    /**
     * 画时间轴：真太阳时 0–24 时，色带为「关键时间」，白点是当前时刻。
     *
     * 宽度按桌面回报的宽度减去左右内边距换算；还没有定位时不画点与色带，只留一条轴线。
     */
    private fun bindAxis(
        context: Context,
        widthDp: Int,
        compact: Boolean,
        now: Instant,
        hasFix: Boolean,
        solarOffsetMillis: Long,
        schedule: TakeTimeSchedule?,
        views: RemoteViews,
    ) {
        val density = context.resources.displayMetrics.density
        val totalWidthDp = if (widthDp > 0) widthDp.toFloat() else DEFAULT_WIDGET_WIDTH_DP
        val paddingDp = if (compact) COMPACT_AXIS_PADDING_DP else AXIS_PADDING_DP
        val widthPx = ((totalWidthDp - paddingDp * 2f) * density).toInt()
        val heightDp = if (compact) COMPACT_AXIS_HEIGHT_DP else AXIS_HEIGHT_DP
        val heightPx = (heightDp * density).toInt()
        val solarSeconds = if (hasFix) {
            Math.floorMod(now.toEpochMilli() + solarOffsetMillis, 86_400_000L) / 1000L
        } else {
            null
        }
        // 关键时间本身就按真太阳时算，和轴上的点同一套刻度，不用再换算。
        val bitmap = WidgetAxis.render(
            context = context,
            widthPx = widthPx,
            heightPx = heightPx,
            solarSecondsOfDay = solarSeconds,
            bands = schedule?.bands.orEmpty(),
            temperature = schedule?.temperature,
        )
        if (bitmap != null) {
            views.setImageViewBitmap(R.id.widget_axis, bitmap)
        }
    }

    /**
     * 那一行能显示的地名：名字越长，依次让出「标准时间」「真太阳时」标签的位置，
     * 而不是把名字截成「克孜勒苏柯尔克孜自治…」。
     */
    private fun cityLabel(context: Context, place: Place, widthDp: Int, compact: Boolean): CityLabelPlan {
        val fallback = CityIndex.nearest(
            place.latitude,
            place.longitude,
            Locale.getDefault().language,
        )?.name.orEmpty()
        val names = DistrictResolver.cachedNames(context)
        val totalWidthDp = if (widthDp > 0) widthDp.toFloat() else DEFAULT_WIDGET_WIDTH_DP
        val chromeDp = if (compact) COMPACT_COLUMN_CHROME_DP else COLUMN_CHROME_DP
        val columnDp = (totalWidthDp - chromeDp) / 2f
        val paddingDp = if (compact) 10f else 14f
        val maxNarrow = ((columnDp - CITY_LABEL_CHARS * CITY_TEXT_SP - CITY_LABEL_GAP_DP) / CITY_TEXT_SP).toInt()
        val maxNoLabel = ((columnDp - CITY_LABEL_GAP_DP) / CITY_TEXT_SP).toInt()
        // 跨栏时可用的宽度：整条轴减去左右内边距，再给右端的「时辰」留出位置。
        val maxWide = ((totalWidthDp - paddingDp * 2f - CITY_WIDE_END_RESERVE_DP) / CITY_TEXT_SP).toInt()
        return planCityLabel(names, fallback, maxNarrow, maxNoLabel, maxWide)
    }

    /**
     * 地名的三级显示：先按现状塞进左栏；塞不下就把「标准时间」标签让出来；
     * 还塞不下就连「真太阳时」的标签一起让出来，改成横跨两栏的一行。
     *
     * @param maxNarrow 有「标准时间」标签时能放的字数
     * @param maxNoLabel 让出「标准时间」后的字数
     * @param maxWide 连「真太阳时」也让出后的字数
     */
    internal data class CityLabelPlan(
        val text: String,
        val wide: Boolean,
        val showCivilLabel: Boolean,
        val showSolarLabel: Boolean,
    )

    internal fun planCityLabel(
        names: DistrictResolver.DistrictNames?,
        fallback: String,
        maxNarrow: Int,
        maxNoLabel: Int,
        maxWide: Int,
    ): CityLabelPlan {
        if (names == null) return CityLabelPlan(fallback, wide = false, showCivilLabel = true, showSolarLabel = true)
        val full = names.full
        return when {
            full.length <= maxNarrow -> CityLabelPlan(full, false, true, true)
            full.length <= maxNoLabel -> CityLabelPlan(full, false, false, true)
            // 跨栏后仍然放不下就用区县名，交给 TextView 的省略号兜底。
            full.length <= maxWide -> CityLabelPlan(full, true, false, false)
            else -> CityLabelPlan(names.short, true, false, false)
        }
    }

    /** 当前真太阳时若落在某段关键时间里，就取那一段的配色；否则返回 null（用默认金色）。 */
    internal fun activeKeyColor(schedule: TakeTimeSchedule?, solarSecondsOfDay: Double): Int? {
        if (schedule == null) return null
        val minuteOfDay = solarSecondsOfDay / 60.0
        val inside = schedule.bands.any { it.contains(minuteOfDay) }
        return if (inside) KeyTimePalette.of(schedule.temperature) else null
    }

    private fun applySolarColor(color: Int, views: RemoteViews) {
        views.setTextColor(R.id.widget_solar_time, color)
        views.setTextColor(R.id.widget_solar_colon, color)
        views.setTextColor(R.id.widget_solar_sec, color)
    }

    /** 各区域的点击目标：日期→日历，标准时间→闹钟，天气行→天气，真太阳时→本 App。 */
    private fun bindClicks(context: Context, place: Place, views: RemoteViews) {
        val appPending = activityIntent(context, REQUEST_APP, openApp(context))
        views.setOnClickPendingIntent(R.id.widget_root, appPending)
        views.setOnClickPendingIntent(R.id.widget_solar_column, appPending)
        views.setOnClickPendingIntent(
            R.id.widget_civil_column,
            activityIntent(context, REQUEST_ALARM, alarmIntent(context)),
        )
        // 日期单独指向日历；解析不到日历应用时不挂，点击会冒泡到左栏（闹钟）。
        WidgetIntents.calendar(context)?.let {
            views.setOnClickPendingIntent(R.id.widget_civil_date, activityIntent(context, REQUEST_CALENDAR, it))
        }
        weatherPendingIntent(context, place)?.let {
            views.setOnClickPendingIntent(R.id.widget_hour_row, it)
        }
    }

    private fun activityIntent(context: Context, requestCode: Int, intent: Intent): PendingIntent =
        PendingIntent.getActivity(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    /** 天气应用的解析结果缓存在进程内，避免每次刷新都查一遍 PackageManager。 */
    private var weatherTarget: Intent? = null
    private var weatherResolvedAt = 0L
    private var alarmTarget: Intent? = null
    private var alarmResolvedAt = 0L

    private fun weatherPendingIntent(context: Context, place: Place): PendingIntent? {
        val now = System.currentTimeMillis()
        if (now - weatherResolvedAt > RESOLVE_TTL_MILLIS) {
            weatherTarget = WidgetIntents.weather(context, place.latitude, place.longitude)
            weatherResolvedAt = now
        }
        val intent = weatherTarget ?: return null
        return activityIntent(context, REQUEST_WEATHER, intent)
    }

    /** 设备上没有闹钟应用时退回本 App，避免点击无反应。 */
    private fun alarmIntent(context: Context): Intent {
        val now = System.currentTimeMillis()
        if (now - alarmResolvedAt > RESOLVE_TTL_MILLIS) {
            alarmTarget = WidgetIntents.alarm(context)
            alarmResolvedAt = now
        }
        return alarmTarget ?: openApp(context)
    }

    /** 临时诊断：记录三个区域解析到的目标。 */
    /** 底部小时预报：从当前时刻起每格 1 小时，显示时刻、天气图标与天气名称；没有数据或高度不够时整行隐藏。 */
    private fun bindHourly(
        context: Context,
        now: Instant,
        zone: ZoneId,
        show: Boolean,
        views: RemoteViews,
    ) {
        val hourly = WeatherRepository.hourly(context).associateBy { it.epochSeconds }
        views.setViewVisibility(R.id.widget_hour_row, if (show && hourly.isNotEmpty()) View.VISIBLE else View.GONE)
        if (!show || hourly.isEmpty()) return

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
     * 按栏宽换算主时间字号：桌面回报的宽度与实际一致，取「栏宽 － 秒数 － 冒号 － 间隙」，
     * 除以实测的「文本宽/字号」比例得到字号，既填满栏宽又不会被裁切。
     *
     * 高度只用于选择布局（桌面回报的高度并不可靠），不参与字号计算，
     * 免得把字缩得过小、留下大片空白。
     */
    private fun applyClockSizing(context: Context, widthDp: Int, date: String, compact: Boolean, views: RemoteViews) {
        val metrics = context.resources.displayMetrics
        val density = metrics.density
        val totalWidthPx = (if (widthDp > 0) widthDp.toFloat() else DEFAULT_WIDGET_WIDTH_DP) * density
        val chromeDp = if (compact) COMPACT_COLUMN_CHROME_DP else COLUMN_CHROME_DP
        val columnWidthPx = (totalWidthPx - chromeDp * density) / 2f

        // 秒数用等宽字体，与 style 里的 WidgetClockSecondChrono 保持一致：
        // 等宽下「0:」与「00」同宽，于是按「00」的宽度裁剪就恰好切在冒号之后。
        val secondsPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            typeface = Typeface.MONOSPACE
            textSize = spToPx(SECOND_TEXT_SP, metrics)
        }
        val secondsBlockPx = secondsPaint.measureText(SECOND_SAMPLE)
        val paint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            typeface = Typeface.create("sans-serif-light", Typeface.NORMAL)
            fontFeatureSettings = "tnum"
            textSize = spToPx(SECOND_TEXT_SP, metrics)
        }
        val colonPx = paint.measureText(":")
        val availablePx = columnWidthPx - secondsBlockPx - colonPx - TEXT_GAP_DP * density
        // 秒数字号也由这里按 px 下发，不用布局里的 sp：sp 会由宿主按它自己的
        // 字体缩放解析，一旦与本进程的度量不一致，裁剪点就会偏，把「0:SS」的冒号露出来。
        views.setTextViewTextSize(R.id.widget_solar_sec, TypedValue.COMPLEX_UNIT_PX, secondsPaint.textSize)
        // Chronometer 的文本是「M:SS」，把宽度限成两位数字再配合右对齐，只露出秒数。
        views.setInt(
            R.id.widget_solar_sec,
            "setMaxWidth",
            (secondsBlockPx + SECOND_WIDTH_SLACK_DP * density).toInt(),
        )

        paint.textSize = spToPx(MAX_MAIN_TEXT_SP, metrics)
        val widthRatio = paint.measureText(MAIN_TEXT_SAMPLE) / paint.textSize
        val mainPx = fitTextSizePx(
            availableWidthPx = availablePx,
            widthRatio = widthRatio,
            minPx = spToPx(MIN_MAIN_TEXT_SP, metrics),
            maxPx = paint.textSize,
        )
        views.setTextViewTextSize(R.id.widget_civil_time, TypedValue.COMPLEX_UNIT_PX, mainPx)
        views.setTextViewTextSize(R.id.widget_solar_time, TypedValue.COMPLEX_UNIT_PX, mainPx)

        // 日期行（含最高/最低气温）同样按宽度收缩，免得窄尺寸时被截成半截。
        val datePx = spToPx(DATE_TEXT_SP, metrics)
        paint.textSize = datePx
        val dateRatio = paint.measureText(date) / datePx
        views.setTextViewTextSize(
            R.id.widget_civil_date,
            TypedValue.COMPLEX_UNIT_PX,
            fitTextSizePx(
                availableWidthPx = columnWidthPx,
                widthRatio = dateRatio,
                minPx = spToPx(MIN_DATE_TEXT_SP, metrics),
                maxPx = datePx,
            ),
        )
    }

    /** 文本宽度约等于 widthRatio × 字号，按可用宽度反推字号并夹在上下限内。 */
    private fun fitTextSizePx(
        availableWidthPx: Float,
        widthRatio: Float,
        minPx: Float,
        maxPx: Float,
    ): Float {
        if (availableWidthPx <= 0f || widthRatio <= 0f) return minPx
        return (availableWidthPx / widthRatio).coerceIn(minPx, maxPx)
    }

    private fun spToPx(sp: Float, metrics: DisplayMetrics): Float =
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_SP, sp, metrics)

    /**
     * 安排下一次刷新：写入时刻取「整分」与「真太阳时整分」里较早的那个（平均每 30 秒一次）。
     *
     * 闹钟提前 [TICK_LEAD_EXACT_MILLIS]/[TICK_LEAD_INEXACT_MILLIS] 醒来，由 [refreshAtTick]
     * 等到真正的边界才写入。这样即使闹钟本身迟到，分钟也不会比秒数慢半拍。
     */
    fun scheduleNextTick(context: Context, place: Place = resolveLocation(context).place) {
        val manager = context.getSystemService(AlarmManager::class.java) ?: return
        val nowMillis = System.currentTimeMillis()
        val now = Instant.ofEpochMilli(nowMillis)
        val at = nowMillis + nextTickDelayMillis(
            nowMillis = nowMillis,
            civilOffsetMillis = civilOffsetMillis(now, civilZoneOf(place)),
            solarOffsetMillis = solarOffsetMillis(now, place),
        )
        val pendingIntent = tickIntent(context, at)
        val exact = Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && canScheduleExact(manager)
        val lead = if (exact) TICK_LEAD_EXACT_MILLIS else TICK_LEAD_INEXACT_MILLIS
        val fireAt = maxOf(at - lead, nowMillis + TICK_MARGIN_MILLIS)
        // RTC：熄屏时不唤醒 CPU。Doze 下 setExact 会被推迟到维护窗口（可能十几分钟），
        // 因此优先用 *AndAllowWhileIdle，保证每分钟的刷新仍能落地。
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            manager.set(AlarmManager.RTC, fireAt, pendingIntent)
        } else if (exact) {
            manager.setExactAndAllowWhileIdle(AlarmManager.RTC, fireAt, pendingIntent)
        } else {
            manager.setAndAllowWhileIdle(AlarmManager.RTC, fireAt, pendingIntent)
        }
    }

    /**
     * 距离下一次写入还有多少毫秒：两个时钟的分钟边界相差 0~59 秒，各自的边界都要刷新一次，
     * 因此取较早的那个边界再押后 [TICK_MARGIN_MILLIS]。
     */
    internal fun nextTickDelayMillis(
        nowMillis: Long,
        civilOffsetMillis: Long,
        solarOffsetMillis: Long,
    ): Long = minOf(
        millisToNextMinute(nowMillis, civilOffsetMillis),
        millisToNextMinute(nowMillis, solarOffsetMillis),
    ) + TICK_MARGIN_MILLIS

    /** 显示时刻距离下一个整分还有多少毫秒（正好落在边界上时返回 0）。 */
    private fun millisToNextMinute(nowMillis: Long, offsetMillis: Long): Long {
        val intoMinute = Math.floorMod(nowMillis + offsetMillis, MINUTE_MILLIS)
        return if (intoMinute == 0L) 0L else MINUTE_MILLIS - intoMinute
    }

    /**
     * 处理刷新闹钟：闹钟可能比边界早醒，等到 [atMillis] 这个真正的整分边界再刷新，
     * 使真太阳时的分钟与秒数在同一刻变化。等待期间用接收方的 goAsync 保住广播。
     */
    fun refreshAtTick(context: Context, atMillis: Long, onDone: () -> Unit) {
        val appContext = context.applicationContext
        val delay = (atMillis - System.currentTimeMillis()).coerceIn(0L, TICK_MAX_LEAD_MILLIS)
        if (delay <= 0L) {
            runCatching { refreshAll(appContext) }
            onDone()
            return
        }
        Handler(Looper.getMainLooper()).postDelayed(
            {
                runCatching { refreshAll(appContext) }
                onDone()
            },
            delay,
        )
    }

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

    /**
     * 桌面是否把「应用内直接添加」做成了半成品。
     *
     * 小米/红米（HyperOS、MIUI）上 `requestPinAppWidget` 会返回 true，但桌面的
     * AddItemActivity 只是闪一下就退，并不真的添加；华为桌面则只提示「当前窗口已满」。
     * 这两类系统上，提示语要引导用户走「长按桌面 → 小组件」的手动路径。
     */
    internal fun pinNeedsManualFallback(manufacturer: String?, brand: String?): Boolean {
        val names = listOfNotNull(manufacturer, brand).map { it.trim().lowercase() }
        return names.any { it in PIN_FALLBACK_VENDORS }
    }

    private val PIN_FALLBACK_VENDORS = setOf("xiaomi", "redmi", "poco", "huawei", "honor")

    /** 请求把小组件固定到桌面；返回请求是否已发出。 */
    fun requestPin(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        val manager = context.getSystemService(AppWidgetManager::class.java) ?: return false
        if (!manager.isRequestPinAppWidgetSupported) return false
        val provider = ComponentName(context, SolarWidgetProvider::class.java)
        // 部分启动器（如华为桌面）不会回调成功事件，是否真的加上去由调用方比对实例数判断。
        return runCatching { manager.requestPinAppWidget(provider, null, null) }.getOrDefault(false)
    }

    /** 当前已固定到桌面的实例数，供「添加到桌面」判断是否成功。 */
    fun pinnedCount(context: Context): Int = runCatching {
        val manager = context.getSystemService(AppWidgetManager::class.java) ?: return 0
        manager.getAppWidgetIds(ComponentName(context, SolarWidgetProvider::class.java)).size
    }.getOrDefault(0)

    private fun tickIntent(context: Context, atMillis: Long = 0L): PendingIntent {
        val intent = Intent(context, SolarWidgetProvider::class.java)
            .setAction(ACTION_TICK)
            .putExtra(EXTRA_TICK_AT, atMillis)
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

    /**
     * 手工指定过坐标时，App 与小组件一律按它显示，连系统最近一次定位都不看；
     * 其余情况跟随 GPS（与 App 内判定一致）。
     */
    internal fun followsSystemFix(source: PlaceSource): Boolean = source != PlaceSource.MANUAL

    private fun resolveLocation(context: Context): LocationState {
        val saved = AppSettings(context).place
        if (!followsSystemFix(saved.source)) return LocationState(saved, hasFix = true)

        val fix = LocationTracker(context).lastKnownLocation()
        if (fix != null) {
            val place = Place(fix.latitude, fix.longitude, PlaceSource.GPS, context.getString(R.string.gps_label))
            return LocationState(place, hasFix = true)
        }
        // 没有实时定位时，只有「历史上确实拿到过 GPS 定位」才继续用它；默认坐标不算有效定位。
        val hasFix = hasValidFix(
            followingGps = true,
            hadFix = saved.source == PlaceSource.GPS,
            fixNow = false,
        )
        return LocationState(saved, hasFix)
    }

    private fun openApp(context: Context): Intent =
        Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }

    /** 日期行；还没有有效定位时不带气温（那份气温属于别的城市）。 */
    private fun dateText(context: Context, civil: ZonedDateTime, place: Place, hasFix: Boolean): String {
        val date = TimeText.dateShortWithWeekday(context, civil.toLocalDate())
        if (!hasFix) return date
        val range = WeatherRepository.temperatureRange(
            WeatherRepository.hourly(context),
            civil.toLocalDate(),
            civil.zone,
        ) ?: return date
        return context.getString(R.string.date_high_low, date, range.second, range.first)
    }
}
