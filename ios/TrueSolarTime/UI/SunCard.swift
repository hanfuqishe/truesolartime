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
            isPolarNight: snapshot.polar == .polarNight
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

/// 只负责画：外圆淡描边 + 白天弧实线 + 夜晚弧虚线 + 贯穿圆盘的地平线 + 日出日落刻度点 + 当前太阳点。
/// 文字不在这里画（`SunCard` 用真 `Text` 叠在上面），所以这里不需要任何标签尺寸假设。
///
/// 颜色一律取主题 token（`palette.primary` / `palette.onSurfaceVariant` / `palette.surface`），
/// 两套主题各用自己的一档，**不碰系统色**（系统 `.orange` / `.secondary` 在强制主题下会串色）。
private struct SunDialCanvas: View {

    @Environment(\.palette) private var palette

    let path: SunPath
    let sunriseHour: Double?
    let sunsetHour: Double?
    let isPolarDay: Bool
    let isPolarNight: Bool

    var body: some View {
        Canvas { context, size in
            drawCircleAndArcs(&context)
            drawHorizon(&context, size: size)
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

        // 两套主题各自的「白天 / 夜晚」两档：白天用主色（暖色），夜晚用次要文字色压暗压淡。
        let dayColor = palette.primary
        let nightColor = palette.onSurfaceVariant.opacity(0.5)
        let dayStyle = StrokeStyle(lineWidth: 2.5, lineCap: .round)
        let nightStyle = StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [5, 5])

        // 外圆：淡描边（同一个次要色 token 的 35%，亮暗两套都看得见但不抢戏）。
        context.stroke(circle, with: .color(palette.onSurfaceVariant.opacity(0.35)), lineWidth: 1)

        // 圆的分段：地平线以上 = 白天（实线、主色），以下 = 夜晚（虚线、低对比度）。
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
            context.stroke(
                arcPath(center: path.center, radius: path.radius, from: arc.start, to: arc.end),
                with: .color(dayColor),
                style: dayStyle
            )
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

    // MARK: 地平线

    /// 地平线：正常日是「弦 + 左右各伸 0.2R」，圆外那段压到 0.55 不透明度；
    /// 极昼 / 极夜 / 相切时没有有效的弦，就画满整条画布（左右各留 4pt）。
    private func drawHorizon(_ context: inout GraphicsContext, size: CGSize) {
        let startX = SunPathGeometry.horizonStartX(path: path, size: size)
        let endX = SunPathGeometry.horizonEndX(path: path, size: size)
        let color = palette.onSurfaceVariant
        let chord = SunPathGeometry.horizonChord(path: path)

        func strokeLine(from: CGFloat, to: CGFloat, opacity: Double) {
            guard to > from + 0.5 else { return }
            var line = Path()
            line.move(to: CGPoint(x: from, y: path.horizonY))
            line.addLine(to: CGPoint(x: to, y: path.horizonY))
            // 比白天弧细：1pt。
            context.stroke(line, with: .color(color.opacity(opacity)), lineWidth: 1)
        }

        if let chord, chord.end.x > chord.start.x + 1 {
            strokeLine(from: startX, to: chord.start.x, opacity: 0.55)
            strokeLine(from: chord.start.x, to: chord.end.x, opacity: 1.0)
            strokeLine(from: chord.end.x, to: endX, opacity: 0.55)

            // 交点就是日出 / 日落（各画一个小刻度点）。
            let dayColor = palette.primary
            for point in [chord.start, chord.end] {
                let dot = CGRect(x: point.x - 2.5, y: point.y - 2.5, width: 5, height: 5)
                context.fill(Path(ellipseIn: dot), with: .color(dayColor))
            }
        } else {
            // 极昼 / 极夜 / 相切：一条贯穿画布的线；相切时那一点正好落在圆底，补一个刻度点。
            strokeLine(from: startX, to: endX, opacity: 1.0)
            if let chord {
                let dayColor = palette.primary
                let dot = CGRect(x: chord.start.x - 2.5, y: chord.start.y - 2.5, width: 5, height: 5)
                context.fill(Path(ellipseIn: dot), with: .color(dayColor))
            }
        }
    }

    // MARK: 当前太阳点

    private func drawSun(_ context: inout GraphicsContext) {
        let sun = path.sunPoint
        let dayColor = palette.primary
        let glow = SunPathGeometry.sunGlowRadius
        let dot = SunPathGeometry.sunRadius

        if SunPathGeometry.isSunAboveHorizon(path: path) {
            // 地平线以上：亮色实心 + 柔光（1.5 × 半径，避免糊到上中天标签）。
            context.fill(
                Path(ellipseIn: CGRect(
                    x: sun.x - glow,
                    y: sun.y - glow,
                    width: glow * 2,
                    height: glow * 2
                )),
                with: .color(dayColor.opacity(0.18))
            )
            context.fill(
                Path(ellipseIn: CGRect(
                    x: sun.x - dot,
                    y: sun.y - dot,
                    width: dot * 2,
                    height: dot * 2
                )),
                with: .color(dayColor)
            )
        } else {
            // 地平线以下：暗色空心（先用卡片底色挖空，虚线和外圆才不会穿过那个空心点）。
            let rect = CGRect(x: sun.x - dot, y: sun.y - dot, width: dot * 2, height: dot * 2)
            context.fill(Path(ellipseIn: rect), with: .color(palette.surface))
            context.stroke(Path(ellipseIn: rect), with: .color(palette.onSurfaceVariant), lineWidth: 1.5)
        }
    }

    /// 沿圆盘采样一段弧（θ，弧度）。
    ///
    /// 不用 `Path.addArc`：SwiftUI / CoreGraphics 对 `clockwise` 的约定正好相反，
    /// 而采样既没有歧义，又能让弧的两端精确落在日出 / 日落与地平线的交点上。
    private func arcPath(center: CGPoint, radius: CGFloat, from start: Double, to end: Double) -> Path {
        var path = Path()
        let span = end - start
        // 每 1° 一段：200pt 的圆盘上弦高误差 < 0.02pt，肉眼无差别。
        let steps = max(Int((abs(span) / (Double.pi / 180.0)).rounded()), 2)
        for step in 0...steps {
            let theta = start + span * Double(step) / Double(steps)
            let point = CGPoint(
                x: center.x + radius * CGFloat(sin(theta)),
                y: center.y - radius * CGFloat(cos(theta))
            )
            if step == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }
}

// MARK: - 卡宽测量

private struct SunCardWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
