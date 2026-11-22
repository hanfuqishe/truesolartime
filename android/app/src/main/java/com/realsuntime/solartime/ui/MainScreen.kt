package com.realsuntime.solartime.ui

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.pm.PackageManager
import android.os.Build
import android.view.WindowManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import androidx.compose.ui.unit.takeOrElse
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.realsuntime.solartime.BuildConfig
import com.realsuntime.solartime.MainViewModel
import com.realsuntime.solartime.R
import com.realsuntime.solartime.data.LocationAvailability
import com.realsuntime.solartime.data.TakeBand
import com.realsuntime.solartime.data.TakeTemperature
import com.realsuntime.solartime.data.WeatherRepository
import com.realsuntime.solartime.solar.Placeholders
import com.realsuntime.solartime.solar.Shichen
import com.realsuntime.solartime.solar.SolarSnapshot
import com.realsuntime.solartime.solar.SolarTimeMath
import com.realsuntime.solartime.solar.SolarTimeSnapshot
import com.realsuntime.solartime.solar.TimeFormat
import com.realsuntime.solartime.ui.theme.SunColors
import com.realsuntime.solartime.ui.theme.TrueSolarTimeTheme
import com.realsuntime.solartime.ui.theme.softDotStops
import com.realsuntime.solartime.ui.theme.sunDayArcColor
import com.realsuntime.solartime.ui.theme.sunDotColor
import com.realsuntime.solartime.ui.theme.sunDotGlowStops
import com.realsuntime.solartime.widget.ChimeAlarm
import com.realsuntime.solartime.widget.WidgetAxis
import java.time.LocalTime
import kotlin.math.atan2
import kotlin.math.roundToInt
import kotlin.math.sqrt

/** 宽屏断点：内容区达到这个宽度就把大卡片与太阳卡片并排（与鸿蒙版同一条规则：560）。 */
private val WIDE_LAYOUT_MIN_WIDTH = 560.dp
/** 手机版大卡片的实测宽度：并排时按这个逻辑宽度排版卡片内容，再整体缩放到实际宽度。 */
private val PHONE_CARD_WIDTH = 334.dp
/** 并排两张卡之间的间距。 */
private val CARD_GAP = 12.dp
/** 缩放系数区间：小平板上不至于把字缩到看不清，大屏上也不无限放大。 */
private const val MIN_CARD_SCALE = 0.8f
private const val MAX_CARD_SCALE = 1.6f
/** 半高秒与主数字之间的间隔。 */
private val SECONDS_GAP = 1.dp
/** 时间字号上下限：下限保证字不糊，上限避免大屏上数字夸张。 */
private const val FALLBACK_HERO_CLOCK_SP = 42f
/** 撑满时留 3% 余量：算出来的字宽正好等于栏宽，右栏会紧贴卡片边缘，留一点才不会擦到圆角。 */
private const val CLOCK_FIT_SAFETY = 0.97f
private const val MIN_HERO_CLOCK_SP = 24f
private const val MAX_HERO_CLOCK_SP = 80f
/** 太阳卡的内边距（沿用 20dp；圆盘画布铺满卡片内容宽度，标签在里面留白）。 */
private val SUN_CARD_PADDING = 20.dp
/** 标题行与圆盘画布之间的间距。 */
private val SUN_TITLE_GAP = 8.dp
/**
 * 圆盘画布的高度。
 *
 * 卡片是满宽的（手机 280~331dp），正方形画布会把卡片顶到 370dp 上下；改成「满宽 + 定高」的扁画布后，
 * 圆按 `min(w, h)` 取半径，卡片高度反而比带右栏时更低（282dp vs 286dp）。
 */
private val SUN_DIAL_HEIGHT = 194.dp
/** 圆盘画布与下方「白昼」行之间的间距。 */
private val SUN_DAYLIGHT_GAP = 4.dp
/** 外侧时间标签与圆（含表圈）的水平间距。 */
private val SUN_LABEL_GAP = 10.dp
/**
 * 上中天标签底边与圆顶之间的竖直间距（≥ 太阳点光晕外沿 5.5dp，正午的太阳点就在圆顶）。
 */
private val SUN_NOON_LABEL_GAP = 8.dp
/**
 * 短昼保护：日出／日落挤在圆顶附近时，两个标签至少下沉到圆顶下方这么远。
 * 取值 ≈ 标签自身行高（16dp）+ 2dp，保证不和圆顶上方的上中天标签撞在同一行。
 */
private val SUN_LABEL_TOP_INSET = 18.dp
/**
 * 日出／日落标签从交点往上抬这么多，给**延伸后的地平线**让路：
 * 抬 10dp 后文字底边仍在地平线上方 2dp，那条贯穿线就能从标签底下穿过去而不压字。
 */
private val SUN_LABEL_RISE = 10.dp
/** 地平线画满画布（极昼极夜）时，左右各留的内边距。 */
private val SUN_HORIZON_INSET = 4.dp
/** 标签距画布左右边缘的最小留白（要求 ≥8dp）。 */
private val SUN_LABEL_SIDE_INSET = 8.dp
/** 地图视口的宽高比：手机 4:3、平板 16:9（与鸿蒙版一致）。 */
private const val PHONE_MAP_ASPECT_RATIO = 4f / 3f
private const val WIDE_MAP_ASPECT_RATIO = 16f / 9f
/** 未知态占位符的不透明度：比真实读数淡一档，强化「占位」观感。 */
private const val PLACEHOLDER_ALPHA = 0.6f
/**
 * 未知态时钟占位符的字距（em）。
 *
 * 半角 `-` 在拉丁字体里本来就是一短横，字距只要**很小**一点、让一对 `-` 不至于粘成一条长横：
 * 0.06em ≈ 7px（主字号），两个 `-` 之间约 24px、冒号两侧约 17px —— 仍然读得出「两短横 + 冒号」。
 * 再大（试过 0.16em）四个 `-` 会被均匀拉开，看着就是虚线碎片了。
 */
