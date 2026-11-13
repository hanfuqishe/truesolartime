package com.realsuntime.solartime.ui

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
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
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
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
    val mapStyle by viewModel.mapStyle.collectAsStateWithLifecycle()
    val message by viewModel.message.collectAsStateWithLifecycle()

    val context = LocalContext.current
    val snackbarHostState = remember { SnackbarHostState() }
    var showSettings by rememberSaveable { mutableStateOf(false) }

    val snapshot = remember(now, place) {
        SolarTimeSnapshot.compute(now, place.latitude, place.longitude)
    }

    // 大卡片里的日期、天气、逐时预报与关键时段：半分钟刷新一次就够，不必每秒读偏好；
    // 但新数据一到（例如刚换了城市、天气刚取回来）要立刻重算，所以把天气版本号也当键。
    val weatherRevision = WeatherRepository.revision()
    val heroExtras = remember(place, now.epochSecond / 30, weatherRevision) {
        loadHeroExtras(context, place, now)
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

    // 主题跟着太阳走：白天浅色，夜晚整体换深色（不再看系统的深色开关）。
    TrueSolarTimeTheme(darkTheme = !snapshot.isDay) {
        Scaffold(
            containerColor = MaterialTheme.colorScheme.background,
            snackbarHost = { SnackbarHost(snackbarHostState) },
        ) { padding ->
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 20.dp),
            ) {
                Header(
                    badge = if (place.source == PlaceSource.GPS) {
                        stringResource(R.string.location_badge_gps)
                    } else {
                        districtName.orEmpty()
                    },
                    onOpenSettings = { showSettings = true },
                )
                Spacer(Modifier.height(12.dp))

                HeroCard(
                    snapshot = snapshot,
                    districtName = districtName,
                    coordinates = TimeText.coordinates(context, place.latitude, place.longitude),
                    waitingForFix = waitingForFix,
                    extras = heroExtras,
                )
                Spacer(Modifier.height(14.dp))

                SunCard(snapshot = snapshot)
                Spacer(Modifier.height(14.dp))

                MapCard(place = place, mapStyle = mapStyle)
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

        if (showSettings) {
            SettingsSheet(
                place = place,
                trackingGps = trackingGps,
                remindersEnabled = remindersEnabled,
                keyTimeChimeEnabled = keyTimeChimeEnabled,
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
                onAddWidget = viewModel::requestPinWidget,
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
        Column(Modifier.weight(1f)) {
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
                modifier = Modifier.padding(end = 6.dp),
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
    val solarColor = if (inKeyTime) bandTint ?: accent else accent
    val dateTail = listOf(extras.dateText, extras.weatherText, extras.rangeText)
        .filter { it.isNotBlank() }
        .joinToString(" · ")

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(18.dp))
            .background(Brush.linearGradient(HeroPalette.gradient(isDay)))
            .padding(16.dp),
    ) {
        Column(modifier = Modifier.fillMaxWidth()) {
            Row(modifier = Modifier.fillMaxWidth()) {
                // 左：标准时间（与桌面卡片一致，用北京时间）
                Column(modifier = Modifier.weight(1f)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            text = stringResource(R.string.widget_label_civil),
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
                        text = TimeFormat.clock(snapshot.beijingTime),
                        seconds = snapshot.beijingTime.second,
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
                                snapshot.shichenName,
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
    private val COLD: Color = Color(0xFF4CAF7D)
    private val HOT: Color = Color(0xFFD9534F)
    // 白天橙色底上亮绿/亮红太抢眼，暗一档反而更清楚（与 KeyTimePalette 的考量一致）。
    private val COLD_ON_DAY: Color = Color(0xFF2E7D32)
    private val HOT_ON_DAY: Color = Color(0xFFB3261E)

    fun gradient(isDay: Boolean): List<Color> = if (isDay) {
        listOf(Color(0xFFF7A64B), Color(0xFFEA7A2C))
    } else {
        listOf(Color(0xFF2A3B5C), Color(0xFF151B2E))
    }

    /** 真太阳时的强调色：白天用白字，夜里用金色。 */
    fun accent(isDay: Boolean): Color = if (isDay) Color.White else GOLD

    fun band(temperature: TakeTemperature?, isDay: Boolean): Color? = when (temperature) {
        TakeTemperature.COLD_OR_MILD -> if (isDay) COLD_ON_DAY else COLD
        TakeTemperature.HOT_OR_MILD -> if (isDay) HOT_ON_DAY else HOT
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

@Composable
private fun HeroClock(text: String, seconds: Int?, color: Color) {
    Row(verticalAlignment = Alignment.Bottom) {
        Text(
            text = text,
            style = TextStyle(
                fontSize = 42.sp,
                fontWeight = FontWeight.Light,
                fontFeatureSettings = "tnum",
            ),
            color = color,
            maxLines = 1,
        )
        if (seconds != null) {
            Text(
                text = ":%02d".format(seconds),
                style = TextStyle(
                    fontSize = 23.sp,
                    fontWeight = FontWeight.Light,
                    fontFeatureSettings = "tnum",
                ),
                color = color,
                maxLines = 1,
                modifier = Modifier.padding(start = 1.dp, bottom = 5.dp),
            )
        }
    }
}

@Composable
private fun SunCard(snapshot: SolarSnapshot) {
    val context = LocalContext.current
    Card(
        modifier = Modifier.fillMaxWidth(),
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
                    .height(110.dp),
            )

            Spacer(Modifier.height(10.dp))

            if (snapshot.polar == SolarTimeMath.PolarState.NORMAL) {
                Row(Modifier.fillMaxWidth()) {
                    SunTimeItem(stringResource(R.string.sunrise), snapshot.sunriseBeijing, Modifier.weight(1f))
                    SunTimeItem(stringResource(R.string.solar_noon), snapshot.solarNoonBeijing, Modifier.weight(1f))
                    SunTimeItem(stringResource(R.string.sunset), snapshot.sunsetBeijing, Modifier.weight(1f))
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
                            TimeFormat.clock(snapshot.solarNoonBeijing),
                        )
                    } else {
                        stringResource(
                            R.string.polar_night,
                            TimeFormat.clock(snapshot.solarNoonBeijing),
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
