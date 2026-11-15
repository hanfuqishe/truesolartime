import Foundation

enum TimeFormat {

    /// 带正负号的时长，例如 "+14 分 22 秒"、"-2 分 05 秒"。
    static func signedDuration(seconds: Double) -> String {
        (seconds < 0 ? "-" : "+") + minutesSeconds(seconds)
    }

    /// 不带符号的时长，例如 "14 分 22 秒"、"13 小时 0 分"。
    static func minutesSeconds(_ seconds: Double) -> String {
        let total = Int(abs(seconds).rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let rest = total % 60
        if hours > 0 {
            return Lf("time.hoursMinutes", hours, minutes)
        }
        if minutes > 0 {
            return Lf("time.minutesSeconds", minutes, rest)
        }
        return Lf("time.seconds", rest)
    }

    /// 例如 "10 小时 54 分"。
    static func duration(_ seconds: Int?) -> String {
        guard let seconds else { return "--" }
        return Lf("time.durationHoursMinutes", seconds / 3600, (seconds % 3600) / 60)
    }

    /// 倒计时，例如 "01:23:45"。
    static func countdown(_ seconds: Int) -> String {
        let safe = max(seconds, 0)
        return String(format: "%02d:%02d:%02d", safe / 3600, (safe % 3600) / 60, safe % 60)
    }

    /// 兼容旧调用（东八区）。
    static func dateWithWeekday(_ date: Date) -> String {
        dateWithWeekday(date, offsetSeconds: Int(SolarTimeMath.beijingOffsetSeconds))
    }

    /// 「11 月 14 日 周六」这种写法，按**观测地标准时区**与界面语言取日期。
    ///
    /// 用 `setLocalizedDateFormatFromTemplate` 而不是硬编码格式：中文出「11月14日周六」、
    /// 繁體出「11月14日 週六」、英文出「Sat, Nov 14」。
    static func dateWithWeekday(_ date: Date, offsetSeconds: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.locale
        formatter.timeZone = TimeZone(secondsFromGMT: offsetSeconds) ?? .current
        formatter.setLocalizedDateFormatFromTemplate("MMMdEEE")
        return formatter.string(from: date)
    }

    /// 「UTC+8」「UTC−5」「UTC+5:30」——负号用 U+2212，和安卓界面一致。
    static func utcOffsetLabel(seconds: Int) -> String {
        let sign = seconds < 0 ? "−" : "+"
        let absolute = abs(seconds)
        let hours = absolute / 3600
        let minutes = (absolute % 3600) / 60
        return minutes == 0
            ? "UTC\(sign)\(hours)"
            : String(format: "UTC%@%d:%02d", sign, hours, minutes)
    }

    static func coordinates(latitude: Double, longitude: Double) -> String {
        String(
            format: "%.4f°%@  %.4f°%@",
            abs(latitude), latitude >= 0 ? "N" : "S",
            abs(longitude), longitude >= 0 ? "E" : "W"
        )
    }

    static func clock(_ time: TimeOfDay?) -> String {
        time?.clock ?? "--:--"
    }
}
