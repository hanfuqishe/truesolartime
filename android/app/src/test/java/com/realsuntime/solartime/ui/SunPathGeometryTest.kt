package com.realsuntime.solartime.ui

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.min
import kotlin.math.sin
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * `SunPathGeometry` 的单元测试。
 *
 * 这些用例把「时间圆盘」的几何模型钉死：圆 = 24 小时、地平线 = 由日出决定的水平弦、
 * 太阳点按真太阳时参数化。任何一个公式被改错，下面的数值都会立刻对不上。
 *
 * 时刻全部是**当地真太阳时**（日出 6.00 = 06:00），不是标准时间。
 */
class SunPathGeometryTest {

    private val width = 400f
    private val height = 400f
    private val radius = SunPathGeometry.RADIUS_RATIO * min(width, height) // 168
    private val centerX = width / 2f
    private val centerY = height / 2f

    /** 赤道春分：日出 06:00、日落 18:00，昼长 12h → 地平线过圆心。 */
    @Test
    fun equinoxAtEquatorPutsHorizonThroughCenter() {
        val path = SunPathGeometry.compute(
            width = width,
            height = height,
            sunriseHour = 6.0,
            sunsetHour = 18.0,
            trueSolarHour = 12.0,
            isPolarDay = false,
            isPolarNight = false,
        )
        assertEquals("地平线应过圆心", centerY, path.horizonY, 0.5f)
        assertFalse(path.isWholeCircleDay)
        assertFalse(path.isWholeCircleNight)
    }

    /** 上海夏至（纬度 31.23°N、赤纬 23.44°）：日出 04:59、日落 19:01，昼长 14h → 地平线在圆心**下方**。 */
    @Test
    fun midsummerAtMidLatitudePutsHorizonBelowCenter() {
        val path = SunPathGeometry.compute(
            width = width,
            height = height,
            sunriseHour = 4.99,
            sunsetHour = 19.01,
            trueSolarHour = 12.0,
            isPolarDay = false,
            isPolarNight = false,
        )
        assertTrue(
            "昼长 > 12h，地平线应在圆心下方：y_h=${path.horizonY} cy=$centerY",
            path.horizonY > centerY,
        )
        // 下移量 = R·|cos θ(日出)|；日出 04:59 → θ ≈ −105.2°，cos ≈ −0.263。
        assertEquals(centerY + radius * 0.263f, path.horizonY, 1.5f)
        assertTrue("太阳点 12:00 必须整圆在白天弧上", path.sunY < path.horizonY)
    }

    /** 中纬度冬至：日出 07:01、日落 16:59，昼长 < 12h → 地平线在圆心**上方**。 */
    @Test
    fun midwinterAtMidLatitudePutsHorizonAboveCenter() {
        val path = SunPathGeometry.compute(
            width = width,
            height = height,
            sunriseHour = 7.01,
            sunsetHour = 16.99,
            trueSolarHour = 12.0,
            isPolarDay = false,
            isPolarNight = false,
        )
        assertTrue(
            "昼长 < 12h，地平线应在圆心上方：y_h=${path.horizonY} cy=$centerY",
            path.horizonY < centerY,
        )
        assertTrue("太阳点 12:00 仍在地平线以上", path.sunY < path.horizonY)
    }

    /** 极昼：没有日出日落，地平线沉到圆下方 → 整圆都在白天。 */
    @Test
    fun polarDaySinksHorizonBelowWholeCircle() {
        val path = SunPathGeometry.compute(
            width = width,
            height = height,
            sunriseHour = null,
            sunsetHour = null,
            trueSolarHour = 0.5, // 半夜十二点半，极昼时仍在地平线以上
            isPolarDay = true,
            isPolarNight = false,
        )
        assertTrue("极昼地平线必须在圆下方：y_h=${path.horizonY}", path.horizonY > centerY + radius)
        assertTrue("整圆都在白天", path.isWholeCircleDay)
        assertFalse(path.isWholeCircleNight)
        assertTrue("半夜的太阳也在白天弧上", path.isSunUp)
        // 整圆都是白天弧：没有「日出→日落」那一段可切，UI 画整圆实线。
        assertNull(SunPathGeometry.dayArcSpan(null, null))
    }

    /** 极夜：没有日出日落，地平线升到圆上方 → 整圆都在夜晚。 */
    @Test
    fun polarNightLiftsHorizonAboveWholeCircle() {
        val path = SunPathGeometry.compute(
            width = width,
            height = height,
            sunriseHour = null,
            sunsetHour = null,
            trueSolarHour = 12.0, // 正午，极夜时仍在地平线以下
            isPolarDay = false,
            isPolarNight = true,
        )
        assertTrue("极夜地平线必须在圆上方：y_h=${path.horizonY}", path.horizonY < centerY - radius)
        assertTrue("整圆都在夜晚", path.isWholeCircleNight)
        assertFalse(path.isWholeCircleDay)
        assertFalse("正午的太阳也在地平线以下", path.isSunUp)
    }

    /** 12:00 在圆顶、00:00 在圆底、06:00 在圆最左、18:00 在圆最右。 */
    @Test
    fun sunPointSitsOnCardinalHours() {
        fun pathAt(hour: Double) = SunPathGeometry.compute(
            width = width,
            height = height,
            sunriseHour = 6.0,
            sunsetHour = 18.0,
            trueSolarHour = hour,
            isPolarDay = false,
            isPolarNight = false,
        )

        val noon = pathAt(12.0)
        assertEquals(centerX, noon.sunX, 0.5f)
        assertEquals("12:00 应在圆顶（y 最小）", centerY - radius, noon.sunY, 0.5f)

        val midnight = pathAt(0.0)
        assertEquals(centerX, midnight.sunX, 0.5f)
        assertEquals("00:00 应在圆底（y 最大）", centerY + radius, midnight.sunY, 0.5f)

        val six = pathAt(6.0)
        assertEquals("06:00 应在圆最左（x 最小）", centerX - radius, six.sunX, 0.5f)
        assertEquals(centerY, six.sunY, 0.5f)

        val eighteen = pathAt(18.0)
        assertEquals("18:00 应在圆最右（x 最大）", centerX + radius, eighteen.sunX, 0.5f)
        assertEquals(centerY, eighteen.sunY, 0.5f)

        // 角度定义本身：θ(12:00)=0、θ(18:00)=+π/2、θ(06:00)=−π/2、θ(00:00)=±π。
        assertEquals(0.0, SunPathGeometry.angleOfDayHour(12.0), 1e-9)
        assertEquals(PI / 2.0, SunPathGeometry.angleOfDayHour(18.0), 1e-9)
        assertEquals(-PI / 2.0, SunPathGeometry.angleOfDayHour(6.0), 1e-9)
        assertEquals(PI, abs(SunPathGeometry.angleOfDayHour(0.0)), 1e-9)
    }

