import Foundation

/// 反查结果的两级写法：`full` 带上级（如「上海市宝山区」/「Huangpu District, Shanghai」），
/// `short` 只有区县。小组件与卡片那一行放不下长名字时退到 `short`。
/// 地名反查的**触发策略**（照搬 Android `DistrictResolver`，纯函数、可离线断言）。
///
/// 规则：
/// - 距「上次成功反查的坐标」**≤ 5 km** → 视为同一地方，**不反查**，沿用缓存名字；
/// - **> 5 km** 或缓存超过 **30 天** → 才发新请求；
/// - 拿不到距离（负数）→ 保守反查。
///
/// 这样「跟 GPS 走动」时不会每秒/每米都触发反查，只有真正换了地方才查。
enum PlaceNamePolicy {

    /// 距离阈值：5 km（与 Android `MOVE_THRESHOLD_KM` 一致）。
    static let moveThresholdKm: Double = 5.0
    /// 缓存有效期：30 天（与 Android `MAX_AGE_MILLIS` 一致）。
    static let maxAgeMillis: Int64 = 30 * 24 * 60 * 60 * 1000

    /// 这个距离内的名字可以信任（直接沿用）。
    static func trustsNameAt(movedKm: Double) -> Bool {
        movedKm >= 0 && movedKm <= moveThresholdKm
    }

    /// 该不该发一次新的反查。
    static func shouldQuery(movedKm: Double, ageMillis: Int64) -> Bool {
        if movedKm < 0 { return true }                       // 拿不到距离 → 保守查
        if movedKm > moveThresholdKm { return true }          // 换地方了
        if ageMillis < 0 || ageMillis > maxAgeMillis { return true }  // 过期
        return false
    }

    /// GPS 采样间隔：**60 秒一次**（Android `GPS_INTERVAL_MILLIS`）。
    static let locationSampleIntervalSeconds: TimeInterval = 60
}
/// 地名反查的**节流与缓存键**（纯函数，可离线断言）。
///
/// 背景：CLGeocoder 有「每次用户操作最多一个请求」的硬性要求，发太频繁会返回
/// `kCLErrorNetwork` / `-1001`（与网络错误无法区分）。所以必须：
///   1. 按**约 100 m 网格**去重（经纬度各 3 位小数）；
///   2. 全局串行 + 两次请求之间至少 **3 秒**；
///   3. 失败沿用时按距离判断（≤ 50 km 可用）。
enum PlaceNameThrottle {

    /// 缓存键的小数位（3 位 ≈ 111 m）。
    static let cacheKeyDecimals = 3
    /// 两次请求的最小间隔（秒）。
    static let minRequestIntervalSeconds: Double = 3
    /// 失败时允许沿用上次地名的最大距离（公里）。
    static let reuseMaxDistanceKm: Double = 50

    /// 坐标 → 缓存键：`31.312,121.379`（同一网格内视为同一地点）。
    static func cacheKey(latitude: Double, longitude: Double) -> String {
        String(format: "%.\(cacheKeyDecimals)f,%.\(cacheKeyDecimals)f", latitude, longitude)
    }

    /// 现在该不该发请求：同一键缓存过 → 不发；距上次请求不足 3 秒 → 不发。
    static func shouldRequest(
        key: String,
        cachedKeys: Set<String>,
        lastRequestAt: Double?,
        now: Double,
        inFlight: Bool = false,
        isNewPlace: Bool = false
    ) -> Bool {
        // 同一时刻只允许 1 个在飞；在飞时不发新请求（排队也不堆，下次触发再发）。
        if inFlight { return false }
        if cachedKeys.contains(key) { return false }
        // **换地点 / 首次拿到 GPS fix**：不受 3 秒窗口限制，第一请求立即发。
        if isNewPlace { return true }
        guard let last = lastRequestAt else { return true }
        return now - last >= minRequestIntervalSeconds
    }