private const val PLACEHOLDER_LETTER_SPACING_EM = 0.06f

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MainScreen(viewModel: MainViewModel = viewModel()) {
    val now by viewModel.now.collectAsStateWithLifecycle()
    val place by viewModel.place.collectAsStateWithLifecycle()
    val trackingGps by viewModel.trackingGps.collectAsStateWithLifecycle()
    val waitingForFix by viewModel.waitingForFix.collectAsStateWithLifecycle()
    // 定位不可用（未知态）：跟随 GPS 却拿不到定位时，界面上不能继续演上一个城市。
    val locationUnknown by viewModel.locationUnknown.collectAsStateWithLifecycle()
    val remindersEnabled by viewModel.remindersEnabled.collectAsStateWithLifecycle()
    val keyTimeChimeEnabled by viewModel.keyTimeChimeEnabled.collectAsStateWithLifecycle()
    val districtName by viewModel.districtName.collectAsStateWithLifecycle()

    val zoneOffsetSeconds by viewModel.zoneOffsetSeconds.collectAsStateWithLifecycle()
    val mapStyle by viewModel.mapStyle.collectAsStateWithLifecycle()
    // 只观察「有效 plan」这一层（源 / 级别 / 降级 / 底图不可用）：瓦片计数怎么变都不重组。
    // 见 MainViewModel.mapUi —— 直接观察 MapFallbackState 会让每块瓦片都触发一次重组。
    val mapUi by viewModel.mapUi.collectAsStateWithLifecycle()
    val mapLoading by viewModel.mapLoading.collectAsStateWithLifecycle()
    val mapReady by viewModel.mapReady.collectAsStateWithLifecycle()
    val keepScreenOn by viewModel.keepScreenOn.collectAsStateWithLifecycle()
    val themeMode by viewModel.themeMode.collectAsStateWithLifecycle()
    val message by viewModel.message.collectAsStateWithLifecycle()

    val context = LocalContext.current

    // 卡片上的城市：
    // ① 未知态（跟随 GPS 但没定位）：不能写「上一个城市」，只写「定位不可用」（可点击去系统设置）；
    // ② 反查到的行政区划优先；
    // ③ 反查还没回来/失败时，只有「预设城市」才回退到城市名；
    // ④ 手工坐标与 GPS 定位没有城市名可用（标签是「手动设置」这类占位词，不该显示），
    //    一律显示减号，等反查结果到了再换成区划名。
    val cityText = if (locationUnknown) {
        stringResource(R.string.location_unavailable)
    } else {
        cityLabel(
            districtName = districtName,
            presetLabel = place.labelResName?.let { TimeText.placeLabel(context, place) },
            unknown = stringResource(R.string.city_unknown),
        )
    }
    val snackbarHostState = remember { SnackbarHostState() }
    var showSettings by rememberSaveable { mutableStateOf(false) }

    // 未知态的标准时间用**系统时区**（不是上一次地点的时区）：只取偏移，太阳相关的读数一律留空。
    val systemOffsetSeconds = remember(now.epochSecond / 60) {
        LocationAvailability.systemOffsetSeconds(now)
    }
    val snapshot = remember(now, place, zoneOffsetSeconds, systemOffsetSeconds, locationUnknown) {
        if (locationUnknown) {
            // 没有坐标：只借 SolarSnapshot 的「标准时钟」口径（lat/lon 传 0，太阳值不显示、也不参与主题）。
            SolarTimeSnapshot.compute(now, 0.0, 0.0, systemOffsetSeconds)
        } else {
            SolarTimeSnapshot.compute(now, place.latitude, place.longitude, zoneOffsetSeconds)
        }
    }

    // 大卡片里的日期、天气、逐时预报与关键时段：半分钟刷新一次就够，不必每秒读偏好；
    // 但新数据一到（例如刚换了城市、天气刚取回来）要立刻重算，所以把天气版本号也当键。
    val weatherRevision = WeatherRepository.revision()
    val heroExtras = if (locationUnknown) {
        // 未知态：日期照常（按系统时区），天气与逐时留空 —— 没有坐标就没有天气。
        remember(now.epochSecond / 30, systemOffsetSeconds) {
            unknownHeroExtras(
                context = context,
                now = now,
                zoneOffsetSeconds = systemOffsetSeconds,
                weatherPlaceholder = Placeholders.weather(),
                temperaturePlaceholder = Placeholders.temperature(),
            )
        }
    } else {
        remember(place, now.epochSecond / 30, weatherRevision, zoneOffsetSeconds) {
            loadHeroExtras(context, place, now, zoneOffsetSeconds)
        }
    }
    // 天气来源（Open-Meteo / 7Timer!）只随缓存版本号变：底部署名跟着它切换，别每秒读一次偏好。
    val weatherSource = remember(weatherRevision) { WeatherRepository.source(context) }

    val locationPermissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions(),
    ) { result ->
        viewModel.markLocationPermissionRequested()
        if (result.values.any { it }) {
            viewModel.startGpsTracking()
        } else {
            viewModel.postMessage(context.getString(R.string.msg_location_permission))
        }
    }

    val requestGps: () -> Unit = {
        val granted = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.ACCESS_FINE_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED
        if (granted) {
            viewModel.startGpsTracking()
        } else {
            // 先把「要跟随 GPS」这个意图落进 ViewModel：没权限时它立刻进未知态
            // （不能一边说要跟随定位、一边继续显示上一个地点的太阳时），再去要权限。
            viewModel.beginGpsFollowingWithoutPermission()
            locationPermissionLauncher.launch(
                arrayOf(
                    Manifest.permission.ACCESS_FINE_LOCATION,
                    Manifest.permission.ACCESS_COARSE_LOCATION,
                ),
            )
        }
    }

    // 未知态的地名「定位不可用」可点击：跳到系统「应用详情 / 权限」页，用户在那里允许定位。
    val openLocationSettings: () -> Unit = {
        viewModel.postMessage(context.getString(R.string.location_unavailable_hint))
        PowerSettings.openAppDetailsSettings(context)
    }

    // 从系统设置回来（刚授权 / 刚撤销定位）：重新核对未知态，别等用户再点一次。
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) {
        viewModel.syncLocationState()
    }

    // 默认跟随 GPS：首次启动自动申请一次定位权限。
    LaunchedEffect(Unit) {
        if (viewModel.shouldRequestLocationPermission()) {
            locationPermissionLauncher.launch(
                arrayOf(
                    Manifest.permission.ACCESS_FINE_LOCATION,
                    Manifest.permission.ACCESS_COARSE_LOCATION,
                ),
            )
        }
    }

    val toggleReminders: (Boolean) -> Unit = { enabled ->
        // 交接提醒只播提示音，不需要通知权限；但需要「闹钟和提醒」才能准时响。
        viewModel.setRemindersEnabled(enabled)
        if (enabled && !ChimeAlarm.canScheduleExact(context)) {
            PowerSettings.openExactAlarmSettings(context)
        }
    }

    val toggleKeyTimeChime: (Boolean) -> Unit = { enabled ->
        // 报时只播提示音，不需要通知权限；但需要「闹钟和提醒」才能准时响。
        viewModel.setKeyTimeChimeEnabled(enabled)
        if (enabled && !ChimeAlarm.canScheduleExact(context)) {
            PowerSettings.openExactAlarmSettings(context)
        }
    }

    LaunchedEffect(message) {
        message?.let {
            snackbarHostState.showSnackbar(it)
            viewModel.consumeMessage()
        }
    }

    // 屏幕常亮：只加窗口标志，退到后台后系统照旧按自己的超时熄屏。
    val hostView = LocalView.current
    LaunchedEffect(keepScreenOn) {
        val window = hostView.context.findActivity()?.window ?: return@LaunchedEffect
        if (keepScreenOn) {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }

    // 主题跟着太阳走：白天浅色，夜晚整体换深色（不再看系统的深色开关）。
    // 设置里选了「亮色/暗色」就忽略日出日落，强制用那一套；默认「自动」= 原来的行为。
    // 未知态没有太阳高度角：按系统时区的钟点粗判昼夜（不能拿上一个地点的太阳高度角来推断）。
    val sunIsUp = if (locationUnknown) {
        LocationAvailability.isDaytime(snapshot.localStandardTime)
    } else {
        snapshot.isDay
    }
    val uiIsDay = !themeMode.isDark(sunIsUp = sunIsUp)
    TrueSolarTimeTheme(darkTheme = !uiIsDay) {
        Scaffold(
            containerColor = MaterialTheme.colorScheme.background,
            snackbarHost = { SnackbarHost(snackbarHostState) },
        ) { padding ->
            // 视口高度：滚动容器的实测高度。宽屏「地图铺满」要用它算剩余空间。
            var viewportPx by remember { mutableIntStateOf(0) }
            // 地图上方内容（标题 + 两卡）与页脚（版本号）的实测高度：
            // 两者都与地图高度无关，因此不会形成测量环。
            var aboveMapPx by remember { mutableIntStateOf(0) }
            var footerPx by remember { mutableIntStateOf(0) }
            BoxWithConstraints(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
                    .onSizeChanged { viewportPx = it.height }
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 20.dp),
            ) {
                // 平板/宽屏：大卡片与太阳卡片并排（1:1、等高），卡片内容整体缩放到手机上那个比例。
                // 先取出来：后面的 `with(density) { ... }` 里 maxWidth 的隐式接收者会变成 Density，
                // 直接用会报「cannot be called with an implicit receiver」。
                val contentWidthDp = maxWidth
                val wide = contentWidthDp >= WIDE_LAYOUT_MIN_WIDTH
                // 自适应缩放：让「卡片的逻辑宽度」恒等于手机卡的 334dp，于是无论平板多宽，
                // 卡片里的版式都和手机一模一样，只是整体按比例放大/缩小。
                // （写死 1.35 会在 640dp 的小平板上出问题：分栏后每张卡只有 294dp，内容会被截断。）
                val cardWidth = (maxWidth - CARD_GAP) / 2
                val cardScale = (cardWidth / PHONE_CARD_WIDTH).coerceIn(MIN_CARD_SCALE, MAX_CARD_SCALE)

                Column {
                    Column(Modifier.onSizeChanged { aboveMapPx = it.height }) {
                    Header(
                        // 只有跟随 GPS 才显示「GPS」徽标；预设城市 / 手动坐标什么都不显示
                        // （地名在下面大卡片里，标题行不占位）。未知态没有定位，同样不显示。
                        badge = if (locationUnknown) {
                            null
                        } else {
                            HeaderBadge.textFor(
                                place.source,
                                stringResource(R.string.location_badge_gps),
                            )
                        },
                        onOpenSettings = { showSettings = true },
                    )
                    Spacer(Modifier.height(12.dp))

                    if (wide) {
                        // IntrinsicSize.Max + fillMaxHeight：两卡取较高的那张作行高，底边自然对齐。
                        // LockedCardDensity 放在 Box 里面（与改动前同一层级）：字体缩放锁死，
                        // 同时几何缩放照旧参与固有测量，IntrinsicSize.Max 不受影响。
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(IntrinsicSize.Max),
                            horizontalArrangement = Arrangement.spacedBy(CARD_GAP),
                        ) {
                            Box(Modifier.weight(1f).fillMaxHeight()) {
                                LockedCardDensity(scale = cardScale) {
                                    HeroCard(
                                        snapshot = snapshot,
                                        districtName = cityText,
                                        coordinates = if (locationUnknown) {
                                            Placeholders.coordinates()
                                        } else {
                                            TimeText.coordinates(context, place.latitude, place.longitude)
                                        },
                                        waitingForFix = waitingForFix,
                                        locationUnknown = locationUnknown,
                                        onLocationUnavailableClick = openLocationSettings,
                                        extras = heroExtras,
                                        isDay = uiIsDay,
                                        hourlyRows = 2,
                                        modifier = Modifier.fillMaxHeight(),
                                    )
                                }
                            }
                            Box(Modifier.weight(1f).fillMaxHeight()) {
                                LockedCardDensity(scale = cardScale) {
                                    SunCard(
                                        snapshot = snapshot,
                                        locationUnknown = locationUnknown,
                                        modifier = Modifier.fillMaxHeight(),
                                    )
                                }
                            }
                        }

                    } else {
                        // 手机：卡片按 100% 排版，字号同样锁死（见 LockedCardDensity）。
                        LockedCardDensity {
                            HeroCard(
                                snapshot = snapshot,
                                districtName = cityText,
                                coordinates = if (locationUnknown) {
                                    Placeholders.coordinates()
                                } else {
                                    TimeText.coordinates(context, place.latitude, place.longitude)
                                },
                                waitingForFix = waitingForFix,
                                locationUnknown = locationUnknown,
                                onLocationUnavailableClick = openLocationSettings,
                                extras = heroExtras,
                                isDay = uiIsDay,
                            )
                        }
                        Spacer(Modifier.height(14.dp))

                        LockedCardDensity {
                            SunCard(snapshot = snapshot, locationUnknown = locationUnknown)
                        }
                    }
                    }

                    // 宽屏铺满：卡片总高 = 视口 − 上方内容 − 页脚（都实测）。
                    // 取 max(比例高度, 剩余高度)：屏幕不够高时退回 16:9，不压扁地图。
                    val density = LocalDensity.current
                    val cardAspectHeight = with(density) {
                        ((contentWidthDp - 40.dp) / WIDE_MAP_ASPECT_RATIO).coerceAtLeast(120.dp)
                    }
                    val fillMapHeight: Dp? = if (!wide) {
                        null
                    } else {
                        val freePx = viewportPx - aboveMapPx - footerPx
                        val freeDp = with(density) { freePx.toDp() }
                        maxOf(freeDp, cardAspectHeight)
                    }

                    Spacer(Modifier.height(14.dp))

                    // 地图卡片同样锁字号：卡上有标题、经纬度、版权三处文本，
                    // 跟着系统放大就会把地图挤小（视口是按 dp 宽高比算的）。
                    LockedCardDensity {
                        MapCard(
                            place = place,
                            ui = mapUi,
                            locationUnknown = locationUnknown,
                            loading = mapLoading,
                            ready = mapReady,
                            isZoomUnavailable = viewModel::isMapZoomUnavailable,
                            onTileEvent = viewModel::onMapTileEvent,
                            onViewportApplied = viewModel::onMapZoomApplied,
                            onUserMapGesture = viewModel::onMapUserGesture,
                            mapAspectRatio = if (wide) WIDE_MAP_ASPECT_RATIO else PHONE_MAP_ASPECT_RATIO,
                            fillHeight = fillMapHeight,
                        )
                    }
                    Spacer(Modifier.height(14.dp))

                    Column(Modifier.onSizeChanged { footerPx = it.height }) {
                    // 页脚与顶部标题不锁：它们不是「版式即内容」的卡片，
                    // 跟随系统字号更符合可读性预期（设置页同理）。
                    // 天气来源随数据源切换（Open-Meteo CC BY 4.0 / 7Timer!），降级后不能还署主源的名。
                    Text(
                        text = stringResource(R.string.version_label, BuildConfig.VERSION_NAME) +
                            " · " + TimeText.weatherAttribution(context, weatherSource),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.fillMaxWidth(),
                    )
                    Spacer(Modifier.height(28.dp))
                    }
                }
            }
        }

        if (showSettings) {
            SettingsSheet(
                place = place,
                locationUnknown = locationUnknown,
                remindersEnabled = remindersEnabled,
                keyTimeChimeEnabled = keyTimeChimeEnabled,
                keepScreenOn = keepScreenOn,
                mapStyle = mapStyle,
                themeMode = themeMode,
                onDismiss = { showSettings = false },
                onRequestGps = {
                    showSettings = false
                    requestGps()
                },
                onApplyManual = { lat, lon, label -> viewModel.applyManualPlace(lat, lon, label) },
                onSelectPreset = viewModel::usePreset,
                onToggleReminders = toggleReminders,
                onToggleKeyTimeChime = toggleKeyTimeChime,
                onSelectMapStyle = viewModel::setMapStyle,
                onToggleKeepScreenOn = viewModel::setKeepScreenOn,
                onSelectTheme = viewModel::setThemeMode,
                    )
        }
    }
}

