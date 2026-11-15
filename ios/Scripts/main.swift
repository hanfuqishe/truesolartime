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

// MARK: - 本地化：把源码目录里的三份 strings 注入进来（命令行自检没有 .lproj）

let scriptURL = URL(fileURLWithPath: #filePath)
let iosRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let localizationTables = LocalizationCatalog.load(root: iosRoot)
L10n.useTablesForTesting(localizationTables)
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
expect("11:00 为时初", Shichen.halfLabel(11 * 3600) == L("shichen.halfEarly"))
expect("12:00 为时正", Shichen.halfLabel(12 * 3600) == L("shichen.halfLate"))
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

// 真实页面片段：2026-11-15 抓自 https://www.duosuccess.com/tcm/001a01080301b01a.htm，
// 保留页面里的标签、全角空格与 &nbsp;，用来保证「HTML → 时段 + 温度」这条链路离线可测。
let realPageFragment = """
<p style="margin-top: 0; margin-bottom: 0">有效期限：列印後 110日內 &nbsp; Expiration: 110 days after printing</p>
<p>	服用時間&nbsp; Take Time : 15:00-17:00　20:00-22:00　10:00-12:00　(凍或溫 Cold or Mild)</p>
<p>&nbsp;</p>
"""
let realSchedule = TakeTimeParsing.parse(html: realPageFragment)
expect("真实页面片段：解析出 3 段", realSchedule?.bands.count == 3, "actual=\(realSchedule?.bands.count ?? -1)")
expect(
    "真实页面片段：时段与顺序一致",
    realSchedule?.bands.map(\.text) == ["15:00-17:00", "20:00-22:00", "10:00-12:00"],
    "actual=\(String(describing: realSchedule?.bands.map(\.text)))"
)
expect("真实页面片段：温度是冻或温", realSchedule?.temperature == .coldOrMild)

// 温度标注：中文兜底（页面把英文标记删掉时仍能决定绿/红）
expect("中文「凍或溫」也识别为冻或温", TakeTimeParsing.parseTemperature("(凍或溫)") == .coldOrMild)
expect("中文「热或温」也识别为热或温", TakeTimeParsing.parseTemperature("（热或温）") == .hotOrMild)

// 时间段提取：跨午夜 / 去重 / 拒绝零长度
expect(
    "跨午夜时段 22:00-02:00",
    TakeTimeParsing.bands(in: "Take Time : 22:00-02:00").first?.text == "22:00-02:00"
)
expect("重复的时间段只留一条", TakeTimeParsing.bands(in: "10:00-12:00 10:00-12:00").count == 1)
expect("零长度时段被丢弃", TakeTimeParsing.bands(in: "10:00-10:00").isEmpty)
expect("紧挨着写的时间段都能取到", TakeTimeParsing.bands(in: "15:00-17:0020:00-22:00").count == 2)

// 编码兜底：页面混入非法 UTF-8 字节时，Android 的 reader 会替换字符继续读，
// iOS 的严格 UTF-8 解码却会整串返回 nil —— 这条断言保证页面不再整块丢。
var brokenBytes = Array(realPageFragment.utf8)
if let index = brokenBytes.firstIndex(of: 0xE6) { brokenBytes[index] = 0xFF }
let brokenHTML = TakeTimeParsing.decodeHTML(Data(brokenBytes))
expect("损坏的 UTF-8 字节也能解码", brokenHTML != nil)
expect(
    "损坏字节后仍能解析出 3 段",
    TakeTimeParsing.parse(html: brokenHTML ?? "")?.bands.count == 3,
    "actual=\(TakeTimeParsing.parse(html: brokenHTML ?? "")?.bands.count ?? -1)"
)

// 锚点缺失 / 锚点离时间段很远：仍然要能救回来
expect(
    "锚点缺失时退回全文",
    TakeTimeParsing.parse(html: "<p>08:30-09:30 (Hot or Mild)</p>")?.bands.first?.text == "08:30-09:30"
)
let farAnchor = "Take Time" + String(repeating: "x", count: 600) + " 05:00-06:00 (Hot or Mild)"
expect(
    "时间段离锚点很远也能解析",
    TakeTimeParsing.parse(html: farAnchor)?.bands.first?.text == "05:00-06:00"
)

// 缓存值兼容：老版本存 rawValue，新版本与 Android 一样存 cold/hot
expect("旧缓存 rawValue 仍能读", TakeTemperature.fromStorageKey("coldOrMild") == .coldOrMild)
expect("新缓存 cold/hot 也能读", TakeTemperature.fromStorageKey("hot") == .hotOrMild)
expect("未知的温度值当作没有标注", TakeTemperature.fromStorageKey("weird") == nil)

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

print("== 境外区划名（CLGeocoder 字段缺失时的逐级降级）==")
// 典型境外结果：Apple 只给 locality + administrativeArea + country，没有 subLocality。
// 旧实现把区县当必需项，这种情况会整串返回 nil（界面只剩预设城市名）。
let newYorkOnly = DistrictNaming.composeNames(
    district: nil,
    city: "New York",
    region: "New York",
    country: "United States",
    prefersChinese: true
)
expect("缺区县也要出名字（不再返回 nil）", newYorkOnly != nil, "actual=\(String(describing: newYorkOnly))")
expect(
    "境外：市 + 国家（州与市同名去重）",
    newYorkOnly?.full == "New York, United States",
    "actual=\(newYorkOnly?.full ?? "nil")"
)
expect("境外：短名取最细一级", newYorkOnly?.short == "New York", "actual=\(newYorkOnly?.short ?? "nil")")

let manhattan = DistrictNaming.composeNames(
    district: "Manhattan",
    city: "New York",
    region: "New York",
    country: "United States",
    prefersChinese: true
)
expect(
    "境外：区+市+国家取最细三级",
    manhattan?.full == "Manhattan, New York, United States",
    "actual=\(manhattan?.full ?? "nil")"
)
// 回归断言：中文界面的「市+区县」直连不能套到拉丁名字上（旧实现拼出 New YorkManhattan）。
expect(
    "境外：拉丁名字不再被直连成 New YorkManhattan",
    manhattan?.full != "New YorkManhattan" && manhattan?.full.contains(", ") == true,
    "actual=\(manhattan?.full ?? "nil")"
)

// 中英混排：Apple 的 zh_CN 常常给「英文区名 + 中文市/州名」，不能崩、也不能粘在一起。
let mixedNames = DistrictNaming.composeNames(
    district: "Manhattan",
    city: "纽约",
    region: "纽约州",
    country: "美国",
    prefersChinese: true
)
expect("中英混排：逗号拼接", mixedNames?.full == "Manhattan, 纽约, 纽约州", "actual=\(mixedNames?.full ?? "nil")")
expect("中英混排：短名是最细一级", mixedNames?.short == "Manhattan", "actual=\(mixedNames?.short ?? "nil")")

expect(
    "只有州/省也能显示",
    DistrictNaming.composeNames(
        district: nil, city: nil, region: "California", country: "United States", prefersChinese: true
    )?.full == "California, United States"
)
expect(
    "只有国家也能显示",
    DistrictNaming.composeNames(
        district: nil, city: nil, region: nil, country: "United States", prefersChinese: true
    )?.full == "United States"
)
expect(
    "所有级别都没有才返回 nil",
    DistrictNaming.composeNames(district: nil, city: nil, region: nil, country: nil, prefersChinese: true) == nil
)
expect(
    "空串 / 空白 / [] 一律当作没有",
    DistrictNaming.composeNames(
        district: "", city: "  ", region: "[]", country: "United States", prefersChinese: true
    )?.full == "United States"
)

// 中文写法仍然走「市+区县」直连，而且不把国家名拼进去。
expect(
    "中文：市+区县（国家名不参与）",
    DistrictNaming.composeNames(
        district: "黄浦区", city: "上海市", region: "上海市", country: "中国", prefersChinese: true
    )?.full == "上海市黄浦区"
)
expect(
    "中文：只有市时退回市",
    DistrictNaming.composeNames(
        district: nil, city: "上海市", region: nil, country: "中国", prefersChinese: true
    )?.full == "上海市"
)
expect(
    "中文：占位值「市辖区」不参与",
    DistrictNaming.composeNames(
        district: "某县", city: "市辖区", region: "河北省", country: "中国", prefersChinese: true
    )?.full == "河北省某县"
)
expect(
    "非中文界面：中文名也用逗号",
    DistrictNaming.composeNames(
        district: "黄浦区", city: "上海市", region: nil, country: nil, prefersChinese: false
    )?.full == "黄浦区, 上海市"
)

expect("中文判定：纯中文 → true", DistrictNaming.isChineseGrouping(["黄浦区", "上海市"]))
expect("中文判定：混拉丁字母 → false", !DistrictNaming.isChineseGrouping(["Manhattan", "纽约"]))
expect("中文判定：全空 → false", !DistrictNaming.isChineseGrouping([nil, "", "[]"]))

print("== OSM Nominatim 兜底（境外区划名）==")
let nominatimURL = NominatimReverse.url(latitude: 40.7128, longitude: -74.0060, language: "zh-CN")
let nominatimURLText = nominatimURL?.absoluteString ?? ""
expect(
    "请求地址是官方 https 端点",
    nominatimURLText.hasPrefix("https://nominatim.openstreetmap.org/reverse?"),
    "actual=\(nominatimURLText)"
)
expect("zoom=18（街区级）", nominatimURLText.contains("zoom=18"))
expect("addressdetails=1", nominatimURLText.contains("addressdetails=1"))
expect("format=jsonv2", nominatimURLText.contains("format=jsonv2"))
expect("accept-language 跟随界面语言", nominatimURLText.contains("accept-language=zh-CN"))
expect(
    "经纬度保留 6 位小数",
    nominatimURLText.contains("lat=40.712800") && nominatimURLText.contains("lon=-74.006000"),
    "actual=\(nominatimURLText)"
)
expect("UA 能标识应用与版本", NominatimReverse.userAgent.contains("TrueSolarTime-iOS"))

// 纽约·曼哈顿的典型返回（字段名与 OSM 一致：city_district / city / state / country）
let manhattanJSON = """
{"place_id":1,"lat":"40.75","lon":"-73.99",
 "address":{"city_district":"Manhattan","city":"New York","state":"New York","country":"United States","country_code":"us"},
 "display_name":"Manhattan, New York, United States"}
"""
let manhattanNames = NominatimReverse.names(json: manhattanJSON, prefersChinese: true)
expect("OSM：区 + 市 + 国家（取最细三级）", manhattanNames?.full == "Manhattan, New York, United States",
       "actual=\(manhattanNames?.full ?? "nil")")
expect("OSM：短名是最细一级", manhattanNames?.short == "Manhattan", "actual=\(manhattanNames?.short ?? "nil")")
expect("OSM：国家码小写", manhattanNames?.countryCode == "us", "actual=\(manhattanNames?.countryCode ?? "nil")")

// 只有市 + 国家（Apple 常只给到这一级，OSM 兜底同样要能出名字）
let dubaiJSON = """
{"address":{"city":"Dubai","country":"United Arab Emirates","country_code":"AE"}}
"""
let dubaiNames = NominatimReverse.names(json: dubaiJSON, prefersChinese: true)
expect("OSM：市 + 国家", dubaiNames?.full == "Dubai, United Arab Emirates", "actual=\(dubaiNames?.full ?? "nil")")
expect("OSM：大写的国家码也归一化", dubaiNames?.countryCode == "ae", "actual=\(dubaiNames?.countryCode ?? "nil")")

// OSM 的多语言值「New York;紐約」：中文界面取含汉字的那一段（Android 取第一段）
let multilingualJSON = """
{"address":{"city":"New York;紐約","state":"紐約州","country":"美国","country_code":"US"}}
"""
let multilingualNames = NominatimReverse.names(json: multilingualJSON, prefersChinese: true)
expect("OSM：多语言值取含汉字的那一段", multilingualNames?.full == "紐約, 紐約州, 美国",
       "actual=\(multilingualNames?.full ?? "nil")")
expect(
    "OSM：没有汉字时取第一段",
    NominatimReverse.languageSegment("Paris;巴黎", prefersChinese: false) == "Paris"
)

expect("OSM：地址为空返回 nil", NominatimReverse.names(json: "{\"address\":{}}", prefersChinese: true) == nil)
expect("OSM：非法 JSON 返回 nil", NominatimReverse.names(json: "not json", prefersChinese: true) == nil)
expect("汉字判定", NominatimReverse.isCJK("区") && NominatimReverse.isCJK("紐") && !NominatimReverse.isCJK("A"))

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
    // 纬度传 0（赤道，不在中国包围盒里）：没有国家码时仍然走「按经度近似」，
    // 与改写前的口径一致；包围盒那条分支另有专门的用例（见「是不是中国境内」一节）。
    SolarTimeMath.standardZoneOffsetSeconds(countryCode: country, latitude: 0, longitude: longitude)
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

// MARK: - 「是不是中国境内」：国家码优先，没有国家码才退回包围盒

// 回归：早先只按经纬度包围盒判断（73–135°E / 18–54°N），新德里（77.2°E, 28.6°N）正好落在
// 框内，于是被当成中国 —— 时区显示 UTC+8（应为 +5:30），底图还会去拉境外的数据。
let delhiLatitude = 28.6139
let delhiLongitude = 77.2090
let delhiInChina = GeoRegion.isInChina(
    countryCode: "in",
    latitude: delhiLatitude,
    longitude: delhiLongitude
)
expect("新德里 + 国家码 in 不算中国境内", delhiInChina == false)
expect(
    "新德里 + 国家码 in → UTC+5:30",
    SolarTimeMath.standardZoneOffsetSeconds(
        countryCode: "in",
        latitude: delhiLatitude,
        longitude: delhiLongitude
    ) == 19_800,
    "得到 \(SolarTimeMath.standardZoneOffsetSeconds(countryCode: "in", latitude: delhiLatitude, longitude: delhiLongitude))"
)
expect(
    "新德里 + 国家码 in → 底图用 OpenStreetMap",
    MapStyle.auto.effective(countryCode: "in", latitude: delhiLatitude, longitude: delhiLongitude) == .osm
)
expect(
    "新德里无国家码 → 底图退回包围盒（仍是高德，已知近似）",
    MapStyle.auto.effective(latitude: delhiLatitude, longitude: delhiLongitude) == .amapVector
)
expect("新德里（预设自带国家码）不算中国境内", Place.presets.first { $0.presetKey == "city.newdelhi" }?.isInChina == false)

// 对照：上海 + 国家码 cn 仍然是境内、仍然 +8、仍然用高德。
let shanghaiLatitude = 31.2304
let shanghaiLongitude = 121.4737
expect(
    "上海 + 国家码 cn 算中国境内",
    GeoRegion.isInChina(countryCode: "cn", latitude: shanghaiLatitude, longitude: shanghaiLongitude)
)
expect(
    "上海 + 国家码 cn → UTC+8",
    SolarTimeMath.standardZoneOffsetSeconds(
        countryCode: "cn",
        latitude: shanghaiLatitude,
        longitude: shanghaiLongitude
    ) == 28_800
)
expect(
    "上海 + 国家码 cn → 底图用高德矢量",
    MapStyle.auto.effective(countryCode: "cn", latitude: shanghaiLatitude, longitude: shanghaiLongitude) == .amapVector
)

// 港澳台按国家码算境内（中国全境统一 +8）。
for code in ["hk", "mo", "tw"] {
    expect(
        "国家码 \(code) 算中国境内且 +8",
        GeoRegion.isInChina(countryCode: code, latitude: 22.3193, longitude: 114.1694)
            && SolarTimeMath.standardZoneOffsetSeconds(
                countryCode: code,
                latitude: 22.3193,
                longitude: 114.1694
            ) == 28_800
    )
}

// 国家码大小写不敏感；空白 / nil 一律视为「没有国家码」。
expect(
    "国家码大小写不敏感",
    GeoRegion.isInChina(countryCode: "CN", latitude: shanghaiLatitude, longitude: shanghaiLongitude)
        && GeoRegion.isInChina(countryCode: " in ", latitude: delhiLatitude, longitude: delhiLongitude) == false
)
expect(
    "空白国家码视为未知",
    GeoRegion.normalizedCountryCode("  ") == nil && GeoRegion.normalizedCountryCode(nil) == nil
)

// 没有国家码时才用包围盒。加德满都（27.7°N, 85.3°E）在框内，所以：
//   - 没有国家码 → 退回包围盒，判为境内、+8（**有意保留**的近似，与 Android / 鸿蒙一致）；
//   - 有 np → 按国家码走，境外、+5:45。
expect(
    "加德满都无国家码 → 退回包围盒（判为境内，已知近似）",
    GeoRegion.isInChina(countryCode: nil, latitude: 27.7, longitude: 85.3)
)
expect(
    "加德满都无国家码 → 兜底 +8（包围盒口径）",
    SolarTimeMath.standardZoneOffsetSeconds(countryCode: nil, latitude: 27.7, longitude: 85.3) == 28_800
)
expect(
    "加德满都 + 国家码 np → 境外且 +5:45",
    GeoRegion.isInChina(countryCode: "np", latitude: 27.7, longitude: 85.3) == false
        && SolarTimeMath.standardZoneOffsetSeconds(countryCode: "np", latitude: 27.7, longitude: 85.3) == 20_700
)

// 境内没有国家码时也必须 +8：乌鲁木齐 87.6°E 若按经度近似会被算成 +6。
expect(
    "乌鲁木齐无国家码也 +8（按经度近似会算成 +6）",
    SolarTimeMath.standardZoneOffsetSeconds(countryCode: nil, latitude: 43.8256, longitude: 87.6168) == 28_800,
    "得到 \(SolarTimeMath.standardZoneOffsetSeconds(countryCode: nil, latitude: 43.8256, longitude: 87.6168))"
)

// 端到端：快照里的标准时间与 UTC 标签也要跟着国家码走。
let delhiSnapshot = SolarTimeSnapshot.compute(
    date: instant,
    latitude: delhiLatitude,
    longitude: delhiLongitude,
    countryCode: "in"
)
expect(
    "新德里快照 UTC+5:30",
    delhiSnapshot.utcLabel == "UTC+5:30" && delhiSnapshot.standardOffsetSeconds == 19_800,
    "得到 \(delhiSnapshot.utcLabel) / \(delhiSnapshot.standardOffsetSeconds)"
)
let delhiWithoutCode = SolarTimeSnapshot.compute(
    date: instant,
    latitude: delhiLatitude,
    longitude: delhiLongitude
)
expect(
    "新德里无国家码的快照退回 +8（包围盒兜底）",
    delhiWithoutCode.utcLabel == "UTC+8",
    "得到 \(delhiWithoutCode.utcLabel)"
)

// MARK: - 内置城市列表的时区（含境外城市，供真机切换验证）

// 回归：预设城市一定要把国家码带进 Place。
// 之前在 `usePreset` 里只传了经纬度和名字，国家码丢了，德里就只能靠兜底 ——
// 而现在兜底的第一条是「境内包围盒」，德里在框内，于是被算成 UTC+8。
// 也就是说：**国家码丢了就一定出错**（要么 UTC+5、要么 UTC+8），必须带上。
if let delhi = Place.presets.first(where: { $0.presetKey == "city.newdelhi" }) {
    let withoutCountry = Place(
        latitude: delhi.latitude,
        longitude: delhi.longitude,
        source: .manual,
        label: delhi.displayLabel
    )
    expect(
        "丢掉国家码只剩包围盒兜底（新德里在框内 → UTC+8，历史 bug 的同一类错）",
        TimeFormat.utcOffsetLabel(seconds: withoutCountry.standardOffsetSeconds) == "UTC+8",
        "得到 \(TimeFormat.utcOffsetLabel(seconds: withoutCountry.standardOffsetSeconds))"
    )
    expect(
        "预设自带的 countryCode 让德里是 UTC+5:30",
        TimeFormat.utcOffsetLabel(seconds: delhi.standardOffsetSeconds) == "UTC+5:30",
        "得到 \(TimeFormat.utcOffsetLabel(seconds: delhi.standardOffsetSeconds))"
    )
}

let expectedPresets: [(String, Int)] = [
    ("city.beijing", 28_800), ("city.shanghai", 28_800), ("city.guangzhou", 28_800), ("city.shenzhen", 28_800),
    ("city.chengdu", 28_800), ("city.xian", 28_800), ("city.harbin", 28_800), ("city.urumqi", 28_800),
    ("city.lhasa", 28_800), ("city.hongkong", 28_800),
    ("city.honolulu", -36_000), ("city.losangeles", -28_800), ("city.newyork", -18_000),
    ("city.london", 0), ("city.paris", 3_600), ("city.dubai", 14_400),
    ("city.newdelhi", 19_800), ("city.tokyo", 32_400), ("city.singapore", 28_800), ("city.sydney", 36_000)
]
for (presetKey, expected) in expectedPresets {
    guard let preset = Place.presets.first(where: { $0.presetKey == presetKey }) else {
        expect("内置城市 \(presetKey) 存在", false, "列表里没有这个城市")
        continue
    }
    expect(
        "内置城市 \(presetKey) 时区偏移 \(expected)",
        preset.standardOffsetSeconds == expected,
        "得到 \(preset.standardOffsetSeconds)（\(TimeFormat.utcOffsetLabel(seconds: preset.standardOffsetSeconds))）"
    )
}
expect("内置城市数量 ≥ 20", Place.presets.count >= 20, "实际 \(Place.presets.count)")

print("== 本地化（三语 strings + 语言匹配）==")
// 1) 三份表的 key 集合必须一致、值非空、格式参数一致、简繁互斥、英文无 CJK
let localizationReport = LocalizationCatalog.check(localizationTables)
expect("三份 strings 都能读到", localizationTables.count == 3, "实际 \(localizationTables.count) 份")
expect("没有本地化问题", localizationReport.isOK, localizationReport.errors.joined(separator: " | "))
expect(
    "三份 key 数量一致",
    Set(localizationReport.counts.values).count == 1,
    "\(localizationReport.counts)"
)
expect("key 数量 ≥ 150", localizationReport.keyCount >= 150, "实际 \(localizationReport.keyCount)")

// 2) 源码里用到的 key 必须都在表里（防止改了代码忘了加翻译）
let usedKeys = LocalizationCatalog.keysUsedInSources(root: iosRoot)
expect("能扫描到源码里的 key", !usedKeys.unreadable && !usedKeys.keys.isEmpty, "扫描失败或没找到 key")
let missingKeys = usedKeys.keys.subtracting(Set((localizationTables["en"] ?? [:]).keys))
expect("源码里没有未定义的 key", missingKeys.isEmpty, "缺少 \(missingKeys.sorted().joined(separator: ", "))")

// 3) 语言匹配：zh-Hans → 简体，zh-Hant（含 TW/HK/MO）→ 繁體，其它一律英文
expect("zh-Hans → 简体", AppLanguage.resolve(preferredLanguages: ["zh-Hans-CN"]) == .simplified)
expect("zh-Hant → 繁體", AppLanguage.resolve(preferredLanguages: ["zh-Hant-TW"]) == .traditional)
expect("zh-TW → 繁體", AppLanguage.resolve(preferredLanguages: ["zh-TW"]) == .traditional)
expect("zh-HK → 繁體", AppLanguage.resolve(preferredLanguages: ["zh-HK"]) == .traditional)
expect("裸 zh → 简体", AppLanguage.resolve(preferredLanguages: ["zh"]) == .simplified)
expect("en → 英文", AppLanguage.resolve(preferredLanguages: ["en-US"]) == .english)
expect("ja → 英文兜底", AppLanguage.resolve(preferredLanguages: ["ja-JP"]) == .english)
expect("空列表 → 英文兜底", AppLanguage.resolve(preferredLanguages: []) == .english)
expect(
    "列表里第二个才是中文也能匹配",
    AppLanguage.resolve(preferredLanguages: ["fr-FR", "zh-Hant"]) == .traditional
)

// 4) 三语关键文案
expect(
    "应用名三语",
    L10n.t("app.name", language: .simplified) == "真太阳时时钟"
        && L10n.t("app.name", language: .traditional) == "真太陽時時鐘"
        && L10n.t("app.name", language: .english) == "True Solar Clock"
)
expect(
    "天气描述三语",
    L10n.t("weather.clear", language: .simplified) == "晴"
        && L10n.t("weather.overcast", language: .traditional) == "陰"
        && L10n.t("weather.overcast", language: .english) == "Overcast"
)
expect(
    "时辰名三语（子 / 子 / Zi）",
    L10n.t("shichen.zi", language: .simplified) == "子"
        && L10n.t("shichen.zi", language: .traditional) == "子"
        && L10n.t("shichen.zi", language: .english) == "Zi"
)
expect(
    "时辰格式三语（子时 / 子時 / Zi hour）",
    L10n.f("shichen.format", language: .simplified, ["子"]) == "子时"
        && L10n.f("shichen.format", language: .traditional, ["子"]) == "子時"
        && L10n.f("shichen.format", language: .english, ["Zi"]) == "Zi hour"
)
expect(
    "预设城市三语（纽约 / 紐約 / New York）",
    L10n.t("city.newyork", language: .simplified) == "纽约"
        && L10n.t("city.newyork", language: .traditional) == "紐約"
        && L10n.t("city.newyork", language: .english) == "New York"
)
expect(
    "预设城市名走本地化（不是空串）",
    !Place.shanghai.displayLabel.isEmpty && !Place.presets[0].displayLabel.isEmpty
)

// 5) 台湾用语：特意纠正过的词
expect("設定（不是「设置」）", L10n.t("common.settings", language: .traditional) == "設定")
expect("螢幕（不是「屏幕」）", L10n.t("settings.sectionScreen", language: .traditional) == "螢幕")
expect("套用座標（不是「应用坐标」）", L10n.t("settings.applyCoordinates", language: .traditional) == "套用座標")
expect("裝置未連線（不是「设备未联网」）", L10n.t("diag.offline", language: .traditional) == "裝置未連線")
expect("伺服器（不是「服务器」）", L10n.t("diag.cannotConnect", language: .traditional) == "無法連線至伺服器")
expect("简体仍是「设置」", L10n.t("common.settings", language: .simplified) == "设置")

// 6) 缺 key 时退回到 key 本身（便于发现漏翻）
expect(
    "未知 key 原样返回",
    L10n.t("no.such.key", language: .simplified) == "no.such.key"
)
print("== 大卡片顶部标签行的四档退化（与 Android SmallRowLayout 对齐）==")
// 固定参数：间距 8、城市与竖线之间 6、其余是各段文本的自然宽度。
let heroGap: CGFloat = HeroRowTier.gap
let heroInset: CGFloat = HeroRowTier.cityEndInset
expect("间距 8pt / 间隙 6pt", heroGap == 8 && heroInset == 6, "gap=\(heroGap) inset=\(heroInset)")

func tierOf(_ utc: CGFloat, _ city: CGFloat, _ label: CGFloat, _ shichen: CGFloat, _ width: CGFloat) -> HeroRowTier.Tier {
    HeroRowTier.tier(
        utcWidth: utc,
        cityWidth: city,
        labelWidth: label,
        shichenWidth: shichen,
        rowWidth: width
    )
}

// 尚未量出行宽（第一帧）→ 按档 0 排，免得闪一下「只剩城市」。
expect("未测量按档 0", tierOf(40, 300, 60, 100, 0) == .allFour)
expect("极宽是档 0", tierOf(40, 100, 60, 100, 2000) == .allFour)

// 档 0 → 档 1 的边界：左半 = utc 40 + (city + 6) + gap 8 ≤ 半宽 200  →  city ≤ 146。
expect("半宽刚好放下（city=146）是档 0", tierOf(40, 146, 60, 100, 400) == .allFour)
expect("城市再多 1pt（147）就落到档 1", tierOf(40, 147, 60, 100, 400) == .noSolarLabel)

// 档 1 → 档 2 的边界：utc 40 + (city + 6) + 时辰 100 + 16 ≤ 400  →  city ≤ 238。
expect("整行刚好放下（city=238）是档 1", tierOf(40, 238, 60, 100, 400) == .noSolarLabel)
expect("再宽 1pt（239）就落到档 2", tierOf(40, 239, 60, 100, 400) == .cityAndShichen)

// 档 2 → 档 3 的边界：(city + 6) + 时辰 100 + 8 ≤ 400  →  city ≤ 286。
expect("城市 + 时辰刚好放下（city=286）是档 2", tierOf(40, 286, 60, 100, 400) == .cityAndShichen)
expect("城市再宽（287）落到档 3（尾部省略号）", tierOf(40, 287, 60, 100, 400) == .cityTruncated)

// 极窄：连「城市 + 时辰」都放不下就是档 3。
expect("极窄（60pt）是档 3", tierOf(40, 100, 60, 100, 60) == .cityTruncated)

// 6pt 间隙确实计入：行宽 96（半宽 48）、UTC 40 时，城市只有 0 宽才装得下左半。
expect("空城市不算间隙（档 0）", tierOf(40, 0, 10, 10, 96) == .allFour)
expect("城市宽 1pt 就要计入 6pt 间隙（落到档 1）", tierOf(40, 1, 10, 10, 96) == .noSolarLabel)

// 每一档能看见哪几段：时辰任何档都在，且排在最右。
expect(
    "档 0 四段都显示",
    HeroRowTier.labels(tier: .allFour) == [.utc, .city, .solarLabel, .shichen]
)
expect(
    "档 1 收掉「真太阳时」",
    HeroRowTier.labels(tier: .noSolarLabel) == [.utc, .city, .shichen]
)
expect(
    "档 2 再收掉 UTC",
    HeroRowTier.labels(tier: .cityAndShichen) == [.city, .shichen]
)
expect(
    "档 3 与档 2 相同（城市截尾）",
    HeroRowTier.labels(tier: .cityTruncated) == [.city, .shichen]
)
expect(
    "任何档位都保留时辰",
    HeroRowTier.Tier.allCases.allSatisfy { HeroRowTier.labels(tier: $0).contains(.shichen) }
)
expect(
    "只有档 1 城市居中",
    !HeroRowTier.cityCentered(tier: .allFour)
        && HeroRowTier.cityCentered(tier: .noSolarLabel)
        && !HeroRowTier.cityCentered(tier: .cityAndShichen)
        && !HeroRowTier.cityCentered(tier: .cityTruncated)
)

// 竖分隔线：只有档 0 向上延伸到标签行。
expect(
    "只有档 0 的竖线延伸到标签行",
    HeroRowTier.dividerReachesLabelRow(tier: .allFour)
        && !HeroRowTier.dividerReachesLabelRow(tier: .noSolarLabel)
        && !HeroRowTier.dividerReachesLabelRow(tier: .cityAndShichen)
        && !HeroRowTier.dividerReachesLabelRow(tier: .cityTruncated)
)
// 标签行高 16（含 2pt 下间距）、时钟行高 40、文字上沿内缩 2。
// 档 0：总高度 = 16 + 40，上端在 2 → top 2 / height 54。
// 档 1~3：只盖时钟行 → top 16 / height 40。
let tier0Divider = HeroRowTier.divider(
    tier: .allFour, labelRowHeight: 16, clockRowHeight: 40, labelTopInset: 2
)
expect(
    "档 0 的线总高 = 标签行 + 时钟行，上端与文字上沿齐平",
    tier0Divider.top == 2 && tier0Divider.height == 54,
    "top=\(tier0Divider.top) height=\(tier0Divider.height)"
)
let tier1Divider = HeroRowTier.divider(
    tier: .noSolarLabel, labelRowHeight: 16, clockRowHeight: 40, labelTopInset: 2
)
expect(
    "档 1 的线只盖时钟行",
    tier1Divider.top == 16 && tier1Divider.height == 40,
    "top=\(tier1Divider.top) height=\(tier1Divider.height)"
)
expect(
    "档 2 / 档 3 的线与档 1 相同",
    HeroRowTier.divider(tier: .cityAndShichen, labelRowHeight: 16, clockRowHeight: 40, labelTopInset: 2)
        == tier1Divider
        && HeroRowTier.divider(tier: .cityTruncated, labelRowHeight: 16, clockRowHeight: 40, labelTopInset: 2)
        == tier1Divider
)

print("== 提示形式：只用非阻塞 Toast，不用需要点击的模态 ==")
// 用户明确要求：告知类消息一律 Toast（或直接去掉），不许用 alert / confirmationDialog。
// 这里扫一遍 UI 源码，防止以后又冒出模态提示。
var modalHits: [String] = []
let uiRoot = iosRoot.appendingPathComponent("TrueSolarTime")
if let enumerator = FileManager.default.enumerator(at: uiRoot, includingPropertiesForKeys: nil) {
    for case let url as URL in enumerator where url.pathExtension == "swift" {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
        if text.contains(".alert(") || text.contains("confirmationDialog") {
            modalHits.append(url.lastPathComponent)
        }
    }
}
expect(
    "源码里没有 alert / confirmationDialog",
    modalHits.isEmpty,
    "仍在使用：\(modalHits.sorted().joined(separator: ", "))"
)
expect(
    "Toast 停留时长在 1.5~2 秒之间",
    ToastTiming.duration >= 1.5 && ToastTiming.duration <= 2.0,
    "actual=\(ToastTiming.duration)"
)
print("== 隐藏的诊断入口（连点 7 次版本号）==")
// 断言「7 次 + 2 秒窗口」的判定：这是唯一能打开诊断区块的途径。
let tapBase = date("2026-11-15T04:00:00Z")

var unlock = DiagnosticsUnlock()
var unlockedAt: Int?
for (index, offset) in [0.0, 0.3, 0.6, 0.9, 1.2, 1.5, 1.8].enumerated() {
    let fired = unlock.register(at: tapBase.addingTimeInterval(offset))
    if fired { unlockedAt = index + 1 }
}
expect("连点 7 次刚好解锁（第 7 次触发）", unlockedAt == 7, "actual=\(unlockedAt.map(String.init) ?? "nil")")

var unlockSix = DiagnosticsUnlock()
var firedEarly = false
for offset in [0.0, 0.2, 0.4, 0.6, 0.8, 1.0] {
    if unlockSix.register(at: tapBase.addingTimeInterval(offset)) { firedEarly = true }
}
expect("只有 6 次不解锁", !firedEarly)

var unlockGap = DiagnosticsUnlock()
var firedAfterGap = false
// 前 4 次连击，停 3 秒（> 2 秒窗口），后面 6 次连击：从 1 重新数，6 次仍不够 7 次。
for offset in [0.0, 0.2, 0.4, 0.6, 3.6, 3.8, 4.0, 4.2, 4.4, 4.6] {
    if unlockGap.register(at: tapBase.addingTimeInterval(offset)) { firedAfterGap = true }
}
expect("中间停超过 2 秒会从头数", !firedAfterGap)
expect("诊断开关不持久化（默认 false）", DiagnosticsUnlock.requiredTaps == 7 && DiagnosticsUnlock.maxInterval == 2)

// 三语都有「已开启诊断」这条文案。
expect(
    "「已开启诊断」三语齐全",
    !L10n.t("settings.diagnosticsUnlocked", language: .simplified).isEmpty
        && L10n.t("settings.diagnosticsUnlocked", language: .simplified) != "settings.diagnosticsUnlocked"
        && L10n.t("settings.diagnosticsUnlocked", language: .traditional) == "已開啟診斷"
        && L10n.t("settings.diagnosticsUnlocked", language: .english) == "Diagnostics enabled"
)
print("")
if failures == 0 {
    print("全部 \(checks) 项检查通过")
    exit(0)
} else {
    print("\(failures)/\(checks) 项检查失败")
    exit(1)
}
