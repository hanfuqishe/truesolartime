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
let chengdu = SolarTimeSnapshot.compute(date: date("2026-11-03T04:00:00Z"), latitude: 30.5728, longitude: 104.0668, countryCode: "cn")
if let noon = chengdu.solarNoonBeijing {
    expect("成都真太阳时正午为 12:00", chengdu.solarNoonBeijing != nil && abs(minutesBetween(TimeOfDay(secondsOfDay: SolarTimeMath.trueSolarSecondsOfDay(SolarTimeMath.sunTimes(containing: date("2026-11-03T04:00:00Z"), latitude: 30.5728, longitude: 104.0668).solarNoon, longitude: 104.0668)), TimeOfDay(hour: 12, minute: 0, second: 0))) < 0.1)
    expect("成都正午落在北京时间 12:40–12:55", (TimeOfDay(hour: 12, minute: 40, second: 0).secondsOfDay...TimeOfDay(hour: 12, minute: 55, second: 0).secondsOfDay).contains(noon.secondsOfDay), "actual=\(noon.clockWithSeconds)")
}
let beijingCity = SolarTimeSnapshot.compute(date: date("2026-11-03T04:00:00Z"), latitude: 39.9042, longitude: 116.4074, countryCode: "cn")
if let noon = beijingCity.solarNoonBeijing {
    expect("北京正午落在北京时间 11:50–12:05", (TimeOfDay(hour: 11, minute: 50, second: 0).secondsOfDay...TimeOfDay(hour: 12, minute: 5, second: 0).secondsOfDay).contains(noon.secondsOfDay), "actual=\(noon.clockWithSeconds)")
}

print("== 天气解析（Open-Meteo）==")
let weatherJSON = """
{"current":{"temperature_2m":13.4,"weather_code":3},
 "hourly":{"time":["2026-11-12T00:00","2026-11-12T01:00","2026-11-12T02:00"],
 "temperature_2m":[12.2,11.6,10.8],"weather_code":[0,1,3]}}
"""
let hourly = WeatherParsing.parseHourly(weatherJSON)
expect("解析出 3 个小时点", hourly.count == 3, "actual=\(hourly.count)")
expect("第一个点温度四舍五入", hourly.first?.temperatureC == 12, "actual=\(hourly.first?.temperatureC ?? -999)")
expect("weather code 0 → 晴", hourly.first?.condition == .clear)
expect("weather code 3 → 阴", hourly.last?.condition == .overcast)
if let current = WeatherParsing.parseCurrent(weatherJSON) {
    expect("当前气温取整", current.temperatureC == 13, "actual=\(current.temperatureC)")
    expect("当前天气码", current.code == 3)
} else {
    expect("解析当前天气", false)
}
let utcDay = Date(timeIntervalSince1970: 1_763_000_000)
if let range = WeatherParsing.temperatureRange(hourly, date: hourly.first!.date, timeZone: TimeZone(identifier: "UTC")!) {
    expect("当天最高 12 / 最低 11", range.high == 12 && range.low == 11, "actual=\(range.high)/\(range.low)")
} else {
    expect("当天温度区间", false)
}
// 本地时区对齐：北京（+8）的 20:30 落进 20:00 那个小时块
let slotsUTC = WeatherParsing.slots(
    nowEpochSeconds: 1_763_000_000, zoneOffsetSeconds: 8 * 3600, count: 3, stepHours: 1
)
expect("小时块按本地时区对齐", slotsUTC.count == 3 && slotsUTC[1] - slotsUTC[0] == 3600)
expect(
    "小时块起点是整点（本地）",
    WeatherParsing.floorMod(slotsUTC[0] + 8 * 3600, 3600) == 0,
    "actual=\(WeatherParsing.floorMod(slotsUTC[0] + 8 * 3600, 3600))"
)

print("== 关键时间（服用時間 Take Time）==")
let takeHTML = """
<td>服用時間 Take&nbsp;Time : 15:00-17:00　20:00-22:00　10:00-12:00　(凍或溫 Cold or Mild)</td>
"""
if let schedule = TakeTimeParsing.parse(html: takeHTML) {
    expect("解析出 3 段关键时间", schedule.bands.count == 3, "actual=\(schedule.bands.count)")
    expect("第一段 15:00-17:00", schedule.bands.first?.text == "15:00-17:00", "actual=\(schedule.bands.first?.text ?? "-")")
    expect("识别 Cold or Mild", schedule.temperature == .coldOrMild)
    let band = schedule.bands.first { $0.startMinute == 15 * 60 }
    expect("16:00 落在段内", band?.contains(minuteOfDay: 16 * 60) == true)
    expect("17:00 不在段内", band?.contains(minuteOfDay: 17 * 60) == false)
} else {
    expect("解析关键时间页面", false)
}
expect("Hot or Mild 用红色标记", TakeTimeParsing.parseTemperature("(Hot or Mild)") == .hotOrMild)
expect("没有标记时返回 nil", TakeTimeParsing.parseTemperature("(something else)") == nil)
let crossMidnight = TakeBand(startMinute: 23 * 60, endMinute: 60)
expect("跨午夜区间长度 120 分钟", crossMidnight.lengthMinutes == 120, "actual=\(crossMidnight.lengthMinutes)")
expect("00:30 落在跨午夜段", crossMidnight.contains(minuteOfDay: 30))
expect("02:00 不在跨午夜段", !crossMidnight.contains(minuteOfDay: 120))
expect(
    "区间编码可往返",
    TakeTimeParsing.decodeBands(TakeTimeParsing.encodeBands([TakeBand(startMinute: 900, endMinute: 1020)]))?
        .first == TakeBand(startMinute: 900, endMinute: 1020)
)
expect("同步窗口 01:00–05:00", TakeTimeParsing.isInsideSyncWindow(offsetMinutes: 60)
    && TakeTimeParsing.isInsideSyncWindow(offsetMinutes: 299)
    && !TakeTimeParsing.isInsideSyncWindow(offsetMinutes: 300))

