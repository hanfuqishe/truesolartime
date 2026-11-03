import Foundation

enum PolarState: Equatable {
    case normal
    case midnightSun
    case polarNight
}

struct SolarPosition {
    /// 均时差：真太阳时减去平太阳时，单位秒。正值表示日晷快于钟表。
    let equationOfTimeSeconds: Double
    /// 太阳赤纬，单位度。
    let declinationDegrees: Double
}

struct SunTimes {
    let sunrise: Date?
    let sunset: Date?
    let solarNoon: Date
    let polar: PolarState
}

/// 真太阳时计算，公式与 Android 版一致（NOAA 太阳位置算法）。
enum SolarTimeMath {

    static let beijingLongitude = 120.0
    static let beijingOffsetSeconds = 8.0 * 3600.0

    private static let rad = Double.pi / 180.0
    private static let deg = 180.0 / Double.pi
    private static let secondsPerDay = 86400.0
    private static let sunriseZenithDegrees = 90.833

    static func solarPosition(_ date: Date) -> SolarPosition {
        let julianDay = date.timeIntervalSince1970 / secondsPerDay + 2_440_587.5
        let t = (julianDay - 2_451_545.0) / 36_525.0

        let meanLongitude = normalizeDegrees(280.46646 + t * (36000.76983 + t * 0.0003032))
        let meanAnomaly = normalizeDegrees(357.52911 + t * (35999.05029 - 0.0001537 * t))
        let eccentricity = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
        let omega = 125.04 - 1934.136 * t

        let meanObliquity = 23.0 + (26.0 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60.0) / 60.0
        let obliquity = meanObliquity + 0.00256 * cos(omega * rad)

        let tanHalfObliquity = tan(obliquity * rad / 2)
        let y = tanHalfObliquity * tanHalfObliquity
        let l0 = meanLongitude * rad
        let m = meanAnomaly * rad

        // 括号内的量以弧度表示，乘以 deg 得"度"，再乘 240 秒/度即为秒。
        let equationOfTimeRadians = y * sin(2 * l0)
            - 2 * eccentricity * sin(m)
            + 4 * eccentricity * y * sin(m) * cos(2 * l0)
            - 0.5 * y * y * sin(4 * l0)
            - 1.25 * eccentricity * eccentricity * sin(2 * m)

        let equationOfCenter = sin(m) * (1.914602 - t * (0.004817 + 0.000014 * t))
            + sin(2 * m) * (0.019993 - 0.000101 * t)
            + sin(3 * m) * 0.000289
        let apparentLongitude = meanLongitude + equationOfCenter - 0.00569 - 0.00478 * sin(omega * rad)
        let declination = asin(sin(obliquity * rad) * sin(apparentLongitude * rad)) * deg

        return SolarPosition(
            equationOfTimeSeconds: equationOfTimeRadians * 240.0 * deg,
            declinationDegrees: declination
        )
    }

    /// 某瞬间在给定经度上的真太阳时，返回当天秒数 [0, 86400)。
    static func trueSolarSecondsOfDay(_ date: Date, longitude: Double) -> Double {
        let utcSeconds = normalizeSeconds(date.timeIntervalSince1970)
        let equationOfTime = solarPosition(date).equationOfTimeSeconds
        return normalizeSeconds(utcSeconds + longitude * 240.0 + equationOfTime)
    }

    /// 北京时间（东八区固定偏移）当天的秒数。
    static func beijingSecondsOfDay(_ date: Date) -> Double {
        normalizeSeconds(date.timeIntervalSince1970 + beijingOffsetSeconds)
    }

    /// 真太阳时相对北京时间的偏差，单位秒，范围 (-43200, 43200]。
    static func offsetFromBeijingSeconds(_ date: Date, longitude: Double) -> Double {
        let delta = trueSolarSecondsOfDay(date, longitude: longitude) - beijingSecondsOfDay(date)
        var normalized = (delta + secondsPerDay * 1.5).truncatingRemainder(dividingBy: secondsPerDay)
        if normalized <= 0 { normalized += secondsPerDay }
        return normalized - secondsPerDay / 2
    }

