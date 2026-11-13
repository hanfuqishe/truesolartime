package com.realsuntime.solartime.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
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
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.realsuntime.solartime.R
import com.realsuntime.solartime.data.Place
import com.realsuntime.solartime.map.MapStyle
import com.realsuntime.solartime.solar.TimeFormat
import com.realsuntime.solartime.widget.ChimeAlarm
import com.realsuntime.solartime.widget.WidgetUpdater

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun SettingsSheet(
    place: Place,
    trackingGps: Boolean,
    remindersEnabled: Boolean,
    keyTimeChimeEnabled: Boolean,
    keepScreenOn: Boolean,
    mapStyle: MapStyle,
    onDismiss: () -> Unit,
    onRequestGps: () -> Unit,
    onApplyManual: (Double, Double, String) -> Unit,
    onToggleReminders: (Boolean) -> Unit,
    onToggleKeyTimeChime: (Boolean) -> Unit,
    onToggleKeepScreenOn: (Boolean) -> Unit,
    onSelectMapStyle: (MapStyle) -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val context = LocalContext.current
    var latitudeText by remember(place) { mutableStateOf("%.4f".format(place.latitude)) }
    var longitudeText by remember(place) { mutableStateOf("%.4f".format(place.longitude)) }
    var error by remember { mutableStateOf<String?>(null) }
    // 桌面上已有的小组件数量：>0 时分钟刷新同样依赖精确闹钟权限，要一并提示。
    var pinnedWidgets by remember { mutableStateOf(WidgetUpdater.pinnedCount(context)) }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
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
                text = "${TimeText.placeLabel(context, place)}　${TimeText.coordinates(context, place.latitude, place.longitude)}",
                style = MaterialTheme.typography.bodyMedium,
            )
            Spacer(Modifier.height(12.dp))
            FilledTonalButton(
                onClick = onRequestGps,
                modifier = Modifier.fillMaxWidth(),
            ) {
                if (trackingGps) {
                    CircularProgressIndicator(modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
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
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Place.PRESETS.forEach { preset ->
                    AssistChip(
                        onClick = {
                            onApplyManual(preset.latitude, preset.longitude, TimeText.placeLabel(context, preset))
                            onDismiss()
                        },
                        label = { Text(TimeText.placeLabel(context, preset)) },
                    )
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
                MapStyle.entries.forEach { style ->
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
            Text(
                text = stringResource(R.string.weather_attribution),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
