package com.realsuntime.solartime.ui

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * 太阳卡圆盘的一次投影结果，**像素坐标**（Compose `Canvas` 口径：原点在左上角、y 向下）。
 *
 * 几何模型（与鸿蒙／iOS 两版同一套）：
 * - **圆 = 一天 24 小时**，圆心 [centerX] / [centerY]、半径 [radius]；
 *   角度 `θ(t) = (t − 12h) / 24h × 360°`，圆上一点 `(x, y) = (C.x + R·sin θ, C.y − R·cos θ)`，
 *   即 **12:00 在正上方、00:00 在正下方、06:00 在正左、18:00 在正右**；
 * - **地平线是一条水平弦**，y 由日出时刻决定：`y_h = C.y − R·cos(θ(日出))`。
 *   昼长 12h → 弦过圆心；昼长 > 12h → 下移（白天那块更大）；< 12h → 上移；
 *   极昼 → 沉到圆下方（整圆都在白天）；极夜 → 升到圆上方（整圆都在夜晚）；
 * - [sunX] / [sunY] 是**当前时刻**按同一参数化算出的点，与地平线比大小即可判断
 *   「在地平线以上还是以下」（y 向下，所以 `sunY <= horizonY` 表示在地平线以上）；
 * - 圆弧与地平线的两个交点就是日出 / 日落位置（极昼极夜时无交点，整圆统一为白天 / 夜晚）；
 *   日出恰好 0:00（日落 24:00）时两个交点重合在圆**最下方**，地平线与圆**相切**（见 [horizonY]）。
 *
 * 时刻一律是**当地真太阳时**的小时数（0–24）：圆盘的角度就是真太阳时的小时数，
 * 换成标准时 / 北京时间来算会让太阳点与日出日落刻度对不上。
 *
 * 这个类刻意不依赖任何 Android 绘图 API，方便在 JVM 单测里直接断言数值。
 */
data class SunPath(
    val centerX: Float,
    val centerY: Float,
    val radius: Float,
    val horizonY: Float,
    val sunX: Float,
    val sunY: Float,
    val isPolarDay: Boolean,
    val isPolarNight: Boolean,
) {
    /** 圆顶（12:00 所在）的 y。 */
    val topY: Float get() = centerY - radius

    /** 圆底（00:00 所在）的 y。 */
    val bottomY: Float get() = centerY + radius

    /** 圆最左（06:00 所在）的 x。 */
    val leftX: Float get() = centerX - radius

    /** 圆最右（18:00 所在）的 x。 */
    val rightX: Float get() = centerX + radius

    /** 整圆都在地平线以上（极昼 / 昼长 ≥ 24h）：白天弧覆盖整圆。 */
    val isWholeCircleDay: Boolean get() = horizonY >= bottomY

    /** 整圆都在地平线以下（极夜）：夜晚弧覆盖整圆。 */
    val isWholeCircleNight: Boolean get() = horizonY <= topY

    /** 当前太阳点是否在地平线以上（y 向下，所以是「不大于地平线」）。 */
    val isSunUp: Boolean get() = sunY <= horizonY

    /**
     * 要不要画「上中天」标签。
     *
     * **极夜没有**：太阳整日不升，根本没有上中天可言，标一个 12:00 的时间只会误导；
     * 极昼有（太阳在 12:00 前后最高），普通日照样有。
     */
    val hasTransitLabel: Boolean get() = !isPolarNight
}

/**
 * 白天弧的绘制角度，口径与 Compose `DrawScope.drawArc` 一致：
 * **0° 指向 3 点方向（+x），顺时针为正**。
 *
 * 之所以不直接返回「θ」，是因为 `drawArc` 的角度以 +x 为 0°、而本文件的 θ 以 12:00（正上方）
 * 为 0°；两者差 90°（见 [SunPathGeometry.dayArcSpan]）。把换算放在纯函数里，UI 里就不用再推一遍。
 */
data class SunArcSpan(val startDegrees: Float, val sweepDegrees: Float)

