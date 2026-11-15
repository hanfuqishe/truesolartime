import Foundation

/// 应用的界面语言：**完全跟随系统**，不提供应用内切换。
///
/// 匹配规则（`Locale.preferredLanguages` 逐级往下看）：
/// - `zh-Hant` / `zh-TW` / `zh-HK` / `zh-MO` → 繁體中文（台灣用語）；
/// - 其余 `zh-*`（`zh-Hans`、`zh-CN`、`zh-SG` …）→ 简体中文；
/// - `en-*` → 英文；
/// - 其它任何语言 → **英文兜底**。
///
/// 注意：区划名与天气描述都跟着这里走 —— 早先写死 `zh-Hans` 时，英文系统上会显示中文地名，
/// 那一类「语言不跟随」的老 bug 不要回退。
enum AppLanguage {

    /// 三种界面语言，`code` 与 `.lproj` 目录名一致。
    enum Language: String, CaseIterable {
        case simplified = "zh-Hans"
        case traditional = "zh-Hant"
        case english = "en"

        var code: String { rawValue }
    }

    /// 当前语言（启动时按系统偏好解析一次）。
    static let current: Language = resolve(preferredLanguages: Locale.preferredLanguages)

    /// 纯函数版本，便于自检。
    static func resolve(preferredLanguages: [String]) -> Language {
        for identifier in preferredLanguages {
            let lowered = identifier.lowercased()
            if lowered.hasPrefix("zh") {
                if lowered.contains("hant")
                    || lowered.contains("-tw")
                    || lowered.contains("-hk")
                    || lowered.contains("-mo") {
                    return .traditional
                }
                return .simplified
            }
            if lowered.hasPrefix("en") {
                return .english
            }
        }
        return .english
    }

    /// 当前语言代码，例如 "zh-Hant"；缓存 key、诊断里用。
    static var code: String { current.code }

    /// 是否需要中文（决定区划名用「市+区县」直连还是逗号拼接）。
    static var prefersChinese: Bool { current != .english }

    /// 交给 `CLGeocoder` / OSM Nominatim 的语言标记。
    ///
    /// `zh-Hans` → `zh-CN`，`zh-Hant` → `zh-TW`，英文界面 → `en`（要英文地名，不要中文）。
    static var geocoderLanguageCode: String {
        switch current {
        case .simplified: return "zh-CN"
        case .traditional: return "zh-TW"
        case .english: return "en"
        }
    }

    /// 交给 `CLGeocoder` 的 `preferredLocale`。
    static var geocoderLocale: Locale {
        Locale(identifier: geocoderLanguageCode)
    }

    /// 日期、星期、数字格式化用的 locale。
    static var locale: Locale {
        switch current {
        case .simplified: return Locale(identifier: "zh_Hans_CN")
        case .traditional: return Locale(identifier: "zh_Hant_TW")
        case .english: return Locale(identifier: "en_US")
        }
    }
}
