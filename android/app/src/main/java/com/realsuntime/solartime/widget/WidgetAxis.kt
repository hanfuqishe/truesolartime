package com.realsuntime.solartime.widget

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RadialGradient
import android.graphics.Shader
import android.util.TypedValue
import com.realsuntime.solartime.data.TakeBand
import com.realsuntime.solartime.data.TakeTemperature

/**
 * 小组件里那条横线：真太阳时 0–24 时的时间轴。
 *
 * 轴线上按「关键时间」涂色带（冻或温用绿色、热或温用红色），并在当前真太阳时的位置打一个点。
 * 小组件只能放系统控件，位置又得随刷新变化，所以整条轴在 App 进程里画成位图再贴上去。
 */
object WidgetAxis {

    private const val MINUTES_PER_DAY = 24 * 60
    private const val GREEN = 0xFF66BB6A.toInt()
    private const val RED = 0xFFEF5350.toInt()
    private const val AXIS_COLOR = 0x40FFFFFF
    private const val DOT_CORE = 0xFFFFFFFF.toInt()
    private const val DOT_EDGE = 0x00FFFFFF

    /** 时间轴上的一个色带区间，单位是「真太阳时的当日分钟」，[endMinutes] 恒大于 [startMinutes]。 */
    data class SolarSpan(val startMinutes: Double, val endMinutes: Double)

    /**
     * 关键时间在 0–24 时轴上的区间。
     *
     * 页面上的时间本身就当真是真太阳时，不用做任何换算；只有跨过午夜的段会拆成两段
     * （轴是线性的 0–24，不做循环）。
     */
    internal fun spans(bands: List<TakeBand>): List<SolarSpan> {
        val spans = ArrayList<SolarSpan>(bands.size)
        bands.forEach { band ->
            val start = band.startMinute.toDouble()
            val end = start + band.lengthMinutes()
            if (end <= MINUTES_PER_DAY) {
                spans += SolarSpan(start, end)
            } else {
                spans += SolarSpan(start, MINUTES_PER_DAY.toDouble())
                spans += SolarSpan(0.0, end - MINUTES_PER_DAY)
            }
        }
        return spans
    }

    /**
     * 画出整条时间轴；宽度或高度无效时返回 null。
     *
     * @param solarSecondsOfDay 当前真太阳时的当日秒数，null 表示还没有定位、不画点也不画色带
     * @param bands 关键时间（直接当作真太阳时）；为空时只画轴线
     */
    fun render(
        context: Context,
        widthPx: Int,
        heightPx: Int,
        solarSecondsOfDay: Long?,
        bands: List<TakeBand>,
        temperature: TakeTemperature?,
    ): Bitmap? {
        if (widthPx <= 0 || heightPx <= 0) return null
        val bitmap = Bitmap.createBitmap(widthPx, heightPx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val centerY = heightPx / 2f
        val dotRadius = heightPx * 0.44f
        // 点画在两端时不外溢。
        val inset = dotRadius
        val usable = widthPx - inset * 2

        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            strokeCap = Paint.Cap.ROUND
            strokeWidth = dp(context, 1f)
            color = AXIS_COLOR
        }
        canvas.drawLine(inset, centerY, widthPx - inset, centerY, paint)

        if (solarSecondsOfDay != null) {
            val bandColor = when (temperature) {
                TakeTemperature.COLD_OR_MILD -> GREEN
                TakeTemperature.HOT_OR_MILD -> RED
                null -> 0
            }
            if (bandColor != 0 && bands.isNotEmpty()) {
                // 与轴线等宽，只换颜色：色带是提示，不该比时间本身更抢眼。
                paint.color = bandColor
                paint.strokeWidth = dp(context, 1f)
                spans(bands).forEach { span ->
                    val x1 = inset + usable * (span.startMinutes / MINUTES_PER_DAY).toFloat()
                    val x2 = inset + usable * (span.endMinutes / MINUTES_PER_DAY).toFloat()
                    canvas.drawLine(x1, centerY, x2, centerY, paint)
                }
            }

            val x = inset + usable * (solarSecondsOfDay / 86_400.0).toFloat()
            // 径向渐变让点的边缘化开，不像贴上去的硬圆。
            paint.style = Paint.Style.FILL
            paint.shader = RadialGradient(
                x,
                centerY,
                dotRadius,
                intArrayOf(DOT_CORE, DOT_CORE, DOT_EDGE),
                floatArrayOf(0f, 0.45f, 1f),
                Shader.TileMode.CLAMP,
            )
            canvas.drawCircle(x, centerY, dotRadius, paint)
            paint.shader = null
        }
        return bitmap
    }

    private fun dp(context: Context, value: Float): Float =
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, value, context.resources.displayMetrics)
}