/**
 * 顶部：标题、副标题，右侧是位置标识与设置按钮。
 *
 * 位置标识与鸿蒙版一致（规则见 [HeaderBadge]）：**只有跟随 GPS 时**才在齿轮左边显示
 * 「GPS」小徽标；预设城市 / 手动坐标传 `null`，那一格**整个不渲染**，标题列自然吃满
 * 剩余宽度，徽标与齿轮之间不会留下空出来的间距。
 */
@Composable
private fun Header(badge: String?, onOpenSettings: () -> Unit) {
    // 页头两行：① 标题 + 齿轮；② 副标题 + GPS 徽标（有才显示）。
    // 右侧是**定宽槽位**（48dp = 齿轮的最小触控宽），齿轮与 GPS 都在槽内居中 →
    // 两者水平中心对齐；不显示 GPS 时槽位仍占位，副标题宽度不会抖。
    // 两行都底对齐，标题底边贴副标题（+2dp），不会因齿轮热区被推远。
    val gearSlot = 48.dp
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 16.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.Bottom,
        ) {
            // 标题与右侧徽标都要限宽：长地名不能把标题挤成一字一行。
            Text(
                text = stringResource(R.string.app_name),
                // 与右侧齿轮图标「等高」：图标 24dp，标题字号 26sp + 行高 1:1（≈26dp 行盒），
                // 实测节点高度 ≈ 齿轮图标高度 + 2dp。保持单行，宽度不够时省略而不是换行。
                style = MaterialTheme.typography.titleLarge.copy(
                    fontSize = 26.sp,
                    lineHeight = 24.sp,
                ),
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f),
            )
            // 齿轮：48dp 触控热区不变，但**图标在热区底部居中**（与标题底边对齐）；
            // 图标放大到 34dp，让它的高度接近标题节点高度（26sp 行盒约 34.7dp），
            // 于是「底边差 0、高度差 ≈ 1dp」，不会再有「齿轮高高在上」。
            Box(
                modifier = Modifier
                    .size(gearSlot)
                    .clickable(onClick = onOpenSettings),
                contentAlignment = Alignment.BottomCenter,
            ) {
                Icon(
                    imageVector = Icons.Outlined.Settings,
                    contentDescription = stringResource(R.string.action_settings),
                    // 线框图标墨迹比实心小一圈：36dp 看着与实心 34dp 相当，仍贴底居中。
                    // 36 × 72/90 ≈ 28.8 → 29dp：线框墨迹高度与标题墨迹（26sp ≈ 72px）齐平。
                    // 线框墨迹底边比盒子底边略高：上移 3dp 让两者墨迹底边齐平。
                    modifier = Modifier
                        .size(29.dp)
                        .offset(y = (-3).dp),
                )
            }
        }
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.Bottom,
        ) {
            Text(
                text = stringResource(R.string.screen_subtitle),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                softWrap = false,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier
                    .weight(1f)
                    .padding(top = 2.dp),
            )
            Box(
                modifier = Modifier.width(gearSlot),
                contentAlignment = Alignment.Center,
            ) {
                if (badge != null) {
                    Text(
                        text = badge,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.primary,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.padding(top = 2.dp),
                    )
                }
            }
        }
    }
}