    /** 跨午夜（23:30 → 00:30）必须沿着圆连续走，不能把 24:00 夹回去导致跳变。 */
    @Test
    fun sunPointIsContinuousAcrossMidnight() {
        fun pathAt(hour: Double) = SunPathGeometry.compute(
            width = width,
            height = height,
            sunriseHour = 6.0,
            sunsetHour = 18.0,
            trueSolarHour = hour,
            isPolarDay = false,
            isPolarNight = false,
        )

        // 每半小时一步，从 22:30 走到 01:30（写成 25.5，参数化本身是周期的）。
        val hours = listOf(22.5, 23.0, 23.5, 24.0, 24.5, 25.0, 25.5)
        val steps = hours.zipWithNext { a, b ->
            val pa = pathAt(a)
            val pb = pathAt(b)
            kotlin.math.hypot((pb.sunX - pa.sunX).toDouble(), (pb.sunY - pa.sunY).toDouble())
        }
        // 半小时 = 7.5° 圆心角，弦长恒定：2R·sin(3.75°)。
        val expected = 2.0 * radius * sin(Math.toRadians(7.5) / 2.0)
        steps.forEach { step ->
            assertEquals("跨午夜的步长必须与其它时段一致", expected, step, 1e-2)
        }

        // 23:30 与 00:30 都在圆的下半部（y > 圆心），没有跳回圆顶。
        val late = pathAt(23.5)
        val early = pathAt(24.5)
        assertTrue("23:30 应在圆下半部", late.sunY > centerY)
        assertTrue("00:30 应在圆下半部", early.sunY > centerY)

        // 角度也连续：θ(00:30) 与 θ(23:30) 相差 15°（取模后），而不是绕一整圈。
        val deltaDegrees = Math.toDegrees(
            SunPathGeometry.angleOfDayHour(0.5) - SunPathGeometry.angleOfDayHour(23.5),
        )
        val wrapped = ((deltaDegrees % 360.0) + 360.0) % 360.0
        assertEquals(15.0, wrapped, 1e-6)
    }

    /** 圆心在画布中央、半径 = 0.42 × min(width, height)，与宽高比例无关。 */
    @Test
    fun radiusAndCenterFollowCanvasSize() {
        val sizes = listOf(
            400f to 300f,
            300f to 400f,
            1080f to 1080f,
            100f to 800f,
            720f to 1280f,
        )
        for ((w, h) in sizes) {
            val path = SunPathGeometry.compute(
                width = w,
                height = h,
                sunriseHour = 6.0,
                sunsetHour = 18.0,
                trueSolarHour = 12.0,
                isPolarDay = false,
                isPolarNight = false,
            )
            assertEquals("centerX for ${w}x$h", w / 2f, path.centerX, 0.5f)
            assertEquals("centerY for ${w}x$h", h / 2f, path.centerY, 0.5f)
            assertEquals(
                "radius for ${w}x$h",
                0.38f * min(w, h),
                path.radius,
                0.5f,
            )
        }
    }

    /** 地平线这条弦的两端正好落在日出 / 日落交点上。 */
    @Test
    fun horizonChordEndsAtSunriseAndSunsetPoints() {
        val sunrise = 4.99
        val sunset = 19.01
        val path = SunPathGeometry.compute(
            width = width,
            height = height,
            sunriseHour = sunrise,
            sunsetHour = sunset,
            trueSolarHour = 12.0,
            isPolarDay = false,
            isPolarNight = false,
        )
        val halfChord = SunPathGeometry.horizonHalfChord(path)
        assertTrue("地平线必须与圆相交", halfChord > 0f)
        // 弦端 x = 日出点 x，弦端 y = 地平线 y = 日出点 y。
        assertEquals(
            SunPathGeometry.hourX(path.centerX, path.radius, sunrise),
            path.centerX - halfChord,
            0.5f,
        )
        assertEquals(
            SunPathGeometry.hourX(path.centerX, path.radius, sunset),
            path.centerX + halfChord,
            0.5f,
        )
        assertEquals(
            SunPathGeometry.hourY(path.centerY, path.radius, sunrise),
            path.horizonY,
            0.5f,
        )
    }

    /** 白天弧的扫角 = 昼长占 24h 的比例；从日出交点顺时针经过 12:00 扫到日落交点。 */
    @Test
    fun dayArcSpanRunsFromSunriseThroughNoonToSunset() {
        val twelveHour = SunPathGeometry.dayArcSpan(6.0, 18.0)
        assertTrue(twelveHour != null)
        assertEquals(-180f, twelveHour!!.startDegrees, 1e-3f)
        assertEquals("昼长 12h → 扫 180°", 180f, twelveHour.sweepDegrees, 1e-3f)

        // 上海夏至昼长 14.02h → 扫角 ≈ 210.3°，起点在日出（左下方）。
        val summer = SunPathGeometry.dayArcSpan(4.99, 19.01)
        assertEquals(14.02 / 24.0 * 360.0, summer!!.sweepDegrees.toDouble(), 0.1)

        // 落日越过 24:00 时按下一圈补 2π，扫角仍是正数（昼长 21.5h → 322.5°）。
        val wrapped = SunPathGeometry.dayArcSpan(3.0, 0.5)
        assertEquals(21.5 / 24.0 * 360.0, wrapped!!.sweepDegrees.toDouble(), 0.1)
    }

    /**
     * 交点上的小圆点已删，白天弧两端各外扩 [SunPathGeometry.ARC_ENDPOINT_OVERDRAW_DEG]，
     * 让圆头线帽略微穿过地平线；按 R≈74dp 换算，这段外扩约 1dp。
     */
    @Test
    fun dayArcEndsAreExtendedSlightlyBeyondTheHorizonCrossings() {
        val span = SunPathGeometry.dayArcSpan(6.0, 18.0)!!
        val extended = SunPathGeometry.withEndpointOverdraw(span)

        assertEquals(
            span.startDegrees - SunPathGeometry.ARC_ENDPOINT_OVERDRAW_DEG,
            extended.startDegrees,
            1e-4f,
        )
        assertEquals(
            span.sweepDegrees + 2f * SunPathGeometry.ARC_ENDPOINT_OVERDRAW_DEG,
            extended.sweepDegrees,
            1e-4f,
        )
        // 两端都真的越过了交点：起点更早、终点更晚。
        assertTrue(extended.startDegrees < span.startDegrees)
        assertTrue(extended.startDegrees + extended.sweepDegrees > span.startDegrees + span.sweepDegrees)

        // 外扩量级：0.5°~1°，在真实半径上约 1dp。
        assertTrue(SunPathGeometry.ARC_ENDPOINT_OVERDRAW_DEG in 0.5f..1f)
        val radius = SunPathGeometry.RADIUS_RATIO * dialHeight
        val overdrawDp = radius * Math.toRadians(SunPathGeometry.ARC_ENDPOINT_OVERDRAW_DEG.toDouble()).toFloat()
        assertEquals("外扩应约 1dp", 1.0f, overdrawDp, 0.15f)
    }

