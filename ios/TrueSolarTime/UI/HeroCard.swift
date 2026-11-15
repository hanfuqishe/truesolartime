import SwiftUI
import UIKit

/// 首页大卡片：与 Android 1.4.39 同款版面。
///
/// 左栏「当地标准时间」、右栏「真太阳时」，中间一道竖分割线；
/// 下面依次是「日期 · 天气 · 温度区间」+ 经纬度一行、0–24 时关键时间轴、六格逐时预报。
///
/// 时间字号遵守两条硬规则（与 Android / 鸿蒙一致）：
/// 1. **秒是半高**：秒字号恒为主字号的 1/2；
/// 2. **整段时间撑满栏宽**：按「00:00 + 半高秒」的实测宽度反推主字号，留 3% 余量。
struct HeroCard: View {

    let snapshot: SolarSnapshot
    /// 卡片左上角那一行城市名：调用方已经按三段式算好（区划名 → 预设城市名 → 「-」），这里只管显示。
    let districtName: String
    let weather: WeatherSnapshot?
    /// 关键时间色段（0–24 时轴上的着色）。
    let keyBands: [TakeBand]
    /// 时间轴色段的颜色：按网页要求的「冻/热」取绿/红；温度未标注时为 nil（不画色段）。
    let bandColor: Color?
    /// 真太阳时落在关键时段内时的字色（同色系、白天淡一档）；不在时段内传 nil。
    let inkColor: Color?
    /// 当前真太阳时是否落在某个关键时段内（决定圆点是否用色段颜色）。
    let inKeyTime: Bool
    /// 「39.9042°N 116.4074°E」，由调用方算好传入。
    let coordinates: String

    /// 卡片宽度：先用「屏宽 − 左右内边距」当首帧估值，随后由 GeometryReader 量出的真实值覆盖。
    /// 若初值给 0，第一帧会按极小宽度算出超大字号，看起来就是卡片被撑出屏幕。
    @State private var cardWidth: CGFloat = UIScreen.main.bounds.width - 40
    /// 顶部标签行的实测尺寸：宽度决定四档退化，高度决定竖分隔线的上端。
    @State private var labelRowSize: CGSize = .zero
    /// 时钟行的实测高度：竖分隔线的长度跟着它走（不写死）。
    @State private var clockRowHeight: CGFloat = 0

