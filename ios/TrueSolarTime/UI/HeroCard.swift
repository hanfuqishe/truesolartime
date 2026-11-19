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
    /// 定位不可用（未知态）：真太阳时 / 时辰 / 高度角 / 经纬度 / 天气 / 逐时全部占位。
    let isLocationUnknown: Bool
    /// 配色用的「当前是不是白天」：由主题设置决定（自动 = 日出日落，亮色 / 暗色 = 强制）。
    /// 只影响配色；卡片里的太阳弧、逐时图标的昼夜标记仍按真实时刻判断。
    let isDay: Bool
    /// 卡片左上角那一行城市名：调用方已经按三段式算好（区划名 → 预设城市名 → 「-」），这里只管显示。
    let districtName: String
    let weather: WeatherSnapshot?
    /// 这份界面**署名**用的来源（`AppModel.weatherSource`）：逐时行的步长必须与署名同源，
    /// 没有快照时（缓存过期 / 刚换城市）也照它的步长排格子。
    let weatherSource: WeatherSource
    /// 正有一次取数在飞（新地点还没有缓存时显示「更新中…」而不是旧数据）。
    let isWeatherLoading: Bool
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
                position: Double(snapshot.trueSolarTime.secondsOfDay) / 86_400,
                // **未知态保留色段、只隐藏「现在」圆点**（用户已确认的 A 方案）：
                // 色段是「关键时段标记」，与地点无关，没有数据时自然为空，不需要额外抑制逻辑；
                // 但圆点表达的是「此刻真太阳时在轴上的位置」，未知态没有可信时间，所以要藏起来。
                showsDot: !isLocationUnknown
            )
            .frame(height: 11)
            .padding(.top, 12)

            HourlyRow(weather: weather, weatherSource: weatherSource, isDay: isDay, isLocationUnknown: isLocationUnknown)
                .padding(.top, 12)

            // **卡片页脚署名**（合规要求）：WeatherKit 用 Apple 官方标识图（**恒 dark 版**，
            // 橙底/深蓝底都是浅色背景外的深色，深色字看不清），可点开法律页；其它源用 CC BY 文字。
            weatherAttributionFooter
                .padding(.top, 7)
        }
        // 页脚署名占了约 18pt：底部内边距相应收一点，逐时行间距不变。
        .padding(EdgeInsets(top: cardPadding, leading: cardPadding, bottom: cardPadding - 6, trailing: cardPadding))
        .background(
            RoundedRectangle(cornerRadius: Theme.heroCornerRadius, style: .continuous)
                .fill(isDay ? Theme.dayGradient : Theme.nightGradient)
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

    /// 卡片内页脚署名：整行宽、居中；标识图高 11pt（只缩高度，不裁切不改色）。
    @ViewBuilder private var weatherAttributionFooter: some View {
        let presentation = WeatherAttributionStore.shared.presentation(source: weatherSource, isDark: true)
        switch presentation {
        case .mark(_, _, let legal):
            if let markURL = presentation.cardMarkURL(), let url = URL(string: markURL),
               let link = URL(string: legal) {
                Link(destination: link) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFit().frame(height: 11)
                        default:
                            // 加载中 / 失败都不留空白：直接落到文字退化版。
                            Text(L("weather.attributionWeatherKit")).font(.system(size: 11))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            } else {
                Text(L("weather.attributionWeatherKit"))
                    .font(.system(size: 11))
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        case .text(let text, let link):
            if let link, let url = URL(string: link) {
                Link(text, destination: url)
                    .font(.system(size: 11))
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                Text(text)
                    .font(.system(size: 11))
                    .frame(maxWidth: .infinity, alignment: .center)
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

    /// 顶部右侧的时辰（`亥时` / `亥時` / `Zi hour`）。
    ///
    /// **不再带「初 / 正」后缀**：三端统一只显示时辰名（分隔符 ` · ` 连同后缀一起去掉，
    /// 不留悬空的点或多余空格）。`Shichen.halfLabel` 与 `snapshot.shichenHalf` 的底层计算
    /// 仍然保留（报时与自检还在用），只是不在这张卡片上显示。
    private var shichenText: String {
        isLocationUnknown ? Placeholders.short : snapshot.shichenName
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
            // 未知态：地名就是「定位不可用」，点它去系统设置里开定位权限。
            .onTapGesture {
                guard isLocationUnknown,
                      let url = URL(string: UIApplication.openSettingsURLString)
                else { return }
                UIApplication.shared.open(url)
            }
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

            if isLocationUnknown {
                // 未知态：`--:--:--`（半角连字符、拉丁字体、0.06em 字距、60% alpha）。
                // 用 .monospaced 保证宽度与真实时间接近，不会因为占位符而跳版。
                Text(Placeholders.time)
                    .font(.system(size: HeroClockMetrics.mainSize(availableWidth: columnWidth), design: .monospaced))
                    .tracking(HeroClockMetrics.mainSize(availableWidth: columnWidth) * 0.06)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                FittingClock(
                    main: String(format: "%02d:%02d", snapshot.trueSolarTime.hour, snapshot.trueSolarTime.minute),
                    seconds: String(format: "%02d", snapshot.trueSolarTime.second),
                    // 落在关键时段内用「冻/热」对应的绿/红，否则用常规强调色（白天淡金、夜里金）
                    color: inkColor ?? HeroPalette.accent(isDay: isDay),
                    availableWidth: columnWidth
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - 日期 / 天气

    private var dateAndWeatherRow: some View {
        HStack(spacing: 8) {
            Text(isLocationUnknown ? Placeholders.dash : dateWeatherText)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            // 空间不够同时显示「日期/天气」与经纬度时，隐藏经纬度（优先保住日期与天气）。
            // 与安卓 `SmallRowLayout.shouldShowTrailing`、鸿蒙 `coordinatesFit` 同一套规则。
            if showsCoordinates {
                Text(isLocationUnknown ? Placeholders.dash : coordinates)
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
            // 没有该地点的天气数据就显示半角减号（与 Android 的 `weather_unknown` 一致）；
            // 正在取数时显示「更新中…」，让「新地点还没有数据」和「一直取不到」能区分开。
            // 失败原因不占卡片：设置页「诊断」里有完整说明。
            parts.append(isWeatherLoading ? L("weather.updating") : "-")
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

/// 首页 0–24 时时间轴：白线 + 关键时段色段 + 当前时刻的**径向渐变圆点**（与 Android 同款）。
///
/// **未知态（定位不可用）保留色段、只隐藏圆点** —— 这是用户确认过的决定，别「顺手」把色段也去掉：
/// 色段是「关键时段」这一与地点无关的标记（没有数据时 `bands`/`bandColor` 自然是空，就什么都不画），
/// 而圆点表示「此刻真太阳时落在轴上哪一格」，未知态没有可信时间，所以只藏它。
struct HeroAxis: View {

    let bands: [TakeBand]
    /// 关键时段色段的颜色（冻/热对应的绿/红）；nil 表示温度未标注，不画色段。
    let bandColor: Color?
    /// 当前时刻圆点的颜色：落在关键时段内时为淡金色，否则白色。
    let dotColor: Color
    /// 0…1
    let position: Double
    /// 是否画「现在」圆点（未知态为 false；色段不受影响）。
    let showsDot: Bool

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

            // 未知态：只跳过圆点，**色段照画**（见类型注释里的决定说明）。
            guard showsDot else { return }

            let clamped = min(max(position, 0), 1)
            // **一个径向渐变圆**（与 Android 完全一致）：半径 5.5pt，色标 0 / 0.5 / 1，
            // alpha 1.0 / 0.45 / 0 —— 边缘快速淡出，视觉核心只有约 2.75pt，比原来那笔
            // 「实心 + 外扩平铺柔光」更小更柔（用户反馈旧画法偏大）。
            let style = NowDotStyle.shared
            let radius = style.radius
            let center = CGPoint(x: CGFloat(clamped) * size.width, y: midY)
            let dot = CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            let stops = zip(style.stops, style.alphas).map { location, alpha in
                Gradient.Stop(color: dotColor.opacity(alpha), location: CGFloat(location))
            }
            context.fill(
                Path(ellipseIn: dot),
                with: .radialGradient(Gradient(stops: stops), center: center, startRadius: 0, endRadius: radius)
            )
        }
    }
}

/// 六格逐时预报：首格永远是「现在」，之后按**数据源自己的步长**往后取。
///
/// - 主源 Open-Meteo 是 1 小时粒度 → 6 格覆盖 6 小时（现在 / 22时 / 23时 / 0时 / 1时 / 2时）；
/// - 备用源 7Timer! 是 3 小时粒度 → 6 格覆盖 18 小时（现在 / 23时 / 2时 / 5时 / 8时 / 11时）。
///
/// 槽位数量永远是 6，变的是格子之间的距离；标签一律用该采样点的实际本地小时数，
/// 与 Android `HeroExtras.hourCells` / 鸿蒙逐时行同一套规则。
struct HourlyRow: View {

    let weather: WeatherSnapshot?
    /// 署名用的来源（与页面底部署名同一份判定）：没有快照时按它的步长排格子。
    let weatherSource: WeatherSource
    /// 配色用的白天/夜间（主题设置决定）。逐时图标自己的昼夜仍按该格的真实小时判断。
    let isDay: Bool
    /// 定位不可用（未知态）：保留六格，首格「现在」+ 按系统时间逐小时，温度 `-°`、不画图标。
    let isLocationUnknown: Bool

    /// 槽位数量：**永远 6 个**，不随数据源变化。
    private let slotCount = 6
    /// 天气图标的固定槽高。
    ///
    /// 不同 SF Symbol（太阳/云/雨）的自带高度并不一致，不给固定高度时
    /// 下面那行温度会被图标顶得高低不齐 —— 所以三行都钉在统一高度上。
    private let iconSlotHeight: CGFloat = 22
    private let labelSlotHeight: CGFloat = 13

    /// 一格的全部内容（标签、图标、温度）。
    private struct Cell: Identifiable {
        let slot: WeatherSlot
        let label: String
        let condition: WeatherCondition?
        /// 该格图标该按白天还是夜间画。**不是**主题的「亮色 / 暗色」，而是该刻的真实昼夜：
        /// 「现在」格用当前时刻（图标与温度都来自实时读数），其余格用采样点的真实时刻。
        let isDay: Bool
        let temperatureC: Int?

        var id: Int { slot.epochSeconds }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(cells) { cell in
                VStack(spacing: 3) {
                    Text(cell.label)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(cell.condition == nil ? 0.6 : 0.75))
                        .lineLimit(1)
                        .frame(height: labelSlotHeight)

                    if let condition = cell.condition {
                        Image(systemName: condition.symbol(isDay: cell.isDay))
                            .font(.system(size: 20))
                            .symbolRenderingMode(.multicolor)
                            .frame(height: iconSlotHeight)
                    } else {
                        // 无数据不用问号（看起来像出错），用一条横线占位；与 Android 的
                        // `ic_wx_unknown`（一条短横线）、鸿蒙的 `wx_unknown.svg` 一致。
                        Image(systemName: "minus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.45))
                            .frame(height: iconSlotHeight)
                    }

                    Text(cell.temperatureC.map { "\($0)°" } ?? (isLocationUnknown ? Placeholders.temperature : "-"))
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(cell.temperatureC == nil ? 0.6 : 0.75))
                        .monospacedDigit()
                        .frame(height: labelSlotHeight)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    /// 当前要画的 6 格：首格是当前时刻之前最近的那个采样点，之后每格前进 `stepHours` 小时。
    ///
    /// 步长**只从快照的来源（没有快照时从署名那一份来源）推**，不再写 `?? 1`：
    /// 7Timer! 的署名配上 1 小时槽位，就是用户报的那个 bug。
    /// 「现在」格的图标与温度都来自实时读数（`slotReadings` 里统一处理），
    /// 3 小时源的采样点可能是几小时前的，不能拿它当「现在」。
    private var cells: [Cell] {
        let now = Date()
        if isLocationUnknown {
            // 未知态：六格占位（系统时间逐小时、跨午夜自然回绕），温度 `-°`，图标 nil（同尺寸占位）。
            let slots = LocationUnknown.hourlySlots(nowEpochSeconds: Int(now.timeIntervalSince1970), count: slotCount)
            return slots.map { slot in
                let hour = Calendar.current.component(.hour, from: slot.date)
                return Cell(
                    slot: slot,
                    label: slot.isNow ? L("weather.now") : Lf("weather.hour", hour),
                    condition: nil,
                    isDay: false,
                    temperatureC: nil
                )
            }
        }
        let readings = WeatherParsing.slotReadings(
            points: weather?.hourly ?? [],
            nowEpochSeconds: Int(now.timeIntervalSince1970),
            zoneOffsetSeconds: TimeZone.current.secondsFromGMT(for: now),
            count: slotCount,
            stepHours: WeatherSnapshot.slotStepHours(weather, source: weatherSource),
            currentTemperatureC: weather?.temperatureC,
            currentCode: weather?.code
        )
        let isDayNow = isDayOf(now)

        return readings.map { reading in
            let label: String
            if reading.slot.isNow {
                label = L("weather.now")
            } else {
                label = Lf("weather.hour", Calendar.current.component(.hour, from: reading.slot.date))
            }
            return Cell(
                slot: reading.slot,
                label: label,
                condition: reading.condition,
                // 「现在」格的图标是实时天气，昼夜也必须是此刻的；其余格用采样点自己的时刻。
                isDay: reading.slot.isNow ? isDayNow : isDayOf(reading.pointDate),
                temperatureC: reading.temperatureC
            )
        }
    }

    /// 某一格是否白天：按该刻的本地小时粗略判断（与 Android `weatherIconRes(isDay = hour in 6..17)` 一致）。
    private func isDayOf(_ date: Date?) -> Bool {
        guard let date else { return isDay }
        let hour = Calendar.current.component(.hour, from: date)
        return (6..<18).contains(hour)
    }
}
