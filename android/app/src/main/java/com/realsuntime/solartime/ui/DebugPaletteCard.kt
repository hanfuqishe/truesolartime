package com.realsuntime.solartime.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.realsuntime.solartime.data.DebugPalette
import com.realsuntime.solartime.data.TakeTemperature
import java.util.Locale
import kotlin.math.roundToInt

/**
 * **临时调试卡片**：直接预览首页大卡片的配色，不需要等到特定时间或网页状态。
 *
 * - 主题：自动 / 白天 / 夜间
 * - 温度：自动 / 冻或温 / 热或温
 * - 关键时段：自动 / 强制「当前在时段内」
 * - 浓淡滑杆：调白天数字色，实时显示十六进制色值
 *
 * 确认配色后删掉本文件、`data/DebugPalette.kt` 与 `MainScreen` 里的调用即可。
 */
@Composable
fun DebugPaletteCard(modifier: Modifier = Modifier) {
    val isDay = DebugPalette.isDayOverride ?: true
    val temperature = DebugPalette.temperatureOverride

    Card(
        modifier = modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant,
        ),
        shape = RoundedCornerShape(16.dp),
    ) {
        Column(Modifier.padding(14.dp)) {
            Text(
                text = "配色预览（临时）",
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
            )
            Spacer(Modifier.height(10.dp))

            ChipRow(
                label = "主题",
                options = listOf(
                    "自动" to (DebugPalette.isDayOverride == null),
                    "白天" to (DebugPalette.isDayOverride == true),
                    "夜间" to (DebugPalette.isDayOverride == false),
                ),
                onSelect = { index ->
                    DebugPalette.isDayOverride = when (index) {
                        0 -> null
                        1 -> true
                        else -> false
                    }
                },
            )
            Spacer(Modifier.height(8.dp))

            ChipRow(
                label = "温度",
                options = listOf(
                    "自动" to (DebugPalette.temperatureOverride == null),
                    "冻或温" to (DebugPalette.temperatureOverride == TakeTemperature.COLD_OR_MILD),
                    "热或温" to (DebugPalette.temperatureOverride == TakeTemperature.HOT_OR_MILD),
                ),
                onSelect = { index ->
                    DebugPalette.temperatureOverride = when (index) {
                        0 -> null
                        1 -> TakeTemperature.COLD_OR_MILD
                        else -> TakeTemperature.HOT_OR_MILD
                    }
                },
            )
            Spacer(Modifier.height(8.dp))

            ChipRow(
                label = "时段",
                options = listOf(
                    "自动" to !DebugPalette.forceInKeyTime,
                    "强制在时段内" to DebugPalette.forceInKeyTime,
                ),
                onSelect = { index -> DebugPalette.forceInKeyTime = index == 1 },
            )
            Spacer(Modifier.height(12.dp))

            // 白天数字色的浓淡：0 = 最淡，1 = 与时间轴色段同色
            val inkColor = HeroPalette.ink(temperature, isDay = true, intensity = DebugPalette.inkIntensity)
                ?: HeroPalette.ink(TakeTemperature.COLD_OR_MILD, isDay = true, intensity = DebugPalette.inkIntensity)
                ?: Color.Gray
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = "白天数字浓度",
                    style = MaterialTheme.typography.labelLarge,
                )
                Spacer(Modifier.width(10.dp))
                Box(
                    Modifier
                        .size(16.dp)
                        .clip(RoundedCornerShape(4.dp))
                        .background(inkColor)
                        .border(1.dp, MaterialTheme.colorScheme.outline, RoundedCornerShape(4.dp)),
                )
                Spacer(Modifier.width(8.dp))
                Text(
                    text = hexOf(inkColor) + "  " + "${(DebugPalette.inkIntensity * 100).roundToInt()}%",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Slider(
                value = DebugPalette.inkIntensity,
                onValueChange = { DebugPalette.inkIntensity = it },
                valueRange = 0f..1f,
                steps = 0,
            )
            Text(
                text = "0% = 最淡（原 #BCF5CA / #FFC4C9 一类）；100% = 与时间轴色段同色",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            if (DebugPalette.anyActive()) {
                Spacer(Modifier.height(6.dp))
                Text(
                    text = "调试覆盖生效中，点击“自动”可恢复实时状态",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error,
                )
            }
        }
    }
}

@Composable
private fun ChipRow(
    label: String,
    options: List<Pair<String, Boolean>>,
    onSelect: (Int) -> Unit,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelLarge,
            modifier = Modifier.width(44.dp),
        )
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            options.forEachIndexed { index, (text, selected) ->
                Box(
                    modifier = Modifier
                        .clip(RoundedCornerShape(9.dp))
                        .background(
                            if (selected) MaterialTheme.colorScheme.primary
                            else MaterialTheme.colorScheme.surface,
                        )
                        .border(
                            width = 1.dp,
                            color = if (selected) MaterialTheme.colorScheme.primary
                            else MaterialTheme.colorScheme.outlineVariant,
                            shape = RoundedCornerShape(9.dp),
                        )
                        .clickable { onSelect(index) }
                        .padding(horizontal = 10.dp, vertical = 5.dp),
                ) {
                    Text(
                        text = text,
                        style = MaterialTheme.typography.labelMedium,
                        color = if (selected) MaterialTheme.colorScheme.onPrimary
                        else MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}

private fun hexOf(color: Color): String {
    val r = (color.red * 255).roundToInt()
    val g = (color.green * 255).roundToInt()
    val b = (color.blue * 255).roundToInt()
    return String.format(Locale.ROOT, "#%02X%02X%02X", r, g, b)
}