    private let cardPadding: CGFloat = 18
    private let columnGap: CGFloat = 12
    private let dividerWidth: CGFloat = 1
    /// 标签行的字号。卡片的字号是固定 `.system(size:)`（不跟 Dynamic Type，见 `CardLegibility`），
    /// 量宽度也用同一个字号，判档结果才与渲染一致。
    private static let labelFontSize: CGFloat = 12
    private static let labelFont = UIFont.systemFont(ofSize: HeroCard.labelFontSize)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 顶部标签行（`UTC+8` · 城市 · `真太阳时` · 时辰）是**整行一个逻辑单元**，
            // 与下面两列放在同一个 ZStack 里：档 0 时那条竖线要从标签行一路贯下来。
            // 分档规则见 `HeroRowTier`（与 Android `SmallRowLayout.cityRowTier` 逐条对应）。
            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 0) {
                    labelRow
                        .padding(.bottom, 2)
                        .background(
                            GeometryReader { proxy in
                                Color.clear.preference(key: HeroLabelRowSizeKey.self, value: proxy.size)
                            }
                        )

                    clockRow
                        .background(
                            GeometryReader { proxy in
                                Color.clear.preference(key: HeroClockRowHeightKey.self, value: proxy.size.height)
                            }
                        )
                }

                dividerLine
            }

            dateAndWeatherRow
                .padding(.top, 8)

            HeroAxis(
                bands: keyBands,
                bandColor: bandColor,
                // 只有「当前正落在关键时段内」时圆点才跟着色段变色，否则保持白色
                dotColor: inKeyTime ? (bandColor ?? HeroPalette.dot) : HeroPalette.dot,
                position: Double(snapshot.trueSolarTime.secondsOfDay) / 86_400
            )
            .frame(height: 11)
            .padding(.top, 12)

            HourlyRow(weather: weather, isDay: snapshot.isDay)
                .padding(.top, 12)
        }
        .padding(cardPadding)
        .background(
            RoundedRectangle(cornerRadius: Theme.heroCornerRadius, style: .continuous)
                .fill(snapshot.isDay ? Theme.dayGradient : Theme.nightGradient)
        )
        // 兜底：万一某个子视图算大了，也不许露到圆角卡片外面。
        .clipShape(
            RoundedRectangle(cornerRadius: Theme.heroCornerRadius, style: .continuous)
        )
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: HeroCardWidthKey.self, value: proxy.size.width)
            }
        )
        .onPreferenceChange(HeroCardWidthKey.self) { width in
            if abs(width - cardWidth) > 0.5 {
                cardWidth = width
            }
        }
        .onPreferenceChange(HeroLabelRowSizeKey.self) { size in
            if abs(size.width - labelRowSize.width) > 0.5 || abs(size.height - labelRowSize.height) > 0.5 {
                labelRowSize = size
            }
        }
        .onPreferenceChange(HeroClockRowHeightKey.self) { height in
            if abs(height - clockRowHeight) > 0.5 {
                clockRowHeight = height
            }
        }
    }

    // MARK: - 顶部标签行（四档退化）

    /// 当前档位。宽度全部用 `UIFont` 量（与渲染同一字号、同一字体），纯计算、无副作用。
    private var rowTier: HeroRowTier.Tier {
        HeroRowTier.tier(
            utcWidth: textWidth(snapshot.utcLabel),
            cityWidth: textWidth(districtName),
            labelWidth: textWidth(L("hero.trueSolar")),
            shichenWidth: textWidth(shichenText),
            rowWidth: labelRowWidth
        )
    }

    /// 整行可用宽度：优先用实测值（第一帧还没量到时退回「卡片内宽」的估值）。
    private var labelRowWidth: CGFloat {
        labelRowSize.width > 0 ? labelRowSize.width : rowContentWidth
    }

    private var shichenText: String {
        "\(snapshot.shichenName) · \(snapshot.shichenHalf)"
    }

    private func textWidth(_ text: String) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        return (text as NSString).size(withAttributes: [.font: Self.labelFont]).width
    }

    private var labelRow: some View {
        let tier = rowTier
        return HStack(spacing: HeroRowTier.showsSolarLabel(tier: tier) ? 0 : HeroRowTier.gap) {
            if HeroRowTier.showsSolarLabel(tier: tier) {
                // 档 0：左右两半各占整行一半（与下面两列等宽）。
                // 左半 `UTC` 贴左、城市贴右（贴着两半分界，尾部再让 6pt 不贴线）；
                // 右半「真太阳时」贴左（先让一个间距）、时辰贴右。
                HStack(spacing: HeroRowTier.gap) {
                    utcLabel
                        .fixedSize(horizontal: true, vertical: false)
                    cityLabel(alignment: .trailing)
                        .padding(.trailing, HeroRowTier.cityEndInset)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: HeroRowTier.gap) {
                    solarLabel
                        .fixedSize(horizontal: true, vertical: false)
                    shichenLabel(alignment: .trailing)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, HeroRowTier.gap)
            } else {
                // 档 1：收掉「真太阳时」—— `UTC` 贴左、城市在 UTC 与时辰之间居中、时辰贴右。
                // 档 2/3：再收掉 UTC —— 城市贴左、时辰贴右（档 3 时城市自然被省略号截尾）。
                if HeroRowTier.showsUTC(tier: tier) {
                    utcLabel
                        .fixedSize(horizontal: true, vertical: false)
                }
                cityLabel(alignment: HeroRowTier.cityCentered(tier: tier) ? .center : .leading)
                shichenLabel(alignment: .trailing)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var utcLabel: some View {
        Text(snapshot.utcLabel)
            .font(.system(size: Self.labelFontSize))
            .foregroundStyle(.white.opacity(0.8))
            .lineLimit(1)
    }

    private var solarLabel: some View {
        Text(L("hero.trueSolar"))
            .font(.system(size: Self.labelFontSize))
            .foregroundStyle(.white.opacity(0.8))
            .lineLimit(1)
    }

    /// 城市是这一行里唯一可压缩的文本：给它剩余宽度 + 指定对齐，放不下时尾部省略号。
    private func cityLabel(alignment: Alignment) -> some View {
        Text(districtName)
            .font(.system(size: Self.labelFontSize))
            .foregroundStyle(.white.opacity(0.7))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: alignment)
    }

    private func shichenLabel(alignment: Alignment) -> some View {
        Text(shichenText)
            .font(.system(size: Self.labelFontSize))
            .foregroundStyle(.white.opacity(0.7))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: alignment)
    }

    // MARK: - 竖分隔线

    /// 竖线几何：档 0 的总高度 = 标签行高 + 时钟行高（上端与「真太阳时」文字上沿齐平）；
    /// 其它档只覆盖时钟行。
    private var dividerGeometry: HeroRowTier.DividerGeometry {
        HeroRowTier.divider(
            tier: rowTier,
            labelRowHeight: labelRowSize.height,
            clockRowHeight: clockRowHeight,
            labelTopInset: labelTopInset
        )
    }

    /// 行盒里字形上沿之上的空白：上端要与**文字上沿**齐平，而不是行盒顶边。
    private var labelTopInset: CGFloat {
        max((Self.labelFont.lineHeight - Self.labelFontSize) / 2, 0)
    }

    private var dividerLine: some View {
        let geometry = dividerGeometry
        return Rectangle()
            .fill(.white.opacity(0.2))
            .frame(width: dividerWidth, height: geometry.height)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .offset(y: geometry.top)
            .allowsHitTesting(false)
    }

    // MARK: - 两栏时钟

    private var clockRow: some View {
        HStack(alignment: .top, spacing: 0) {
            FittingClock(
                main: String(format: "%02d:%02d", snapshot.beijingTime.hour, snapshot.beijingTime.minute),
                seconds: String(format: "%02d", snapshot.beijingTime.second),
                color: .white,
                availableWidth: columnWidth
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            // 原来这里放的是「1pt 线 + 左右各 12pt」的分隔块；线改成整块卡片的 overlay 之后，
            // 仍占同样的宽度，两列宽度与字号推算都不变。
            Color.clear
                .frame(width: dividerWidth + columnGap * 2, height: 0)

            FittingClock(
                main: String(format: "%02d:%02d", snapshot.trueSolarTime.hour, snapshot.trueSolarTime.minute),
                seconds: String(format: "%02d", snapshot.trueSolarTime.second),
                // 落在关键时段内用「冻/热」对应的绿/红，否则用常规强调色（白天淡金、夜里金）
                color: inkColor ?? HeroPalette.accent(isDay: snapshot.isDay),
                availableWidth: columnWidth
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - 日期 / 天气

    private var dateAndWeatherRow: some View {
        HStack(spacing: 8) {
            Text(dateWeatherText)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            // 空间不够同时显示「日期/天气」与经纬度时，隐藏经纬度（优先保住日期与天气）。
            // 与安卓 `SmallRowLayout.shouldShowTrailing`、鸿蒙 `coordinatesFit` 同一套规则。
            if showsCoordinates {
                Text(coordinates)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
        }
    }

    /// 这一行可用的内容宽度（卡片内宽）。
    private var rowContentWidth: CGFloat {
        max(cardWidth - cardPadding * 2, 0)
    }

    /// 日期/天气与经纬度能否并排：两者自然宽度 + 8pt 间距放得下才显示经纬度。
    private var showsCoordinates: Bool {
        guard !coordinates.isEmpty, rowContentWidth > 0 else { return false }
        let font = UIFont.systemFont(ofSize: 11)
        let dateWidth = (dateWeatherText as NSString).size(withAttributes: [.font: font]).width
        let coordWidth = (coordinates as NSString).size(withAttributes: [.font: font]).width
        return dateWidth + coordWidth + 8 <= rowContentWidth
    }


    private var dateWeatherText: String {
        var parts: [String] = [snapshot.beijingDateText]
        if let weather {
            parts.append("\(weather.temperatureC)° \(weather.condition.label)")
            if let range = WeatherParsing.temperatureRange(weather.hourly, date: Date(), timeZone: .current) {
                parts.append("\(range.low)~\(range.high)°")
            }
        } else {
            // 没有天气数据就显示半角减号（与 Android 的 `weather_unknown` 一致）。
            // 失败原因不占卡片：设置页「诊断」里有完整说明。
            parts.append("-")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - 尺寸

    private var columnWidth: CGFloat {
        guard cardWidth > 0 else { return 150 }
        let inner = cardWidth - cardPadding * 2
        return max((inner - dividerWidth - columnGap * 2) / 2, 80)
    }

    private var clockHeight: CGFloat {
        HeroClockMetrics.mainSize(availableWidth: columnWidth) * 1.25
    }
}

private struct HeroCardWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// 顶部标签行的实测尺寸（宽决定四档，高决定竖线的上端）。
private struct HeroLabelRowSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next.width > 0 || next.height > 0 {
            value = next
        }
    }
}

/// 时钟行的实测高度（竖线的长度跟着它走）。
private struct HeroClockRowHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// 时间字号的换算：与 Android 版同一套规则（按实测字宽反推，秒恒为主字号一半）。
enum HeroClockMetrics {

    /// 探针字号：用 100pt 量一次「00:00」和半高的「:00」，得到每 1pt 的宽度。
    private static let probe: CGFloat = 100

    private static let mainProbeWidth: CGFloat = {
        let font = probeFont(size: probe)
        return ("00:00" as NSString).size(withAttributes: [.font: font]).width
    }()

    private static let secondsProbeWidth: CGFloat = {
        let font = probeFont(size: probe / 2)
        return (":00" as NSString).size(withAttributes: [.font: font]).width
    }()

    private static let gapWidth: CGFloat = 0

    /// 探针字体必须和 SwiftUI 里 `.system(size:weight:design:.rounded).monospacedDigit()` 一致，
    /// 否则量出来的比例会偏小、字号偏大，最终把文字顶出卡片。
    /// （`kNumberSpacingType = 6`、`kMonospacedNumbersSelector = 0`，用字面量避免多引一个 CoreText。）
    static func probeFont(size: CGFloat) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: .medium)
        let rounded = base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor
        let features: [[UIFontDescriptor.FeatureKey: Int]] = [
            [.type: 6, .selector: 0]
        ]
        let described = rounded.addingAttributes([.featureSettings: features])
        return UIFont(descriptor: described, size: size)
    }

    /// 每 1pt 字号占多少宽度。
    static var widthRatio: CGFloat {
        (mainProbeWidth + secondsProbeWidth + gapWidth) / probe
    }

    /// 撑满可用宽度时的主字号（留 3% 余量，18…80 之间）。
    static func mainSize(availableWidth: CGFloat) -> CGFloat {
        guard availableWidth > 0, widthRatio > 0 else { return 42 }
        let fitted = availableWidth / widthRatio * 0.97
        return min(max(fitted, 16), 68)
    }
}

/// 一格时间：主字号「时:分」+ 半高「:秒」，整体撑满可用宽度。
struct FittingClock: View {

    let main: String
    let seconds: String
    let color: Color
    let availableWidth: CGFloat

    var body: some View {
        let mainSize = HeroClockMetrics.mainSize(availableWidth: availableWidth)
        let secondsSize = mainSize / 2

        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(main)
                .font(.system(size: mainSize, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .allowsTightening(true)
            Text(":" + seconds)
                .font(.system(size: secondsSize, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .allowsTightening(true)
                .baselineOffset(mainSize * 0.06)
        }
        // 关键：宽度必须由外层给定。用 `fixedSize()` + intrinsic 宽度会让卡片被内容撑到屏幕外。
        .frame(width: availableWidth, alignment: .leading)
        .frame(height: mainSize * 1.18, alignment: .bottom)
    }
}

/// 首页 0–24 时时间轴：白线 + 关键时段色段 + 当前时刻的柔光圆点（与 Android 同款）。
struct HeroAxis: View {

    let bands: [TakeBand]
    /// 关键时段色段的颜色（冻/热对应的绿/红）；nil 表示温度未标注，不画色段。
    let bandColor: Color?
    /// 当前时刻圆点的颜色：落在关键时段内时为淡金色，否则白色。
    let dotColor: Color
    /// 0…1
    let position: Double

    var body: some View {
        Canvas { context, size in
            let midY = size.height / 2
            let track = CGRect(x: 0, y: midY - 0.5, width: size.width, height: 1)
            context.fill(Path(track), with: .color(.white.opacity(0.25)))

            if let bandColor {
                for band in bands {
                    let start = CGFloat(band.startMinute) / CGFloat(TakeBand.minutesPerDay) * size.width
                    let width = max(
                        CGFloat(band.lengthMinutes) / CGFloat(TakeBand.minutesPerDay) * size.width,
                        2
                    )
                    let rect = CGRect(x: start, y: midY - 1, width: width, height: 2)
                    context.fill(Path(rect), with: .color(bandColor))
                }
            }

            let clamped = min(max(position, 0), 1)
            let radius: CGFloat = 5.5
            let center = CGPoint(x: CGFloat(clamped) * size.width, y: midY)
            let dot = CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            context.fill(
                Path(ellipseIn: dot.insetBy(dx: -2, dy: -2)),
                with: .color(dotColor.opacity(0.28))
            )
            context.fill(Path(ellipseIn: dot), with: .color(dotColor))
        }
    }
}

/// 六格逐时预报：现在 + 未来 5 个整点。
struct HourlyRow: View {

    let weather: WeatherSnapshot?
    let isDay: Bool

    private let slots = 6
    /// 天气图标的固定槽高。
    ///
    /// 不同 SF Symbol（太阳/云/雨）的自带高度并不一致，不给固定高度时
    /// 下面那行温度会被图标顶得高低不齐 —— 所以三行都钉在统一高度上。
    private let iconSlotHeight: CGFloat = 22
    private let labelSlotHeight: CGFloat = 13

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(points, id: \.epochSeconds) { point in
                VStack(spacing: 3) {
                    Text(label(for: point))
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                        .frame(height: labelSlotHeight)
                    Image(systemName: point.condition.symbol(isDay: isDayOfHour(point)))
                        .font(.system(size: 20))
                        .symbolRenderingMode(.multicolor)
                        .frame(height: iconSlotHeight)
                    Text("\(point.temperatureC)°")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.75))
                        .monospacedDigit()
                        .frame(height: labelSlotHeight)
                }
                .frame(maxWidth: .infinity)
            }

            if points.isEmpty {
                ForEach(0..<slots, id: \.self) { index in
                    VStack(spacing: 3) {
                        Text(index == 0 ? L("weather.now") : "-")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(height: labelSlotHeight)
                        // 无数据不用问号（看起来像出错），用一条横线占位；与 Android 的
                        // `ic_wx_unknown`（一条短横线）、鸿蒙的 `wx_unknown.svg` 一致。
                        Image(systemName: "minus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.45))
                            .frame(height: iconSlotHeight)
                        Text("-")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(height: labelSlotHeight)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var points: [WeatherHour] {
        let all = weather?.hourly ?? []
        guard !all.isEmpty else { return [] }
        let slots = WeatherParsing.slots(
            nowEpochSeconds: Int(Date().timeIntervalSince1970),
            zoneOffsetSeconds: TimeZone.current.secondsFromGMT(for: Date()),
            count: 6,
            stepHours: 1
        )
        return slots.compactMap { WeatherParsing.point(at: $0, in: all) }
    }

    private func label(for point: WeatherHour) -> String {
        let now = Date()
        let calendar = Calendar.current
        if calendar.isDate(point.date, equalTo: now, toGranularity: .hour) {
            return L("weather.now")
        }
        // 中文习惯写「15时」，英文写「15:00」—— 由本地化表决定，不再硬编码格式。
        let hour = Calendar.current.component(.hour, from: point.date)
        return Lf("weather.hour", hour)
    }

    private func isDayOfHour(_ point: WeatherHour) -> Bool {
        let hour = Calendar.current.component(.hour, from: point.date)
        return (6..<18).contains(hour)
    }
}
