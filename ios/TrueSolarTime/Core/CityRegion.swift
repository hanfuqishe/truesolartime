import Foundation

/// 常用城市的大洲分组（与 Android / 鸿蒙同一套顺序与命名）。
enum CityRegion: String, CaseIterable, Identifiable {
    case asia
    case europe
    case africa
    case northAmerica
    case southAmerica
    case oceania
    case antarctica

    var id: String { rawValue }

    /// 组标题的本地化 key（`city.region.xxx`）。
    var titleKey: String { "city.region.\(rawValue)" }

    var title: String { L(titleKey) }

    /// 城市在这个洲里（用国家码粗分；预设城市都显式带 `region`，这里只给断言/兜底用）。
    static func of(countryCode: String?) -> CityRegion? {
        guard let code = countryCode?.lowercased() else { return nil }
        if ["cn", "hk", "mo", "tw", "jp", "kr", "kp", "sg", "th", "id", "in", "ae", "tr", "my", "ph", "vn"].contains(code) {
            return .asia
        }
        if ["ru", "gb", "fr", "de", "it", "es", "is", "se", "no", "fi", "pl", "nl"].contains(code) {
            return .europe
        }
        if ["eg", "za", "ke", "ng", "ma", "tn"].contains(code) {
            return .africa
        }
        if ["us", "ca", "mx", "gl"].contains(code) {
            return .northAmerica
        }
        if ["br", "ar", "pe", "cl", "co", "ve"].contains(code) {
            return .southAmerica
        }
        if ["au", "nz", "fj"].contains(code) {
            return .oceania
        }
        if code == "aq" {
            return .antarctica
        }
        return nil
    }
}
