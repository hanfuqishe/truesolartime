import Foundation

/// 用户可选的天气数据源（设置页）。
///
/// - `auto`（默认）：**WeatherKit → Open-Meteo → 7Timer!**；
/// - `weatherKit`：只用 WeatherKit，**失败不回退**（保留旧数据 / 显示 `-`）；
/// - `openMeteo`：只用 Open-Meteo（7Timer 仍只在自动链里当最后一环）。
enum WeatherSourceSetting: String, CaseIterable, Identifiable {
    case auto
    case weatherKit
    case openMeteo

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return L("weather.sourceAuto")
        case .weatherKit: return L("weather.sourceWeatherKit")
        case .openMeteo: return L("weather.sourceOpenMeteoShort")
        }
    }

    /// 设置页说明（三语）。
    var hint: String { L("weather.sourceHint") }

    /// 旧版本 / 未知值一律回自动（大小写不敏感）。
    static func of(id: String?) -> WeatherSourceSetting {
        let text = (id ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return .auto }
        return allCases.first { $0.rawValue.lowercased() == text } ?? .auto
    }
}

/// 署名：文案 + 链接（WeatherKit 强制要求「 Apple 天气」这一官方表述与链接）。
struct WeatherAttribution: Equatable {
    let text: String
    let link: String?
}

/// 天气取数的**链式规则**（纯函数，可离线断言）。
enum WeatherChain {

    /// WeatherKit 官方署名链接（Apple 要求的法律署名页）。
    static let weatherKitAttributionLink = "https://weatherkit.apple.com/legal-attribution.html"

    /// 某个设置下的尝试顺序。手动模式只有一项（**不回退**）。
    static func order(setting: WeatherSourceSetting) -> [WeatherSource] {
        switch setting {
        case .auto: return [.weatherKit, .openMeteo, .sevenTimer]
        case .weatherKit: return [.weatherKit]
        case .openMeteo: return [.openMeteo]
        }
    }

    /// 自动模式下失败后该换谁；手动模式返回 nil（不回退）。
    static func nextSource(after source: WeatherSource, setting: WeatherSourceSetting) -> WeatherSource? {
        let chain = order(setting: setting)
        guard let index = chain.firstIndex(of: source), index + 1 < chain.count else { return nil }
        return chain[index + 1]
    }

    /// 该不该真的去调 WeatherKit（未知态一律不调；手动 Open-Meteo 也不调）。
    static func shouldRequestWeatherKit(setting: WeatherSourceSetting, isLocationUnknown: Bool) -> Bool {
        guard !isLocationUnknown else { return false }
        switch setting {
        case .auto, .weatherKit: return true
        case .openMeteo: return false
        }
    }

    /// 该不该去调 Open-Meteo（手动 WeatherKit 时不调）。
    static func shouldRequestOpenMeteo(setting: WeatherSourceSetting, isLocationUnknown: Bool) -> Bool {
        guard !isLocationUnknown else { return false }
        switch setting {
        case .auto, .openMeteo: return true
        case .weatherKit: return false
        }
    }

    /// 底部署名：WeatherKit 用 Apple 官方表述 + 链接，其余沿用现有 CC BY 4.0 文案。
    static func attribution(for source: WeatherSource) -> WeatherAttribution {
        switch source {
        case .weatherKit:
            return WeatherAttribution(text: L("weather.attributionWeatherKit"), link: weatherKitAttributionLink)
        case .openMeteo, .sevenTimer:
            return WeatherAttribution(text: source.attribution, link: nil)
        }
    }
}
