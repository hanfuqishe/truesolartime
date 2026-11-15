import SwiftUI

struct SunCard: View {

    @Environment(\.palette) private var palette

    let snapshot: SolarSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L("sun.title"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.onSurfaceVariant)
                Spacer()
                Text(Lf("sun.altitude", snapshot.altitudeDegrees))
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
            }

            SunArc(progress: daylightProgress, isDay: snapshot.isDay)
                .frame(height: 110)
                .padding(.vertical, 10)

            if snapshot.polar == .normal {
                HStack {
                    SunTimeItem(label: L("sun.sunrise"), time: snapshot.sunriseBeijing)
                    SunTimeItem(label: L("sun.noon"), time: snapshot.solarNoonBeijing)
                    SunTimeItem(label: L("sun.sunset"), time: snapshot.sunsetBeijing)
                }

                Text(Lf(
                    "sun.daylight",
                    TimeFormat.duration(snapshot.daylightSeconds),
                    TimeFormat.clock(snapshot.sunriseTrueSolar),
                    TimeFormat.clock(snapshot.sunsetTrueSolar)
                ))
                .font(.system(size: 12))
                .foregroundStyle(palette.onSurfaceVariant)
                .padding(.top, 10)
            } else {
                Text(
                    snapshot.polar == .midnightSun
                        ? Lf("sun.polarDay", TimeFormat.clock(snapshot.solarNoonBeijing))
                        : Lf("sun.polarNight", TimeFormat.clock(snapshot.solarNoonBeijing))
                )
                .font(.system(size: 12))
                .foregroundStyle(palette.onSurfaceVariant)
            }
        }
        .foregroundStyle(palette.onSurface)
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

    @Environment(\.palette) private var palette

    let label: String
    let time: TimeOfDay?

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(palette.onSurfaceVariant)
            Text(TimeFormat.clock(time))
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }
}

private struct SunArc: View {

    @Environment(\.palette) private var palette

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
                with: .color(palette.outlineVariant),
                style: StrokeStyle(lineWidth: 2, dash: [6, 6])
            )

            var horizon = Path()
            horizon.move(to: CGPoint(x: 0, y: horizonY))
            horizon.addLine(to: CGPoint(x: size.width, y: horizonY))
            context.stroke(horizon, with: .color(palette.outlineVariant), lineWidth: 2)

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
