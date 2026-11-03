import SwiftUI

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
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .fill(colorScheme == .dark ? Color(red: 0.114, green: 0.098, blue: 0.086) : Color(red: 1.0, green: 0.984, blue: 0.965))
            )
    }
}

extension View {
    func cardBackground() -> some View { modifier(CardBackground()) }
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
