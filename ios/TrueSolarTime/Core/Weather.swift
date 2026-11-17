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

    /// 本地化 key，例如 "weather.clear"。
    var key: String {
        switch self {
        case .clear: return "weather.clear"
        case .partlyCloudy: return "weather.partlyCloudy"
        case .overcast: return "weather.overcast"
        case .fog: return "weather.fog"
        case .drizzle: return "weather.drizzle"
        case .rain: return "weather.rain"
        case .heavyRain: return "weather.heavyRain"
        case .showers: return "weather.showers"
        case .snow: return "weather.snow"
        case .heavySnow: return "weather.heavySnow"
        case .thunder: return "weather.thunder"
        }
    }

    /// 界面上的写法（晴 / 多雲 / Clear）。
    var label: String { L(key) }
}

/// 天气数据的来源。**步长跟着来源走**：主源 1 小时一格，备用源 3 小时一格。
///
/// 「步长」是与采样点同等重要的一等信息：界面永远只画 6 格，格子之间的距离由它决定。
/// 拿 1 小时的槽位去配 3 小时的数据，标签就会和实际读数错位（21 时那格显示 20 点的温度）。
enum WeatherSource: String, CaseIterable, Equatable {
    /// 主源：Open-Meteo，1 小时粒度。
    case openMeteo = "open-meteo"
    /// 备用源：7Timer!（civil 产品），3 小时粒度。
    case sevenTimer = "7timer"

    /// 这份数据的采样间隔（小时）。
    var stepHours: Int {
        switch self {
        case .openMeteo: return 1
        case .sevenTimer: return 3
        }
    }

    /// 低精度数据（3 小时粒度）：**即使没过期也要尝试刷新**，目的是尽快升级回主源的 1 小时数据。
    var isLowPrecision: Bool { stepHours > 1 }

    /// 界面上的品牌名（三语同形，但仍走本地化表以免以后要改）。
    var displayName: String {
        switch self {
        case .openMeteo: return L("weather.sourceOpenMeteo")
        case .sevenTimer: return L("weather.source7Timer")
        }
    }

    /// 底部署名整句。主源是 CC BY 4.0，必须署名；降级到 7Timer! 后不能再写 Open-Meteo。
    var attribution: String {
        switch self {
        case .openMeteo: return L("weather.attribution")
        case .sevenTimer: return L("weather.attribution7Timer")
        }
    }