    /** 昼长接近 24h 时外扩不会把扫角顶过 360°（否则夜间弧会变成负扫角、画反）。 */
    @Test
    fun endpointOverdrawNeverExceedsAFullCircle() {
        val nearFull = SunPathGeometry.dayArcSpan(0.05, 23.95)!!
        val extended = SunPathGeometry.withEndpointOverdraw(nearFull)
        assertTrue("扫角不能超过整圈：${extended.sweepDegrees}", extended.sweepDegrees <= 360f)
        assertTrue("夜间弧扫角不能为负：${360f - extended.sweepDegrees}", 360f - extended.sweepDegrees >= 0f)
    }

    // ---- 外侧标签锚点（labelAnchors） ----
    //
    // 画布比例取卡片里的真实值：334dp 的卡减掉左右各 20dp 内边距 = 294dp 宽 × 194dp 高。
    // 间距也是 UI 里的 dp 数（测试里 1dp = 1px，纯几何层不关心密度）。

    private val dialWidth = 294f
    private val dialHeight = 194f
    private val sideGap = 10f
    private val noonGap = 8f
    private val labelDrop = 18f
    /** 标签从交点往上抬这么多，给延伸后的地平线让路。 */
    private val labelRise = 10f
    /** 11sp 的「23:59」约 30dp 宽，用来验「标签不越出画布」。 */
    private val labelWidth = 30f
    /** 标签与卡片左右边缘的最小留白。 */
    private val sideInset = 8f
    /** labelSmall 的行高。 */
    private val labelHeight = 16f

    // 带文字说明的新标签：「日出 06:24」≈ 2 汉字 + 空格 + 5 字符；「上中天 11:39」更长。
    private val sunriseLabelWidth = 55f
    private val sunsetLabelWidth = 55f
    private val noonLabelWidth = 66f

    private fun dial(
        sunriseHour: Double?,
        sunsetHour: Double?,
        trueSolarHour: Double = 12.0,
        isPolarDay: Boolean = false,
        isPolarNight: Boolean = false,
        southernHemisphere: Boolean = false,
    ): SunPath = SunPathGeometry.compute(
        width = dialWidth,
        height = dialHeight,
        sunriseHour = sunriseHour,
        sunsetHour = sunsetHour,
        trueSolarHour = trueSolarHour,
        isPolarDay = isPolarDay,
        isPolarNight = isPolarNight,
        southernHemisphere = southernHemisphere,
    )

    private fun anchors(path: SunPath, sunriseHour: Double?, sunsetHour: Double?): SunLabelAnchors =
        SunPathGeometry.labelAnchors(path, sunriseHour, sunsetHour, sideGap, noonGap, labelDrop, labelRise)

    /** 标签所在那一行上，圆的左 / 右边界 x：标签永远贴在它外侧 [sideGap] 处。 */
    private fun circleBoundaryAt(path: SunPath, labelY: Float): Pair<Float, Float> {
        val dy = labelY - path.centerY
        val half = kotlin.math.sqrt((path.radius * path.radius - dy * dy).coerceAtLeast(0f))
        return (path.centerX - half) to (path.centerX + half)
    }

    /** 赤道春分：两个交点落在圆的最左 / 最右（= 圆心高度），标签在交点外侧、略高于地平线。 */
    @Test
    fun labelAnchorsOnEquinoxSitBesideTheLeftAndRightIntersections() {
        val path = dial(6.0, 18.0)
        val a = anchors(path, 6.0, 18.0)
        assertEquals("春分交点在地平线（= 圆心高度），标签抬高了 labelRise", path.centerY - labelRise, a.sunriseY, 0.5f)
        assertEquals(path.centerY - labelRise, a.sunsetY, 0.5f)
        val (left, right) = circleBoundaryAt(path, a.sunriseY)
        assertEquals("日出标签贴在左边界外侧", left - sideGap, a.sunriseX, 0.5f)
        assertEquals("日落标签贴在右边界外侧", right + sideGap, a.sunsetX, 0.5f)
        assertEquals("上中天标签在圆顶正上方", path.centerX, a.noonX, 0.5f)
        assertEquals(path.centerY - path.radius - noonGap, a.noonY, 0.5f)
        assertEquals("极昼／极夜文案锚在圆心", path.centerX, a.polarX, 0.5f)
        assertEquals(path.centerY, a.polarY, 0.5f)
        // 抬起来之后，地平线从文字底下穿过，不会压字。
        assertTrue(
            "标签底边必须在地平线上方：${a.sunriseY + labelHeight / 2} vs ${path.horizonY}",
            a.sunriseY + labelHeight / 2 <= path.horizonY - 1f,
        )
    }

    /** 上海夏至：地平线下移，两个交点在圆心下方，标签跟着下去（仍比地平线高一点）。 */
    @Test
    fun labelAnchorsFollowTheLoweredHorizonInMidsummer() {
        val path = dial(4.99, 19.01)
        val a = anchors(path, 4.99, 19.01)
        assertTrue("日出标签应在圆心下方：${a.sunriseY} vs ${path.centerY}", a.sunriseY > path.centerY)
        assertEquals("标签比地平线高一档（给线条让路）", path.horizonY - labelRise, a.sunriseY, 0.5f)
        assertEquals(path.horizonY - labelRise, a.sunsetY, 0.5f)
        assertTrue(a.sunriseY + labelHeight / 2 <= path.horizonY - 1f)
        // 标签贴着「自己那一行」的圆边界，跟交点所在行只差 labelRise 的高度。
        val (left, right) = circleBoundaryAt(path, a.sunriseY)
        assertEquals(left - sideGap, a.sunriseX, 0.5f)
        assertEquals(right + sideGap, a.sunsetX, 0.5f)
        // 抬起来以后离交点只差「间距 + 圆的弯曲」：这个高度附近圆几乎是竖直的，偏移 ≈ sideGap。
        assertTrue(
            "标签仍在左交点附近：${a.sunriseX} vs ${SunPathGeometry.hourX(path.centerX, path.radius, 4.99)}",
            kotlin.math.abs(a.sunriseX - SunPathGeometry.hourX(path.centerX, path.radius, 4.99)) < sideGap + 4f,
        )
    }

    /** 极昼：整圆白天，**保留**上中天标签；极昼文案锚在圆心。 */
    @Test
    fun polarDayKeepsTransitLabel() {
        val path = dial(null, null, isPolarDay = true)
        assertTrue("极昼要有上中天标签", path.hasTransitLabel)
        assertTrue(path.isWholeCircleDay)
        val a = anchors(path, null, null)
        assertEquals(path.centerX, a.noonX, 0.5f)
        assertEquals(path.centerY - path.radius - noonGap, a.noonY, 0.5f)
        // 没有交点时日出／日落锚点退到圆的最左 / 最右（06:00 / 18:00 的位置）。
        assertEquals(path.centerX - path.radius - sideGap, a.sunriseX, 0.5f)
        assertEquals(path.centerY, a.sunriseY, 0.5f)
        assertEquals(path.centerX + path.radius + sideGap, a.sunsetX, 0.5f)
    }

