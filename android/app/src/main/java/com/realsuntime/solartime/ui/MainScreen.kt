package com.realsuntime.solartime.ui

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Canvas
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
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
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
import com.realsuntime.solartime.solar.Shichen
import com.realsuntime.solartime.solar.SolarSnapshot
import com.realsuntime.solartime.solar.SolarTimeMath
import com.realsuntime.solartime.solar.SolarTimeSnapshot
import com.realsuntime.solartime.solar.TimeFormat
import java.time.LocalTime

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MainScreen(viewModel: MainViewModel = viewModel()) {
    val now by viewModel.now.collectAsStateWithLifecycle()
    val place by viewModel.place.collectAsStateWithLifecycle()
    val trackingGps by viewModel.trackingGps.collectAsStateWithLifecycle()
    val waitingForFix by viewModel.waitingForFix.collectAsStateWithLifecycle()
    val remindersEnabled by viewModel.remindersEnabled.collectAsStateWithLifecycle()
    val hourlyChimeEnabled by viewModel.hourlyChimeEnabled.collectAsStateWithLifecycle()
    val mapStyle by viewModel.mapStyle.collectAsStateWithLifecycle()
    val message by viewModel.message.collectAsStateWithLifecycle()

    val context = LocalContext.current
    val snackbarHostState = remember { SnackbarHostState() }
    var showSettings by rememberSaveable { mutableStateOf(false) }

    val snapshot = remember(now, place) {
        SolarTimeSnapshot.compute(now, place.latitude, place.longitude)
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

    val notificationPermissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted ->
        viewModel.setRemindersEnabled(true)
        if (!granted) {
            viewModel.postMessage(context.getString(R.string.msg_notification_reminder))
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
        when {
            !enabled -> viewModel.setRemindersEnabled(false)
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                ContextCompat.checkSelfPermission(
                    context,
                    Manifest.permission.POST_NOTIFICATIONS,
                ) != PackageManager.PERMISSION_GRANTED -> notificationPermissionLauncher.launch(
                Manifest.permission.POST_NOTIFICATIONS,
            )
            else -> viewModel.setRemindersEnabled(true)
        }
    }

    val toggleHourlyChime: (Boolean) -> Unit = { enabled ->
        // 报时只播提示音，不需要通知权限。
        viewModel.setHourlyChimeEnabled(enabled)
    }

    LaunchedEffect(message) {
        message?.let {
            snackbarHostState.showSnackbar(it)
            viewModel.consumeMessage()
        }
    }

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
            Header(onOpenSettings = { showSettings = true })
            Spacer(Modifier.height(12.dp))

            HeroCard(
                snapshot = snapshot,
                placeLabel = place.label,
                trackingGps = trackingGps,
                waitingForFix = waitingForFix,
            )
            Spacer(Modifier.height(14.dp))

            BeijingCard(snapshot = snapshot)
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
            hourlyChimeEnabled = hourlyChimeEnabled,
            mapStyle = mapStyle,
            onDismiss = { showSettings = false },
            onRequestGps = {
                showSettings = false
                requestGps()
            },
            onApplyManual = { lat, lon, label -> viewModel.applyManualPlace(lat, lon, label) },
            onToggleReminders = toggleReminders,
            onToggleHourlyChime = toggleHourlyChime,
            onSelectMapStyle = viewModel::setMapStyle,
        )
    }
}

@Composable
private fun Header(onOpenSettings: () -> Unit) {
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
        IconButton(onClick = onOpenSettings) {
            Icon(Icons.Filled.Settings, contentDescription = stringResource(R.string.action_settings))
        }
    }
}