print("== 区划名拼接 ==")
expect(
    "中文：市+区县",
    DistrictNaming.joinChinese(county: "宝山区", city: "上海市", region: "上海市")?.full == "上海市宝山区"
)
expect(
    "中文：省+县级市",
    DistrictNaming.joinChinese(county: "义乌市", city: nil, region: "浙江省")?.full == "浙江省义乌市"
)
expect(
    "中文：市辖区占位值不参与",
    DistrictNaming.joinChinese(county: "某县", city: "市辖区", region: "河北省")?.full == "河北省某县"
)
expect(
    "中文：区县已带上级前缀不重复",
    DistrictNaming.joinChinese(county: "上海市宝山区", city: "上海市", region: "上海市")?.full == "上海市宝山区"
)
expect(
    "英文：逗号拼接并去重",
    DistrictNaming.compose(parts: [nil, "Huangpu District", "Shanghai", "Shanghai"])?.full
        == "Huangpu District, Shanghai"
)
expect(
    "英文：最多三级",
    DistrictNaming.compose(parts: ["A", "B", "C", "D"])?.full == "A, B, C"
)
expect("英文：短名取最细一级", DistrictNaming.compose(parts: ["Huangpu District", "Shanghai"])?.short == "Huangpu District")
expect(
    "5 km 阈值",
    !DistrictNaming.shouldQuery(movedKm: 4.9, ageSeconds: 60)
        && DistrictNaming.shouldQuery(movedKm: 5.1, ageSeconds: 60)
)
expect(
    "30 天过期",
    DistrictNaming.shouldQuery(movedKm: 0, ageSeconds: 31 * 24 * 3600)
)
expect(
    "距离计算（上海→北京 ≈ 1067 km）",
    abs(DistrictNaming.distanceKm(31.2304, 121.4737, 39.9042, 116.4074) - 1067) < 15,
    String(format: "actual=%.1f", DistrictNaming.distanceKm(31.2304, 121.4737, 39.9042, 116.4074))
)

print("== 真太阳时 → 系统时刻（给本地通知排时间）==")
// 上海：真太阳时 15:00 应落在北京时间约 14:38（真太阳时快 21~22 分）
let shanghaiDay = date("2026-11-12T04:00:00Z")
let fifteen = SolarTimeMath.date(trueSolarMinuteOfDay: 15 * 60, on: shanghaiDay, longitude: 121.4737)
let backToSolar = SolarTimeMath.trueSolarSecondsOfDay(fifteen, longitude: 121.4737)
expectClose("往返一致（15:00 真太阳时）", backToSolar, 15 * 3600, tolerance: 1.5, unit: " 秒")
let beijingBack = SolarTimeMath.beijingSecondsOfDay(fifteen)
expectClose("对应北京时间 14:38 ±2 分", beijingBack, 14 * 3600 + 38 * 60, tolerance: 120, unit: " 秒")
let midnight = SolarTimeMath.date(trueSolarMinuteOfDay: 0, on: shanghaiDay, longitude: 121.4737)
expectClose(
    "往返一致（真太阳时 00:00）",
    SolarTimeMath.trueSolarSecondsOfDay(midnight, longitude: 121.4737),
    0,
    tolerance: 1.5,
    unit: " 秒"
)

// MARK: - 时区表（对齐 Android 的 ZoneTable）

func zoneOffset(_ country: String?, _ longitude: Double) -> Int {
    SolarTimeMath.standardZoneOffsetSeconds(countryCode: country, longitude: longitude)
}