    /// 经度修正：当地经度相对东经 120° 的时差，单位秒。
    static func longitudeOffsetSeconds(_ longitude: Double) -> Double {
        (longitude - beijingLongitude) * 240.0
    }

    /// 太阳高度角，单位度（不含大气折射修正）。
    static func solarAltitudeDegrees(_ date: Date, latitude: Double, longitude: Double) -> Double {
        let position = solarPosition(date)
        let hourAngle = (trueSolarSecondsOfDay(date, longitude: longitude) / 3600.0 - 12.0) * 15.0 * rad
        let lat = latitude * rad
        let dec = position.declinationDegrees * rad
        let sine = sin(lat) * sin(dec) + cos(lat) * cos(dec) * cos(hourAngle)
        return asin(min(max(sine, -1.0), 1.0)) * deg
    }

    /// 计算某瞬间所属北京日期当天的日出、日落与正午。
    static func sunTimes(containing date: Date, latitude: Double, longitude: Double) -> SunTimes {
        let midnightUTC = startOfBeijingDayInUTC(date)
        let reference = midnightUTC.addingTimeInterval(12 * 3600)
        let position = solarPosition(reference)
        let equationOfTimeMinutes = position.equationOfTimeSeconds / 60.0

        let lat = latitude * rad
        let dec = position.declinationDegrees * rad
        let solarNoonMinutes = 720.0 - 4.0 * longitude - equationOfTimeMinutes
        let solarNoon = midnightUTC.addingTimeInterval(solarNoonMinutes * 60)

        let cosHourAngle = cos(sunriseZenithDegrees * rad) / (cos(lat) * cos(dec)) - tan(lat) * tan(dec)
        if cosHourAngle > 1.0 || cosHourAngle < -1.0 {
            return SunTimes(
                sunrise: nil,
                sunset: nil,
                solarNoon: solarNoon,
                polar: cosHourAngle > 1.0 ? .polarNight : .midnightSun
            )
        }

        let hourAngleDegrees = acos(cosHourAngle) * deg
        let sunriseMinutes = 720.0 - 4.0 * (longitude + hourAngleDegrees) - equationOfTimeMinutes
        let sunsetMinutes = 720.0 + 4.0 * (hourAngleDegrees - longitude) - equationOfTimeMinutes

        return SunTimes(
            sunrise: midnightUTC.addingTimeInterval(sunriseMinutes * 60),
            sunset: midnightUTC.addingTimeInterval(sunsetMinutes * 60),
            solarNoon: solarNoon,
            polar: .normal
        )
    }

    /// 北京日期当天 0 点对应的 UTC 时刻。
    static func startOfBeijingDayInUTC(_ date: Date) -> Date {
        var beijingCalendar = Calendar(identifier: .gregorian)
        beijingCalendar.timeZone = TimeZone(secondsFromGMT: Int(beijingOffsetSeconds)) ?? .current
        let components = beijingCalendar.dateComponents([.year, .month, .day], from: date)

        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        var dayComponents = DateComponents()
        dayComponents.year = components.year
        dayComponents.month = components.month
        dayComponents.day = components.day
        dayComponents.hour = 0
        return utcCalendar.date(from: dayComponents) ?? date
    }

    private static func normalizeDegrees(_ value: Double) -> Double {
        let remainder = value.truncatingRemainder(dividingBy: 360.0)
        return remainder < 0 ? remainder + 360.0 : remainder
    }

    private static func normalizeSeconds(_ value: Double) -> Double {
        let remainder = value.truncatingRemainder(dividingBy: secondsPerDay)
        return remainder < 0 ? remainder + secondsPerDay : remainder
    }
}
