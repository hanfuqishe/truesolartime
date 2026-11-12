import SwiftUI

struct HeroCard: View {

    let snapshot: SolarSnapshot
    let placeLabel: String
    let districtName: DistrictNames?
    let trackingGps: Bool
    let waitingForFix: Bool

    /// 名字太长就退到「只有区县」，否则胶囊会被截成看不出位置的样子。
    private var statusLabel: String {
        if waitingForFix { return "定位中…" }
        if let districtName {
            return districtName.full.count <= 12 ? districtName.full : districtName.short
        }
        return placeLabel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(trackingGps ? "当地真太阳时 · 每分钟更新" : "当地真太阳时")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer(minLength: 8)
                Text(statusLabel)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(.white.opacity(0.18)))
            }

            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(String(format: "%02d:%02d", snapshot.trueSolarTime.hour, snapshot.trueSolarTime.minute))
                    .font(.system(size: 72, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text(":" + String(format: "%02d", snapshot.trueSolarTime.second))
                    .font(.system(size: 26, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.bottom, 12)
            }

            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(.white.opacity(0.18)).frame(width: 54, height: 54)
                    Text(String(snapshot.shichenName.prefix(1)))
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(snapshot.shichenName) · \(snapshot.shichenHalf)\(chineseNumber(snapshot.shichenQuarter))刻")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("\(snapshot.shichenRange)　距\(snapshot.nextShichenName) \(TimeFormat.countdown(snapshot.secondsToNextShichen))")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.8))
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 16)
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: Theme.heroCornerRadius, style: .continuous)
                .fill(snapshot.isDay ? Theme.dayGradient : Theme.nightGradient)
        )
    }
}

struct BeijingCard: View {

    let snapshot: SolarSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("北京时间")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(snapshot.beijingDateText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Text(snapshot.beijingTime.clockWithSeconds)
                .font(.system(size: 34, weight: .medium, design: .rounded))
                .monospacedDigit()
                .padding(.top, 2)

            Divider().padding(.vertical, 12)

            Text("真太阳时比北京时间\(snapshot.offsetSeconds >= 0 ? "快" : "慢") \(TimeFormat.minutesSeconds(snapshot.offsetSeconds))")
                .font(.system(size: 15))

            Text("经度修正 \(TimeFormat.signedDuration(seconds: snapshot.longitudeOffsetSeconds))　均时差 \(TimeFormat.signedDuration(seconds: snapshot.equationOfTimeSeconds))")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .cardBackground()
    }
}
