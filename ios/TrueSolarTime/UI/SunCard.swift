import SwiftUI

struct SunCard: View {

    let snapshot: SolarSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("太阳位置 · 北京时间")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "高度角 %.1f°", snapshot.altitudeDegrees))
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
            }

            SunArc(progress: daylightProgress, isDay: snapshot.isDay)
                .frame(height: 110)
                .padding(.vertical, 10)

            if snapshot.polar == .normal {
                HStack {
                    SunTimeItem(label: "日出", time: snapshot.sunriseBeijing)
                    SunTimeItem(label: "上中天", time: snapshot.solarNoonBeijing)
                    SunTimeItem(label: "日落", time: snapshot.sunsetBeijing)
                }

                Text("白昼 \(TimeFormat.duration(snapshot.daylightSeconds))　真太阳时 日出 \(TimeFormat.clock(snapshot.sunriseTrueSolar)) 日落 \(TimeFormat.clock(snapshot.sunsetTrueSolar))")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)
            } else {
                Text(
                    snapshot.polar == .midnightSun
                        ? "极昼：太阳整日不落，上中天（当地标准时间）\(TimeFormat.clock(snapshot.solarNoonBeijing))"
                        : "极夜：太阳整日不出，上中天（当地标准时间）\(TimeFormat.clock(snapshot.solarNoonBeijing))"
                )
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }
        }
        .cardBackground()
    }

    private var daylightProgress: Double {
        guard let sunrise = snapshot.sunriseTrueSolar, let sunset = snapshot.sunsetTrueSolar else { return 0.5 }
        var start = Double(sunrise.secondsOfDay)
        var end = Double(sunset.secondsOfDay)
        if end <= start { end += 86_400 }
        var current = Double(snapshot.trueSolarTime.secondsOfDay)
        if current < start { current += 86_400 }
        return min(max((current - start) / (end - start), 0), 1)
    }
}

private struct SunTimeItem: View {

    let label: String
    let time: TimeOfDay?

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(TimeFormat.clock(time))
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }
}

private struct SunArc: View {

    let progress: Double
    let isDay: Bool

    var body: some View {
        Canvas { context, size in
            let horizonY = size.height * 0.88
            let start = CGPoint(x: size.width * 0.06, y: horizonY)
            let end = CGPoint(x: size.width * 0.94, y: horizonY)
            let control = CGPoint(x: size.width / 2, y: -size.height * 0.42)

            var arc = Path()
            arc.move(to: start)
            arc.addQuadCurve(to: end, control: control)
            context.stroke(
                arc,
                with: .color(.secondary.opacity(0.35)),
                style: StrokeStyle(lineWidth: 2, dash: [6, 6])
            )

            var horizon = Path()
            horizon.move(to: CGPoint(x: 0, y: horizonY))
            horizon.addLine(to: CGPoint(x: size.width, y: horizonY))
            context.stroke(horizon, with: .color(.secondary.opacity(0.35)), lineWidth: 2)

            let t = min(max(progress, 0), 1)
            let u = 1 - t
            let sunX = u * u * start.x + 2 * u * t * control.x + t * t * end.x
            let sunY = u * u * start.y + 2 * u * t * control.y + t * t * end.y
            let center = CGPoint(x: sunX, y: sunY)

            let color: Color = isDay ? Color(red: 1.0, green: 0.70, blue: 0.0) : .secondary
            if isDay {
                context.fill(Path(ellipseIn: CGRect(x: center.x - 18, y: center.y - 18, width: 36, height: 36)),
                             with: .color(color.opacity(0.18)))
            }
            context.fill(Path(ellipseIn: CGRect(x: center.x - 7, y: center.y - 7, width: 14, height: 14)),
                         with: .color(color))
        }
    }
}
