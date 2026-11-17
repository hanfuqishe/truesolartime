import SwiftUI

/// 天气卡片：今天的最低/最高气温 + 当前天气 + 未来 5 小时。
/// 数据来自 Open-Meteo（与 Android 版同一接口、同一缓存策略）。
struct WeatherCard: View {

    @Environment(\.palette) private var palette

    let weather: WeatherSnapshot?
    let isDay: Bool
    let waitingForGPS: Bool
    /// 署名用的来源：没有快照时逐时行按它的步长排（与底部署名同源，绝不退回 1 小时）。
    var source: WeatherSource = .openMeteo

    private let hoursToShow = 5

    var body: some View {
        CardContainer {
            HStack {
                Text(L("weather.title"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.onSurfaceVariant)
                Spacer()
                if let weather, let range = todayRange(weather) {
                    Text("\(range.low)° ~ \(range.high)°")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(palette.onSurfaceVariant)
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
                            .foregroundStyle(palette.onSurfaceVariant)
                    }
                    Spacer()
                }
                .padding(.top, 2)

                if !hourlyReadings.isEmpty {
                    ThemedDivider().padding(.vertical, 2)
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(hourlyReadings, id: \.slot.epochSeconds) { reading in
                            VStack(spacing: 4) {
                                Text(hourLabel(reading))
                                    .font(.system(size: 11))
                                    .foregroundStyle(palette.onSurfaceVariant)
                                if let condition = reading.condition {
                                    Image(systemName: condition.symbol(isDay: isDayOf(reading)))
                                        .font(.system(size: 18))
                                        .symbolRenderingMode(.multicolor)
                                } else {
                                    Image(systemName: "minus")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(palette.onSurfaceVariant)
                                }
                                Text(reading.temperatureC.map { "\($0)°" } ?? "-")
                                    .font(.system(size: 12, weight: .medium))
                                    .monospacedDigit()
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            } else {
                Text(waitingForGPS ? L("weather.waitingFix") : L("weather.loading"))
                    .font(.system(size: 13))
                    .foregroundStyle(palette.onSurfaceVariant)
                    .padding(.vertical, 6)
            }
        }
    }

    private func todayRange(_ weather: WeatherSnapshot) -> (low: Int, high: Int)? {
        WeatherParsing.temperatureRange(weather.hourly, date: Date(), timeZone: .current)
    }

    /// 从当前小时块开始取 5 个点（步长跟数据源走：主源 1 小时、备用源 3 小时）。
    ///
    /// 与首页大卡片共用 `WeatherParsing.slotReadings`：「现在」那一格的图标与温度都取实时读数，
    /// 步长由 `WeatherSnapshot.slotStepHours` 按来源归一化（不再写 `?? 1`）。
    private var hourlyReadings: [WeatherSlotReading] {
        let points = weather?.hourly ?? []
        guard !points.isEmpty else { return [] }
        let now = Date()
        return WeatherParsing.slotReadings(
            points: points,
            nowEpochSeconds: Int(now.timeIntervalSince1970),
            zoneOffsetSeconds: TimeZone.current.secondsFromGMT(for: now),
            count: hoursToShow,
            stepHours: WeatherSnapshot.slotStepHours(weather, source: source),
            currentTemperatureC: weather?.temperatureC,
            currentCode: weather?.code
        )
    }

    private func hourLabel(_ reading: WeatherSlotReading) -> String {
        if reading.slot.isNow { return L("weather.now") }
        return Lf("weather.hour", Calendar.current.component(.hour, from: reading.slot.date))
    }

    /// 该格图标该按白天还是夜间画：「现在」格的图标是实时天气，昼夜也取当前时刻；
    /// 其余格用采样点自己的真实时刻（与首页大卡片同一规则）。
    private func isDayOf(_ reading: WeatherSlotReading) -> Bool {
        if reading.slot.isNow {
            return isDayNow(Date())
        }
        return isDayNow(reading.pointDate)
    }

    /// 各时段是否白天：用日出日落粗略判断（只在做图标明暗区分时用）。
    private func isDayNow(_ date: Date?) -> Bool {
        guard let date else { return isDay }
        let hour = Calendar.current.component(.hour, from: date)
        return (6..<18).contains(hour)
    }
}

/// 统一的卡片外观，和其余卡片保持一致。
struct CardContainer<Content: View>: View {

    @Environment(\.palette) private var palette

    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(palette.surface)
        )
    }
}
