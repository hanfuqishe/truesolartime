import SwiftUI
import UIKit

/// 太阳卡：**内容宽 × 194 的时间圆盘**，四个时间标签直接标在圆上（与安卓 v2 同一套版式）。
///
/// 圆盘的轴线是**当地真太阳时**（不是标准时间，也与时区无关）：
/// 整圆 = 一天 24 小时，12:00 正上方、00:00 正下方；地平线是一条水平弦，高度由日出时刻决定
/// （昼长 12h 过圆心、>12h 下移、<12h 上移；极昼沉到圆下方、极夜升到圆上方；
/// 日出恰好 0:00 时与圆相切于最下方）。几何与四个标签的**锚点**全部在
/// `Core/SunPathGeometry.swift`，那边有纯数值自检（六种场景 + 防重叠 + 不越界）。
///
/// 标签是**真正的 `Text`**（自然宽度、不会被截断），按锚点 + 对齐方式贴上去：
/// - 日出：右对齐，锚在左交点左侧 10pt；日落：左对齐，锚在右交点右侧 10pt；两者都比交点抬高 10pt，
///   于是伸出圆外的那段地平线正好从字下面过去；
/// - 上中天：圆顶上方居中，底边离圆顶 8pt；白昼时长：画布下方居中一行（间隔 4pt）；
/// - 极昼：整圆白天 + **保留**上中天 + 圆心「极昼」；极夜：**没有**上中天，只有圆心「极夜」；
/// - 短昼（昼长 ≤ 2 小时）：两块标签改放到圆顶下方一行，左右仍各离圆 10pt。
struct SunCard: View {

    @Environment(\.palette) private var palette

    let snapshot: SolarSnapshot

    /// 卡片实测宽度：圆盘宽度 = 卡片内容宽（卡宽 − 左右内边距），只有量到真实卡宽才能定。
    /// 首帧先用「屏宽 − 页面左右内边距」兜底，避免第一帧按 0 算出极小的圆盘、下一帧再跳大。
    @State private var cardWidth: CGFloat = UIScreen.main.bounds.width - 40