    /// 缓存里的来源字符串（旧版本没有这个键、或值被人为改坏）→ 一律当主源。
    static func of(id: String?) -> WeatherSource {
        let text = (id ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return .openMeteo }
        return WeatherSource(rawValue: text) ?? .openMeteo
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

/// 界面上的一格：用哪个采样点，以及它是不是「现在」那一格。
struct WeatherSlot: Equatable {
    let epochSeconds: Int
    let isNow: Bool

    var date: Date { Date(timeIntervalSince1970: TimeInterval(epochSeconds)) }
}

/// 界面上某一格**最终要显示**的内容（标签文本由界面按语言拼，这里只管数据）。
///
/// 抽到 Core 里是为了让「『现在』那一格的图标与温度都来自实时读数」成为一条**可断言**的
/// 数据规则，而不是散在 SwiftUI 视图里的三元表达式：3 小时源的采样点可能已经是几小时前，
/// 只把图标换成实时、温度仍取采样点，就会出现「现在格：夜间图标 + 3 小时前的温度」，
/// 同时又和日期行的实时温度互相矛盾。
struct WeatherSlotReading: Equatable {
    /// 这一格排在哪个时刻（有数据时就是那条采样点的真实时刻）。
    let slot: WeatherSlot
    /// 该格显示的天气；没有数据时 nil（界面显示占位符）。
    let condition: WeatherCondition?
    /// 该格显示的气温；没有数据时 nil。
    let temperatureC: Int?
    /// 该格对应的采样点真实时刻（判昼夜图标用）；没有采样点时为 nil。
    let pointEpochSeconds: Int?

    var pointDate: Date? {
        pointEpochSeconds.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }
}

/// 主源失败之后怎么办（纯判定，便于自检）。
enum WeatherFallback: Equatable {
    /// 缓存还没过期：什么都不做，界面继续用缓存（**不清空**）。
    case keepCache
    /// 缓存已过期，或根本没有缓存：去问备用源 7Timer!。
    case trySevenTimer
}

/// 小组件与卡片消费的天气快照。
///
/// 采样点、来源、步长必须**一起**消费：只取 `hourly` 而不知道 `stepHours`，
/// 槽位标签就会和实际读数错位。
struct WeatherSnapshot: Equatable {
    /// 当前气温；没有当前值时用小时序列里最近的一点兜底。
    let temperatureC: Int
    let code: Int
    let hourly: [WeatherHour]
    /// 这份数据是从哪个源取的。
    let source: WeatherSource
    /// 逐时步长（小时）：界面 6 个槽位之间的间隔。
    ///
    /// 它**恒等于 `source.stepHours`**（构造时归一化），不可能与署名不一致。
    let stepHours: Int

    init(
        temperatureC: Int,
        code: Int,
        hourly: [WeatherHour],
        source: WeatherSource = .openMeteo,
        stepHours: Int? = nil
    ) {
        self.temperatureC = temperatureC
        self.code = code
        self.hourly = hourly
        self.source = source
        // **步长只由来源决定**，调用方传什么都不采纳。
        //
        // 之前是 `max(stepHours ?? source.stepHours, 1)`：只要有一条路径（缓存里旧的
        // `weather.step`、外部调用点、旧版本写下的 0）把 1 传进来，就会出现
        // 「署名 7Timer! + 逐时行按 1 小时排」这种自相矛盾的界面 —— 署名与步长必须同源，
        // 所以这里把「归一化」做成唯一入口，缓存读回也走同一条路。
        // 参数保留只为兼容既有调用点与自检里「传错值也要被纠正」的断言。
        _ = stepHours
        self.stepHours = source.stepHours
    }

    /// 界面画逐时行时**唯一允许**用的步长。
    ///
    /// 有快照就用快照的（已在 `init` 里按来源归一化）；没有快照时用**署名那一份来源**的步长
    /// —— 以前界面写 `?? 1`，于是 7Timer! 的署名配上 1 小时的理论网格，
    /// 正是用户报的「署名 7Timer!，逐时行却是 1 小时粒度」。
    static func slotStepHours(_ snapshot: WeatherSnapshot?, source: WeatherSource) -> Int {
        snapshot?.stepHours ?? source.stepHours
    }

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

    /// 备用源 7Timer! 的请求地址（注意参数顺序是 `lon` 在前、`lat` 在后）。
    static func sevenTimerURL(latitude: Double, longitude: Double) -> URL? {
        let text = String(
            format: "https://www.7timer.info/bin/api.pl?lon=%.4f&lat=%.4f&product=civil&output=json",
            longitude,
            latitude
        )
        return URL(string: text)
    }

    /// 主源的一份完整结果：实时读数 + 逐时序列。
    ///
    /// 两者缺一都算失败：只有 `current` 没有 `hourly`（或 JSON 被截断）时降级到备用源，
    /// 否则界面会拿到一份「有气温、没有逐时」的半残数据。
    static func parsePrimary(_ json: String) -> (current: (temperatureC: Int, code: Int), hourly: [WeatherHour])? {
        guard let current = parseCurrent(json) else { return nil }
        let hourly = parseHourly(json)
        guard !hourly.isEmpty else { return nil }
        return (current, hourly)
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

    // MARK: - 备用源 7Timer!（3 小时粒度）

    /// 解析 7Timer! 的 `dataseries`。
    ///
    /// 官方 `api.pl` **不给每个点的绝对时刻**，只给「模式起报时刻 `init`」+「相对 init 的小时数
    /// `timepoint`」（实测 2026-11 的返回：`init=2026111606`、`timepoint=3,6,9,…`）；
    /// 旧文档 / 部分镜像里还出现过 `time` 字段（形如 `2025111603`）。两种都认，且都**向下对齐到
    /// UTC 的 0/3/6/…/21 点整 3 小时网格**，免得界面上出现 `22时`、`1时` 这种不在网格上的标签。
    static func parseSevenTimer(_ json: String) -> [WeatherHour] {
        guard
            let data = json.data(using: .utf8),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let series = root["dataseries"] as? [Any]
        else { return [] }

        let initEpoch = sevenTimerStampEpoch(root["init"] as? String)
        var points: [WeatherHour] = []
        points.reserveCapacity(series.count)
        for item in series {
            guard let item = item as? [String: Any] else { continue }
            // 没有气温的条目直接丢掉（真实返回里偶尔混进只有 `weather` 的残项）。
            guard let temp = numberValue(item["temp2m"]) else { continue }

            let epoch: Int
            if let stampEpoch = sevenTimerStampEpoch(item["time"] as? String) {
                epoch = stampEpoch
            } else if let initEpoch, let timepoint = numberValue(item["timepoint"]) {
                // `timepoint` 是相对 `init` 的小时数（3,6,9,…,192）。
                epoch = initEpoch + Int(timepoint) * 3600
            } else {
                // 既没有 `time` 也没有 `init` + `timepoint`：算不出时刻，整条丢掉。
                continue
            }

            points.append(
                WeatherHour(
                    epochSeconds: alignToStep(epoch, stepHours: WeatherSource.sevenTimer.stepHours),
                    temperatureC: Int(temp.rounded()),
                    code: wmoCodeOfSevenTimer(item["weather"] as? String)
                )
            )
        }
        return points.sorted { $0.epochSeconds < $1.epochSeconds }
    }

    /// `2025111603` / `2026111606` 这类 UTC 时刻串 → epoch 秒；解析不了返回 nil。
    ///
    /// 用 `Calendar` 而不是 `DateFormatter`：解析一份 200 点的返回要建 200 个 formatter，
    /// 而 `Calendar` 是值类型、随手造一个也不慢。时区固定 UTC —— 接口给的就是 UTC。
    static func sevenTimerStampEpoch(_ stamp: String?) -> Int? {
        let text = (stamp ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count == 10, text.allSatisfy(\.isNumber) else { return nil }
        let digits = Array(text)
        func number(_ range: Range<Int>) -> Int? {
            Int(String(digits[range]))
        }
        guard
            let year = number(0..<4),
            let month = number(4..<6),
            let day = number(6..<8),
            let hour = number(8..<10)
        else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0)!
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        guard let date = calendar.date(from: components) else { return nil }
        return Int(date.timeIntervalSince1970)
    }

    /// 7Timer! 的天气词 → WMO 天气码（与主源共用同一套文案与图标）。
    ///
    /// 7Timer 用 `day`/`night` 后缀区分昼夜（`clearday` / `cloudynight`），先剥掉后缀再查表；
    /// 表外的值按「多云」处理（宁可少报一个极端天气，也不要显示成晴）。
    static func wmoCodeOfSevenTimer(_ weather: String?) -> Int {
        var key = (weather ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if key.hasSuffix("day") {
            key.removeLast(3)
        } else if key.hasSuffix("night") {
            key.removeLast(5)
        }
        switch key {
        case "clear", "sunny": return 0 // 晴
        case "pcloudy": return 2 // 多云
        case "mcloudy", "cloudy", "overcast": return 3 // 阴
        case "humid", "fog", "foggy": return 45 // 雾
        case "lightrain", "drizzle", "oshower", "ishower", "shower", "showers": return 80 // 阵雨 / 小雨
        case "rain": return 63 // 中雨
        case "heavyrain": return 65 // 大雨
        case "lightsnow": return 71 // 小雪
        case "snow", "snowrain", "rainsnow", "sleet": return 73 // 雪 / 雨夹雪
        case "ts", "thunder", "thunderstorm": return 95 // 雷雨
        default: return 2 // 未知 → 多云
        }
    }

    /// 把时刻向下对齐到 `stepHours` 小时的整倍（UTC 网格：0/3/6/…/21 点）。
    static func alignToStep(_ epochSeconds: Int, stepHours: Int) -> Int {
        let step = max(stepHours, 1) * 3600
        return epochSeconds - floorMod(epochSeconds, step)
    }

    /// 从逐时序列里取「现在」的读数（备用源没有 `current` 块）：
    /// 不晚于当前时刻的**最后一个**采样点；全都在未来时取第一个。
    static func snapshotAt(points: [WeatherHour], nowEpochSeconds: Int) -> (temperatureC: Int, code: Int)? {
        let point = points.last { $0.epochSeconds <= nowEpochSeconds } ?? points.first
        guard let point else { return nil }
        return (point.temperatureC, point.code)
    }

    /// 界面真正要画的那 6 格（首页大卡片与逐时行共用这一条规则）。
    ///
    /// - **首格永远是「现在」**：当前时刻之前最近的那个采样点（全都在未来时取第一个点）。
    ///   它不是「当前整点」—— 3 小时源在 21:30 的「现在」是 20 点那一条读数。
    /// - 之后按**数据源自己的步长**往后取：1 小时源是 现在/22时/23时/0时…，
    ///   3 小时源是 现在/23时/2时/5时/8时/11时（取决于采样网格）。标签一律用该点的实际本地小时数
    ///   —— 所以每一格会尽量落到真实采样点上（见 `snapToPoint`），而不是停在理论网格上。
    /// - 没有数据时退回按步长对齐的理论网格，让格子照样排出来（内容显示占位符）。
    ///
    /// - Parameter skip: 跳过前面几格（桌面卡片的第二排逐时行接在第一排后面）。
    static func visibleSlots(
        points: [WeatherHour],
        nowEpochSeconds: Int,
        zoneOffsetSeconds: Int,
        count: Int,
        stepHours: Int,
        skip: Int = 0
    ) -> [WeatherSlot] {
        guard count > 0 else { return [] }
        let step = max(stepHours, 1) * 3600
        let offset = max(skip, 0) * step
        let anchor = points.last { $0.epochSeconds <= nowEpochSeconds }?.epochSeconds
            ?? points.first?.epochSeconds

        guard let anchor else {
            // 没有数据：照样排满 6 格占位符（内容由界面填 `-`）。
            // 1 小时源按**本地整点**对齐（用户看到的就是整点）；3 小时源按 UTC 的 0/3/6/…/21 点对齐
            // —— 与 7Timer! 的采样网格一致，数据一到标签不会整体跳一格。
            let shifted = nowEpochSeconds + offset
            let start: Int
            if stepHours <= 1 {
                let local = shifted + zoneOffsetSeconds
                start = local - floorMod(local, 3600) - zoneOffsetSeconds
            } else {
                start = alignToStep(shifted, stepHours: stepHours)
            }
            return (0..<count).map {
                WeatherSlot(epochSeconds: start + $0 * step, isNow: skip == 0 && $0 == 0)
            }
        }

        let start = snapToPoint(anchor + offset, points: points, step: step)
        var slots: [WeatherSlot] = []
        slots.reserveCapacity(count)
        var previous = start
        for index in 0..<count {
            // 标签一律用槽位时刻的本地小时数，所以槽位时刻必须尽量落在**真实采样点**上：
            // 半个步长以内有真实点就用真实点，否则保留名义网格时刻（缺口那格显示占位符）。
            var epoch = index == 0 ? start : snapToPoint(previous + step, points: points, step: step)
            if index > 0 && epoch <= previous {
                epoch = previous + step
            }
            slots.append(
                WeatherSlot(epochSeconds: epoch, isNow: skip == 0 && index == 0)
            )
            previous = epoch
        }
        return slots
    }

    /// 把名义网格时刻落到**真实采样点**上（距离小于半个步长才算命中），否则原样返回。
    ///
    /// 为什么需要它：标签用的是槽位时刻，若数据自己的网格与「来源步长」略有偏移
    /// （旧文档的 `time` 字段、镜像站的残项），槽位就会停在一条不存在的读数上 ——
    /// 界面上看起来是「这个点的标签对应另一个点的温度」。落点只允许在半步长内，
    /// 这样既不会跳过缺口、也不会把 6 格压短成 5 格。
    private static func snapToPoint(_ nominal: Int, points: [WeatherHour], step: Int) -> Int {
        guard let nearest = point(at: nominal, in: points) else { return nominal }
        return abs(nearest.epochSeconds - nominal) < step / 2 ? nearest.epochSeconds : nominal
    }

    /// 逐时行每一格显示什么（首页大卡片与遗留 `WeatherCard` 共用这一条规则）。
    ///
    /// - **「现在」那一格的图标与温度都取实时读数**（与日期行同一个数）。3 小时源的采样点
    ///   可能是 3 小时前的，只换图标不换温度就会出现「夜间图标 + 下午的温度」。
    /// - 其余格取该采样点的读数；该时刻没有采样点就是占位符（两项都为 nil）。
    static func slotReadings(
        points: [WeatherHour],
        nowEpochSeconds: Int,
        zoneOffsetSeconds: Int,
        count: Int,
        stepHours: Int,
        currentTemperatureC: Int? = nil,
        currentCode: Int? = nil,
        skip: Int = 0
    ) -> [WeatherSlotReading] {
        let slots = visibleSlots(
            points: points,
            nowEpochSeconds: nowEpochSeconds,
            zoneOffsetSeconds: zoneOffsetSeconds,
            count: count,
            stepHours: stepHours,
            skip: skip
        )
        let byEpoch = Dictionary(
            points.map { ($0.epochSeconds, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return slots.map { slot in
            let point = byEpoch[slot.epochSeconds]
            let code = slot.isNow ? (currentCode ?? point?.code) : point?.code
            let temperature = slot.isNow
                ? (currentTemperatureC ?? point?.temperatureC)
                : point?.temperatureC
            return WeatherSlotReading(
                slot: slot,
                condition: code.map { WeatherCondition.of(code: $0) },
                temperatureC: temperature,
                pointEpochSeconds: point?.epochSeconds
            )
        }
    }

    // MARK: - 降级与旧数据

    /// 「需要重新取数」的时限：超过它就发起请求（不是「超过它就不显示」）。
    static let cacheTTLSeconds: Int = 30 * 60
    /// 显示用的硬上限：**24 小时**。取数一直失败时，旧数据继续显示一天，超过才当没有数据。
    static let displayMaxAgeSeconds: Int = 24 * 60 * 60
    /// 「低精度触发」刷新的节流窗口：最多每 10 分钟试一次。
    static let lowPrecisionRetrySeconds: Int = 10 * 60

    /// 这一轮该不该刷新（纯判定，便于自检）。
    ///
    /// 满足**任意一条**即刷新：
    /// 1. 数据已过期（超过 `cacheTTLSeconds`）；
    /// 2. 当前显示的是**低精度数据**（`source = 7Timer!` / `stepHours = 3`），即使未过期也刷 ——
    ///    目的是尽快升级回 Open-Meteo 的 1 小时数据。
    ///
    /// 只有「低精度」这一条受节流：10 分钟内已经试过就先算了（失败不该让界面变差，
    /// 也不该每回到前台就打一次网络）。过期与低精度互不干扰：过期就是过期，立刻刷。
    ///
    /// - Parameters:
    ///   - isStale: 数据是否已过期。
    ///   - isLowPrecision: 当前数据是否低精度（3 小时粒度）。
    ///   - lastLowPrecisionAttempt: 距上一次「低精度触发刷新」过去了多少秒；从没试过传 nil。
    static func shouldRefresh(
        isStale: Bool,
        isLowPrecision: Bool,
        lastLowPrecisionAttempt: Int?
    ) -> Bool {
        if isStale { return true }
        guard isLowPrecision else { return false }
        guard let last = lastLowPrecisionAttempt else { return true }
        // 时间戳异常（负数）当作「从没试过」，别把它永久节流掉。
        return last < 0 || last >= lowPrecisionRetrySeconds
    }

    /// 主源失败之后怎么办。
    ///
    /// - 没有缓存 → 去问备用源；
    /// - 缓存还没过期（30 分钟内）→ **什么都不做**，界面继续显示缓存，不清空；
    /// - 缓存过期 → 去问备用源（7Timer!）。
    static func fallbackFor(hasCache: Bool, cacheAgeSeconds: Int) -> WeatherFallback {
        guard hasCache else { return .trySevenTimer }
        if cacheAgeSeconds >= 0 && cacheAgeSeconds <= cacheTTLSeconds { return .keepCache }
        return .trySevenTimer
    }

    /// 这份缓存还值不值得显示（24 小时内都算「旧数据但可显示」）。
    static func isDisplayable(ageSeconds: Int) -> Bool {
        ageSeconds >= 0 && ageSeconds <= displayMaxAgeSeconds
    }

    /// 诊断用的「数据过期 N 分钟」里的 N；没有缓存（nil）或时间戳异常时返回 nil。
    static func staleMinutes(ageSeconds: Int?) -> Int? {
        guard let ageSeconds, ageSeconds >= 0 else { return nil }
        return ageSeconds / 60
    }

    /// 诊断里的过期说明：「数据过期 N 分钟」。没有缓存时返回 nil。
    static func staleLabel(ageSeconds: Int?) -> String? {
        guard let minutes = staleMinutes(ageSeconds: ageSeconds) else { return nil }
        return Lf("weather.stale", minutes)
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
