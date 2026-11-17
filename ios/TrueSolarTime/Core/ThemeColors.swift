import Foundation

/// 主题里的一种颜色：`0xRRGGBB`。
///
/// 为什么颜色 token 放在 **Core**（纯 Foundation）而不是 UI 层：
/// 自检 `Scripts/main.swift` 只编译 Core，颜色一旦散落在各个视图里，就没有任何东西能守住
/// 「暗色主题下输入框必须跟着变暗」「文字和底色的对比度够不够」这类可读性问题 ——
/// 之前设置页的经纬度输入框用了系统 `.roundedBorder`，暗色主题下仍旧是白底浅字，正是这么来的。
///
/// UI 层用 `Color(hex:)` 把它转成 SwiftUI 颜色（见 `UI/Theme.swift` 的 `ThemePalette`）。
struct ThemeColor: Equatable {

    /// `0xRRGGBB`（高 8 位被忽略，避免调用方传 ARGB 时算出怪颜色）。
    let hex: UInt32

    init(hex: UInt32) {
        self.hex = hex & 0x00FF_FFFF
    }

    /// 0…1 的红通道（必须用浮点除法，整数相除会全变成 0）。
    var red: Double { Double((hex >> 16) & 0xFF) / 255.0 }
    var green: Double { Double((hex >> 8) & 0xFF) / 255.0 }
    var blue: Double { Double(hex & 0xFF) / 255.0 }

    /// `#RRGGBB` 文本：报告与诊断里好读。
    var hexText: String { String(format: "#%06X", hex) }