/**
 * 圆盘外侧三个时间标签（以及极昼／极夜那行文案）的锚点，**像素坐标**。对齐方式由 UI 负责：
 * - 日出标签：[sunriseX] 是文字**右边缘**、[sunriseY] 是竖直中心 → 整个标签写在左交点的**左边**；
 * - 日落标签：[sunsetX] 是文字**左边缘**、[sunsetY] 是竖直中心 → 写在右交点的**右边**；
 * - 上中天标签：[noonX] 是水平中心、[noonY] 是文字**底边** → 写在圆顶正上方；
 * - 极昼／极夜文案：[polarX] / [polarY] 是文字中心 → 写在圆心（盘面正中）。
 *
 * 这么定位是因为短昼时两个交点可能只隔十几度（高纬度昼长 1 小时 ≈ 15° 圆心角）：
 * 日出标签在左交点左边、日落标签在右交点右边，中间还隔着约 `2R·sin(7.5°) ≈ 0.26R` 的弦宽，
 * 两个标签永远不会重叠，也不会压到圆弧上。
 */
data class SunLabelAnchors(
    val sunriseX: Float,
    val sunriseY: Float,
    val sunsetX: Float,
    val sunsetY: Float,
    val noonX: Float,
    val noonY: Float,
    val polarX: Float,
    val polarY: Float,
)

/**
 * 地平线要画的范围（x 起止，像素）。
 *
 * 长度是**固定**的：画布左右各内缩 [SunPathGeometry.horizonSpan] 的 `sideInset`（4dp），
 * 与圆心 / 半径 / 昼长都无关 —— 五种场景（普通日、短昼、极昼、极夜、0:00 相切）画出来一样长，
 * 这样它读起来才是「地平线」，而不是某一段圆弧的弦。
 */
data class HorizonSpan(val startX: Float, val endX: Float) {
    val length: Float get() = endX - startX
}

/** 圆盘几何的唯一入口：纯 Kotlin，不依赖 Android 绘图 API。 */
object SunPathGeometry {

    /**
     * 半径占画布短边的比例。
     *
     * 0.38（原 0.42）：圆上下各留 12% 的边，正好放得下圆顶那个 11sp 的「上中天」标签
     * （行高 16dp + 6dp 间距）；再大标签就会顶到画布上沿。太阳卡的画布是**满宽 + 定高**
     * （见 `SUN_DIAL_HEIGHT`），所以 `min(w, h)` 取到的是高度。
     */
    const val RADIUS_RATIO = 0.38f

    /**
     * 极昼 / 极夜时地平线离圆心的距离（半径的倍数）。
     * 必须 > 1：这样极昼时 `horizonY > centerY + radius`（整圆在白天），
     * 极夜时 `horizonY < centerY − radius`（整圆在夜晚），渲染时整圆不会被切成两段弧。
     */
    const val POLAR_HORIZON_RATIO = 1.25f

    private const val HOURS_PER_DAY = 24.0

    /**
     * 真太阳时 [hour]（0–24，允许越界：23:30 之后接着写 24.5 仍然连续）对应的角度，
     * 单位是**弧度**：`θ = (hour − 12) / 24 × 2π`。
     *
     * 12:00 → 0（正上方）、18:00 → +π/2（右侧）、00:00 → ±π（正下方）、06:00 → −π/2（左侧）。
     */
    fun angleOfDayHour(hour: Double): Double = (hour - 12.0) / HOURS_PER_DAY * 2.0 * PI

    /** 圆上 [hour] 处的 x：`C.x + R·sin θ`。 */
    fun hourX(centerX: Float, radius: Float, hour: Double): Float =
        centerX + radius * sin(angleOfDayHour(hour)).toFloat()

    /** 圆上 [hour] 处的 y：`C.y − R·cos θ`（y 向下，所以用减号）。 */
    fun hourY(centerY: Float, radius: Float, hour: Double): Float =
        centerY - radius * cos(angleOfDayHour(hour)).toFloat()

