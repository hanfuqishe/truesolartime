package com.realsuntime.solartime.widget

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import androidx.core.content.res.ResourcesCompat
import com.realsuntime.solartime.R
import kotlin.math.roundToInt

/**
 * 桌面卡片「高度校准尺」：卡片进入校准模式后只画一把竖直刻度尺，
 * 用户读出**最大完整刻度**就是卡片真实高度（Android 读不到 RemoteViews 的真实高度）。
 *
 * 一屏一尺：0 在顶端，每 10dp 短刻度、每 50dp 长刻度并标数字，`maxDp` 处一定有刻度。
 * 纯几何部分（[tickY]、[clampWidthPx]、[clampOverrideDp]）不依赖 Android，单测直接盯。
 */
internal object WidgetRuler {

    /** 与时间轴位图一致的宽度上限：RemoteViews 的 Binder 事务只有约 1 MB。 */
    const val MAX_WIDTH_PX = 1024

    /**
     * 位图尺寸上限（RGB_565，约 2 字节/px）：RemoteViews 走 Binder，事务上限约 1 MB。
     * 1220×1200 的 ARGB 位图会直接 TransactionTooLarge，卡片变成空白。
     */
    const val BITMAP_MAX_WIDTH_PX = 480
    const val BITMAP_MAX_HEIGHT_PX = 800

    const val MIN_OVERRIDE_DP = 100
    const val MAX_OVERRIDE_DP = 400

    const val MINOR_TICK_DP = 10
    const val LABEL_EVERY_DP = 50

    /** 刻度 y 坐标（px）：`dp / maxDp * heightPx`。 */
    fun tickY(dp: Int, maxDp: Int, heightPx: Int): Float =
        if (maxDp <= 0) 0f else dp.toFloat() / maxDp * heightPx

    /** 位图宽度夹取：至少 1px，至多 [MAX_WIDTH_PX]。 */
    fun clampWidthPx(widthPx: Int): Int = widthPx.coerceIn(1, MAX_WIDTH_PX)

    /**
     * 用户填的实测高度：`0` 表示未校准；`1..99` 夹到 100，`>400` 夹到 400。
     */
    fun clampOverrideDp(value: Int): Int = when {
        value <= 0 -> 0
        value < MIN_OVERRIDE_DP -> MIN_OVERRIDE_DP
        value > MAX_OVERRIDE_DP -> MAX_OVERRIDE_DP
        else -> value
    }

    /** 竖向预算：有实测值时用它减 4dp 余量，否则沿用自动估算。 */
    fun availableDp(overrideDp: Int, autoDp: Float): Float =
        if (overrideDp > 0) overrideDp - 4f else autoDp

    /** 需要画的刻度（含 0 和 maxDp）。 */
    fun tickDps(maxDp: Int = MAX_OVERRIDE_DP): List<Int> =
        (0..maxDp step MINOR_TICK_DP).toList()

    /** 横向刻度 x 坐标（px）：与竖直方向同一套 dp→px 映射。 */
    fun tickX(dp: Int, maxDp: Int, widthPx: Int): Float =
        if (maxDp <= 0) 0f else dp.toFloat() / maxDp * widthPx

    /**
     * 横向尺的像素比例：正常 1dp = density px；若 `400dp × density > 1024px`，
     * 则按 **1024/400 px per dp** 固定比例画（**不许再被 View 拉伸**，否则读数失真）。
     */
    fun horizontalPxPerDp(density: Float, maxDp: Int = MAX_OVERRIDE_DP): Float {
        val full = density.coerceAtLeast(0.1f)
        val width = maxDp * full
        return if (width > MAX_WIDTH_PX) MAX_WIDTH_PX.toFloat() / maxDp else full
    }

    /**
     * 画横向尺：0 在左端，每 10dp 短刻度、每 50dp 长刻度并标数字（数字在刻度线下方）。
     * 宽度固定 400dp（`fitXY` 时与位图 1:1，不会被拉伸）。
     */
    fun renderHorizontal(context: Context, heightPx: Int, maxDp: Int = MAX_OVERRIDE_DP): Bitmap {
        val density = context.resources.displayMetrics.density
        val pxPerDp = horizontalPxPerDp(density, maxDp)
        val width = (maxDp * pxPerDp).roundToInt().coerceIn(1, MAX_WIDTH_PX)
        val height = heightPx.coerceIn(1, 400)
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.RGB_565)
        val canvas = Canvas(bitmap)
        canvas.drawColor(Color.rgb(0xF2, 0xF2, 0xF2))
        val tickPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.rgb(0x33, 0x33, 0x33)
            strokeWidth = 2f
        }
        val labelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.rgb(0x22, 0x22, 0x22)
            textSize = 10f * density
            typeface = runCatching {
                ResourcesCompat.getFont(context, R.font.card_sans_medium)
            }.getOrNull() ?: Typeface.DEFAULT
        }
        val shortTick = 8f * density
        val longTick = 20f * density
        val baseline = height - 4f * density
        for (dp in 0..maxDp step MINOR_TICK_DP) {
            val x = tickX(dp, maxDp, width).coerceIn(1f, width - 1f)
            val isLabel = dp % LABEL_EVERY_DP == 0
            canvas.drawLine(x, 0f, x, if (isLabel) longTick else shortTick, tickPaint)
            if (isLabel) {
                canvas.drawText(dp.toString(), x + 3f * density, baseline, labelPaint)
            }
        }
        return bitmap
    }
    /**
     * 画尺：浅灰底、深色刻度与数字，任何主题下都能读。
     *
     * @param widthPx 位图宽度（会被夹到 [MAX_WIDTH_PX]）
     * @param maxDp 尺子的总高度（dp）
     */
    fun render(context: Context, widthPx: Int, maxDp: Int = MAX_OVERRIDE_DP): Bitmap {
        val width = clampWidthPx(widthPx)
        val density = context.resources.displayMetrics.density
        val height = (maxDp * density).roundToInt().coerceAtLeast(1)
        val scale = minOf(1f, BITMAP_MAX_WIDTH_PX.toFloat() / width, BITMAP_MAX_HEIGHT_PX.toFloat() / height)
        val bitmap = Bitmap.createBitmap(
            (width * scale).toInt().coerceAtLeast(1),
            (height * scale).toInt().coerceAtLeast(1),
            Bitmap.Config.RGB_565,
        )
        val canvas = Canvas(bitmap)
        canvas.scale(scale, scale)
        canvas.drawColor(Color.rgb(0xF2, 0xF2, 0xF2))

        val tickPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.rgb(0x33, 0x33, 0x33)
            strokeWidth = 2f
        }
        val labelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.rgb(0x22, 0x22, 0x22)
            textSize = 11f * density
            typeface = runCatching {
                ResourcesCompat.getFont(context, R.font.card_sans_medium)
            }.getOrNull() ?: Typeface.DEFAULT
        }
        val shortTick = 12f * density
        val longTick = 26f * density
        for (dp in tickDps(maxDp)) {
            val y = tickY(dp, maxDp, height).coerceIn(1f, height - 1f)
            val isLabel = dp % LABEL_EVERY_DP == 0
            canvas.drawLine(0f, y, if (isLabel) longTick else shortTick, y, tickPaint)
            if (isLabel) {
                canvas.drawText(dp.toString(), longTick + 6f * density, y + 4f * density, labelPaint)
            }
        }
        return bitmap
    }
}