    /** 极夜：**没有**上中天标签（太阳整日不升），只留圆心那行「极夜」。 */
    @Test
    fun polarNightHasNoTransitLabel() {
        val path = dial(null, null, isPolarNight = true)
        assertFalse("极夜不该有上中天标签", path.hasTransitLabel)
        assertTrue(path.isWholeCircleNight)
        val a = anchors(path, null, null)
        assertEquals("极夜文案在圆心", path.centerX, a.polarX, 0.5f)
        assertEquals(path.centerY, a.polarY, 0.5f)
    }

    /** 日出 0:00（日落 24:00）：地平线与圆**相切于最下方**，两个标签贴在底点两侧。 */
    @Test
    fun sunriseAtMidnightMakesHorizonTangentAtTheBottom() {
        val path = dial(0.0, 24.0, trueSolarHour = 0.0)
        assertEquals("相切：y_h = C.y + R", path.centerY + path.radius, path.horizonY, 0.5f)
        assertTrue("整圆都在白天", path.isWholeCircleDay)
        assertEquals("弦退化成一个点", 0f, SunPathGeometry.horizonHalfChord(path), 0.5f)

        val a = anchors(path, 0.0, 24.0)
        // 抬起来之后两个标签会沿着圆往两边让开一点（圆的底部是尖的），但仍然贴在底点附近。
        assertEquals(path.centerY + path.radius - labelRise, a.sunriseY, 0.5f)
        assertEquals(path.centerY + path.radius - labelRise, a.sunsetY, 0.5f)
        val (left, right) = circleBoundaryAt(path, a.sunriseY)
        assertEquals("日出标签贴在底点左侧的圆外", left - sideGap, a.sunriseX, 0.5f)
        assertEquals("日落标签贴在底点右侧的圆外", right + sideGap, a.sunsetX, 0.5f)
        assertTrue("日出标签应在圆心的左半边", a.sunriseX < path.centerX - path.radius * 0.3f)
        assertTrue("日落标签应在圆心的右半边", a.sunsetX > path.centerX + path.radius * 0.3f)
        val bottomDistance = kotlin.math.hypot(
            (a.sunriseX - path.centerX).toDouble(),
            (a.sunriseY - path.bottomY).toDouble(),
        )
        // 圆底是个尖：标签为了躲开地平线抬高 labelRise，就必然沿着圆往两边让开
        // sqrt(2R·rise) 左右；0.7R 以内仍算「底点附近」。
        assertTrue(
            "日出标签应离底点不远：$bottomDistance vs R=${path.radius}",
            bottomDistance <= path.radius * 0.7,
        )
    }

    /** 高纬度昼长 1 小时：两交点只隔约 15°，标签必须分列左右交点外侧、彼此不重叠、不压弧线。 */
    @Test
    fun shortDayKeepsLabelsApartAndOutsideTheCircle() {
        val sunrise = 11.5
        val sunset = 12.5
        val path = dial(sunrise, sunset)
        val a = anchors(path, sunrise, sunset)
        val leftIntersectionX = SunPathGeometry.hourX(path.centerX, path.radius, sunrise)
        val rightIntersectionX = SunPathGeometry.hourX(path.centerX, path.radius, sunset)

        assertTrue("日出交点应在圆心左侧", leftIntersectionX < path.centerX)
        assertTrue("日落交点应在圆心右侧", rightIntersectionX > path.centerX)
        assertTrue(
            "日出标签右边界必须在左交点左边：${a.sunriseX} vs $leftIntersectionX",
            a.sunriseX < leftIntersectionX,
        )
        assertTrue(
            "日落标签左边界必须在右交点右边：${a.sunsetX} vs $rightIntersectionX",
            a.sunsetX > rightIntersectionX,
        )
        assertTrue("两个标签之间至少隔两个 sideGap", a.sunsetX - a.sunriseX > sideGap * 2f)

        // 短昼保护：不下沉的话标签会挤到圆顶、和上中天标签撞在同一行。
        assertEquals("短昼时下沉到圆顶下方 labelDrop 处", path.centerY - path.radius + labelDrop, a.sunriseY, 0.5f)
        // 下沉后仍要贴在圆外：标签 x = 圆心 − 该高度上的半宽 − sideGap。
        val dy = a.sunriseY - path.centerY
        val halfWidthAtLabel = kotlin.math.sqrt(
            (path.radius * path.radius - dy * dy).coerceAtLeast(0f),
        )
        assertEquals(path.centerX - halfWidthAtLabel - sideGap, a.sunriseX, 0.5f)
        // 标签不会盖住上中天标签：两者竖直方向至少隔了半行字。
        assertTrue("日出标签应在上中天标签下方", a.sunriseY - labelHeight / 2 >= a.noonY - labelHeight)
    }

    /** 五个场景的标签都不越出画布左右两侧（各留 ≥8dp），竖直方向也不出画布。 */
    // ---- 重叠退让（近极昼：日出/日落/上中天挤到一起） ----

    /** 带「真实标签尺寸」的锚点计算（与 UI 传参一致）。 */
    private fun anchorsWithSizes(
        path: SunPath,
        sunriseHour: Double?,
        sunsetHour: Double?,
        sunriseWidth: Float = sunriseLabelWidth,
        sunsetWidth: Float = sunsetLabelWidth,
        noonWidth: Float = noonLabelWidth,
    ): SunLabelAnchors = SunPathGeometry.labelAnchors(
        path = path,
        sunriseHour = sunriseHour,
        sunsetHour = sunsetHour,
        sideGap = sideGap,
        noonGap = noonGap,
        minLabelDrop = labelDrop,
        sideLabelRise = labelRise,
        sunriseWidth = sunriseWidth,
        sunsetWidth = sunsetWidth,
        noonWidth = noonWidth,
        labelHeight = labelHeight,
        edgeInset = sideInset,
        canvasWidth = dialWidth,
    )

    private data class Rect(val left: Float, val top: Float, val right: Float, val bottom: Float) {
        fun overlaps(o: Rect): Boolean =
            left < o.right && o.left < right && top < o.bottom && o.top < bottom
    }

