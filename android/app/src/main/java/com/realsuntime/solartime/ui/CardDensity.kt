package com.realsuntime.solartime.ui

import android.os.Build
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Density

/**
 * 卡片里锁死的字号缩放系数。
 *
 * 首页大卡片 / 太阳卡片 / 地图卡片是「版式即内容」的界面：数字必须正好撑满一栏、
 * 行高与竖分隔线的接缝都按固定 em 算出来、顶部标签行还要按文字宽度分四档退化。
 * 系统「字体大小」「粗体字」以及长辈关怀（超大字体）会把 `LocalDensity.fontScale`
 * 调大，上面这些假设全部失效（文字溢出、行高变化、档位判断偏早/偏晚），
 * 所以卡片内部一律按 [CARD_FONT_SCALE] 排版 —— 与日历、时钟类应用的做法一致。
 *
 * 设置页（`SettingsSheet`）**不锁**：那里是长文本、以可读性优先，跟随系统字号。
 */
internal const val CARD_FONT_SCALE = 1f

/**
 * 把 [content] 内的 `LocalDensity` 换成「[scale] 倍的几何缩放 + 字号不缩放」。
 *
 * 只改 `fontScale`，不动 `density`：dp 尺寸、圆角、间距、`Modifier.height(IntrinsicSize.Max)`
 * 的固有测量全部保持原样，被替换的只有 sp → px 的换算（`fontScale` 恒为 1）。
 *
 * [scale] 给宽屏并排时用：卡片内容先按手机那个逻辑宽度（334dp）排版，再整体等比放大，
 * 于是平板上的版式与手机完全一致，只是尺码不同。
 */
@Composable
internal fun LockedCardDensity(
    scale: Float = 1f,
    content: @Composable () -> Unit,
) {
    val base = LocalDensity.current
    val locked = remember(base, scale) {
        Density(
            density = base.density * scale,
            fontScale = CARD_FONT_SCALE,
        )
    }
    CompositionLocalProvider(LocalDensity provides locked, content = content)
}

/**
 * 可以提供给卡片文本的字重 —— **系统「粗体字」被抵消掉了**。
 *
 * 只把 `fontWeight` 写成固定值还不够：Android 12 起系统会在**渲染时**把
 * `Configuration.fontWeightAdjustment`（「设置 → 显示 → 字体与显示大小 → 加粗」，
 * 实测这台 ROM 上是 +300）加到每个字形上，加在写死的字重之上，于是同一段文本
 * 在加粗档位下更粗、略宽 1~3px。卡片的行宽/档位判断是按文字宽度算的，所以要一起抵掉：
 *
 *    实际字重 = 这里返回的字重 + 系统调整量 ≈ [nominal]
 *
 * [nominal] 传「不想被系统加粗影响时的目标字重」（卡片里是 Medium / Normal）。
 * 设置页用默认字重，不经过这里，于是它照旧跟着系统加粗走。
 */
@Composable
internal fun cardFontWeight(nominal: FontWeight): FontWeight {
    // 调整量只在系统设置变化时变，且那次变化会重建 Activity，所以这里直接读。
    val adjustment = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        LocalContext.current.resources.configuration.fontWeightAdjustment
    } else {
        0
    }
    if (adjustment == 0) return nominal
    return FontWeight((nominal.weight - adjustment).coerceIn(1, 1000))
}
