import Foundation

/// 十二时辰：以真太阳时为准，每个时辰两小时，子时自 23:00 起。
enum Shichen {

    /// 十二个时辰名各自的本地化 key（简体「子」、繁體「子」、英文「Zi」）。
    static let nameKeys = [
        "shichen.zi", "shichen.chou", "shichen.yin", "shichen.mao",
        "shichen.chen", "shichen.si", "shichen.wu", "shichen.wei",
        "shichen.shen", "shichen.you", "shichen.xu", "shichen.hai",
    ]

    private static let secondsPerShichen = 7200.0

    /// 返回 0..11，0 为子时。传入真太阳时当天的秒数。
    static func index(of trueSolarSecondsOfDay: Double) -> Int {
        let shifted = positiveRemainder(trueSolarSecondsOfDay + 3600.0, 86400.0)
        return Int(shifted / secondsPerShichen) % 12
    }

    /// 单个时辰名，例如「子」/「Zi」。
    static func baseName(_ index: Int) -> String {
        let wrapped = ((index % 12) + 12) % 12
        return L(nameKeys[wrapped])
    }

    /// 带单位，例如「子时」/「子時」/「Zi hour」。
    static func name(_ index: Int) -> String {
        Lf("shichen.format", baseName(index))
    }

    /// 例如 "23:00 – 01:00"（纯数字，不需要翻译）。
    static func rangeText(_ index: Int) -> String {
        let start = (index * 2 + 23) % 24
        let end = (start + 2) % 24
        return String(format: "%02d:00 – %02d:00", start, end)
    }

    static func secondsIntoShichen(_ trueSolarSecondsOfDay: Double) -> Double {
        positiveRemainder(trueSolarSecondsOfDay + 3600.0, 86400.0).truncatingRemainder(dividingBy: secondsPerShichen)
    }

    static func secondsToNextShichen(_ trueSolarSecondsOfDay: Double) -> Double {
        secondsPerShichen - secondsIntoShichen(trueSolarSecondsOfDay)
    }

    /// 时初 / 时正，各占一个时辰的前后一小时（英文 early / late）。
    static func halfLabel(_ trueSolarSecondsOfDay: Double) -> String {
        secondsIntoShichen(trueSolarSecondsOfDay) < 3600.0
            ? L("shichen.halfEarly")
            : L("shichen.halfLate")
    }

    /// 刻：每 15 分钟一刻，返回 1..4。
    static func quarterOfHalf(_ trueSolarSecondsOfDay: Double) -> Int {
        let into = secondsIntoShichen(trueSolarSecondsOfDay)
        return Int((into.truncatingRemainder(dividingBy: 3600.0)) / 900.0) + 1
    }

    /// 下一个时辰交接的绝对时刻（均时差变化率极小，线性外推误差在 1 秒内）。
    static func nextBoundary(after date: Date, longitude: Double) -> Date {
        let remaining = secondsToNextShichen(SolarTimeMath.trueSolarSecondsOfDay(date, longitude: longitude))
        return date.addingTimeInterval(remaining)
    }

    private static func positiveRemainder(_ value: Double, _ modulus: Double) -> Double {
        let remainder = value.truncatingRemainder(dividingBy: modulus)
        return remainder < 0 ? remainder + modulus : remainder
    }
}
