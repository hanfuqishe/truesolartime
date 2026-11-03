import Foundation

// 与 Android 版单元测试同源的数值自检。
// 用法：见 Scripts/verify.sh —— 无需 Xcode，直接用 swiftc 编译运行。

var failures = 0
var checks = 0

func expect(_ name: String, _ condition: Bool, _ detail: @autoclosure () -> String = "") {
    checks += 1
    if !condition {
        failures += 1
        print("  ✗ \(name) \(detail())")
    } else {
        print("  ✓ \(name)")
    }
}

func expectClose(_ name: String, _ actual: Double, _ expected: Double, tolerance: Double, unit: String = "") {
    let delta = abs(actual - expected)
    expect(name, delta <= tolerance, String(format: "actual=%.4f expected=%.4f delta=%.4f%@", actual, expected, delta, unit))
}

func date(_ iso: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    guard let parsed = formatter.date(from: iso) else {
        fatalError("无法解析时间：\(iso)")
    }
    return parsed
}

func minutesBetween(_ a: TimeOfDay, _ b: TimeOfDay) -> Double {
    Double(a.secondsOfDay - b.secondsOfDay) / 60.0
}

print("== 均时差（对照公开数据，容差 ±0.5 分钟）==")
let equationCases: [(String, Double)] = [
    ("2024-02-11T12:00:00Z", -14.2),
    ("2024-05-14T12:00:00Z", 3.7),
    ("2024-06-21T12:00:00Z", -1.8),
    ("2024-07-26T12:00:00Z", -6.5),
    ("2024-11-03T12:00:00Z", 16.5),
]
for (iso, expectedMinutes) in equationCases {
    let seconds = SolarTimeMath.solarPosition(date(iso)).equationOfTimeSeconds
    expectClose(iso, seconds / 60.0, expectedMinutes, tolerance: 0.5, unit: " min")
}

print("== 北京时差（2026-11-02 12:03 北京时间，东经 116.4074）==")
let november = date("2026-11-02T04:03:00Z")
let beijingOffset = SolarTimeMath.offsetFromBeijingSeconds(november, longitude: 116.4074)
expectClose("真太阳时比北京时间快约 127 秒", beijingOffset, 127.0, tolerance: 20.0, unit: " s")

print("== 日出日落（北京 39.9042N / 116.4074E）==")
let june = SolarTimeMath.sunTimes(containing: date("2024-06-21T04:00:00Z"), latitude: 39.9042, longitude: 116.4074)
if let sunrise = june.sunrise, let sunset = june.sunset {
    expectClose("夏至日出 04:46（北京时间）", minutesBetween(SolarTimeSnapshot.timeOfDayInBeijing(sunrise), TimeOfDay(hour: 4, minute: 46, second: 0)), 0, tolerance: 3.0, unit: " min")
    expectClose("夏至日落 19:46（北京时间）", minutesBetween(SolarTimeSnapshot.timeOfDayInBeijing(sunset), TimeOfDay(hour: 19, minute: 46, second: 0)), 0, tolerance: 3.0, unit: " min")
    expectClose("夏至昼长 15.0 小时", sunset.timeIntervalSince(sunrise) / 3600.0, 15.0, tolerance: 0.1, unit: " h")
} else {
    expect("夏至应正常给出日出日落", false, "polar=\(june.polar)")
}

let december = SolarTimeMath.sunTimes(containing: date("2024-12-21T04:00:00Z"), latitude: 39.9042, longitude: 116.4074)
if let sunrise = december.sunrise {
    expectClose("冬至日出 07:32（北京时间）", minutesBetween(SolarTimeSnapshot.timeOfDayInBeijing(sunrise), TimeOfDay(hour: 7, minute: 32, second: 0)), 0, tolerance: 3.0, unit: " min")
} else {
    expect("冬至应正常给出日出", false)
}

print("== 正午定义（真太阳时 12:00）==")
let noonOfNovember = SolarTimeMath.sunTimes(containing: november, latitude: 39.9042, longitude: 116.4074)
let noonTrueSolar = TimeOfDay(secondsOfDay: SolarTimeMath.trueSolarSecondsOfDay(noonOfNovember.solarNoon, longitude: 116.4074))
expectClose("真太阳时正午落在 12:00", abs(minutesBetween(noonTrueSolar, TimeOfDay(hour: 12, minute: 0, second: 0))), 0, tolerance: 0.1, unit: " min")

print("== 极区 ==")
let polarSummer = SolarTimeMath.sunTimes(containing: date("2024-06-21T04:00:00Z"), latitude: 78.0, longitude: 15.0)
expect("北纬 78° 夏至极昼", polarSummer.polar == .midnightSun && polarSummer.sunrise == nil)
let polarWinter = SolarTimeMath.sunTimes(containing: date("2024-12-21T04:00:00Z"), latitude: 78.0, longitude: 15.0)
expect("北纬 78° 冬至极夜", polarWinter.polar == .polarNight && polarWinter.sunset == nil)