    /**
     * 地平线的 y：`C.y − R·cos(θ(日出))`。
     *
     * [sunriseHour] 为 null 时（极昼 / 极夜，太阳整天不升起或整天不落）没有交点，
     * 由 [isPolarDay] / [isPolarNight] 把地平线沉到圆下方 / 升到圆上方；
     * 两个标志都为 false 又拿不到日出（理论上不该出现）时退回圆心，圆盘至少还能读。
     *
     * **相切**：日出恰好 0:00（日落 24:00）时 θ = −180°，`cos θ = −1`，
     * 于是 `y_h = C.y + R` —— 地平线正好与圆**相切于最下方**，日出 / 日落两个交点都落在
     * `(C.x, C.y + R)` 这一点上。这是参数化的自然结果，不是特例：弦退化成一点
     * （[horizonHalfChord] == 0），整圆都在白天（[SunPath.isWholeCircleDay] == true）。
     */
    fun horizonY(
        centerY: Float,
        radius: Float,
        sunriseHour: Double?,
        isPolarDay: Boolean,
        isPolarNight: Boolean,
    ): Float = when {
        sunriseHour != null -> centerY - radius * cos(angleOfDayHour(sunriseHour)).toFloat()
        isPolarDay -> centerY + radius * POLAR_HORIZON_RATIO
        isPolarNight -> centerY - radius * POLAR_HORIZON_RATIO
        else -> centerY
    }

    /**
     * 算出圆盘的全部几何。
     *
     * [width] / [height] 是画布像素尺寸；圆心在画布中央、半径 = 0.42 × min(width, height)。
     * [sunriseHour] / [sunsetHour] / [trueSolarHour] 都是**当地真太阳时**（0–24 的小时数，
     * 可以用负数或 >24 表示跨午夜，参数化本身是周期的）。
     *
     * [sunsetHour] 不参与地平线的计算（日出已经唯一确定了这条弦），它在这里只作为
     * 「只有日落没有日出」时的兜底：真太阳时里日出与日落关于 12:00 对称（日出 = 24 − 日落），
     * 缺一个也能把弦算出来。留给调用方一个入口传全，省得两处各算一套口径。
     */
    fun compute(
        width: Float,
        height: Float,
        sunriseHour: Double?,
        sunsetHour: Double?,
        trueSolarHour: Double,
        isPolarDay: Boolean,
        isPolarNight: Boolean,
    ): SunPath {
        val radius = RADIUS_RATIO * min(width, height)
        val centerX = width / 2f
        val centerY = height / 2f
        // 没有日出时（极昼极夜）不能套「24 − 日落」的对称关系，交给 polar 标志决定。
        val horizonAnchor = sunriseHour ?: if (isPolarDay || isPolarNight) {
            null
        } else {
            sunsetHour?.let { HOURS_PER_DAY - it }
        }
        val horizon = horizonY(
            centerY = centerY,
            radius = radius,
            sunriseHour = horizonAnchor,
            isPolarDay = isPolarDay,
            isPolarNight = isPolarNight,
        )
        return SunPath(
            centerX = centerX,
            centerY = centerY,
            radius = radius,
            horizonY = horizon,
            sunX = hourX(centerX, radius, trueSolarHour),
            sunY = hourY(centerY, radius, trueSolarHour),
            isPolarDay = isPolarDay,
            isPolarNight = isPolarNight,
        )
    }

    /**
     * 白天弧的起止角度（`drawArc` 口径，见 [SunArcSpan]）；日出或日落缺一个（极昼 / 极夜）时返回
     * null，调用方按 [SunPath.isWholeCircleDay] / [SunPath.isWholeCircleNight] 画整圆。
     *
     * 真太阳时里日出与日落关于 12:00 对称，于是白天弧恰好从日出刻度起、顺时针扫到日落刻度；
     * 落日越过 24:00（极圈附近夏令时的那几天）时按下一圈补 2π，保证扫角是正数、不会反着画。
     */
    fun dayArcSpan(sunriseHour: Double?, sunsetHour: Double?): SunArcSpan? {
        if (sunriseHour == null || sunsetHour == null) return null
        val start = angleOfDayHour(sunriseHour)
        var sweep = angleOfDayHour(sunsetHour) - start
        while (sweep <= 0.0) sweep += 2.0 * PI
        while (sweep > 2.0 * PI) sweep -= 2.0 * PI
        // θ 以正上方为 0°、drawArc 以 +x 为 0°：θ = φ + π/2，所以 φ = θ − π/2。
        return SunArcSpan(
            startDegrees = Math.toDegrees(start - PI / 2.0).toFloat(),
            sweepDegrees = Math.toDegrees(sweep).toFloat(),
        )
    }

