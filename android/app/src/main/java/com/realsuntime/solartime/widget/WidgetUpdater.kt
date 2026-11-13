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
import android.os.PowerManager
import android.os.SystemClock
import android.text.TextPaint
import android.util.DisplayMetrics
import android.util.Log
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

    private const val TAG = "SolarWidget"

    /** 兜底刷新：正常每分钟的 [ACTION_TICK] 万一被系统丢掉，靠它把链条接回来。 */
    const val ACTION_WATCHDOG = "com.realsuntime.solartime.action.WIDGET_WATCHDOG"
    private const val REQUEST_TICK = 7301
    private const val REQUEST_WATCHDOG = 7306
    private const val REQUEST_APP = 7302
    private const val REQUEST_ALARM = 7303
    private const val REQUEST_WEATHER = 7304
    private const val REQUEST_CALENDAR = 7305
    private const val MINUTE_MILLIS = 60_000L

    /** 写入落在这个整分边界之后多少毫秒：小到肉眼看来就是「秒数跳到 00 的同一刻」。 */
    internal const val TICK_MARGIN_MILLIS = 30L

    /** 兜底刷新的间隔：链条断了最多这么久就自己接回来。 */
    private const val WATCHDOG_INTERVAL_MILLIS = 10L * 60 * 1000

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

    /**
     * 时间轴位图的像素上限。位图随每次刷新 parcel 给系统进程，Binder 事务只有约 1 MB；
     * 高密度大屏（5 列 × ~500dpi）按真实像素画会逼近上限，桌面上就表现成「加载失败」。
     */
    private const val AXIS_MAX_WIDTH_PX = 1024
    private const val AXIS_MAX_HEIGHT_PX = 64
    private const val MAIN_TEXT_SAMPLE = "00:00"
    private const val SECOND_SAMPLE = "00"

    /** 秒数宽度的余量：等宽字体下切点本就精确，只留一点防亚像素裁边。 */
    private const val SECOND_WIDTH_SLACK_DP = 0.25f
    private const val MAX_MAIN_TEXT_SP = 48f
    private const val MIN_MAIN_TEXT_SP = 20f
    private const val SECOND_TEXT_SP = 23f
    private const val DATE_TEXT_SP = 11f
    private const val MIN_DATE_TEXT_SP = 8f
    /** 日期行右侧经纬度的字号与它和日期之间的间隙。 */
    private const val COORD_TEXT_SP = 10f
    private const val COORD_GAP_DP = 8f

    /**
     * 真太阳时的强调色，与首页大卡片一致：白天（橙底）用白字，夜间用金色。
     * 进入关键时间段时另改用 KeyTimePalette 的绿或红。
     */
    private const val SOLAR_TIME_COLOR_DAY = 0xFFFFFFFF.toInt()
    private const val SOLAR_TIME_COLOR_NIGHT = 0xFFF5D68A.toInt()

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


    /**
     * 刷新所有实例。
     *
     * @param forceChronometer 强制重发秒数的基准时刻。只在「视图可能是新建的」或
     *   「时间/时区被改动」时才需要；平时重发会让秒的显示出现忽长忽短的抖动，见
     *   [shouldResetChronometer]。
     */
    fun refreshAll(context: Context, forceChronometer: Boolean = false) {
        val manager = AppWidgetManager.getInstance(context)
        val ids = manager.getAppWidgetIds(ComponentName(context, SolarWidgetProvider::class.java))
        val location = resolveLocation(context)
        val place = location.place
        // 地名与天气即使桌面上一个小组件都没有也要更新：首页也在用这两份缓存，
        // 否则定位变化后首页会一直显示启动时那个默认位置的地名。
        DistrictResolver.requestRefresh(context, place)
        WeatherRepository.requestRefresh(context, place)
        // 关键时间每天在 01:00–05:00 随机时刻同步一次，失败每小时重试，结果缓存 7 天。
        TakeTimeRepository.requestRefresh(context)
        if (ids.isEmpty()) {
            cancelTick(context)
            return
        }
        // 先排下一分钟再刷新：刷新途中出任何异常（或者进程被系统冻结）都不会把链条断掉。
        scheduleNextTick(context, place)
        val fallbackSeconds = solarSecondOf(
            Math.floorMod(
                System.currentTimeMillis() + solarOffsetMillis(Instant.now(), place),
                DAY_MILLIS,
            ),
        )
        // 各机型/桌面给到的尺寸不同：按可用宽度与折算后的高度换算字号，2 行高时压缩留白。
        // 单个实例出错（尺寸异常、缓存里是坏 JSON、位图分配失败……）不能连累其它实例，
        // 否则桌面会整块显示「加载失败」——这里逐个兜住，失败就退成只显示时刻的最小版面。
        ids.forEach { id ->
            val updates = runCatching {
                val options = manager.getAppWidgetOptions(id)
                val widthDp = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH)
                val heightDp = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT)
                buildViews(context, location, widthDp, heightDp, id, forceChronometer)
            }.onFailure {
                Log.w(TAG, "buildViews($id) failed, falling back to minimal", it)
            }.getOrNull() ?: minimalViews(context, fallbackSeconds)
            runCatching { manager.updateAppWidget(id, updates) }.onFailure { error ->
                // 系统可能直接拒收这棵 RemoteViews（例如 Android 17 的位图内存上限），
                // 那种情况下退成最小版面至少能让用户看到时间，而不是「加载失败」。
                Log.w(TAG, "updateAppWidget($id) rejected, retrying with minimal", error)
                runCatching { manager.updateAppWidget(id, minimalViews(context, fallbackSeconds)) }
                    .onFailure { Log.e(TAG, "minimal update($id) also failed", it) }
            }
        }
        // 关键时间可能刚更新，重排「进入关键时间」报时（关闭时这里是空操作）。
        KeyTimeChime.schedule(context)
    }

    /** 刷新失败时的兜底版面：只显示真太阳时的「时:分」，不含位图与 Chronometer。 */
    private fun minimalViews(context: Context, solarSeconds: Long): RemoteViews =
        RemoteViews(context.packageName, R.layout.widget_solar_time_minimal).apply {
            setTextViewText(R.id.widget_minimal_time, clockText(solarSeconds))
        }

    fun buildViews(
        context: Context,
        location: LocationState = resolveLocation(context),
        widthDp: Int = 0,
        heightDp: Int = 0,
        widgetId: Int = 0,
        forceChronometer: Boolean = false,
    ): RemoteViews {
        val place = location.place
        val now = Instant.now()
        val zone = civilZoneOf(place)
        val civil = now.atZone(zone)
        val solarOffset = solarOffsetMillis(now, place)
        val trueSolarSeconds = SolarTimeMath.trueSolarSecondsOfDay(now, place.longitude)
        val shichenIndex = Shichen.indexOf(trueSolarSeconds)
        val isDay = SolarTimeMath.solarAltitudeDegrees(now, place.latitude, place.longitude) > -0.833
        // 真太阳时的秒由 Chronometer 自走，这里只负责写入「时:分」与它的基准时刻。
        // 两个细节必须一起处理，否则秒会与「时:分」、也与标准时间错位：
        // 1) 取样必须一次完成 —— now 与 elapsedRealtime 若分两次读，中间隔着的
        //    buildViews 耗时（字体测量、时间轴位图）会让基准整体偏移几十毫秒；
        // 2) 口径必须与 Chronometer 的**显示值**一致 —— 它每秒在整秒边界更新一次，
        //    两次更新之间显示的是上一次的值，也就是 floor；这里跟着用 floor，
        //    「时:分」与秒才不会在整分前后差一拍。基准只在必要时下发，见
        //    shouldResetChronometer。
        val wallNowMillis = System.currentTimeMillis()
        val elapsedNowMillis = SystemClock.elapsedRealtime()
        val solarDayMillis = Math.floorMod(wallNowMillis + solarOffset, DAY_MILLIS)
        val solarSeconds = solarSecondOf(solarDayMillis)
        val date = dateText(context, civil, place, location.hasFix)
        // 桌面回报的高度比实际单元格小，先折算成近似可用高度。
        val effectiveHeightDp = if (heightDp > 0) heightDp * HEIGHT_SCALE else 0f
        // 折算后放不下常规布局的内容（如默认 5x2）时，改用只压缩留白的紧凑间距布局。
        val compact = effectiveHeightDp > 0f && effectiveHeightDp < REGULAR_MIN_CONTENT_DP
        // 关键时间只在刷新时读一次：时间轴着色与真太阳时的数字都要用。
        val keyTime = TakeTimeRepository.schedule(context)
        val solarSecondsOfDay = solarSeconds.toDouble()
        val keyColor = if (location.hasFix) activeKeyColor(keyTime, solarSecondsOfDay, isDay) else null
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
            applyClockSizing(context, widthDp, date, TimeText.coordinates(context, place.latitude, place.longitude), compact, this)
            bindAxis(context, widthDp, compact, now, location.hasFix, solarOffset, keyTime, isDay, this)
            setString(R.id.widget_civil_time, "setTimeZone", zone.id)
            setString(R.id.widget_civil_sec, "setTimeZone", zone.id)
            setTextViewText(R.id.widget_civil_date, date)
            val city = cityLabel(context, place, widthDp, compact)
            // 地名放不下时才用「整行」：那一行里地名在左、时辰在右，右边那一栏的时辰就不必再显示。
            val wideName = location.hasFix && city.wide
            setTextViewText(R.id.widget_city, if (location.hasFix && !city.wide) city.text else "")
            setTextViewText(R.id.widget_city_wide, if (wideName) city.text else "")
            setViewVisibility(R.id.widget_city, if (location.hasFix && !city.wide) View.VISIBLE else View.GONE)
            setViewVisibility(R.id.widget_wide_row, if (wideName) View.VISIBLE else View.GONE)
            setViewVisibility(R.id.widget_solar_shichen, if (wideName) View.GONE else View.VISIBLE)
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
                // base 取「当前真太阳时整分的时刻」，且与上面同一套取样：
                // Chronometer 每秒按 base 重算到下一整秒的延时，永远落在整秒边界上。
                // 但只在必要时下发：Chronometer 内部用 Math.round 换算秒数，若在某一秒的
                // 后半段重发 base，它会把下一秒提前显示出来，那一秒就只有 0.6 秒、下一秒
                // 却占 1.4 秒 —— 看上去就是「秒忽大忽小」。
                val minuteStartElapsed = elapsedNowMillis - Math.floorMod(solarDayMillis, MINUTE_MILLIS)
                val layoutChanged = lastChronometerLayout[widgetId] != layout
                val reset = layoutChanged ||
                    shouldResetChronometer(minuteStartElapsed, lastChronometerBase[widgetId], forceChronometer)
                if (reset) {
                    lastChronometerBase[widgetId] = minuteStartElapsed
                    lastChronometerLayout[widgetId] = layout
                    setChronometer(R.id.widget_solar_sec, minuteStartElapsed, null, true)
                }
                setViewVisibility(R.id.widget_solar_colon, View.VISIBLE)
                setViewVisibility(R.id.widget_solar_sec, View.VISIBLE)
                // 处在关键时间段里时，时:分、冒号与秒一起换成关键时间的配色。
                applySolarColor(keyColor ?: defaultSolarColor(isDay), this)
                setTextViewText(R.id.widget_solar_shichen, shichenText(context, solarSecondsOfDay))
                setTextViewText(
                    R.id.widget_city_wide_shichen,
                    shichenText(context, solarSecondsOfDay),
                )
                setTextViewText(
                    R.id.widget_coordinates,
                    TimeText.coordinates(context, place.latitude, place.longitude),
                )
            } else {
                // 跟随 GPS 但还没有有效定位：真太阳时无从计算，显示占位而不是拿旧位置冒充。
                setTextViewText(R.id.widget_solar_time, SOLAR_PLACEHOLDER)
                setViewVisibility(R.id.widget_solar_colon, View.GONE)
                setViewVisibility(R.id.widget_solar_sec, View.GONE)
                applySolarColor(defaultSolarColor(isDay), this)
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
        isDay: Boolean,
        views: RemoteViews,
    ) {
        val density = context.resources.displayMetrics.density
        val totalWidthDp = if (widthDp > 0) widthDp.toFloat() else DEFAULT_WIDGET_WIDTH_DP
        val paddingDp = if (compact) COMPACT_AXIS_PADDING_DP else AXIS_PADDING_DP
        val widthPx = (((totalWidthDp - paddingDp * 2f) * density).toInt())
            // 整张位图要 parcel 给系统进程，Binder 事务上限约 1 MB：高密度大屏上
            // 「可用宽度 × 13dp」能到好几百 KB（小米 18 Pro 这类 ~500dpi、5 列的机器
            // 甚至接近上限），超了桌面会直接判小组件「加载失败」。轴只有十几 dp 高、
            // 内容是一条线和几段纯色，图片用 fitXY 拉伸，限到 1024px 宽肉眼无差别。
            .coerceIn(1, AXIS_MAX_WIDTH_PX)
        val heightDp = if (compact) COMPACT_AXIS_HEIGHT_DP else AXIS_HEIGHT_DP
        val heightPx = (heightDp * density).toInt().coerceIn(1, AXIS_MAX_HEIGHT_PX)
        val solarSeconds = if (hasFix) {
            Math.floorMod(now.toEpochMilli() + solarOffsetMillis, 86_400_000L) / 1000L
        } else {
            null
        }
        // 关键时间本身就按真太阳时算，和轴上的点同一套刻度，不用再换算。
        // 色带与圆点跟着昼夜换档：白天暗一档、夜间亮一档；时段外圆点是白色。
        val bandColor = KeyTimePalette.of(schedule?.temperature, isDay) ?: 0
        val bitmap = WidgetAxis.render(
            context = context,
            widthPx = widthPx,
            heightPx = heightPx,
            solarSecondsOfDay = solarSeconds,
            bands = schedule?.bands.orEmpty(),
            bandColor = bandColor,
            dotColor = if (solarSeconds != null && bandColor != 0 && insideKeyTime(schedule, solarSeconds)) {
                bandColor
            } else {
                0xFFFFFFFF.toInt()
            },
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

    /** 当前真太阳时若落在某段关键时间里，就取那一段的配色；否则返回 null（用默认色）。 */
    internal fun activeKeyColor(
        schedule: TakeTimeSchedule?,
        solarSecondsOfDay: Double,
        isDay: Boolean,
    ): Int? {
        if (schedule == null) return null
        val minuteOfDay = solarSecondsOfDay / 60.0
        val inside = schedule.bands.any { it.contains(minuteOfDay) }
        return if (inside) KeyTimePalette.of(schedule.temperature, isDay) else null
    }

    /** 时辰 + 时初／时正，与首页大卡片一致（如「午时 · 初」）。 */
    private fun shichenText(context: Context, solarSecondsOfDay: Double): String {
        val name = TimeText.shichenName(context, Shichen.indexOf(solarSecondsOfDay))
        val half = TimeText.shichenHalf(context, Shichen.halfLabel(solarSecondsOfDay) == "正")
        return context.getString(R.string.hero_shichen, name, half)
    }

    /** 真太阳时的默认色：白天白字、夜间金色，与首页大卡片一致。 */
    private fun defaultSolarColor(isDay: Boolean): Int =
        if (isDay) SOLAR_TIME_COLOR_DAY else SOLAR_TIME_COLOR_NIGHT

    /** 当前真太阳时是否落在某段关键时间里（时间轴圆点用同一判定）。 */
    private fun insideKeyTime(schedule: TakeTimeSchedule?, solarSecondsOfDay: Long): Boolean {
        if (schedule == null) return false
        val minuteOfDay = solarSecondsOfDay / 60.0
        return schedule.bands.any { it.contains(minuteOfDay) }
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

    /**
     * 一天的毫秒数。
     */
    private const val DAY_MILLIS = 86_400_000L

    /**
     * 每个实例上次下发的 Chronometer base（elapsedRealtime 时基）与当时的布局。
     *
     * 同一个基准下 Chronometer 会自己走时；重复下发只会带来取整误差，所以只记下来避免重复。
     * 布局换了意味着宿主会重新 inflate、基准随之丢失，这时必须补发。
     */
    private val lastChronometerBase = HashMap<Int, Long>()
    private val lastChronometerLayout = HashMap<Int, Int>()

    /**
     * 相位容差：基准之间的差落在整分的这一范围内，就认为相位没变、不必重发。
     *
     * 同一分钟内反复取样只差几毫秒；跨分只差一个整分（60000），两者都在容差内。
     */
    private const val CHRONOMETER_TOLERANCE_MILLIS = 100L

    /**
     * 是否需要重发 Chronometer 的 base。
     *
     * `Chronometer` 的 `updateText` 是 `Math.round((now - base) / 1000f)`，而它自己的走时
     * 回调永远落在「base + 整秒 + 1ms」上。也就是说：基准正确时显示值恰好在整秒边界
     * 翻页，但**额外的**一次 `setBase` 会把「已过整秒半秒以上」的当前时刻四舍五入成
     * 下一秒——那一秒只显示了零点几秒，下一秒却占了整整一秒多，看上去就是秒忽大忽小。
     *
     * 基准本身是绝对的（elapsedRealtime 单调），一旦对齐就不会再漂，所以只有相位真的
     * 变了才需要重发：换了位置导致偏移变化、进程重启、视图重建。
     *
     * @param desired 这次算出的基准
     * @param last 上次下发的基准（没有则为 null）
     * @param force 视图可能是新建的（首次添加、重建、改时间）时强制下发
     */
    internal fun shouldResetChronometer(desired: Long, last: Long?, force: Boolean): Boolean {
        if (force || last == null) return true
        val diff = Math.floorMod(desired - last, MINUTE_MILLIS)
        return Math.min(diff, MINUTE_MILLIS - diff) > CHRONOMETER_TOLERANCE_MILLIS
    }

    /**
     * 真太阳时当天的第几秒，**向下取整**。
     *
     * `Chronometer` 在整秒边界翻页，两次翻页之间保持上一次的值，等价于向下取整；
     * 「时:分」跟着用同一口径，才不会在整分前后和秒差一拍。
     */
    internal fun solarSecondOf(solarDayMillis: Long): Long =
        solarDayMillis / 1000 % (DAY_MILLIS / 1000)

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
    private fun applyClockSizing(
        context: Context,
        widthDp: Int,
        date: String,
        coordinates: String,
        compact: Boolean,
        views: RemoteViews,
    ) {
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

        // 日期与经纬度同一行：日期占满剩余宽度，同样按可用宽度收缩，免得窄尺寸时被截成半截。
        val coordPx = spToPx(COORD_TEXT_SP, metrics)
        paint.textSize = coordPx
        val coordsWidthPx = if (coordinates.isEmpty()) 0f else paint.measureText(coordinates) + COORD_GAP_DP * density
        val dateAvailablePx = totalWidthPx - chromeDp * density - coordsWidthPx
        val datePx = spToPx(DATE_TEXT_SP, metrics)
        paint.textSize = datePx
        val dateRatio = paint.measureText(date) / datePx
        views.setTextViewTextSize(
            R.id.widget_civil_date,
            TypedValue.COMPLEX_UNIT_PX,
            fitTextSizePx(
                availableWidthPx = dateAvailablePx,
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
     * 安排下一次刷新。
     *
     * 亮屏时取「整分」与「真太阳时整分」里较早的那个（平均每 30 秒一次）；息屏时只跟真太阳时整分
     * （标准时间由布局里的 `TextClock` 自己走，不用 App 刷），把夜里的唤醒减半。
     *
     * 闹钟直接排在边界之后 [TICK_MARGIN_MILLIS] 处，一响就刷新。**不要**再「提前醒来 + `postDelayed`
     * 等到边界」：那样排下一次闹钟的动作就落进了进程里的 Handler，进程一旦被冻结/回收，
     * 这次刷新和下一次排程一起丢掉，分钟会停在旧值直到系统 30 分钟的兜底刷新。
     */
    fun scheduleNextTick(context: Context, place: Place = resolveLocation(context).place) {
        val manager = context.getSystemService(AlarmManager::class.java) ?: return
        val power = context.getSystemService(PowerManager::class.java)
        val interactive = power?.isInteractive ?: true
        val nowMillis = System.currentTimeMillis()
        val now = Instant.ofEpochMilli(nowMillis)
        val solarOffset = solarOffsetMillis(now, place)
        val fireAt = nowMillis +
            if (interactive) {
                // 亮屏时两个时钟的整分都要刷（日期、天气、时辰、色带都跟着走）。
                nextTickDelayMillis(
                    nowMillis = nowMillis,
                    civilOffsetMillis = civilOffsetMillis(now, civilZoneOf(place)),
                    solarOffsetMillis = solarOffset,
                )
            } else {
                // 息屏：只有真太阳时是 App 写的，标准时间由宿主自己的 TextClock 走时；只对
                // 真太阳时整分刷新即可，把夜里的唤醒次数从每分钟两次压到一次。
                millisToNextMinute(nowMillis, solarOffset) + TICK_MARGIN_MILLIS
            }
        val pendingIntent = tickIntent(context)
        // 必须是唤醒型、并且在会冻结/吞闹钟的 ROM 上走「闹钟」语义（见 [ChimeAlarm]）：
        // 普通闹钟在息屏后会被吞掉，分钟从此停在旧值。
        ChimeAlarm.schedule(context, fireAt, pendingIntent)
        // 每分钟都会重排一次，这里顺带把兜底闹钟刷成最新（覆盖安装后闹钟会被系统清空）。
        manager.setInexactRepeating(
            AlarmManager.RTC,
            nowMillis + WATCHDOG_INTERVAL_MILLIS,
            WATCHDOG_INTERVAL_MILLIS,
            watchdogIntent(context),
        )
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
        manager.cancel(watchdogIntent(context))
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

    /**
     * 桌面实例被移除时清掉按实例缓存的秒数基准：实例 id 会被系统回收复用，
     * 留着旧值会让新实例以为基准已经下发过，秒数就停在 `00` 不再走。
     */
    fun forgetWidget(widgetId: Int) {
        lastChronometerBase.remove(widgetId)
        lastChronometerLayout.remove(widgetId)
    }

    private fun tickIntent(context: Context): PendingIntent {
        val intent = Intent(context, SolarWidgetProvider::class.java)
            .setAction(ACTION_TICK)
        return PendingIntent.getBroadcast(
            context,
            REQUEST_TICK,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun watchdogIntent(context: Context): PendingIntent {
        val intent = Intent(context, SolarWidgetProvider::class.java)
            .setAction(ACTION_WATCHDOG)
        return PendingIntent.getBroadcast(
            context,
            REQUEST_WATCHDOG,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

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
    /**
     * 日期 + 当日天气与温度区间，与首页大卡片同一行结构：
     * 「11月13日 周五 · 17° 小雨 · 14°~19°」。没有天气数据时退化成只剩日期。
     */
    private fun dateText(context: Context, civil: ZonedDateTime, place: Place, hasFix: Boolean): String {
        val date = TimeText.dateShortWithWeekday(context, civil.toLocalDate())
        if (!hasFix) return date
        val parts = ArrayList<String>(3)
        parts += date
        val cached = WeatherRepository.cached(context)
        if (cached != null) {
            val condition = WeatherRepository.conditionOf(cached.code)
            parts += context.getString(
                R.string.hero_weather,
                context.getString(R.string.weather_temp, cached.temperatureC),
                TimeText.conditionLabel(context, condition),
            )
        }
        val range = WeatherRepository.temperatureRange(
            WeatherRepository.hourly(context),
            civil.toLocalDate(),
            civil.zone,
        )
        if (range != null) {
            // temperatureRange 返回的是 (最高, 最低)，显示顺序按「低 ~ 高」。
            parts += context.getString(R.string.hero_temp_range, range.second, range.first)
        }
        return parts.joinToString(" · ")
    }
}
