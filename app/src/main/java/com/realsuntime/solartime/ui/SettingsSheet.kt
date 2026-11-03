package com.realsuntime.solartime.ui

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
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.realsuntime.solartime.data.Place
import com.realsuntime.solartime.solar.TimeFormat

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun SettingsSheet(
    place: Place,
    locating: Boolean,
    remindersEnabled: Boolean,
    onDismiss: () -> Unit,
    onRequestGps: () -> Unit,
    onApplyManual: (Double, Double, String) -> Unit,
    onToggleReminders: (Boolean) -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
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
            Text("位置与提醒", style = MaterialTheme.typography.titleLarge)
            Spacer(Modifier.height(16.dp))

            Text(
                text = "当前位置",
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.primary,
            )
            Spacer(Modifier.height(6.dp))
            Text(
                text = "${place.label}　${TimeFormat.coordinates(place.latitude, place.longitude)}",
                style = MaterialTheme.typography.bodyMedium,
            )
            Spacer(Modifier.height(12.dp))
            FilledTonalButton(
                onClick = onRequestGps,
                enabled = !locating,
                modifier = Modifier.fillMaxWidth(),
            ) {
                if (locating) {
                    CircularProgressIndicator(modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
                    Spacer(Modifier.width(10.dp))
                    Text("定位中…")
                } else {
                    Text("使用 GPS 自动定位")
                }
            }

            Spacer(Modifier.height(22.dp))
            Text(
                text = "手动设置经纬度",
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.primary,
            )
            Spacer(Modifier.height(8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                OutlinedTextField(
                    value = latitudeText,
                    onValueChange = { latitudeText = it; error = null },
                    label = { Text("纬度") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                    modifier = Modifier.weight(1f),
                )
                OutlinedTextField(
                    value = longitudeText,
                    onValueChange = { longitudeText = it; error = null },
                    label = { Text("经度") },
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
                            error = "纬度需为 -90 至 90 之间的数值"
                        longitude == null || longitude !in Place.MIN_LONGITUDE..Place.MAX_LONGITUDE ->
                            error = "经度需为 -180 至 180 之间的数值"
                        else -> {
                            onApplyManual(latitude, longitude, "手动设置")
                            onDismiss()
                        }
                    }
                },
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text("应用坐标")
            }

            Spacer(Modifier.height(18.dp))
            Text(
                text = "常用城市",
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.primary,
            )
            Spacer(Modifier.height(4.dp))
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Place.PRESETS.forEach { preset ->
                    AssistChip(
                        onClick = {
                            onApplyManual(preset.latitude, preset.longitude, preset.label)
                            onDismiss()
                        },
                        label = { Text(preset.label) },
                    )
                }
            }

            Spacer(Modifier.height(18.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text("时辰交接提醒", style = MaterialTheme.typography.titleSmall)
                    Text(
                        text = "进入下一个时辰前 5 分钟发送通知",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Switch(checked = remindersEnabled, onCheckedChange = onToggleReminders)
            }

            Spacer(Modifier.height(20.dp))
            HorizontalDivider()
            Spacer(Modifier.height(14.dp))
            Text("关于计算", style = MaterialTheme.typography.labelLarge)
            Spacer(Modifier.height(6.dp))
            Text(
                text = "真太阳时按太阳的真实位置计时：先由当地经度相对东经 120° 的偏差修正时差" +
                    "（每 1° 相差 4 分钟），再叠加因地球轨道偏心率与黄赤交角产生的均时差。" +
                    "十二时辰按真太阳时划分，子时自 23:00 起，每两小时一个时辰。",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
