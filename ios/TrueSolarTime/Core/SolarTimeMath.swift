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

    /// 经度修正：当地经度相对**所在时区中央经线**的时差，单位秒。
    ///
    /// 时区偏移 offset 对应的中央经线是 offset / 240 度（+8 → 120°E，−5 → 75°W）。
    static func longitudeOffsetSecondsForZone(longitude: Double, offsetSeconds: Int) -> Double {
        longitude * 240.0 - Double(offsetSeconds)
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

    /// 把「某天真太阳时的第几分钟」换算成系统时刻。
    ///
    /// 关键时间与时辰都是以**真太阳时**给出的，要给本地通知排时间就得反解：
    /// 真太阳时 = UTC 当天秒数 + 经度 × 240 + 均时差，所以
    /// UTC 秒数 = 目标真太阳时秒数 − 经度 × 240 − 均时差。
    /// 均时差随日期缓慢变化，用它自己的解迭代两次就足够（误差 < 1 秒）。
    static func date(trueSolarMinuteOfDay: Double, on day: Date, longitude: Double) -> Date {
        let midnightUTC = startOfBeijingDayInUTC(day)
        let target = trueSolarMinuteOfDay * 60 - longitude * 240.0
        var guess = midnightUTC.addingTimeInterval(target)
        for _ in 0..<2 {
            let equationOfTime = solarPosition(guess).equationOfTimeSeconds
            guess = midnightUTC.addingTimeInterval(target - equationOfTime)
        }
        return guess
    }

    /// 北京日期当天 0 点对应的 UTC 时刻。
    static func startOfBeijingDayInUTC(_ date: Date) -> Date {        var beijingCalendar = Calendar(identifier: .gregorian)
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

    // MARK: - 当地标准时区（与 Android 版口径一致）

    /// 表里查不到国家时的近似：按经度每 15° 取整。
    static func approxZoneOffsetSeconds(longitude: Double) -> Int {
        Int(((longitude / 15.0).rounded()) * 3600.0)
    }

    /// 观测点的标准时区偏移（秒）：先查国家表，查不到按经度近似。
    static func standardZoneOffsetSeconds(countryCode: String?, longitude: Double) -> Int {
        ZoneTable.offsetSeconds(
            countryCode: countryCode,
            longitude: longitude,
            fallbackSeconds: approxZoneOffsetSeconds(longitude: longitude)
        )
    }

    /// 某瞬间在给定标准时区偏移下的当天秒数。
    static func localSecondsOfDay(_ date: Date, offsetSeconds: Int) -> Double {
        normalizeSeconds(date.timeIntervalSince1970 + Double(offsetSeconds))
    }

    /// 真太阳时相对「当地标准时间」的偏差，单位秒，范围 (-43200, 43200]。
    static func offsetFromLocalSeconds(_ date: Date, longitude: Double, offsetSeconds: Int) -> Double {
        let delta = trueSolarSecondsOfDay(date, longitude: longitude)
            - localSecondsOfDay(date, offsetSeconds: offsetSeconds)
        var normalized = (delta + secondsPerDay * 1.5).truncatingRemainder(dividingBy: secondsPerDay)
        if normalized <= 0 { normalized += secondsPerDay }
        return normalized - secondsPerDay / 2
    }

    /// 「某瞬间所在当地标准日期」对应的**UTC 零点**。
    ///
    /// 日出/日落/正午的分钟数公式是「相对 UTC 零点」的，所以基准必须取
    /// 那个 UTC 零点，而不是「当地零点对应的 UTC 时刻」（后者会整体偏掉一个时区）。
    static func startOfLocalDayInUTC(_ date: Date, offsetSeconds: Int) -> Date {
        let local = date.timeIntervalSince1970 + Double(offsetSeconds)
        let dayStartUTC = (local / secondsPerDay).rounded(.down) * secondsPerDay
        return Date(timeIntervalSince1970: dayStartUTC)
    }

    /// 计算某瞬间所属「当地标准日期」当天的日出、日落与正午。
    static func sunTimes(
        containing date: Date,
        latitude: Double,
        longitude: Double,
        offsetSeconds: Int
    ) -> SunTimes {
        let midnightUTC = startOfLocalDayInUTC(date, offsetSeconds: offsetSeconds)
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

    /// 把「某天当地真太阳时的第几分钟」换算成系统时刻（供本地通知排期用）。
    static func date(
        trueSolarMinuteOfDay: Double,
        on day: Date,
        longitude: Double,
        offsetSeconds: Int
    ) -> Date {
        let midnightUTC = startOfLocalDayInUTC(day, offsetSeconds: offsetSeconds)
        let target = trueSolarMinuteOfDay * 60 - longitude * 240.0
        var guess = midnightUTC.addingTimeInterval(target)
        for _ in 0..<2 {
            let equationOfTime = solarPosition(guess).equationOfTimeSeconds
            guess = midnightUTC.addingTimeInterval(target - equationOfTime)
        }
        return guess
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
