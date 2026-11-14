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
    let placeLabel: String
    let districtName: DistrictNames?
    let trackingGps: Bool
    let waitingForFix: Bool
    let weather: WeatherSnapshot?
    /// 关键时间色段（0–24 时轴上的着色）。
    let keyBands: [TakeBand]
    /// 落在关键时段内时的高亮色；不在时段内传 nil。
    let keyHighlight: Color?
    /// 「39.9042°N 116.4074°E」，由调用方算好传入。
    let coordinates: String
    /// 天气取不到时的说明（例如「请求超时（15 秒）」）；有天气数据时为 nil。
    let weatherNote: String?

    /// 卡片宽度：先用「屏宽 − 左右内边距」当首帧估值，随后由 GeometryReader 量出的真实值覆盖。
    /// 若初值给 0，第一帧会按极小宽度算出超大字号，看起来就是卡片被撑出屏幕。
    @State private var cardWidth: CGFloat = UIScreen.main.bounds.width - 40

    private let cardPadding: CGFloat = 18
    private let columnGap: CGFloat = 12
    private let dividerWidth: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                standardColumn
                    .frame(maxWidth: .infinity, alignment: .leading)

                Rectangle()
                    .fill(.white.opacity(0.2))
                    .frame(width: dividerWidth, height: clockHeight * 0.72)
                    .padding(.horizontal, columnGap)

                solarColumn
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            dateAndWeatherRow
                .padding(.top, 8)

            HeroAxis(
                bands: keyBands,
                bandColor: keyHighlight ?? .white,
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
    }

    // MARK: - 两栏

    private var standardColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("UTC+8")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.8))
                Spacer(minLength: 4)
                Text(districtText)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            FittingClock(
                main: String(format: "%02d:%02d", snapshot.beijingTime.hour, snapshot.beijingTime.minute),
                seconds: String(format: "%02d", snapshot.beijingTime.second),
                color: .white,
                availableWidth: columnWidth
            )
            .padding(.top, 2)
        }
    }

    private var solarColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("真太阳时")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.8))
                Spacer(minLength: 4)
                Text("\(snapshot.shichenName) · \(snapshot.shichenHalf)")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }

            FittingClock(
                main: String(format: "%02d:%02d", snapshot.trueSolarTime.hour, snapshot.trueSolarTime.minute),
                seconds: String(format: "%02d", snapshot.trueSolarTime.second),
                color: keyHighlight ?? .white,
                availableWidth: columnWidth
            )
            .padding(.top, 2)
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
            Text(coordinates)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
        }
    }


    private var dateWeatherText: String {
        var parts: [String] = [snapshot.beijingDateText]
        if let weather {
            parts.append("\(weather.temperatureC)° \(weather.condition.label)")
            if let range = WeatherParsing.temperatureRange(weather.hourly, date: Date(), timeZone: .current) {
                parts.append("\(range.low)~\(range.high)°")
            }
        } else if let weatherNote, !weatherNote.isEmpty {
            parts.append(weatherNote)
        } else {
            parts.append("--")
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

    private var districtText: String {
        if waitingForFix { return "定位中…" }
        if let districtName {
            return districtName.full.count <= 12 ? districtName.full : districtName.short
        }
        return placeLabel
    }
}

private struct HeroCardWidthKey: PreferenceKey {
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
    let bandColor: Color
    /// 0…1
    let position: Double

    var body: some View {
        Canvas { context, size in
            let midY = size.height / 2
            let track = CGRect(x: 0, y: midY - 0.5, width: size.width, height: 1)
            context.fill(Path(track), with: .color(.white.opacity(0.25)))

            for band in bands {
                let start = CGFloat(band.startMinute) / CGFloat(TakeBand.minutesPerDay) * size.width
                let width = max(
                    CGFloat(band.lengthMinutes) / CGFloat(TakeBand.minutesPerDay) * size.width,
                    2
                )
                let rect = CGRect(x: start, y: midY - 1, width: width, height: 2)
                context.fill(Path(rect), with: .color(bandColor.opacity(0.9)))
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
                with: .color(.white.opacity(0.25))
            )
            context.fill(Path(ellipseIn: dot), with: .color(.white))
        }
    }
}

/// 六格逐时预报：现在 + 未来 5 个整点。
struct HourlyRow: View {

    let weather: WeatherSnapshot?
    let isDay: Bool

    private let slots = 6

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(points, id: \.epochSeconds) { point in
                VStack(spacing: 3) {
                    Text(label(for: point))
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                    Image(systemName: point.condition.symbol(isDay: isDayOfHour(point)))
                        .font(.system(size: 20))
                        .symbolRenderingMode(.multicolor)
                    Text("\(point.temperatureC)°")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.75))
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity)
            }

            if points.isEmpty {
                ForEach(0..<slots, id: \.self) { index in
                    VStack(spacing: 3) {
                        Text(index == 0 ? "现在" : "--")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.6))
                        Image(systemName: "questionmark")
                            .font(.system(size: 18))
                            .foregroundStyle(.white.opacity(0.5))
                        Text("--")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.6))
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
            return "现在"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "H时"
        return formatter.string(from: point.date)
    }

    private func isDayOfHour(_ point: WeatherHour) -> Bool {
        let hour = Calendar.current.component(.hour, from: point.date)
        return (6..<18).contains(hour)
    }
}
