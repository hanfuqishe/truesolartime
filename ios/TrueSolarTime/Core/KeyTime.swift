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

    /// 界面上的说法（简体中文，与 Android / 鸿蒙一致）。
    var label: String {
        switch self {
        case .coldOrMild: return "冻或温"
        case .hotOrMild: return "热或温"
        }
    }

    /// 存进偏好设置的值（与 Android 的 `cold` / `hot` 对应）。
    var storageKey: String {
        switch self {
        case .coldOrMild: return "cold"
        case .hotOrMild: return "hot"
        }
    }

    static func fromStorageKey(_ raw: String?) -> TakeTemperature? {
        switch raw {
        case "cold", TakeTemperature.coldOrMild.rawValue: return .coldOrMild
        case "hot", TakeTemperature.hotOrMild.rawValue: return .hotOrMild
        default: return nil
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
/// 在「Take Time」锚点附近（以及兜底的全文里）找 `HH:MM-HH:MM` 形式的区间，
/// 温度标记先认英文 `Cold or Mild` / `Hot or Mild`（分别对应绿、红），
/// 英文缺失时再认中文「凍或溫 / 冻或温」「熱或溫 / 热或温」。
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
        let text = plainText(html: html)
        for source in windows(in: text) {
            let found = bands(in: source)
            if !found.isEmpty {
                return TakeTimeSchedule(bands: found, temperature: parseTemperature(source))
            }
        }
        return nil
    }

    /// HTML → 纯文本（去标签、还原常见实体）。纯函数，便于离线断言。
    static func plainText(html: String) -> String {
        html
            .replacingOccurrences(of: "<[^>]*>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&#160;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    /// 把服务器返回的字节解码成文本。
    ///
    /// 页面声明的是 UTF-8，但镜像站/历史页面可能混入 Big5/GBK 字节。Foundation 的严格 UTF-8
    /// 解码遇到**任何一个**非法字节就整串返回 nil —— 这正是「抓到了页面却解析不出关键时间」的一类
    /// 隐形失败（Android 的 `InputStreamReader` 会把坏字节替换成 U+FFFD 继续读，照样能匹配到
    /// ASCII 的时间段）。所以先严格 UTF-8，失败退 ISO-8859-1（逐字节无损映射），保证时间段与
    /// `Cold or Mild` 这些 ASCII 信息永远不会因为编码问题丢掉。
    static func decodeHTML(_ data: Data) -> String? {
        if let text = String(data: data, encoding: .utf8) { return text }
        if let text = String(data: data, encoding: .isoLatin1) { return text }
        return nil
    }

    /// 候选窗口：先在每个「Take Time」锚点后取 [windowChars] 个字符；一个锚点都没有时退回全文。
    /// 锚点可能出现在导航/目录里，所以逐处尝试，最后再兜一次全文（页面改版把时间段挪远也能救回来）。
    static func windows(in text: String) -> [String] {
        var starts: [Int] = []
        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(of: anchor, options: .caseInsensitive, range: searchRange) {
            starts.append(text.distance(from: text.startIndex, to: range.lowerBound))
            searchRange = range.upperBound..<text.endIndex
            if starts.count >= 8 { break }
        }
        guard !starts.isEmpty else { return [text] }
        var result: [String] = starts.map { start in
            let end = min(text.count, start + windowChars)
            return String(text.dropFirst(start).prefix(end - start))
        }
        result.append(text)
        return result
    }

    /// 从一段文字里取出所有 `HH:MM-HH:MM` 时间段（去重，长度 1…1439 分钟）。纯函数。
    static func bands(in source: String) -> [TakeBand] {
        let regex = try? NSRegularExpression(pattern: rangePattern)
        let ns = source as NSString
        var result: [TakeBand] = []
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
            let band = TakeBand(startMinute: start, endMinute: end)
            guard (1..<TakeBand.minutesPerDay).contains(band.lengthMinutes) else { return }
            guard !result.contains(band) else { return }
            result.append(band)
        }
        return result
    }

    static func parseTemperature(_ text: String) -> TakeTemperature? {
        if text.range(of: "Cold or Mild", options: .caseInsensitive) != nil { return .coldOrMild }
        if text.range(of: "Hot or Mild", options: .caseInsensitive) != nil { return .hotOrMild }
        // 中文兜底：页面把英文标记删掉时仍能着色（Android 只认英文，这里是严格超集）。
        if text.contains("凍或溫") || text.contains("冻或温") { return .coldOrMild }
        if text.contains("熱或溫") || text.contains("热或温") { return .hotOrMild }
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
