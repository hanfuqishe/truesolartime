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
import android.provider.Settings
import android.text.TextPaint
import android.util.DisplayMetrics
import android.util.Log
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.widget.RemoteViews
import com.realsuntime.solartime.MainActivity
import com.realsuntime.solartime.R
import com.realsuntime.solartime.data.AppSettings
import com.realsuntime.solartime.data.CityIndex
import com.realsuntime.solartime.data.DiagStore
import com.realsuntime.solartime.data.DistrictResolver
import com.realsuntime.solartime.data.LocalZone
import com.realsuntime.solartime.data.LocationTracker
import com.realsuntime.solartime.data.Place
import com.realsuntime.solartime.ui.SmallRowLayout
import com.realsuntime.solartime.data.PlaceSource
import com.realsuntime.solartime.data.TakeTimeRepository
import com.realsuntime.solartime.data.TakeTimeSchedule
import com.realsuntime.solartime.data.WeatherRepository
import com.realsuntime.solartime.ui.hourTemperatures
import com.realsuntime.solartime.ui.temperatureLabel
import com.realsuntime.solartime.ui.TimeText
import com.realsuntime.solartime.solar.Shichen
import com.realsuntime.solartime.solar.SolarTimeMath
import com.realsuntime.solartime.solar.TimeFormat
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

    /** 卡片可见时的定位节奏：每 5 分钟最多主动取一次（应用打开时由 MainViewModel 每分钟取一次）。 */
    private const val GPS_FIX_INTERVAL_MILLIS = 5L * 60 * 1000

    /**
     * 桌面回报的高度（OPTION_APPWIDGET_MIN_HEIGHT）只是**名义尺寸**：各家桌面一律按
     * 「一格 70dp」折算单元格数，而实际一格的高度差得很远。实测三组（回报值 → 实际卡片高度）：
     *
     * | 设备 | 回报 | 实际 |
     * |---|---|---|
     * | Pixel 4（手机）1 格 | 52dp  | 107dp |
     * | Pixel 4（手机）2 格 | 116dp | 223dp |
     * | 华为 MRR-W29（平板）2 格 | 132dp | 266dp |
     *
     * 三组都约等于 **2 倍**，所以按这个系数折算才是接近真实的可用高度（早先按 1.25 折算，
     * 会把一张 266dp 的卡片当成 165dp，于是错用了紧凑版面、内容显得缩成一团）。
     */
    private const val HEIGHT_SCALE = 2.0f

    /** 折算后低于这个高度就用紧凑间距布局（常规内容约 180dp）。 */
    private const val REGULAR_MIN_CONTENT_DP = 170f

    /** 折算后低于这个高度就算「一行卡片」，连日期行都紧（见 [showAxis] 处的说明）。 */
    private const val MIN_HEIGHT_WITH_HOURLY_DP = 145f

    /**
     * 卡片「够高」的门槛（折算后的 dp）：到这个高度才加**日出 / 正午 / 日落**那一行。
     *
     * 手机 2 格折算 232dp → 不加（223dp 正好放下现有内容）；平板 2 格折算 264dp → 加
     * （卡片实际 288dp，加完约 200dp，剩下的空间刚好）。
     */
    private const val TALL_CONTENT_DP = 240f

    /**
     * 再加**第二排逐时天气**（后 6 小时）所需的高度。
     *
     * 平板 2 格折算 264dp：现有内容约 200dp，第二排约 66dp，加起来 266dp，288dp 的卡片放得下
     * （实测确实放得下）；手机 2 格 232dp 就不行。
     */
    private const val TALL_WEATHER_DP = 255f

    /** 第二排逐时行的最小宽度：6 格逐时排得开就行（约 4 列）。 */
    private const val MIN_WIDTH_FOR_SECOND_HOUR_ROW_DP = 260

    /** 桌面没给出宽度时按默认 5x2 小组件的宽度（dp）估算字号。 */
    private const val DEFAULT_WIDGET_WIDTH_DP = 320f

    /** 两栏之间的分隔线（1dp）与内边距/外边距：常规版 14+14+12+1+12，紧凑版 10+10+8+1+8。 */
    private const val COLUMN_CHROME_DP = 53f
    private const val COMPACT_COLUMN_CHROME_DP = 37f

    private const val TEXT_GAP_DP = 2f

    /** 地名那一行（顶部标签行）的字号：11dp，与布局里的小字一致。 */
    private const val CITY_TEXT_DP = 11f

    /**
     * 顶部标签行里三段固定文本的估算宽度：`UTC+8`（5 个拉丁字符）、`真太阳时`（4 个汉字）、
     * 时辰（现在只显示时辰名，如「亥时」两个汉字；英文是 "Hai hour"，约 4 个字宽）。
     *
     * 时辰宽度**不再写死**：真机刷新时按本地化后的实际文案量（见 [cityLabel]），
     * 这个常量只作默认估算（中文「亥时」＝两个汉字）。去掉「初/正」后时辰短了，
     * 地名能占的宽度随之变大，档位自然往宽松的方向走。
     */
    private const val UTC_LABEL_DP = 34f
    private const val SOLAR_LABEL_DP = 4f * CITY_TEXT_DP
    private const val SHICHEN_DP = 2f * CITY_TEXT_DP

    /** 顶部标签行里相邻两段文本之间的间距（与布局里的 marginStart/End 一致）。 */
    private const val CITY_LABEL_GAP_DP = 8f

    /**
     * 档 0 左半：地区文字右端与竖线之间的间隙。
     *
     * 竖线落在整行 50% 分界上，右半的「真太阳时」从分界右侧 8dp 起排；左半的地区若贴到分界上，
     * 就会紧贴着线（实测只剩 1px）。所以地区右侧再让出 6dp —— 与布局里 `widget_city_default`
     * 的 `layout_marginEnd="6dp"`、首页 `HeroCard` 档 0 的 `padding(end = 6.dp)` 三处一致。
     */
    private const val CITY_END_INSET_DP = 6f

    /**
     * 顶部标签行的控件 id，**两套**都要一起下发（见 [build] 里的说明）：
     *
     * - 档 0 用两半结构的 `*_default` 那一套；
     * - 档 1-3 用合并单行的那一套（`widget_top_utc` / `widget_city` / …）。
     *
     * 同一个布局里 id 不能重名，所以档 0 的容器另起了一套 id；容器可见性互斥，
     * 但文本、可见性与对齐都统一按这两个数组下发，避免哪一套漏更新留下旧文字。
     */
    private val TOP_ROW_UTC_IDS = intArrayOf(R.id.widget_top_utc_default, R.id.widget_top_utc)
    private val TOP_ROW_CITY_IDS = intArrayOf(R.id.widget_city_default, R.id.widget_city)
    private val TOP_ROW_SOLAR_IDS = intArrayOf(R.id.widget_top_solar_default, R.id.widget_top_solar)
    private val TOP_ROW_SHICHEN_IDS = intArrayOf(R.id.widget_top_shichen_default, R.id.widget_top_shichen)

    /** 汉字/全角字符与拉丁字符的字宽比例（单位都是「字号」）。 */
    private const val FULL_WIDTH_EM = 1.0f
    private const val LATIN_EM = 0.55f
    private const val SPACE_EM = 0.30f

    /**
     * 一段文本大约占几个「字号」宽（1.0 = 一个汉字）。
     *
     * RemoteViews 里拿不到文本的真实测量宽度（没有 `TextMeasurer`），只能按字符估：
     * 汉字/假名等全角字符算 1 个字宽，拉丁字母数字算 0.55，空格算 0.3。
     * 首页是按实测像素分档的，这里按同一套口径近似 —— 于是「Manhattan, 纽约, New York County」
     * 这种以拉丁字母为主的长名字不会被 29 个字符误判成最窄的一档。
     */
    internal fun cityTextEm(text: String): Float {
        var em = 0f
        for (ch in text) {
            em += when {
                ch == ' ' -> SPACE_EM
                // CJK 部首扩展及以后：汉字、假名、韩文、全角标点等
                ch.code >= 0x2E80 -> FULL_WIDTH_EM
                else -> LATIN_EM
            }
        }
        return em
    }

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
    private const val SECOND_WIDTH_SLACK_DP = 2.0f
    /** 「添加到桌面」请求的记账文件与键名。 */
    private const val PIN_PREFS = "widget_pin"
    private const val KEY_PIN_BASELINE = "baseline"
    private const val KEY_PIN_STARTED = "started_at"
    private const val KEY_PIN_PENDING = "pending"
    /** 请求发出后多久才允许判定「没加上」：用户可能还在桌面的确认框上。 */
    private const val PIN_SETTLE_MIN_MILLIS = 3_000L
    private const val MAX_MAIN_TEXT_DP = 56f
    private const val MIN_MAIN_TEXT_DP = 20f
    /**
     * 显示大小被抬到出厂 dpi 之上（长辈关怀的「大号显示」）时主时钟的宽度余量。
     * 见 [clockSafetyFactor]：那种情况下桌面回报的格子 dp 与渲染密度不是同一套，留 10% 宁可略小。
     */
    private const val LARGE_DISPLAY_CLOCK_SAFETY = 0.90f
    /**
     * 格子宽度占整屏宽度的上限。桌面会在格子两侧留内缩（华为 1200px 屏上格子 1134px ≈ 95%），
     * 所以「按整屏宽封顶」还不够，再乘这个系数才是真实可用宽度。
     */
    private const val CELL_SCREEN_FRACTION = 0.95f
    /** 时间未知时的占位符（绝不写 00:00，见 [minimalViews]）。 */
    private const val PLACEHOLDER_TIME = "--:--"
    /** 除时钟行以外所有行的合计高度（dp，含时间轴与上下各 10dp 内边距），450 档实测。 */
    private const val CONTENT_FIXED_DP = 143.3f
    /** 时间轴行（13dp + 3dp 上边距）。内容放不下时最先收掉它。 */
    private const val AXIS_ROW_DP = 16f
    /** 收紧时上下内边距 10dp → 4dp 省下的高度（dp）。 */
    private const val PADDING_SAVE_DP = 12f
    /** 内容列左右内边距（与布局 XML 对齐；收紧时用于 setViewPadding）。 */
    private const val SIDE_PADDING_DP = 14f
    private const val COMPACT_SIDE_PADDING_DP = 10f
    /** 格子高 ≈ 格子宽(dp) × 这个系数（实测 450: 0.56、600: 0.54，取小值偏保守）。 */
    private const val CELL_HEIGHT_RATIO = 0.54f
    /** 主时钟行盒 = 1.2em（字体 ascent 0.9 + descent 0.3）。 */
    private const val CLOCK_LINE_BOX_EM = 1.2f
    /** 时钟行的宽度安全系数：给「桌面实际字宽与 Paint 量测的偏差」留余量，避免秒被挤掉一位。 */
    /**
     * 时钟行宽度安全系数：沿用首页大卡片的 `CLOCK_FIT_SAFETY = 0.97`。
     *
     * 以前这里取 0.90（更保守），桌面卡片因此比首页**小约 7%**，整块内容也矮一截，
     * `center_vertical` 居中后就显得上下留白偏大。两边用同一个比例，观感才一致。
     */
    private const val CLOCK_ROW_SAFETY = 0.97f
    /** 主字号 ≈ 栏宽 × 这个比例（实测 0.27~0.29，只为估算竖向预算，不参与最终字号）。 */
    private const val CLOCK_EM_PER_COLUMN = 0.28f
    /** 密度的合理区间：任何 ROM 给出 0 / 极小 / 荒谬的 density 都不许让字号、宽度塌成 0。 */
    private const val MIN_DENSITY = 1.0f
    private const val MAX_DENSITY = 8.0f
    /** 格子宽度的合理区间（dp）：算出来的一律夹进这个范围，避免 0 宽导致字号 0。 */
    private const val MIN_CELL_WIDTH_DP = 100f
    private const val MAX_CELL_WIDTH_DP = 4000f
    /** 华为「字体粗细」每 +1.0 字重带来的字宽增长（实测 1.18→+4.1%、1.59→+8.5%）。 */
    private const val BOLD_WIDTH_PER_WEIGHT_UNIT = 0.22f
    /** 字宽放大系数的封顶（最粗档也不许把主时钟缩得太小）。 */
    private const val BOLD_WIDTH_MAX = 1.10f
    /** 华为写在 `Settings.System` 里的「字体粗细」键（乘法通道）。 */
    private const val WEIGHT_SCALE_KEY = "font_weight_scale"
    /** AOSP / HyperOS / 原生写的加性字重偏移（`Configuration.fontWeightAdjustment` 的来源），0~1000。 */
    private const val WEIGHT_ADJUSTMENT_KEY = "font_weight_adjustment"
    /** 加性通道拉满（1000）时按「最粗」处理：字宽 +8%（华为 1.59 档实测 +6.5%，取保守值）。 */
    private const val AOSP_BOLD_WIDTH_MAX = 1.08f
    /** 加性通道的量程上限（AOSP 用 0~1000 表示字重偏移）。 */
    private const val AOSP_ADJUSTMENT_MAX = 1000f
    // 秒与冒号的字号不再固定：恒为主字号的 1/2（见 applyClockSizing），布局里的 23dp 只是预览初值。
    private const val DATE_TEXT_DP = 11f
    /**
     * 日期／经纬度这行小字统一缩放的下限。
     *
     * 两者按自然字号（11dp / 10dp）算出的总宽超出可用宽度时一起缩，缩到 0.85 为止
     * （日期 ≈ 9.4dp、经纬度 ≈ 8.5dp），再不够就让日期那格自己省略号截断。
     */
    private const val MIN_SMALL_TEXT_SCALE = 0.85f
    /** 日期行右侧经纬度的字号与它和日期之间的间隙：与其它小字（标签、逐时、日出日落）一致。 */
    private const val COORD_TEXT_DP = 11f
    private const val COORD_GAP_DP = 8f

    /**
     * 真太阳时的强调色，与首页大卡片一致：白天（橙底）用淡金，夜间用金色。
     * 进入关键时间段时另改用 KeyTimePalette 的绿或红。
     */
    private const val SOLAR_TIME_COLOR_DAY = 0xFFFFE6B4.toInt()
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
        // 定位/设置读取本身就可能抛（偏好文件损坏、Place 字段非法……）。它挂在所有渲染之前，
        // 一旦抛出去整轮刷新就没了 —— 桌面只剩 initialLayout（标准时间自走、真太阳时停在占位的
        // 00:00、其余全空），这是用户报过的「卡片全空」最可能的成因。这里一律兜住并退回默认地点。
        val refreshDiag = mutableListOf<Pair<String, String>>()
        refreshDiag += "时间" to DiagStore.now()
        val location = runCatching { resolveLocation(context) }.getOrElse { error ->
            Log.w(TAG, "resolveLocation failed, falling back to Place.DEFAULT", error)
            refreshDiag += "定位" to ("失败，" + DiagStore.describe(error))
            LocationState(Place.DEFAULT, hasFix = false)
        }
        if (refreshDiag.none { it.first == "定位" }) {
            refreshDiag += "定位" to ("成功，hasFix=" + location.hasFix)
        }
        refreshDiag += "地区名" to (DistrictResolver.cachedName(context) ?: "（无缓存）")
        refreshDiag += "小组件数量" to ids.size.toString()
        val place = location.place
        // 地名与天气即使桌面上一个小组件都没有也要更新：首页也在用这两份缓存，
        // 否则定位变化后首页会一直显示启动时那个默认位置的地名。
        // 三条侧链互不相干，任何一条失败都不许挡住主渲染。
        runCatching { DistrictResolver.requestRefresh(context, place) }
            .onFailure {
                Log.w(TAG, "district refresh failed", it)
                refreshDiag += "区划请求" to ("失败，" + DiagStore.describe(it))
            }
        // 小组件这条链路显式按**后台**处理：低精度重试主源最少间隔 10 分钟，
        // 不参与前台的 60/120/300 秒退避（前台心跳在 MainViewModel 里）。
        runCatching { WeatherRepository.requestRefresh(context, place, background = true) }
            .onFailure {
                Log.w(TAG, "weather refresh failed", it)
                refreshDiag += "天气请求" to ("失败，" + DiagStore.describe(it))
            }
        // 关键时间每天在 01:00–05:00 随机时刻同步一次，失败每小时重试，结果缓存 7 天。
        runCatching { TakeTimeRepository.requestRefresh(context) }
            .onFailure { Log.w(TAG, "key-time refresh failed", it) }
        if (ids.isEmpty()) {
            refreshDiag += "结果" to "成功（桌面上没有小组件，只更新了缓存）"
            DiagStore.recordRefresh(context, refreshDiag)
            runCatching { cancelTick(context) }
            return
        }
        // 先排下一分钟再刷新：刷新途中出任何异常（或者进程被系统冻结）都不会把链条断掉。
        runCatching { scheduleNextTick(context, place) }
            .onFailure { Log.w(TAG, "scheduleNextTick failed", it) }
        // 兜底时刻同样兜住：算不出来就传 null，让最小版面写 `--:--` 而不是 00:00。
        val fallbackSeconds = runCatching {
            solarSecondOf(
                Math.floorMod(
                    System.currentTimeMillis() + solarOffsetMillis(Instant.now(), place),
                    DAY_MILLIS,
                ),
            )
        }.getOrNull()
        // 各机型/桌面给到的尺寸不同：按可用宽度与折算后的高度换算字号，2 行高时压缩留白。
        // 单个实例出错（尺寸异常、缓存里是坏 JSON、位图分配失败……）不能连累其它实例，
        // 否则桌面会整块显示「加载失败」——这里逐个兜住，失败就退成只显示时刻的最小版面。
        ids.forEach { id ->
            val updates = runCatching {
                val options = manager.getAppWidgetOptions(id)
                val widthDp = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH)
                val heightDp = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT)
                // 排查尺寸问题时一并打出另一组口径（max 是横屏/放大后的上限，各桌面含义不一）。
                Log.d(
                    TAG,
                    "options($id) min=${options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH)}x" +
                        "${options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT)} " +
                        "max=${options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH)}x" +
                        "${options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT)}",
                )
                val buildDiag = mutableListOf<Pair<String, String>>()
                buildDiag += "时间" to DiagStore.now()
                buildDiag += "AppWidget id" to id.toString()
                buildDiag += "options min" to (widthDp.toString() + "x" + heightDp + "dp")
                buildDiag += "options max" to (options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH)
                    .toString() + "x" + options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT) + "dp")
                buildDiag += "reported W×H(dp)" to (widthDp.toString() + "x" + heightDp + "dp")
                val built = buildViews(context, location, widthDp, heightDp, id, forceChronometer, buildDiag)
                buildDiag += "结果" to "成功"
                DiagStore.recordWidgetBuild(context, buildDiag)
                built
            }.onFailure { error ->
                Log.w(TAG, "buildViews($id) failed, falling back to minimal", error)
                DiagStore.recordWidgetBuildFailure(context, id, error)
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
        runCatching { KeyTimeChime.schedule(context) }.onFailure {
            refreshDiag += "报时排程" to ("失败，" + DiagStore.describe(it))
        }
        refreshDiag += "结果" to "成功"
        DiagStore.recordRefresh(context, refreshDiag)
    }

    /**
     * 刷新失败时的兜底版面：只显示真太阳时的「时:分」，不含位图与 Chronometer。
     *
     * [solarSeconds] 允许为 null（真太阳时算不出来）：这时写 `--:--` 占位，**绝不能写 00:00** ——
     * 用户会把「00:00」当成「真太阳时是零点」，从而认为整个 App 坏了（旧版最小版面就报过这个）。
     */
    private fun minimalViews(context: Context, solarSeconds: Long?): RemoteViews =
        RemoteViews(context.packageName, R.layout.widget_solar_time_minimal).apply {
            setTextViewText(
                R.id.widget_minimal_time,
                solarSeconds?.takeIf { it in 0 until DAY_MILLIS / 1000 }?.let(::clockText) ?: PLACEHOLDER_TIME,
            )
        }

    fun buildViews(
        context: Context,
        location: LocationState = resolveLocation(context),
        widthDp: Int = 0,
        heightDp: Int = 0,
        widgetId: Int = 0,
        forceChronometer: Boolean = false,
        /** 诊断页用：把这次构建的关键参数收集起来（null = 不收集）。 */
        diag: MutableList<Pair<String, String>>? = null,
    ): RemoteViews {
        val place = location.place
        val now = Instant.now()
        val zone = civilZoneOf(context, place, now)
        val civil = now.atZone(zone)
        val solarOffset = solarOffsetMillis(now, place)
        val trueSolarSeconds = SolarTimeMath.trueSolarSecondsOfDay(now, place.longitude)
        val shichenIndex = Shichen.indexOf(trueSolarSeconds)
        // 太阳是否在地平线上（事实，用于逐时图标的昼夜与日出弧；与配色无关）。
        val sunIsUp = SolarTimeMath.solarAltitudeDegrees(now, place.latitude, place.longitude) > -0.833
        // 卡片的昼夜配色：默认「自动」跟随日出日落（旧行为）；设置里强制亮色/暗色时忽略太阳高度角。
        // 与首页同一套判定（AppSettings.themeMode，见 ThemeMode），只是那边读 Compose 的 StateFlow。
        val themeMode = AppSettings(context).themeMode
        val isDay = !themeMode.isDark(sunIsUp)
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
        // 天气来源署名不再画在卡片上（用户要求去掉，日期行只留日期 / 天气 / 经纬度）；
        // CC BY 4.0 的完整署名保留在 App 页脚与设置页「关于」，由 `TimeText.weatherAttribution` 负责。
        // 桌面回报的高度比实际单元格小，先折算成近似可用高度。
        val effectiveHeightDp = if (heightDp > 0) heightDp * HEIGHT_SCALE else 0f
        // 折算后不足两行的高度就算「一行卡片」。桌面一律按「一格 70dp」上报（实测 1 行报 46~52dp、
        // 2 行报 116dp），折算后 145dp 正好把一行和两行分开。
        val singleRow = effectiveHeightDp > 0f && effectiveHeightDp < MIN_HEIGHT_WITH_HOURLY_DP
        val large = isLargeScreen(context)
        // 一行卡片在两档设备上的实际高度差很多：平板一格实测 143dp，刚好装得下带逐时行的紧凑版面；
        // 手机一格只有约 107dp，连日期行+时间轴都塞不下。所以：
        //   * 平板一行 → 紧凑间距 + 整张卡（时钟、日期、时间轴、逐时行）；
        //   * 手机一行 → 常规间距（把空间用满）+ 只留两栏时钟与日期，时间轴和逐时行都让位；
        //   * 两行及以上 → 与原来一致，按折算高度在常规/紧凑之间切。
        val compact = if (singleRow) large else effectiveHeightDp > 0f && effectiveHeightDp < REGULAR_MIN_CONTENT_DP
        // 关键时间只在刷新时读一次：时间轴着色与真太阳时的数字都要用。
        val keyTime = TakeTimeRepository.schedule(context)
        val solarSecondsOfDay = solarSeconds.toDouble()
        val keyColor = if (location.hasFix) activeKeyColor(keyTime, solarSecondsOfDay, isDay) else null
        var showAxis = !singleRow || large
        val showHourly = !singleRow || large
        // 竖向预算：格子按**像素**固定，而版面是按 dp 排的 —— 显示密度被抬高（长辈关怀的 600）
        // 或格子偏矮时，内容就装不下，最后一行会被裁掉半截（实测华为 600 档：格子 164dp、
        // 内容 185dp，逐时天气行只露出上半截）。按「先压留白 → 再收时间轴」的顺序收紧，
        // 只有还不够时才让主时钟缩一点。常规 450 档实测不紧（内容 199dp ≤ 可用 207dp），
        // 一个字节都不动。
        val fitMetrics = renderMetrics(context)
        val cellDp = cellWidthDp(fitMetrics, widthDp)
        val columnPx = ((cellDp * fitMetrics.density -
            (if (compact) COMPACT_COLUMN_CHROME_DP else COLUMN_CHROME_DP) * fitMetrics.density) / 2f)
            .coerceAtLeast(1f)
        val clockRowDp = CLOCK_LINE_BOX_EM * columnPx * CLOCK_EM_PER_COLUMN / fitMetrics.density
        val availableDp = cellDp * CELL_HEIGHT_RATIO
        // 注意比的是**本进程原始密度**：fitMetrics.density 已经夹到出厂密度了，跟出厂比较永远相等。
        val densityOverridden = verticalFitEnabled(context)
        var contentDp = CONTENT_FIXED_DP + clockRowDp
        var compressPadding = false
        // 收紧到最后一档才缩字号：给时钟行留出剩余预算（下限 12dp，免得缩成一条线）。
        var clockRowBudgetDp = 0f
        val denseLayout = compact
        val cellWidthDpValue = cellDp
        if (densityOverridden && !singleRow && showAxis && contentDp > availableDp) {
            Log.d(TAG, "vertical tight: content=${contentDp}dp avail=${availableDp}dp -> hide axis + tighter padding")
            showAxis = false
            compressPadding = true
            contentDp -= AXIS_ROW_DP + PADDING_SAVE_DP
        }
        if (densityOverridden && !singleRow && contentDp > availableDp) {
            clockRowBudgetDp = (availableDp - (contentDp - clockRowDp)).coerceAtLeast(12f)
            Log.d(TAG, "vertical still tight: shrink clock row to ${clockRowBudgetDp}dp (was ${clockRowDp}dp)")
            contentDp = availableDp
        }
        // 只有**平板**才在富余空间里加料（手机上一加就显满，实测 P40 Pro 的 5x2 卡片
        // 折算 262dp，够高但不该再塞东西）：
        // 高度富余 → 加一行日出/正午/日落；再富余一截 → 加第二排逐时天气（后 6 小时）。
        val tallContent = effectiveHeightDp >= TALL_CONTENT_DP
        val roomForMoreWeather = effectiveHeightDp >= TALL_WEATHER_DP &&
            widthDp >= MIN_WIDTH_FOR_SECOND_HOUR_ROW_DP
        val showSunRow = large && tallContent && !singleRow
        val showSecondHourRow = large && showHourly && roomForMoreWeather
        val layout = if (compact) R.layout.widget_solar_time_compact else R.layout.widget_solar_time
        // 各厂商启动器上报的高度口径差异很大（小米/华为实测 2 行报 110~143dp，实际单元格 165~286dp），
        // 排查布局问题时先把原始值与折算值打出来。
        Log.d(
            TAG,
            "build($widgetId) reported=${widthDp}x${heightDp}dp effectiveHeight=${effectiveHeightDp}dp " +
                "singleRow=$singleRow large=$large compact=$compact axis=$showAxis hourly=$showHourly " +
                "sun=$showSunRow hourly2=$showSecondHourRow " +
                "layout=${if (compact) "compact" else "regular"}",
        )

        return RemoteViews(context.packageName, layout).apply {
            setInt(
                R.id.widget_root,
                "setBackgroundResource",
                if (isDay) R.drawable.widget_background_day else R.drawable.widget_background_night,
            )
            // 竖向富余先用来放大时钟（上限：宽度拟合值 / 时钟行占满可用高度），
            // 还有剩再均分给上下内边距。空间不足时 growDp 为 0，仍走原来的压缩逻辑。
            val roomDp = (if (effectiveHeightDp > 0f) effectiveHeightDp else availableDp)
            // 主时间字号按栏宽换算（桌面回报的宽度与实际一致），保证填满栏宽又不被裁切。
            val mainPx = applyClockSizing(
                context = context,
                widthDp = widthDp,
                date = date,
                coordinates = TimeText.coordinates(context, place.latitude, place.longitude),
                compact = compact,
                views = this,
                clockRowBudgetDp = clockRowBudgetDp,
                clockRowGrowDp = 0f,
                diag = diag,
            )
            // 与首页大卡片同一套字号/行距（时钟字号只由宽度拟合决定），
            // 多出来的高度**平均分给上下**，内容垂直居中；放不下则维持原压缩逻辑。
            val clockRowNowDp = CLOCK_LINE_BOX_EM * mainPx / renderMetrics(context).density
            // 一行 logcat 方便 adb 直接核对：可用/内容高度、时钟字号、有没有撞宽度上限。
            Log.d(
                TAG,
                "clock fit: avail=${roomDp}dp content=${(CONTENT_FIXED_DP + clockRowNowDp).toInt()}dp " +
                    "clockPx=${mainPx.toInt()} widthLimited=${clockRowBudgetDp == 0f}",
            )
            val (topPaddingDp, bottomPaddingDp) = if (!compressPadding && !singleRow) {
                WidgetVerticalPadding.paddingDp(
                    availableDp = roomDp,
                    contentDp = CONTENT_FIXED_DP + clockRowNowDp,
                    basePaddingDp = 10f,
                )
            } else {
                10f to 10f
            }
            val extraPaddingDp = 0f
            diag?.apply {
                add("单行版面 singleRow" to singleRow.toString())
                add("紧凑版面 compact" to denseLayout.toString())
                add("时间轴显示" to showAxis.toString())
                add("逐时行显示" to showHourly.toString())
                add("压缩内边距" to compressPadding.toString())
                add("格子宽度预算 cellDp" to cellWidthDpValue.toString())
                add("时钟行预算(dp)" to clockRowBudgetDp.toString())
                add("逐时步长(小时)" to WeatherRepository.stepHours(context).toString())
                add("主题模式" to themeMode.name.lowercase(Locale.ROOT))
                add("昼夜(经主题修正)" to if (isDay) "白天" else "夜间")
            }
            if (compressPadding) {
                // 上下内边距 10dp/9dp → 4dp：内容更紧时先把留白压掉，比收掉整行信息温和得多。
                val d = renderMetrics(context).density
                val side = (if (compact) COMPACT_SIDE_PADDING_DP else SIDE_PADDING_DP) * d
                val v = 4f * d
                setViewPadding(R.id.widget_content, side.toInt(), v.toInt(), side.toInt(), v.toInt())
            } else if (extraPaddingDp > 0.5f) {
                // 竖向富余均分：上下各加同样的值，内容自然垂直居中（左右内边距不变）。
                val d = renderMetrics(context).density
                val side = (if (compact) COMPACT_SIDE_PADDING_DP else SIDE_PADDING_DP) * d
                val v = (10f + extraPaddingDp) * d
                setViewPadding(R.id.widget_content, side.toInt(), v.toInt(), side.toInt(), v.toInt())
                diag?.add("竖向富余/侧(dp)" to "%.1f".format(Locale.US, extraPaddingDp))
            }
            if (showAxis) {
                bindAxis(context, widthDp, compact, now, location.hasFix, solarOffset, keyTime, isDay, this)
            } else {
                // 一行卡片放不下时间轴：整条连位图一起收掉，别让它在底部露出半截。
                setViewVisibility(R.id.widget_axis, View.GONE)
            }
            setString(R.id.widget_civil_time, "setTimeZone", zone.id)
            setString(R.id.widget_civil_sec, "setTimeZone", zone.id)
            // 顶部标签行（整行一个逻辑单元）：`UTC+8` 直接写偏移，与首页一致 —— 一张卡片上
            // 「标准时间」到底是哪个时区的，一眼就能看出来。地区按四档退化（见 planCityLabel），
            // 时辰在下面的 hasFix 分支里写入。
            //
            // 档 0 与档 1-3 的排布**结构**不同，布局里因此有两套容器 + 两套同义控件
            // （RemoteViews 改不了 layout_weight / 宽度，只能准备两份）：
            //   * 档 0 → widget_top_row_default：整行分左右两半，左半 `UTC` 贴左 + 地区贴右
            //     （右端落在 50% 分界上），右半「真太阳时」贴左 + 时辰贴最右 —— 与首页 HeroCard 档 0 同一几何；
            //   * 档 1-3 → widget_top_row：合并成一条，地区对齐由 setGravity 按档位下发。
            // 两个容器互斥，文本 / 可见性 / 对齐对两套控件一起下发（同一布局里 id 不能重名）。
            // 竖分隔线同理有两份（见下面 dividerReachesLabelRow 那一段）。
            // 顶行留给地名的宽度要按**这次真要写的**时辰文案算：中文「亥时」两个汉字，
            // 英文 "Hai hour" 更宽。去掉「初/正」后时辰短了，档位判定自动变宽松。
            val shichenForWidth = cityTextEm(shichenText(context, solarSecondsOfDay))
            val city = cityLabel(context, place, widthDp, compact, shichenForWidth)
            val topRowDefault = city.tier == 0
            setViewVisibility(
                R.id.widget_top_row_default,
                if (topRowDefault) View.VISIBLE else View.GONE,
            )
            setViewVisibility(
                R.id.widget_top_row,
                if (topRowDefault) View.GONE else View.VISIBLE,
            )
            // 竖分隔线（整行 50% 处那条）：档 0 的标签行仍是左右两半 —— 左半地区贴右、右半
            // 「真太阳时」贴左，两半的分界**就是**下面两列的分界，所以那条线要从标签行顶部
            // 一路贯到两列底部；档 1~3 标签行已合并成一整行，线只盖下方两列（规则见
            // SmallRowLayout.dividerReachesLabelRow）。
            // 布局里为此有两条线、落在同一个 x 上：上延档位让短线 INVISIBLE（保留占位，两列的
            // 宽度与行高都不变），其余档位让高线 GONE —— 两条同时可见会在同一段上叠成更深的一截。
            val dividerReachesLabelRow = SmallRowLayout.dividerReachesLabelRow(city.tier)
            setViewVisibility(
                R.id.widget_divider_tier0,
                if (dividerReachesLabelRow) View.VISIBLE else View.GONE,
            )
            setViewVisibility(
                R.id.widget_divider_short,
                if (dividerReachesLabelRow) View.INVISIBLE else View.VISIBLE,
            )
            val utcLabel = TimeFormat.utcOffsetLabel(zone.rules.getOffset(now).totalSeconds)
            val cityText = if (location.hasFix) city.text else ""
            diag?.apply {
                add("档位 tier" to city.tier.toString())
                add("地区名文本" to (cityText.ifBlank { "（空）" }))
                add("UTC 标签" to (
                    if (city.showUtc) TimeFormat.utcOffsetLabel(zone.rules.getOffset(now).totalSeconds)
                    else "（本档收起）"
                    ))
            }
            // 对齐跟着档位走（与首页一致）：0 档贴右（贴着分界）→ 1 档居中 → 2/3 档贴左；
            // 档 3 的省略号由布局里的 ellipsize="end" + maxLines="1" 保证。
            // TextView#setGravity 带 @RemotableViewMethod，可以交给宿主进程执行。
            // 只下发 setGravity，不碰 transformationMethod 之类非 RemoteViews 属性。
            for (utcId in TOP_ROW_UTC_IDS) setTextViewText(utcId, utcLabel)
            for (cityId in TOP_ROW_CITY_IDS) {
                setTextViewText(cityId, cityText)
                // ⚠️ TextView#setGravity 的 @RemotableViewMethod 是后来才加上的：
                // Android 10（P30 / ELE-AL00 实测）上 RemoteViews 调它会抛
                //   "view: android.widget.TextView can't use method with RemoteViews: setGravity(int)"
                // 而且是**在桌面进程里**抛，我们这边 catch 不到 —— 整个小组件直接变成
                // 「加载窗口小工具时出现问题」的空白块。只在验证过的新系统上下发，
                // 老系统用布局里声明的默认对齐（档 1 的地区名靠左而不是居中，可接受）。
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    setInt(cityId, "setGravity", gravityFor(city.align))
                }
            }
            // 档 1 起收起「真太阳时」，档 2 起连 UTC 一起收起：把位置让给长地名。
            for (utcId in TOP_ROW_UTC_IDS) {
                setViewVisibility(utcId, if (city.showUtc) View.VISIBLE else View.GONE)
            }
            for (solarId in TOP_ROW_SOLAR_IDS) {
                setViewVisibility(solarId, if (city.showSolarLabel) View.VISIBLE else View.GONE)
            }
            setTextViewText(R.id.widget_civil_date, date)
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
                val shichen = shichenText(context, solarSecondsOfDay)
                for (shichenId in TOP_ROW_SHICHEN_IDS) setTextViewText(shichenId, shichen)
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
                for (shichenId in TOP_ROW_SHICHEN_IDS) setTextViewText(shichenId, "")
                setTextViewText(R.id.widget_coordinates, context.getString(R.string.widget_waiting_gps))
            }
            bindSunRow(context, place, now, zone, showSunRow && location.hasFix, this)
            // 逐时行在「还没有定位」时也照样画出来（格子填 `-` 与问号图标）：
            // 早先这里整块隐藏，卡片就只剩两个时钟、下面空一大片，看着像坏了；
            // 留占位既保持版面形状，也说明「在等数据」。
            bindHourly(
                context, place, now, zone,
                show = showHourly,
                row = FIRST_HOUR_ROW,
                skipSlots = 0,
                hasFix = location.hasFix,
                views = this,
            )
            bindHourly(
                context, place, now, zone,
                show = showSecondHourRow,
                row = SECOND_HOUR_ROW,
                skipSlots = FIRST_HOUR_ROW.size,
                hasFix = location.hasFix,
                views = this,
            )
            bindClicks(context, place, this)

        }
    }

    /**
     * 时间轴圆点的「横向预压扁」系数。
     *
     * 轴线整条是按**桌面回报的宽度**画成位图、再由桌面 `fitXY` 横向拉伸到真实卡片宽度，
     * 画成正圆的点子会被拉成椭圆。桌面只给名义尺寸、真实宽度拿不到，所以按屏幕档位来：
     *
     * - **手机 = 1.0（完全不动）**：Pixel 这类桌面回报的宽度和真实卡片基本一致，圆点本来就是正圆。
     * - **平板 = 1.30**：华为桌面回报 304dp、实际卡片约 396dp，横向被拉伸 1.3 倍，点子明显变扁。
     *
     * 实测（截图量亮核）：平板改前宽高比 1.29 → 改后 1.00。
     */
    private fun dotXCompensation(context: Context): Float =
        if (isLargeScreen(context)) 1.30f else 1f

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
        // 位图是按像素画、再被桌面 1:1 贴上去的，所以这里也要用「桌面渲染密度」而不是本进程密度，
        // 否则长辈模式（显示大小 600、本进程 density 3.75）下轴的高度会比版面高 13%，版面跟着挤。
        val metrics = renderMetrics(context)
        val density = metrics.density
        val totalWidthDp = cellWidthDp(metrics, widthDp)
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
        val bandColor = KeyTimePalette.band(schedule?.temperature, isDay) ?: 0
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
            dotXCompensation = dotXCompensation(context),
        )
        if (bitmap != null) {
            views.setImageViewBitmap(R.id.widget_axis, bitmap)
            // 把视图高度钉成位图的像素高度，纵向缩放就永远是 1:1。
            // 不钉的话，布局写的是 `13dp`，由**宿主**按它自己的密度换算：真机 P40 Pro 上
            // 系统的显示大小被改成 450dpi、物理 530dpi，宿主换算出的 13dp 比我们算的位图高，
            // 竖直方向被放大，圆点就变成竖椭圆（同一份代码在模拟器上是正圆）。
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                views.setViewLayoutHeight(R.id.widget_axis, heightPx.toFloat(), TypedValue.COMPLEX_UNIT_PX)
            }
        }
    }

    /**
     * 那一行能显示的地名：名字越长，依次让出「真太阳时」「UTC」的位置，
     * 而不是把名字截成「克孜勒苏柯尔克孜自治…」。
     */
    private fun cityLabel(
        context: Context,
        place: Place,
        widthDp: Int,
        compact: Boolean,
        shichenEm: Float,
    ): CityLabelPlan {
        // 兜底名与首页保持同一优先级：预设城市名优先，其次才用离线城市表里最近的城市。
        // 这样「点选纽约」时首页与桌面卡片写的是同一个名字。
        val presetLabel = place.labelResName?.let { TimeText.placeLabel(context, place) }.orEmpty()
        val fallback = presetLabel.ifEmpty {
            CityIndex.nearest(
                place.latitude,
                place.longitude,
                Locale.getDefault().language,
            )?.name.orEmpty()
        }
        // 与首页同一口径：缓存里的区划名只在与当前地点相距 ≤5 km 时才认，
        // 换城市后立刻失效，绝不拿上一个城市的地名凑数。
        val names = DistrictResolver.cachedNamesFor(context, place)
        val totalWidthDp = if (widthDp > 0) widthDp.toFloat() else DEFAULT_WIDGET_WIDTH_DP
        val budgets = cityRowBudgets(totalWidthDp, compact, shichenEm)
        return planCityLabel(names, fallback, budgets.tier0, budgets.tier1, budgets.tier2)
    }

    /**
     * 顶部标签行留给地名的宽度上限（单位：字号 em，1.0 = 一个汉字宽），三档一一对应首页
     * `SmallRowLayout.cityRowTier` 的判定：
     *
     * - [tier0]：档 0 —— 与首页同一套几何，地区要能塞进**左半**（整行一半减去 UTC、
     *   两段之间的间距、以及地区与竖线之间的 [CITY_END_INSET_DP]）。
     *   右半连「真太阳时 + 时辰」都装不下时档 0 不可能成立，这里返回负数，让所有地名退到档 1。
     * - [tier1]：收起「真太阳时」后，UTC + 地区 + 时辰 装进整行。
     * - [tier2]：再收起 UTC，地区 + 时辰 装进整行（再宽就是档 3：贴左 + 省略号）。
     *
     * @param shichenEm 当前这次刷新要写入的时辰文本宽度（单位「字号」）。默认按中文「亥时」
     *   两个汉字估算；调用方传本地化后的实际文案（英文 "Hai hour" 更宽），
     *   这样去掉「初/正」后判档会自动跟着变宽，不必改常量。
     */
    internal data class CityRowBudgets(val tier0: Float, val tier1: Float, val tier2: Float)

    internal fun cityRowBudgets(
        widthDp: Float,
        compact: Boolean,
        shichenEm: Float = SHICHEN_DP / CITY_TEXT_DP,
    ): CityRowBudgets {
        val totalWidthDp = if (widthDp > 0f) widthDp else DEFAULT_WIDGET_WIDTH_DP
        val paddingDp = if (compact) 10f else 14f
        // 整行可用宽度：卡片宽度减去左右内边距（顶行横跨整行，不再按栏宽算），
        // 再换算成「字号」数（1.0 = 一个汉字宽）。
        val rowEm = (totalWidthDp - paddingDp * 2f) / CITY_TEXT_DP
        val utcEm = UTC_LABEL_DP / CITY_TEXT_DP
        val solarLabelEm = SOLAR_LABEL_DP / CITY_TEXT_DP
        val gapEm = CITY_LABEL_GAP_DP / CITY_TEXT_DP
        val cityEndEm = CITY_END_INSET_DP / CITY_TEXT_DP
        val halfEm = rowEm / 2f
        // 档 0 要求右半装得下「真太阳时 + 时辰」，与首页两半等宽一致。
        val rightHalfFits = solarLabelEm + shichenEm + gapEm <= halfEm
        return CityRowBudgets(
            // 左半：UTC + 间距 + 地区 + 地区与竖线之间的间隙。
            tier0 = if (rightHalfFits) halfEm - utcEm - gapEm - cityEndEm else -1f,
            tier1 = rowEm - utcEm - shichenEm - 2f * gapEm,
            tier2 = rowEm - shichenEm - gapEm,
        )
    }

    /**
     * 地名在卡片上怎么水平对齐：地址越长、让出的东西越多，对齐就越往左走。
     *
     * 与首页大卡片顶部那一行的四档一一对应（`SmallRowLayout.cityRowTier`）：
     * 档 0 贴右、档 1 居中、档 2/3 贴左。
     */
    internal enum class CityAlign { END, CENTER, START }

    /** [CityAlign] → TextView 的 gravity（只动水平方向，纵向仍是默认的顶部）。 */
    private fun gravityFor(align: CityAlign): Int = when (align) {
        CityAlign.END -> Gravity.END
        CityAlign.CENTER -> Gravity.CENTER_HORIZONTAL
        CityAlign.START -> Gravity.START
    }

    /**
     * 地名的四档显示（与首页大卡片顶部那一行同一套语义）。
     *
     * 档 0 与档 1-3 用的是布局里的**两个容器**（见 [build]）：档 0 的两半结构里
     * `UTC+8` 在左半最左、地区贴在左半最右（即整行 50% 分界），「真太阳时」从分界右侧起排、
     * 时辰贴整行最右；档 1-3 合并成一条，`UTC+8` 在左、地区在中间、时辰在最右。
     *
     * - **档 0**：`UTC` 与「真太阳时」都还在，地区在**左半**（UTC 到「真太阳时」之间）**贴右**；
     * - **档 1**：收起「真太阳时」，地区在 UTC 与时辰之间**居中**；
     * - **档 2**：再收起 UTC，地区**贴左**；
     * - **档 3**：同档 2，地区尾部用省略号（布局里的 `ellipsize="end"` + `maxLines="1"`）。
     *
     * 任何档位时辰都保留、且始终贴整行最右。
     *
     * @param maxTier0 收起任何标签之前地名能占的「字号」数（1.0 = 一个汉字宽）
     * @param maxTier1 收起「真太阳时」之后地名能占的字号数
     * @param maxTier2 连 UTC 一起收起之后地名能占的字号数（再宽就是档 3）
     */
    internal data class CityLabelPlan(
        val text: String,
        val tier: Int,
    ) {
        /** 档 0/1 还显示 UTC，档 2 起收起。 */
        val showUtc: Boolean get() = tier <= 1

        /** 只有档 0 还显示「真太阳时」这四个字。 */
        val showSolarLabel: Boolean get() = tier == 0

        val align: CityAlign
            get() = when (tier) {
                0 -> CityAlign.END
                1 -> CityAlign.CENTER
                else -> CityAlign.START
            }
    }

    internal fun planCityLabel(
        names: DistrictResolver.DistrictNames?,
        fallback: String,
        maxTier0: Float,
        maxTier1: Float,
        maxTier2: Float,
    ): CityLabelPlan {
        // 还没有反查到区划名（离线、或新坐标还没查回来）：写兜底名，按最宽松的档 0 排。
        if (names == null) return CityLabelPlan(fallback, tier = 0)
        val full = names.full
        val em = cityTextEm(full)
        return when {
            em <= maxTier0 -> CityLabelPlan(full, tier = 0)
            em <= maxTier1 -> CityLabelPlan(full, tier = 1)
            em <= maxTier2 -> CityLabelPlan(full, tier = 2)
            // 仍放不下：保持贴左，交给 TextView 的省略号兜底（与首页档 3 一致）。
            else -> CityLabelPlan(full, tier = 3)
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
        return if (inside) KeyTimePalette.ink(schedule.temperature, isDay) else null
    }

    /** 时辰标签，与首页大卡片一致：只显示时辰名（如「亥时」/ "Hai hour"），不再带时初／时正。 */
    private fun shichenText(context: Context, solarSecondsOfDay: Double): String =
        TimeText.shichenName(context, Shichen.indexOf(solarSecondsOfDay))

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

    /** 是否已有一个「卡片侧」定位请求在路上：避免每分钟的刷新叠加请求。 */
    private var gpsFixInFlight = false

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

    /**
     * 底部小时预报：从「现在」那一格起按数据源步长（1 小时 / 3 小时）取，显示时刻、天气图标与**气温**；
     * 没有数据或高度不够时整行隐藏。
     *
     * 图标下面那一行原来写的是天气文字，现在与首页大卡片、iOS 版一样换成该格气温（`18°`），
     * 缺读数时写占位符 `-`；「现在」那一格用实时温度（日期行那个读数），不用可能陈旧的采样点温度。
     */
    private fun bindHourly(
        context: Context,
        place: Place,
        now: Instant,
        zone: ZoneId,
        show: Boolean,
        row: HourRow,
        skipSlots: Int,
        hasFix: Boolean,
        views: RemoteViews,
    ) {
        val hourly = WeatherRepository.hourly(context, place)
        views.setViewVisibility(row.rowId, if (show) View.VISIBLE else View.GONE)
        if (!show) return

        val slots = WeatherRepository.visibleSlots(
            points = hourly.points,
            nowEpochSeconds = now.epochSecond,
            zoneOffsetSeconds = zone.rules.getOffset(now).totalSeconds,
            count = row.size,
            stepHours = hourly.stepHours,
            // 第二排接在第一排后面：直接跳过前 6 格，不能按小时数硬挪（3 小时源的「6 格」是 18 小时）。
            skip = skipSlots,
        )
        val points = hourly.points.associateBy { it.epochSeconds }
        // 第一排的第一格标「现在」，用实时天气码与实时温度，与日期行的读数保持一致。
        val cached = WeatherRepository.cached(context, place)
        val currentCode = cached?.code
        val currentTemperature = cached?.temperatureC
        val temperatures = hourTemperatures(
            points = hourly.points,
            nowEpochSeconds = now.epochSecond,
            zoneOffsetSeconds = zone.rules.getOffset(now).totalSeconds,
            stepHours = hourly.stepHours,
            currentTemperatureC = currentTemperature,
            count = row.size,
            skip = skipSlots,
            hasFix = hasFix,
        )
        val unknown = context.getString(R.string.weather_unknown)
        val degrees: (Int) -> String = { context.getString(R.string.weather_temp, it) }
        slots.forEachIndexed { index, slot ->
            val point = points[slot.epochSeconds]
            val isNow = slot.isNow
            val hour = Instant.ofEpochSecond(slot.epochSeconds).atZone(zone).hour
            val label = if (isNow) {
                context.getString(R.string.weather_now)
            } else {
                // 标签用该采样点**实际**的本地小时数：3 小时源会得到 23时/2时/5时…，不是「现在 + n」。
                context.getString(R.string.weather_hour, hour)
            }
            // 还没有定位时一律画占位符：兜底城市（内置默认坐标）的天气挂在这里会让人
            // 以为那就是当地的读数（气温同理，见 hourTemperatures 的 hasFix）。
            val code = if (!hasFix) {
                null
            } else if (isNow) {
                currentCode ?: point?.code
            } else {
                point?.code
            }
            views.setTextViewText(row.labelIds[index], label)
            val condition = code?.let { WeatherRepository.conditionOf(it) }
            views.setImageViewResource(
                row.iconIds[index],
                condition?.let { conditionIcon(it, isDay = hour in 6..17) } ?: R.drawable.ic_wx_unknown,
            )
            views.setTextViewText(
                row.tempIds[index],
                temperatureLabel(temperatures[index], degrees, unknown),
            )
        }
    }

    /**
     * 日出 / 正午 / 日落那一行：只在卡片够高时显示。
     *
     * 时间按观测点的标准时（与左栏那个时钟同一口径），不是真太阳时；极昼／极夜时
     * 没有日出或日落，对应的位置显示占位符 `--`。
     */
    private fun bindSunRow(
        context: Context,
        place: Place,
        now: Instant,
        zone: ZoneId,
        show: Boolean,
        views: RemoteViews,
    ) {
        views.setViewVisibility(R.id.widget_sun_row, if (show) View.VISIBLE else View.GONE)
        if (!show) return
        val times = SolarTimeMath.sunTimes(now.atZone(zone).toLocalDate(), place.latitude, place.longitude)
        fun text(time: Instant?): String = time?.atZone(zone)?.toLocalTime()
            ?.let { "%02d:%02d".format(Locale.ROOT, it.hour, it.minute) }
            ?: context.getString(R.string.weather_unknown)
        views.setTextViewText(R.id.widget_sunrise, text(times.sunrise))
        views.setTextViewText(R.id.widget_noon, text(times.solarNoon))
        views.setTextViewText(R.id.widget_sunset, text(times.sunset))
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
        clockRowBudgetDp: Float = 0f,
        /** 竖向富余时，允许把主字号放大到「时钟行占满这么多 dp」为止（0 = 不放大）。 */
        clockRowGrowDp: Float = 0f,
        diag: MutableList<Pair<String, String>>? = null,
    ): Float {
        val metrics = renderMetrics(context)
        val density = metrics.density
        val totalWidthPx = cellWidthDp(metrics, widthDp) * density
        val chromeDp = if (compact) COMPACT_COLUMN_CHROME_DP else COLUMN_CHROME_DP
        val columnWidthPx = ((totalWidthPx - chromeDp * density) / 2f).coerceAtLeast(0f)

        // 两条规则与首页大卡片一致：
        //   1. 秒（和它前面的冒号）**恒为主字号的一半**；
        //   2. 「时:分 + 半高秒」的总宽**正好撑满栏宽**。
        // 因为秒是主字号的一半，两者宽度都随主字号线性变化，所以一次解方程即可：
        //   主字号·R主 + (主字号/2)·(R秒 + R冒) + 间隙 = 栏宽
        // 等宽数字（tnum）下「00:00」「00」「:」的宽度与具体时刻无关，比例可以一次量准。
        val probePx = dpToPx(MAX_MAIN_TEXT_DP, metrics)
        val paint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            // 必须用**小组件实际渲染的那份字面**（`@font/card_sans_widget` = Noto Sans SC Medium）：
            // 早先这里量的是系统 `sans-serif-medium`，而 Noto 的数字略宽（约 +6%），
            // 于是「秒」那一段的 setMaxWidth 差一点点 —— 长辈模式下主字号变小、余量被吃掉，
            // 两位秒就被裁成一位（实测：`12:03:2`）。
            typeface = widgetTypeface(context)
            fontFeatureSettings = "tnum"
            textSize = probePx
        }
        val mainRatio = paint.measureText(MAIN_TEXT_SAMPLE) / probePx
        val secondsRatio = paint.measureText(SECOND_SAMPLE) / probePx
        val colonRatio = paint.measureText(":") / probePx
        // 「行内剩余宽度」反算：主钟的盒子 = 栏宽 −（冒号 + 两位秒的实测宽度）− 两段间距。
        // 布局里主钟已经改成 weight=1（冒号与秒先按自然宽度排完，剩下的全给主钟），
        // 所以这里算出来的就是这个盒子的宽度；秒再也不会因为主钟太宽而被挤掉一位。
        // 冒号/秒都是主钟的一半，宽度随主字号线性变化，一次解方程即可。
        val secondsAndColonRatio = (secondsRatio + colonRatio) / 2f
        val gapsPx = (TEXT_GAP_DP * 2f + SECOND_WIDTH_SLACK_DP / 2f) * density
        val bodyPx = (columnWidthPx - gapsPx).coerceAtLeast(1f)
        // 行宽安全系数：桌面实际渲染的字宽/间距与我们用 Paint 量出来的可能有几个百分点出入
        // （小米实测差到 ~9%，秒就被挤掉一位）。宁可整行窄一点，也不裁字。
        val fittedPx = if (mainRatio > 0f) {
            bodyPx * CLOCK_ROW_SAFETY / (mainRatio + secondsAndColonRatio)
        } else {
            0f
        }
        // 加粗会把字渲染得更宽（见 boldWidthFactor）：主时钟按系数缩小，把多出来的宽度让给秒，
        // 否则最粗档两位秒会被挤出栏宽只剩一位。系数 ≤1.0 时这一步是恒等变换。
        val bold = boldWidthFactor(context)
        var mainPx = (fittedPx * clockSafetyFactor(context, metrics) / bold)
            .coerceIn(dpToPx(MIN_MAIN_TEXT_DP, metrics), probePx)
            .coerceAtLeast(dpToPx(MIN_MAIN_TEXT_DP, metrics))
        if (clockRowBudgetDp > 0f) {
            // 竖向预算兜底：时钟行（1.2em 行盒）不得超过分配到的 dp，否则最后一行会被裁。
            val cap = clockRowBudgetDp * density / CLOCK_LINE_BOX_EM
            if (cap < mainPx) {
                Log.d(TAG, "clock shrink for vertical budget: ${mainPx}px -> ${cap}px")
                mainPx = cap.coerceAtLeast(dpToPx(MIN_MAIN_TEXT_DP, metrics) / 2f)
            }
        }
        // 竖向富余：把主字号往上顶，直到「时钟行占满可用高度」或「碰到宽度拟合值」。
        // 两列共用同一个 mainPx（下面分别下发同一字号），所以左右永远同步放大。
        if (clockRowGrowDp > 0f) {
            val heightCapPx = clockRowGrowDp * density / CLOCK_LINE_BOX_EM
            val widthCapPx = fittedPx.coerceAtLeast(mainPx)
            val grown = minOf(heightCapPx, widthCapPx).coerceAtLeast(mainPx)
            if (grown > mainPx) {
                Log.d(TAG, "clock grow: ${mainPx}px -> ${grown}px (heightCap=${heightCapPx}px)")
                mainPx = grown
            }
        }
        val halfPx = mainPx / 2f

        views.setTextViewTextSize(R.id.widget_civil_time, TypedValue.COMPLEX_UNIT_PX, mainPx)
        views.setTextViewTextSize(R.id.widget_solar_time, TypedValue.COMPLEX_UNIT_PX, mainPx)
        // 秒与冒号一起按半高下发（都按 px，不用布局里的 sp：sp 会由宿主按它自己的字体缩放解析，
        // 一旦与本进程的度量不一致，裁剪点就会偏，把「0:SS」的冒号露出来）。
        views.setTextViewTextSize(R.id.widget_civil_colon, TypedValue.COMPLEX_UNIT_PX, halfPx)
        views.setTextViewTextSize(R.id.widget_civil_sec, TypedValue.COMPLEX_UNIT_PX, halfPx)
        views.setTextViewTextSize(R.id.widget_solar_colon, TypedValue.COMPLEX_UNIT_PX, halfPx)
        views.setTextViewTextSize(R.id.widget_solar_sec, TypedValue.COMPLEX_UNIT_PX, halfPx)
        // Chronometer 的文本是「M:SS」，把宽度限成两位数字再配合右对齐，只露出秒数。
        // **必须严格小于「两位数字 + 冒号」**：早先按「两位数字 + 2dp 余量」算，2dp 足以让自带的
        // 冒号完整露出来，于是和静态冒号叠成 `::37`（真太阳时那侧就中招了）。这里用实测的数字宽
        // 与冒号宽，余量强制压到冒号宽以内。两边共用同一个值，标准时间那侧同样安全。
        val scale = if (probePx > 0f) halfPx / probePx else 0f
        val digitPx = paint.measureText("0") * scale * bold
        val colonPx = paint.measureText(":") * scale * bold
        val secondsMaxWidth = ClockWidthMath.secondsMaxWidthPx(
            digitWidthPx = digitPx,
            colonWidthPx = colonPx,
            slackPx = SECOND_WIDTH_SLACK_DP * density,
        )
        views.setInt(R.id.widget_solar_sec, "setMaxWidth", secondsMaxWidth)

        diag?.apply {
            add("主时钟 mainPx" to mainPx.toInt().toString())
            add("秒 setMaxWidth(px)" to secondsMaxWidth.toString())
            add("秒数字宽(px)" to digitPx.toInt().toString())
            add("秒冒号宽(px)" to colonPx.toInt().toString())
            add("clockSafetyFactor" to clockSafetyFactor(context, metrics).toString())
            add("boldWidthFactor" to bold.toString())
            add("renderDensity" to density.toString())
            add("格子宽度 cellWidthDp" to cellWidthDp(metrics, widthDp).toString())
        }
        // 左侧标准时间的秒是 TextClock（文本恒为两位 ss），同样限宽 + 右对齐：
        // 万一这一行被栏宽挤到，宁可裁掉空白也不要把一位数字拦腰截断（小米实测过）。
        views.setInt(R.id.widget_civil_sec, "setMaxWidth", secondsMaxWidth)

        // 日期与经纬度同一行。两个都是「小字」，但**必须一起缩**：
        // 早先只让日期按可用宽度收缩、并允许缩到 8dp，而经纬度是定死的 10dp，于是窄一点的
        // 卡片上日期那行明显比旁边的经纬度、比下面的逐时标签小一截（真机 P40 Pro 上肉眼可见）。
        // 现在按两者在自然字号（11dp / 10dp）下需要的总宽度算一个统一系数，一起缩放，
        // 下限 0.85（日期 ≈ 9.4dp、经纬度 ≈ 8.5dp），比例始终与设计一致。
        //
        // 注意下发时用 **dp** 而不是 px：布局里其它小字都是 dp，由桌面按**它自己**的密度换算成
        // 像素；而本进程拿到的 density 可能和桌面不同（真机 P40 Pro 系统显示大小 450dpi、
        // 物理 530dpi，桌面按 530 渲染）。用 px 下发会让这一行比同样标称 11dp 的标签小 ~15%。
        val dateNaturalDp = DATE_TEXT_DP
        val coordNaturalDp = COORD_TEXT_DP
        val dateNaturalWidth = measureTextWidth(date, dateNaturalDp, metrics)
        val coordNaturalWidth = if (coordinates.isEmpty()) 0f else measureTextWidth(coordinates, coordNaturalDp, metrics)
        val dateGapPx = if (coordinates.isEmpty()) 0f else COORD_GAP_DP * density
        val rowAvailablePx = totalWidthPx - chromeDp * density
        // 空间不够时先保「日期/天气」，其次才保经纬度；不再有第三个（来源署名）要权衡。
        // 宁可少一个次要信息，也不要让日期被压缩成省略号。
        val showCoordinates = SmallRowLayout.shouldShowTrailing(
            leadingWidthPx = dateNaturalWidth,
            trailingWidthPx = coordNaturalWidth,
            gapPx = dateGapPx,
            availablePx = rowAvailablePx,
        )
        val dateScale = if (dateNaturalWidth <= rowAvailablePx) {
            1f
        } else {
            (rowAvailablePx / dateNaturalWidth).coerceIn(MIN_SMALL_TEXT_SCALE, 1f)
        }
        views.setTextViewTextSize(R.id.widget_civil_date, TypedValue.COMPLEX_UNIT_DIP, dateNaturalDp * dateScale)
        views.setViewVisibility(
            R.id.widget_coordinates,
            if (showCoordinates) View.VISIBLE else View.GONE,
        )
        if (showCoordinates) {
            views.setTextViewTextSize(R.id.widget_coordinates, TypedValue.COMPLEX_UNIT_DIP, coordNaturalDp)
        }
        Log.d(
            TAG,
            "smallText date=${"%.2f".format(Locale.ROOT, dateNaturalDp * dateScale)}dp " +
                "coord=${if (showCoordinates) "%.2f".format(Locale.ROOT, coordNaturalDp) else "hidden"} " +
                "scale=${"%.3f".format(Locale.ROOT, dateScale)} " +
                "dateW=${dateNaturalWidth.toInt()} coordW=${coordNaturalWidth.toInt()} avail=${rowAvailablePx.toInt()}",
        )
        return mainPx
    }

    /** 用与小字相同的字体度量量出某段文字的宽度（px）。 */
    private fun measureTextWidth(text: String, sizeDp: Float, metrics: DisplayMetrics): Float {
        val paint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            textSize = dpToPx(sizeDp, metrics)
            fontFeatureSettings = "tnum"
        }
        return paint.measureText(text)
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

    /**
     * dp → px。
     *
     * 小组件里**一律按 dp 换算，不用 sp**：桌面单元格的尺寸是固定的，而 sp 会跟着系统「字体大小」
     * 一起放大（有些人会把它调到 1.3～2 倍），字号一涨排版就被挤出格子、甚至把时钟裁掉。
     * 布局里的 `textSize` 也全部写成了 dp，见 `res/layout/widget_solar_time*.xml`。
     */
    private fun dpToPx(dp: Float, metrics: DisplayMetrics): Float =
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, dp, metrics)

    /**
     * 桌面进程**真正**用来把 dp 换算成像素的密度（本进程的 `DisplayMetrics.density` 未必是它）。
     *
     * EMUI 的「显示大小」/ 长辈关怀会把 `densityDpi` 抬到出厂 dpi 之上（这台 ELS-AN00：450 → **600**），
     * 本进程跟着变成 600（density 3.75），但**桌面进程仍按出厂 dpi（`Secure.init_dpi` = 530）渲染 dp**。
     * 实测：显示大小 600 时小组件里 11dp 的标签渲染成 33px（= 3.31 px/dp），与 450 时的 28px
     * 呈 3.31/2.81 的比例 —— 桌面用的是 530 这一档，不是 600。
     *
     * 用本进程密度算主时钟的 px，字号会大 13%；再叠加桌面回报的格子宽度也按另一套密度算
     * （见 [clockSafetyFactor]），主时钟就撑破栏宽 —— 表现就是「11:46」被裁成「11:4」、秒整段消失、
     * 变高的时钟行再把逐时行挤出格子（只露出半个「18°」）。
     */
    /**
     * 诊断页用：把「测量与密度」这一块算出来（只读、全程兜异常）。
     * 这些都是 [WidgetUpdater] 内部真正在用的值，和 logcat 的 `SolarWidget` 行同源。
     */
    internal fun metricsSummary(context: Context): List<Pair<String, String>> = runCatching {
        val dm = context.resources.displayMetrics
        val metrics = renderMetrics(context)
        val factory = factoryDensity(context)
        listOf(
            "dm.density" to dm.density.toString(),
            "renderDensity(实际使用)" to metrics.density.toString(),
            "dm.densityDpi" to dm.densityDpi.toString(),
            "dm.scaledDensity" to dm.scaledDensity.toString(),
            "fontScale" to context.resources.configuration.fontScale.toString(),
            "init_dpi" to settingValue(context, "secure", "init_dpi"),
            "factoryDensity = init_dpi/160" to factory.toString(),
            "init_dpi 可用" to if (factory in MIN_DENSITY..MAX_DENSITY) "是" else "否（改用 dm.density）",
            "display_density_forced" to settingValue(context, "secure", "display_density_forced"),
            "屏幕 px" to (dm.widthPixels.toString() + "x" + dm.heightPixels),
            "屏幕 dp" to ((dm.widthPixels / metrics.density).toInt().toString() + "x" +
                (dm.heightPixels / metrics.density).toInt()),
            "cellWidthDp(默认宽度)" to cellWidthDp(metrics, 0).toString(),
            "clockSafetyFactor" to clockSafetyFactor(context, metrics).toString(),
            "boldWidthFactor" to boldWidthFactor(context).toString(),
            "竖向自适应生效" to if (verticalFitEnabled(context)) "是（显示密度高于出厂）" else "否",
            "API<31 跳过 setGravity" to if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) "是" else "否",
        )
    }.getOrElse { listOf("读取失败" to DiagStore.describe(it)) }

    /** 读一个系统设置键；不存在返回字符串 `null`（诊断页要求显式显示 null）。 */
    private fun settingValue(context: Context, namespace: String, key: String): String = runCatching {
        val value = if (namespace == "system") {
            Settings.System.getString(context.contentResolver, key)
        } else {
            Settings.Secure.getString(context.contentResolver, key)
        }
        value ?: "null"
    }.getOrElse { "读取失败: " + DiagStore.describe(it) }

    /** 竖向自适应是否会对这台机器生效：显示密度被抬到出厂密度之上（老系统没有 init_dpi 时为 false）。 */
    internal fun verticalFitEnabled(context: Context): Boolean = runCatching {
        val raw = context.resources.displayMetrics.density
        val factory = factoryDensity(context)
        factory in MIN_DENSITY..MAX_DENSITY && raw > factory + 0.01f
    }.getOrDefault(false)

    private fun renderMetrics(context: Context): DisplayMetrics {
        val base = context.resources.displayMetrics
        val baseDensity = base.density.takeIf { it.isFinite() && it > 0f } ?: MIN_DENSITY
        val factory = factoryDensity(context)
        // 只在出厂密度「看起来合理」时才夹取。`init_dpi` 缺失（部分 HyperOS / 原生）或被人为改成
        // 0 / 极小值时，绝不能把 density 夹成 0 —— 那会让 dpToPx、字号、setMaxWidth 全变 0，
        // 整张卡片一片空白（用户报过的「只有标准时间、真太阳时 00:00、其余全空」就是这个量级的事故）。
        val density = if (factory in MIN_DENSITY..MAX_DENSITY) minOf(baseDensity, factory) else baseDensity
        val safe = density.coerceIn(MIN_DENSITY, MAX_DENSITY)
        if (safe == base.density) return base
        return DisplayMetrics().also {
            it.setTo(base)
            it.density = safe
            it.scaledDensity = safe * (base.scaledDensity / baseDensity)
        }
    }

    /** 出厂 dpi（`Secure.init_dpi`，EMUI 才有）折算的密度；读不到返回 0（= 不做任何假设）。 */
    private fun factoryDensity(context: Context): Float = runCatching {
        Settings.Secure.getInt(context.contentResolver, "init_dpi")
    }.getOrNull()?.takeIf { it > 0 }?.div(160f) ?: 0f

    /**
     * 小组件文字真正用的 Typeface（`res/font/card_sans_widget` → `card_sans_medium.ttf`）。
     *
     * 量字号比例必须用它：系统 `sans-serif-medium` 的数字比 Noto 窄约 6%，
     * 拿它算出来的「秒」宽度会把两位秒裁成一位。取不到时退回系统字面（不崩）。
     */
    private fun widgetTypeface(context: Context): Typeface = runCatching {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.resources.getFont(R.font.card_sans_medium)
        } else {
            Typeface.create("sans-serif-medium", Typeface.NORMAL)
        }
    }.getOrElse { Typeface.create("sans-serif-medium", Typeface.NORMAL) }

    /**
     * 桌面回报的格子宽度（dp），按「屏幕在桌面渲染空间里的 dp 宽」封顶。
     *
     * 显示大小被抬到出厂 dpi 之上时，桌面回报的宽度是按**另一套密度**折出来的：格子 1134px
     * 回报成 384dp（= 2.95 px/dp），而桌面实际按 3.31 px/dp 渲染、本进程是 3.75 —— 三方都不一致。
     * 封顶之后再配 [clockSafetyFactor] 的余量，主时钟在长辈模式下也不会超出栏宽。
     */
    private fun cellWidthDp(metrics: DisplayMetrics, widthDp: Int): Float {
        // 桌面的格子两侧还有一圈内缩（华为 1200px 屏上格子 1134px），所以不能直接拿整屏宽度封顶。
        val density = metrics.density.takeIf { it.isFinite() && it > 0f } ?: MIN_DENSITY
        val screenPx = metrics.widthPixels.coerceAtLeast(1)
        val screenDp = screenPx / density.coerceIn(MIN_DENSITY, MAX_DENSITY) * CELL_SCREEN_FRACTION
        val reported = if (widthDp > 0) widthDp.toFloat() else DEFAULT_WIDGET_WIDTH_DP
        // 下限 100dp：任何异常（宽高为 0、密度荒谬）都不许把格子宽度算成 0，否则字号一起归零。
        return minOf(reported, screenDp).coerceIn(MIN_CELL_WIDTH_DP, MAX_CELL_WIDTH_DP)
    }

    /**
     * 主时钟的宽度余量：显示大小被抬到出厂 dpi 之上时留 10%。
     *
     * 那种情况下桌面回报的格子 dp 与它自己的渲染密度不是同一套（见 [cellWidthDp]），
     * 折算出来仍会偏宽约 7%；宁可时钟略小一圈，也不要裁掉最后一位数字或整段秒。
     * 显示大小 ≤ 出厂 dpi（绝大多数机器、以及本机 450 档）时余量为 1，行为与改造前完全一致。
     */
    private fun clockSafetyFactor(context: Context, metrics: DisplayMetrics): Float {
        val factory = factoryDensity(context)
        // 注意比的是**本进程**的密度：传进来的 metrics 已经换成「桌面渲染密度」，与出厂 dpi 相等，
        // 拿它比较永远判成「没被抬高」，余量就白设了。
        val overridden = factory > 0f && context.resources.displayMetrics.density > factory + 0.01f
        return if (overridden) LARGE_DISPLAY_CLOCK_SAFETY else 1f
    }

    /**
     * 华为「字体粗细」（`Settings.System.font_weight_scale`）带来的**字宽放大系数**。
     *
     * EMUI 的加粗是渲染层描粗，笔画变粗的同时**推进宽度也会涨一点**：同一串数字实测
     * 0.79 → 1.18 时主时钟「12:33」的推进宽度 +4.1%，拖到最右 **1.59** 时 +8.5%。
     * 栏宽是固定的、主时钟又正好铺满栏宽 —— 于是最粗档「秒」被挤出栏宽，两位秒只剩一位
     * （实测 `12:33:5` / `12:54:1`）。这里把字重折成宽度系数：主时钟按它缩、秒宽按它放宽。
     *
     * 基准取 **1.0**：`font_weight_scale ≤ 1.0` 一律 1.0（默认档 0.79、长辈关怀档 1.0 都走这条，
     * 与改造前逐像素一致）；1.0 以上每 +1.0 字重加 22%，封顶 1.10（覆盖实测最粗的 1.59）。
     * **缺这个键**（小米 / 原生）直接返回 1.0 —— 零影响。
     */
    private fun boldWidthFactor(context: Context): Float {
        // 通道 1（华为 EMUI / HarmonyOS）：乘法字重 font_weight_scale，>1.0 才算加粗。
        val huawei = runCatching {
            Settings.System.getFloat(context.contentResolver, WEIGHT_SCALE_KEY)
        }.getOrNull()?.takeIf { it.isFinite() }?.let { w ->
            (1f + (w - 1f).coerceAtLeast(0f) * BOLD_WIDTH_PER_WEIGHT_UNIT).coerceAtMost(BOLD_WIDTH_MAX)
        } ?: 1f
        // 通道 2（AOSP / HyperOS / 原生）：加性字重偏移 font_weight_adjustment，0~1000，
        // 1000 就是「最粗」。红米实测：这个键设成 1000 时，只读华为键的实现会把秒裁成一位。
        val aosp = runCatching {
            Settings.Secure.getInt(context.contentResolver, WEIGHT_ADJUSTMENT_KEY)
        }.getOrDefault(0).let { adj ->
            if (adj <= 0) 1f else {
                val t = (adj.coerceAtMost(AOSP_ADJUSTMENT_MAX.toInt()) / AOSP_ADJUSTMENT_MAX)
                1f + t * (AOSP_BOLD_WIDTH_MAX - 1f)
            }
        }
        return maxOf(huawei, aosp).coerceAtMost(AOSP_BOLD_WIDTH_MAX)
    }

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
                    civilOffsetMillis = civilOffsetMillis(now, civilZoneOf(context, place, now)),
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

    private val HOUR_TEMP_IDS = intArrayOf(
        R.id.widget_hour_cond_0,
        R.id.widget_hour_cond_1,
        R.id.widget_hour_cond_2,
        R.id.widget_hour_cond_3,
        R.id.widget_hour_cond_4,
        R.id.widget_hour_cond_5,
    )

    private val HOUR2_LABEL_IDS = intArrayOf(
        R.id.widget_hour2_label_0,
        R.id.widget_hour2_label_1,
        R.id.widget_hour2_label_2,
        R.id.widget_hour2_label_3,
        R.id.widget_hour2_label_4,
        R.id.widget_hour2_label_5,
    )

    private val HOUR2_ICON_IDS = intArrayOf(
        R.id.widget_hour2_icon_0,
        R.id.widget_hour2_icon_1,
        R.id.widget_hour2_icon_2,
        R.id.widget_hour2_icon_3,
        R.id.widget_hour2_icon_4,
        R.id.widget_hour2_icon_5,
    )

    private val HOUR2_TEMP_IDS = intArrayOf(
        R.id.widget_hour2_cond_0,
        R.id.widget_hour2_cond_1,
        R.id.widget_hour2_cond_2,
        R.id.widget_hour2_cond_3,
        R.id.widget_hour2_cond_4,
        R.id.widget_hour2_cond_5,
    )

    /** 一排逐时格子的三条 id（行容器 + 时刻 + 图标 + 气温）。 */
    private class HourRow(
        val rowId: Int,
        val labelIds: IntArray,
        val iconIds: IntArray,
        val tempIds: IntArray,
    ) {
        val size: Int get() = labelIds.size
    }

    private val FIRST_HOUR_ROW = HourRow(R.id.widget_hour_row, HOUR_LABEL_IDS, HOUR_ICON_IDS, HOUR_TEMP_IDS)
    private val SECOND_HOUR_ROW = HourRow(R.id.widget_hour_row2, HOUR2_LABEL_IDS, HOUR2_ICON_IDS, HOUR2_TEMP_IDS)

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
        // 记一笔「这次请求从几个实例开始」，桌面添加完成后会把前台切成桌面、我们的界面被盖住，
        // 没法当场等结果，只能等用户回到 App 再结算（见 [consumePinOutcome]）。
        pinPrefs(context).edit()
            .putInt(KEY_PIN_BASELINE, pinnedCount(context))
            .putLong(KEY_PIN_STARTED, System.currentTimeMillis())
            .putBoolean(KEY_PIN_PENDING, true)
            .apply()
        // 部分启动器（如华为桌面）不会回调成功事件，是否真的加上去由调用方比对实例数判断。
        return runCatching { manager.requestPinAppWidget(provider, null, null) }.getOrDefault(false)
    }

    /** 「添加到桌面」的结算结果。 */
    enum class PinOutcome { ADDED, NOT_ADDED }

    /**
     * 结算上一次「添加到桌面」请求；没有待结算的请求时返回 null。
     *
     * 桌面添加成功后会直接把桌面切到前台，我们的界面在后台，所以这里只在**用户回到 App 之后**
     * 比对实例数。请求刚发出不到 [PIN_SETTLE_MIN_MILLIS] 时不结算 —— 用户可能还在确认框上。
     */
    fun consumePinOutcome(context: Context): PinOutcome? {
        val prefs = pinPrefs(context)
        if (!prefs.getBoolean(KEY_PIN_PENDING, false)) return null
        val baseline = prefs.getInt(KEY_PIN_BASELINE, 0)
        val now = pinnedCount(context)
        if (now > baseline) {
            prefs.edit().putBoolean(KEY_PIN_PENDING, false).apply()
            return PinOutcome.ADDED
        }
        val startedAt = prefs.getLong(KEY_PIN_STARTED, 0L)
        if (System.currentTimeMillis() - startedAt < PIN_SETTLE_MIN_MILLIS) return null
        prefs.edit().putBoolean(KEY_PIN_PENDING, false).apply()
        return PinOutcome.NOT_ADDED
    }

    private fun pinPrefs(context: Context) =
        context.applicationContext.getSharedPreferences(PIN_PREFS, Context.MODE_PRIVATE)

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
     * 是不是平板级的宽屏（sw ≥ 600dp）。平板的桌面单元格比手机高得多（实测一格 143dp vs
     * 手机约 111dp），但上报口径两边都按「一格 70dp」算，所以高度这一路判断在平板上偏保守。
     */
    private fun isLargeScreen(context: Context): Boolean =
        context.resources.configuration.smallestScreenWidthDp >= 600

    /**
     * 卡片左栏「标准时间」用的时区，取**观测点所在地**的标准时，而不是手机所在的时区。
     *
     * 中国境内钉在 `Asia/Shanghai`（含港澳台与新疆，不按经度算）；境外优先用设备时区
     * （人在当地时手机通常已自动切换，还能顺带照顾夏令时），当设备时区与观测点的标准偏移
     * 对不上时（人在国内、手工指定了纽约坐标）退到固定的 `GMT±HH:MM`，两者口径见 [LocalZone]。
     */
    private fun civilZoneOf(context: Context, place: Place, now: Instant): ZoneId =
        LocalZone.zoneIdFor(context, place, now)

    /**
     * 手工指定过坐标时，App 与小组件一律按它显示，连系统最近一次定位都不看；
     * 其余情况跟随 GPS（与 App 内判定一致）。
     */
    internal fun followsSystemFix(source: PlaceSource): Boolean = source != PlaceSource.MANUAL

    private fun resolveLocation(context: Context): LocationState {
        val settings = AppSettings(context)
        val saved = settings.place
        if (!followsSystemFix(saved.source)) return LocationState(saved, hasFix = true)

        // 卡片可见时每 5 分钟主动取一次定位：整分 tick 每分钟都会跑到这里，
        // 若每次都取会把定位唤醒放大到每分钟一次。
        requestWidgetFixIfDue(context, settings)

        val fix = LocationTracker(context).lastKnownLocation()
        if (fix != null) {
            val place = Place(fix.latitude, fix.longitude, PlaceSource.GPS, context.getString(R.string.gps_label))
            return LocationState(place, hasFix = true)
        }
        // 没有实时定位时，只有「历史上确实拿到过 GPS 定位」才继续用它；默认坐标不算有效定位。
        //
        // 「跟随 GPS」的判定必须与 App 内一致：**有定位权限**且**不是手工指定坐标**。
        // App 启动时就是按 `hasPermission() && source != MANUAL` 决定要不要开启跟踪、要不要进
        // 「等待定位」的；早先这里只看 source，于是在没给定位权限的机器上，主页拿默认坐标照常
        // 显示内容、桌面卡片却全变成占位符（用户报「为什么两边显示不一样」）。
        val followingGps = LocationTracker(context).hasPermission() &&
            saved.source != PlaceSource.MANUAL
        val hasFix = hasValidFix(
            followingGps = followingGps,
            hadFix = saved.source == PlaceSource.GPS,
            fixNow = false,
        )
        return LocationState(saved, hasFix)
    }

    /**
     * 桌面卡片侧的定位节奏：最多每 [GPS_FIX_INTERVAL_MILLIS] 取一次。
     *
     * 取到后写回设置（下次直接用 lastKnown），并整体重绘一次卡片。
     * 进程随时可能被回收，所以「上次取定位的时刻」存在偏好里而不是内存里。
     */
    private fun requestWidgetFixIfDue(context: Context, settings: AppSettings) {
        if (gpsFixInFlight) return
        val now = System.currentTimeMillis()
        if (now - settings.lastWidgetFixMillis < GPS_FIX_INTERVAL_MILLIS) return
        settings.lastWidgetFixMillis = now
        gpsFixInFlight = true
        val app = context.applicationContext
        LocationTracker(app).requestSingleFix { fix ->
            gpsFixInFlight = false
            val fresh = Place(
                fix.latitude,
                fix.longitude,
                PlaceSource.GPS,
                app.getString(R.string.gps_label),
            )
            AppSettings(app).place = fresh
            DistrictResolver.requestRefresh(app, fresh)
            WeatherRepository.requestRefresh(app, fresh)
            refreshAll(app)
        }
    }

    private fun openApp(context: Context): Intent =
        Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }

    /** 日期行；还没有有效定位时不带气温（那份气温属于别的城市）。 */
    /**
     * 日期 + 当日天气与温度区间，与首页大卡片同一行结构：
     * 「11月13日 周五 · 17° 小雨 · 14°~19°」。没有有效天气时天气位显示占位符「--」。
     */
    private fun dateText(context: Context, civil: ZonedDateTime, place: Place, hasFix: Boolean): String {
        val date = TimeText.dateShortWithWeekday(context, civil.toLocalDate())
        // 还没定位时不知道是哪里的天气，但这一行不该只剩日期：留个 `--` 占位，
        // 与逐时格子的 `--` 一起表示「在等数据」，版面也保持原样。
        if (!hasFix) return "$date · ${context.getString(R.string.weather_unknown)}"
        val parts = ArrayList<String>(3)
        parts += date
        val weather = WeatherRepository.cached(context, place)?.let {
            context.getString(
                R.string.hero_weather,
                context.getString(R.string.weather_temp, it.temperatureC),
                TimeText.conditionLabel(context, WeatherRepository.conditionOf(it.code)),
            )
        }
        // temperatureRange 返回的是 (最高, 最低)，显示顺序按「低 ~ 高」。
        val range = WeatherRepository.temperatureRange(
            WeatherRepository.hourly(context, place).points,
            civil.toLocalDate(),
            civil.zone,
        )?.let { context.getString(R.string.hero_temp_range, it.second, it.first) }
        // 一个都没有时留占位符，避免这一行只剩日期让人以为坏了。
        parts += weather ?: range ?: context.getString(R.string.weather_unknown)
        if (weather != null && range != null) parts += range
        return parts.joinToString(" · ")
    }
}