@Composable
private fun HeroCard(
    snapshot: SolarSnapshot,
    districtName: String?,
    coordinates: String,
    waitingForFix: Boolean,
    /**
     * 定位不可用（未知态）：真太阳时 / 时辰 / 天气 / 逐时 / 经纬度全部换成占位符，
     * 只有标准时间（系统时区）与日期照常显示。
     */
    locationUnknown: Boolean,
    /** 未知态点地名「定位不可用」时执行：跳系统「应用详情 / 权限」页。 */
    onLocationUnavailableClick: () -> Unit,
    extras: HeroExtras,
    /** 卡片该用白天的暖橙底还是夜里的深蓝底：由主题设置 + 太阳高度角共同决定（见 `ThemeMode`）。 */
    isDay: Boolean,
    /** 逐时天气预报画几排（每排 6 格）。手机 1 排；平板宽屏 2 排，填掉卡片被拉高后的空白。 */
    hourlyRows: Int = 1,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    // 真太阳时有读数吗：未知态 / 还没等到首个 fix 都没有 —— 所有「按太阳算出来的」东西一律留空。
    val showPlaceholders = locationUnknown || waitingForFix
    val solarSeconds = snapshot.trueSolarTime.toSecondOfDay().toDouble()
    // 真太阳时落在关键时间段里时，数字与时间轴圆点一起换成该时段的配色。
    val inKeyTime = !showPlaceholders && extras.bands.any { it.contains(solarSeconds / 60.0) }
    val accent = HeroPalette.accent(isDay)
    // 关键时段的色段一直画出来（与桌面卡片一致），只有「当前正落在某个关键时段里」时才把
    // 真太阳时数字与时间轴圆点也换成该时段的配色。
    val bandTint = if (showPlaceholders) null else HeroPalette.band(extras.temperature, isDay)
    val inkTint = if (showPlaceholders) null else HeroPalette.ink(extras.temperature, isDay)
    val solarColor = if (inKeyTime) inkTint ?: accent else accent
    val dateTail = listOf(extras.dateText, extras.weatherText, extras.rangeText)
        .filter { it.isNotBlank() }
        .joinToString(" · ")
    // 地名可点击：只有未知态才有这个入口（其它情况的地区名只是文字）。
    val unavailableHint = stringResource(R.string.location_unavailable_hint)
    val cityClickModifier = if (locationUnknown) {
        Modifier.clickable(onClickLabel = unavailableHint, onClick = onLocationUnavailableClick)
    } else {
        Modifier
    }

    Box(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(18.dp))
            .background(Brush.linearGradient(HeroPalette.gradient(isDay)))
            .padding(16.dp),
    ) {
        Column(modifier = Modifier.fillMaxWidth()) {
            // 顶部这一行（`UTC+8` · 地区 · `真太阳时` · 时辰）是**整行一个逻辑单元**：四段文本的
            // 相对位置随行宽分 4 档退化，规则在 SmallRowLayout.cityRowTier 里（纯函数，有单测）：
            //   档 0 左半 `UTC` 贴左、地区贴右｜右半 `真太阳时` 贴左、时辰贴右（两半各占整行一半）；
            //   档 1 收掉「真太阳时」：`UTC` 贴左、地区在 UTC 与时辰之间居中、时辰贴右；
            //   档 2 再收掉 UTC：地区贴左、时辰贴右；
            //   档 3 同档 2，地区尾部省略号。
            // 这一行必须横跨整行、放在下方两列时间内容的上方 —— 档 1 的「居中」是相对整行说的，
            // 仍嵌在左半列里就没有可居中的余地。
            // 行宽只能用 onSizeChanged 取（不能用 BoxWithConstraints：卡片在 IntrinsicSize.Max 里，
            // SubcomposeLayout 参与固有测量会抛异常），再用 TextMeasurer 量各段文本的自然宽度。
            var cityRowWidthPx by remember { mutableStateOf(0f) }
            val cityRowMeasurer = rememberTextMeasurer()
            // 字重显式写死（labelMedium 的默认值就是 Medium），并用 cardFontWeight 抵掉系统
            // 「粗体字」的字重调整：不抵掉的话同一行在这台机器上比在别的机器上宽，
            // 四档退化会提前/延后。
            val cityRowStyle = cardTextStyle(MaterialTheme.typography.labelMedium, FontWeight.Medium)
            val cityRowGap = 8.dp
            val cityRowGapPx = with(LocalDensity.current) { cityRowGap.toPx() }
            // 档 0 左半：地区文字与竖线之间留出的间隙。竖线正落在两半分界上，
            // 右半「真太阳时」从分界右侧 8dp 起排，左侧再留 6dp，线两侧都不会贴着字。
            val cityEndInset = 6.dp
            val cityEndInsetPx = with(LocalDensity.current) { cityEndInset.toPx() }
            val utcLabel = TimeFormat.utcOffsetLabel(snapshot.localOffsetSeconds)
            val cityLabel = districtName ?: ""
            val solarLabel = stringResource(R.string.widget_label_solar)
            // 时辰只显示时辰名（如「亥时」／英文 "Hai hour"），与桌面卡片共用本地化字符串；
            // `snapshot.shichenName` 是固定的中文名，不能直接用，否则英文界面下两边写法不一致。
            // 时初／时正（`snapshot.shichenHalf`）仍照旧算着，只是不再显示。
            // 未知态没有真太阳时，也就没有时辰 —— 显示 `--`。
            val shichenLabel = if (showPlaceholders) {
                Placeholders.shichen()
            } else {
                TimeText.shichenName(context, snapshot.shichenIndex)
            }
            val utcWidthPx = cityRowMeasurer.measure(utcLabel, cityRowStyle).size.width.toFloat()
            val cityWidthPx = if (cityLabel.isEmpty()) {
                0f
            } else {
                // 档 0 里地区右侧还要让出 cityEndInset，判档时一并算进宽度，
                // 否则那一档会「看起来刚好放下、实际被挤掉 6dp」。
                cityRowMeasurer.measure(cityLabel, cityRowStyle).size.width.toFloat() +
                    cityEndInsetPx
            }
            val solarLabelWidthPx =
                cityRowMeasurer.measure(solarLabel, cityRowStyle).size.width.toFloat()
            val shichenWidthPx =
                cityRowMeasurer.measure(shichenLabel, cityRowStyle).size.width.toFloat()
            val cityRowTier = SmallRowLayout.cityRowTier(
                wUtc = utcWidthPx,
                wCity = cityWidthPx,
                // 档 0 右半的内容从分界处起排，分界处还要留一个间距，这里一并算进标签宽度。
                wLabel = solarLabelWidthPx + cityRowGapPx,
                wShichen = shichenWidthPx,
                rowWidth = cityRowWidthPx,
                gap = cityRowGapPx,
            )

            // 兜底的一档：到了档 1~3，「地区名」已经被挤成整行里唯一可压缩的文本。
            // 这时不再只靠省略号砍字尾，而是**按自己这一行的可用宽度反算字号**：
            // 缩小到放得下为止（下限 MIN_FIT_FONT_SIZE），连下限都放不下才交给省略号。
            // 行高不跟着变（见 fitTextStyle），所以标签行高度、下面两列与竖线的位置都不动。
            // 档 0 是「两半各自排」的宽屏形态，地区只在半行里有固定权位，维持原来的省略号策略。
            val cityFitStyle = when (cityRowTier) {
                0 -> cityRowStyle
                1 -> fitTextStyle(
                    measurer = cityRowMeasurer,
                    text = cityLabel,
                    style = cityRowStyle,
                    maxWidthPx = (
                        cityRowWidthPx - utcWidthPx - shichenWidthPx - cityRowGapPx * 2f
                        ).coerceAtLeast(0f),
                )
                else -> fitTextStyle(
                    measurer = cityRowMeasurer,
                    text = cityLabel,
                    style = cityRowStyle,
                    maxWidthPx = (cityRowWidthPx - shichenWidthPx - cityRowGapPx).coerceAtLeast(0f),
                )
            }

            // 竖分隔线的上端跟着档位走：
            //   档 0 —— 标签行仍是左右两半（左半地区贴右、右半「真太阳时」贴左），两半的分界就是
            //           下面两列的分界，所以线要从标签行顶部一路画下来才连得上；
            //   档 1~3 —— 标签行已合并成一整行，线只盖下方两列（与以前一样）。
            // 两段线共用下面这套尺寸（左右各让 12dp，中心仍落在整行 50% 上）。
            val dividerColor = Color(0x33FFFFFF)
            val dividerWidth = 1.dp
            val dividerSideInset = 12.dp
            // 两列行里的那条线从 3dp 处起画，档 0 的上延段要接到它的顶端，所以多补 3dp。
            val dividerTopPadding = 3.dp
            val dividerColumnHeight = 58.dp
            var labelRowHeightPx by remember { mutableStateOf(0f) }
            // 时钟行的实际高度（px）。竖线的长度要跟着它走，不能写死：
            // 长辈关怀里「显示大小」被抬到 600dpi，卡片在 dp 上变窄（387dp → 280dp），
            // HeroClock 按栏宽自动缩了字号，时钟行只剩 ~39dp 高，而线还是 58dp ——
            // 于是线比整行时钟还长，上下都戳出来。做法与标签行一致：onSizeChanged 量到真实高度，
            // 线的长度取 min(58dp, 时钟行高)。常规档时钟行 58.3dp > 58dp，取 58dp，
            // 与改造前逐像素一致；只有时钟行更矮时才跟着缩。
            // 不能用 BoxWithConstraints / SubcomposeLayout：卡片在宽屏分支里处于
            // IntrinsicSize.Max 下，SubcomposeLayout 参与固有测量会抛异常。
            var clockRowHeightPx by remember { mutableStateOf(0f) }
            val dividerHeight = if (clockRowHeightPx > 0f) {
                with(LocalDensity.current) { clockRowHeightPx.toDp() }
                    .coerceAtMost(dividerColumnHeight)
            } else {
                dividerColumnHeight
            }
            // 上延段的顶端要和**标签文字的上沿**齐平（不是标签行的顶边）：文字画在行盒（lineHeight）
            // 里、上下各留一半行距，所以字形上沿比行盒顶边还要低 (行高 − 字号) / 2；
            // 标签行万一比文本本身更高（居中对齐），再补上差值的一半。
            // 字号/行高都从同一套 style 里取；卡片内 fontScale 已锁成 1，所以这里的 px 与
            // 系统字体缩放无关。
            val insetDensity = LocalDensity.current
            val labelTextHeightPx = cityRowMeasurer
                .measure(solarLabel, cityRowStyle, maxLines = 1)
                .size.height.toFloat()
            val labelFontSizePx = with(insetDensity) { cityRowStyle.fontSize.toPx() }
            val labelLineHeightPx = with(insetDensity) {
                cityRowStyle.lineHeight.takeOrElse { cityRowStyle.fontSize }.toPx()
            }
            val dividerTopInsetPx = ((labelLineHeightPx - labelFontSizePx) / 2f).coerceAtLeast(0f) +
                ((labelRowHeightPx - labelTextHeightPx) / 2f).coerceAtLeast(0f)
            // 标签行与两列放进同一个 Box，档 0 那条线才能当 overlay 画到标签行顶部。
            // 高度只能用 onSizeChanged 量（不能用 BoxWithConstraints：卡片在 IntrinsicSize.Max 里，
            // SubcomposeLayout 参与固有测量会抛异常）。
            Box(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.fillMaxWidth()) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .onSizeChanged {
                                cityRowWidthPx = it.width.toFloat()
                                labelRowHeightPx = it.height.toFloat()
                            },
                        verticalAlignment = Alignment.CenterVertically,
                        // 档 0 是两半各自排（间距在两半内部），档 1~3 才需要元素之间统一留间距。
                        horizontalArrangement = if (cityRowTier == 0) {
                            Arrangement.Start
                        } else {
                            Arrangement.spacedBy(cityRowGap)
                        },
                    ) {
                        if (cityRowTier == 0) {
                            // 档 0：左右两半各占整行一半（与下面两列等宽）。
                            // 左半 `UTC` 贴左、地区贴右（贴着两半的分界）；右半「真太阳时」贴左、时辰贴右。
                            Row(
                                modifier = Modifier.weight(1f),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(cityRowGap),
                            ) {
                                Text(
                                    text = utcLabel,
                                    style = cityRowStyle,
                                    color = HeroPalette.LABEL,
                                    maxLines = 1,
                                )
                                Text(
                                    text = cityLabel,
                                    style = cityRowStyle,
                                    color = HeroPalette.LABEL_DIM,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                    textAlign = TextAlign.End,
                                    // 吃满 UTC 之后的剩余宽度，`TextAlign.End` 才有把文字推到分界处的余量；
                                    // 尾部再让出 6dp，地区与竖线之间留出明显间隙（不与线贴在一起）。
                                    modifier = Modifier
                                        .weight(1f)
                                        .padding(end = cityEndInset)
                                        .then(cityClickModifier),
                                )
                            }
                            Row(
                                modifier = Modifier
                                    .weight(1f)
                                    // 两半各自贴着分界，这里再留一个间距，否则地区与「真太阳时」会挤在一起。
                                    .padding(start = cityRowGap),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(cityRowGap),
                            ) {
                                Text(
                                    text = solarLabel,
                                    style = cityRowStyle,
                                    color = HeroPalette.LABEL,
                                    maxLines = 1,
                                )
                                Text(
                                    text = shichenLabel,
                                    style = cityRowStyle,
                                    color = HeroPalette.LABEL_DIM,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                    textAlign = TextAlign.End,
                                    modifier = Modifier.weight(1f),
                                )
                            }
                        } else {
                            // 档 1：收掉「真太阳时」，整行当一个整体 —— UTC 贴左、时辰贴右、地区居中。
                            // 档 2/3：再收掉 UTC —— 地区贴左（档 3 尾部省略号）。任何档位时辰都贴整行最右。
                            if (cityRowTier == 1) {
                                Text(
                                    text = utcLabel,
                                    style = cityRowStyle,
                                    color = HeroPalette.LABEL,
                                    maxLines = 1,
                                )
                            }
                            Text(
                                text = cityLabel,
                                style = cityFitStyle,
                                color = HeroPalette.LABEL_DIM,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                                textAlign = if (cityRowTier == 1) TextAlign.Center else TextAlign.Start,
                                modifier = Modifier.weight(1f).then(cityClickModifier),
                            )
                            Text(
                                text = shichenLabel,
                                style = cityRowStyle,
                                color = HeroPalette.LABEL_DIM,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                                textAlign = TextAlign.End,
                            )
                        }
                    }

                    // 下面两列时间内容：左标准时、右真太阳时。
                    // 两列之间那条竖线在这里；档 0 时它还要向上延伸到标签行顶部（见上面
                    // Box 里的 overlay）。
                    Row(modifier = Modifier.fillMaxWidth()) {
                        // 左：当地标准时间（所在地的法定时区；中国境内就是北京时间，
                        // 出国或手工指定外地坐标时换成当地标准时。时区标签在上面的整行里）
                        // 顺手把这一列的高度量下来给竖线用：列的高度就是时钟行的高度，
                        // 而竖线不参与列的高度（它在 Row 里是固定高度，见 dividerHeight）。
                        Column(
                            modifier = Modifier
                                .weight(1f)
                                .onSizeChanged { clockRowHeightPx = it.height.toFloat() },
                        ) {
                            HeroClock(
                                text = AnnotatedString(TimeFormat.clock(snapshot.localStandardTime)),
                                seconds = snapshot.localStandardTime.second,
                                color = Color.White,
                            )
                        }

                        Box(
                            modifier = Modifier
                                .padding(
                                    start = dividerSideInset,
                                    end = dividerSideInset,
                                    top = dividerTopPadding,
                                )
                                .width(dividerWidth)
                                .height(dividerHeight)
                                .background(dividerColor),
                        )

                        // 右：真太阳时（逐秒刷新）。未知态 / 还没等到 fix：三组横线占位，
                        // 字号、行高、宽度与真实时间完全一致（主字号 `‒‒:‒‒` + 半高 `:‒‒`），版式不跳。
                        Column(modifier = Modifier.weight(1f)) {
                            if (showPlaceholders) {
                                HeroClock(
                                    text = placeholderClock(Placeholders.trueSolarClockMain()),
                                    seconds = null,
                                    secondsText = placeholderClock(Placeholders.trueSolarClockSeconds()),
                                    color = solarColor.copy(alpha = PLACEHOLDER_ALPHA),
                                )
                            } else {
                                HeroClock(
                                    text = AnnotatedString(
                                        "%02d:%02d".format(
                                            snapshot.trueSolarTime.hour,
                                            snapshot.trueSolarTime.minute,
                                        ),
                                    ),
                                    seconds = snapshot.trueSolarTime.second,
                                    color = solarColor,
                                )
                            }
                        }
                    }
                }

                // 档 0 的上延段：从**标签文字上沿**补到两列那条线的起点，两段接起来是一条从
                // 文字顶部通到两列底部的整线。这里用与下面两列**同一套**排布（左右各 weight 1、
                // 中间 1dp + 左右各 12dp）来摆这一小段线，四舍五入后 x 与下面那条严格重合，
                // 接缝处不会错开 1px。
                if (cityRowTier == 0 && labelRowHeightPx > 0f) {
                    // 顶端下移 dividerTopInsetPx（= 行盒里字形上沿之上的空白），高度同比减掉，
                    // 底端仍接在两列那条线上。
                    val overlayHeightPx = (
                        labelRowHeightPx +
                            with(insetDensity) { dividerTopPadding.toPx() } -
                            dividerTopInsetPx
                        ).coerceAtLeast(0f)
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = with(insetDensity) { dividerTopInsetPx.toDp() }),
                    ) {
                        Spacer(Modifier.weight(1f))
                        Box(
                            modifier = Modifier
                                .padding(start = dividerSideInset, end = dividerSideInset)
                                .width(dividerWidth)
                                .height(with(insetDensity) { overlayHeightPx.toDp() })
                                .background(dividerColor),
                        )
                        Spacer(Modifier.weight(1f))
                    }
                }
            }

            Spacer(Modifier.height(6.dp))

            // 日期/天气与经纬度同一行：日期行吃满剩余宽度，经纬度贴右。
            // 放不下「日期/天气」与经纬度两者时，优先保住日期与天气，把右侧经纬度隐藏。
            // 宽度用 onSizeChanged 取（不能用 BoxWithConstraints：卡片在 IntrinsicSize.Max 里，
            // SubcomposeLayout 参与固有测量会抛异常），再用 TextMeasurer 量两者自然宽度。
            var statsRowWidthPx by remember { mutableStateOf(0f) }
            val rowMeasurer = rememberTextMeasurer()
            // 同上：日期行/经纬度也把字重钉死（并抵掉系统加粗），避免这一行被撑宽、把经纬度挤掉。
            val labelStyle = cardTextStyle(MaterialTheme.typography.labelSmall, FontWeight.Medium)
            val gapPx = with(LocalDensity.current) { 8.dp.toPx() }
            val dateWidthPx = rowMeasurer.measure(dateTail, labelStyle).size.width.toFloat()
            val coordWidthPx = if (coordinates.isEmpty()) {
                0f
            } else {
                rowMeasurer.measure(coordinates, labelStyle).size.width.toFloat()
            }
            val showCoordinates = SmallRowLayout.shouldShowTrailing(
                leadingWidthPx = dateWidthPx,
                trailingWidthPx = coordWidthPx,
                gapPx = gapPx,
                availablePx = statsRowWidthPx,
            )
            // 同理兜底：日期行也可能放不下（长城市名 + 天气 + 温度区间，再被经纬度挤）。
            // 能收起经纬度就先收；收完还放不下就把日期行字号按可用宽度缩下来，
            // 缩到下限仍放不下才交给省略号。行高不变，所以下面时间轴/逐时的位置不跳。
            val dateFitStyle = fitTextStyle(
                measurer = rowMeasurer,
                text = dateTail,
                style = labelStyle,
                maxWidthPx = (
                    statsRowWidthPx - if (showCoordinates) coordWidthPx + gapPx else 0f
                    ).coerceAtLeast(0f),
            )

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .onSizeChanged { statsRowWidthPx = it.width.toFloat() },
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = dateTail,
                    style = dateFitStyle,
                    color = HeroPalette.LABEL_DIM,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f),
                )
                if (showCoordinates) {
                    Text(
                        text = coordinates,
                        style = labelStyle,
                        color = HeroPalette.LABEL_DIM,
                        maxLines = 1,
                        modifier = Modifier.padding(start = 8.dp),
                    )
                }
            }

            Spacer(Modifier.height(10.dp))

            // 0–24 时时间轴：与桌面卡片、鸿蒙版同款（1vp 细线 + 柔化圆点）。
            // 未知态没有真太阳时就没有「现在走到哪」的圆点（画在 0:00 上等于报了个假时刻）。
            HeroAxis(
                solarSecondsOfDay = if (showPlaceholders) null else solarSeconds,
                bands = if (locationUnknown) emptyList() else extras.bands,
                bandColor = bandTint,
                dotColor = if (inKeyTime && bandTint != null) bandTint else HeroPalette.DOT,
            )
            // 逐时行：未知态也照画（六格时间 + `-°` 占位、无图标），行高与正常态一致。
            if (extras.hourly.isNotEmpty()) {
                Spacer(Modifier.height(10.dp))
                HeroHourly(extras.hourly, rows = hourlyRows)
            }
        }
    }
}