    /** 按 UI 的对齐规则把锚点还原成矩形：日出/日落锚点是挨着圆的边，上中天是中心 + 底边。 */
    private fun rects(
        path: SunPath,
        a: SunLabelAnchors,
        sunriseW: Float = sunriseLabelWidth,
        sunsetW: Float = sunsetLabelWidth,
        noonW: Float = noonLabelWidth,
    ): List<Rect> {
        fun side(x: Float, y: Float, width: Float): Rect {
            val left = if (x > path.centerX) x else x - width
            return Rect(left, y - labelHeight / 2f, left + width, y + labelHeight / 2f)
        }
        return listOf(
            side(a.sunriseX, a.sunriseY, sunriseW),
            side(a.sunsetX, a.sunsetY, sunsetW),
            Rect(a.noonX - noonW / 2f, a.noonY - labelHeight, a.noonX + noonW / 2f, a.noonY),
        )
    }

    /**
     * 南极中山站（69.37°S，近极昼：日落 02:01 / 日出 03:18，昼长 22.7h）：
     * 标签在**交点正下方**，只做最小必要外推（偏移 ≤ 40% 卡片宽），三者矩形两两不相交。
     */
    @Test
    fun nearPolarDayKeepsLabelsUnderTheIntersectionsAndApart() {
        val path = dial(3.3, 2.02, trueSolarHour = 9.7, southernHemisphere = true)
        val a = anchorsWithSizes(path, 3.3, 2.02)
        val sunrisePoint = SunPathGeometry.hourX(path.centerX, path.radius, 3.3, southernHemisphere = true)
        val sunsetPoint = SunPathGeometry.hourX(path.centerX, path.radius, 2.02, southernHemisphere = true)

        // 地平线下方
        assertTrue("日出标签应在地平线下方：${a.sunriseY} vs ${path.horizonY}", a.sunriseY > path.horizonY)
        assertTrue("日落标签应在地平线下方", a.sunsetY > path.horizonY)
        // 仍以交点为基准：偏移不超过卡片宽 40%
        assertTrue(
            "日出标签偏移过大：${a.sunriseX} vs 交点 $sunrisePoint",
            kotlin.math.abs(a.sunriseX - sunrisePoint) <= dialWidth * 0.4f,
        )
        assertTrue(
            "日落标签偏移过大：${a.sunsetX} vs 交点 $sunsetPoint",
            kotlin.math.abs(a.sunsetX - sunsetPoint) <= dialWidth * 0.4f,
        )
        // 间距够放得下较宽的那个标签
        assertTrue("两个标签间距不足：${a.sunriseX - a.sunsetX}", a.sunriseX - a.sunsetX >= sunriseLabelWidth + 8f)
        // 三者两两不相交
        val (sr, ss, noon) = rects(path, a)
        assertFalse("日出标签不能与日落标签相交", sr.overlaps(ss))
        assertFalse("日出标签不能与上中天相交", sr.overlaps(noon))
        assertFalse("日落标签不能与上中天相交", ss.overlaps(noon))
    }

    /** 南半球普通日（悉尼）：标签 x **就是交点 x**（偏移 0），在地平线下方、左右不重叠。 */
    @Test
    fun southernHemisphereLabelsSitDirectlyUnderTheIntersections() {
        val path = dial(6.0, 18.0, southernHemisphere = true)
        val a = anchorsWithSizes(path, 6.0, 18.0)
        assertEquals(
            "日出标签 x 应等于交点 x",
            SunPathGeometry.hourX(path.centerX, path.radius, 6.0, southernHemisphere = true),
            a.sunriseX,
            0.01f,
        )
        assertEquals(
            "日落标签 x 应等于交点 x",
            SunPathGeometry.hourX(path.centerX, path.radius, 18.0, southernHemisphere = true),
            a.sunsetX,
            0.01f,
        )
        assertTrue("日出标签在地平线下方", a.sunriseY > path.horizonY)
        assertTrue("日落标签在地平线下方", a.sunsetY > path.horizonY)
        assertTrue("南半球日出在右", a.sunriseX > path.centerX)
        assertTrue("南半球日落在左", a.sunsetX < path.centerX)
        val (sr, ss, noon) = rects(path, a)
        assertFalse(sr.overlaps(ss))
        assertFalse(sr.overlaps(noon))
        assertFalse(ss.overlaps(noon))
    }

    /** 极端近极昼（日出=日落同点）：退到画布边缘布局，横向间距 ≥ 卡片宽 60%。 */
    @Test
    fun coincidentIntersectionsFallBackToTheCanvasEdges() {
        val path = dial(2.02, 2.02, trueSolarHour = 0.0, southernHemisphere = true)
        val a = anchorsWithSizes(path, 2.02, 2.02)
        assertEquals(dialWidth - sunriseLabelWidth, a.sunriseX, 0.5f)
        assertEquals(sunsetLabelWidth, a.sunsetX, 0.5f)
        assertTrue("间距应 ≥ 60% 卡片宽：${a.sunriseX - a.sunsetX}", a.sunriseX - a.sunsetX >= dialWidth * 0.6f)
        assertTrue("仍在地平线下方", a.sunriseY > path.horizonY && a.sunsetY > path.horizonY)
        val (sr, ss, noon) = rects(path, a)
        assertFalse(sr.overlaps(ss))
        assertFalse(sr.overlaps(noon))
        assertFalse(ss.overlaps(noon))
    }

    /** 北半球（北京）：传了标签尺寸也与改动前**完全一致**（逐字段相等）。 */
    @Test
    fun northernHemisphereKeepsTheExactOldAnchors() {
        val beijing = dial(6.2, 17.8)
        assertEquals(anchors(beijing, 6.2, 17.8), anchorsWithSizes(beijing, 6.2, 17.8))
    }

    /** 极昼/极夜没有日出日落：不做任何南半球处理，锚点与旧版一致（UI 本来就不画这两个标签）。 */
    @Test
    fun polarDaysKeepTheOldAnchors() {
        val path = dial(null, null, isPolarDay = true)
        assertEquals(anchors(path, null, null), anchorsWithSizes(path, null, null))
        assertTrue(path.hasTransitLabel)
    }
    @Test
    fun labelAnchorsStayInsideTheCanvasOnSmallCards() {
        // 最小的常见卡片：320dp 宽 − 20×2 内边距 = 280dp；高度不变。
        val w = 280f
        val h = dialHeight
        val cases = listOf(
            Triple("赤道春分", 6.0, 18.0),
            Triple("上海夏至", 4.99, 19.01),
            Triple("昼长 1 小时", 11.5, 12.5),
            Triple("日出 0:00", 0.0, 24.0),
        )
        for ((name, sunrise, sunset) in cases) {
            val path = SunPathGeometry.compute(w, h, sunrise, sunset, 12.0, false, false)
            val a = SunPathGeometry.labelAnchors(path, sunrise, sunset, sideGap, noonGap, labelDrop, labelRise)
            // 日出标签右对齐、日落标签左对齐。
            assertTrue("$name 日出标签越界：${a.sunriseX}", a.sunriseX - labelWidth >= sideInset)
            assertTrue("$name 日落标签越界：${a.sunsetX}", a.sunsetX + labelWidth <= w - sideInset)
            assertTrue("$name 上中天标签越界（左）", a.noonX - labelWidth / 2 >= sideInset)
            assertTrue("$name 上中天标签越界（右）", a.noonX + labelWidth / 2 <= w - sideInset)
            assertTrue("$name 上中天标签顶出画布", a.noonY - labelHeight >= -1f)
            assertTrue("$name 日出标签底出画布", a.sunriseY + labelHeight / 2 <= h + 1f)
            assertTrue("$name 日落标签底出画布", a.sunsetY + labelHeight / 2 <= h + 1f)
        }
        // 极昼 / 极夜：只剩圆心那行字（极昼另有上中天标签）。
        val polarCases = listOf(Triple("极昼", true, false), Triple("极夜", false, true))
        for ((name, polarDay, polarNight) in polarCases) {
            val path = SunPathGeometry.compute(w, h, null, null, 12.0, polarDay, polarNight)
            val a = SunPathGeometry.labelAnchors(path, null, null, sideGap, noonGap, labelDrop, labelRise)
            assertTrue(
                "$name 文案越界",
                a.polarX - labelWidth / 2 >= sideInset && a.polarX + labelWidth / 2 <= w - sideInset,
            )
            assertTrue("$name 文案竖直出界", a.polarY - labelHeight / 2 >= 0f && a.polarY + labelHeight / 2 <= h)
            if (polarDay) {
                assertTrue("极昼上中天标签越界", a.noonX - labelWidth / 2 >= sideInset)
            }
        }
    }

