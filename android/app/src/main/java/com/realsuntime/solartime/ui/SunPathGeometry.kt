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
 *   角度 `θ(t) = (t − 12h) / 24h × 360°`，12:00 恒在正上方、00:00 恒在正下方；
 * - **x 的方向分半球**（[southernHemisphere]）：
 *   北半球 `x = C.x + R·sin θ`（06:00 在左、18:00 在右，太阳从左往右）；
 *   南半球观察者面朝北，东在右、西在左，太阳从右往左走，所以 `x = C.x − R·sin θ`
 *   （06:00 在右、18:00 在左）。y 两边完全一样，`sunX` / `hourX` 都按这条来；
 * - **地平线是一条水平弦**，y 由日出时刻决定：`y_h = C.y − R·cos(θ(日出))`。
 *   昼长 12h → 弦过圆心；昼长 > 12h → 下移（白天那块更大）；< 12h → 上移；
 *   极昼 → 沉到圆下方（整圆都在白天）；极夜 → 升到圆上方（整圆都在夜晚）；
 *   它与半球无关（同一昼长南北半球的地平线高度相同）；
 * - [sunX] / [sunY] 是**当前时刻**按同一参数化算出的点，与地平线比大小即可判断
 *   「在地平线以上还是以下」（y 向下，所以 `sunY <= horizonY` 表示在地平线以上）；
 * - 圆弧与地平线的两个交点就是日出 / 日落位置（极昼极夜时无交点，整圆统一为白天 / 夜晚）；
 *   日出恰好 0:00（日落 24:00）时两个交点重合在圆**最下方**，地平线与圆**相切**（见 [horizonY]）。
 *
 * 时刻一律是**当地真太阳时**的小时数（0–24）：圆盘的角度就是真太阳时的小时数，
 * 换成标准时 / 北京时间来算会让太阳点与日出日落交点对不上。
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
    /** 南半球：x 取 `C.x − R·sin θ`（镜像），见类注释。默认北半球，保持老调用方不变。 */
    val southernHemisphere: Boolean = false,
    /**
     * **定位不可用（未知态）**：昼夜各半的对半圆，地平线从圆心穿过。
     *
     * 这种盘面没有观测点，太阳点 / 运动箭头 / 日出日落时间标签全都没有意义，
     * 由 [showsSunDot] / [showsMotionArrow] / [showsTimeLabels] 统一关掉
     * （UI 只画两段弧 + 中间那条地平线）。
     */
    val unknown: Boolean = false,
) {
    /** 圆顶（12:00 所在）的 y。 */
    val topY: Float get() = centerY - radius

    /** 圆底（00:00 所在）的 y。 */
    val bottomY: Float get() = centerY + radius

    /** 圆最左（06:00 所在）的 x。 */
    val leftX: Float get() = centerX - radius

    /** 圆最右（18:00 所在）的 x。 */
    val rightX: Float get() = centerX + radius

    /** 未知态没有位置，也就没有「此刻太阳在哪」：不画太阳点。 */
    val showsSunDot: Boolean get() = !unknown

    /** 未知态不画运动方向箭头（没有轨迹可讲）。 */
    val showsMotionArrow: Boolean get() = !unknown

    /** 未知态不画日出 / 上中天 / 日落时间标签（也就没有「白昼/极昼/极夜」那行文案）。 */
    val showsTimeLabels: Boolean get() = !unknown

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
     * 极昼有（太阳在 12:00 前后最高），普通日照样有。**未知态也没有**：没有观测点就没有上中天。
     */
    val hasTransitLabel: Boolean get() = !isPolarNight && !unknown
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
 * - 日出标签：[sunriseX] 是**挨着圆的那条边**（北半球=右边缘、南半球=左边缘）、
 *   [sunriseY] 是竖直中心 → 整个标签写在日出交点的外侧；
 * - 日落标签：[sunsetX] 同理是挨着圆的那条边（北半球=左边缘、南半球=右边缘）；
 * - 上中天标签：[noonX] 是水平中心、[noonY] 是文字**底边** → 写在圆顶正上方；
 * - 极昼／极夜文案：[polarX] / [polarY] 是文字中心 → 写在圆心（盘面正中）。
 *
 * 为什么是「挨着圆的那条边」而不是固定写「右边缘」：南半球日出在右、日落在左（见
 * [SunPath.southernHemisphere]），标签要跟着换到交点的另一侧，对齐方向也随之翻转。
 * UI 用「锚点在圆心的哪一侧」来判断该左对齐还是右对齐。
 *
 * 这么定位是因为短昼时两个交点可能只隔十几度（高纬度昼长 1 小时 ≈ 15° 圆心角）：两个标签
 * 一个在左交点外侧、一个在右交点外侧，中间还隔着约 `2R·sin(7.5°) ≈ 0.26R` 的弦宽，
 * 永远不会重叠，也不会压到圆弧上。
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

/**
 * 圆盘**内侧**那段「太阳运动方向」的短弧 + 箭头（像素坐标）。
 *
 * - [startX] / [startY]：弧的起点（当前真太阳时角度 **−** 半跨角，时间较早的一端）；
 * - [endX] / [endY]：弧的终点（角度 **+** 半跨角，运动方向的下游）；
 * - [tipX] / [tipY]：箭头尖，等于终点。
 *
 * 北半球从 start 到 end 在屏幕上是**顺时针**（时间增大的方向）；南半球整个 x 镜像，
 * 所以是**逆时针**。方向完全由 [SunPath.southernHemisphere] 决定，UI 不再另算一套。
 */
data class MotionArrow(
    val startX: Float,
    val startY: Float,
    val endX: Float,
    val endY: Float,
    val tipX: Float,
    val tipY: Float,
)

/**
 * 估算的标签矩形（像素）：只用于「三个时间标签会不会叠在一起」的检测，不参与绘制。
 */
private data class LabelRect(val left: Float, val top: Float, val right: Float, val bottom: Float) {
    fun overlaps(other: LabelRect): Boolean =
        left < other.right && other.left < right && top < other.bottom && other.top < bottom
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

    /** 运动方向箭头所在圆的半径（相对轨迹圆 R）：画在圆内侧，离太阳点（在 R 上）留出足够空隙。 */
    const val MOTION_ARROW_RADIUS_RATIO = 0.72f

    /** 运动方向箭头短弧的跨角（度），以当前太阳点角度为中心左右各一半。 */
    const val MOTION_ARROW_SPAN_DEG = 30f

    private const val HOURS_PER_DAY = 24.0

    /** 南半球日出/日落两个标签之间的最小水平间距（= 较宽者 + 8dp 的 8dp）。 */
    private const val SOUTHERN_LABEL_GAP = 8f

    /**
     * 真太阳时 [hour]（0–24，允许越界：23:30 之后接着写 24.5 仍然连续）对应的角度，
     * 单位是**弧度**：`θ = (hour − 12) / 24 × 2π`。
     *
     * 12:00 → 0（正上方）、18:00 → +π/2（右侧）、00:00 → ±π（正下方）、06:00 → −π/2（左侧）。
     */
    fun angleOfDayHour(hour: Double): Double = (hour - 12.0) / HOURS_PER_DAY * 2.0 * PI

    /**
     * 圆上 [hour] 处的 x。
     *
     * 北半球（默认）：`C.x + R·sin θ` —— 06:00 在左、18:00 在右，太阳从左往右；
     * 南半球（[southernHemisphere]）：`C.x − R·sin θ` —— 观察者面朝北，东在右、西在左，
     * 06:00 在**右**、18:00 在**左**，太阳从右往左（逆时针）。y 两边一致。
     */
    fun hourX(
        centerX: Float,
        radius: Float,
        hour: Double,
        southernHemisphere: Boolean = false,
    ): Float {
        val offset = radius * sin(angleOfDayHour(hour)).toFloat()
        return if (southernHemisphere) centerX - offset else centerX + offset
    }

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
     *
     * [southernHemisphere] 为 true 时 x 取镜像（`C.x − R·sin θ`）：太阳点、日出日落位置
     * 全部换边，但**地平线高度不变**（它只由昼长决定），12:00 / 00:00 仍在天顶 / 天底。
     */
    fun compute(
        width: Float,
        height: Float,
        sunriseHour: Double?,
        sunsetHour: Double?,
        trueSolarHour: Double,
        isPolarDay: Boolean,
        isPolarNight: Boolean,
        southernHemisphere: Boolean = false,
        unknown: Boolean = false,
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
            sunX = hourX(centerX, radius, trueSolarHour, southernHemisphere),
            sunY = hourY(centerY, radius, trueSolarHour),
            isPolarDay = isPolarDay,
            isPolarNight = isPolarNight,
            southernHemisphere = southernHemisphere,
            unknown = unknown,
        )
    }

    /** 「昼夜各半」的日出 / 日落口径：06:00 与 18:00，正好让地平线穿过圆心。 */
    const val UNKNOWN_SUNRISE_HOUR = 6.0
    const val UNKNOWN_SUNSET_HOUR = 18.0

    /**
     * **未知态**（定位不可用）的盘面：一个昼夜各半的圆。
     *
     * 借 [compute] 的正常日参数化（日出 06:00、日落 18:00）得到：
     * 白天弧 180°（上半圈，实线）、夜间弧 180°（下半圈，虚线）、地平线 y = 圆心。
     * 与普通日不同的是 [SunPath.unknown] = true：太阳点 / 运动箭头 / 时间标签全部关掉
     * —— 没有观测点，也就没有「此刻太阳在哪」。
     */
    fun unknown(width: Float, height: Float): SunPath = compute(
        width = width,
        height = height,
        sunriseHour = UNKNOWN_SUNRISE_HOUR,
        sunsetHour = UNKNOWN_SUNSET_HOUR,
        // 没有真实时刻可标：参数化取 12:00（圆顶），反正太阳点不画。
        trueSolarHour = 12.0,
        isPolarDay = false,
        isPolarNight = false,
        southernHemisphere = false,
        unknown = true,
    )

    /**
     * 圆盘内侧那段「太阳运动方向」短弧的起止点（见 [MotionArrow]）。
     *
     * 弧以 [currentTrueSolarHour] 对应的圆心角为中心、左右各 [spanDeg] / 2，画在半径
     * `radiusRatio × R` 的同心圆上（默认 0.72R，离太阳点所在的 R 还有 0.28R ≈ 20dp）。
     * 半球决定 x 是否镜像：北半球 start → end 顺时针，南半球逆时针。
     *
     * 端点用与太阳点**同一套**参数化（[hourX] / [hourY] 的公式），所以两端的半径恒等于
     * `radiusRatio × R`、两端夹角恒等于 [spanDeg]，不受半球影响。
     */
    fun motionArrow(
        path: SunPath,
        currentTrueSolarHour: Double,
        radiusRatio: Float = MOTION_ARROW_RADIUS_RATIO,
        spanDeg: Float = MOTION_ARROW_SPAN_DEG,
    ): MotionArrow {
        val arrowRadius = path.radius * radiusRatio
        val halfSpan = Math.toRadians(spanDeg / 2.0)
        val centerAngle = angleOfDayHour(currentTrueSolarHour)

        fun point(theta: Double): Pair<Float, Float> {
            val offset = arrowRadius * sin(theta).toFloat()
            val x = if (path.southernHemisphere) path.centerX - offset else path.centerX + offset
            return x to (path.centerY - arrowRadius * cos(theta).toFloat())
        }

        val (startX, startY) = point(centerAngle - halfSpan)
        val (endX, endY) = point(centerAngle + halfSpan)
        // 箭头尖就是弧的终点（运动方向的下游）。
        return MotionArrow(
            startX = startX,
            startY = startY,
            endX = endX,
            endY = endY,
            tipX = endX,
            tipY = endY,
        )
    }

    /**
     * 白天弧的起止角度（`drawArc` 口径，见 [SunArcSpan]）；日出或日落缺一个（极昼 / 极夜）时返回
     * null，调用方按 [SunPath.isWholeCircleDay] / [SunPath.isWholeCircleNight] 画整圆。
     *
     * 真太阳时里日出与日落关于 12:00 对称，于是白天弧恰好从日出交点起、顺时针扫到日落交点；
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
     * 白天弧两端各沿圆外扩的角度（度）：约 **1dp**（半径 ≈74dp 时 0.8° ≈ 1.03dp）。
     *
     * 日出 / 日落交点上的小圆点已经删掉，只剩弧端一个圆头线帽（比端点多半条线宽）。
     * 不外扩时白弧会「停在地平线前一点」，看起来悬空；两端各外扩这么多之后，
     * 白弧会略微穿过地平线，接缝自然。**太阳高度角算出的交点本身不变**，
     * 标签（[labelAnchors]）仍按真实交点摆位。
     */
    const val ARC_ENDPOINT_OVERDRAW_DEG = 0.8f

    /**
     * 把白天弧的两端各外扩 [ARC_ENDPOINT_OVERDRAW_DEG]。
     *
     * 扫角封顶 360°：昼长接近 24h（太阳刚要落就升）时，外扩会把白天弧接到整圈，
     * 夜里那一小段随之消失，避免算出一个负的夜间扫角。
     */
    fun withEndpointOverdraw(span: SunArcSpan): SunArcSpan = SunArcSpan(
        startDegrees = span.startDegrees - ARC_ENDPOINT_OVERDRAW_DEG,
        sweepDegrees = (span.sweepDegrees + 2f * ARC_ENDPOINT_OVERDRAW_DEG).coerceAtMost(360f),
    )

    /**
     * 算出三个时间标签 + 极昼极夜文案的锚点（见 [SunLabelAnchors]）。
     *
     * [sideGap] 是标签与圆（外沿）的水平间距；[noonGap] 是上中天标签底边与圆顶的竖直间距；
     * [minLabelDrop] 是**短昼保护**：日出／日落挤在圆顶附近时，两个标签至少下沉到圆顶下方这么远，
     * 免得和上中天标签挤成一团；下沉后再按「这一行高度上的圆边界」求 x，保证标签仍在圆外。
     * [sideLabelRise] 把日出／日落标签从交点往上抬一点，于是**延伸后的地平线可以从标签底下穿过去**
     * （不抬的话那条线会正好压过文字）。
     *
     * **重叠退让**：三个标签的实际宽高由调用方传进来（[sunriseWidth] / [sunsetWidth] / [noonWidth] /
     * [labelHeight]）。接近极昼时日出、日落两个交点都贴近圆顶/圆底，算出来的锚点会挤到圆心正上方（或正下方），
     * 和上中天标签叠在一起。这时启用**边缘退让**：日出/日落贴画布左右内边距（[edgeInset]，南北半球按镜像摆）、
     * 竖直位置取「地平线 − [sideLabelRise]」；上中天仍在圆顶上方，若仍相交再上移到画布顶部内边距。
     *
     * 宽度都传 0 时**不做检测**，输出与旧版逐像素一致（普通日不受影响，老调用方也不用改）。
     *
     * 极昼 / 极夜（[sunriseHour] / [sunsetHour] 为 null）时没有交点，日出／日落锚点退到圆的
     * 最左 / 最右（06:00 与 18:00 的位置，南北半球按 [SunPath.southernHemisphere] 镜像）；
     * UI 在这两种情况下不画这两个标签，只用 [SunLabelAnchors.polarX] / [SunLabelAnchors.polarY]
     * 那一行文案。保留坐标是为了让函数在任何输入下都有确定结果，也方便单测。
     */
    fun labelAnchors(
        path: SunPath,
        sunriseHour: Double?,
        sunsetHour: Double?,
        sideGap: Float,
        noonGap: Float,
        minLabelDrop: Float,
        sideLabelRise: Float,
        sunriseWidth: Float = 0f,
        sunsetWidth: Float = 0f,
        noonWidth: Float = 0f,
        labelHeight: Float = 0f,
        edgeInset: Float = 0f,
        canvasWidth: Float = path.centerX * 2f,
        labelBelowOffset: Float = sideLabelRise,
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

        // 北半球：日出在左（-1）、日落在右（+1）；南半球镜像（日出在右、日落在左）。
        val sunriseSign = if (path.southernHemisphere) 1f else -1f
        var (sunriseX, sunriseY) = side(sunriseHour, sunriseSign)
        var (sunsetX, sunsetY) = side(sunsetHour, -sunriseSign)
        var noonY = cy - r - noonGap

        // 只有拿得到「标签尺寸」且真有日出日落时才做重叠检测；宽度为 0 = 老行为（零变化）。
        val hasSizes = labelHeight > 0f && (sunriseWidth > 0f || sunsetWidth > 0f || noonWidth > 0f)
        if (path.southernHemisphere && sunriseHour != null && sunsetHour != null) {
            // 南半球：太阳从右往左走，日出/日落交点贴近圆底 —— 标签放到**地平线下方**（不压轨迹线），
            // 并且 **x 直接取交点 x**（左标签右对齐、右标签左对齐，各自向圆外延伸），
            // 只有两个矩形会相交 / 间距不足时才以交点为基准等量外推；推不开才退到画布内边距。
            val y = path.horizonY + labelBelowOffset
            sunriseY = y
            sunsetY = y
            val sunrisePointX = hourX(cx, r, sunriseHour, southernHemisphere = true)
            val sunsetPointX = hourX(cx, r, sunsetHour, southernHemisphere = true)
            sunriseX = sunrisePointX
            sunsetX = sunsetPointX
            if (hasSizes && sunriseWidth > 0f && sunsetWidth > 0f) {
                val required = maxOf(sunriseWidth, sunsetWidth) + SOUTHERN_LABEL_GAP
                val gap = sunrisePointX - sunsetPointX
                if (gap < 1f) {
                    // 极端近极昼：两个交点几乎重合（日出=日落同点）→ 直接退到画布左右边缘，
                    // 间距 = 画布宽 − 两个标签宽（≥ 卡片宽 60%）。
                    sunriseX = canvasWidth - sunriseWidth
                    sunsetX = sunsetWidth
                } else if (gap < required) {
                    // 以交点为基准等量推开：日出往右、日落往左，各推一半。
                    val push = (required - gap) / 2f
                    val maxSunriseX = canvasWidth - edgeInset - sunriseWidth
                    val minSunsetX = edgeInset + sunsetWidth
                    val pushedSunrise = (sunrisePointX + push).coerceAtMost(maxSunriseX)
                    val pushedSunset = (sunsetPointX - push).coerceAtLeast(minSunsetX)
                    if (pushedSunrise - pushedSunset >= required) {
                        sunriseX = pushedSunrise
                        sunsetX = pushedSunset
                    } else {
                        // 推到内边距仍不够（两交点几乎重合且贴着边）：才退到画布左右边缘布局。
                        sunriseX = maxSunriseX
                        sunsetX = minSunsetX
                    }
                }
            }
        } else if (hasSizes && sunriseHour != null && sunsetHour != null) {
            // 矩形按 UI 的真实摆法来估：锚点 → 左边缘 → **夹进画布**（左右各留 edgeInset），
            // 窄卡/宽字时夹取会把两侧标签推向中间，这才是真机上「叠在一起」的来源。
            fun placedLeft(rawLeft: Float, width: Float): Float {
                val maxLeft = (canvasWidth - width - edgeInset).coerceAtLeast(edgeInset)
                return rawLeft.coerceIn(edgeInset, maxLeft)
            }

            fun sideRect(anchorX: Float, centerY: Float, width: Float): LabelRect {
                // 锚点在哪一侧，就由它向那一侧展开（与 UI 的 left/right 对齐一致）。
                val rawLeft = if (anchorX > cx) anchorX else anchorX - width
                val left = placedLeft(rawLeft, width)
                return LabelRect(left, centerY - labelHeight / 2f, left + width, centerY + labelHeight / 2f)
            }

            val sunriseRect = sideRect(sunriseX, sunriseY, sunriseWidth)
            val sunsetRect = sideRect(sunsetX, sunsetY, sunsetWidth)
            val noonLeft = placedLeft(cx - noonWidth / 2f, noonWidth)
            val noonRect = LabelRect(
                noonLeft,
                noonY - labelHeight,
                noonLeft + noonWidth,
                noonY,
            )
            val overlaps = sunriseRect.overlaps(sunsetRect) ||
                sunriseRect.overlaps(noonRect) ||
                sunsetRect.overlaps(noonRect)
            if (overlaps) {
                // 边缘退让：日出/日落贴各自那一侧的内边距，竖直取地平线往上一点。
                val y = path.horizonY - sideLabelRise
                val leftEdge = edgeInset
                val rightEdge = canvasWidth - edgeInset
                sunriseX = if (sunriseSign > 0f) {
                    rightEdge - sunriseWidth
                } else {
                    leftEdge + sunriseWidth
                }
                sunsetX = if (sunriseSign > 0f) {
                    leftEdge + sunsetWidth
                } else {
                    rightEdge - sunsetWidth
                }
                sunriseY = y
                sunsetY = y
                // 上中天仍在圆顶上方；若和退让后的两侧标签还相交，就一路顶到画布上沿。
                val topY = edgeInset + labelHeight
                val noonAtTopLeft = placedLeft(cx - noonWidth / 2f, noonWidth)
                val noonAtTop = LabelRect(
                    noonAtTopLeft,
                    topY - labelHeight,
                    noonAtTopLeft + noonWidth,
                    topY,
                )
                val stillOverlaps = noonAtTop.overlaps(sideRect(sunriseX, y, sunriseWidth)) ||
                    noonAtTop.overlaps(sideRect(sunsetX, y, sunsetWidth))
                if (stillOverlaps) noonY = topY
            }
        }
        return SunLabelAnchors(
            sunriseX = sunriseX,
            sunriseY = sunriseY,
            sunsetX = sunsetX,
            sunsetY = sunsetY,
            noonX = cx,
            noonY = noonY,
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
     * 弦两端正好落在日出 / 日落交点上；极昼极夜时地平线在圆外（|dy| > R），返回 0 表示没有弦。
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