    /// 失败时能不能沿用上次成功的地名（按距离；没有上次 → 不能）。
    static func canReuseLast(
        lastLatitude: Double?,
        lastLongitude: Double?,
        latitude: Double,
        longitude: Double
    ) -> Bool {
        guard let lastLatitude, let lastLongitude else { return false }
        let km = DistrictNaming.distanceKm(latitude, longitude, lastLatitude, lastLongitude)
        return km <= reuseMaxDistanceKm
    }
}
/// 地名反查的**来源决策**（纯函数，可离线断言）。
///
/// 背景：悉尼那台机器上 `CLGeocoder` 报 `-1001`（超时）、Nominatim 又被墙 → 地名变「暫無」。
/// 规则：**Apple 优先**（CLGeocoder 是系统服务、国内可用）；**超时类错误先退避重试**，
/// 期间沿用上一次成功的地名；只有明确「查不到 / 不可用」才转 OSM；OSM 也失败才放弃。
enum PlaceNameSource {

    enum Outcome: Equatable {
        case ok
        case notFound
        /// 超时（`NSURLErrorTimedOut` / -1001）：**不代表地名不存在**，应重试。
        case timeout
        case unavailable
        case failed
    }

    /// 错误分类：只有「明确查不到」才算终局，其它一律保守当可重试。
    enum ErrorKind: Equatable { case retryable, terminal }

    enum Action: Equatable {
        case useCLGeocoder
        case retryCLGeocoder
        /// 重试也没拿到：**沿用上一次成功的地名**（不要显示「暫無」）。
        case useCached
        case fallbackOSM
        case giveUp
    }

    /// 重试间隔（秒）：最多 2 次（1 秒、3 秒），与 `retryDelays` 一一对应。
    static let retryDelays: [Double] = [1, 3]

    static func errorKind(_ outcome: Outcome) -> ErrorKind {
        switch outcome {
        case .notFound: return .terminal
        // 超时 / 不可用 / 其它：保守当可重试（网络抖动很常见，不该一次就判死）。
        case .timeout, .unavailable, .failed: return .retryable
        case .ok: return .terminal
        }
    }

    /// 决策：`clGeocoder` 决定主路径；`hasCachedName` 表示缓存里有没有该地点附近成功过的地名。
    static func pick(clGeocoder: Outcome, osm: Outcome, hasCachedName: Bool = false) -> Action {
        switch clGeocoder {
        case .ok:
            return .useCLGeocoder
        case .timeout:
            // 超时 → 先重试；调用方重试完仍超时、且缓存里有地名 → 沿用缓存名（`useCached`）。
            return hasCachedName ? .useCached : .retryCLGeocoder
        case .notFound, .unavailable, .failed:
            return osm == .ok ? .fallbackOSM : (hasCachedName ? .useCached : .giveUp)
        }
    }
}


struct DistrictNames: Equatable {
    let full: String
    let short: String
    /// ISO 3166-1 alpha-2（小写），用于查标准时区；反查不到时为 nil。
    var countryCode: String? = nil
}

/// 把反查到的各级行政区划拼成显示名。纯逻辑，便于自检。
/// 地名**最终显示什么**（纯函数，`cardCityText` 与断言共用同一套规则）。
///
/// 项目规则（`docs/AGENTS.md` 第 5 节）：
/// - **预设城市**反查失败 → 直接显示该预设的城市名（本地数据、零网络、立即出）；
/// - **手工坐标 / GPS** 反查失败 → 半角 `-`（不是「暫無」，也不是空）。
enum PlaceNameResolver {

    // 中文文档注释：规则与 `DistrictNaming.cardCityText` 完全一致，后者转调本函数。

    /// - Parameters:
    ///   - presetName: 预设城市的本地化名（手工 / GPS 传 nil）。
    ///   - geocoded: 反查成功的地名（`nil` = 没拿到）。
    ///   - source: 地点来源（预设 / 手动 / GPS）。
    static func name(presetName: String?, geocoded: DistrictNames?, source: PlaceSource) -> String {
        if let full = geocoded?.full, !full.isEmpty { return full }
        // 预设名由调用方决定（只有预设城市才传）：传了就用，不看 `source`
        if let presetName, !presetName.isEmpty { return presetName }
        _ = source
        return "-"
    }
}
enum DistrictNaming {

    /// 高德 / 系统逆地理用来占位、本身不是地名的上级字段。
    static let placeholderRegions: Set<String> = ["市辖区", "县", "省直辖县级行政区划", "自治区直辖县级行政区划"]

