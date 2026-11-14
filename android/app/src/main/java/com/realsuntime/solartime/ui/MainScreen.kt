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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Settings
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
import androidx.compose.runtime.CompositionLocalProvider
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
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.realsuntime.solartime.BuildConfig
import com.realsuntime.solartime.MainViewModel
import com.realsuntime.solartime.R
import com.realsuntime.solartime.data.TakeBand
import com.realsuntime.solartime.data.TakeTemperature
import com.realsuntime.solartime.data.PlaceSource
import com.realsuntime.solartime.data.WeatherRepository
import com.realsuntime.solartime.solar.Shichen
import com.realsuntime.solartime.solar.SolarSnapshot
import com.realsuntime.solartime.solar.SolarTimeMath
import com.realsuntime.solartime.solar.SolarTimeSnapshot
import com.realsuntime.solartime.solar.TimeFormat
import com.realsuntime.solartime.ui.theme.TrueSolarTimeTheme
import com.realsuntime.solartime.widget.ChimeAlarm
import com.realsuntime.solartime.widget.WidgetAxis
import java.time.LocalTime

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
/** 宽屏并排时把太阳弧线压矮：压低后太阳卡比大卡片略矮，行高由大卡片决定，橙色卡片里就不会再留空白。 */
private val WIDE_ARC_HEIGHT = 74.dp
/** 地图视口的宽高比：手机 4:3、平板 16:9（与鸿蒙版一致）。 */
private const val PHONE_MAP_ASPECT_RATIO = 4f / 3f
private const val WIDE_MAP_ASPECT_RATIO = 16f / 9f

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MainScreen(viewModel: MainViewModel = viewModel()) {
    val now by viewModel.now.collectAsStateWithLifecycle()
    val place by viewModel.place.collectAsStateWithLifecycle()
    val trackingGps by viewModel.trackingGps.collectAsStateWithLifecycle()
    val waitingForFix by viewModel.waitingForFix.collectAsStateWithLifecycle()
    val remindersEnabled by viewModel.remindersEnabled.collectAsStateWithLifecycle()
    val keyTimeChimeEnabled by viewModel.keyTimeChimeEnabled.collectAsStateWithLifecycle()
    val districtName by viewModel.districtName.collectAsStateWithLifecycle()
    val zoneOffsetSeconds by viewModel.zoneOffsetSeconds.collectAsStateWithLifecycle()
    val mapStyle by viewModel.mapStyle.collectAsStateWithLifecycle()
    val keepScreenOn by viewModel.keepScreenOn.collectAsStateWithLifecycle()
    val message by viewModel.message.collectAsStateWithLifecycle()

    val context = LocalContext.current
    val snackbarHostState = remember { SnackbarHostState() }
    var showSettings by rememberSaveable { mutableStateOf(false) }

    val snapshot = remember(now, place, zoneOffsetSeconds) {
        SolarTimeSnapshot.compute(now, place.latitude, place.longitude, zoneOffsetSeconds)
    }

    // 大卡片里的日期、天气、逐时预报与关键时段：半分钟刷新一次就够，不必每秒读偏好；
    // 但新数据一到（例如刚换了城市、天气刚取回来）要立刻重算，所以把天气版本号也当键。
    val weatherRevision = WeatherRepository.revision()
    val heroExtras = remember(place, now.epochSecond / 30, weatherRevision, zoneOffsetSeconds) {
        loadHeroExtras(context, place, now, zoneOffsetSeconds)
    }

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
            locationPermissionLauncher.launch(
                arrayOf(
                    Manifest.permission.ACCESS_FINE_LOCATION,
                    Manifest.permission.ACCESS_COARSE_LOCATION,
                ),
            )
        }
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
    TrueSolarTimeTheme(darkTheme = !snapshot.isDay) {
        Scaffold(
            containerColor = MaterialTheme.colorScheme.background,
            snackbarHost = { SnackbarHost(snackbarHostState) },
        ) { padding ->
            BoxWithConstraints(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 20.dp),
            ) {
                // 平板/宽屏：大卡片与太阳卡片并排（1:1、等高），卡片内容整体缩放到手机上那个比例。
                val wide = maxWidth >= WIDE_LAYOUT_MIN_WIDTH
                val baseDensity = LocalDensity.current
                // 自适应缩放：让「卡片的逻辑宽度」恒等于手机卡的 334dp，于是无论平板多宽，
                // 卡片里的版式都和手机一模一样，只是整体按比例放大/缩小。
                // （写死 1.35 会在 640dp 的小平板上出问题：分栏后每张卡只有 294dp，内容会被截断。）
                val cardWidth = (maxWidth - CARD_GAP) / 2
                val cardScale = (cardWidth / PHONE_CARD_WIDTH).coerceIn(MIN_CARD_SCALE, MAX_CARD_SCALE)
                val scaledDensity = remember(baseDensity, cardScale) {
                    Density(
                        density = baseDensity.density * cardScale,
                        fontScale = baseDensity.fontScale,
                    )
                }

                Column {
                    Header(
                        badge = if (place.source == PlaceSource.GPS) {
                            stringResource(R.string.location_badge_gps)
                        } else {
                            districtName.orEmpty()
                        },
                        onOpenSettings = { showSettings = true },
                    )
                    Spacer(Modifier.height(12.dp))

                    if (wide) {
                        // IntrinsicSize.Max + fillMaxHeight：两卡取较高的那张作行高，底边自然对齐。
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(IntrinsicSize.Max),
                            horizontalArrangement = Arrangement.spacedBy(CARD_GAP),
                        ) {
                            Box(Modifier.weight(1f).fillMaxHeight()) {
                                CompositionLocalProvider(LocalDensity provides scaledDensity) {
                                    HeroCard(
                                        snapshot = snapshot,
                                        districtName = districtName,
                                        coordinates = TimeText.coordinates(context, place.latitude, place.longitude),
                                        waitingForFix = waitingForFix,
                                        extras = heroExtras,
                                        modifier = Modifier.fillMaxHeight(),
                                    )
                                }
                            }
                            Box(Modifier.weight(1f).fillMaxHeight()) {
                                CompositionLocalProvider(LocalDensity provides scaledDensity) {
                                    SunCard(
                                        snapshot = snapshot,
                                        modifier = Modifier.fillMaxHeight(),
                                        arcHeight = WIDE_ARC_HEIGHT,
                                    )
                                }
                            }
                        }
                    } else {
                        HeroCard(
                            snapshot = snapshot,
                            districtName = districtName,
                            coordinates = TimeText.coordinates(context, place.latitude, place.longitude),
                            waitingForFix = waitingForFix,
                            extras = heroExtras,
                        )
                        Spacer(Modifier.height(14.dp))

                        SunCard(snapshot = snapshot)
                    }
                    Spacer(Modifier.height(14.dp))

                    MapCard(
                        place = place,
                        mapStyle = mapStyle,
                        mapAspectRatio = if (wide) WIDE_MAP_ASPECT_RATIO else PHONE_MAP_ASPECT_RATIO,
                    )
                    Spacer(Modifier.height(14.dp))

                    Text(
                        text = stringResource(R.string.version_label, BuildConfig.VERSION_NAME),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.fillMaxWidth(),
                    )
                    Spacer(Modifier.height(28.dp))
                }
            }
        }

        if (showSettings) {
            SettingsSheet(
                place = place,
                trackingGps = trackingGps,
                remindersEnabled = remindersEnabled,
                keyTimeChimeEnabled = keyTimeChimeEnabled,
                keepScreenOn = keepScreenOn,
                mapStyle = mapStyle,
                onDismiss = { showSettings = false },
                onRequestGps = {
                    showSettings = false
                    requestGps()
                },
                onApplyManual = { lat, lon, label -> viewModel.applyManualPlace(lat, lon, label) },
                onToggleReminders = toggleReminders,
                onToggleKeyTimeChime = toggleKeyTimeChime,
                onSelectMapStyle = viewModel::setMapStyle,
                onToggleKeepScreenOn = viewModel::setKeepScreenOn,
                    )
        }
    }
}

