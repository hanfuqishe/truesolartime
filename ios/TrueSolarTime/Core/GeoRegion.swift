import Foundation

/// 「是不是中国境内」的唯一口径（含港澳台），时区兜底与底图选源都走这里。
///
/// **国家码优先**：`73–135°E / 18–54°N` 这个矩形把印度、尼泊尔、孟加拉与部分东南亚
/// 都框了进来 —— 新德里（77.2°E, 28.6°N）就在框内。只按矩形判断，德里会被当成中国：
/// 时区显示成 UTC+8（应为 +5:30），底图还会去拉高德的瓦片（境外没有覆盖，标点又带着 GCJ-02 偏移）。
///
/// 所以规则是：
///   1. 有国家码就以国家码为准 —— `cn` / `hk` / `mo` / `tw` 算境内，其余一律算境外；
///   2. 没有国家码（刚 GPS 定位、逆地理还没回来）才退回经纬度包围盒。
///
/// 与 Android 的 `LocalZone.isInChina`、鸿蒙的 `SolarTimeMath.isInChina` 是同一套规则，
/// 三端改口径要一起改。
enum GeoRegion {

    /// 中国境内（含港澳台）的国家/地区码，小写。
    static let chinaCountryCodes: Set<String> = ["cn", "hk", "mo", "tw"]

    /// 中国境内的经纬度包围盒，与 Android `SolarTimeMath.isInChinaBbox`、鸿蒙
    /// `SolarTimeMath.isInChinaBbox` 同源。
    ///
    /// **只作没有国家码时的兜底**，不是「是不是中国」的完整判据。
    static func isInChinaBbox(latitude: Double, longitude: Double) -> Bool {
        longitude >= 73.0 && longitude <= 135.0 && latitude >= 18.0 && latitude <= 54.0
    }

    /// 有国家码就以国家码为准，没有才退回包围盒。
    ///
    /// - Parameters:
    ///   - countryCode: ISO 3166-1 alpha-2（大小写不敏感），未知传 nil 或空串。
    ///   - latitude: WGS-84 纬度。
    ///   - longitude: WGS-84 经度。
    static func isInChina(countryCode: String?, latitude: Double, longitude: Double) -> Bool {
        if let code = normalizedCountryCode(countryCode) {
            return chinaCountryCodes.contains(code)
        }
        return isInChinaBbox(latitude: latitude, longitude: longitude)
    }

    /// 国家码归一化：去空白、转小写；nil / 空串 / 全空白都返回 nil（视为未知）。
    static func normalizedCountryCode(_ countryCode: String?) -> String? {
        guard let trimmed = countryCode?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed.lowercased()
    }
}
