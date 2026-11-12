import Foundation

/// WMO 天气码对应的分类，图标用 SF Symbols（与 Android 版的分类一一对应）。
enum WeatherCondition: String, CaseIterable {
    case clear
    case partlyCloudy
    case overcast
    case fog
    case drizzle
    case rain
    case heavyRain
    case showers
    case snow
    case heavySnow
    case thunder

    /// WMO weather code → 分类，同 Android 版 `conditionOf`。
    static func of(code: Int) -> WeatherCondition {
        switch code {
        case 0: return .clear
        case 1, 2: return .partlyCloudy
        case 3: return .overcast
        case 45, 48: return .fog
        case 51, 53, 55, 56, 57: return .drizzle
        case 61, 63, 66, 67: return .rain
        case 65, 82: return .heavyRain
        case 80, 81: return .showers
        case 71, 73, 77, 85, 86: return .snow
        case 75: return .heavySnow
        case 95, 96, 99: return .thunder
        default: return .overcast
        }
    }

    func symbol(isDay: Bool) -> String {
        switch self {
        case .clear: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case .partlyCloudy: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case .overcast: return "cloud.fill"
        case .fog: return "cloud.fog.fill"
        case .drizzle: return "cloud.drizzle.fill"
        case .rain: return "cloud.rain.fill"
        case .heavyRain: return "cloud.heavyrain.fill"
        case .showers: return isDay ? "cloud.sun.rain.fill" : "cloud.moon.rain.fill"
        case .snow: return "cloud.snow.fill"
        case .heavySnow: return "snowflake"
        case .thunder: return "cloud.bolt.rain.fill"
        }
    }

    var label: String {
        switch self {
        case .clear: return "晴"
        case .partlyCloudy: return "多云"
        case .overcast: return "阴"
        case .fog: return "雾"
        case .drizzle: return "小雨"
        case .rain: return "中雨"
        case .heavyRain: return "大雨"
        case .showers: return "阵雨"
        case .snow: return "雪"
        case .heavySnow: return "大雪"
        case .thunder: return "雷雨"
        }
    }
}

/// 小时预报的一个点。时间用 UTC 秒存，跨时区展示时再换算。
struct WeatherHour: Equatable, Codable {
    let epochSeconds: Int
    let temperatureC: Int
    let code: Int

    var date: Date { Date(timeIntervalSince1970: TimeInterval(epochSeconds)) }
    var condition: WeatherCondition { WeatherCondition.of(code: code) }
}

/// 小组件与卡片消费的天气快照。
struct WeatherSnapshot: Equatable {
    /// 当前气温；没有当前值时用小时序列里最近的一点兜底。
    let temperatureC: Int
    let code: Int
    let hourly: [WeatherHour]

    var condition: WeatherCondition { WeatherCondition.of(code: code) }

    var hourlyPoints: [WeatherHour] { hourly }
}

enum WeatherParsing {

    /// Open-Meteo 请求地址，参数与 Android 版完全一致（`timezone=UTC`，时间可直接当 UTC 解析）。
    static func url(latitude: Double, longitude: Double) -> URL? {
        let text = String(
            format: "https://api.open-meteo.com/v1/forecast?latitude=%.4f&longitude=%.4f"
                + "&current=temperature_2m,weather_code"
                + "&hourly=temperature_2m,weather_code&forecast_days=2&past_days=1&timezone=UTC",
            latitude,
            longitude
        )
        return URL(string: text)
    }

    static func parseHourly(_ json: String) -> [WeatherHour] {
        guard
            let data = json.data(using: .utf8),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let hourly = root["hourly"] as? [String: Any],
            let times = hourly["time"] as? [String],
            let temps = hourly["temperature_2m"] as? [Any]
        else { return [] }
        let codes = hourly["weather_code"] as? [Any] ?? []

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"

        var points: [WeatherHour] = []
        points.reserveCapacity(min(times.count, temps.count))
        for index in 0..<min(times.count, temps.count) {
            guard let date = formatter.date(from: times[index]) else { continue }
            guard let temp = numberValue(temps[index]) else { continue }
            let code = index < codes.count ? (numberValue(codes[index]) ?? 0) : 0
            points.append(
                WeatherHour(
                    epochSeconds: Int(date.timeIntervalSince1970),
                    temperatureC: Int(temp.rounded()),
                    code: Int(code)
                )
            )
        }
        return points
    }

    static func parseCurrent(_ json: String) -> (temperatureC: Int, code: Int)? {
        guard
            let data = json.data(using: .utf8),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let current = root["current"] as? [String: Any]
        else { return nil }
        guard let temp = numberValue(current["temperature_2m"]) else { return nil }
        let code = numberValue(current["weather_code"]) ?? 0
        return (Int(temp.rounded()), Int(code))
    }

    /// 本地某一天的最高/最低温度；小时序列没覆盖这一天时返回 nil。
    static func temperatureRange(
        _ points: [WeatherHour],
        date: Date,
        timeZone: TimeZone
    ) -> (high: Int, low: Int)? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let temps = points
            .filter { calendar.isDate($0.date, inSameDayAs: date) }
            .map(\.temperatureC)
        guard let high = temps.max(), let low = temps.min() else { return nil }
        return (high, low)
    }

    /// 要显示的时刻：从当前所在的 `stepHours` 小时块开始取 `count` 个（本地时区对齐）。
    /// 返回 UTC 秒，可直接与 `WeatherHour.epochSeconds` 对应。
    static func slots(
        nowEpochSeconds: Int,
        zoneOffsetSeconds: Int,
        count: Int,
        stepHours: Int
    ) -> [Int] {
        let step = stepHours * 3600
        let local = nowEpochSeconds + zoneOffsetSeconds
        let blockStart = local - floorMod(local, step)
        return (0..<count).map { blockStart + $0 * step - zoneOffsetSeconds }
    }

    /// 取某个时刻对应的小时预报（同一小时内取最近的一条）。
    static func point(at epochSeconds: Int, in points: [WeatherHour]) -> WeatherHour? {
        points.min { abs($0.epochSeconds - epochSeconds) < abs($1.epochSeconds - epochSeconds) }
    }

    static func floorMod(_ value: Int, _ modulus: Int) -> Int {
        let remainder = value % modulus
        return remainder < 0 ? remainder + modulus : remainder
    }

    private static func numberValue(_ any: Any?) -> Double? {
        if let value = any as? Double { return value }
        if let value = any as? Int { return Double(value) }
        if let value = any as? NSNumber { return value.doubleValue }
        return nil
    }
}