/** 大卡片用的配色：白天暖橙底、白字；夜里深蓝底、金色真太阳时。 */
private object HeroPalette {
    val LABEL: Color = Color(0xCCFFFFFF)
    val LABEL_DIM: Color = Color(0xB3FFFFFF)
    val DOT: Color = Color.White
    private val GOLD: Color = Color(0xFFF5D68A)
    /** 白天橙底上的真太阳时：淡金，比纯白暖一档，又不至于和底色糊在一起。 */
    private val DAY_ACCENT: Color = Color(0xFFFFE6B4)
    private val COLD: Color = Color(0xFF4CAF7D)
    private val HOT: Color = Color(0xFFD9534F)
    // 白天数字色的两个端点：0% 用「最淡」，100% 用时间轴色段的深色；默认取中间偏浓。
    // 白天/夜间都用「最淡」一档：浓度统一 0%（用户确认）。
    private val COLD_INK_DAY: Color = Color(0xFFBCF5CA)
    private val HOT_INK_DAY: Color = Color(0xFFFFC4C9)
    private val COLD_INK_NIGHT: Color = Color(0xFFA6E4C3)
    private val HOT_INK_NIGHT: Color = Color(0xFFF0A9A6)
    // 时间轴上的色段、圆点仍用深一档，淡色在橙底上几乎看不出边界。
    private val COLD_BAND_ON_DAY: Color = Color(0xFF2E7D32)
    private val HOT_BAND_ON_DAY: Color = Color(0xFFB3261E)

    fun gradient(isDay: Boolean): List<Color> = if (isDay) {
        listOf(Color(0xFFF7A64B), Color(0xFFEA7A2C))
    } else {
        listOf(Color(0xFF2A3B5C), Color(0xFF151B2E))
    }

    /** 真太阳时的强调色：白天用白字，夜里用金色。 */
    fun accent(isDay: Boolean): Color = if (isDay) DAY_ACCENT else GOLD

    /**
     * 关键时段里真太阳时数字的颜色。
     *
     * [intensity] 只影响白天：0 = 最淡（[COLD_INK_DAY_PALE] / [HOT_INK_DAY_PALE]），
     * 1 = 与时间轴色段同色（[COLD_BAND_ON_DAY] / [HOT_BAND_ON_DAY]）。夜间始终用 [COLD] / [HOT]。
     */
    fun ink(temperature: TakeTemperature?, isDay: Boolean): Color? = when (temperature) {
        TakeTemperature.COLD_OR_MILD -> if (isDay) COLD_INK_DAY else COLD_INK_NIGHT
        TakeTemperature.HOT_OR_MILD -> if (isDay) HOT_INK_DAY else HOT_INK_NIGHT
        else -> null
    }

    /** 关键时段在时间轴上的色段与圆点颜色。 */
    fun band(temperature: TakeTemperature?, isDay: Boolean): Color? = when (temperature) {
        TakeTemperature.COLD_OR_MILD -> if (isDay) COLD_BAND_ON_DAY else COLD
        TakeTemperature.HOT_OR_MILD -> if (isDay) HOT_BAND_ON_DAY else HOT
        else -> null
    }
}

/** 时间轴：1vp 轨道 + 关键时段的色段 + 当前时刻的柔化圆点（[solarSecondsOfDay] 为 null 时不画圆点）。 */
@Composable
private fun HeroAxis(
    solarSecondsOfDay: Double?,
    bands: List<TakeBand>,
    bandColor: Color?,
    dotColor: Color,
    modifier: Modifier = Modifier,
) {
    Canvas(modifier = modifier.fillMaxWidth().height(11.dp)) {
        val middle = size.height / 2f
        val thickness = 1.dp.toPx()
        drawRect(
            color = Color(0x40FFFFFF),
            topLeft = Offset(0f, middle - thickness / 2f),
            size = Size(size.width, thickness),
        )
        if (bandColor != null) {
            WidgetAxis.spans(bands).forEach { span ->
                val left = size.width * (span.startMinutes / MINUTES_PER_DAY).toFloat()
                val right = size.width * (span.endMinutes / MINUTES_PER_DAY).toFloat()
                drawRect(
                    color = bandColor,
                    topLeft = Offset(left, middle - thickness / 2f),
                    size = Size(right - left, thickness),
                )
            }
        }
        // 半径与 alpha 曲线是太阳点共用的那组常量（SunColors.SOFT_DOT_*）：两处点必须一模一样，
        // 所以这里不再写 5.5dp / 0.5 / 0.45 这些魔数。
        // 未知态（定位不可用）没有真太阳时：连圆点也不画，否则等于在 0:00 上报了个假时刻。
        val solarSeconds = solarSecondsOfDay ?: return@Canvas
        val radius = SunColors.SOFT_DOT_RADIUS_DP.dp.toPx()
        val center = Offset(
            x = (size.width * (solarSecondsOfDay / SECONDS_PER_DAY).toFloat()).coerceIn(0f, size.width),
            y = middle,
        )
        drawCircle(
            brush = Brush.radialGradient(
                *softDotStops(dotColor).toTypedArray(),
                center = center,
                radius = radius,
            ),
            radius = radius,
            center = center,
        )
    }
}

/**
 * 六格逐时预报：时刻、天气图标、**气温**，与桌面卡片、iOS 版同一套取数规则。
 *
 * 图标下面那一行原来写的是天气文字（`多云` / `小雨`），现在换成该格的气温（`18°`）——
 * 与 iOS 对齐，也省得长名字（英文 "Partly cloudy"）在 22dp 的格子里被省略号砍掉。
 * 字号/配色/行距沿用原来那一格文字标签的样式（只换内容，不动版式），所以卡片高度不变。
 *
 * 未知态（定位不可用）同样画满六格：时间标签照常、温度是 `-°`、**图标不画但位子留着**
 * （`iconRes == null` 时补一个同尺寸的空位），所以卡片高度与正常态逐像素一致，不会突然变矮。
 */
@Composable
private fun HeroHourly(cells: List<HourCell>, rows: Int = 1) {
    // 平板宽屏：大卡片被拉到与太阳卡片等高，一排逐时只占一半高度，留出大片空白 ——
    // 那里画两排（每排 6 格）。手机永远 1 排，渲染与改动前逐像素一致。
    val rowsToShow = cells.chunked(HOUR_CELLS).take(rows.coerceAtLeast(1))
    Column(modifier = Modifier.fillMaxWidth()) {
        rowsToShow.forEachIndexed { index, rowCells ->
            if (index > 0) {
                Spacer(Modifier.height(10.dp))
            }
            HeroHourlyRow(rowCells)
        }
    }
}

/** 一排逐时格子（6 格等宽）。 */
@Composable
private fun HeroHourlyRow(cells: List<HourCell>) {
    Row(modifier = Modifier.fillMaxWidth()) {
        cells.forEach { cell ->
            Column(
                modifier = Modifier.weight(1f),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text(
                    text = cell.label,
                    style = cardTextStyle(MaterialTheme.typography.labelSmall, FontWeight.Medium),
                    color = HeroPalette.LABEL_DIM,
                    maxLines = 1,
                )
                if (cell.iconRes != null) {
                    Image(
                        painter = painterResource(cell.iconRes),
                        contentDescription = null,
                        modifier = Modifier.padding(top = 3.dp).size(22.dp),
                    )
                } else {
                    // 没有天气就没有图标，但**位置要留着**：行高与正常态一致。
                    Spacer(Modifier.padding(top = 3.dp).size(22.dp))
                }
                Text(
                    text = cell.temperature,
                    style = cardTextStyle(MaterialTheme.typography.labelSmall, FontWeight.Medium),
                    color = HeroPalette.LABEL_DIM,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.padding(top = 1.dp),
                )
            }
        }
    }
}

