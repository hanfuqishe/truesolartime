import Foundation

/// 界面与卡片的配色模式：自动 / 强制亮色 / 强制暗色。
///
/// 「自动」是**默认值，也是本特性之前唯一的行为**：白天（太阳在地平线上）用亮色、夜里用暗色，
/// 不看系统的深色开关 —— 太阳落山的那一刻整个界面一起换色。
/// 强制模式只是忽略日出日落，其余渲染逻辑（关键时间配色、时间轴、卡片渐变）完全一样。
///
/// 与 Android 的 `data/ThemeMode.kt` 一一对应；持久化存 `rawValue`（`auto` / `light` / `dark`）。
enum ThemeMode: String, CaseIterable, Equatable {

    /// 按日出日落自动切换（默认）。
    case auto = "auto"

    /// 永远亮色。
    case light = "light"

    /// 永远暗色。
    case dark = "dark"

    /// 当前该不该用暗色。
    ///
    /// - Parameter sunIsUp: 太阳是否在地平线之上（`SolarSnapshot.isDay` / 太阳高度角判断）。
    ///   `.auto` 用它，`.light` / `.dark` 直接忽略它。
    func isDark(sunIsUp: Bool) -> Bool {
        switch self {
        case .auto: return !sunIsUp
        case .light: return false
        case .dark: return true
        }
    }

    /// 配色用的「当前是不是白天」：自动模式看太阳，强制模式由用户定。
    ///
    /// 页面、卡片、大卡片渐变都读它；`SunCard` 里的太阳弧仍按真实高度角画（那是事实，不是配色）。
    func isDayPalette(sunIsUp: Bool) -> Bool {
        !isDark(sunIsUp: sunIsUp)
    }

    /// 设置页三项的文案（自动 / 亮色 / 暗色）。
    var label: String {
        switch self {
        case .auto: return L("settings.themeAuto")
        case .light: return L("settings.themeLight")
        case .dark: return L("settings.themeDark")
        }
    }

    /// 存储里的名字 → 枚举。认不出来（旧版本没有这个键、或值被改坏）一律回「自动」。
    static func fromStorage(_ raw: String?) -> ThemeMode {
        let text = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return .auto }
        return ThemeMode(rawValue: text) ?? .auto
    }
}
