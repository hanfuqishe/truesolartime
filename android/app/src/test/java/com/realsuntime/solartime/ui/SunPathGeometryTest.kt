package com.realsuntime.solartime.ui

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.min
import kotlin.math.sin
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
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

    /** 地平线这条弦的两端正好落在日出 / 日落刻度上。 */
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

    /** 白天弧的扫角 = 昼长占 24h 的比例；从日出刻度顺时针经过 12:00 扫到日落刻度。 */
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

    private fun dial(
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

    /** 地平线要比圆宽（弦 + 两侧各 0.2R = 2.4R），两端留在画布内；极昼极夜没有弦就画满画布。 */
    @Test
    fun horizonSpansWiderThanTheCircle() {
        val path = dial(6.0, 18.0)
        val span = SunPathGeometry.horizonSpan(path, dialWidth, sideInset)
        assertTrue(
            "地平线要比圆宽：${span.length} vs ${2 * path.radius}",
            span.length > 2 * path.radius,
        )
        assertEquals(path.centerX - path.radius * (1f + SunPathGeometry.HORIZON_EXTENSION_RATIO), span.startX, 0.5f)
        assertEquals(path.centerX + path.radius * (1f + SunPathGeometry.HORIZON_EXTENSION_RATIO), span.endX, 0.5f)
        assertTrue("左端要在画布内", span.startX >= sideInset - 0.5f)
        assertTrue("右端要在画布内", span.endX <= dialWidth - sideInset + 0.5f)

        // 窄画布：延伸被夹到边距以内，不会画出卡片。
        val narrow = SunPathGeometry.compute(160f, 194f, 6.0, 18.0, 12.0, false, false)
        val narrowSpan = SunPathGeometry.horizonSpan(narrow, 160f, sideInset)
        assertTrue(narrowSpan.startX >= sideInset - 0.5f)
        assertTrue(narrowSpan.endX <= 160f - sideInset + 0.5f)

        // 极昼 / 极夜：地平线整个在圆外，没有弦，直接画满画布（左右各留 sideInset）。
        for ((name, polarDay, polarNight) in listOf(Triple("极昼", true, false), Triple("极夜", false, true))) {
            val polarPath = dial(null, null, isPolarDay = polarDay, isPolarNight = polarNight)
            val polarSpan = SunPathGeometry.horizonSpan(polarPath, dialWidth, sideInset)
            assertEquals("$name 地平线应从画布左边起画", sideInset, polarSpan.startX, 0.5f)
            assertEquals("$name 地平线应画到画布右边", dialWidth - sideInset, polarSpan.endX, 0.5f)
            assertTrue("$name 地平线仍在画布内", polarSpan.endX <= dialWidth - sideInset + 0.5f)
        }
    }
}
