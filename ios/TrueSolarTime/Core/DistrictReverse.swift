import Foundation

/// OpenStreetMap Nominatim 反向地理编码：`CLGeocoder` 拿不到地名时的兜底。
///
/// 为什么需要：`CLGeocoder` 由 Apple 提供，境外坐标在大陆网络下经常只回 `country`，
/// 或者直接报错（`CLErrorDomain` 8 / 网络错误），界面就只能显示预设城市名。
/// Android 端对境外坐标本来就是走 Nominatim，这里补上同一套策略。
///
/// 纯逻辑（URL 拼装 + JSON → 地名）放在 Core 里，便于离线断言；网络请求见
/// `services/DistrictStore.swift`（12 秒超时、失败重试一次、结果进 30 天缓存）。
enum NominatimReverse {

    static let endpoint = "https://nominatim.openstreetmap.org/reverse"

    /// 遵守 OSM 使用条款：带可识别的 UA（Android 用 `TrueSolarTime-Android/<version>`）。
    static let userAgent = "TrueSolarTime-iOS/1.4.39 (com.realsuntime.solartime)"

    /// 查询参数与 Android 完全一致：`format=jsonv2`、`addressdetails=1`、
    /// `zoom=18`（给到街区级，境外也能取到「区」这一层）、`accept-language` 跟随界面语言。
    static func url(latitude: Double, longitude: Double, language: String) -> URL? {
        var components = URLComponents(string: endpoint)
        components?.queryItems = [
            URLQueryItem(name: "format", value: "jsonv2"),
            URLQueryItem(name: "addressdetails", value: "1"),
            URLQueryItem(name: "zoom", value: "18"),
            URLQueryItem(name: "lat", value: String(format: "%.6f", latitude)),
            URLQueryItem(name: "lon", value: String(format: "%.6f", longitude)),
            URLQueryItem(name: "accept-language", value: language),
        ]
        return components?.url
    }

    /// Nominatim 的 JSON → 地名。字段优先级与 Android `namesFromNominatim` 一致，
    /// 最终仍由 `DistrictNaming.compose` 做成「区县, 市, 州/省（最多三级）」。
    static func names(json: String, prefersChinese: Bool) -> DistrictNames? {
        guard
            let data = json.data(using: .utf8),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        let address = root["address"] as? [String: Any] ?? [:]
        guard var names = names(address: address, prefersChinese: prefersChinese) else { return nil }
        if let raw = address["country_code"] as? String {
            let code = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            names.countryCode = code.count == 2 ? code : nil
        }
        return names
    }

    /// 纯函数版本：直接喂字段字典，便于断言。
    ///
    /// 顺序就是 Android 的「由细到粗」：区县 → 街道 → 市 → 县 → 州/省 → 国家。
    static func names(address: [String: Any], prefersChinese: Bool) -> DistrictNames? {
        let levels: [String?] = [
            first(address, ["city_district", "district", "borough"], prefersChinese: prefersChinese),
            first(address, ["suburb", "quarter", "neighbourhood"], prefersChinese: prefersChinese),
            first(address, ["city", "town", "village", "municipality"], prefersChinese: prefersChinese),
            first(address, ["county"], prefersChinese: prefersChinese),
            first(address, ["state", "province", "region"], prefersChinese: prefersChinese),
            first(address, ["country"], prefersChinese: prefersChinese),
        ]
        let cleaned = levels.filter { value in
            guard let value else { return true }
            return !DistrictNaming.placeholderRegions.contains(value)
        }
        return DistrictNaming.compose(parts: cleaned)
    }

    /// 取第一个非空字段。
    static func first(_ address: [String: Any], _ keys: [String], prefersChinese: Bool) -> String? {
        for key in keys {
            guard let raw = address[key] as? String else { continue }
            if let value = languageSegment(raw, prefersChinese: prefersChinese) { return value }
        }
        return nil
    }

    /// OSM 在 `accept-language` 含中文时会返回「简体;繁体」这种多语言值（如「纽约;紐約」），
    /// Android 取第一段；这里中文界面优先取**含汉字**的那一段，其余取第一段。
    static func languageSegment(_ raw: String, prefersChinese: Bool) -> String? {
        let parts = raw
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "[]" }
        guard !parts.isEmpty else { return nil }
        if prefersChinese, let chinese = parts.first(where: { $0.contains(where: isCJK) }) {
            return chinese
        }
        return parts[0]
    }

    /// 是否是汉字（CJK 统一表意文字，含扩展 A）。
    static func isCJK(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value) || (0x3400...0x4DBF).contains(scalar.value)
        }
    }
}
