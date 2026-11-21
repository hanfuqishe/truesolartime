package com.realsuntime.solartime.ui

import android.content.Context
import androidx.compose.foundation.clickable
import androidx.compose.foundation.BorderStroke
import androidx.compose.material3.Surface
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.TextButton
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.realsuntime.solartime.R
import com.realsuntime.solartime.data.CityRegion
import com.realsuntime.solartime.data.Place
import com.realsuntime.solartime.data.ThemeMode
import com.realsuntime.solartime.data.WeatherRepository
import com.realsuntime.solartime.map.MapSourceAttribution
import com.realsuntime.solartime.map.MapStyle
import com.realsuntime.solartime.solar.TimeFormat
import com.realsuntime.solartime.widget.ChimeAlarm
import com.realsuntime.solartime.widget.WidgetUpdater
import androidx.compose.runtime.DisposableEffect
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun SettingsSheet(
    place: Place,
    trackingGps: Boolean,
    /** 定位不可用（未知态）：「当前位置」那一行不能写上一个地点的名字与经纬度。 */
    locationUnknown: Boolean = false,
    remindersEnabled: Boolean,
    keyTimeChimeEnabled: Boolean,
    keepScreenOn: Boolean,
    mapStyle: MapStyle,
    themeMode: ThemeMode,
    onDismiss: () -> Unit,
    onRequestGps: () -> Unit,
    onApplyManual: (Double, Double, String) -> Unit,
    /** 选中常用城市：整个 [Place] 传出去，国家码与资源名才不会丢。 */
    onSelectPreset: (Place) -> Unit,
    onToggleReminders: (Boolean) -> Unit,
    onToggleKeyTimeChime: (Boolean) -> Unit,
    onToggleKeepScreenOn: (Boolean) -> Unit,
    onSelectMapStyle: (MapStyle) -> Unit,
    onSelectTheme: (ThemeMode) -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val context = LocalContext.current
    var latitudeText by remember(place) { mutableStateOf("%.4f".format(place.latitude)) }
    var longitudeText by remember(place) { mutableStateOf("%.4f".format(place.longitude)) }
    var error by remember { mutableStateOf<String?>(null) }
    // 桌面上已有的小组件数量：>0 时分钟刷新同样依赖精确闹钟权限，要一并提示。
    var pinnedWidgets by remember { mutableStateOf(WidgetUpdater.pinnedCount(context)) }
    // 「添加到桌面」的结果提示（null 时显示常规说明）。
    var widgetMessage by remember { mutableStateOf<String?>(null) }
    val lifecycleOwner = LocalLifecycleOwner.current
    // 结算上一次「添加到桌面」：桌面加成功后会把桌面切到前台、我们的界面进后台，
    // 所以在回到本页（ON_RESUME）时再比对实例数，才知道到底加没加上。
    DisposableEffect(lifecycleOwner, context) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                when (WidgetUpdater.consumePinOutcome(context)) {
                    WidgetUpdater.PinOutcome.ADDED -> {
                        pinnedWidgets = WidgetUpdater.pinnedCount(context)
                        widgetMessage = context.getString(R.string.widget_add_done)
                    }

                    WidgetUpdater.PinOutcome.NOT_ADDED -> {
                        widgetMessage = context.getString(R.string.widget_add_manual)
                    }

                    null -> Unit
                }
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        var showDiagnostics by remember { mutableStateOf(false) }
        if (showDiagnostics) {
            DiagnosticsDialog(onDismiss = { showDiagnostics = false })
        }
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 24.dp)
                .padding(bottom = 36.dp),
        ) {
            Text(stringResource(R.string.settings_title), style = MaterialTheme.typography.titleLarge)
            Spacer(Modifier.height(16.dp))

            Text(
                text = stringResource(R.string.settings_current_location),
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.primary,
            )
            Spacer(Modifier.height(6.dp))
            Text(
                // 未知态：位置就是「不知道」，不要写上一个城市（那是要避免的误导）。
                text = if (locationUnknown) {
                    stringResource(R.string.location_unavailable)
                } else {
                    "${TimeText.placeLabel(context, place)}　${TimeText.coordinates(context, place.latitude, place.longitude)}"
                },
                style = MaterialTheme.typography.bodyMedium,
            )
            Spacer(Modifier.height(12.dp))
            // 与下方「应用坐标」**同款主按钮**：同一个 Material3 `Button` + 同一套颜色/高度/圆角，
            // 不抄颜色值（主色改了这里自动跟着变）。选中态（跟随中）用主色底 + 白色进度环表达。
            Button(
                onClick = onRequestGps,
                modifier = Modifier.fillMaxWidth(),
            ) {
                if (trackingGps) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(18.dp),
                        strokeWidth = 2.dp,
                        color = MaterialTheme.colorScheme.onPrimary,
                    )
                    Spacer(Modifier.width(10.dp))
                }
                // 文案与鸿蒙版一致：跟随中也是「实时跟随GPS」，不改成「重新开始…」（点它本来就是重取一次定位）。
                Text(stringResource(R.string.action_use_gps))
            }

            Spacer(Modifier.height(22.dp))
            Text(
                text = stringResource(R.string.section_manual),
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.primary,
            )
            Spacer(Modifier.height(8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                OutlinedTextField(
                    value = latitudeText,
                    onValueChange = { latitudeText = it; error = null },
                    label = { Text(stringResource(R.string.label_latitude)) },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                    modifier = Modifier.weight(1f),
                )
                OutlinedTextField(
                    value = longitudeText,
                    onValueChange = { longitudeText = it; error = null },
                    label = { Text(stringResource(R.string.label_longitude)) },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                    modifier = Modifier.weight(1f),
                )
            }
            if (error != null) {
                Spacer(Modifier.height(4.dp))
                Text(
                    text = error.orEmpty(),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error,
                )
            }
            Spacer(Modifier.height(10.dp))
            Button(
                onClick = {
                    val latitude = latitudeText.trim().toDoubleOrNull()
                    val longitude = longitudeText.trim().toDoubleOrNull()
                    when {
                        latitude == null || latitude !in Place.MIN_LATITUDE..Place.MAX_LATITUDE ->
                            error = context.getString(R.string.error_latitude)
                        longitude == null || longitude !in Place.MIN_LONGITUDE..Place.MAX_LONGITUDE ->
                            error = context.getString(R.string.error_longitude)
                        else -> {
                            onApplyManual(latitude, longitude, context.getString(R.string.label_manual_place))
                            onDismiss()
                        }
                    }
                },
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(stringResource(R.string.action_apply))
            }

            Spacer(Modifier.height(18.dp))
            Text(
                text = stringResource(R.string.section_cities),
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.primary,
            )
            Spacer(Modifier.height(4.dp))
            // 常用城市：**内容宽 chip + 自动折行**（与 iOS 的流式布局一致）。
            // 不用 FlowRow（SubcomposeLayout，本仓库硬性禁用）；纯函数 `packRows` 先算行，
            // 再用 Row 手工渲染。chip 宽度**实测**（TextMeasurer 量 12sp 城市名）+ 左右各 10dp。
            val screenWidthDp = LocalConfiguration.current.screenWidthDp.toFloat()
            val contentWidthDp = (screenWidthDp - 2 * 24f).coerceAtLeast(0f)
            val chipStyle = MaterialTheme.typography.labelMedium.copy(fontSize = PresetGrid.TEXT_SIZE_SP.sp)
            val textMeasurer = rememberTextMeasurer()
            val density = LocalDensity.current
            fun measuredWidthDp(preset: Place): Float {
                val measured = textMeasurer.measure(
                    text = TimeText.placeLabel(context, preset),
                    style = chipStyle,
                    maxLines = 1,
                    softWrap = false,
                ).size.width
                return with(density) { measured.toDp().value } + 2f * PresetGrid.CHIP_PADDING_DP
            }
            // 按大洲分组：组标题 + 组内流式 chips（内容宽 + 两端对齐）。
            Column {
                CityRegion.entries.forEachIndexed { groupIndex, region ->
                    val cities = Place.PRESETS.filter { it.region == region }
                    if (cities.isEmpty()) return@forEachIndexed
                    if (groupIndex > 0) Spacer(Modifier.height(10.dp))
                    Text(
                        text = stringResource(regionTitleRes(region)),
                        style = MaterialTheme.typography.labelSmall.copy(fontSize = 11.sp),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Spacer(Modifier.height(4.dp))
                    val widths = cities.map { measuredWidthDp(it) }
                    val rows = PresetGrid.packRows(widths, contentWidthDp, PresetGrid.GAP_DP)
                    Column(verticalArrangement = Arrangement.spacedBy(PresetGrid.ROW_GAP_DP.dp)) {
                        rows.forEachIndexed { rowIndex, row ->
                            val spacedToEdges = rowIndex != rows.lastIndex && row.size > 1
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = if (spacedToEdges) {
                                    Arrangement.SpaceBetween
                                } else {
                                    Arrangement.spacedBy(PresetGrid.GAP_DP.dp)
                                },
                            ) {
                                row.forEach { index ->
                                    val preset = cities[index]
                                    val widthDp = widths[index].coerceAtMost(contentWidthDp)
                                    Surface(
                                        onClick = {
                                            onSelectPreset(preset)
                                            onDismiss()
                                        },
                                        modifier = Modifier
                                            .width(widthDp.dp)
                                            .height(PresetGrid.CHIP_HEIGHT_DP.dp),
                                        shape = RoundedCornerShape(8.dp),
                                        color = MaterialTheme.colorScheme.surface,
                                        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
                                    ) {
                                        Box(
                                            modifier = Modifier
                                                .fillMaxSize()
                                                .padding(horizontal = PresetGrid.CHIP_PADDING_DP.dp),
                                            contentAlignment = Alignment.Center,
                                        ) {
                                            Text(
                                                text = TimeText.placeLabel(context, preset),
                                                style = chipStyle,
                                                maxLines = 1,
                                                softWrap = false,
                                                overflow = TextOverflow.Ellipsis,
                                                textAlign = TextAlign.Center,
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            Spacer(Modifier.height(18.dp))
            Text(
                text = stringResource(R.string.section_map),
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.primary,
            )
            Spacer(Modifier.height(4.dp))
            Text(
                text = stringResource(R.string.map_auto_hint),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.height(6.dp))
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                MapStyle.manualOptions.forEach { style ->
                    FilterChip(
                        selected = style == mapStyle,
                        onClick = { onSelectMapStyle(style) },
                        label = { Text(MapText.label(context, style)) },
                    )
                }
            }

            Spacer(Modifier.height(18.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(stringResource(R.string.reminder_title), style = MaterialTheme.typography.titleSmall)
                    Text(
                        text = stringResource(R.string.reminder_desc),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Switch(checked = remindersEnabled, onCheckedChange = onToggleReminders)
            }

            Spacer(Modifier.height(14.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(stringResource(R.string.chime_title), style = MaterialTheme.typography.titleSmall)
                    Text(
                        text = stringResource(R.string.chime_desc),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Switch(checked = keyTimeChimeEnabled, onCheckedChange = onToggleKeyTimeChime)
            }

            // 没有「闹钟和提醒」权限时，报时只能退化为可延迟闹钟（可能晚几分钟响）；
            // 小组件的分钟刷新也靠精确闹钟，桌面上有实例时同样需要提示。
            if (!ChimeAlarm.canScheduleExact(context) &&
                (remindersEnabled || keyTimeChimeEnabled || pinnedWidgets > 0)
            ) {
                TextButton(
                    onClick = { PowerSettings.openExactAlarmSettings(context) },
                    contentPadding = PaddingValues(0.dp),
                ) {
                    Text(
                        text = stringResource(R.string.chime_exact_alarm_hint),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error,
                    )
                }
            }

            // 华为/荣耀会冻结后台应用、延迟广播，报时可能因此晚响；这里给一个直达入口。
            TextButton(
                onClick = { PowerSettings.openBackgroundSettings(context) },
                contentPadding = PaddingValues(0.dp),
            ) {
                Text(
                    text = stringResource(R.string.chime_background_hint),
                    style = MaterialTheme.typography.bodySmall,
                )
            }

            Spacer(Modifier.height(14.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(stringResource(R.string.keep_screen_on_title), style = MaterialTheme.typography.titleSmall)
                    Text(
                        text = stringResource(R.string.keep_screen_on_desc),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Switch(checked = keepScreenOn, onCheckedChange = onToggleKeepScreenOn)
            }

            // 外观：主题。与「屏幕常亮」同属「外观 / 屏幕」这一片。
            // 默认「自动」＝按日出日落（旧版本行为）；亮色/暗色是强制，首页大卡片与桌面卡片一起跟随。
            Spacer(Modifier.height(14.dp))
            Text(stringResource(R.string.theme_title), style = MaterialTheme.typography.titleSmall)
            Spacer(Modifier.height(2.dp))
            Text(
                text = stringResource(R.string.theme_desc),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.height(6.dp))
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                ThemeMode.entries.forEach { mode ->
                    FilterChip(
                        selected = mode == themeMode,
                        onClick = { onSelectTheme(mode) },
                        label = { Text(themeLabel(context, mode)) },
                    )
                }
            }

            Spacer(Modifier.height(18.dp))
            // 「添加到桌面」放在页面下方、「诊断」正上方（不再夹在提醒开关之前）：
            // 它是一次性动作，不是常用开关，跟着「关于/诊断」这类低频入口更顺。
            Text(
                text = stringResource(R.string.section_widget),
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.primary,
            )
            Spacer(Modifier.height(6.dp))
            FilledTonalButton(
                onClick = {
                    // 各桌面对「应用内添加」的支持参差不齐：Pixel 桌面会弹确认框，
                    // 华为桌面也弹，但桌面这一屏满了就只 toast 一句「当前屏幕已经没有空间」，
                    // 小米/红米甚至返回成功却什么都不做。所以只负责发出请求 + 记一笔基线，
                    // 真正是否加上，等用户回到本页时用实例数结算（见上面的 ON_RESUME）。
                    val requested = WidgetUpdater.requestPin(context)
                    widgetMessage = if (requested) {
                        context.getString(R.string.widget_add_waiting)
                    } else {
                        context.getString(R.string.widget_add_manual)
                    }
                },
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(stringResource(R.string.widget_add_action))
            }
            Spacer(Modifier.height(6.dp))
            Text(
                text = widgetMessage ?: stringResource(R.string.widget_add_desc),
                style = MaterialTheme.typography.bodySmall,
                color = if (widgetMessage == null) {
                    MaterialTheme.colorScheme.onSurfaceVariant
                } else {
                    MaterialTheme.colorScheme.primary
                },
            )

            Spacer(Modifier.height(20.dp))
            HorizontalDivider()
            Spacer(Modifier.height(14.dp))
            Spacer(Modifier.height(20.dp))
            HorizontalDivider()
            Spacer(Modifier.height(14.dp))
            // 桌面卡片校准：高度 / 宽度二选一，卡片刻度尺让用户直接读数。
            Text(stringResource(R.string.section_widget_calibration), style = MaterialTheme.typography.labelLarge)
            Spacer(Modifier.height(4.dp))
            Text(
                text = stringResource(R.string.widget_calibration_hint),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.height(6.dp))
            var target by remember { mutableStateOf(WidgetUpdater.calibrationTarget(context)) }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf(
                    R.string.calibration_off to 0,
                    R.string.calibration_height to 1,
                    R.string.calibration_width to 2,
                ).forEach { (res, value) ->
                    FilterChip(
                        selected = target == value,
                        onClick = {
                            target = value
                            WidgetUpdater.setCalibrationTarget(context, value)
                            WidgetUpdater.refreshAll(context, forceChronometer = true)
                        },
                        label = { Text(stringResource(res)) },
                    )
                }
            }
            Spacer(Modifier.height(8.dp))
            var heightText by remember {
                mutableStateOf(WidgetUpdater.heightOverrideDp(context).takeIf { it > 0 }?.toString().orEmpty())
            }
            var widthText by remember {
                mutableStateOf(WidgetUpdater.widthOverrideDp(context).takeIf { it > 0 }?.toString().orEmpty())
            }
            OutlinedTextField(
                value = heightText,
                onValueChange = { raw ->
                    val digits = raw.filter { it.isDigit() }.take(3)
                    heightText = digits
                    WidgetUpdater.setHeightOverrideDp(context, digits.toIntOrNull() ?: 0)
                    WidgetUpdater.refreshAll(context)
                },
                label = { Text(stringResource(R.string.widget_height_override)) },
                suffix = { Text(stringResource(R.string.widget_height_unit)) },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                modifier = Modifier.fillMaxWidth(),
            )
            Spacer(Modifier.height(8.dp))
            OutlinedTextField(
                value = widthText,
                onValueChange = { raw ->
                    val digits = raw.filter { it.isDigit() }.take(3)
                    widthText = digits
                    WidgetUpdater.setWidthOverrideDp(context, digits.toIntOrNull() ?: 0)
                    WidgetUpdater.refreshAll(context)
                },
                label = { Text(stringResource(R.string.widget_width_override)) },
                suffix = { Text(stringResource(R.string.widget_height_unit)) },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                modifier = Modifier.fillMaxWidth(),
            )
            Spacer(Modifier.height(6.dp))
            TextButton(
                onClick = {
                    WidgetUpdater.resetCalibration(context)
                    target = 0
                    heightText = ""
                    widthText = ""
                    WidgetUpdater.refreshAll(context, forceChronometer = true)
                },
            ) { Text(stringResource(R.string.widget_reset_auto)) }
            Text(stringResource(R.string.section_diagnostics), style = MaterialTheme.typography.labelLarge)
            Spacer(Modifier.height(4.dp))
            Text(
                text = stringResource(R.string.diagnostics_desc),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.height(8.dp))
            OutlinedButton(onClick = { showDiagnostics = true }) {
                Text(stringResource(R.string.diagnostics_open))
            }

            Spacer(Modifier.height(20.dp))
            HorizontalDivider()
            Spacer(Modifier.height(14.dp))
            Text(stringResource(R.string.section_about), style = MaterialTheme.typography.labelLarge)
            Spacer(Modifier.height(6.dp))
            Text(
                text = stringResource(R.string.about_body),


                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.height(6.dp))
            // 天气来源随实际数据源切换：降级到 7Timer! 后不能还署 Open-Meteo 的名。
            Text(
                text = TimeText.weatherAttribution(context, WeatherRepository.source(context)),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            Spacer(Modifier.height(20.dp))
            HorizontalDivider()
            Spacer(Modifier.height(14.dp))
            // 地图数据来源：卡片底部只放 4 个主要来源的短署名；这里是**完整署名**（英文原文），
            // 按当前实际使用的源切换，可点击打开版权页。Esri 的 copyrightText 有 14 个来源，
            // 卡片一行放不下，只列 4 个又不合规，所以分两层。
            Text(stringResource(R.string.section_map_sources), style = MaterialTheme.typography.labelLarge)
            Spacer(Modifier.height(6.dp))
            val mapSource = MapSourceAttribution.resolveSource(
                style = mapStyle,
                latitude = place.latitude,
                longitude = place.longitude,
                countryCode = place.countryCode,
            )
            val sourceNote = MapSourceAttribution.noteFor(
                source = mapSource,
                osmText = stringResource(R.string.map_sources_osm),
                amapText = stringResource(R.string.map_sources_amap),
            )
            val uriHandler = LocalUriHandler.current
            Text(
                text = sourceNote.text,
                style = MaterialTheme.typography.labelSmall.copy(fontSize = 10.sp),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 6,
                modifier = if (sourceNote.url != null) {
                    Modifier.clickable { uriHandler.openUri(sourceNote.url) }
                } else {
                    Modifier
                },
            )
        }
    }
}

/** 主题选项的本地化名称：自动 / 亮色 / 暗色。 */
/** 大洲分组标题的资源 id。 */
private fun regionTitleRes(region: CityRegion): Int = when (region) {
    CityRegion.ASIA -> R.string.region_asia
    CityRegion.EUROPE -> R.string.region_europe
    CityRegion.AFRICA -> R.string.region_africa
    CityRegion.NORTH_AMERICA -> R.string.region_north_america
    CityRegion.SOUTH_AMERICA -> R.string.region_south_america
    CityRegion.OCEANIA -> R.string.region_oceania
    CityRegion.ANTARCTICA -> R.string.region_antarctica
}
private fun themeLabel(context: Context, mode: ThemeMode): String = context.getString(
    when (mode) {
        ThemeMode.AUTO -> R.string.theme_auto
        ThemeMode.LIGHT -> R.string.theme_light
        ThemeMode.DARK -> R.string.theme_dark
    },
)