    /**
     * 地平线是**固定长度**的：画布左右各内缩 [sideInset]（4dp），长度恒为 `canvasWidth − 8`。
     *
     * 五种场景（普通日 / 上海夏至 / 昼长 1 小时 / 0:00 相切 / 极昼 / 极夜）地平线的**高度**各不相同，
     * 但**长度和起止 x 必须完全一样** —— 它是一条贯穿画面的地平线，不再是「圆的弦 + 延伸」。
     */
    @Test
    fun horizonSpansTheCanvasAtFixedLength() {
        val normalCases = listOf(
            Triple("赤道春分", 6.0, 18.0),
            Triple("上海夏至", 4.99, 19.01),
            Triple("昼长 1 小时", 11.5, 12.5),
            Triple("日出 0:00（相切）", 0.0, 24.0),
        )
        val paths = normalCases.map { (_, sunrise, sunset) ->
            SunPathGeometry.compute(dialWidth, dialHeight, sunrise, sunset, 12.0, false, false)
        } + listOf(true to false, false to true).map { (polarDay, polarNight) ->
            SunPathGeometry.compute(dialWidth, dialHeight, null, null, 12.0, polarDay, polarNight)
        }
        // 六个场景的地平线高度互不相同 —— 说明「固定长度」不是靠数值恰好相等蒙过去的。
        assertEquals("六种场景的地平线高度应各不相同", 6, paths.map { it.horizonY }.toSet().size)

        val spans = paths.map { SunPathGeometry.horizonSpan(dialWidth, sideInset) }
        spans.forEach { span ->
            assertEquals("左端 = 画布内缩 $sideInset", sideInset, span.startX, 0.5f)
            assertEquals("右端 = 画布宽 − 内缩", dialWidth - sideInset, span.endX, 0.5f)
            assertEquals(
                "长度 = 画布宽 − 2×内缩",
                dialWidth - 2 * sideInset,
                span.length,
                0.5f,
            )
        }
        spans.drop(1).forEach { span ->
            assertEquals("所有场景的地平线必须一样长", spans.first().length, span.length, 0.5f)
            assertEquals("所有场景的起点必须一样", spans.first().startX, span.startX, 0.5f)
            assertEquals("所有场景的终点必须一样", spans.first().endX, span.endX, 0.5f)
        }

        // 窄画布同理：只有左右内缩，跟圆的尺寸无关。
        val narrowSpan = SunPathGeometry.horizonSpan(160f, sideInset)
        assertEquals(sideInset, narrowSpan.startX, 0.5f)
        assertEquals(160f - sideInset, narrowSpan.endX, 0.5f)
        assertEquals(160f - 2 * sideInset, narrowSpan.length, 0.5f)
    }

    // ---- 南北半球：太阳方向镜像 ----

    private fun dialSouth(
        sunriseHour: Double?,
        sunsetHour: Double?,
        trueSolarHour: Double = 12.0,
        isPolarDay: Boolean = false,
        isPolarNight: Boolean = false,
    ): SunPath = SunPathGeometry.compute(
        width = dialWidth,
        height = dialHeight,
        sunriseHour = sunriseHour,
        sunsetHour = sunsetHour,
        trueSolarHour = trueSolarHour,
        isPolarDay = isPolarDay,
        isPolarNight = isPolarNight,
        southernHemisphere = true,
    )

    /** 北半球（上海 31.2°N）：06:00 在左、18:00 在右，太阳从左往右。 */
    @Test
    fun northernHemisphereRunsLeftToRight() {
        fun at(hour: Double) = SunPathGeometry.compute(width, height, 6.0, 18.0, hour, false, false)
        assertTrue("北半球 06:00 应在圆心左侧：${at(6.0).sunX} vs $centerX", at(6.0).sunX < centerX)
        assertTrue("北半球 18:00 应在圆心右侧", at(18.0).sunX > centerX)
        assertEquals("12:00 仍在圆顶", centerY - radius, at(12.0).sunY, 0.5f)
        assertEquals("00:00 仍在圆底", centerY + radius, at(0.0).sunY, 0.5f)
        // 11:00 → 13:00 向右走。
        assertTrue("北半球上午到下午太阳向右移动", at(13.0).sunX > at(11.0).sunX)
    }

    /** 南半球（中山站 −69.4°S）：06:00 在**右**、18:00 在**左**，太阳从右往左（逆时针）。 */
    @Test
    fun southernHemisphereMirrorsTheSun() {
        fun southAt(hour: Double) = dialSouth(6.0, 18.0, hour)
        assertTrue("南半球 06:00 应在圆心右侧：${southAt(6.0).sunX} vs ${dialWidth / 2}", southAt(6.0).sunX > dialWidth / 2)
        assertTrue("南半球 18:00 应在圆心左侧", southAt(18.0).sunX < dialWidth / 2)
        assertEquals("12:00 仍在圆顶（南北一样）", dialHeight / 2 - SunPathGeometry.RADIUS_RATIO * dialHeight, southAt(12.0).sunY, 0.5f)
        assertEquals("00:00 仍在圆底", dialHeight / 2 + SunPathGeometry.RADIUS_RATIO * dialHeight, southAt(0.0).sunY, 0.5f)
        assertTrue("南半球上午到下午太阳向左移动", southAt(13.0).sunX < southAt(11.0).sunX)

        // 同一时刻的 x 关于圆心与北半球镜像，y 完全相同。
        for (hour in listOf(3.0, 6.0, 9.0, 12.0, 15.0, 18.0, 21.0, 23.5, 0.5)) {
            val north = dial(6.0, 18.0, trueSolarHour = hour)
            val south = dialSouth(6.0, 18.0, trueSolarHour = hour)
            assertEquals("$hour 的 x 应左右镜像", 2 * north.centerX - north.sunX, south.sunX, 0.5f)
            assertEquals("$hour 的 y 应不受半球影响", north.sunY, south.sunY, 0.5f)
        }

        // 极昼时整圆方向也跟着镜像：06:00 的太阳北半球在左、南半球在右。
        val polarNorth = SunPathGeometry.compute(dialWidth, dialHeight, null, null, 6.0, true, false)
        val polarSouth = dialSouth(null, null, trueSolarHour = 6.0, isPolarDay = true)
        assertTrue("极昼北半球 06:00 在左", polarNorth.sunX < polarNorth.centerX)
        assertTrue("极昼南半球 06:00 在右", polarSouth.sunX > polarSouth.centerX)
        assertTrue("极昼两边都是整圆", polarNorth.isWholeCircleDay && polarSouth.isWholeCircleDay)
    }