    /**
     * 算出三个时间标签 + 极昼极夜文案的锚点（见 [SunLabelAnchors]）。
     *
     * [sideGap] 是标签与圆（外沿）的水平间距；[noonGap] 是上中天标签底边与圆顶的竖直间距；
     * [minLabelDrop] 是**短昼保护**：日出／日落挤在圆顶附近时，两个标签至少下沉到圆顶下方这么远，
     * 免得和上中天标签挤成一团；下沉后再按「这一行高度上的圆边界」求 x，保证标签仍在圆外。
     * [sideLabelRise] 把日出／日落标签从交点往上抬一点，于是**延伸后的地平线可以从标签底下穿过去**
     * （不抬的话那条线会正好压过文字）。
     *
     * 极昼 / 极夜（[sunriseHour] / [sunsetHour] 为 null）时没有交点，日出／日落锚点退到圆的
     * 最左 / 最右（06:00 与 18:00 的位置）；UI 在这两种情况下不画这两个标签，
     * 只用 [SunLabelAnchors.polarX] / [SunLabelAnchors.polarY] 那一行文案。
     * 保留坐标是为了让函数在任何输入下都有确定结果，也方便单测。
     */
    fun labelAnchors(
        path: SunPath,
        sunriseHour: Double?,
        sunsetHour: Double?,
        sideGap: Float,
        noonGap: Float,
        minLabelDrop: Float,
        sideLabelRise: Float,
    ): SunLabelAnchors {
        val cx = path.centerX
        val cy = path.centerY
        val r = path.radius

        fun side(hour: Double?, sign: Float): Pair<Float, Float> {
            if (hour == null) return (cx + sign * (r + sideGap)) to cy
            val intersectionY = hourY(cy, r, hour)
            // 先给地平线让路（上抬），再做短昼保护（下沉），两个约束取更靠下的那个。
            val y = maxOf(intersectionY - sideLabelRise, cy - r + minLabelDrop)
            val dy = (y - cy).coerceIn(-r, r)
            val halfWidth = sqrt((r * r - dy * dy).coerceAtLeast(0f))
            return (cx + sign * (halfWidth + sideGap)) to y
        }

        val (sunriseX, sunriseY) = side(sunriseHour, -1f)
        val (sunsetX, sunsetY) = side(sunsetHour, 1f)
        return SunLabelAnchors(
            sunriseX = sunriseX,
            sunriseY = sunriseY,
            sunsetX = sunsetX,
            sunsetY = sunsetY,
            noonX = cx,
            noonY = cy - r - noonGap,
            polarX = cx,
            polarY = cy,
        )
    }

    /**
     * 地平线的绘制范围：**固定为画布左右各内缩 [sideInset]**，与圆心、半径、昼长全都无关。
     *
     * 长度恒等于 `canvasWidth − 2 × sideInset`（卡片里 sideInset = 4dp），所以普通日、短昼、
     * 极昼、极夜、0:00 相切五种场景画出来一样长 —— 它是一条贯穿整个画面的地平线，
     * 不是「圆的那条弦」。极昼极夜时地平线在圆外，同样画满这一条。
     */
    fun horizonSpan(canvasWidth: Float, sideInset: Float): HorizonSpan {
        val inset = sideInset.coerceIn(0f, canvasWidth / 2f)
        return HorizonSpan(startX = inset, endX = canvasWidth - inset)
    }

    /**
     * 地平线这条弦的半宽：`sqrt(R² − (y_h − C.y)²)`，单位像素。
     *
     * 弦两端正好落在日出 / 日落刻度上；极昼极夜时地平线在圆外（|dy| > R），返回 0 表示没有弦。
     * 日出 0:00（相切）时也返回 0：弦退化成一个点。
     * 单独拿出来是为了让 UI 只负责画线、不算几何（也便于单测断言「弦端 = 日出点」）。
     */
    fun horizonHalfChord(path: SunPath): Float {
        val dy = path.horizonY - path.centerY
        val r = path.radius
        return if (abs(dy) <= r) {
            sqrt((r * r - dy * dy).coerceAtLeast(0f))
        } else {
            0f
        }
    }
}