    /// WCAG 相对亮度（0 = 全黑，1 = 全白）。
    var relativeLuminance: Double {
        func channel(_ value: Double) -> Double {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    /// WCAG 对比度（1…21）：`foreground.contrast(with: background)`。
    ///
    /// 断言用它守「字看不清」：正文 ≥ 4.5（AA）、大字号 ≥ 3。1.0 表示完全同色（看不见）。
    func contrast(with other: ThemeColor) -> Double {
        let a = relativeLuminance
        let b = other.relativeLuminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

/// 一套主题的全部颜色语义 token（亮色 / 暗色各一套）。
///
/// 取值与原 `UI/Theme.swift` 里写死的 6 个基础色一致（色值对齐 Android `ui/theme/Theme.kt`），
/// 新增的是输入框与主色按钮上的文字：这两处以前交给系统外观（`.roundedBorder` / `.bordered`），
/// 在「强制亮色 / 强制暗色」与系统外观不一致时就会串色。
struct ThemeColors: Equatable {

    /// 这套主题是不是「白天/亮色」。
    let isDay: Bool

    // MARK: 页面与卡片

    /// 页面背景。
    let background: ThemeColor
    /// 卡片背景（也是输入框所在的分组的底色）。
    let surface: ThemeColor
    /// 主文字。
    let onSurface: ThemeColor
    /// 次要文字（说明、诊断行）。
    let onSurfaceVariant: ThemeColor
    /// 分隔线 / 弱描边。
    let outlineVariant: ThemeColor
    /// 强调色（按钮底色、开关、光标）。
    let primary: ThemeColor
    /// 强调色底上的文字（「应用坐标」「使用 GPS 定位」这类主按钮）。
    let onPrimary: ThemeColor
    /// 圆盘「地平线以上」那段白天弧的颜色（**实线**）。
    ///
    /// 白天主题用**淡金色** `#E8CFA0`：弧只是「路径示意」，压在近白的卡片底（`surface`）上
    /// 只有 **1.47:1**，几乎不发沉 —— 主色 `#B4550A` 是 4.80:1（用户连报两次「白天弧太重」），
    /// 中间的 `#CA8751` 也有 2.87:1，都还是太实。
    ///
    /// 淡到 1.5:1 之后，与夜晚虚线（`onSurfaceVariant` 50% ≈ `#A8A098` / 2.50:1）**不再是深浅之分**，
    /// 而是**色相之分**：弧是暖金（r−b = 0.28），虚线是中性灰（r−b = 0.06），加上实线 vs 虚线、
    /// 2.5pt vs 1.6pt，两者一眼分得开（自检断言的就是这条色相不变式）。
    ///
    /// 夜间主题**保持原样**（`#F5D68A`，等于 `primary`）：深底上再调浅就真的看不见了。
    let sunArc: ThemeColor
    /// 当前太阳点的**中段 / 主体**色（径向渐变从核心色过渡到它）。
    ///
    /// 白天主题用**亮金** `#D9A520`（与卡片 2.18:1、与淡金弧 1.48:1）。
    /// 夜间主题**保持原样**（`#F5D68A`，等于 `primary`）。
    let sunDot: ThemeColor
    /// 太阳点**径向渐变的中心**色（最亮的一档）。
    ///
    /// 白天 `#F5C842`（比主体再亮一档，中心有「亮点」感）；夜间同样用夜间金 `#F5D68A`。
    /// 渐变的外沿是**透明**的（不再有硬描边那一圈）：中心 → 中段 → 透明，边缘是柔的。
    let sunDotCore: ThemeColor
    /// 错误文字（坐标校验失败）。纯 `.red` 在暗色底上只有 4:1 左右，深浅两套各取一档。
    let danger: ThemeColor

    // MARK: 输入框（设置页经纬度）

    /// 输入框底色。**不跟系统外观走**：亮色是白底、暗色是比卡片略亮的深底。
    let fieldBackground: ThemeColor
    /// 输入框描边。
    let fieldBorder: ThemeColor
    /// 输入框里的文字。
    let fieldText: ThemeColor
    /// 占位符文字（「纬度」「经度」）。
    let fieldPlaceholder: ThemeColor

    /// 亮色（白天）主题。
    static let day = ThemeColors(
        isDay: true,
        background: ThemeColor(hex: 0xFFF8F1),
        surface: ThemeColor(hex: 0xFFFBF6),
        onSurface: ThemeColor(hex: 0x211A15),
        onSurfaceVariant: ThemeColor(hex: 0x52443A),
        outlineVariant: ThemeColor(hex: 0xD7C4B5),
        primary: ThemeColor(hex: 0xB4550A),
        onPrimary: ThemeColor(hex: 0xFFFFFF),
        // 白天弧：淡金色（只是路径示意）。卡片底 #FFFBF6 上 1.47:1，比主色（4.80:1）轻得多。
        // 不建议再浅到 #ECD6AC（1.38:1）—— 会低于「看得见」的下限 1.4。
        sunArc: ThemeColor(hex: 0xE8CFA0),
        // 太阳点：亮金（径向渐变的**中段**色）。与卡片 2.18:1、与淡金弧 1.48:1。
        // 不再有硬描边：可辨识度交给「中心更亮 + 边缘柔和淡出」。
        sunDot: ThemeColor(hex: 0xD9A520),
        // 太阳点径向渐变的**中心**色：比中段再亮一档，中心有个亮点。
        sunDotCore: ThemeColor(hex: 0xF5C842),
        danger: ThemeColor(hex: 0xB3261E),
        // 亮色保持原样：白底 + 浅棕描边 + 深字（原来的系统 `.roundedBorder` 就是白底）。
        fieldBackground: ThemeColor(hex: 0xFFFFFF),
        fieldBorder: ThemeColor(hex: 0xC9B7A7),
        fieldText: ThemeColor(hex: 0x211A15),
        fieldPlaceholder: ThemeColor(hex: 0x7A6A5E)
    )

    /// 暗色（夜间）主题。
    static let night = ThemeColors(
        isDay: false,
        background: ThemeColor(hex: 0x0B1220),
        surface: ThemeColor(hex: 0x16203A),
        onSurface: ThemeColor(hex: 0xE8EDF7),
        onSurfaceVariant: ThemeColor(hex: 0x9AA7BF),
        outlineVariant: ThemeColor(hex: 0x24304F),
        primary: ThemeColor(hex: 0xF5D68A),
        // 淡金底上用深字（白字在 #F5D68A 上只有 1.4:1，等于看不见）。
        onPrimary: ThemeColor(hex: 0x1A1408),
        // 夜间主题的白天弧**保持原样**（= primary #F5D68A）：深底上再调浅就真的看不见了。
        sunArc: ThemeColor(hex: 0xF5D68A),
        // 夜间主题的太阳点也**保持原样**（= primary #F5D68A）：深底上金色本来就是它。
        sunDot: ThemeColor(hex: 0xF5D68A),
        // 夜间径向渐变的中心色同样是夜间金（深底上再提亮就过曝了）。
        sunDotCore: ThemeColor(hex: 0xF5D68A),
        // 暗色底上的错误色要够亮（纯红在 #0B1220 上只有 4.3:1）。
        danger: ThemeColor(hex: 0xFF8A80),
        // 比卡片底色（#16203A）略亮一档：深色界面里输入框靠「比卡片亮」来暗示可输入，
        // 同时描边再抬一档，保证在暗色卡片上仍然看得出边界。
        fieldBackground: ThemeColor(hex: 0x1E2A47),
        fieldBorder: ThemeColor(hex: 0x3E4E72),
        fieldText: ThemeColor(hex: 0xE8EDF7),
        fieldPlaceholder: ThemeColor(hex: 0x8E9CB8)
    )

    /// 按「配色用的白天/夜间」取一套 token（`AppModel.uiIsDay`）。
    static func of(isDay: Bool) -> ThemeColors {
        isDay ? .day : .night
    }

    /// 所有 token 的（名字, 亮色, 暗色）三元组：自检用它逐对断言「两套都有值且不同」。
    var tokens: [(name: String, color: ThemeColor)] {
        [
            ("background", background),
            ("surface", surface),
            ("onSurface", onSurface),
            ("onSurfaceVariant", onSurfaceVariant),
            ("outlineVariant", outlineVariant),
            ("primary", primary),
            ("onPrimary", onPrimary),
            ("sunArc", sunArc),
            ("sunDot", sunDot),
            ("sunDotCore", sunDotCore),
            ("danger", danger),
            ("fieldBackground", fieldBackground),
            ("fieldBorder", fieldBorder),
            ("fieldText", fieldText),
            ("fieldPlaceholder", fieldPlaceholder)
        ]
    }

    /// 太阳点的**径向渐变**档位：中心（核心色）→ 中段（主体色，实心到 `sunRadius`）→ 外沿**透明**。
    ///
    /// 中间那一档的 location 取 `sunRadius / sunGlowRadius`（4 / 8.8 ≈ 0.45）：
    /// 实心部分正好到 4pt，之后柔和淡出到 8.8pt —— 跟逐时时间轴上「现在」圆点同一套思路
    /// （实心 + 柔光），只是这里用渐变代替「实心圆 + 18% 柔光圆」两笔，边缘没有硬边。
    /// Core 只给数据，UI（`SunDialCanvas`）把它转成 `Gradient`。
    var sunDotGradient: [(color: ThemeColor, alpha: Double, location: Double)] {
        [
            (sunDotCore, 1, 0),
            (sunDot, 1, Double(SunPathGeometry.sunRadius / SunPathGeometry.sunGlowRadius)),
            (sunDot, 0, 1)
        ]
    }
}
