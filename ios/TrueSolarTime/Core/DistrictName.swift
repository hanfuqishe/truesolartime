import Foundation

/// 反查结果的两级写法：`full` 带上级（如「上海市宝山区」/「Huangpu District, Shanghai」），
/// `short` 只有区县。小组件与卡片那一行放不下长名字时退到 `short`。
struct DistrictNames: Equatable {
    let full: String
    let short: String
    /// ISO 3166-1 alpha-2（小写），用于查标准时区；反查不到时为 nil。
    var countryCode: String? = nil
}

/// 把反查到的各级行政区划拼成显示名。纯逻辑，便于自检。
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