private const val MINUTES_PER_DAY: Double = 24.0 * 60.0
private const val SECONDS_PER_DAY: Double = 24.0 * 3600.0

/**
 * 未知态时钟的占位文本（`--:--` / `:--`）。
 *
 * 用**半角**连字符（`--`），不在字符串里写全角 `－`：全角破折号在时钟字号下像一条长横，
 * 「空位」的感觉反而不对。真正的问题是**字体** —— 默认字体栈以中文为主，半角 `-` 被画得极短，
 * 几个连起来像碎点；这里显式指定**拉丁无衬线字体**（与数字同一个字体族），并用 `em` 单位加一点
 * 字距，两个 `-` 就读成了「两短横 + 冒号」。
 *
 * 字距用 `em`（而不是 sp）：主段大号、秒段半高，各自按自己的字号等比拉开，
 * 所以整行仍与真实时间同宽同高。
 */
private fun placeholderClock(text: String): AnnotatedString = buildAnnotatedString {
    withStyle(
        SpanStyle(
            fontFamily = FontFamily.SansSerif,
            letterSpacing = PLACEHOLDER_LETTER_SPACING_EM.em,
        ),
    ) { append(text) }
}

/**
 * 首页大卡片里的一格时间（`HH:mm` + 半高秒）。
 *
 * 两条硬规则：
 * 1. **秒是半高**：秒字号恒为主字号的 1/2；
 * 2. **整段时间正好撑满可用宽度**：用固定样本按 100sp 量出「主字号 + 半高秒」的实际宽度，
 *    再按这一栏的可用宽度反推主字号 —— 数字是等宽（`tnum`），所以不同时刻的宽度一致，
 *    不会忽宽忽窄。这样手机、平板（并排两栏、卡片被缩放）都自动铺满，不需要手调参数。
 *
 * 字号反推只在 `fontScale == 1` 时成立：探针按 sp 量、最终也按 sp 渲染，两者之间差的就是
 * `fontScale`；外层 `LockedCardDensity` 已把它锁成 1，所以「1sp = 1dp」在这里恒成立
 * （秒数那个 `(mainSp * 0.12f).dp` 的下沉量也是按这条前提写的：1sp 与 1dp 等值）。
 * 字重走 `cardFontWeight`：显式给出目标字重，并把系统「粗体字」的调整量抵掉。
 */
@Composable
private fun HeroClock(
    text: AnnotatedString,
    seconds: Int?,
    color: Color,
    modifier: Modifier = Modifier,
    /**
     * 半高那一组显示什么（默认由 [seconds] 生成 `:ss`）。
     *
     * 未知态（定位不可用）传占位文本：占位符与真实时间的**版式完全一致**（主字号 `‒‒:‒‒` +
     * 半高 `:‒‒`），所以卡片高度、两列宽度都不会跳。
     */
    secondsText: AnnotatedString? = null,
) {
    val measurer = rememberTextMeasurer()
    val density = LocalDensity.current
    val baseStyle = cardTextStyle(
        TextStyle(fontFeatureSettings = "tnum"),
        FontWeight.Medium,
    )
    // 行高钉回「系统字体在同一个字号下的行盒」（见 rememberSystemLineBoxEm）：自带 Noto 的
    // ascender 比原字体高，不钉的话两台机器的卡片高度分别 +4.9% / +2.7%。字号是下面算出来的，
    // 所以这里不能交给 cardTextStyle，得在算完 mainSp / secondsSp 之后自己套。
    val lineBoxEm = rememberSystemLineBoxEm()
    val probeSp = 100f
    // 半高那一组的实际文本：`secondsText` 优先（未知态是 `:‒‒`）。
    val tailText: AnnotatedString? = secondsText ?: seconds?.let { AnnotatedString(":%02d".format(it)) }
    // 用「88:88」与「:88」作样本：等宽数字下与实际渲染同宽，和具体时刻无关。
    val mainProbePx = measurer
        .measure("88:88", baseStyle.copy(fontSize = probeSp.sp), maxLines = 1)
        .size.width.toFloat()
    val secondsProbePx = if (tailText == null) {
        0f
    } else {
        measurer
            .measure(":88", baseStyle.copy(fontSize = (probeSp / 2f).sp), maxLines = 1)
            .size.width.toFloat()
    }
    val gapPx = if (tailText == null) 0f else with(density) { SECONDS_GAP.toPx() }
    val totalRatio = (mainProbePx + secondsProbePx + gapPx) / probeSp // 每 1sp 对应的像素宽

    // 用 onSizeChanged 取这一栏的可用宽度（不能用 BoxWithConstraints：它是 SubcomposeLayout，
    // 外面 Row 的 IntrinsicSize.Max 会向它要固有尺寸，直接抛 IllegalStateException）。
    var availablePx by remember { mutableIntStateOf(0) }
    // totalRatio 已经是「每 1sp 占多少像素」（探针按 100sp 量出来），所以直接相除就是 sp；
    // 不能再走 toSp() —— 那会再除一次 density × fontScale，字号会被压小一半。
    val mainSp = if (totalRatio > 0f && availablePx > 0) {
        availablePx / totalRatio * CLOCK_FIT_SAFETY
    } else {
        FALLBACK_HERO_CLOCK_SP
    }.coerceIn(MIN_HERO_CLOCK_SP, MAX_HERO_CLOCK_SP)
    val secondsSp = mainSp / 2f

    Row(
        verticalAlignment = Alignment.Bottom,
        modifier = modifier
            .fillMaxWidth()
            .onSizeChanged { availablePx = it.width },
    ) {
        Text(
            text = text,
            style = baseStyle.copy(fontSize = mainSp.sp).pinSystemLineBox(lineBoxEm),
            color = color,
            maxLines = 1,
        )
        if (tailText != null) {
            Text(
                text = tailText,
                style = baseStyle.copy(fontSize = secondsSp.sp).pinSystemLineBox(lineBoxEm),
                color = color,
                maxLines = 1,
                // 秒是半高，往上抬一点让它与主数字的基线齐平（间距按主字号等比）。
                modifier = Modifier.padding(start = SECONDS_GAP, bottom = (mainSp * 0.12f).dp),
            )
        }
    }
}

@Composable
private fun SunCard(
    snapshot: SolarSnapshot,
    /** 定位不可用（未知态）：高度角 / 白昼 / 圆盘全部换成「没有读数」的形态。 */
    locationUnknown: Boolean = false,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    Card(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(24.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
    ) {
        Column(Modifier.padding(SUN_CARD_PADDING)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = stringResource(R.string.sun_section_title),
                    // 字重显式写出（titleSmall 默认就是 Medium），并由 cardTextStyle 抵掉
                    // 系统「加粗」的加法 / 乘法两层调整。
                    style = cardTextStyle(MaterialTheme.typography.titleSmall, FontWeight.Medium),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(Modifier.weight(1f))
                Text(
                    // 未知态没有观测点：高度角留 `—`（不显示上一次地点的读数）。
                    text = if (locationUnknown) {
                        Placeholders.altitude()
                    } else {
                        stringResource(R.string.altitude, snapshot.altitudeDegrees)
                    },
                    style = cardTextStyle(MaterialTheme.typography.bodySmall, FontWeight.Medium),
                    color = MaterialTheme.colorScheme.primary,
                )
            }

            Spacer(Modifier.height(SUN_TITLE_GAP))

            // 圆盘铺满卡片内容宽度：日出／上中天／日落三个时间直接标在圆的外侧，
            // 不再占右边一整栏，所以卡片高度比带右栏时更低。
            SunDial(snapshot = snapshot, locationUnknown = locationUnknown)

            Spacer(Modifier.height(SUN_DAYLIGHT_GAP))

            // 「白昼 X 小时 X 分」这行：未知态只留一个 `—`（不编 12 小时之类的假数据），
            // 而且必须和正常态的整行**同一位置**：两者都放进同一行、同一套 Box 居中，
            // 谁都不带额外 padding / fillMaxWidth 的差异，切换时这一行不会左右挪。
            Box(
                modifier = Modifier.fillMaxWidth(),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    text = if (locationUnknown) {
                        Placeholders.daylight()
                    } else {
                        stringResource(R.string.sun_daylight_line, daylightText(context, snapshot))
                    },
                    style = cardTextStyle(MaterialTheme.typography.bodySmall, FontWeight.Normal),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center,
                )
            }
        }
    }
}

/** 白昼时长的读数：极昼按整天算、极夜按 0，其余用日出日落算出来的秒数。 */
private fun daylightText(context: Context, snapshot: SolarSnapshot): String = when (snapshot.polar) {
    SolarTimeMath.PolarState.MIDNIGHT_SUN -> TimeText.duration(context, DAY_SECONDS)
    SolarTimeMath.PolarState.POLAR_NIGHT -> TimeText.duration(context, 0L)
    SolarTimeMath.PolarState.NORMAL -> TimeText.duration(context, snapshot.daylightSeconds)
}

/**
 * 圆盘上的一个外侧标签：天然尺寸的 `Text`，用 `offset` 摆到 `SunPathGeometry.labelAnchors`
 * 算出来的锚点上（对齐方式、夹取都由调用方算好）。
 *
 * 用真正的 `Text` 而不是画到 Canvas 里，是为了保住无障碍朗读与卡片自带的字体／字重补偿。
 */
@Composable
private fun DialLabel(text: String, style: TextStyle, color: Color, offset: IntOffset) {
    Text(
        text = text,
        style = style,
        color = color,
        maxLines = 1,
        softWrap = false,
        modifier = Modifier.offset { offset },
    )
}