/**
 * 顶部：标题、副标题，右侧是位置标识与设置按钮。
 *
 * 位置标识与鸿蒙版一致：跟随 GPS 时显示「GPS」，指定坐标时显示反查到的行政区划。
 */
@Composable
private fun Header(badge: String, onOpenSettings: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        // 标题与右侧地名都要限宽：地名是不定宽文本，早先它按内容取宽，长地址（例如
        // "Donghuamen Subdistrict, Dongcheng District"）会把左边的标题挤成一字一行。
        // 两者都给权重，地名右对齐、超出省略，标题至少拿 60% 宽度。
        Column(Modifier.weight(1.5f)) {
            Text(
                text = stringResource(R.string.app_name),
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.SemiBold,
            )
            Text(
                text = stringResource(R.string.screen_subtitle),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        if (badge.isNotBlank()) {
            Text(
                text = badge,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.primary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                textAlign = TextAlign.End,
                modifier = Modifier
                    .weight(1f)
                    .padding(start = 8.dp, end = 6.dp),
            )
        }
        IconButton(onClick = onOpenSettings) {
            Icon(Icons.Filled.Settings, contentDescription = stringResource(R.string.action_settings))
        }
    }
}

@Composable
private fun HeroCard(
    snapshot: SolarSnapshot,
    districtName: String?,
    coordinates: String,
    waitingForFix: Boolean,
    extras: HeroExtras,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val solarSeconds = snapshot.trueSolarTime.toSecondOfDay().toDouble()
    val isDay = snapshot.isDay
    // 真太阳时落在关键时间段里时，数字与时间轴圆点一起换成该时段的配色。
    val inKeyTime = !waitingForFix && extras.bands.any { it.contains(solarSeconds / 60.0) }
    val accent = HeroPalette.accent(isDay)
    // 关键时段的色段一直画出来（与桌面卡片一致），只有「当前正落在某个关键时段里」时才把
    // 真太阳时数字与时间轴圆点也换成该时段的配色。
    val bandTint = if (waitingForFix) null else HeroPalette.band(extras.temperature, isDay)
    val inkTint = if (waitingForFix) null else HeroPalette.ink(extras.temperature, isDay)
    val solarColor = if (inKeyTime) inkTint ?: accent else accent
    val dateTail = listOf(extras.dateText, extras.weatherText, extras.rangeText)
        .filter { it.isNotBlank() }
        .joinToString(" · ")

    Box(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(18.dp))
            .background(Brush.linearGradient(HeroPalette.gradient(isDay)))
            .padding(16.dp),
    ) {
        Column(modifier = Modifier.fillMaxWidth()) {
            Row(modifier = Modifier.fillMaxWidth()) {
                // 左：当地标准时间（所在地的法定时区，标签直接写成 UTC+8 这种形式；
                // 中国境内就是北京时间，出国或手工指定外地坐标时换成当地标准时）
                Column(modifier = Modifier.weight(1f)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            text = TimeFormat.utcOffsetLabel(snapshot.localOffsetSeconds),
                            style = MaterialTheme.typography.labelMedium,
                            color = HeroPalette.LABEL,
                        )
                        Spacer(Modifier.weight(1f))
                        Text(
                            text = districtName ?: "",
                            style = MaterialTheme.typography.labelMedium,
                            color = HeroPalette.LABEL_DIM,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            textAlign = TextAlign.End,
                            modifier = Modifier.padding(start = 8.dp),
                        )
                    }
                    HeroClock(
                        text = TimeFormat.clock(snapshot.localStandardTime),
                        seconds = snapshot.localStandardTime.second,
                        color = Color.White,
                    )
                }

                Box(
                    modifier = Modifier
                        .padding(start = 12.dp, end = 12.dp, top = 3.dp)
                        .width(1.dp)
                        .height(58.dp)
                        .background(Color(0x33FFFFFF)),
                )

                // 右：真太阳时（逐秒刷新）
                Column(modifier = Modifier.weight(1f)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            text = stringResource(R.string.widget_label_solar),
                            style = MaterialTheme.typography.labelMedium,
                            color = HeroPalette.LABEL,
                        )
                        Spacer(Modifier.weight(1f))
                        Text(
                            text = stringResource(
                                R.string.hero_shichen,
                                // 时辰名走本地化字符串（英文本地化成 "Si hour"），与桌面卡片
                                // 用同一套；`snapshot.shichenName` 是固定的中文名，不能直接用，
                                // 否则英文界面下主页显示「巳时」、桌面卡片显示「Si hour」。
                                TimeText.shichenName(context, snapshot.shichenIndex),
                                TimeText.shichenHalf(context, snapshot.secondHalf),
                            ),
                            style = MaterialTheme.typography.labelMedium,
                            color = HeroPalette.LABEL_DIM,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            textAlign = TextAlign.End,
                            modifier = Modifier.padding(start = 8.dp),
                        )
                    }
                    if (waitingForFix) {
                        HeroClock(text = "--:--", seconds = null, color = solarColor)
                    } else {
                        HeroClock(
                            text = "%02d:%02d".format(snapshot.trueSolarTime.hour, snapshot.trueSolarTime.minute),
                            seconds = snapshot.trueSolarTime.second,
                            color = solarColor,
                        )
                    }                }
            }

            Spacer(Modifier.height(6.dp))

            // 日期/天气与经纬度同一行：日期行吃满剩余宽度，经纬度贴右。
            Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = dateTail,
                    style = MaterialTheme.typography.labelSmall,
                    color = HeroPalette.LABEL_DIM,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f),
                )
                Text(
                    text = coordinates,
                    style = MaterialTheme.typography.labelSmall,
                    color = HeroPalette.LABEL_DIM,
                    maxLines = 1,
                    modifier = Modifier.padding(start = 8.dp),
                )
            }

            Spacer(Modifier.height(10.dp))

            // 0–24 时时间轴：与桌面卡片、鸿蒙版同款（1vp 细线 + 柔化圆点）
            HeroAxis(
                solarSecondsOfDay = if (waitingForFix) 0.0 else solarSeconds,
                bands = if (waitingForFix) emptyList() else extras.bands,
                bandColor = bandTint,
                dotColor = if (inKeyTime && bandTint != null) bandTint else HeroPalette.DOT,
            )
            if (!waitingForFix && extras.hourly.isNotEmpty()) {
                Spacer(Modifier.height(10.dp))
                HeroHourly(extras.hourly)
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
    // 白天的数字用与淡金同浓度的淡绿/淡红，深绿/深红压在橙底上发闷。
    private val COLD_INK_ON_DAY: Color = Color(0xFFBCF5CA)
    private val HOT_INK_ON_DAY: Color = Color(0xFFFFC4C9)
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

    /** 关键时段里真太阳时数字的颜色。 */
    fun ink(temperature: TakeTemperature?, isDay: Boolean): Color? = when (temperature) {
        TakeTemperature.COLD_OR_MILD -> if (isDay) COLD_INK_ON_DAY else COLD
        TakeTemperature.HOT_OR_MILD -> if (isDay) HOT_INK_ON_DAY else HOT
        else -> null
    }

    /** 关键时段在时间轴上的色段与圆点颜色。 */
    fun band(temperature: TakeTemperature?, isDay: Boolean): Color? = when (temperature) {
        TakeTemperature.COLD_OR_MILD -> if (isDay) COLD_BAND_ON_DAY else COLD
        TakeTemperature.HOT_OR_MILD -> if (isDay) HOT_BAND_ON_DAY else HOT
        else -> null
    }
}

