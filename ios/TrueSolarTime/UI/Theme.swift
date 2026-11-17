import SwiftUI

/// 日间／夜间两套主题。
///
/// **用哪一套由设置里的主题三态决定**（`ThemeMode`）：
/// - 自动（默认）= 按太阳高度角（`SolarSnapshot.isDay`），不看系统深色开关 ——
///   太阳落山那一刻就换主题，与 Android 的 `TrueSolarTimeTheme(darkTheme = !snapshot.isDay)` 一致；
/// - 亮色 / 暗色 = 强制忽略日出日落，页面、卡片、大卡片渐变一起跟随。
///
/// 色值全部来自 **Core 的 `ThemeColors`**（那里是唯一的真源，自检会对亮/暗两套取值做断言），
/// 这里只负责把 `0xRRGGBB` 转成 SwiftUI 的 `Color`。
///
/// 为什么要这样分层：以前颜色一半写在这里、一半交给系统外观（`.roundedBorder` 输入框、
/// `.bordered` 按钮、`Divider()`、`.secondary` 文字），一旦「强制亮色 / 强制暗色」和系统外观
/// 不一致就会串色 —— 暗色主题下白底输入框里的浅色字就是这么来的。
struct ThemePalette {

    let isDay: Bool

    /// 页面背景
    let background: Color
    /// 卡片背景（也是输入框分组的底色）
    let surface: Color
    /// 主文字
    let onSurface: Color
    /// 次要文字
    let onSurfaceVariant: Color
    /// 分隔线 / 弱描边
    let outlineVariant: Color
    /// 强调色（按钮底色、开关、光标）
    let primary: Color
    /// 强调色底上的文字
    let onPrimary: Color
    /// 圆盘白天弧（地平线以上的实线）：白天淡金色，只作路径示意
    let sunArc: Color
    /// 圆盘太阳点：实心核心（深金，边界清楚）
    let sunDot: Color
    /// 圆盘太阳点：中心高光（近白暖色小点）
    let sunDotHighlight: Color
    /// 圆盘太阳点：外圈柔光（径向渐变从核心半径到 5.5pt）
    let sunDotGlow: Color
    /// 错误文字
    let danger: Color
    /// 输入框底色
    let fieldBackground: Color
    /// 输入框描边
    let fieldBorder: Color
    /// 输入框文字
    let fieldText: Color
    /// 输入框占位符
    let fieldPlaceholder: Color

    init(_ colors: ThemeColors) {
        isDay = colors.isDay
        background = Color(hex: colors.background.hex)
        surface = Color(hex: colors.surface.hex)
        onSurface = Color(hex: colors.onSurface.hex)
        onSurfaceVariant = Color(hex: colors.onSurfaceVariant.hex)
        outlineVariant = Color(hex: colors.outlineVariant.hex)
        primary = Color(hex: colors.primary.hex)
        onPrimary = Color(hex: colors.onPrimary.hex)
        sunArc = Color(hex: colors.sunArc.hex)
        sunDot = Color(hex: colors.sunDot.hex)
        sunDotHighlight = Color(hex: colors.sunDotHighlight.hex)
        sunDotGlow = Color(hex: colors.sunDotGlow.hex)
        danger = Color(hex: colors.danger.hex)
        fieldBackground = Color(hex: colors.fieldBackground.hex)
        fieldBorder = Color(hex: colors.fieldBorder.hex)
        fieldText = Color(hex: colors.fieldText.hex)
        fieldPlaceholder = Color(hex: colors.fieldPlaceholder.hex)
    }

    static let day = ThemePalette(ThemeColors.day)
    static let night = ThemePalette(ThemeColors.night)

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
