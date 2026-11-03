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
            return "\(hours) 小时 \(minutes) 分"
        }
        if minutes > 0 {
            return String(format: "%d 分 %02d 秒", minutes, rest)
        }
        return "\(rest) 秒"
    }

    /// 例如 "10 小时 54 分"。
    static func duration(_ seconds: Int?) -> String {
        guard let seconds else { return "--" }
        return String(format: "%d 小时 %02d 分", seconds / 3600, (seconds % 3600) / 60)
    }

    /// 倒计时，例如 "01:23:45"。
    static func countdown(_ seconds: Int) -> String {
        let safe = max(seconds, 0)
        return String(format: "%02d:%02d:%02d", safe / 3600, (safe % 3600) / 60, safe % 60)
    }

    static func dateWithWeekday(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: Int(SolarTimeMath.beijingOffsetSeconds)) ?? .current
        let components = calendar.dateComponents([.month, .day, .weekday], from: date)
        let weekdays = ["星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六"]
        let weekdayIndex = (components.weekday ?? 1) - 1
        return String(
            format: "%d 月 %d 日 · %@",
            components.month ?? 1,
            components.day ?? 1,
            weekdays[max(0, min(6, weekdayIndex))]
        )
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