    /**
     * 南半球日出标签锚点在**右**、日落在**左**（北半球相反）；
     * 南半球统一放到地平线**下方**（北半球仍在地平线上方）。
     */
    @Test
    fun southernHemisphereSwapsSunriseAndSunsetLabels() {
        val north = dial(4.99, 19.01)
        val northAnchors = anchors(north, 4.99, 19.01)
        assertTrue("北半球日出标签在左", northAnchors.sunriseX < north.centerX)
        assertTrue("北半球日落标签在右", northAnchors.sunsetX > north.centerX)
        assertTrue("北半球标签在地平线上方", northAnchors.sunriseY < north.horizonY)

        val south = dialSouth(4.99, 19.01)
        assertTrue("路径要记住这是南半球", south.southernHemisphere)
        val southAnchors = anchors(south, 4.99, 19.01)
        assertTrue(
            "南半球日出标签应在圆心右侧：${southAnchors.sunriseX} vs ${south.centerX}",
            southAnchors.sunriseX > south.centerX,
        )
        assertTrue("南半球日落标签应在圆心左侧", southAnchors.sunsetX < south.centerX)
        assertTrue("南半球日出标签在地平线下方", southAnchors.sunriseY > south.horizonY)
        assertTrue("南半球日落标签在地平线下方", southAnchors.sunsetY > south.horizonY)
    }

    /** 地平线只由昼长决定：同一昼长下南北半球的 horizonY 与地平线跨度完全相同。 */
    @Test
    fun horizonIsIndependentOfHemisphere() {
        for ((sunrise, sunset) in listOf(6.0 to 18.0, 4.99 to 19.01, 11.5 to 12.5, 0.0 to 24.0)) {
            val north = dial(sunrise, sunset)
            val south = dialSouth(sunrise, sunset)
            assertEquals(
                "昼长 ($sunrise/$sunset) 的地平线不应随半球变化",
                north.horizonY,
                south.horizonY,
                1e-4f,
            )
            assertEquals(north.bottomY, south.bottomY, 1e-4f)
            assertEquals(north.topY, south.topY, 1e-4f)
            val northSpan = SunPathGeometry.horizonSpan(dialWidth, sideInset)
            val southSpan = SunPathGeometry.horizonSpan(dialWidth, sideInset)
            assertEquals(northSpan.startX, southSpan.startX, 1e-4f)
            assertEquals(northSpan.endX, southSpan.endX, 1e-4f)
        }
        // 极昼 / 极夜：地平线位置同样与半球无关。
        for ((polarDay, polarNight) in listOf(true to false, false to true)) {
            val north = SunPathGeometry.compute(dialWidth, dialHeight, null, null, 12.0, polarDay, polarNight)
            val south = dialSouth(null, null, isPolarDay = polarDay, isPolarNight = polarNight)
            assertEquals(north.horizonY, south.horizonY, 1e-4f)
        }
    }

    // ---- 圆盘内侧的「太阳运动方向」箭头 ----

    private fun arrowAngle(path: SunPath, x: Float, y: Float): Double =
        Math.toDegrees(kotlin.math.atan2((y - path.centerY).toDouble(), (x - path.centerX).toDouble()))

    /** 从 start 到 end 的屏幕扫角，归一到 (−180, 180]：正 = 顺时针，负 = 逆时针。 */
    private fun arrowSweep(path: SunPath, arrow: MotionArrow): Double {
        val start = arrowAngle(path, arrow.startX, arrow.startY)
        val end = arrowAngle(path, arrow.endX, arrow.endY)
        return (end - start + 540.0) % 360.0 - 180.0
    }

    /** 北半球 12:00：弧从 start 顺时针扫到 end（时间增大的方向），箭头尖 == end。 */
    @Test
    fun motionArrowRunsClockwiseInTheNorth() {
        val path = dial(6.0, 18.0, trueSolarHour = 12.0)
        val arrow = SunPathGeometry.motionArrow(path, 12.0)
        assertEquals("箭头尖就是弧的终点（x）", arrow.endX, arrow.tipX, 0f)
        assertEquals("箭头尖就是弧的终点（y）", arrow.endY, arrow.tipY, 0f)
        val sweep = arrowSweep(path, arrow)
        assertEquals("北半球 12:00 应顺时针扫过 +30°，实际 $sweep", 30.0, sweep, 0.1)
        // 12:00 的弧在圆顶附近，两端都在圆心上方。
        assertTrue("起点应在圆顶附近", arrow.startY < path.centerY)
        assertTrue("终点应在圆顶附近", arrow.endY < path.centerY)
    }

    /** 南半球：start/end 关于竖轴镜像，且行进方向反过来（逆时针）。 */
    @Test
    fun motionArrowMirrorsInTheSouth() {
        val north = dial(6.0, 18.0, trueSolarHour = 12.0)
        val south = dialSouth(6.0, 18.0, trueSolarHour = 12.0)
        val n = SunPathGeometry.motionArrow(north, 12.0)
        val s = SunPathGeometry.motionArrow(south, 12.0)

        assertEquals("start 应关于竖轴镜像（x）", 2 * north.centerX - n.startX, s.startX, 0.5f)
        assertEquals("start 应关于竖轴镜像（y）", n.startY, s.startY, 0.5f)
        assertEquals("end 应关于竖轴镜像（x）", 2 * north.centerX - n.endX, s.endX, 0.5f)
        assertEquals("end 应关于竖轴镜像（y）", n.endY, s.endY, 0.5f)
        assertEquals("南半球应逆时针扫过 −30°", -30.0, arrowSweep(south, s), 0.1)
    }

