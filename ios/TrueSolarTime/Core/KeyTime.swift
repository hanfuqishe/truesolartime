import Foundation

/// 一段关键时间，按「真太阳时的当天第几分钟」表示（0…1439，可跨午夜）。
struct TakeBand: Equatable {
    let startMinute: Int
    let endMinute: Int

    static let minutesPerDay = 24 * 60

    var lengthMinutes: Int { WeatherParsing.floorMod(endMinute - startMinute, Self.minutesPerDay) }

    /// `minuteOfDay` 是否落在这段里（含起点、不含终点，支持跨午夜）。
    func contains(minuteOfDay: Double) -> Bool {
        guard minuteOfDay.isFinite else { return false }
        let offset = WeatherParsing.floorMod(
            Int(minuteOfDay.rounded(.down)) - startMinute,
            Self.minutesPerDay
        )
        return offset < lengthMinutes
    }

    var startText: String {
        String(format: "%02d:%02d", startMinute / 60, startMinute % 60)
    }

    var endText: String {
        String(format: "%02d:%02d", endMinute / 60, endMinute % 60)
    }

    var text: String { "\(startText)-\(endText)" }
}

/// 页面上的 Cold or Mild / Hot or Mild，决定时间轴色带用绿还是红。
enum TakeTemperature: String {
    case coldOrMild
    case hotOrMild

    var label: String {
        switch self {
        case .coldOrMild: return "寒或溫"
        case .hotOrMild: return "熱或溫"
        }
    }
}

/// 网页上抓到的关键时间。
struct TakeTimeSchedule: Equatable {
    let bands: [TakeBand]
    let temperature: TakeTemperature?

    /// 当前真太阳时落在哪一段里；不在任何一段时返回 nil。
    func band(containing minuteOfDay: Double) -> TakeBand? {
        bands.first { $0.contains(minuteOfDay: minuteOfDay) }
    }
}

/// 从「西格瑪食療」页面解析「服用時間 Take Time」。
///
/// 规则与 Android 版一致：页面给出的时间一律当作**真太阳时**，不做任何换算；
/// 只在页面那段文字里找 `HH:MM-HH:MM` 形式的区间，标记只认英文
/// `Cold or Mild` / `Hot or Mild`（分别对应绿、红）。
enum TakeTimeParsing {

    static let pageURL = URL(string: "https://www.duosuccess.com/tcm/001a01080301b01a.htm")!

    private static let anchor = "Take Time"
    private static let windowChars = 400
    private static let rangePattern = #"(\d{1,2}):(\d{2})\s*[-~–—至]\s*(\d{1,2}):(\d{2})"#

    /// 每天只在 01:00–05:00 之间挑一个随机时刻同步一次。
    static let syncWindowStartMinute = 60
    static let syncWindowEndMinute = 300

    /// 缓存有效期：7 天。超过就当作「没有关键时间」，只画轴线不着色。
    static let validSeconds: TimeInterval = 7 * 24 * 60 * 60

    /// 失败后隔多久重试。
    static let retrySeconds: TimeInterval = 60 * 60

    static func parse(html: String) -> TakeTimeSchedule? {
        let text = html
            .replacingOccurrences(of: "<[^>]*>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&#160;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")

        let source: String
        if let range = text.range(of: anchor, options: .caseInsensitive) {
            let start = text.distance(from: text.startIndex, to: range.lowerBound)
            let end = min(text.count, start + windowChars)
            source = String(text.dropFirst(start).prefix(end - start))
        } else {
            source = text
        }

        let regex = try? NSRegularExpression(pattern: rangePattern)
        let ns = source as NSString
        var bands: [TakeBand] = []
        regex?.enumerateMatches(in: source, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match, match.numberOfRanges == 5 else { return }
            guard
                let start = minuteOf(
                    hour: Int(ns.substring(with: match.range(at: 1))),
                    minute: Int(ns.substring(with: match.range(at: 2)))
                ),
                let end = minuteOf(
                    hour: Int(ns.substring(with: match.range(at: 3))),
                    minute: Int(ns.substring(with: match.range(at: 4)))
                ),
                start != end
            else { return }
            bands.append(TakeBand(startMinute: start, endMinute: end))
        }
        let valid = bands.filter { (1..<TakeBand.minutesPerDay).contains($0.lengthMinutes) }
        guard !valid.isEmpty else { return nil }
        return TakeTimeSchedule(bands: valid, temperature: parseTemperature(source))
    }

    static func parseTemperature(_ text: String) -> TakeTemperature? {
        if text.range(of: "Cold or Mild", options: .caseInsensitive) != nil { return .coldOrMild }
        if text.range(of: "Hot or Mild", options: .caseInsensitive) != nil { return .hotOrMild }
        return nil
    }

    static func isInsideSyncWindow(offsetMinutes: Int) -> Bool {
        offsetMinutes >= syncWindowStartMinute && offsetMinutes < syncWindowEndMinute
    }

    static func encodeBands(_ bands: [TakeBand]) -> String {
        bands.map { "\($0.startMinute)-\($0.endMinute)" }.joined(separator: ",")
    }

    static func decodeBands(_ encoded: String?) -> [TakeBand]? {
        guard let encoded, !encoded.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let bands: [TakeBand] = encoded.split(separator: ",").compactMap { part in
            let pair = part.split(separator: "-")
            guard pair.count == 2,
                  let start = Int(pair[0]),
                  let end = Int(pair[1])
            else { return nil }
            return TakeBand(startMinute: start, endMinute: end)
        }
        return bands.isEmpty ? nil : bands
    }

    private static func minuteOf(hour: Int?, minute: Int?) -> Int? {
        guard let hour, let minute else { return nil }
        guard (0...24).contains(hour), (0...59).contains(minute) else { return nil }
        return (hour * 60 + minute) % TakeBand.minutesPerDay
    }
}
