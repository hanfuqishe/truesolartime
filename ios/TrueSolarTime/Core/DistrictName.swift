import Foundation

/// 反查结果的两级写法：`full` 带上级（如「上海市宝山区」/「Huangpu District, Shanghai」），
/// `short` 只有区县。小组件与卡片那一行放不下长名字时退到 `short`。
struct DistrictNames: Equatable {
    let full: String
    let short: String
}

/// 把反查到的各级行政区划拼成显示名。纯逻辑，便于自检。
enum DistrictNaming {

    /// 中文界面：与 Android 版 `pickNames` 一致 —— 优先「市 + 区县」（直辖市时市与省同名），
    /// 区县名已带上级前缀就不再重复；没有区县时退回市，再退回省。
    static func joinChinese(
        county: String?,
        city: String?,
        region: String?
    ) -> DistrictNames? {
        let placeholders: Set<String> = ["市辖区", "县", "省直辖县级行政区划", "自治区直辖县级行政区划"]
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

    /// 与上次反查的坐标相距是否已超过阈值（公里）。
    static func shouldQuery(movedKm: Double, ageSeconds: TimeInterval) -> Bool {
        movedKm > moveThresholdKm || !(ageSeconds >= 0 && ageSeconds <= maxAgeSeconds)
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
