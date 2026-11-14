import Foundation

struct TimeOfDay: Equatable {
    let hour: Int
    let minute: Int
    let second: Int

    init(hour: Int, minute: Int, second: Int) {
        self.hour = hour
        self.minute = minute
        self.second = second
    }

    init(secondsOfDay: Double) {
        let total = Int(secondsOfDay.rounded())
        let wrapped = ((total % 86_400) + 86_400) % 86_400
        hour = wrapped / 3600
        minute = (wrapped % 3600) / 60
        second = wrapped % 60
    }

    var secondsOfDay: Int { hour * 3600 + minute * 60 + second }

    var clock: String { String(format: "%02d:%02d", hour, minute) }

    var clockWithSeconds: String { String(format: "%02d:%02d:%02d", hour, minute, second) }
}

/// 某一瞬间、某地点的完整太阳时快照，UI 只消费这个对象。
///
/// 「标准时间」一律指**观测地的法定标准时**（`ZoneTable` 给出的偏移），不再固定东八区。
struct SolarSnapshot {
    let trueSolarTime: TimeOfDay
    /// 当地标准时间。
    let standardTime: TimeOfDay
    /// 当地标准日期，例如「11月14日 周六」。
    let standardDateText: String
    /// 标准时区偏移（秒），例如 +28800 / -18000 / +19800（印度 +5:30）。
    let standardOffsetSeconds: Int
    /// 时区标签，例如「UTC+8」「UTC−5」「UTC+5:30」。
    let utcLabel: String
    /// 真太阳时比当地标准时间快多少秒，可正可负。
    let offsetSeconds: Double
    /// 经度修正：当地经度相对所在时区中央经线的时差，单位秒。
    let longitudeOffsetSeconds: Double
    let equationOfTimeSeconds: Double
    let shichenIndex: Int
    let shichenName: String
    let shichenRange: String
    let shichenHalf: String
    let shichenQuarter: Int
    let secondsToNextShichen: Int
    /// 日出/日落/上中天，当地标准时。
    let sunriseStandard: TimeOfDay?
    let sunsetStandard: TimeOfDay?
    let solarNoonStandard: TimeOfDay?
    let sunriseTrueSolar: TimeOfDay?
    let sunsetTrueSolar: TimeOfDay?
    let daylightSeconds: Int?
    let polar: PolarState
    let altitudeDegrees: Double

    var isDay: Bool { altitudeDegrees > -0.833 }

    var nextShichenName: String { Shichen.name((shichenIndex + 1) % 12) }

    /// 兼容旧代码里的命名（`beijingTime` = 现在会随观测地变化的标准时间）。
    var beijingTime: TimeOfDay { standardTime }
    var beijingDateText: String { standardDateText }
    var sunriseBeijing: TimeOfDay? { sunriseStandard }
    var sunsetBeijing: TimeOfDay? { sunsetStandard }
    var solarNoonBeijing: TimeOfDay? { solarNoonStandard }
}

enum SolarTimeSnapshot {

    static func compute(
        date: Date,
        latitude: Double,
        longitude: Double,
        countryCode: String? = nil
    ) -> SolarSnapshot {
        let offsetSeconds = SolarTimeMath.standardZoneOffsetSeconds(
            countryCode: countryCode,
            longitude: longitude
        )
        return compute(date: date, latitude: latitude, longitude: longitude, offsetSeconds: offsetSeconds)
    }

    static func compute(
        date: Date,
        latitude: Double,
        longitude: Double,
        offsetSeconds: Int
    ) -> SolarSnapshot {
        let trueSolarSeconds = SolarTimeMath.trueSolarSecondsOfDay(date, longitude: longitude)
        let sunTimes = SolarTimeMath.sunTimes(
            containing: date,
            latitude: latitude,
            longitude: longitude,
            offsetSeconds: offsetSeconds
        )

        let standardTime = TimeOfDay(
            secondsOfDay: SolarTimeMath.localSecondsOfDay(date, offsetSeconds: offsetSeconds)
        )
        let shichenIndex = Shichen.index(of: trueSolarSeconds)

        let daylightSeconds: Int? = {
            guard let sunrise = sunTimes.sunrise, let sunset = sunTimes.sunset else { return nil }
            return Int(sunset.timeIntervalSince(sunrise).rounded())
        }()

        func standard(_ instant: Date?) -> TimeOfDay? {
            guard let instant else { return nil }
            return TimeOfDay(secondsOfDay: SolarTimeMath.localSecondsOfDay(instant, offsetSeconds: offsetSeconds))
        }

        return SolarSnapshot(
            trueSolarTime: TimeOfDay(secondsOfDay: trueSolarSeconds),
            standardTime: standardTime,
            standardDateText: TimeFormat.dateWithWeekday(date, offsetSeconds: offsetSeconds),
            standardOffsetSeconds: offsetSeconds,
            utcLabel: TimeFormat.utcOffsetLabel(seconds: offsetSeconds),
            offsetSeconds: SolarTimeMath.offsetFromLocalSeconds(
                date,
                longitude: longitude,
                offsetSeconds: offsetSeconds
            ),
            longitudeOffsetSeconds: SolarTimeMath.longitudeOffsetSecondsForZone(
                longitude: longitude,
                offsetSeconds: offsetSeconds
            ),
            equationOfTimeSeconds: SolarTimeMath.solarPosition(date).equationOfTimeSeconds,
            shichenIndex: shichenIndex,
            shichenName: Shichen.name(shichenIndex),
            shichenRange: Shichen.rangeText(shichenIndex),
            shichenHalf: Shichen.halfLabel(trueSolarSeconds),
            shichenQuarter: Shichen.quarterOfHalf(trueSolarSeconds),
            secondsToNextShichen: Int(Shichen.secondsToNextShichen(trueSolarSeconds).rounded()),
            sunriseStandard: standard(sunTimes.sunrise),
            sunsetStandard: standard(sunTimes.sunset),
            solarNoonStandard: standard(sunTimes.solarNoon),
            sunriseTrueSolar: sunTimes.sunrise.map {
                TimeOfDay(secondsOfDay: SolarTimeMath.trueSolarSecondsOfDay($0, longitude: longitude))
            },
            sunsetTrueSolar: sunTimes.sunset.map {
                TimeOfDay(secondsOfDay: SolarTimeMath.trueSolarSecondsOfDay($0, longitude: longitude))
            },
            daylightSeconds: daylightSeconds,
            polar: sunTimes.polar,
            altitudeDegrees: SolarTimeMath.solarAltitudeDegrees(date, latitude: latitude, longitude: longitude)
        )
    }

    /// 兼容旧调用（东八区），供 Scripts/main.swift 的数值自检继续使用。
    static func timeOfDayInBeijing(_ date: Date) -> TimeOfDay {
        timeOfDay(date, offsetSeconds: Int(SolarTimeMath.beijingOffsetSeconds))
    }

    static func timeOfDay(_ date: Date, offsetSeconds: Int) -> TimeOfDay {
        TimeOfDay(secondsOfDay: SolarTimeMath.localSecondsOfDay(date, offsetSeconds: offsetSeconds))
    }
}
