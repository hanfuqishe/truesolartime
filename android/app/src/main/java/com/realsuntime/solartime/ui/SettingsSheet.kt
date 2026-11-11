package com.realsuntime.solartime.ui

import android.appwidget.AppWidgetManager
import android.os.Build
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
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
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
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
import com.realsuntime.solartime.widget.WidgetUpdater
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** 等待启动器新增小组件实例的最长时间（用户还要在系统弹窗里确认）。 */
private const val PIN_RESULT_TIMEOUT_MILLIS = 10_000L
private const val PIN_POLL_INTERVAL_MILLIS = 300L

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun SettingsSheet(
    place: Place,
    trackingGps: Boolean,
    remindersEnabled: Boolean,
    keyTimeChimeEnabled: Boolean,
    mapStyle: MapStyle,
    onDismiss: () -> Unit,
    onRequestGps: () -> Unit,
    onApplyManual: (Double, Double, String) -> Unit,
    onToggleReminders: (Boolean) -> Unit,
    onToggleKeyTimeChime: (Boolean) -> Unit,
    onSelectMapStyle: (MapStyle) -> Unit,
    onAddWidget: () -> Boolean,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val context = LocalContext.current
    var latitudeText by remember(place) { mutableStateOf("%.4f".format(place.latitude)) }
    var longitudeText by remember(place) { mutableStateOf("%.4f".format(place.longitude)) }
    var error by remember { mutableStateOf<String?>(null) }

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
                    Text(stringResource(R.string.action_restart_gps))
                } else {
                    Text(stringResource(R.string.action_use_gps))
                }
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

            Spacer(Modifier.height(14.dp))
            Text(
                text = stringResource(R.string.section_widget),
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.primary,
            )
            Spacer(Modifier.height(4.dp))
            Text(
                text = stringResource(R.string.widget_desc),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.height(8.dp))
            val canPin = remember {
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                    context.getSystemService(AppWidgetManager::class.java)
                        ?.isRequestPinAppWidgetSupported == true
            }
            var pinHint by remember { mutableStateOf<String?>(null) }
            val scope = rememberCoroutineScope()
            FilledTonalButton(
                onClick = {
                    pinHint = null
                    val before = WidgetUpdater.pinnedCount(context)
                    if (!onAddWidget()) {
                        pinHint = context.getString(R.string.widget_pin_unsupported)
                        return@FilledTonalButton
                    }
                    // 启动器只在真的加上去时才新增实例；用户还要在系统弹窗里点「添加」，
                    // 因此轮询一段时间，始终没有新实例才认为这次没加上（多半是桌面没空间）。
                    scope.launch {
                        val deadline = System.currentTimeMillis() + PIN_RESULT_TIMEOUT_MILLIS
                        while (System.currentTimeMillis() < deadline) {
                            delay(PIN_POLL_INTERVAL_MILLIS)
                            if (WidgetUpdater.pinnedCount(context) > before) return@launch
                        }
                        pinHint = context.getString(R.string.widget_pin_no_space)
                    }
                },
                enabled = canPin,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(if (canPin) stringResource(R.string.action_add_to_home) else stringResource(R.string.widget_pin_unsupported))
            }
            pinHint?.let { hint ->
                Spacer(Modifier.height(6.dp))
                Text(
                    text = hint,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error,
                )
            }
            Spacer(Modifier.height(6.dp))
            Text(
                text = stringResource(R.string.widget_pin_hint),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

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