expect("中国全境 +8（乌鲁木齐 87.6°E 不按经度算）", zoneOffset("cn", 87.6168) == 28_800, "得到 \(zoneOffset("cn", 87.6168))")
expect("香港 +8", zoneOffset("hk", 114.17) == 28_800)
expect("日本 +9", zoneOffset("jp", 139.69) == 32_400)
expect("印度 +5:30", zoneOffset("in", 77.2) == 19_800)
expect("尼泊尔 +5:45", zoneOffset("np", 85.3) == 20_700)
expect("英国 +0", zoneOffset("gb", -0.12) == 0)
expect("德国 +1", zoneOffset("de", 13.4) == 3_600)
expect("纽约 −5", zoneOffset("us", -74.006) == -18_000)
expect("芝加哥 −6", zoneOffset("us", -87.6) == -21_600)
expect("丹佛 −7", zoneOffset("us", -104.99) == -25_200)
expect("安克雷奇 −9", zoneOffset("us", -149.9) == -32_400)
expect("檀香山 −10", zoneOffset("us", -157.86) == -36_000)
expect("俄罗斯按经度分段 +7（82.9°E）", zoneOffset("ru", 82.9) == 25_200)
expect("未知国家按经度近似（100°E → +7）", zoneOffset(nil, 100.0) == 25_200, "得到 \(zoneOffset(nil, 100.0))")
expect("未知国家按经度近似（−74°E → −5）", zoneOffset(nil, -74.0) == -18_000, "得到 \(zoneOffset(nil, -74.0))")

let utcLabelCases: [(Int, String)] = [
    (28_800, "UTC+8"),
    (-18_000, "UTC−5"),
    (19_800, "UTC+5:30"),
    (0, "UTC+0"),
    (-34_200, "UTC−9:30")
]
for (seconds, expected) in utcLabelCases {
    let actual = TimeFormat.utcOffsetLabel(seconds: seconds)
    expect("UTC 标签 \(expected)", actual == expected, "得到 \(actual)")
}

let instant = date("2026-11-14T04:00:00Z")
let beijingZone = SolarTimeSnapshot.compute(
    date: instant, latitude: 39.9042, longitude: 116.4074, countryCode: "cn"
)
expect("北京标准时间 12:00", beijingZone.standardTime.hour == 12, "得到 \(beijingZone.standardTime.clock)")
expect("北京 UTC 标签 UTC+8", beijingZone.utcLabel == "UTC+8", "得到 \(beijingZone.utcLabel)")

let newYorkZone = SolarTimeSnapshot.compute(
    date: instant, latitude: 40.7128, longitude: -74.0060, countryCode: "us"
)
expect("纽约标准时间 23:00（前一日）", newYorkZone.standardTime.hour == 23, "得到 \(newYorkZone.standardTime.clock)")
expect("纽约 UTC 标签 UTC−5", newYorkZone.utcLabel == "UTC−5", "得到 \(newYorkZone.utcLabel)")

let mumbaiZone = SolarTimeSnapshot.compute(
    date: instant, latitude: 19.0760, longitude: 72.8777, countryCode: "in"
)
expect("孟买 UTC 标签 UTC+5:30", mumbaiZone.utcLabel == "UTC+5:30", "得到 \(mumbaiZone.utcLabel)")

// MARK: - 内置城市列表的时区（含境外城市，供真机切换验证）

// 回归：预设城市一定要把国家码带进 Place。
// 之前在 `usePreset` 里只传了经纬度和名字，国家码丢了，德里就被按经度近似算成 UTC+5。
if let delhi = Place.presets.first(where: { $0.label == "新德里" }) {
    let withoutCountry = Place(
        latitude: delhi.latitude,
        longitude: delhi.longitude,
        source: .manual,
        label: delhi.label
    )
    expect(
        "丢掉国家码会退化成 UTC+5（历史 bug）",
        TimeFormat.utcOffsetLabel(seconds: withoutCountry.standardOffsetSeconds) == "UTC+5",
        "得到 \(TimeFormat.utcOffsetLabel(seconds: withoutCountry.standardOffsetSeconds))"
    )
    expect(
        "预设自带的 countryCode 让德里是 UTC+5:30",
        TimeFormat.utcOffsetLabel(seconds: delhi.standardOffsetSeconds) == "UTC+5:30",
        "得到 \(TimeFormat.utcOffsetLabel(seconds: delhi.standardOffsetSeconds))"
    )
}

let expectedPresets: [(String, Int)] = [
    ("北京", 28_800), ("上海", 28_800), ("广州", 28_800), ("深圳", 28_800),
    ("成都", 28_800), ("西安", 28_800), ("哈尔滨", 28_800), ("乌鲁木齐", 28_800),
    ("拉萨", 28_800), ("香港", 28_800),
    ("檀香山", -36_000), ("洛杉矶", -28_800), ("纽约", -18_000),
    ("伦敦", 0), ("巴黎", 3_600), ("迪拜", 14_400),
    ("新德里", 19_800), ("东京", 32_400), ("新加坡", 28_800), ("悉尼", 36_000)
]
for (label, expected) in expectedPresets {
    guard let preset = Place.presets.first(where: { $0.label == label }) else {
        expect("内置城市 \(label) 存在", false, "列表里没有这个城市")
        continue
    }
    expect(
        "内置城市 \(label) 时区偏移 \(expected)",
        preset.standardOffsetSeconds == expected,
        "得到 \(preset.standardOffsetSeconds)（\(TimeFormat.utcOffsetLabel(seconds: preset.standardOffsetSeconds))）"
    )
}
expect("内置城市数量 ≥ 20", Place.presets.count >= 20, "实际 \(Place.presets.count)")

print("")
if failures == 0 {
    print("全部 \(checks) 项检查通过")
    exit(0)
} else {
    print("\(failures)/\(checks) 项检查失败")
    exit(1)
}
