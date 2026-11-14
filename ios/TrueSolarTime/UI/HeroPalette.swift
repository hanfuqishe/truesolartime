import SwiftUI

/// 首页大卡片的配色：与 Android 的 `HeroPalette`（MainScreen.kt）逐值对应。
///
/// 关键时间的配色规则（与安卓完全一致）：
/// - 时间轴上的关键时段色段：按网页要求的「冻/热」取绿/红；白天用深一档，夜里用常规色；
/// - 当前真太阳时落在某段关键时间内：真太阳时数字换成同色系的绿/红（白天淡一档）；
/// - 圆点：落在关键时间内取**色段颜色**，否则白色。
enum HeroPalette {

    static let dot = Color.white
    static let label = Color.white.opacity(0.8)
    static let labelDim = Color.white.opacity(0.7)

    /// 十六进制转颜色（0xRRGGBB）。注意必须用浮点除法，否则整数相除会全部变成 0。
    private static func hex(_ value: UInt32, opacity: Double = 1.0) -> Color {
        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        return Color(red: red, green: green, blue: blue, opacity: opacity)
    }

    /// 夜里（深色底）的真太阳时字色。
    static let gold = hex(0xF5D68A)
    /// 白天（橙底）的真太阳时字色：淡金，比纯白暖一档。
    static let dayAccent = hex(0xFFE6B4)

    static let cold = hex(0x4CAF7D)
    static let hot = hex(0xD9534F)

    /// 白天的数字用与淡金同浓度的淡绿/淡红，深绿/深红压在橙底上发闷。
    static let coldInkOnDay = hex(0xBCF5CA)
    static let hotInkOnDay = hex(0xFFC4C9)

    /// 时间轴上的色段与圆点仍用深一档，淡色在橙底上几乎看不出边界。
    static let coldBandOnDay = hex(0x2E7D32)
    static let hotBandOnDay = hex(0xB3261E)

    /// 真太阳时的常规字色：白天淡金、夜里金色。
    static func accent(isDay: Bool) -> Color {
        isDay ? dayAccent : gold
    }

    /// 关键时段里真太阳时数字的颜色（温度未标注时为 nil）。
    static func ink(_ temperature: TakeTemperature?, isDay: Bool) -> Color? {
        switch temperature {
        case .some(.coldOrMild):
            return isDay ? coldInkOnDay : cold
        case .some(.hotOrMild):
            return isDay ? hotInkOnDay : hot
        case .none:
            return nil
        }
    }

    /// 时间轴上关键时段色段的颜色（也用作「落在时段内」时的圆点颜色）。
    static func band(_ temperature: TakeTemperature?, isDay: Bool) -> Color? {
        switch temperature {
        case .some(.coldOrMild):
            return isDay ? coldBandOnDay : cold
        case .some(.hotOrMild):
            return isDay ? hotBandOnDay : hot
        case .none:
            return nil
        }
    }
}
