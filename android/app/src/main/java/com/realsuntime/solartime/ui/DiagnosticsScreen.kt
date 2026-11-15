package com.realsuntime.solartime.ui

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.widget.Toast
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.realsuntime.solartime.R
import com.realsuntime.solartime.data.DiagReport

/**
 * 诊断页：给「别人的机器出问题时截图发我们」用。
 *
 * 刻意**不用**卡片那套锁定字体/字号（[CardDensity]），就是系统字体 + 等宽，保证任何机型
 * 截屏都能看清；内容全部可选中复制，底部一个「复制全部」。
 */
@Composable
fun DiagnosticsDialog(onDismiss: () -> Unit) {
    val context = LocalContext.current
    // 打开时算一次即可：页面是只读快照，避免滚动时反复读系统设置。
    val report = remember { runCatching { DiagReport.build(context) }.getOrElse { "生成诊断信息失败: $it" } }
    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false),
    ) {
        Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.surface) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .systemBarsPadding()
                    .padding(horizontal = 16.dp, vertical = 12.dp),
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        text = "诊断信息",
                        style = MaterialTheme.typography.titleLarge,
                        modifier = Modifier.weight(1f),
                    )
                    TextButton(onClick = onDismiss) { Text("关闭") }
                }
                Text(
                    text = "如需反馈，可点下方「复制全部」后粘贴到微信发给我们；也可以直接截屏。",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(Modifier.height(8.dp))
                // 滚动必须挂在「有确定高度」的那一层（weight 的 Column）上：
                // 挂在内部 Text 上时，Text 会按内容高度测量，把下面的「复制全部」按钮顶出屏幕。
                Column(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxWidth()
                        .verticalScroll(rememberScrollState()),
                ) {
                    SelectionContainer {
                        Text(
                            text = report,
                            // 系统等宽字体（不是卡片锁定的那份 TTF），11sp 起、不随卡片密度变化
                            style = MaterialTheme.typography.bodySmall.copy(
                                fontFamily = FontFamily.Monospace,
                                fontSize = 11.sp,
                                lineHeight = 15.sp,
                            ),
                            modifier = Modifier.fillMaxWidth(),
                        )
                    }
                }
                Spacer(Modifier.height(10.dp))
                Button(
                    onClick = {
                        // 纯文本入剪贴板（ClipData.newPlainText，label 用中文名），
                        // 微信粘贴出来仍是「键 = 值」的排版。API 29 与新版行为一致，无需分支。
                        val ok = runCatching {
                            val clip = context.getSystemService(Context.CLIPBOARD_SERVICE)
                                as? ClipboardManager ?: return@runCatching false
                            clip.setPrimaryClip(ClipData.newPlainText("真太阳时诊断信息", report))
                            true
                        }.getOrDefault(false)
                        Toast.makeText(
                            context,
                            if (ok) "已复制，可直接粘贴到微信发送" else "复制失败，请直接截屏",
                            Toast.LENGTH_SHORT,
                        ).show()
                    },
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text("复制全部")
                }
            }
        }
    }
}
