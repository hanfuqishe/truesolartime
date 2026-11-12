import SwiftUI

/// 天气卡片：今天的最低/最高气温 + 当前天气 + 未来 5 小时。
/// 数据来自 Open-Meteo（与 Android 版同一接口、同一缓存策略）。
struct WeatherCard: View {

    let weather: WeatherSnapshot?
    let isDay: Bool
    let waitingForGPS: Bool

    private let hoursToShow = 5

    var body: some View {
        CardContainer {
            HStack {
                Text("天气")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let weather, let range = todayRange(weather) {
                    Text("\(range.low)° ~ \(range.high)°")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            if let weather {
                HStack(spacing: 10) {
                    Image(systemName: weather.condition.symbol(isDay: isDay))
                        .font(.system(size: 34))
                        .symbolRenderingMode(.multicolor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(weather.temperatureC)°")
                            .font(.system(size: 34, weight: .light))
                            .monospacedDigit()
                        Text(weather.condition.label)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.top, 2)

                if !hourlySlots().isEmpty {
                    Divider().padding(.vertical, 2)
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(hourlySlots(), id: \.epochSeconds) { point in
                            VStack(spacing: 4) {
                                Text(hourLabel(point))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                Image(systemName: point.condition.symbol(isDay: isDayNow(point)))
                                    .font(.system(size: 18))
                                    .symbolRenderingMode(.multicolor)
                                Text("\(point.temperatureC)°")
                                    .font(.system(size: 12, weight: .medium))
                                    .monospacedDigit()
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            } else {
                Text(waitingForGPS ? "定位中，稍后取天气" : "正在获取天气…")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            }
        }
    }

    private func todayRange(_ weather: WeatherSnapshot) -> (low: Int, high: Int)? {
        WeatherParsing.temperatureRange(weather.hourly, date: Date(), timeZone: .current)
    }

    /// 从当前小时块开始取 5 个点。
    private func hourlySlots() -> [WeatherHour] {
        let points = weather?.hourly ?? []
        guard !points.isEmpty else { return [] }
        let now = Int(Date().timeIntervalSince1970)
        let offset = TimeZone.current.secondsFromGMT(for: Date())
        let slots = WeatherParsing.slots(
            nowEpochSeconds: now,
            zoneOffsetSeconds: offset,
            count: hoursToShow,
            stepHours: 1
        )
        return slots.compactMap { WeatherParsing.point(at: $0, in: points) }
    }

    private func hourLabel(_ point: WeatherHour) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "H:00"
        return formatter.string(from: point.date)
    }

    /// 各时段是否白天：用日出日落粗略判断（只在做图标明暗区分时用）。
    private func isDayNow(_ point: WeatherHour) -> Bool {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: point.date)
        return (6..<18).contains(hour)
    }
}

/// 统一的卡片外观，和其余卡片保持一致。
struct CardContainer<Content: View>: View {

    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
}