    /// 中文界面：与 Android 版 `pickNames` 一致 —— 优先「市 + 区县」（直辖市时市与省同名），
    /// 区县名已带上级前缀就不再重复；没有区县时退回市，再退回省。
    static func joinChinese(
        county: String?,
        city: String?,
        region: String?
    ) -> DistrictNames? {
        let placeholders = placeholderRegions
        let countyName = clean(county)
        let cityName = clean(city).flatMap { placeholders.contains($0) ? nil : $0 }
        let regionName = clean(region).flatMap { placeholders.contains($0) ? nil : $0 }

        guard let countyName else {
            guard let only = cityName ?? regionName else { return nil }
            return DistrictNames(full: only, short: only)
        }
        let parent = [cityName, regionName].compactMap { $0 }.first { $0 != countyName }
        let full: String
        if let parent, !countyName.hasPrefix(parent) {
            full = parent + countyName
        } else {
            full = countyName
        }
        return DistrictNames(full: full, short: countyName)
    }

    /// 其他语言（以及 CLGeocoder 已经本地化的字符串）：由细到粗用逗号连接，去重、去占位值，
    /// 最多留三级 —— 太长会被省略号吃掉。同 Android 版 `composeNames`。
    static func compose(parts: [String?]) -> DistrictNames? {
        var seen = Set<String>()
        var levels: [String] = []
        for part in parts {
            guard let name = clean(part), !seen.contains(name) else { continue }
            seen.insert(name)
            levels.append(name)
            if levels.count == 3 { break }
        }
        guard let first = levels.first else { return nil }
        return DistrictNames(full: levels.joined(separator: ", "), short: first)
    }

    static func clean(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        guard !trimmed.isEmpty, trimmed != "[]" else { return nil }
        return trimmed
    }

    /// 反查字段（可能缺级）→ 卡片上那一行地名。**任何一级有值就出名字**，不会因为缺区县返回 nil。
    ///
    /// 这是修复「境外城市选完看不到区划名」的核心：
    ///
    /// 1. 中文界面、且这几级名字确实是中文写法 → 沿用 Android `pickNames` 的「市+区县」直连
    ///    （如「上海市黄浦区」）；
    /// 2. 其余情况（境外坐标；或 Apple 给的「Manhattan」+「纽约」这种中英混排）→ 由细到粗用
    ///    逗号连接（同 Android `composeNames`）。之前不区分语言一律走「市+区县」直连，
    ///    拉丁名字会被拼成「New YorkManhattan」这种怪串；
    /// 3. 国家名只作最粗一级兜底：Apple 对境外常只给 `locality`+`country`，甚至只给 `country`。
    ///
    /// - Parameters:
    ///   - district: 区 / 县 / 街道（`CLPlacemark.subLocality` 或 `subAdministrativeArea`）
    ///   - city: 市（`locality`）
    ///   - region: 省 / 州（`administrativeArea`）
    ///   - country: 国家（`country`），只用来兜底，不参与中文拼法
    ///   - prefersChinese: 界面语言是否为中文
    static func composeNames(
        district: String?,
        city: String?,
        region: String?,
        country: String? = nil,
        prefersChinese: Bool
    ) -> DistrictNames? {
        let county = clean(district).flatMap { placeholderRegions.contains($0) ? nil : $0 }
        let town = clean(city).flatMap { placeholderRegions.contains($0) ? nil : $0 }
        let regionName = clean(region).flatMap { placeholderRegions.contains($0) ? nil : $0 }
        let countryName = clean(country)

        if prefersChinese,
           isChineseGrouping([county, town, regionName]),
           let chinese = joinChinese(county: county, city: town, region: regionName) {
            return chinese
        }
        // 逐级降级：区县 → 市 → 州/省 → 国家，取最细的三级；只要有一级非空就有名字。
        return compose(parts: [county, town, regionName, countryName])
    }

    /// 这三级名字能不能按中文习惯直接相连：至少有一个汉字，且一个拉丁字母都没有。
    ///
    /// 「黄浦区」+「上海市」→ true（拼成「上海市黄浦区」）；
    /// 「Manhattan」+「纽约」→ false（用逗号，免得拼出「纽约Manhattan」）。
    static func isChineseGrouping(_ values: [String?]) -> Bool {
        var hasChinese = false
        for value in values {
            guard let name = clean(value) else { continue }
            for scalar in name.unicodeScalars {
                if (0x4E00...0x9FFF).contains(scalar.value) || (0x3400...0x4DBF).contains(scalar.value) {
                    hasChinese = true
                } else if (0x41...0x5A).contains(scalar.value) || (0x61...0x7A).contains(scalar.value) {
                    return false
                }
            }
        }
        return hasChinese
    }