@Composable
private fun HeroCard(
    snapshot: SolarSnapshot,
    placeLabel: String,
    trackingGps: Boolean,
    waitingForFix: Boolean,
) {
    val gradient = if (snapshot.isDay) {
        listOf(Color(0xFFF7A64B), Color(0xFFEA7A2C))
    } else {
        listOf(Color(0xFF2A3B5C), Color(0xFF151B2E))
    }
    val onHero = Color.White
    val nextShichen = TimeText.shichenName(LocalContext.current, (snapshot.shichenIndex + 1) % 12)
    val quarterText = TimeText.shichenQuarter(LocalContext.current, snapshot.shichenQuarter)
    val statusLabel = if (waitingForFix) stringResource(R.string.gps_waiting) else placeLabel

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(28.dp))
            .background(Brush.linearGradient(gradient))
            .padding(22.dp),
    ) {
        Column {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = if (trackingGps) stringResource(R.string.hero_title_tracking) else stringResource(R.string.hero_title),
                    style = MaterialTheme.typography.labelLarge,
                    color = onHero.copy(alpha = 0.85f),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f, fill = false),
                )
                Spacer(Modifier.weight(1f))
                Surface(
                    color = onHero.copy(alpha = 0.18f),
                    shape = RoundedCornerShape(50),
                ) {
                    Text(
                        text = statusLabel,
                        style = MaterialTheme.typography.labelMedium,
                        color = onHero,
                        maxLines = 1,
                        modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
                    )
                }
            }

            Spacer(Modifier.height(4.dp))

            Row(verticalAlignment = Alignment.Bottom) {
                Text(
                    text = "%02d:%02d".format(snapshot.trueSolarTime.hour, snapshot.trueSolarTime.minute),
                    style = TextStyle(
                        fontSize = 72.sp,
                        fontWeight = FontWeight.Light,
                        letterSpacing = (-2).sp,
                        fontFeatureSettings = "tnum",
                    ),
                    color = onHero,
                )
                Text(
                    text = "%02d".format(snapshot.trueSolarTime.second),
                    style = TextStyle(
                        fontSize = 26.sp,
                        fontWeight = FontWeight.Medium,
                        fontFeatureSettings = "tnum",
                    ),
                    color = onHero.copy(alpha = 0.75f),
                    modifier = Modifier.padding(start = 6.dp, bottom = 12.dp),
                )
            }

            Spacer(Modifier.height(16.dp))

            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                    modifier = Modifier
                        .size(54.dp)
                        .clip(CircleShape)
                        .background(onHero.copy(alpha = 0.18f)),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        text = snapshot.shichenName.take(1),
                        style = TextStyle(fontSize = 28.sp, fontWeight = FontWeight.Medium),
                        color = onHero,
                    )
                }
                Spacer(Modifier.width(14.dp))
                Column {
                    Text(
                        text = stringResource(
                            R.string.shichen_summary,
                            TimeText.shichenName(LocalContext.current, snapshot.shichenIndex),
                            TimeText.shichenHalf(LocalContext.current, snapshot.secondHalf),
                            quarterText,
                        ),
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                        color = onHero,
                    )
                    Text(
                        text = stringResource(
                            R.string.shichen_countdown,
                            snapshot.shichenRange,
                            TimeText.shichenName(LocalContext.current, (snapshot.shichenIndex + 1) % 12),
                            TimeFormat.countdown(snapshot.secondsToNextShichen),
                        ),
                        style = MaterialTheme.typography.bodySmall,
                        color = onHero.copy(alpha = 0.8f),
                    )
                }
            }
        }
    }
}

@Composable
private fun BeijingCard(snapshot: SolarSnapshot) {
    val context = LocalContext.current
    val faster = snapshot.offsetSeconds >= 0
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(24.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
    ) {
        Column(Modifier.padding(20.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = stringResource(R.string.beijing_time_title),
                    style = MaterialTheme.typography.titleSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(Modifier.weight(1f))
                Text(
                    text = TimeText.dateWithWeekday(context, snapshot.beijingDate),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Spacer(Modifier.height(4.dp))
            Text(
                text = TimeFormat.clockWithSeconds(snapshot.beijingTime),
                style = TextStyle(
                    fontSize = 34.sp,
                    fontWeight = FontWeight.Medium,
                    fontFeatureSettings = "tnum",
                ),
                color = MaterialTheme.colorScheme.onSurface,
            )
            Spacer(Modifier.height(12.dp))
            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
            Spacer(Modifier.height(12.dp))
            Text(
                text = stringResource(
                    if (faster) R.string.offset_faster else R.string.offset_slower,
                    TimeText.minutesSeconds(context, snapshot.offsetSeconds),
                ),
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurface,
            )
            Spacer(Modifier.height(6.dp))
            Text(
                text = stringResource(
                    R.string.longitude_correction,
                    TimeText.signedDuration(context, snapshot.longitudeOffsetSeconds),
                ) + "　" + stringResource(
                    R.string.equation_of_time,
                    TimeText.signedDuration(context, snapshot.equationOfTimeSeconds),
                ),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
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