/**
 * 时间圆盘：**圆 = 一天 24 小时**，12:00 在正上方、00:00 在正下方，
 * 地平线是一条水平线，其高度由日出时刻决定（见 `SunPathGeometry`）。
 *
 * 盘面画四样东西（**不再画外圈「表圈」**：白天弧 / 夜晚虚线就是圆盘唯一的边界）：
 * 1. 白天弧：实线 1.6dp、主色；夜晚弧：虚线 1.5dp / 4dp 间隔、低对比度；弧端各外扩 0.8°（≈1dp），
 *    让线帽略微穿过地平线（交点上的小圆点已按用户要求删掉）；
 * 2. 地平线：一条**固定长度**的横线（画布左右各内缩 4dp），高度由日出时刻决定，贯穿整个画面；
 * 3. 当前太阳点：**两层** —— 外圈光晕（2.75→5.5dp，alpha 0.35→0）+ 纯色实心核心（2.75dp、alpha 1.0，
 *    先光晕后核心）；地平线以上金色、以下低对比 outline；核心绝不被弧线透出；
 * 4. 运动方向箭头：圆内侧 0.72R 上一段 30° 的短弧 + 实心小三角，标出太阳往哪走
 *    （北半球顺时针、南半球逆时针，颜色 onSurfaceVariant，不与主色抢视觉）。
 *
 * 南半球（`snapshot.latitude < 0`）时圆盘整体左右镜像：观察者面朝北，06:00 的太阳在右、
 * 18:00 在左，太阳从右往左走；三处竖直基准（12:00 圆顶、00:00 圆底、地平线高度）不变，
 * 日出 / 日落标签也跟着换到交点的另一侧（见 `SunPathGeometry.hourX` / `labelAnchors`）。
 *
 * 三个时间标签直接标在圆外：日出在左交点左侧（右对齐）、日落在右交点右侧（左对齐）、
 * 上中天在圆顶正上方（居中），三者都离圆 10dp，不会压到弧线。
 * 极昼／极夜没有交点：不再画日出／日落标签，只在圆心写一行「极昼」／「极夜」；
 * 其中极昼**保留**上中天标签，极夜连它也不画（太阳整日不升，上中天没有意义）。
 *
 * 时刻全部用**当地真太阳时**（圆盘的角度就是真太阳时的小时数）；标签文字用当地标准时，
 * 两者口径不同是有意的 —— 盘上讲太阳的实际位置，标签写当地钟表上的时刻。
 * 颜色一律取主题 token（白天／夜间两套由 `TrueSolarTimeTheme` 换掉色板），这里不写死颜色。
 */