    /// 与上次反查的坐标相距是否已超过阈值（公里）。
    static func shouldQuery(movedKm: Double, ageSeconds: TimeInterval) -> Bool {
        movedKm > moveThresholdKm || !(ageSeconds >= 0 && ageSeconds <= maxAgeSeconds)
    }

    // MARK: - 缓存能不能用 / 卡片上显示什么（纯逻辑，便于自检）

    /// 缓存里的地名能不能用在这个地点上。
    ///
    /// 两条硬要求：
    /// 1. **必须存过坐标**。旧版本的缓存只存了名字、没存坐标 —— 那种缓存对**任何**坐标都会被判成
    ///    「同一地点」，于是手动输入埃及坐标时卡片上仍挂着「北京」（本次修的 bug）。
    ///    没坐标就一律不可用（宁可显示「-」，也不要张冠李戴）。
    /// 2. 相距 ≤ `moveThresholdKm`（5 km）才算同一地点（GPS 抖动 / 步行范围内复用，换城市不复用）。
    static func cacheMatches(storedLatitude: Double?, storedLongitude: Double?, place: Place) -> Bool {
        guard let storedLatitude, let storedLongitude else { return false }
        let moved = distanceKm(storedLatitude, storedLongitude, place.latitude, place.longitude)
        return moved <= moveThresholdKm
    }

    /// 卡片左上角那一行城市名，三段式（与 Android `MainScreen.cityText` 一致）：
    ///
    /// ① 反查到的行政区划名优先（**只有属于当前地点时才给得出来**，见 `cacheMatches`）；
    /// ② 反查没结果时，**只有预设城市**才回退显示预设名（如「纽约」）；
    /// ③ 手工坐标与 GPS 没有名字可用 —— 显示半角「-」（既定产品决策：失败**不回填旧地名**）。
    /// - Parameter isQuerying: 反查是否还在进行（首帧 / 查询中）。为 true 时 GPS / 手工显示
    ///   `--`（查询中），false 时才显示 `-`（两者都失败）。
    static func cardCityText(district: DistrictNames?, place: Place, isQuerying: Bool = false) -> String {
        // 规则统一在 `PlaceNameResolver`：**只有预设城市**才拿预设名兜底；
        // 手工坐标 / GPS 反查失败一律显示 `-`（`presetLabel` 会按坐标「认回」预设城市，
        // 那是给老数据升级用的，不能用于这里）。
        // 预设城市：`presetLabel`（有 `presetKey` 时是本地化名；老数据按坐标认回预设城市）。
        // 手工 / GPS：一律 `nil` —— 反查失败就显示 `-`。
        // **有 `presetKey` 就是预设城市**（`Place.presets` 里的 source 是 `.manual`，不能按 source 判断）；
        // 手工坐标 / GPS 没有 `presetKey` → 反查失败显示 `-`。
        let presetName: String? = place.presetKey != nil ? place.displayLabel : nil
        if isQuerying {
            // 首帧 / 查询中：有缓存或预设名就先用，否则 `--`（**不是** `-`）。
            return PlaceNamePhase.firstFrame(presetName: presetName, cached: district)
        }
        return PlaceNameResolver.name(presetName: presetName, geocoded: district, source: place.source)
    }

    static let moveThresholdKm = 5.0
    static let maxAgeSeconds: TimeInterval = 30 * 24 * 60 * 60

    /// 两点间距离（公里），Haversine。
    static func distanceKm(
        _ latitude1: Double, _ longitude1: Double,
        _ latitude2: Double, _ longitude2: Double
    ) -> Double {
        let earthRadiusKm = 6371.0
        let dLat = (latitude2 - latitude1) * .pi / 180
        let dLon = (longitude2 - longitude1) * .pi / 180
        let lat1 = latitude1 * .pi / 180
        let lat2 = latitude2 * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + sin(dLon / 2) * sin(dLon / 2) * cos(lat1) * cos(lat2)
        return 2 * earthRadiusKm * atan2(sqrt(a), sqrt(1 - a))
    }

    /// 界面语言是否为中文（决定用「市+区县」拼法还是逗号拼法）。
    static func prefersChinese(_ language: String) -> Bool {
        language.lowercased().hasPrefix("zh")
    }
}