    /** 弧在 0.72R 的内圆上、跨角恒定 30°、以太阳点角度为中心，且箭头尖离太阳点足够远。 */
    @Test
    fun motionArrowStaysOnTheInnerCircleAndClearOfTheSun() {
        val expectedRadiusRatio = SunPathGeometry.MOTION_ARROW_RADIUS_RATIO
        val expectedSpan = SunPathGeometry.MOTION_ARROW_SPAN_DEG.toDouble()
        val hours = listOf(0.0, 2.5, 6.0, 9.0, 12.0, 15.0, 18.0, 21.0, 23.5)
        for (hour in hours) {
            for (south in listOf(false, true)) {
                val path = if (south) {
                    dialSouth(6.0, 18.0, trueSolarHour = hour)
                } else {
                    dial(6.0, 18.0, trueSolarHour = hour)
                }
                val arrow = SunPathGeometry.motionArrow(path, hour)
                val expectedRadius = path.radius * expectedRadiusRatio
                val startDistance = kotlin.math.hypot(
                    (arrow.startX - path.centerX).toDouble(),
                    (arrow.startY - path.centerY).toDouble(),
                )
                val endDistance = kotlin.math.hypot(
                    (arrow.endX - path.centerX).toDouble(),
                    (arrow.endY - path.centerY).toDouble(),
                )
                assertEquals("$south $hour 起点半径", expectedRadius.toDouble(), startDistance, 0.5)
                assertEquals("$south $hour 终点半径", expectedRadius.toDouble(), endDistance, 0.5)

                // 两端夹角 = 30°。
                var span = kotlin.math.abs(arrowAngle(path, arrow.endX, arrow.endY) -
                    arrowAngle(path, arrow.startX, arrow.startY)) % 360.0
                if (span > 180.0) span = 360.0 - span
                assertEquals("$south $hour 跨角", expectedSpan, span, 0.1)

                // 弧以太阳点角度为中心：两端中点与圆心连线，角度应与太阳点一致。
                val midAngle = Math.toDegrees(
                    kotlin.math.atan2(
                        ((arrow.startY + arrow.endY) / 2f - path.centerY).toDouble(),
                        ((arrow.startX + arrow.endX) / 2f - path.centerX).toDouble(),
                    ),
                )
                val sunAngle = Math.toDegrees(
                    kotlin.math.atan2(
                        (path.sunY - path.centerY).toDouble(),
                        (path.sunX - path.centerX).toDouble(),
                    ),
                )
                var centerDelta = kotlin.math.abs(midAngle - sunAngle) % 360.0
                if (centerDelta > 180.0) centerDelta = 360.0 - centerDelta
                assertEquals("$south $hour 弧应以太阳点为中心", 0.0, centerDelta, 0.1)

                // 箭头尖离太阳点 > 6dp（太阳点在 R 上，柔光到 5.5dp 散尽，弧在 0.72R）。
                val sunDistance = kotlin.math.hypot(
                    (arrow.tipX - path.sunX).toDouble(),
                    (arrow.tipY - path.sunY).toDouble(),
                )
                assertTrue("$south $hour 箭头离太阳点太近：$sunDistance", sunDistance > 6.0)
            }
        }
    }

    // ---- 未知态（定位不可用）：昼夜各半的对半圆 ----

    /**
     * 未知态是**对半圆**：白天弧 180°（上半圈，从 9 点经 12 点到 3 点）、夜间弧 180°（下半圈），
     * 地平线正好从圆心穿过。
     */
    @Test
    fun unknownStateIsAnEvenDayNightCircle() {
        val path = SunPathGeometry.unknown(width, height)
        assertTrue("未知态必须打上 unknown 标记", path.unknown)
        assertFalse("未知态不是极昼", path.isPolarDay)
        assertFalse("未知态不是极夜", path.isPolarNight)
        assertFalse("整圆不是白天", path.isWholeCircleDay)
        assertFalse("整圆不是夜晚", path.isWholeCircleNight)

        // 地平线 = 圆心那条水平线（不能算成弦：弦两端就在圆的最左 / 最右）。
        assertEquals("地平线应过圆心", centerY, path.horizonY, 0.01f)
        assertEquals("地平线半弦 = 半径", radius, SunPathGeometry.horizonHalfChord(path), 0.5f)

        val span = SunPathGeometry.dayArcSpan(
            SunPathGeometry.UNKNOWN_SUNRISE_HOUR,
            SunPathGeometry.UNKNOWN_SUNSET_HOUR,
        )
        assertNotNull("未知态必须有白天弧（不是极昼极夜的整圆）", span)
        span!!
        assertEquals("白天弧 = 180°", 180f, span.sweepDegrees, 0.01f)
        assertEquals("夜间弧 = 180°", 180f, 360f - span.sweepDegrees, 0.01f)
        // drawArc 口径：−180° 是 9 点方向，顺时针扫 180° 经过 −90°（12 点）到 0°（3 点）—— 正是上半圈。
        assertEquals("白天弧从 9 点（−180°）起画", -180f, span.startDegrees, 0.01f)
        assertEquals("白天弧中点 = 圆顶（−90°）", -90f, span.startDegrees + span.sweepDegrees / 2f, 0.01f)
    }

    /** 未知态没有观测点：不画太阳点、不画运动箭头、不画日出/上中天/日落标签。 */
    @Test
    fun unknownStateDrawsNoSunDotNoArrowAndNoLabels() {
        val path = SunPathGeometry.unknown(width, height)
        assertFalse("未知态不画太阳点", path.showsSunDot)
        assertFalse("未知态不画运动箭头", path.showsMotionArrow)
        assertFalse("未知态不画时间标签", path.showsTimeLabels)
        assertFalse("未知态也没有上中天标签", path.hasTransitLabel)
    }

    /** 回归护栏：普通日、极昼、极夜该怎么画还怎么画（未知态那条分支不能漏进别的盘面）。 */
    @Test
    fun normalPolarAndUnknownKeepTheirOwnBranches() {
        val normal = dial(6.0, 18.0, trueSolarHour = 9.0)
        assertFalse(normal.unknown)
        assertTrue(normal.showsSunDot)
        assertTrue(normal.showsMotionArrow)
        assertTrue(normal.showsTimeLabels)
        assertTrue(normal.hasTransitLabel)

        val polarDay = SunPathGeometry.compute(
            width = width,
            height = height,
            sunriseHour = null,
            sunsetHour = null,
            trueSolarHour = 0.5,
            isPolarDay = true,
            isPolarNight = false,
        )
        assertTrue(polarDay.showsTimeLabels)
        assertTrue("极昼保留上中天标签", polarDay.hasTransitLabel)

        val polarNight = SunPathGeometry.compute(
            width = width,
            height = height,
            sunriseHour = null,
            sunsetHour = null,
            trueSolarHour = 12.0,
            isPolarDay = false,
            isPolarNight = true,
        )
        assertTrue(polarNight.showsSunDot)
        assertFalse("极夜仍不画上中天标签", polarNight.hasTransitLabel)
    }
}