@Composable
private fun SunDial(
    snapshot: SolarSnapshot,
    /** 定位不可用（未知态）：昼夜各半的对半圆，不画太阳点 / 箭头 / 时间标签。 */
    locationUnknown: Boolean = false,
    modifier: Modifier = Modifier,
) {
    val scheme = MaterialTheme.colorScheme
    // 白天弧单独取淡金：亮色主题下主色实色在白卡上太沉（见 `sunDayArcColor` 的注释）；
    // 太阳点是**两层**：外圈光晕（2.75→5.5dp，alpha 0.35→0）+ 纯色实心核心（2.75dp，alpha 1.0）。
    // 核心用纯 Color 直接画、不套 Brush 也不 copy(alpha)，所以弧线不会从点下面透出来。
    // 地平线以下用同样的两层结构，只把颜色换成低对比的 outline。
    // 地平线与运动箭头仍是灰（outline / onSurfaceVariant），不动。
    val dayArcColor = sunDayArcColor()
    val dotCoreColor = sunDotColor()
    val dotGlowStops = sunDotGlowStops(dotCoreColor)
    val belowHorizonGlowStops = sunDotGlowStops(scheme.outline)
    val polar = snapshot.polar
    val polarDay = polar == SolarTimeMath.PolarState.MIDNIGHT_SUN
    val polarNight = polar == SolarTimeMath.PolarState.POLAR_NIGHT
    // 极昼 / 极夜没有日出日落：传 null，让几何层按 polar 标志把地平线沉到圆下 / 升到圆上。
    val normal = polar == SolarTimeMath.PolarState.NORMAL
    // 未知态（定位不可用）：昼夜各半 —— 日出 06:00、日落 18:00，地平线正好过圆心；
    // 但它**不是**「一个普通日」：太阳点 / 运动箭头 / 时间标签全部不画（见 SunPath.unknown）。
    val sunriseHour = when {
        locationUnknown -> SunPathGeometry.UNKNOWN_SUNRISE_HOUR
        normal -> snapshot.sunriseTrueSolar.toHours()
        else -> null
    }
    val sunsetHour = when {
        locationUnknown -> SunPathGeometry.UNKNOWN_SUNSET_HOUR
        normal -> snapshot.sunsetTrueSolar.toHours()
        else -> null
    }
    val trueSolarHour = if (locationUnknown) {
        12.0 // 未知态没有真实时刻；参数化取 12:00（太阳点在圆顶，反正不画）
    } else {
        snapshot.trueSolarTime.toSecondOfDay() / SECONDS_PER_HOUR
    }
    // 南半球观察者面朝北：06:00 的太阳在右、18:00 在左，整条轨迹与北半球镜像。
    // 只认观测点自己的纬度（snapshot.latitude），不掺时区 / 北京时间之类的东西。
    // 未知态没有观测点，对半圆不镜像（上下半圈本来就是对称的）。
    val southernHemisphere = !locationUnknown && snapshot.latitude < 0

    val labelStyle = cardTextStyle(MaterialTheme.typography.labelSmall, FontWeight.Medium)
    val dataColor = MaterialTheme.colorScheme.onSurface
    // 圆盘标签带文字说明：日出 06:24 / 日落 16:54 / 上中天 11:39（文案走 strings.xml，三语）。
    val sunriseText = stringResource(R.string.sun_label_sunrise) + " " + TimeFormat.clock(snapshot.sunriseLocal)
    val sunsetText = stringResource(R.string.sun_label_sunset) + " " + TimeFormat.clock(snapshot.sunsetLocal)
    // 上中天补方位后缀：圆盘是「面朝赤道」的竖直平面投影，北半球面朝南、南半球面朝北，
    // 直接把上中天时的方位标出来，用户就不会把日出方向看反。
    val noonText = SunLabelText.noonLabel(
        prefix = stringResource(R.string.sun_label_noon),
        time = TimeFormat.clock(snapshot.solarNoonLocal),
        latitude = snapshot.latitude,
        dueSouth = stringResource(R.string.sun_due_south),
        dueNorth = stringResource(R.string.sun_due_north),
    )
    val polarText = stringResource(if (polarDay) R.string.sun_polar_day else R.string.sun_polar_night)

    val measurer = rememberTextMeasurer()
    val density = LocalDensity.current
    var dialPx by remember { mutableStateOf(IntSize.Zero) }
    val sideGapPx = with(density) { SUN_LABEL_GAP.toPx() }
    val noonGapPx = with(density) { SUN_NOON_LABEL_GAP.toPx() }
    val dropPx = with(density) { SUN_LABEL_TOP_INSET.toPx() }
    val risePx = with(density) { SUN_LABEL_RISE.toPx() }
    val sideInsetPx = with(density) { SUN_LABEL_SIDE_INSET.roundToPx() }
    val horizonInsetPx = with(density) { SUN_HORIZON_INSET.toPx() }

    // 标签尺寸要先量出来：锚点给的是「文字的边缘 / 中心」，摆位得用真实宽高。
    val sunriseLabel = remember(sunriseText, labelStyle) {
        measurer.measure(sunriseText, labelStyle, maxLines = 1, softWrap = false)
    }
    val sunsetLabel = remember(sunsetText, labelStyle) {
        measurer.measure(sunsetText, labelStyle, maxLines = 1, softWrap = false)
    }
    val noonLabel = remember(noonText, labelStyle) {
        measurer.measure(noonText, labelStyle, maxLines = 1, softWrap = false)
    }
    val polarLabel = remember(polarText, labelStyle) {
        measurer.measure(polarText, labelStyle, maxLines = 1, softWrap = false)
    }

    Box(
        modifier
            .fillMaxWidth()
            .height(SUN_DIAL_HEIGHT)
            // 画布尺寸只能用 onSizeChanged 拿：宽屏分支里卡片在 IntrinsicSize.Max 下，
            // BoxWithConstraints 这类 SubcomposeLayout 参与固有测量会抛异常（见 HeroCard 注释）。
            .onSizeChanged { dialPx = it },
    ) {
        Canvas(Modifier.fillMaxSize()) {
            val path = if (locationUnknown) {
                // 未知态的「对半圆」走独立的几何入口：昼夜各 180°、地平线过圆心、无太阳点。
                SunPathGeometry.unknown(size.width, size.height)
            } else {
                SunPathGeometry.compute(
                    width = size.width,
                    height = size.height,
                    sunriseHour = sunriseHour,
                    sunsetHour = sunsetHour,
                    trueSolarHour = trueSolarHour,
                    isPolarDay = polarDay,
                    isPolarNight = polarNight,
                    southernHemisphere = southernHemisphere,
                )
            }
            val center = Offset(path.centerX, path.centerY)
            // 轨迹线（亮 / 暗两个主题、地平线上下）都比上一版细：白天实线 1.6dp、夜晚虚线 1.5dp，
            // 虚线间隔跟着从 6/6dp 缩到 4/4dp —— 线细了间隔不缩，看起来还是一段段粗棒。
            // 极昼 / 极夜的整圆用同一组线宽（白天实线用 1.6dp，极夜虚圆用 1.5dp + 4/4dp）。
            val dayArcStroke = SunColors.DAY_ARC_STROKE_DP.dp.toPx()
            val nightArcStroke = SunColors.NIGHT_ARC_STROKE_DP.dp.toPx()
            // 太阳点：核心 2.75dp（纯色不透明，= 时间轴半径 × 0.5）+ 外圈光晕到 5.5dp（alpha 0.35→0）。
            val dotCoreRadius = SunColors.SUN_DOT_CORE_RADIUS_DP.dp.toPx()
            val dotGlowRadius = SunColors.SUN_DOT_GLOW_RADIUS_DP.dp.toPx()
            val nightDash = PathEffect.dashPathEffect(
                floatArrayOf(
                    SunColors.NIGHT_DASH_ON_DP.dp.toPx(),
                    SunColors.NIGHT_DASH_OFF_DP.dp.toPx(),
                ),
            )
            val arcTopLeft = Offset(path.centerX - path.radius, path.centerY - path.radius)
            val arcSize = Size(path.radius * 2f, path.radius * 2f)

            val span = SunPathGeometry.dayArcSpan(sunriseHour, sunsetHour)
            if (span == null) {
                // 整圆只有一种性质：极昼画实线亮弧，极夜画虚线暗弧（同样用细线）。
                if (path.isWholeCircleDay) {
                    drawCircle(
                        color = dayArcColor,
                        radius = path.radius,
                        center = center,
                        style = Stroke(dayArcStroke),
                    )
                } else {
                    drawCircle(
                        color = scheme.outline,
                        radius = path.radius,
                        center = center,
                        style = Stroke(width = nightArcStroke, pathEffect = nightDash),
                    )
                }
            } else {
                // 白天弧：从日出交点顺时针经过 12:00（正上方）扫到日落交点。
                // 交点上的小圆点已删，两端各外扩 0.8°（≈1dp），让圆头线帽略微穿过地平线，
                // 不然弧端会看起来悬在地平线前一点。
                val dayArc = SunPathGeometry.withEndpointOverdraw(span)
                drawArc(
                    color = dayArcColor,
                    startAngle = dayArc.startDegrees,
                    sweepAngle = dayArc.sweepDegrees,
                    useCenter = false,
                    topLeft = arcTopLeft,
                    size = arcSize,
                    style = Stroke(width = dayArcStroke, cap = StrokeCap.Round),
                )
                // 夜晚弧：从白天弧的终点接上，整圈补齐（白天弧外扩后，夜间弧相应短 1.6°）。
                val nightSweep = 360f - dayArc.sweepDegrees
                if (nightSweep > 0f) {
                    drawArc(
                        color = scheme.outline,
                        startAngle = dayArc.startDegrees + dayArc.sweepDegrees,
                        sweepAngle = nightSweep,
                        useCenter = false,
                        topLeft = arcTopLeft,
                        size = arcSize,
                        style = Stroke(width = nightArcStroke, pathEffect = nightDash),
                    )
                }
            }

            // 地平线：固定长度的一条横线（画布左右各内缩 4dp），高度由日出时刻决定。
            // 普通日 / 短昼 / 极昼 / 极夜 / 0:00 相切全部画满这一条，同色同宽（outline, 1dp）——
            // 圆内那一段就是「弦」，但不再单独加强，否则短昼时看起来会断成两截。
            // 它也是圆盘唯一的水平基准线：外面不再套「表圈」，白天弧 / 夜晚虚线就是圆盘的边界。
            val horizon = SunPathGeometry.horizonSpan(size.width, horizonInsetPx)
            drawLine(
                color = scheme.outline,
                start = Offset(horizon.startX, path.horizonY),
                end = Offset(horizon.endX, path.horizonY),
                strokeWidth = 1.dp.toPx(),
            )

            // 日出 / 日落交点不再画小圆点：弧的端点 + 两侧时间标签已经说明了位置，
            // 那个点会和「当前太阳点」抢注意力（用户要求删掉）。

            // 运动方向箭头：画在圆内侧 0.72R 上的一小段弧（跨 30°，以当前太阳点角度为中心），
            // 末端一个实心小三角。方向与太阳点同一套参数化 —— 北半球顺时针、南半球逆时针。
            // 颜色刻意用低对比的 onSurfaceVariant（不用主色，免得和白天弧抢视觉）。
            // 未知态（定位不可用）没有轨迹可讲：整段不画（见 SunPath.showsMotionArrow）。
            if (path.showsMotionArrow) {
                val motion = SunPathGeometry.motionArrow(path, trueSolarHour)
                val arrowRadius = path.radius * SunPathGeometry.MOTION_ARROW_RADIUS_RATIO
                val arrowStartAngle = Math.toDegrees(
                    atan2(
                        (motion.startY - path.centerY).toDouble(),
                        (motion.startX - path.centerX).toDouble(),
                    ),
                ).toFloat()
                val arrowEndAngle = Math.toDegrees(
                    atan2(
                        (motion.endY - path.centerY).toDouble(),
                        (motion.endX - path.centerX).toDouble(),
                    ),
                ).toFloat()
                // 归一到 (−180, 180]：正 = 顺时针（北半球），负 = 逆时针（南半球）。
                val arrowSweep = ((arrowEndAngle - arrowStartAngle + 540f) % 360f) - 180f
                drawArc(
                    color = scheme.onSurfaceVariant,
                    startAngle = arrowStartAngle,
                    sweepAngle = arrowSweep,
                    useCenter = false,
                    topLeft = Offset(path.centerX - arrowRadius, path.centerY - arrowRadius),
                    size = Size(arrowRadius * 2f, arrowRadius * 2f),
                    style = Stroke(width = 1.5.dp.toPx(), cap = StrokeCap.Round),
                )
                // 箭头尖 = 弧的终点，朝向该点的切线方向：顺时针是 (−r.y, r.x)，逆时针取反。
                val radiusX = motion.endX - path.centerX
                val radiusY = motion.endY - path.centerY
                val radiusLength = sqrt(radiusX * radiusX + radiusY * radiusY).coerceAtLeast(0.001f)
                val clockwise = if (arrowSweep > 0f) 1f else -1f
                val dirX = clockwise * (-radiusY / radiusLength)
                val dirY = clockwise * (radiusX / radiusLength)
                val headLength = 5.dp.toPx()
                val headHalfWidth = headLength * 0.45f
                val headBaseX = motion.tipX - dirX * headLength
                val headBaseY = motion.tipY - dirY * headLength
                val normalX = -dirY
                val normalY = dirX
                drawPath(
                    path = Path().apply {
                        moveTo(motion.tipX, motion.tipY)
                        lineTo(headBaseX + normalX * headHalfWidth, headBaseY + normalY * headHalfWidth)
                        lineTo(headBaseX - normalX * headHalfWidth, headBaseY - normalY * headHalfWidth)
                        close()
                    },
                    color = scheme.onSurfaceVariant,
                )
            }

            // 当前太阳点：**两层**，先光晕后核心 —— 核心是纯色圆（alpha 1.0），压在最上面，
            // 所以弧线绝不会从点下面透出来（真机上单层渐变曾被渲染成均匀半透明）。
            // 光晕：半径 5.5dp 的径向渐变，内沿 2.75dp（= 核心半径）alpha 0.35 → 外沿 0，只在外圈发光。
            // 地平线以下用同样的两层，只把颜色换成低对比的 outline；不做硬边空心圈。
            // 未知态没有观测点：太阳点整块不画（见 SunPath.showsSunDot）。
            if (path.showsSunDot) {
                val sun = Offset(path.sunX, path.sunY)
                val dotGlowColorStops = if (path.isSunUp) dotGlowStops else belowHorizonGlowStops
                val dotCoreFill = if (path.isSunUp) dotCoreColor else scheme.outline
                drawCircle(
                    brush = Brush.radialGradient(
                        *dotGlowColorStops.toTypedArray(),
                        center = sun,
                        radius = dotGlowRadius,
                    ),
                    radius = dotGlowRadius,
                    center = sun,
                )
                // 核心：纯 Color，不走 Brush、不 copy(alpha) —— 保证 100% 不透明。
                drawCircle(color = dotCoreFill, radius = dotCoreRadius, center = sun)
            }
        }

        // 标签层：等画布量到尺寸后再摆，坐标全部来自纯几何函数。
        // 未知态不画日出／上中天／日落标签（也就没有「极昼／极夜」那句文案）。
        if (!locationUnknown && dialPx.width > 0 && dialPx.height > 0) {
            val path = SunPathGeometry.compute(
                width = dialPx.width.toFloat(),
                height = dialPx.height.toFloat(),
                sunriseHour = sunriseHour,
                sunsetHour = sunsetHour,
                trueSolarHour = trueSolarHour,
                isPolarDay = polarDay,
                isPolarNight = polarNight,
                southernHemisphere = southernHemisphere,
            )
            val anchors = SunPathGeometry.labelAnchors(
                path = path,
                sunriseHour = sunriseHour,
                sunsetHour = sunsetHour,
                sideGap = sideGapPx,
                noonGap = noonGapPx,
                minLabelDrop = dropPx,
                sideLabelRise = risePx,
                // 把量出来的真实宽高交给纯几何：接近极昼时三个标签会挤在一起，由它决定要不要边缘退让。
                sunriseWidth = sunriseLabel.size.width.toFloat(),
                sunsetWidth = sunsetLabel.size.width.toFloat(),
                noonWidth = noonLabel.size.width.toFloat(),
                labelHeight = maxOf(
                    sunriseLabel.size.height,
                    sunsetLabel.size.height,
                    noonLabel.size.height,
                ).toFloat(),
                edgeInset = sideInsetPx.toFloat(),
                canvasWidth = dialPx.width.toFloat(),
                // 南半球把两个标签放到地平线下方，偏移量与「北半球抬升」同一档。
                labelBelowOffset = risePx,
            )
            // 夹进画布：左右各留 sideInset，竖直方向不出画布（极端昼长时标签会顶到边上）。
            fun placed(x: Float, y: Float, w: Int, h: Int): IntOffset {
                val maxX = (dialPx.width - w - sideInsetPx).coerceAtLeast(sideInsetPx)
                val maxY = (dialPx.height - h).coerceAtLeast(0)
                return IntOffset(
                    x.roundToInt().coerceIn(sideInsetPx, maxX),
                    y.roundToInt().coerceIn(0, maxY),
                )
            }

            if (path.hasTransitLabel) {
                DialLabel(
                    text = noonText,
                    style = labelStyle,
                    color = dataColor,
                    offset = placed(
                        anchors.noonX - noonLabel.size.width / 2f,
                        anchors.noonY - noonLabel.size.height,
                        noonLabel.size.width,
                        noonLabel.size.height,
                    ),
                )
            }
            if (normal) {
                // 锚点是「挨着圆的那条边」：锚点在圆心左侧 → 文字往左排（右对齐），
                // 在右侧 → 往右排（左对齐）。南北半球靠这一条自动换边，不用再传标志。
                val sunriseOnRight = anchors.sunriseX > path.centerX
                val sunsetOnRight = anchors.sunsetX > path.centerX
                DialLabel(
                    text = sunriseText,
                    style = labelStyle,
                    color = dataColor,
                    offset = placed(
                        if (sunriseOnRight) {
                            anchors.sunriseX
                        } else {
                            anchors.sunriseX - sunriseLabel.size.width
                        },
                        anchors.sunriseY - sunriseLabel.size.height / 2f,
                        sunriseLabel.size.width,
                        sunriseLabel.size.height,
                    ),
                )
                DialLabel(
                    text = sunsetText,
                    style = labelStyle,
                    color = dataColor,
                    offset = placed(
                        if (sunsetOnRight) {
                            anchors.sunsetX
                        } else {
                            anchors.sunsetX - sunsetLabel.size.width
                        },
                        anchors.sunsetY - sunsetLabel.size.height / 2f,
                        sunsetLabel.size.width,
                        sunsetLabel.size.height,
                    ),
                )
            } else {
                DialLabel(
                    text = polarText,
                    style = labelStyle,
                    color = MaterialTheme.colorScheme.primary,
                    offset = placed(
                        anchors.polarX - polarLabel.size.width / 2f,
                        anchors.polarY - polarLabel.size.height / 2f,
                        polarLabel.size.width,
                        polarLabel.size.height,
                    ),
                )
            }
        }
    }
}

/** 一天的秒数：极昼时白昼时长按整天算。 */
private const val DAY_SECONDS = 86_400L

private const val SECONDS_PER_HOUR = 3600.0

/** 真太阳时的小时数（0–24，含小数）；为空时返回 null（极昼 / 极夜）。 */
private fun LocalTime?.toHours(): Double? = this?.toSecondOfDay()?.div(SECONDS_PER_HOUR)

/** Compose 的 LocalView.context 可能是 ContextWrapper 包了几层，取出宿主 Activity。 */
private tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}
