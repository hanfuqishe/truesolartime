package com.realsuntime.solartime.ui

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.widget.Toast
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.realsuntime.solartime.data.DiagReport

/**
 * 诊断页：给「别人的机器出问题时把诊断信息复制发我们」用。
 *
 * 布局硬约束（红米 Android 16 上出过「整页溢出屏幕」，根因见 [Box] 那句注释）：
 * 1. 外层 `Box(fillMaxSize + systemBarsPadding + padding(16.dp))` 把可用区域定死在窗口内；
 * 2. 内层 `Surface(fillMaxWidth + fillMaxHeight(0.9f))` **显式限高**，绝不让它按内容撑；
 * 3. 正文 `Column(weight(1f) + verticalScroll)` —— 高度只减不增，永远顶不掉兄弟控件；
 * 4. 标题栏 / 按钮 / 分隔线都是固定高度，任何 `Text` 都不带 `fillMaxHeight`。
 *
 * 字体：本页固定 `fontScale = 1f`（工具页不跟随系统大字号），正文等宽 11sp、系统字体。
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
        // 诊断页不跟随系统字号缩放：红米开 1.5 倍字号时，标题/提示/按钮若一起放大，
        // 会把正文挤没、甚至让窗口按内容撑出屏幕。工具页固定 1f，各机型排版也一致。
        val base = LocalDensity.current
        CompositionLocalProvider(LocalDensity provides Density(base.density, fontScale = 1f)) {
            // 根因修复点：Dialog 窗口的高度默认是 **wrap_content**（即使 usePlatformDefaultWidth=false
            // 只改了宽度）。之前 Surface 直接 fillMaxSize()，窗口就按内容高度测量 → 整页比屏幕还高、
            // 底部按钮被挤出可视区。现在外层 Box 吃满窗口约束、内层 Surface 显式 0.9 高度，
            // 正文 weight(1f) + verticalScroll，高度只可能缩不可能涨。
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .systemBarsPadding()
                    .padding(16.dp),
            ) {
                Surface(
                    modifier = Modifier
                        .fillMaxWidth()
                        .fillMaxHeight(0.9f),
                    color = MaterialTheme.colorScheme.surface,
                    shape = MaterialTheme.shapes.large,
                    tonalElevation = 1.dp,
                ) {
                    Column(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(horizontal = 16.dp, vertical = 12.dp),
                    ) {
                        // ① 标题栏（固定高度）
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(
                                text = "诊断信息",
                                style = MaterialTheme.typography.titleLarge,
                                modifier = Modifier.weight(1f),
                            )
                            TextButton(onClick = onDismiss) { Text("关闭") }
                        }
                        Spacer(Modifier.height(8.dp))
                        // ② 复制按钮（固定高度，≥48dp，整宽）——放在副标题之上，
                        // 副标题里的「点上方」才与实际位置一致。
                        Button(
                            onClick = {
                                // 纯文本入剪贴板（ClipData.newPlainText，label 用中文名），
                                // 微信粘贴出来仍是「键 = 值」的排版。API 29 与新版行为一致。
                                val ok = runCatching {
                                    val clip = context.getSystemService(Context.CLIPBOARD_SERVICE)
                                        as? ClipboardManager ?: return@runCatching false
                                    clip.setPrimaryClip(ClipData.newPlainText("真太阳时诊断信息", report))
                                    true
                                }.getOrDefault(false)
                                Toast.makeText(
                                    context,
                                    if (ok) {
                                        "已复制，可直接粘贴到微信发送"
                                    } else {
                                        "复制失败：请点上方「复制全部」重试，或把本页内容分几次复制发送。"
                                    },
                                    Toast.LENGTH_SHORT,
                                ).show()
                            },
                            modifier = Modifier
                                .fillMaxWidth()
                                .heightIn(min = 48.dp),
                        ) {
                            Text("复制全部")
                        }
                        Spacer(Modifier.height(8.dp))
                        // 副标题：只引导复制，不再提「截屏」（截屏只能看到当前一屏、
                        // 几十行内容会丢，容易让我们误判）。
                        Text(
                            text = "如需反馈，请点上方「复制全部」，把内容粘贴到微信发给我们。",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Spacer(Modifier.height(10.dp))
                        HorizontalDivider()
                        Spacer(Modifier.height(8.dp))
                        // 卡片尺寸校准收在这里：只给「布局明显不对」的用户用，
                        // 普通用户在主设置里看不到它。
                        var showCalibration by remember { mutableStateOf(false) }
                        TextButton(onClick = { showCalibration = !showCalibration }) {
                            Text(if (showCalibration) "收起卡片校准" else "卡片布局不对？校准卡片尺寸")
                        }
                        if (showCalibration) {
                            CardCalibrationSection(onDismissAll = onDismiss)
                            Spacer(Modifier.height(8.dp))
                        }
                        HorizontalDivider()
                        Spacer(Modifier.height(8.dp))
                        // ③ 正文：weight(1f) 只会缩，不会把上面的控件顶出去；滚动只在这一层。
                        Column(
                            modifier = Modifier
                                .weight(1f)
                                .fillMaxWidth()
                                .verticalScroll(rememberScrollState()),
                        ) {
                            SelectionContainer {
                                Text(
                                    text = report,
                                    style = MaterialTheme.typography.bodySmall.copy(
                                        fontFamily = FontFamily.Monospace,
                                        fontSize = 11.sp,
                                        lineHeight = 15.sp,
                                    ),
                                    modifier = Modifier.fillMaxWidth(),
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}
