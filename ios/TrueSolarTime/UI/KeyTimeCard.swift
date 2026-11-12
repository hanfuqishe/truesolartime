import SwiftUI

/// 「关键时间」卡片：0–24 时的真太阳时时间轴，色带是「服用時間 Take Time」，
/// 白点标出当前时刻；下面列出各段与当前状态。与 Android 版小组件同一套规则：
/// 页面给的时间按真太阳时使用，不做时区或经度换算；Cold or Mild 用绿、Hot or Mild 用红。
struct KeyTimeCard: View {

    let schedule: TakeTimeSchedule?
    let trueSolarSeconds: Double

    private var currentBand: TakeBand? {
        schedule?.band(containing: trueSolarSeconds / 60.0)
    }

    private var accent: Color {
        guard let temperature = schedule?.temperature else { return .secondary }
        return temperature == .coldOrMild ? Color(red: 0.18, green: 0.49, blue: 0.20) : Color(red: 0.70, green: 0.15, blue: 0.12)
    }

    var body: some View {
        CardContainer {
            HStack {
                Text("关键时间")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let schedule, let temperature = schedule.temperature {
                    Text(temperature.label)
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(accent.opacity(0.16)))
                        .foregroundStyle(accent)
                }
            }

            AxisTimeline(bands: schedule?.bands ?? [], color: accent, position: trueSolarSeconds / 86_400)
                .frame(height: 18)
                .padding(.vertical, 6)

            HStack(spacing: 6) {
                Text("0")
                Spacer()
                Text("6")
                Spacer()
                Text("12")
                Spacer()
                Text("18")
                Spacer()
                Text("24")
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)

            if let schedule {
                if let band = currentBand {
                    Label {
                        Text("现在处于关键时间 \(band.text)")
                    } icon: {
                        Image(systemName: "bell.badge.fill")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(accent)
                    .padding(.top, 4)
                } else {
                    Text("当前不在关键时间段内")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }

                Text(schedule.bands.map(\.text).joined(separator: "　"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                Text("还没有取到关键时间（每天 01:00–05:00 自动同步一次，失败每小时重试）")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
    }
}

/// 0–24 时的时间轴：底色是轴线，色带是关键时间段，白点是当前真太阳时。
struct AxisTimeline: View {

    let bands: [TakeBand]
    let color: Color
    /// 当前时刻在一天里的位置，0…1。
    let position: Double

    var body: some View {
        Canvas { context, size in
            let midY = size.height / 2
            let track = CGRect(x: 0, y: midY - 1.5, width: size.width, height: 3)
            context.fill(Capsule().path(in: track), with: .color(.secondary.opacity(0.25)))

            for band in bands {
                let start = CGFloat(band.startMinute) / CGFloat(TakeBand.minutesPerDay) * size.width
                let width = max(
                    CGFloat(band.lengthMinutes) / CGFloat(TakeBand.minutesPerDay) * size.width,
                    3
                )
                let rect = CGRect(x: start, y: midY - 1.5, width: width, height: 3)
                context.fill(Capsule().path(in: rect), with: .color(color))
            }

            let clamped = min(max(position, 0), 1)
            let dot = CGRect(x: CGFloat(clamped) * size.width - 4.5, y: midY - 4.5, width: 9, height: 9)
            context.fill(Path(ellipseIn: dot), with: .color(.white))
            context.stroke(Path(ellipseIn: dot), with: .color(.black.opacity(0.18)), lineWidth: 0.5)
        }
    }
}