/** 时间轴：1vp 轨道 + 关键时段的色段 + 当前时刻的柔化圆点。 */
@Composable
private fun HeroAxis(
    solarSecondsOfDay: Double,
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
        val radius = 5.5.dp.toPx()
        val center = Offset(
            x = (size.width * (solarSecondsOfDay / SECONDS_PER_DAY).toFloat()).coerceIn(0f, size.width),
            y = middle,
        )
        drawCircle(
            brush = Brush.radialGradient(
                colors = listOf(dotColor, dotColor.copy(alpha = 0.45f), dotColor.copy(alpha = 0f)),
                center = center,
                radius = radius,
            ),
            radius = radius,
            center = center,
        )
    }
}

/** 六格逐时预报：时刻、天气图标、天气名称，与桌面卡片同一套取数规则。 */
@Composable
private fun HeroHourly(cells: List<HourCell>) {
    Row(modifier = Modifier.fillMaxWidth()) {
        cells.forEach { cell ->
            Column(
                modifier = Modifier.weight(1f),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text(
                    text = cell.label,
                    style = MaterialTheme.typography.labelSmall,
                    color = HeroPalette.LABEL_DIM,
                    maxLines = 1,
                )
                Image(
                    painter = painterResource(cell.iconRes),
                    contentDescription = null,
                    modifier = Modifier.padding(top = 3.dp).size(22.dp),
                )
                Text(
                    text = cell.condition,
                    style = MaterialTheme.typography.labelSmall,
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
 * 首页大卡片里的一格时间（`HH:mm` + 半高秒）。
 *
 * 两条硬规则：
 * 1. **秒是半高**：秒字号恒为主字号的 1/2；
 * 2. **整段时间正好撑满可用宽度**：用固定样本按 100sp 量出「主字号 + 半高秒」的实际宽度，
 *    再按这一栏的可用宽度反推主字号 —— 数字是等宽（`tnum`），所以不同时刻的宽度一致，
 *    不会忽宽忽窄。这样手机、平板（并排两栏、卡片被缩放）都自动铺满，不需要手调参数。
 */
@Composable
private fun HeroClock(text: String, seconds: Int?, color: Color, modifier: Modifier = Modifier) {
    val measurer = rememberTextMeasurer()
    val density = LocalDensity.current
    val baseStyle = TextStyle(fontWeight = FontWeight.Medium, fontFeatureSettings = "tnum")
    val probeSp = 100f
    // 用「88:88」与「:88」作样本：等宽数字下与实际渲染同宽，和具体时刻无关。
    val mainProbePx = measurer
        .measure("88:88", baseStyle.copy(fontSize = probeSp.sp), maxLines = 1)
        .size.width.toFloat()
    val secondsProbePx = if (seconds == null) {
        0f
    } else {
        measurer
            .measure(":88", baseStyle.copy(fontSize = (probeSp / 2f).sp), maxLines = 1)
            .size.width.toFloat()
    }
    val gapPx = if (seconds == null) 0f else with(density) { SECONDS_GAP.toPx() }
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
            style = baseStyle.copy(fontSize = mainSp.sp),
            color = color,
            maxLines = 1,
        )
        if (seconds != null) {
            Text(
                text = ":%02d".format(seconds),
                style = baseStyle.copy(fontSize = secondsSp.sp),
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
    modifier: Modifier = Modifier,
    arcHeight: Dp = 110.dp,
) {
    val context = LocalContext.current
    Card(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(24.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
    ) {
        Column(Modifier.padding(20.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = stringResource(R.string.sun_section_title),
                    style = MaterialTheme.typography.titleSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(Modifier.weight(1f))
                Text(
                    text = stringResource(R.string.altitude, snapshot.altitudeDegrees),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.primary,
                )
            }

            Spacer(Modifier.height(10.dp))

            SunArc(
                progress = daylightProgress(snapshot),
                isDay = snapshot.isDay,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(arcHeight),
            )

            Spacer(Modifier.height(10.dp))

            if (snapshot.polar == SolarTimeMath.PolarState.NORMAL) {
                Row(Modifier.fillMaxWidth()) {
                    SunTimeItem(stringResource(R.string.sunrise), snapshot.sunriseLocal, Modifier.weight(1f))
                    SunTimeItem(stringResource(R.string.solar_noon), snapshot.solarNoonLocal, Modifier.weight(1f))
                    SunTimeItem(stringResource(R.string.sunset), snapshot.sunsetLocal, Modifier.weight(1f))
                }
                Spacer(Modifier.height(10.dp))
                Text(
                    text = stringResource(
                        R.string.daylight_line,
                        TimeText.duration(context, snapshot.daylightSeconds),
                        TimeFormat.clock(snapshot.sunriseTrueSolar),
                        TimeFormat.clock(snapshot.sunsetTrueSolar),
                    ),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            } else {
                Text(
                    text = if (snapshot.polar == SolarTimeMath.PolarState.MIDNIGHT_SUN) {
                        stringResource(
                            R.string.polar_day,
                            TimeFormat.clock(snapshot.solarNoonLocal),
                        )
                    } else {
                        stringResource(
                            R.string.polar_night,
                            TimeFormat.clock(snapshot.solarNoonLocal),
                        )
                    },
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun SunTimeItem(label: String, time: LocalTime?, modifier: Modifier = Modifier) {
    Column(modifier = modifier, horizontalAlignment = Alignment.CenterHorizontally) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.height(2.dp))
        Text(
            text = TimeFormat.clock(time),
            style = TextStyle(fontSize = 17.sp, fontWeight = FontWeight.Medium, fontFeatureSettings = "tnum"),
            color = MaterialTheme.colorScheme.onSurface,
            textAlign = TextAlign.Center,
        )
    }
}

@Composable
private fun SunArc(progress: Float, isDay: Boolean, modifier: Modifier = Modifier) {
    val trackColor = MaterialTheme.colorScheme.outlineVariant
    val sunColor = if (isDay) Color(0xFFFFB300) else MaterialTheme.colorScheme.outline

    Canvas(modifier) {
        val horizonY = size.height * 0.88f
        val start = Offset(size.width * 0.06f, horizonY)
        val end = Offset(size.width * 0.94f, horizonY)
        val control = Offset(size.width / 2f, -size.height * 0.42f)

        val arc = Path().apply {
            moveTo(start.x, start.y)
            quadraticTo(control.x, control.y, end.x, end.y)
        }
        drawPath(
            path = arc,
            color = trackColor,
            style = Stroke(width = 2.5f, pathEffect = PathEffect.dashPathEffect(floatArrayOf(10f, 10f))),
        )
        drawLine(trackColor, Offset(0f, horizonY), Offset(size.width, horizonY), strokeWidth = 2f)

        val t = progress.coerceIn(0f, 1f)
        val u = 1f - t
        val sunX = u * u * start.x + 2f * u * t * control.x + t * t * end.x
        val sunY = u * u * start.y + 2f * u * t * control.y + t * t * end.y
        val center = Offset(sunX, sunY)
        if (isDay) {
            drawCircle(sunColor.copy(alpha = 0.18f), radius = 20f, center = center)
        }
        drawCircle(sunColor, radius = 7f, center = center)
    }
}

private fun daylightProgress(snapshot: SolarSnapshot): Float {
    val sunrise = snapshot.sunriseTrueSolar ?: return 0.5f
    val sunset = snapshot.sunsetTrueSolar ?: return 0.5f
    val start = sunrise.toSecondOfDay().toFloat()
    var end = sunset.toSecondOfDay().toFloat()
    if (end <= start) end += 86_400f
    var current = snapshot.trueSolarTime.toSecondOfDay().toFloat()
    if (current < start) current += 86_400f
    return ((current - start) / (end - start)).coerceIn(0f, 1f)
}

/** Compose 的 LocalView.context 可能是 ContextWrapper 包了几层，取出宿主 Activity。 */
private tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}
