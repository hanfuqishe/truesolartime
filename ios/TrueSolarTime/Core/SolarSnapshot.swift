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

/// 某一瞬间、某一地点的完整太阳时快照，UI 只消费这个对象。
struct SolarSnapshot {
    let trueSolarTime: TimeOfDay
    let beijingTime: TimeOfDay
    let beijingDateText: String
    /// 真太阳时比北京时间快多少秒，可正可负。
    let offsetSeconds: Double
    let longitudeOffsetSeconds: Double
    let equationOfTimeSeconds: Double
    let shichenIndex: Int
    let shichenName: String
    let shichenRange: String
    let shichenHalf: String
    let shichenQuarter: Int
    let secondsToNextShichen: Int
    let sunriseBeijing: TimeOfDay?
    let sunsetBeijing: TimeOfDay?
    let solarNoonBeijing: TimeOfDay?
    let sunriseTrueSolar: TimeOfDay?
    let sunsetTrueSolar: TimeOfDay?
    let daylightSeconds: Int?
    let polar: PolarState
    let altitudeDegrees: Double

    var isDay: Bool { altitudeDegrees > -0.833 }

    var nextShichenName: String { Shichen.name((shichenIndex + 1) % 12) }
}

enum SolarTimeSnapshot {

    static func compute(date: Date, latitude: Double, longitude: Double) -> SolarSnapshot {
        let trueSolarSeconds = SolarTimeMath.trueSolarSecondsOfDay(date, longitude: longitude)
        let sunTimes = SolarTimeMath.sunTimes(containing: date, latitude: latitude, longitude: longitude)

        let beijingTime = timeOfDayInBeijing(date)
        let shichenIndex = Shichen.index(of: trueSolarSeconds)

        let daylightSeconds: Int? = {
            guard let sunrise = sunTimes.sunrise, let sunset = sunTimes.sunset else { return nil }
            return Int(sunset.timeIntervalSince(sunrise).rounded())
        }()

        return SolarSnapshot(
            trueSolarTime: TimeOfDay(secondsOfDay: trueSolarSeconds),
            beijingTime: beijingTime,
            beijingDateText: TimeFormat.dateWithWeekday(date),
            offsetSeconds: SolarTimeMath.offsetFromBeijingSeconds(date, longitude: longitude),
            longitudeOffsetSeconds: SolarTimeMath.longitudeOffsetSeconds(longitude),
            equationOfTimeSeconds: SolarTimeMath.solarPosition(date).equationOfTimeSeconds,
            shichenIndex: shichenIndex,
            shichenName: Shichen.name(shichenIndex),
            shichenRange: Shichen.rangeText(shichenIndex),
            shichenHalf: Shichen.halfLabel(trueSolarSeconds),
            shichenQuarter: Shichen.quarterOfHalf(trueSolarSeconds),
            secondsToNextShichen: Int(Shichen.secondsToNextShichen(trueSolarSeconds).rounded()),
            sunriseBeijing: sunTimes.sunrise.map { timeOfDayInBeijing($0) },
            sunsetBeijing: sunTimes.sunset.map { timeOfDayInBeijing($0) },
            solarNoonBeijing: timeOfDayInBeijing(sunTimes.solarNoon),
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

    static func timeOfDayInBeijing(_ date: Date) -> TimeOfDay {
        TimeOfDay(secondsOfDay: SolarTimeMath.beijingSecondsOfDay(date))
    }
}