print("== 十二时辰 ==")
let shichenCases: [(Double, Int)] = [(23 * 3600, 0), (30 * 60, 0), (3600, 1), (11 * 3600, 6), (13 * 3600, 7), (22.99 * 3600, 11)]
for (seconds, expected) in shichenCases {
    expect("\(Int(seconds)) 秒 → 第 \(expected) 个时辰", Shichen.index(of: seconds) == expected, "actual=\(Shichen.index(of: seconds))")
}
expect("子时范围", Shichen.rangeText(0) == "23:00 – 01:00", "actual=\(Shichen.rangeText(0))")
expect("午时范围", Shichen.rangeText(6) == "11:00 – 13:00", "actual=\(Shichen.rangeText(6))")
expect("11:00 为时初", Shichen.halfLabel(11 * 3600) == "初")
expect("12:00 为时正", Shichen.halfLabel(12 * 3600) == "正")
expect("距下个时辰 5400 秒", abs(Shichen.secondsToNextShichen(23.5 * 3600) - 5400) < 1e-6)

print("== GCJ-02 坐标转换 ==")
let gcjBeijing = CoordinateTransform.wgs84ToGcj02(latitude: 39.9042, longitude: 116.4074)
expectClose("北京 GCJ 纬度", gcjBeijing.latitude, 39.905603, tolerance: 1e-5)
expectClose("北京 GCJ 经度", gcjBeijing.longitude, 116.413642, tolerance: 1e-5)
let gcjShanghai = CoordinateTransform.wgs84ToGcj02(latitude: 31.2304, longitude: 121.4737)
expectClose("上海 GCJ 纬度", gcjShanghai.latitude, 31.228458, tolerance: 1e-5)
expectClose("上海 GCJ 经度", gcjShanghai.longitude, 121.478223, tolerance: 1e-5)
let gcjShenzhen = CoordinateTransform.wgs84ToGcj02(latitude: 22.5431, longitude: 114.0579)
expectClose("深圳 GCJ 经度", gcjShenzhen.longitude, 114.063014, tolerance: 1e-5)

let london = CoordinateTransform.wgs84ToGcj02(latitude: 51.5072, longitude: -0.1276)
expect("境外不加偏移", london.latitude == 51.5072 && london.longitude == -0.1276)

var roundTripError = 0.0
for (latitude, longitude) in [(39.9042, 116.4074), (31.2304, 121.4737), (43.8256, 87.6168), (29.6520, 91.1721)] {
    let converted = CoordinateTransform.wgs84ToGcj02(latitude: latitude, longitude: longitude)
    let back = CoordinateTransform.gcj02ToWgs84(latitude: converted.latitude, longitude: converted.longitude)
    roundTripError = max(roundTripError, max(abs(back.latitude - latitude), abs(back.longitude - longitude)))
}
expect("往返精度 < 1e-6", roundTripError < 1e-6, String(format: "error=%.2e", roundTripError))

print("== 底图自动选择 ==")
expect("北京 → 高德矢量", MapStyle.auto.effective(latitude: 39.9042, longitude: 116.4074) == .amapVector)
expect("伦敦 → OpenStreetMap", MapStyle.auto.effective(latitude: 48.8566, longitude: 2.3522) == .osm)
expect("手动指定不覆盖", MapStyle.amapSatellite.effective(latitude: 48.8566, longitude: 2.3522) == .amapSatellite)

print("== 成都正午（北京时间）==")
let chengdu = SolarTimeSnapshot.compute(date: date("2026-11-03T04:00:00Z"), latitude: 30.5728, longitude: 104.0668)
if let noon = chengdu.solarNoonBeijing {
    expect("成都真太阳时正午为 12:00", chengdu.solarNoonBeijing != nil && abs(minutesBetween(TimeOfDay(secondsOfDay: SolarTimeMath.trueSolarSecondsOfDay(SolarTimeMath.sunTimes(containing: date("2026-11-03T04:00:00Z"), latitude: 30.5728, longitude: 104.0668).solarNoon, longitude: 104.0668)), TimeOfDay(hour: 12, minute: 0, second: 0))) < 0.1)
    expect("成都正午落在北京时间 12:40–12:55", (TimeOfDay(hour: 12, minute: 40, second: 0).secondsOfDay...TimeOfDay(hour: 12, minute: 55, second: 0).secondsOfDay).contains(noon.secondsOfDay), "actual=\(noon.clockWithSeconds)")
}
let beijingCity = SolarTimeSnapshot.compute(date: date("2026-11-03T04:00:00Z"), latitude: 39.9042, longitude: 116.4074)
if let noon = beijingCity.solarNoonBeijing {
    expect("北京正午落在北京时间 11:50–12:05", (TimeOfDay(hour: 11, minute: 50, second: 0).secondsOfDay...TimeOfDay(hour: 12, minute: 5, second: 0).secondsOfDay).contains(noon.secondsOfDay), "actual=\(noon.clockWithSeconds)")
}

print("")
if failures == 0 {
    print("全部 \(checks) 项检查通过")
    exit(0)
} else {
    print("\(failures)/\(checks) 项检查失败")
    exit(1)
}
