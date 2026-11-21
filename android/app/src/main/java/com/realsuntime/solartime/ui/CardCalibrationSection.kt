package com.realsuntime.solartime.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.realsuntime.solartime.R
import com.realsuntime.solartime.widget.WidgetUpdater

/**
 * 「桌面卡片校准」：把卡片变成刻度尺，用户读出真实宽高再填回来。
 *
 * **只在诊断页里露出**：自动估算已经修好（预算以真实高度为准、axis 可见性恢复），
 * 普通用户不需要它；但遇到读不到尺寸的机型时，它仍是唯一能拿到真值的手段
 * （用户自己读数即可，不必装 adb、不必看日志）。
 *
 * @param onDismissAll 保存成功后关闭整层（诊断对话框），随后由 [goHome] 回桌面看卡片。
 */
@Composable
fun CardCalibrationSection(onDismissAll: () -> Unit) {
    val context = LocalContext.current

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
    // 只保留一个「刻度」入口：点一下卡片变刻度尺；点「保存并刷新」或「恢复自动」即退出。
    FilterChip(
        selected = target != 0,
        onClick = {
            // 再点一次可以退出刻度模式（保存/恢复自动也会退出）。
            val next = if (target != 0) 0 else 1
            target = next
            WidgetUpdater.setCalibrationTarget(context, next)
            WidgetUpdater.refreshAll(context, forceChronometer = true)
        },
        label = { Text(stringResource(R.string.calibration_ruler)) },
    )
    var heightText by remember {
        mutableStateOf(WidgetUpdater.heightOverrideDp(context).takeIf { it > 0 }?.toString().orEmpty())
    }
    var widthText by remember {
        mutableStateOf(WidgetUpdater.widthOverrideDp(context).takeIf { it > 0 }?.toString().orEmpty())
    }
    // 回填控件只在「刻度」打开时出现；保存后随刻度模式一起收起（用户要求）。
    if (target != 0) {
        Spacer(Modifier.height(8.dp))
        // 说明「现在该做什么」：读数是靠用户去桌面看尺子得到的。
        Text(
            text = stringResource(R.string.widget_calib_go_desktop),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.primary,
        )
        Spacer(Modifier.height(8.dp))
        // 宽、高并排一行（先宽后高），省得上下滚动。
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
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
                modifier = Modifier.weight(1f),
            )
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
                modifier = Modifier.weight(1f),
            )
        }
        Spacer(Modifier.height(6.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(
                onClick = {
                    WidgetUpdater.setHeightOverrideDp(context, heightText.toIntOrNull() ?: 0)
                    WidgetUpdater.setWidthOverrideDp(context, widthText.toIntOrNull() ?: 0)
                    // 保存后自动退出校准模式，卡片立刻恢复正常排版。
                    WidgetUpdater.setCalibrationTarget(context, 0)
                    target = 0
                    WidgetUpdater.refreshAll(context, forceChronometer = true)
                    // 保存即完成一次校准动作：收起面板并直接回桌面，省得用户再手动退出。
                    onDismissAll()
                    goHome(context)
                },
            ) { Text(stringResource(R.string.widget_apply_calibration)) }
            TextButton(
                onClick = {
                    WidgetUpdater.resetCalibration(context)
                    target = 0
                    heightText = ""
                    widthText = ""
                    WidgetUpdater.refreshAll(context, forceChronometer = true)
                },
            ) { Text(stringResource(R.string.widget_reset_auto)) }
        }
    }
    // 状态行**常驻**：即使收起输入框，也要能看到当前生效的是自动还是校准值。
    val savedWidth = widthText.toIntOrNull() ?: 0
    val savedHeight = heightText.toIntOrNull() ?: 0
    val statusText = when {
        savedWidth > 0 && savedHeight > 0 ->
            stringResource(R.string.widget_calib_state_both, savedWidth, savedHeight)
        savedWidth > 0 -> stringResource(R.string.widget_calib_state_width, savedWidth)
        savedHeight > 0 -> stringResource(R.string.widget_calib_state_height, savedHeight)
        else -> stringResource(R.string.widget_calib_state_auto)
    }
    Text(
        text = statusText,
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
}

/** 保存校准后直接回桌面：用户下一步就是看卡片。HOME 意图比 moveTaskToBack 稳。 */
private fun goHome(context: android.content.Context) {
    runCatching {
        context.startActivity(
            android.content.Intent(android.content.Intent.ACTION_MAIN).apply {
                addCategory(android.content.Intent.CATEGORY_HOME)
                flags = android.content.Intent.FLAG_ACTIVITY_NEW_TASK
            },
        )
    }
}
