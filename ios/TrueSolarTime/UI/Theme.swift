import SwiftUI

/// 日间／夜间两套主题。
///
/// **切换由太阳高度角决定**（`SolarSnapshot.isDay`），不看系统深色开关 —— 太阳落山那一刻就换主题，
/// 与 Android 的 `TrueSolarTimeTheme(darkTheme = !snapshot.isDay)` 一致。
/// 色值逐项对齐 Android `ui/theme/Theme.kt` 的 LightColors / DarkColors。
struct ThemePalette {

    let isDay: Bool

    /// 页面背景
    let background: Color
    /// 卡片背景
    let surface: Color
    /// 主文字
    let onSurface: Color
    /// 次要文字
    let onSurfaceVariant: Color
    /// 分隔线 / 弱描边
    let outlineVariant: Color
    /// 强调色
    let primary: Color

    static let day = ThemePalette(
        isDay: true,
        background: Color(hex: 0xFFF8F1),
        surface: Color(hex: 0xFFFBF6),
        onSurface: Color(hex: 0x211A15),
        onSurfaceVariant: Color(hex: 0x52443A),
        outlineVariant: Color(hex: 0xD7C4B5),
        primary: Color(hex: 0xB4550A)
    )

    static let night = ThemePalette(
        isDay: false,
        background: Color(hex: 0x0B1220),
        surface: Color(hex: 0x16203A),
        onSurface: Color(hex: 0xE8EDF7),
        onSurfaceVariant: Color(hex: 0x9AA7BF),
        outlineVariant: Color(hex: 0x24304F),
        primary: Color(hex: 0xF5D68A)
    )

    static func of(isDay: Bool) -> ThemePalette {
        isDay ? .day : .night
    }
}

private struct IsDayKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// 当前是否白天（由太阳高度角决定，不是系统深色模式）。
    var isDay: Bool {
        get { self[IsDayKey.self] }
        set { self[IsDayKey.self] = newValue }
    }

    /// 当前主题调色板。
    var palette: ThemePalette {
        ThemePalette.of(isDay: isDay)
    }
}

enum Theme {

    static let dayGradient = LinearGradient(
        colors: [Color(red: 0.969, green: 0.651, blue: 0.294), Color(red: 0.918, green: 0.478, blue: 0.173)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let nightGradient = LinearGradient(
        colors: [Color(red: 0.165, green: 0.231, blue: 0.361), Color(red: 0.082, green: 0.106, blue: 0.180)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let cardCornerRadius: CGFloat = 24
    static let heroCornerRadius: CGFloat = 28
}

struct CardBackground: ViewModifier {
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .fill(palette.surface)
            )
    }
}

extension View {
    func cardBackground() -> some View { modifier(CardBackground()) }
}

extension Color {
    /// 0xRRGGBB → Color。必须用浮点除法，整数相除会全部变成 0。
    init(hex: UInt32, opacity: Double = 1.0) {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue, opacity: opacity)
    }
}

/// 与 Android 版一致的中文数字，用于"初一刻""正四刻"。
func chineseNumber(_ value: Int) -> String {
    switch value {
    case 1: return "一"
    case 2: return "二"
    case 3: return "三"
    case 4: return "四"
    default: return "\(value)"
    }
}
