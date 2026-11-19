import Foundation

/// 天气署名**怎么显示**（纯函数，可离线断言）。
///
/// Apple 的要求（`WeatherService.attribution` 文档原文）：*"The required attribution which
/// includes a legal attribution page and Apple Weather mark."* —— 也就是说 WeatherKit 数据
/// 必须显示 **Apple 天气标识图** + 法律声明页链接，而不是我们自造的「 天气」文字。
///
/// 三条规则：
/// 1. `source == .weatherKit` 且拿到了标识图 → `.mark(light/dark + legal)`；
/// 2. 拿到了 WeatherKit 但**标识图不可用**（网络失败 / 未取到）→ 退化成 `.text(Apple 文案 + legal)`（Apple 允许）；
/// 3. Open-Meteo / 7Timer → 沿用 CC BY 4.0 文字，无链接。
enum WeatherAttributionPresentation: Equatable {
    /// 标识图 + 法律声明页链接。
    case mark(lightURL: String, darkURL: String, legalURL: String)
    /// 纯文字（第二个参数是可选链接）。
    case text(String, String?)

    /// 选哪种显示。
    static func choose(
        source: WeatherSource,
        markLightURL: String?,
        markDarkURL: String?,
        legalURL: String?,
        isDark: Bool
    ) -> WeatherAttributionPresentation {
        guard source == .weatherKit else {
            return .text(source.attribution, nil)
        }
        let chosen = isDark ? markDarkURL : markLightURL
        if let chosen, !chosen.isEmpty, let legalURL, !legalURL.isEmpty {
            return .mark(
                lightURL: markLightURL ?? chosen,
                darkURL: markDarkURL ?? chosen,
                legalURL: legalURL
            )
        }
        // 退化：标识图不可用，用 Apple 官方文字 + 法律声明页链接。
        return .text(WeatherChain.attribution(for: .weatherKit).text, WeatherChain.weatherKitAttributionLink)
    }

    /// 当前该用哪个标识图 URL（非 mark 时为 nil）。
    func markURL(isDark: Bool) -> String? {
        switch self {
        case .mark(let light, let dark, _): return isDark ? dark : light
        case .text: return nil
        }
    }

    /// 点击后该打开的链接（非 mark / 无链接时为 nil）。
    var link: String? {
        switch self {
        case .mark(_, _, let legal): return legal
        case .text(_, let link): return link
        }
    }
}