    /// 必须和 `Theme.swift` 里 `CardBackground` 的 `.padding(20)` 一致（圆盘内容宽 = 卡宽 − 2×20）。
    private let cardPadding: CGFloat = 20
    /// 圆盘画布高度：固定 194pt（安卓同款），半径因此 = 0.38 × 194 ≈ 73.7。
    private let dialHeight: CGFloat = 194

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            dial
                .padding(.top, 12)
            footer
                .padding(.top, 4)
        }
        .foregroundStyle(palette.onSurface)
        .cardBackground()
        // 卡宽在 `.cardBackground()` 之后量（那时 `maxWidth: .infinity` 已经展开），读到的是整张卡的宽度。
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: SunCardWidthKey.self, value: proxy.size.width)
            }
        )
        .onPreferenceChange(SunCardWidthKey.self) { width in
            if width > 0, abs(width - cardWidth) > 0.5 {
                cardWidth = width
            }
        }
    }

    // MARK: - 顶部

    private var header: some View {
        HStack {
            Text(L("sun.title"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(palette.onSurfaceVariant)
            Spacer(minLength: 8)
            Text(Lf("sun.altitude", snapshot.altitudeDegrees))
                .font(.system(size: 12))
                // 与 Android 一致用主题 primary（系统 `.orange` 在浅色卡片上只有 2.2:1，读不清）。
                .foregroundStyle(palette.primary)
        }
    }

    // MARK: - 圆盘（画布 + 真 Text 标签）

    private var dialSize: CGSize {
        CGSize(width: max(cardWidth - cardPadding * 2, 200), height: dialHeight)
    }

    private var dialPath: SunPath {
        SunPathGeometry.compute(
            size: dialSize,
            sunriseHour: sunriseTrueSolarHour,
            sunsetHour: sunsetTrueSolarHour,
            trueSolarHour: trueSolarHour,
            isPolarDay: snapshot.polar == .midnightSun,
            isPolarNight: snapshot.polar == .polarNight,
            // 南半球观察者面朝北：东在右、西在左，太阳从右往左走（逆时针），
            // 日出 / 日落标签也跟着换边。
            southernHemisphere: snapshot.latitude < 0
        )
    }

    private var dialLabels: SunPathLabels {
        SunPathGeometry.labels(
            path: dialPath,
            size: dialSize,
            dayLengthHours: snapshot.daylightSeconds.map { Double($0) / 3600.0 }
        )
    }

    private var dial: some View {
        ZStack {
            SunDialCanvas(
                path: dialPath,
                sunriseHour: sunriseTrueSolarHour,
                sunsetHour: sunsetTrueSolarHour,
                trueSolarHour: trueSolarHour,
                isPolarDay: snapshot.polar == .midnightSun,
                isPolarNight: snapshot.polar == .polarNight
            )
            labels
        }
        .frame(width: dialSize.width, height: dialSize.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(dialAccessibilityLabel)
    }

    /// 四个标签：真正的 `Text`，按 Core 给的锚点 + 对齐方式贴上去（宽度自然，不截断）。
    @ViewBuilder private var labels: some View {
        if let sunrise = dialLabels.sunrise {
            anchored(
                Text(L("sun.sunrise"))
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(palette.onSurfaceVariant)
                    + Text(" " + TimeFormat.clock(snapshot.sunriseBeijing))
                    .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundColor(palette.onSurface),
                at: sunrise.point,
                alignment: .trailing
            )
        }
        if let sunset = dialLabels.sunset {
            anchored(
                Text(L("sun.sunset"))
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(palette.onSurfaceVariant)
                    + Text(" " + TimeFormat.clock(snapshot.sunsetBeijing))
                    .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundColor(palette.onSurface),
                at: sunset.point,
                alignment: .leading
            )
        }
        if let noon = dialLabels.noon {
            anchored(
                Text(L("sun.noon"))
                    .font(.system(size: 9))
                    .foregroundColor(palette.onSurfaceVariant)
                    + Text(" " + TimeFormat.clock(snapshot.solarNoonBeijing))
                    .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundColor(palette.onSurface),
                at: noon.point,
                alignment: .bottom
            )
        }
        if let polar = dialLabels.polar {
            anchored(
                Text(polarText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(palette.onSurface),
                at: polar.point,
                alignment: .center
            )
        }
    }

    /// 把一段文字按「锚点 + 对齐」放到圆盘上。
    ///
    /// 用 0×0 的 frame 承载文字：`frame(width: 0, height: 0, alignment: .trailing)` 会让文字
    /// 以**右边界**贴住这个 0×0 框，`.position` 再把该框的中心放到锚点上 —— 于是文字右边界正好落在锚点、
    /// 垂直居中；`.fixedSize()` 保证文字按自然宽度排版，不会被压缩或截断。
    private func anchored(_ text: Text, at point: CGPoint, alignment: Alignment) -> some View {
        text
            .fixedSize()
            .frame(width: 0, height: 0, alignment: alignment)
            .position(x: point.x, y: point.y)
    }

    // MARK: - 圆盘下方一行

    /// 正常日：白昼时长；极昼 / 极夜：24 小时 / 0 小时（圆心那一行的「极昼 / 极夜」由 `labels` 画）。
    private var footer: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            Text(L("sun.daylightLength"))
                .font(.system(size: 9))
                .foregroundColor(palette.onSurfaceVariant)
                + Text(" " + footerValue)
                .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundColor(palette.onSurface)
            Spacer(minLength: 0)
        }
    }

    /// 白昼时长；极昼 24 小时、极夜 0 小时（`SolarSnapshot.daylightSeconds` 在极区是 nil）。
    private var footerValue: String {
        switch snapshot.polar {
        case .normal:
            return TimeFormat.duration(snapshot.daylightSeconds)
        case .midnightSun:
            return TimeFormat.duration(86_400)
        case .polarNight:
            return TimeFormat.duration(0)
        }
    }

    private var polarText: String {
        snapshot.polar == .midnightSun ? L("sun.polarDayShort") : L("sun.polarNightShort")
    }

    /// 圆盘整体给读屏用的一句话（画布里的图形读不出来，这里补一份）。
    private var dialAccessibilityLabel: String {
        var parts: [String] = []
        if snapshot.polar == .normal {
            parts.append("\(L("sun.sunrise")) \(TimeFormat.clock(snapshot.sunriseBeijing))")
            parts.append("\(L("sun.sunset")) \(TimeFormat.clock(snapshot.sunsetBeijing))")
        }
        parts.append("\(L("sun.noon")) \(TimeFormat.clock(snapshot.solarNoonBeijing))")
        if snapshot.polar != .normal {
            parts.append(polarText)
        }
        parts.append(L("sun.daylightLength") + " " + footerValue)
        return parts.joined(separator: " · ")
    }

    // MARK: - 真太阳时的小时数（圆盘的唯一输入）

    private var sunriseTrueSolarHour: Double? {
        snapshot.sunriseTrueSolar.map { Double($0.secondsOfDay) / 3600.0 }
    }

    private var sunsetTrueSolarHour: Double? {
        snapshot.sunsetTrueSolar.map { Double($0.secondsOfDay) / 3600.0 }
    }

    private var trueSolarHour: Double {
        Double(snapshot.trueSolarTime.secondsOfDay) / 3600.0
    }
}

// MARK: - 圆盘（纯绘制）

/// 只负责画：白天弧实线 + 夜晚弧虚线（圆盘边界只有这两段，没有额外的「表圈」）+
/// 贯穿圆盘的地平线 + 当前太阳点（**不画**日出/日落刻度点：弧端外扩 0.8° 盖住交点）。
/// 文字不在这里画（`SunCard` 用真 `Text` 叠在上面），所以这里不需要任何标签尺寸假设。
///
/// 颜色一律取主题 token（`palette.sunArc` / `palette.sunDot` / `palette.primary` /
/// `palette.onSurfaceVariant` / `palette.surface`），两套主题各用自己的一档，**不碰系统色**
/// （系统 `.orange` / `.secondary` 在强制主题下会串色）。
/// 弧与点各单独一档：白天弧淡金细线（只作路径示意）、太阳点是**纯色核心 + 独立光晕**
/// （尺寸与时间轴「现在」圆点一致：核心 5.5pt、外沿 7.5pt）；地平线 / 箭头仍是灰。
private struct SunDialCanvas: View {

    @Environment(\.palette) private var palette

    let path: SunPath
    let sunriseHour: Double?
    let sunsetHour: Double?
    /// 当前真太阳时（小时数）：圆内侧那支「运动方向」小箭头用它定位。
    let trueSolarHour: Double
    let isPolarDay: Bool
    let isPolarNight: Bool

    var body: some View {
        Canvas { context, size in
            drawCircleAndArcs(&context)
            drawHorizon(&context, size: size)
            drawMotionArrow(&context)
            drawSun(&context)
        }
    }

    // MARK: 圆与弧

    private func drawCircleAndArcs(_ context: inout GraphicsContext) {
        let circle = Path(ellipseIn: CGRect(
            x: path.center.x - path.radius,
            y: path.center.y - path.radius,
            width: path.radius * 2,
            height: path.radius * 2
        ))

        // 两套主题各自的「白天 / 夜晚」两档：白天用**白天弧专用色**（淡金，只是路径示意），
        // 夜晚用次要文字色压暗压淡。线宽都很细：白天 1.6pt、夜晚 1.5pt（虚线 4/4），
        // 地平线与箭头保持原样（1pt / 1.5pt）。
        let dayColor = palette.sunArc
        let nightColor = palette.onSurfaceVariant.opacity(0.5)
        let dayStyle = StrokeStyle(
            lineWidth: SunPathGeometry.dayArcLineWidth,
            lineCap: .round
        )
        let nightStyle = StrokeStyle(
            lineWidth: SunPathGeometry.nightArcLineWidth,
            lineCap: .round,
            dash: SunPathGeometry.nightArcDash
        )

        // 圆的分段：地平线以上 = 白天（实线、`sunArc`），以下 = 夜晚（虚线、低对比度）。
        // 圆盘边界只由这两段弧构成 —— 不再额外描一圈「表圈」。
        if isPolarNight {
            context.stroke(circle, with: .color(nightColor), style: nightStyle)
        } else if isPolarDay {
            context.stroke(circle, with: .color(dayColor), style: dayStyle)
        } else if let arc = SunPathGeometry.dayArcAngles(
            sunriseHour: sunriseHour,
            sunsetHour: sunsetHour,
            isPolarDay: isPolarDay,
            isPolarNight: isPolarNight
        ) {
            // 白天弧两端各外扩 0.8°（Core 里算好）：弧端略穿过地平线，
            // 交点因此被弧「盖住」—— 圆盘上不再画日出 / 日落刻度点。
            context.stroke(
                arcPath(center: path.center, radius: path.radius, from: arc.start, to: arc.end),
                with: .color(dayColor),
                style: dayStyle
            )
            // 夜间虚线从**外扩后的终点**接上；扫角为 0（整圆都是白天）时不画。
            let nightSweep = 2.0 * Double.pi - (arc.end - arc.start)
            if nightSweep > 1e-9 {
                context.stroke(
                    arcPath(
                        center: path.center,
                        radius: path.radius,
                        from: arc.end,
                        to: arc.start + 2.0 * Double.pi
                    ),
                    with: .color(nightColor),
                    style: nightStyle
                )
            }
        }
    }

    // MARK: 地平线

    /// 地平线：**一条贯穿画布的横线**，长度固定为「画布宽 − 左右各 4pt」（与安卓一致）。
    ///
    /// 所有场景（普通日 / 短昼 / 极昼 / 极夜 / 相切）一样长、一样颜色、一样不透明度，
    /// 不再按弦长延伸、也不分圆内 / 圆外两段。**不画日出 / 日落刻度点**（与安卓一致）：
    /// 白天弧两端各外扩 0.8°，交点已经被弧端盖住了。
    private func drawHorizon(_ context: inout GraphicsContext, size: CGSize) {
        let startX = SunPathGeometry.horizonStartX(size: size)
        let endX = SunPathGeometry.horizonEndX(size: size)

        var line = Path()
        line.move(to: CGPoint(x: startX, y: path.horizonY))
        line.addLine(to: CGPoint(x: endX, y: path.horizonY))
        // 比白天弧（1.6pt）细：1pt；单色单不透明度。
        // 用 `onSurfaceVariant` 而不是 `outlineVariant`：后者在夜间主题是 #24304F，对卡片只有 1.26:1，
        // 等于看不见（夜间可见性是硬要求）；这一档白天 2.6:1、夜间 3.6:1，两套都读得出来。
        context.stroke(
            line,
            with: .color(palette.onSurfaceVariant.opacity(0.7)),
            lineWidth: 1
        )
    }

    // MARK: 运动方向小弧

    /// 圆内侧一段 30° 小弧 + 末端实心箭头：告诉用户太阳往哪走。
    ///
    /// 半径 0.72R（离太阳点 0.28R ≈ 20pt，不会和太阳点 / 柔光打架），颜色与地平线同源
    /// （`onSurfaceVariant`，不抢白天弧的主色）；北半球顺时针、南半球逆时针，由 `SunPath` 的半球决定。
    private func drawMotionArrow(_ context: inout GraphicsContext) {
        let arrow = SunPathGeometry.motionArrow(path: path, currentTrueSolarHour: trueSolarHour)
        let angles = SunPathGeometry.motionArrowAngles(currentTrueSolarHour: trueSolarHour)
        let radius = path.radius * 0.72
        let color = palette.onSurfaceVariant.opacity(0.7)

        // 弧：从 start 采到 end（θ 递增 = 运动方向）。
        var arc = Path()
        let steps = 18
        for step in 0...steps {
            let theta = angles.start + (angles.end - angles.start) * Double(step) / Double(steps)
            let point = SunPathGeometry.point(
                center: path.center,
                radius: radius,
                theta: theta,
                southernHemisphere: path.isSouthernHemisphere
            )
            if step == 0 {
                arc.move(to: point)
            } else {
                arc.addLine(to: point)
            }
        }
        context.stroke(
            arc,
            with: .color(color),
            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
        )

        // 箭头：终点处的切线方向（对 θ 求导，南北半球符号不同），两条边再合成实心三角。
        let cosEnd = cos(angles.end)
        let sinEnd = sin(angles.end)
        let ux = path.isSouthernHemisphere ? -cosEnd : cosEnd
        let uy = sinEnd
        let barb: CGFloat = 5
        let spread = 25.0 * Double.pi / 180.0
        func barbPoint(_ sign: Double) -> CGPoint {
            let cosA = cos(spread * sign)
            let sinA = sin(spread * sign)
            // 沿切线反向、再旋转 ±25°，退 5pt。
            let bx = -(ux * cosA - uy * sinA)
            let by = -(ux * sinA + uy * cosA)
            return CGPoint(x: arrow.tip.x + CGFloat(bx) * barb, y: arrow.tip.y + CGFloat(by) * barb)
        }
        var head = Path()
        head.move(to: arrow.tip)
        head.addLine(to: barbPoint(1))
        head.addLine(to: barbPoint(-1))
        head.closeSubpath()
        context.fill(head, with: .color(color))
    }

    // MARK: 当前太阳点

    private func drawSun(_ context: inout GraphicsContext) {
        let sun = path.sunPoint
        // **纯色核心 + 独立光晕**（尺寸与时间轴那个点一致，画法各自适合各自底色）：
        //   ① 光晕（先画，在核心后面）：从**核心半径** 5.5pt 到 7.5pt 的径向渐变，alpha 0.35 → 0；
        //   ② 核心（后画）：5.5pt 纯色实心，alpha 1.0 —— 不用渐变，边界干净。
        // 时间轴的点是「实心 + 0.28 平铺柔光」两笔（`NowDotStyle`）；这里只共用**尺寸**
        // （核心半径、整体外沿），光晕用渐变收边：亮金画在米白卡上，平铺柔光会散成光斑。
        // 地平线、箭头仍用次要色（灰），不跟着变。
        let halo = SunHaloStyle.shared
        let core = SunPathGeometry.sunRadius
        let coreRect = CGRect(x: sun.x - core, y: sun.y - core, width: core * 2, height: core * 2)

        if SunPathGeometry.isSunAboveHorizon(path: path) {
            let haloRect = CGRect(
                x: sun.x - halo.endRadius,
                y: sun.y - halo.endRadius,
                width: halo.endRadius * 2,
                height: halo.endRadius * 2
            )
            let stops = halo.stops.map { stop in
                Gradient.Stop(
                    color: palette.sunDot.opacity(stop.alpha),
                    location: CGFloat(stop.location)
                )
            }
            context.fill(
                Path(ellipseIn: haloRect),
                with: .radialGradient(
                    Gradient(stops: stops),
                    center: sun,
                    // 从**核心半径**起步（不是 0）：光晕只出现在核心外面，核心本身不被冲淡。
                    startRadius: halo.startRadius,
                    endRadius: halo.endRadius
                )
            )
            context.fill(Path(ellipseIn: coreRect), with: .color(palette.sunDot))
        } else {
            // 地平线以下：同尺寸的空心圈（半径 = 核心半径，细描边 1pt），不画光、也不留粗硬边。
            let hollow = SunPathGeometry.sunHollowRadius
            let hollowRect = CGRect(x: sun.x - hollow, y: sun.y - hollow, width: hollow * 2, height: hollow * 2)
            context.fill(Path(ellipseIn: hollowRect), with: .color(palette.surface))
            context.stroke(
                Path(ellipseIn: hollowRect),
                with: .color(palette.onSurfaceVariant),
                lineWidth: SunPathGeometry.sunHollowLineWidth
            )
        }
    }

    /// 沿圆盘采样一段弧（θ，弧度）。
    ///
    /// 不用 `Path.addArc`：SwiftUI / CoreGraphics 对 `clockwise` 的约定正好相反，
    /// 而采样既没有歧义，又能让弧的两端精确落在日出 / 日落与地平线的交点上。
    /// 采样点统一走 `SunPathGeometry.point`，南半球的 x 镜像才不会漏掉。
    private func arcPath(center: CGPoint, radius: CGFloat, from start: Double, to end: Double) -> Path {
        var arc = Path()
        let span = end - start
        // 每 1° 一段：200pt 的圆盘上弦高误差 < 0.02pt，肉眼无差别。
        let steps = max(Int((abs(span) / (Double.pi / 180.0)).rounded()), 2)
        for step in 0...steps {
            let theta = start + span * Double(step) / Double(steps)
            // 采样点统一走 `SunPathGeometry.point`，南半球的 x 镜像才不会漏掉。
            let point = SunPathGeometry.point(
                center: center,
                radius: radius,
                theta: theta,
                southernHemisphere: self.path.isSouthernHemisphere
            )
            if step == 0 {
                arc.move(to: point)
            } else {
                arc.addLine(to: point)
            }
        }
        return arc
    }
}

// MARK: - 卡宽测量

private struct SunCardWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
