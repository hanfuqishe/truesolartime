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
    private const val REQUEST_TICK = 7301
    private const val REQUEST_APP = 7302
    private const val REQUEST_ALARM = 7303
    private const val REQUEST_WEATHER = 7304
    private const val MINUTE_MILLIS = 60_000L
    private const val TICK_MARGIN_MILLIS = 150L

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
    private const val MAIN_TEXT_SAMPLE = "00:00"
    private const val SECOND_SAMPLE = "00"
    private const val MAX_MAIN_TEXT_SP = 48f
    private const val MIN_MAIN_TEXT_SP = 20f
    private const val SECOND_TEXT_SP = 23f
    private const val DATE_TEXT_SP = 11f
    private const val MIN_DATE_TEXT_SP = 8f


    fun refreshAll(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        val ids = manager.getAppWidgetIds(ComponentName(context, SolarWidgetProvider::class.java))
        if (ids.isEmpty()) {
            cancelTick(context)
            return
        }
        val place = resolvePlace(context)
        // 各机型/桌面给到的尺寸不同：按可用宽度与折算后的高度换算字号，2 行高时压缩留白。
        ids.forEach { id ->
            val options = manager.getAppWidgetOptions(id)
            val widthDp = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH)
            val heightDp = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT)
            manager.updateAppWidget(id, buildViews(context, place, widthDp, heightDp))
        }
        scheduleNextTick(context, place)
        // 区县名与天气都要联网，命中缓存时不会重复请求；失败则用离线城市表／旧天气。
        DistrictResolver.requestRefresh(context, place)
        WeatherRepository.requestRefresh(context, place)
    }

    fun buildViews(
        context: Context,
        place: Place = resolvePlace(context),
        widthDp: Int = 0,
        heightDp: Int = 0,
    ): RemoteViews {
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
        val date = dateText(context, civil, place)
        // 桌面回报的高度比实际单元格小，先折算成近似可用高度。
        val effectiveHeightDp = if (heightDp > 0) heightDp * HEIGHT_SCALE else 0f
        // 折算后放不下常规布局的内容（如默认 5x2）时，改用只压缩留白的紧凑间距布局。
        val compact = effectiveHeightDp > 0f && effectiveHeightDp < REGULAR_MIN_CONTENT_DP
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
            setString(R.id.widget_civil_time, "setTimeZone", zone.id)
            setString(R.id.widget_civil_sec, "setTimeZone", zone.id)
            setTextViewText(R.id.widget_civil_date, date)
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
            bindHourly(context, now, zone, showHourly, this)
            bindClicks(context, place, this)
        }
    }

    /** 三个区域各自的点击目标：标准时间→闹钟，天气行→天气，真太阳时→本 App。 */
    private fun bindClicks(context: Context, place: Place, views: RemoteViews) {
        val appPending = activityIntent(context, REQUEST_APP, openApp(context))
        views.setOnClickPendingIntent(R.id.widget_root, appPending)
        views.setOnClickPendingIntent(R.id.widget_solar_column, appPending)
        views.setOnClickPendingIntent(
            R.id.widget_civil_column,
            activityIntent(context, REQUEST_ALARM, alarmIntent(context)),
        )
        weatherPendingIntent(context, place)?.let {
            views.setOnClickPendingIntent(R.id.widget_hour_row, it)
        }
        logClicks(context, place)
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
    private fun logClicks(context: Context, place: Place) {
        val alarm = WidgetIntents.alarm(context)?.let { "${it.action}/${it.component?.flattenToShortString()}" }
        val weather = WidgetIntents.weather(context, place.latitude, place.longitude)
            ?.let { "${it.action}/${it.component?.flattenToShortString()}/${it.data}" }
        android.util.Log.i("WidgetClicks", "alarm=$alarm weather=$weather")
    }

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

        val paint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            typeface = Typeface.create("sans-serif-light", Typeface.NORMAL)
            fontFeatureSettings = "tnum"
            textSize = spToPx(SECOND_TEXT_SP, metrics)
        }
        val secondsBlockPx = paint.measureText(SECOND_SAMPLE)
        val colonPx = paint.measureText(":")
        val availablePx = columnWidthPx - secondsBlockPx - colonPx - TEXT_GAP_DP * density

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
     * 对齐到下一次「整分」或「真太阳时整分」，取更早的那个再多留 0.15 秒。
     *
     * 标准时间由 TextClock 自行走时，这里只负责刷新真太阳时的分钟、日期、时辰与天气；
     * 两个时钟的分钟边界相差 0~59 秒，两者各自的边界都要刷新一次（约每 30 秒一次）。
     */
    fun scheduleNextTick(context: Context, place: Place = resolvePlace(context)) {
        val manager = context.getSystemService(AlarmManager::class.java) ?: return
        val nowMillis = System.currentTimeMillis()
        val now = Instant.ofEpochMilli(nowMillis)
        val toCivil = millisToNextMinute(nowMillis, civilOffsetMillis(now, civilZoneOf(place)))
        val toSolar = millisToNextMinute(nowMillis, solarOffsetMillis(now, place))
        val next = nowMillis + minOf(toCivil, toSolar) + TICK_MARGIN_MILLIS
        val pendingIntent = tickIntent(context)
        // RTC：熄屏时不唤醒 CPU。Doze 下 setExact 会被推迟到维护窗口（可能十几分钟），
        // 因此优先用 *AndAllowWhileIdle，保证每分钟的刷新仍能落地。
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            manager.set(AlarmManager.RTC, next, pendingIntent)
        } else if (canScheduleExact(manager)) {
            manager.setExactAndAllowWhileIdle(AlarmManager.RTC, next, pendingIntent)
        } else {
            manager.setAndAllowWhileIdle(AlarmManager.RTC, next, pendingIntent)
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

    private fun openApp(context: Context): Intent =
        Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
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
