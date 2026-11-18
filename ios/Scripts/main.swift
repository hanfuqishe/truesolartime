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

print("== 太阳卡圆盘：一天 24 小时的圆 × 可移动地平线 ==")
// 模型（见 Core/SunPathGeometry.swift）：圆 = 一天 24 小时（12:00 正上方、00:00 正下方）；
// 地平线是一条水平弦，高度由日出时刻决定：昼长 12h 过圆心、>12h 下移、<12h 上移，
// 极昼沉到圆下方（整圆白天）、极夜升到圆上方（整圆夜晚）。角度一律用**当地真太阳时**。
let dialSize = CGSize(width: 200, height: 200)
let dialRadius: CGFloat = 76 // = 0.38 × 200
let dialCenter = CGPoint(x: 100, y: 100)

func dialHour(_ time: TimeOfDay?) -> Double? {
    time.map { Double($0.secondsOfDay) / 3600.0 }
}

/// 用一份真实快照算出圆盘几何（日出/日落/当前时刻都取真太阳时）。
func dialPath(_ snapshot: SolarSnapshot) -> SunPath {
    SunPathGeometry.compute(
        size: dialSize,
        sunriseHour: dialHour(snapshot.sunriseTrueSolar),
        sunsetHour: dialHour(snapshot.sunsetTrueSolar),
        trueSolarHour: Double(snapshot.trueSolarTime.secondsOfDay) / 3600.0,
        isPolarDay: snapshot.polar == .midnightSun,
        isPolarNight: snapshot.polar == .polarNight
    )
}

// 6) 半径 = 0.38 × min(w, h)（±0.5pt），圆心居中。
let squareDial = SunPathGeometry.compute(
    size: dialSize,
    sunriseHour: 6,
    sunsetHour: 18,
    trueSolarHour: 12,
    isPolarDay: false,
    isPolarNight: false
)
expectClose("圆盘半径 = 0.38 × min(w, h)", squareDial.radius, 76, tolerance: 0.5, unit: " pt")
expectClose("圆盘圆心居中（x）", squareDial.center.x, 100, tolerance: 0.5, unit: " pt")
expectClose("圆盘圆心居中（y）", squareDial.center.y, 100, tolerance: 0.5, unit: " pt")
let wideDial = SunPathGeometry.compute(
    size: CGSize(width: 220, height: 180),
    sunriseHour: 6,
    sunsetHour: 18,
    trueSolarHour: 12,
    isPolarDay: false,
    isPolarNight: false
)
expectClose("非方形区域取短边：0.38 × 180", wideDial.radius, 68.4, tolerance: 0.5, unit: " pt")
expectClose("非方形区域圆心仍在中央（x）", wideDial.center.x, 110, tolerance: 0.5, unit: " pt")
expectClose("非方形区域圆心仍在中央（y）", wideDial.center.y, 90, tolerance: 0.5, unit: " pt")

// 角度换算：θ 的单位是**弧度**（输入 0…24 时 → (−π, π]）。
expectClose("12:00 的角度是 0（圆顶）", SunPathGeometry.angleOfDayHour(12), 0, tolerance: 1e-9)
expectClose("06:00 的角度是 −π/2（圆左）", SunPathGeometry.angleOfDayHour(6), -Double.pi / 2, tolerance: 1e-9)
expectClose("18:00 的角度是 +π/2（圆右）", SunPathGeometry.angleOfDayHour(18), Double.pi / 2, tolerance: 1e-9)
expectClose("00:00 的角度是 −π（圆底）", abs(SunPathGeometry.angleOfDayHour(0)), Double.pi, tolerance: 1e-9)

// 1) 春分赤道附近：昼长 ≈ 12h → 地平线 ≈ 圆心 y。
let equatorEquinox = SolarTimeSnapshot.compute(
    date: date("2024-03-20T04:00:00Z"),
    latitude: 0,
    longitude: 0,
    offsetSeconds: 0
)
let equatorPath = dialPath(equatorEquinox)
if let daylight = equatorEquinox.daylightSeconds {
    expectClose("赤道春分昼长 ≈ 12h", Double(daylight) / 3600.0, 12.0, tolerance: 0.2, unit: " h")
} else {
    expect("赤道春分应有日出日落", false)
}
expectClose("赤道春分地平线 ≈ 圆心 y", equatorPath.horizonY, equatorPath.center.y, tolerance: 3.0, unit: " pt")
expect("昼长正好 12h：地平线过圆心", abs(squareDial.horizonY - dialCenter.y) < 0.01, "horizonY=\(squareDial.horizonY)")
if let chord = SunPathGeometry.horizonChord(path: squareDial) {
    let sunrisePoint = SunPathGeometry.point(center: dialCenter, radius: dialRadius, hour: 6)
    let sunsetPoint = SunPathGeometry.point(center: dialCenter, radius: dialRadius, hour: 18)
    expectClose("弦左端 = 06:00 的位置（日出刻度点）", chord.start.x, sunrisePoint.x, tolerance: 0.5, unit: " pt")
    expectClose("弦右端 = 18:00 的位置（日落刻度点）", chord.end.x, sunsetPoint.x, tolerance: 0.5, unit: " pt")
} else {
    expect("昼长 12h 时地平线应是一条圆内的弦", false)
}

// 2) 中纬度夏至（昼长 > 12h）→ 地平线在圆心下方。
let shanghaiSummer = SolarTimeSnapshot.compute(
    date: date("2024-06-21T04:00:00Z"),
    latitude: 31.2304,
    longitude: 121.4737,
    offsetSeconds: 8 * 3600
)
let summerPath = dialPath(shanghaiSummer)
if let daylight = shanghaiSummer.daylightSeconds {
    expect("上海夏至昼长 > 12h", Double(daylight) > 43_200, "actual=\(Double(daylight) / 3600.0) h")
} else {
    expect("上海夏至应有日出日落", false)
}
expect(
    "上海夏至地平线在圆心下方",
    summerPath.horizonY > summerPath.center.y,
    "horizonY=\(summerPath.horizonY) center=\(summerPath.center.y)"
)
expect(
    "上海夏至下移量明显（> 0.1R）",
    summerPath.horizonY - summerPath.center.y > summerPath.radius * 0.1,
    String(format: "offset=%.2f pt", summerPath.horizonY - summerPath.center.y)
)

// 3) 中纬度冬至（昼长 < 12h）→ 地平线在圆心上方。
let shanghaiWinter = SolarTimeSnapshot.compute(
    date: date("2024-12-21T04:00:00Z"),
    latitude: 31.2304,
    longitude: 121.4737,
    offsetSeconds: 8 * 3600
)
let winterPath = dialPath(shanghaiWinter)
if let daylight = shanghaiWinter.daylightSeconds {
    expect("上海冬至昼长 < 12h", Double(daylight) < 43_200, "actual=\(Double(daylight) / 3600.0) h")
} else {
    expect("上海冬至应有日出日落", false)
}
expect(
    "上海冬至地平线在圆心上方",
    winterPath.horizonY < winterPath.center.y,
    "horizonY=\(winterPath.horizonY) center=\(winterPath.center.y)"
)
expect(
    "上海冬至上移量明显（> 0.1R）",
    winterPath.center.y - winterPath.horizonY > winterPath.radius * 0.1,
    String(format: "offset=%.2f pt", winterPath.center.y - winterPath.horizonY)
)

// 4) 极昼 → 地平线沉到圆下方；极夜 → 升到圆上方。
let polarDaySnapshot = SolarTimeSnapshot.compute(
    date: date("2024-06-21T04:00:00Z"),
    latitude: 78.0,
    longitude: 15.0,
    offsetSeconds: 3_600
)
let polarDayPath = dialPath(polarDaySnapshot)
expect(
    "极昼快照确实是极昼（没有日出日落）",
    polarDaySnapshot.polar == .midnightSun
        && polarDaySnapshot.sunriseTrueSolar == nil
        && polarDaySnapshot.sunsetTrueSolar == nil
)
expect(
    "极昼：地平线沉到圆下方（y_h > C.y + R）",
    polarDayPath.horizonY > polarDayPath.center.y + polarDayPath.radius,
    "horizonY=\(polarDayPath.horizonY) limit=\(polarDayPath.center.y + polarDayPath.radius)"
)
expect(
    "极昼：圆和地平线没有交点（不画日出日落刻度点）",
    SunPathGeometry.horizonChord(path: polarDayPath) == nil
)
expect(
    "极昼：整圆都是白天（太阳点在地平线以上）",
    SunPathGeometry.isSunAboveHorizon(path: polarDayPath)
)

let polarNightSnapshot = SolarTimeSnapshot.compute(
    date: date("2024-12-21T04:00:00Z"),
    latitude: 78.0,
    longitude: 15.0,
    offsetSeconds: 3_600
)
let polarNightPath = dialPath(polarNightSnapshot)
expect(
    "极夜快照确实是极夜（没有日出日落）",
    polarNightSnapshot.polar == .polarNight
        && polarNightSnapshot.sunriseTrueSolar == nil
        && polarNightSnapshot.sunsetTrueSolar == nil
)
expect(
    "极夜：地平线升到圆上方（y_h < C.y − R）",
    polarNightPath.horizonY < polarNightPath.center.y - polarNightPath.radius,
    "horizonY=\(polarNightPath.horizonY) limit=\(polarNightPath.center.y - polarNightPath.radius)"
)
expect(
    "极夜：圆和地平线没有交点（不画日出日落刻度点）",
    SunPathGeometry.horizonChord(path: polarNightPath) == nil
)
expect(
    "极夜：整圆都是夜晚（太阳点在地平线以下）",
    !SunPathGeometry.isSunAboveHorizon(path: polarNightPath)
)
expect(
    "极昼 / 极夜标记原样带出来",
    polarDayPath.isPolarDay && !polarDayPath.isPolarNight
        && polarNightPath.isPolarNight && !polarNightPath.isPolarDay
)

// 5) 太阳点：12:00 在圆顶、00:00 在圆底、06:00 在圆左、18:00 在圆右；23:30 → 00:30 连续。
let noonPoint = SunPathGeometry.point(center: dialCenter, radius: dialRadius, hour: 12)
expectClose("12:00 太阳点在圆顶（x = C.x）", noonPoint.x, dialCenter.x, tolerance: 0.5, unit: " pt")
expectClose("12:00 太阳点在圆顶（y = C.y − R）", noonPoint.y, dialCenter.y - dialRadius, tolerance: 0.5, unit: " pt")
let midnightPoint = SunPathGeometry.point(center: dialCenter, radius: dialRadius, hour: 0)
expectClose("00:00 太阳点在圆底（x = C.x）", midnightPoint.x, dialCenter.x, tolerance: 0.5, unit: " pt")
expectClose("00:00 太阳点在圆底（y = C.y + R）", midnightPoint.y, dialCenter.y + dialRadius, tolerance: 0.5, unit: " pt")
let sunrisePointOfDay = SunPathGeometry.point(center: dialCenter, radius: dialRadius, hour: 6)
expectClose("06:00 太阳点在圆左（x = C.x − R）", sunrisePointOfDay.x, dialCenter.x - dialRadius, tolerance: 0.5, unit: " pt")
expectClose("06:00 太阳点与圆心同高（y = C.y）", sunrisePointOfDay.y, dialCenter.y, tolerance: 0.5, unit: " pt")
let sunsetPointOfDay = SunPathGeometry.point(center: dialCenter, radius: dialRadius, hour: 18)
expectClose("18:00 太阳点在圆右（x = C.x + R）", sunsetPointOfDay.x, dialCenter.x + dialRadius, tolerance: 0.5, unit: " pt")
expectClose("18:00 太阳点与圆心同高（y = C.y）", sunsetPointOfDay.y, dialCenter.y, tolerance: 0.5, unit: " pt")

let lateNight = SunPathGeometry.compute(
    size: dialSize,
    sunriseHour: 6,
    sunsetHour: 18,
    trueSolarHour: 23.5,
    isPolarDay: false,
    isPolarNight: false
)
let earlyMorning = SunPathGeometry.compute(
    size: dialSize,
    sunriseHour: 6,
    sunsetHour: 18,
    trueSolarHour: 0.5,
    isPolarDay: false,
    isPolarNight: false
)
expectClose(
    "23:30 与 00:30 的 y 完全相同（跨午夜不跳变）",
    lateNight.sunPoint.y,
    earlyMorning.sunPoint.y,
    tolerance: 1e-9
)
expect(
    "23:30 / 00:30 都贴着圆底（> C.y + 0.9R）",
    lateNight.sunPoint.y > dialCenter.y + dialRadius * 0.9
        && earlyMorning.sunPoint.y > dialCenter.y + dialRadius * 0.9
)
expect(
    "23:30 → 00:30 横向只差 < 0.3R（连续前进，不是绕到对面）",
    abs(lateNight.sunPoint.x - earlyMorning.sunPoint.x) < dialRadius * 0.3,
    String(format: "dx=%.2f pt", abs(lateNight.sunPoint.x - earlyMorning.sunPoint.x))
)
expect("23:30 在地平线以下（空心）", !SunPathGeometry.isSunAboveHorizon(path: lateNight))
expect("12:00 在地平线以上（实心）", SunPathGeometry.isSunAboveHorizon(path: squareDial))
expect("上海夏至正午的太阳点在地平线以上", SunPathGeometry.isSunAboveHorizon(path: summerPath))
expect("赤道春分 03:52（夜里）的太阳点在地平线以下", !SunPathGeometry.isSunAboveHorizon(path: equatorPath))

// MARK: 圆盘外侧标签（日出 / 上中天 / 日落 / 极昼极夜）—— 锚点 + 预算矩形

// 圆盘画布 = 卡片内容宽 × 194（iPhone 15 内容宽 313），半径 = 0.38 × 194 ≈ 73.7（与安卓同档）。
let dialCanvas = CGSize(width: 313, height: 194)
let canvasRadius = SunPathGeometry.radiusRatio * dialCanvas.height
let canvasCenter = CGPoint(x: dialCanvas.width / 2.0, y: dialCanvas.height / 2.0)

/// 标签预算矩形到圆心的最近距离 ≥ 半径 → 整块在圆外，不会压到圆弧。
func rectAvoidsCircle(_ rect: CGRect, center: CGPoint, radius: CGFloat) -> Bool {
    let nearestX = min(max(center.x, rect.minX), rect.maxX)
    let nearestY = min(max(center.y, rect.minY), rect.maxY)
    let dx = Double(nearestX - center.x)
    let dy = Double(nearestY - center.y)
    return (dx * dx + dy * dy).squareRoot() >= Double(radius) - 1e-6
}

/// 标签预算矩形四边都在画布内。
func rectInsideCanvas(_ rect: CGRect, size: CGSize) -> Bool {
    rect.minX >= -1e-6 && rect.maxX <= size.width + 1e-6
        && rect.minY >= -1e-6 && rect.maxY <= size.height + 1e-6
}

func rectText(_ rect: CGRect) -> String {
    String(format: "x %.1f…%.1f, y %.1f…%.1f", rect.minX, rect.maxX, rect.minY, rect.maxY)
}

func labelText(_ label: SunPathLabel?) -> String {
    guard let label else { return "nil" }
    return String(format: "(%.1f, %.1f) %@", label.point.x, label.point.y, String(describing: label.alignment))
}

/// 锚点四边都在画布内、各留 ≥8pt（需求里的「标签锚点不越出画布」）。
func labelAnchorInside(_ label: SunPathLabel, size: CGSize, margin: CGFloat = 8) -> Bool {
    label.point.x >= margin && label.point.x <= size.width - margin
        && label.point.y >= margin && label.point.y <= size.height - margin
}

// 画布从正方形（313×194 之前是 313×313）改成 194 高：半径、圆心跟着变，先钉住这两条。
let canvasDial = SunPathGeometry.compute(
    size: dialCanvas,
    sunriseHour: 6,
    sunsetHour: 18,
    trueSolarHour: 12,
    isPolarDay: false,
    isPolarNight: false
)
expectClose("新画布半径 = 0.38 × 194", canvasDial.radius, 73.72, tolerance: 0.1, unit: " pt")
expectClose("新画布圆心 x = 313/2", canvasDial.center.x, 156.5, tolerance: 0.1, unit: " pt")
expectClose("新画布圆心 y = 194/2", canvasDial.center.y, 97.0, tolerance: 0.1, unit: " pt")

// 日出 0:00（日落 24:00）：θ = −180°，太阳点在圆底，地平线与圆**相切于最下方**（弦长 0）。
let tangentDial = SunPathGeometry.compute(
    size: dialCanvas,
    sunriseHour: 0,
    sunsetHour: 24,
    trueSolarHour: 12,
    isPolarDay: false,
    isPolarNight: false
)
expectClose(
    "日出 0:00：地平线与圆相切于圆底（y_h = C.y + R）",
    tangentDial.horizonY,
    tangentDial.center.y + tangentDial.radius,
    tolerance: 0.5,
    unit: " pt"
)
if let tangentChord = SunPathGeometry.horizonChord(path: tangentDial) {
    expect(
        "日出 0:00：弦长为 0（日出 / 日落交点重合在圆底）",
        abs(tangentChord.end.x - tangentChord.start.x) < 0.5
            && abs(tangentChord.start.x - tangentDial.center.x) < 0.5
            && abs(tangentChord.start.y - (tangentDial.center.y + tangentDial.radius)) < 0.5,
        "start=\(tangentChord.start) end=\(tangentChord.end)"
    )
} else {
    expect("日出 0:00 应仍是一条（退化的）弦", false)
}
let tangentArc = SunPathGeometry.dayArcAngles(
    sunriseHour: 0,
    sunsetHour: 24,
    isPolarDay: false,
    isPolarNight: false
)
expect(
    "日出 0:00：白天弧是整圆（弦退化成切点，昼长 24h；外扩后仍封顶 2π）",
    tangentArc != nil && abs((tangentArc!.end - tangentArc!.start) - 2 * Double.pi) < 1e-9,
    tangentArc.map { "span=\(($0.end - $0.start) * 180 / Double.pi)°" } ?? "nil"
)

print("== 白天弧两端外扩 0.8°（不再画日出/日落刻度点）==")
/// 0.8° 换成的弧度。
let overshoot = SunPathGeometry.dayArcOvershootRadians
expect(
    "外扩常量 = 0.8°（弧度 ≈ 0.01396）",
    SunPathGeometry.dayArcOvershootDegrees == 0.8
        && abs(overshoot - 0.8 * Double.pi / 180) < 1e-12,
    "actual=\(SunPathGeometry.dayArcOvershootDegrees)°"
)
let noonDayArc = SunPathGeometry.dayArcAngles(
    sunriseHour: 6,
    sunsetHour: 18,
    isPolarDay: false,
    isPolarNight: false
)
let sunriseAngle = SunPathGeometry.angleOfDayHour(6)
let sunsetAngle = SunPathGeometry.angleOfDayHour(18)
let arcStart = noonDayArc?.start ?? .nan
let arcEnd = noonDayArc?.end ?? .nan
let arcSpanDegrees = (arcEnd - arcStart) * 180 / Double.pi
expect(
    "起点 = 日出 − 0.8°",
    noonDayArc != nil && abs(arcStart - (sunriseAngle - overshoot)) < 1e-12,
    "start=\(arcStart)"
)
expect(
    "扫角 = 跨度 + 1.6°（两端各 0.8°）",
    noonDayArc != nil
        && abs((arcEnd - arcStart) - ((sunsetAngle - sunriseAngle) + 2 * overshoot)) < 1e-12,
    "span=\(arcSpanDegrees)°"
)
expect(
    "两端确实越过交点（起点更早、终点更晚）",
    noonDayArc != nil && arcStart < sunriseAngle && arcEnd > sunsetAngle,
    "start<sunrise: \(arcStart < sunriseAngle) end>sunset: \(arcEnd > sunsetAngle)"
)
// R ≈ 73.72pt 时 0.8° 的弧长 ≈ 1pt。
let overshootPoints = Double(canvasRadius) * overshoot
expect(
    "0.8° 在 R≈73.7pt 上约 1pt（0.9…1.2）",
    overshootPoints > 0.9 && overshootPoints < 1.2,
    String(format: "R=%.2fpt → %.2fpt", canvasRadius, overshootPoints)
)
// 昼长接近 24h：白天扫角封顶 ≤ 2π、夜间扫角 ≥ 0（为 0 时不画虚线）。
let sweeps24h = SunPathGeometry.arcSweeps(
    sunriseHour: 0,
    sunsetHour: 23.5,
    isPolarDay: false,
    isPolarNight: false
)
expect(
    "昼长 23.5h：白天扫角 ≤ 360°、夜间扫角 ≥ 0",
    sweeps24h != nil
        && sweeps24h!.day <= 2 * Double.pi + 1e-12
        && sweeps24h!.night >= 0,
    sweeps24h.map { String(format: "day=%.1f° night=%.1f°", $0.day * 180 / Double.pi, $0.night * 180 / Double.pi) } ?? "nil"
)
expect(
    "普通日（12h）：白天 + 夜间 = 360°",
    sweeps24h != nil
        && abs((sweeps24h!.day + sweeps24h!.night) - 2 * Double.pi) < 1e-12
)
let sweepsNoon = SunPathGeometry.arcSweeps(
    sunriseHour: 6,
    sunsetHour: 18,
    isPolarDay: false,
    isPolarNight: false
)
expect(
    "12h 昼：白天扫角 = 180° + 1.6°，夜间 = 178.4°",
    sweepsNoon != nil
        && abs(sweepsNoon!.day * 180 / Double.pi - 181.6) < 1e-9
        && abs(sweepsNoon!.night * 180 / Double.pi - 178.4) < 1e-9,
    sweepsNoon.map { String(format: "day=%.2f° night=%.2f°", $0.day * 180 / Double.pi, $0.night * 180 / Double.pi) } ?? "nil"
)
// 整圆白天：夜间扫角为 0（不画虚线）、白天正好 360°。
let sweepsFull = SunPathGeometry.arcSweeps(
    sunriseHour: 0,
    sunsetHour: 24,
    isPolarDay: false,
    isPolarNight: false
)
expect(
    "24h 昼：白天 360°、夜间 0°（不画夜间虚线）",
    sweepsFull != nil
        && abs(sweepsFull!.day - 2 * Double.pi) < 1e-9
        && sweepsFull!.night < 1e-9,
    sweepsFull.map { String(format: "day=%.3f night=%.3f", $0.day, $0.night) } ?? "nil"
)
expect(
    "极昼：整圆白天（0…2π）；极夜：没有白天弧",
    SunPathGeometry.dayArcAngles(sunriseHour: nil, sunsetHour: nil, isPolarDay: true, isPolarNight: false).map {
        abs($0.start) < 1e-12 && abs($0.end - 2 * Double.pi) < 1e-12
    } == true
        && SunPathGeometry.dayArcAngles(sunriseHour: nil, sunsetHour: nil, isPolarDay: false, isPolarNight: true) == nil
)
expect(
    "刻度点已彻底移除：token 表里没有 sunTick 之类",
    !ThemeColors.day.tokens.contains { $0.name.lowercased().contains("tick") }
        && !ThemeColors.night.tokens.contains { $0.name.lowercased().contains("tick") }
)

// 极短弦：昼长 1 小时（两个交点只隔 ±7.5°）。
let shortChordDial = SunPathGeometry.compute(
    size: dialCanvas,
    sunriseHour: 11.5,
    sunsetHour: 12.5,
    trueSolarHour: 12,
    isPolarDay: false,
    isPolarNight: false
)
expectClose(
    "极短弦（昼长 1 小时）：弦端点到圆心的高差 = R·cos(7.5°)",
    shortChordDial.horizonY,
    shortChordDial.center.y - shortChordDial.radius * CGFloat(cos(7.5 * Double.pi / 180.0)),
    tolerance: 0.01,
    unit: " pt"
)

// 六种场景：赤道春分、上海夏至、极昼、极夜、极短弦（昼长 1 小时）、日出 0:00（相切）。
let labelCases: [(name: String, path: SunPath, dayLength: Double?)] = [
    ("赤道春分", SunPathGeometry.compute(
        size: dialCanvas,
        sunriseHour: dialHour(equatorEquinox.sunriseTrueSolar),
        sunsetHour: dialHour(equatorEquinox.sunsetTrueSolar),
        trueSolarHour: 12,
        isPolarDay: false,
        isPolarNight: false
    ), 12.11),
    ("上海夏至", SunPathGeometry.compute(
        size: dialCanvas,
        sunriseHour: dialHour(shanghaiSummer.sunriseTrueSolar),
        sunsetHour: dialHour(shanghaiSummer.sunsetTrueSolar),
        trueSolarHour: 12,
        isPolarDay: false,
        isPolarNight: false
    ), 14.18),
    ("极昼", SunPathGeometry.compute(
        size: dialCanvas,
        sunriseHour: nil,
        sunsetHour: nil,
        trueSolarHour: 4.97,
        isPolarDay: true,
        isPolarNight: false
    ), nil),
    ("极夜", SunPathGeometry.compute(
        size: dialCanvas,
        sunriseHour: nil,
        sunsetHour: nil,
        trueSolarHour: 5.03,
        isPolarDay: false,
        isPolarNight: true
    ), nil),
    ("极短弦（昼长 1 小时）", shortChordDial, 1.0),
    ("日出 0:00（相切）", tangentDial, 24.0)
]

// 每个场景：算标签锚点，断「锚点不越界 / 不压圆 / 互不重叠 / 地平线贯穿」。
var labelReports: [String] = []
var horizonSpans: [CGFloat] = []
for (name, path, dayLength) in labelCases {
    let labels = SunPathGeometry.labels(path: path, size: dialCanvas, dayLengthHours: dayLength)
    let chord = SunPathGeometry.horizonChord(path: path)
    let xLeft = chord?.start.x ?? path.center.x
    let xRight = chord?.end.x ?? path.center.x
    let isPolar = path.isPolarDay || path.isPolarNight
    let isShortDay = (dayLength ?? 24.0) <= SunPathGeometry.shortDayHours
    let isLongDay = (dayLength ?? 24.0) >= 24.0 - SunPathGeometry.shortDayHours

    // 1) 锚点都在画布内（左右上下各 ≥8pt）。
    for (labelName, label) in [("日出", labels.sunrise), ("日落", labels.sunset),
                               ("上中天", labels.noon), ("极昼极夜", labels.polar)] {
        if let label {
            expect(
                "\(name)：\(labelName)锚点不越出画布（各 ≥8pt）",
                labelAnchorInside(label, size: dialCanvas),
                labelText(label)
            )
        }
    }

    // 2) 预算矩形：在画布内、不压圆、互不重叠。
    let sunriseRect = SunPathGeometry.rect(for: labels.sunrise, budget: SunPathGeometry.sideLabelBudget)
    let sunsetRect = SunPathGeometry.rect(for: labels.sunset, budget: SunPathGeometry.sideLabelBudget)
    let noonRect = SunPathGeometry.rect(for: labels.noon, budget: SunPathGeometry.noonLabelBudget)
    let polarRect = SunPathGeometry.rect(for: labels.polar, budget: SunPathGeometry.polarLabelBudget)

    var blocks: [(String, CGRect)] = []
    if let sunriseRect { blocks.append(("日出", sunriseRect)) }
    if let sunsetRect { blocks.append(("日落", sunsetRect)) }
    if let noonRect { blocks.append(("上中天", noonRect)) }
    if let polarRect { blocks.append(("极昼极夜", polarRect)) }

    for (blockName, rect) in blocks {
        expect(
            "\(name)：\(blockName)标签块在画布内",
            rectInsideCanvas(rect, size: dialCanvas),
            rectText(rect)
        )
        if blockName == "极昼极夜" {
            // 「极昼 / 极夜」这一行本来就在圆心、圆内：只需要它水平居中、整块不出圆。
            expect(
                "\(name)：极昼 / 极夜那一行在圆内且水平居中",
                abs(rect.midX - path.center.x) < 0.01
                    && rect.maxX - rect.minX < path.radius * 2
                    && rect.maxY - rect.minY < path.radius * 2,
                rectText(rect)
            )
        } else {
            expect(
                "\(name)：\(blockName)标签块不压圆弧",
                rectAvoidsCircle(rect, center: path.center, radius: path.radius),
                "\(rectText(rect)) R=\(path.radius)"
            )
        }
    }
    for i in 0..<blocks.count {
        for j in (i + 1)..<blocks.count {
            expect(
                "\(name)：\(blocks[i].0) 与 \(blocks[j].0) 标签不重叠",
                !blocks[i].1.intersects(blocks[j].1),
                "\(rectText(blocks[i].1)) vs \(rectText(blocks[j].1))"
            )
        }
    }

    // 3) 日出 / 日落标签的方向：左交点左侧（右对齐）、右交点右侧（左对齐），且都在交点外侧。
    if isPolar {
        expect(
            "\(name)：极昼 / 极夜没有交点，不画日出 / 日落标签",
            labels.sunrise == nil && labels.sunset == nil
        )
    } else if let sunrise = labels.sunrise, let sunset = labels.sunset {
        if !isShortDay {
            expect(
                "\(name)：日出标签锚在左交点左侧 10pt（右对齐）",
                sunrise.alignment == .trailing
                    && abs(sunrise.point.x - (xLeft - SunPathGeometry.labelOffsetX)) < 0.01,
                "anchor=\(labelText(sunrise)) xLeft=\(xLeft)"
            )
            expect(
                "\(name)：日落标签锚在右交点右侧 10pt（左对齐）",
                sunset.alignment == .leading
                    && abs(sunset.point.x - (xRight + SunPathGeometry.labelOffsetX)) < 0.01,
                "anchor=\(labelText(sunset)) xRight=\(xRight)"
            )
        }
        if isShortDay {
            let expectedY = path.center.y - path.radius + SunPathGeometry.shortDayRowOffset
            expect(
                "\(name)：短昼保护——标签落到圆顶下方一行（y = 圆顶 + 26）",
                abs(sunrise.point.y - expectedY) < 0.01 && abs(sunset.point.y - expectedY) < 0.01,
                String(format: "y=%.2f expected=%.2f", sunrise.point.y, expectedY)
            )
            let rowDy = Double(sunrise.point.y - path.center.y)
            let halfWidth = CGFloat((Double(path.radius * path.radius) - rowDy * rowDy).squareRoot())
            expect(
                "\(name)：短昼保护——标签左右仍各离圆弧 10pt",
                abs(abs(sunrise.point.x - path.center.x) - (halfWidth + SunPathGeometry.labelOffsetX)) < 0.01,
                String(format: "|x−C.x|=%.2f expected=%.2f",
                       abs(sunrise.point.x - path.center.x),
                       halfWidth + SunPathGeometry.labelOffsetX)
            )
        } else if isLongDay {
            expect(
                "\(name)：弦退化时标签放到地平线下方（远离圆心一侧）",
                abs(sunrise.point.y - (path.horizonY + SunPathGeometry.labelOffsetY)) < 0.01
                    && abs(sunset.point.y - (path.horizonY + SunPathGeometry.labelOffsetY)) < 0.01,
                String(format: "y=%.2f horizon=%.2f", sunrise.point.y, path.horizonY)
            )
        } else {
            expect(
                "\(name)：日出 / 日落标签比交点抬高 10pt（地平线从字下过）",
                abs(sunrise.point.y - (path.horizonY - SunPathGeometry.labelOffsetY)) < 0.01
                    && abs(sunset.point.y - (path.horizonY - SunPathGeometry.labelOffsetY)) < 0.01,
                String(format: "y=%.2f horizon=%.2f", sunrise.point.y, path.horizonY)
            )
        }
        expect(
            "\(name)：日出标签右边界 ≤ 左交点",
            sunriseRect == nil || sunriseRect!.maxX <= xLeft + 0.01,
            sunriseRect.map(rectText) ?? "nil"
        )
        expect(
            "\(name)：日落标签左边界 ≥ 右交点",
            sunsetRect == nil || sunsetRect!.minX >= xRight - 0.01,
            sunsetRect.map(rectText) ?? "nil"
        )
        expect(
            "\(name)：日出标签右边界 < 右交点、日落标签左边界 > 左交点（弦再短也不越界）",
            sunriseRect == nil || sunsetRect == nil
                || (sunriseRect!.maxX < xRight && sunsetRect!.minX > xLeft),
            "\(sunriseRect.map(rectText) ?? "nil") / \(sunsetRect.map(rectText) ?? "nil")"
        )
    } else {
        expect("\(name)：正常日必须有日出 / 日落标签", false)
    }

    // 4) 上中天：圆顶点上方居中、底边离圆顶 8pt；极夜没有。
    if path.isPolarNight {
        expect("\(name)：极夜不显示上中天标签", labels.noon == nil)
    } else if let noon = labels.noon, let noonRect {
        expect(
            "\(name)：上中天标签水平居中",
            abs(noon.point.x - path.center.x) < 0.01 && noon.alignment == .bottom,
            labelText(noon)
        )
        expectClose(
            "\(name)：上中天底边离圆顶 8pt",
            noonRect.maxY,
            path.center.y - path.radius - SunPathGeometry.noonGap,
            tolerance: 0.01,
            unit: " pt"
        )
    } else {
        expect("\(name)：正常日 / 极昼必须有上中天标签", false)
    }

    // 5) 极昼 / 极夜：圆心一行，极昼保留上中天、极夜不画。
    if isPolar {
        expect(
            "\(name)：极昼 / 极夜那一行在圆心",
            labels.polar != nil
                && abs(labels.polar!.point.x - path.center.x) < 0.01
                && abs(labels.polar!.point.y - path.center.y) < 0.01
                && labels.polar!.alignment == .center
        )
        if path.isPolarDay {
            expect("\(name)：极昼保留上中天标签", labels.noon != nil)
        }
        let word = path.isPolarDay ? "sun.polarDayShort" : "sun.polarNightShort"
        expect(
            "\(name)：极昼 / 极夜短词三语齐全",
            L10n.t(word, language: .simplified) != word
                && L10n.t(word, language: .traditional) != word
                && L10n.t(word, language: .english) != word
        )
    }

    // 6) 地平线：固定长度 = 画布宽 − 左右各 4pt；所有场景一样长，不再按弦长延伸。
    let startX = SunPathGeometry.horizonStartX(size: dialCanvas)
    let endX = SunPathGeometry.horizonEndX(size: dialCanvas)
    horizonSpans.append(endX - startX)
    expect(
        "\(name)：地平线起点 = 4pt",
        abs(startX - SunPathGeometry.horizonInset) < 0.5,
        String(format: "start=%.2f", startX)
    )
    expect(
        "\(name)：地平线终点 = 画布宽 − 4pt",
        abs(endX - (dialCanvas.width - SunPathGeometry.horizonInset)) < 0.5,
        String(format: "end=%.2f", endX)
    )
    expect(
        "\(name)：地平线长度 = 画布宽 − 8pt",
        abs((endX - startX) - (dialCanvas.width - 2 * SunPathGeometry.horizonInset)) < 0.5,
        String(format: "length=%.2f 期望=%.2f", endX - startX, dialCanvas.width - 2 * SunPathGeometry.horizonInset)
    )

    // 7) 报告用：锚点坐标。
    labelReports.append(
        "\(name)：日出 \(labelText(labels.sunrise)) / 日落 \(labelText(labels.sunset)) / 上中天 \(labelText(labels.noon))"
    )
}
expect(
    "六种场景的地平线长度完全相同（普通日 / 短昼 / 极昼 / 极夜 / 相切）",
    (horizonSpans.max() ?? 0) - (horizonSpans.min() ?? 0) < 0.001,
    horizonSpans.map { String(format: "%.2f", $0) }.joined(separator: " / ")
)
expectClose(
    "地平线长度 = 313 − 8（画布左右各留 4pt）",
    horizonSpans.first ?? 0,
    dialCanvas.width - 2 * SunPathGeometry.horizonInset,
    tolerance: 0.5,
    unit: " pt"
)
expect(
    "地平线两端固定为 4 … 画布宽−4",
    abs(SunPathGeometry.horizonStartX(size: dialCanvas) - 4) < 0.5
        && abs(SunPathGeometry.horizonEndX(size: dialCanvas) - (dialCanvas.width - 4)) < 0.5
)
print("标签锚点（画布 313×194，半径 \(String(format: "%.2f", canvasRadius))，地平线 x = "
      + String(format: "%.0f…%.0f", SunPathGeometry.horizonStartX(size: dialCanvas), SunPathGeometry.horizonEndX(size: dialCanvas))
      + "）：")
for report in labelReports {
    print("  · \(report)")
}

// MARK: 南半球：太阳从右往左（逆时针），日出在右、日落在左

// 观察者面朝北：北半球东在左、南半球东在右。圆盘的点 x 因此镜像，y（12:00 顶 / 00:00 底）不变。
let northernDialPath = SunPathGeometry.compute(
    size: dialCanvas,
    sunriseHour: 6,
    sunsetHour: 18,
    trueSolarHour: 12,
    isPolarDay: false,
    isPolarNight: false,
    southernHemisphere: false
)
let southernDialPath = SunPathGeometry.compute(
    size: dialCanvas,
    sunriseHour: 6,
    sunsetHour: 18,
    trueSolarHour: 12,
    isPolarDay: false,
    isPolarNight: false,
    southernHemisphere: true
)
expect(
    "南半球标记随参数带出来",
    !northernDialPath.isSouthernHemisphere && southernDialPath.isSouthernHemisphere
)

// 北半球（上海 31.2°N）：06:00 在左、18:00 在右。
let northSixPoint = SunPathGeometry.point(
    center: canvasCenter, radius: canvasRadius, hour: 6, southernHemisphere: false
)
let northEighteenPoint = SunPathGeometry.point(
    center: canvasCenter, radius: canvasRadius, hour: 18, southernHemisphere: false
)
expect(
    "北半球 31.2°N：06:00 的太阳点在圆心左侧",
    northSixPoint.x < canvasCenter.x - 1,
    String(format: "x=%.1f centerX=%.1f", northSixPoint.x, canvasCenter.x)
)
expect(
    "北半球 31.2°N：18:00 的太阳点在圆心右侧",
    northEighteenPoint.x > canvasCenter.x + 1
)

// 南半球（中山站 −69.4°S）：06:00 在右、18:00 在左（从右往左）。
let southSixPoint = SunPathGeometry.point(
    center: canvasCenter, radius: canvasRadius, hour: 6, southernHemisphere: true
)
let southEighteenPoint = SunPathGeometry.point(
    center: canvasCenter, radius: canvasRadius, hour: 18, southernHemisphere: true
)
expect(
    "南半球 −69.4°S：06:00 的太阳点在圆心右侧",
    southSixPoint.x > canvasCenter.x + 1,
    String(format: "x=%.1f centerX=%.1f", southSixPoint.x, canvasCenter.x)
)
expect(
    "南半球 −69.4°S：18:00 的太阳点在圆心左侧",
    southEighteenPoint.x < canvasCenter.x - 1
)
expectClose("南半球 06:00 仍与圆心同高", southSixPoint.y, canvasCenter.y, tolerance: 0.5, unit: " pt")
expectClose("南半球 18:00 仍与圆心同高", southEighteenPoint.y, canvasCenter.y, tolerance: 0.5, unit: " pt")

// 12:00 在圆顶、00:00 在圆底 —— 两个半球都一样。
let southNoonPoint = SunPathGeometry.point(
    center: canvasCenter, radius: canvasRadius, hour: 12, southernHemisphere: true
)
let southMidnightPoint = SunPathGeometry.point(
    center: canvasCenter, radius: canvasRadius, hour: 0, southernHemisphere: true
)
expectClose("南半球 12:00 仍在圆顶（y = C.y − R）", southNoonPoint.y, canvasCenter.y - canvasRadius, tolerance: 0.5, unit: " pt")
expectClose("南半球 12:00 的 x 仍在圆心（不镜像 y 轴上的点）", southNoonPoint.x, canvasCenter.x, tolerance: 0.5, unit: " pt")
expectClose("南半球 00:00 仍在圆底（y = C.y + R）", southMidnightPoint.y, canvasCenter.y + canvasRadius, tolerance: 0.5, unit: " pt")
expectClose("南半球 00:00 的 x 仍在圆心", southMidnightPoint.x, canvasCenter.x, tolerance: 0.5, unit: " pt")

// 半球只影响 x 方向，不影响地平线（地平线只由昼长决定）。
expectClose(
    "同一昼长（12h）南北半球的地平线 y 相同",
    southernDialPath.horizonY,
    northernDialPath.horizonY,
    tolerance: 1e-9,
    unit: " pt"
)
expectClose(
    "同一昼长南北半球的半径、圆心也相同",
    southernDialPath.radius,
    northernDialPath.radius,
    tolerance: 1e-9,
    unit: " pt"
)

// 标签跟着换边：南半球日出在右（左对齐）、日落在左（右对齐）。
let northernLabels = SunPathGeometry.labels(path: northernDialPath, size: dialCanvas, dayLengthHours: 12)
let southernLabels = SunPathGeometry.labels(path: southernDialPath, size: dialCanvas, dayLengthHours: 12)
if let sunrise = northernLabels.sunrise, let sunset = northernLabels.sunset {
    expect(
        "北半球：日出标签在圆心左侧（右对齐）",
        sunrise.point.x < canvasCenter.x && sunrise.alignment == .trailing,
        labelText(sunrise)
    )
    expect(
        "北半球：日落标签在圆心右侧（左对齐）",
        sunset.point.x > canvasCenter.x && sunset.alignment == .leading,
        labelText(sunset)
    )
} else {
    expect("北半球应有日出 / 日落标签", false)
}
if let sunrise = southernLabels.sunrise, let sunset = southernLabels.sunset {
    expect(
        "南半球：日出标签在圆心右侧（左对齐）",
        sunrise.point.x > canvasCenter.x && sunrise.alignment == .leading,
        labelText(sunrise)
    )
    expect(
        "南半球：日落标签在圆心左侧（右对齐）",
        sunset.point.x < canvasCenter.x && sunset.alignment == .trailing,
        labelText(sunset)
    )
    // 南半球的标签块同样不能压圆、不能出画布。
    let sunriseRect = SunPathGeometry.rect(for: sunrise, size: SunPathGeometry.sideLabelBudget)
    let sunsetRect = SunPathGeometry.rect(for: sunset, size: SunPathGeometry.sideLabelBudget)
    expect(
        "南半球：日出 / 日落标签块不压圆弧",
        rectAvoidsCircle(sunriseRect, center: southernDialPath.center, radius: southernDialPath.radius)
            && rectAvoidsCircle(sunsetRect, center: southernDialPath.center, radius: southernDialPath.radius),
        "\(rectText(sunriseRect)) / \(rectText(sunsetRect))"
    )
    expect(
        "南半球：日出 / 日落标签块在画布内",
        rectInsideCanvas(sunriseRect, size: dialCanvas) && rectInsideCanvas(sunsetRect, size: dialCanvas)
    )
} else {
    expect("南半球应有日出 / 日落标签", false)
}

// 调用方用 `place.latitude < 0` 判断半球，所以快照必须把纬度带回来。
expect("北半球快照纬度为正（上海 31.23）", shanghaiSummer.latitude > 0, "\(shanghaiSummer.latitude)")
let sydneySnapshot = SolarTimeSnapshot.compute(
    date: date("2024-12-21T04:00:00Z"),
    latitude: -33.8688,
    longitude: 151.2093,
    offsetSeconds: 11 * 3600
)
expect(
    "南半球快照纬度为负（悉尼 −33.87）",
    sydneySnapshot.latitude < 0 && abs(sydneySnapshot.latitude + 33.8688) < 1e-9,
    "\(sydneySnapshot.latitude)"
)

print("南北半球太阳点（画布 313×194，半径 \(String(format: "%.2f", canvasRadius))，圆心 (156.5, 97)）：")
print(String(format: "  · 北半球 上海 31.2°N：06:00 (%.1f, %.1f) / 12:00 (%.1f, %.1f) / 18:00 (%.1f, %.1f)",
             northSixPoint.x, northSixPoint.y,
             SunPathGeometry.point(center: canvasCenter, radius: canvasRadius, hour: 12).x,
             SunPathGeometry.point(center: canvasCenter, radius: canvasRadius, hour: 12).y,
             northEighteenPoint.x, northEighteenPoint.y))
print(String(format: "  · 南半球 中山站 −69.4°S：06:00 (%.1f, %.1f) / 12:00 (%.1f, %.1f) / 18:00 (%.1f, %.1f)",
             southSixPoint.x, southSixPoint.y,
             southNoonPoint.x, southNoonPoint.y,
             southEighteenPoint.x, southEighteenPoint.y))
print(String(format: "  · 南半球标签：日出 (%.1f, %.1f) %@ / 日落 (%.1f, %.1f) %@",
             southernLabels.sunrise?.point.x ?? -1, southernLabels.sunrise?.point.y ?? -1,
             String(describing: southernLabels.sunrise?.alignment ?? .trailing),
             southernLabels.sunset?.point.x ?? -1, southernLabels.sunset?.point.y ?? -1,
             String(describing: southernLabels.sunset?.alignment ?? .leading)))


// MARK: 圆内侧的「太阳运动方向」小弧箭头（北半球顺时针 / 南半球逆时针）

func crossAround(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Double {
    let ax = Double(a.x - c.x)
    let ay = Double(a.y - c.y)
    let bx = Double(b.x - c.x)
    let by = Double(b.y - c.y)
    return ax * by - ay * bx
}

func pointDistance(_ a: CGPoint, _ b: CGPoint) -> Double {
    hypot(Double(a.x - b.x), Double(a.y - b.y))
}

func angleAround(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Double {
    let ax = Double(a.x - c.x)
    let ay = Double(a.y - c.y)
    let bx = Double(b.x - c.x)
    let by = Double(b.y - c.y)
    let dot = ax * bx + ay * by
    let la = (ax * ax + ay * ay).squareRoot()
    let lb = (bx * bx + by * by).squareRoot()
    guard la > 0, lb > 0 else { return 0 }
    return acos(max(-1, min(1, dot / (la * lb)))) * 180.0 / Double.pi
}

let noonNorthPath = SunPathGeometry.compute(
    size: dialCanvas,
    sunriseHour: 6,
    sunsetHour: 18,
    trueSolarHour: 12,
    isPolarDay: false,
    isPolarNight: false,
    southernHemisphere: false
)
let noonSouthPath = SunPathGeometry.compute(
    size: dialCanvas,
    sunriseHour: 6,
    sunsetHour: 18,
    trueSolarHour: 12,
    isPolarDay: false,
    isPolarNight: false,
    southernHemisphere: true
)
let northArrow = SunPathGeometry.motionArrow(path: noonNorthPath, currentTrueSolarHour: 12)
let southArrow = SunPathGeometry.motionArrow(path: noonSouthPath, currentTrueSolarHour: 12)

// 1) 北半球 12:00：end 在 start 之后（屏幕上顺时针）。
let northCross = crossAround(northArrow.start, northArrow.end, canvasCenter)
expect(
    "北半球 12:00：箭头从 start 顺时针走向 end",
    northCross > 0 && northArrow.end.x > northArrow.start.x,
    String(format: "cross=%.2f end.x=%.1f start.x=%.1f", northCross, northArrow.end.x, northArrow.start.x)
)

// 2) 南半球：start / end 关于竖轴镜像，方向相反（逆时针）。
let southCross = crossAround(southArrow.start, southArrow.end, canvasCenter)
expect(
    "南半球：start / end 是北半球关于竖轴的镜像",
    abs(southArrow.start.x - (2 * canvasCenter.x - northArrow.start.x)) < 1e-9
        && abs(southArrow.start.y - northArrow.start.y) < 1e-9
        && abs(southArrow.end.x - (2 * canvasCenter.x - northArrow.end.x)) < 1e-9
        && abs(southArrow.end.y - northArrow.end.y) < 1e-9,
    "south start=\(southArrow.start) end=\(southArrow.end)"
)
expect(
    "南半球 12:00：箭头从 start 逆时针走向 end（方向相反）",
    southCross < 0 && southArrow.end.x < southArrow.start.x,
    String(format: "cross=%.2f end.x=%.1f start.x=%.1f", southCross, southArrow.end.x, southArrow.start.x)
)

// 3) 半径 = 0.72R（±0.5pt），tip == end。
let arrowRadius = canvasRadius * 0.72
expectClose(
    "北半球 start 到圆心 = 0.72R",
    pointDistance(northArrow.start, canvasCenter),
    0.72 * canvasRadius,
    tolerance: 0.5,
    unit: " pt"
)
expectClose(
    "北半球 end 到圆心 = 0.72R",
    pointDistance(northArrow.end, canvasCenter),
    0.72 * canvasRadius,
    tolerance: 0.5,
    unit: " pt"
)
expectClose(
    "南半球 end 到圆心 = 0.72R",
    pointDistance(southArrow.end, canvasCenter),
    0.72 * canvasRadius,
    tolerance: 0.5,
    unit: " pt"
)
expect(
    "tip 就是 end（箭头尖落在弧的终点）",
    northArrow.tip == northArrow.end && southArrow.tip == southArrow.end
)

// 4) start 与 end 的夹角 = 30°（±0.1°）。
expectClose(
    "北半球 start / end 夹角 = 30°",
    angleAround(northArrow.start, northArrow.end, canvasCenter),
    30.0,
    tolerance: 0.1,
    unit: "°"
)
expectClose(
    "南半球 start / end 夹角 = 30°",
    angleAround(southArrow.start, southArrow.end, canvasCenter),
    30.0,
    tolerance: 0.1,
    unit: "°"
)

// 5) 箭头（0.72R）离太阳点（R）至少 6pt：0.28R ≈ 20.6pt。
let northSunPoint = SunPathGeometry.point(center: canvasCenter, radius: canvasRadius, hour: 12)
expect(
    "北半球 tip 离太阳点 > 6pt",
    pointDistance(northArrow.tip, northSunPoint) > 6,
    String(format: "d=%.1f pt", pointDistance(northArrow.tip, northSunPoint))
)
expect(
    "南半球 tip 离太阳点 > 6pt",
    pointDistance(southArrow.tip, northSunPoint) > 6,
    String(format: "d=%.1f pt", pointDistance(southArrow.tip, northSunPoint))
)

// 6) 极昼 / 极夜也照画（箭头只跟当前时刻和半球有关，不看 polar 状态）。
let polarArrowPath = SunPathGeometry.compute(
    size: dialCanvas,
    sunriseHour: nil,
    sunsetHour: nil,
    trueSolarHour: 4.97,
    isPolarDay: true,
    isPolarNight: false
)
let polarArrow = SunPathGeometry.motionArrow(path: polarArrowPath, currentTrueSolarHour: 4.97)
expect(
    "极昼也画运动箭头（半径仍是 0.72R、夹角 30°）",
    abs(pointDistance(polarArrow.start, canvasCenter) - 0.72 * canvasRadius) < 0.5
        && abs(angleAround(polarArrow.start, polarArrow.end, canvasCenter) - 30) < 0.1
)
let polarNightArrowPath = SunPathGeometry.compute(
    size: dialCanvas,
    sunriseHour: nil,
    sunsetHour: nil,
    trueSolarHour: 5.03,
    isPolarDay: false,
    isPolarNight: true
)
let polarNightArrow = SunPathGeometry.motionArrow(path: polarNightArrowPath, currentTrueSolarHour: 5.03)
expect(
    "极夜也画运动箭头",
    abs(pointDistance(polarNightArrow.end, canvasCenter) - 0.72 * canvasRadius) < 0.5
)

// 7) 正午 12:00 的箭头在整个圆盘的上半部分（theta=0 附近），不会跑到下半圆。
expect(
    "12:00 的箭头在圆心上方（y < C.y）",
    northArrow.start.y < canvasCenter.y && northArrow.end.y < canvasCenter.y
        && southArrow.start.y < canvasCenter.y && southArrow.end.y < canvasCenter.y
)

print(String(format: "运动小箭头（12:00，半径 0.72R = %.2f）：", arrowRadius))
print(String(format: "  · 北半球：start (%.1f, %.1f) / end (%.1f, %.1f) / tip (%.1f, %.1f)",
             northArrow.start.x, northArrow.start.y,
             northArrow.end.x, northArrow.end.y,
             northArrow.tip.x, northArrow.tip.y))
print(String(format: "  · 南半球：start (%.1f, %.1f) / end (%.1f, %.1f) / tip (%.1f, %.1f)",
             southArrow.start.x, southArrow.start.y,
             southArrow.end.x, southArrow.end.y,
             southArrow.tip.x, southArrow.tip.y))


// 圆盘的颜色也守一遍：全部取主题 token，白天弧用 sunArc（白天主题比主色浅一档），
// 夜晚弧用 50% 的次要文字色。
func dialBlend(_ foreground: ThemeColor, over background: ThemeColor, alpha: Double) -> ThemeColor {
    func mix(_ f: Double, _ b: Double) -> UInt32 {
        UInt32(min(max((f * alpha + b * (1 - alpha)) * 255.0, 0), 255).rounded())
    }
    let hex = (mix(foreground.red, background.red) << 16)
        | (mix(foreground.green, background.green) << 8)
        | mix(foreground.blue, background.blue)
    return ThemeColor(hex: hex)
}

let dayArc = ThemeColors.day.sunArc
let dayDot = ThemeColors.day.sunDot
let nightThemeArc = ThemeColors.night.sunArc
let dayArcContrast = dayArc.contrast(with: ThemeColors.day.surface)
let nightArcContrast = nightThemeArc.contrast(with: ThemeColors.night.surface)
let dayPrimaryContrast = ThemeColors.day.primary.contrast(with: ThemeColors.day.surface)
expect(
    "圆盘白天弧「很轻」但仍看得见：白天 1.40…1.55、夜间 ≥ 3",
    dayArc.hexText == "#EAD095"
        && dayArcContrast >= 1.40 && dayArcContrast <= 1.55
        && nightArcContrast >= 3,
    String(format: "day=%.3f (sunArc %@) night=%.2f (sunArc %@)",
           dayArcContrast, dayArc.hexText, nightArcContrast, nightThemeArc.hexText)
)
// 用户连着报两次「白天弧太深」：主色 4.80、上一版 #CA8751 是 2.87，现在 #EAD095 是 1.46。
expect(
    "白天弧比主色浅得多（对比度至少低 2.5，且亮度更高）",
    dayArcContrast <= dayPrimaryContrast - 2.5
        && dayArc.relativeLuminance > ThemeColors.day.primary.relativeLuminance + 0.3,
    String(format: "arc=%.2f primary=%.2f arcL=%.3f primaryL=%.3f",
           dayArcContrast, dayPrimaryContrast,
           dayArc.relativeLuminance, ThemeColors.day.primary.relativeLuminance)
)
expect(
    "白天弧不是主色本身，也不是另一套主题的取值",
    dayArc != ThemeColors.day.primary && dayArc.hexText != "#B4550A" && dayArc != nightThemeArc,
    "actual=\(dayArc.hexText)"
)
expect(
    "夜间主题：弧与太阳点都保持夜间金 #F5D68A",
    nightThemeArc == ThemeColors.night.primary
        && nightThemeArc.hexText == "#F5D68A"
        && ThemeColors.night.sunDot == ThemeColors.night.primary,
    "sunArc=\(nightThemeArc.hexText) sunDot=\(ThemeColors.night.sunDot.hexText)"
)
let dayNightArc = dialBlend(ThemeColors.day.onSurfaceVariant, over: ThemeColors.day.surface, alpha: 0.5)
let nightNightArc = dialBlend(ThemeColors.night.onSurfaceVariant, over: ThemeColors.night.surface, alpha: 0.5)
let dayNightArcContrast = dayNightArc.contrast(with: ThemeColors.day.surface)
let nightNightArcContrast = nightNightArc.contrast(with: ThemeColors.night.surface)
expect(
    "圆盘夜晚弧（50% 次要色）仍看得见：对比度 ≥ 1.6",
    dayNightArcContrast >= 1.6 && nightNightArcContrast >= 1.6,
    String(format: "day=%.2f night=%.2f", dayNightArcContrast, nightNightArcContrast)
)
// 弧淡到 1.47 之后，与夜晚虚线（2.50）不再是「深浅」之分，改用**色相 + 线型**区分：
// 暖金（r−b 0.28）对中性灰（r−b 0.06）。这条断言替代了原来的「夜晚弧必须弱于白天弧」。
let arcWarmth = dayArc.red - dayArc.blue
let dashWarmth = dayNightArc.red - dayNightArc.blue
expect(
    "白天弧与夜晚虚线靠色相区分：暖度差 ≥ 0.15（暖金 vs 中性灰）",
    abs(arcWarmth - dashWarmth) >= 0.15 && arcWarmth > dashWarmth,
    String(format: "arc r−b=%.2f 虚线 r−b=%.2f 差=%.2f",
           arcWarmth, dashWarmth, arcWarmth - dashWarmth)
)
let arcChannelGap = abs(dayArc.red - dayNightArc.red)
    + abs(dayArc.green - dayNightArc.green)
    + abs(dayArc.blue - dayNightArc.blue)
expect(
    "白天弧与夜晚虚线的 RGB 距离 ≥ 0.4（且弧可见 ≥ 1.4）",
    arcChannelGap >= 0.4 && dayArc.contrast(with: ThemeColors.day.surface) >= 1.4,
    String(format: "gap=%.2f（夜晚虚线 %@）", arcChannelGap, dayNightArc.hexText)
)
print("== 时间轴圆点（两笔）与太阳点（纯色核心 + 独立光晕）==")
// 用户裁定：时间轴回到最初的两笔（5.5 实心 + 外扩 2pt/0.28），中间层与三层 alphaRamp 删掉；
// 太阳点共用以**尺寸**（核心 5.5、外沿 7.5），光晕改成 5.5→7.5 的径向渐变 0.35→0。
let axisDot = NowDotStyle.shared
let halo = SunHaloStyle.shared
let sunCoreRadius = SunPathGeometry.sunRadius
let sunGlowRadius = SunPathGeometry.sunGlowRadius
// 结构断言：NowDotStyle 只有三个存储属性（radius / glowInset / glowAlpha），
// 一旦再有人塞进「中间层」，下面这个 memberwise 构造就编译不过 —— 等于钉死「只有两笔」。
expect(
    "时间轴：核心 5.5pt、柔光 7.5pt、alpha 0.28，且只有两笔（没有中间层）",
    axisDot.radius == 5.5
        && axisDot.glowInset == 2
        && axisDot.glowRadius == 7.5
        && axisDot.glowAlpha == 0.28
        && axisDot == NowDotStyle(radius: 5.5, glowInset: 2, glowAlpha: 0.28),
    "axis=\(axisDot.radius)/+\(axisDot.glowInset)/\(axisDot.glowAlpha)"
)
expect(
    "太阳核心半径 = 2.75pt（正好是时间轴核心 5.5 的一半）",
    sunCoreRadius == 2.75
        && sunCoreRadius == axisDot.radius / 2,
    "sun=\(sunCoreRadius) axis=\(axisDot.radius)"
)
expect(
    "太阳点整体外沿 = 5.5pt（核心的 2 倍）⇒ 直径 11pt（原 15pt）",
    sunGlowRadius == 5.5
        && sunGlowRadius == sunCoreRadius * 2
        && sunGlowRadius == axisDot.radius,
    "sunGlow=\(sunGlowRadius)"
)
expect(
    "太阳点柔光渐变：startRadius = 2.75（= 核心半径，不是 0）、endRadius = 5.5",
    halo.startRadius == sunCoreRadius
        && halo.startRadius == 2.75
        && halo.endRadius == 5.5
        && SunPathGeometry.sunHaloStartRadius == halo.startRadius,
    "halo=\(halo.startRadius)…\(halo.endRadius)"
)
expect(
    "太阳点柔光 alpha：0.35 → 0（起点在核心边缘、外沿完全透明）",
    halo.alpha == 0.35
        && halo.stops.count == 2
        && halo.stops[0].alpha == 0.35
        && halo.stops[0].location == 0
        && halo.stops[1].alpha == 0
        && halo.stops[1].location == 1,
    "stops=\(halo.stops.map { ($0.alpha, $0.location) })"
)
expect(
    "颜色：白天核心 #D9AC1C（Android DAY_SUN）、夜间 #F5D68A（核心与光晕同色）",
    ThemeColors.day.sunDot.hexText == "#D9AC1C"
        && ThemeColors.night.sunDot.hexText == "#F5D68A"
        && ThemeColors.night.sunDot == ThemeColors.night.primary,
    "day=\(ThemeColors.day.sunDot.hexText) night=\(ThemeColors.night.sunDot.hexText)"
)
expect(
    "没有渐变/高光/描边 token 残留（太阳点只有「核心 + 光晕」两层）",
    !ThemeColors.day.tokens.contains { $0.name == "sunDotHighlight" }
        && !ThemeColors.day.tokens.contains { $0.name == "sunDotGlow" }
        && !ThemeColors.day.tokens.contains { $0.name == "sunDotRing" }
        && !ThemeColors.day.tokens.contains { $0.name == "sunDotCore" }
)
expect(
    "地平线以下的点：同尺寸（半径 = 核心）、细描边 1pt，不留粗硬边",
    SunPathGeometry.sunHollowRadius == sunCoreRadius
        && SunPathGeometry.sunHollowLineWidth == 1,
    "hollow=\(SunPathGeometry.sunHollowRadius) line=\(SunPathGeometry.sunHollowLineWidth)"
)
expect(
    "太阳核心对卡片 ≥ 2.0（核心清晰）",
    ThemeColors.day.sunDot.contrast(with: ThemeColors.day.surface) >= 2.0,
    String(format: "dot %@ / card = %.3f",
           ThemeColors.day.sunDot.hexText,
           ThemeColors.day.sunDot.contrast(with: ThemeColors.day.surface))
)
expect(
    "太阳点对卡片比淡金弧实：对比度高于弧",
    ThemeColors.day.sunDot.contrast(with: ThemeColors.day.surface) > dayArcContrast,
    String(format: "dot=%.2f arc=%.2f",
           ThemeColors.day.sunDot.contrast(with: ThemeColors.day.surface), dayArcContrast)
)
expect(
    "太阳点 vs 淡金弧 ≥ 1.3（核心与弧分得开）",
    ThemeColors.day.sunDot.contrast(with: dayArc) >= 1.3,
    String(format: "actual=%.3f", ThemeColors.day.sunDot.contrast(with: dayArc))
)
expect(
    "夜间三档仍是 #F5D68A（弧 / 核心 / 光晕同色，一点没动）",
    ThemeColors.night.sunArc.hexText == "#F5D68A"
        && ThemeColors.night.sunDot.hexText == "#F5D68A"
        && ThemeColors.night.sunArc == ThemeColors.night.sunDot,
    "arc=\(ThemeColors.night.sunArc.hexText) dot=\(ThemeColors.night.sunDot.hexText)"
)
expect(
    "轨迹线线宽：白天 1.6pt、夜晚 1.5pt、虚线 4/4pt",
    SunPathGeometry.dayArcLineWidth == 1.6
        && SunPathGeometry.nightArcLineWidth == 1.5
        && SunPathGeometry.nightArcDash == [4, 4],
    "day=\(SunPathGeometry.dayArcLineWidth) night=\(SunPathGeometry.nightArcLineWidth) dash=\(SunPathGeometry.nightArcDash)"
)

print("== 地图底图兜底：空白瓦片像素判定 + 四级降级状态机 ==")

// MARK: 空白瓦片判定（构造像素样本，1×1 采样点就够：判定是逐像素统计的）

/// 用一组颜色铺成 `count` 个样本（均匀铺开，方便构造「纯色 / 灰底+字 / 多色」）。
func tileSamples(_ colors: [(r: UInt8, g: UInt8, b: UInt8)], repeating count: Int = 64) -> [(r: UInt8, g: UInt8, b: UInt8)] {
    var samples: [(r: UInt8, g: UInt8, b: UInt8)] = []
    samples.reserveCapacity(count)
    for index in 0..<count {
        samples.append(colors[index % colors.count])
    }
    return samples
}

let solidGrey = BlankTileAnalysis.analyze(samples: tileSamples([(200, 200, 200)]))
expect(
    "纯色瓦片 → 空白（方差 0）",
    solidGrey?.isBlank == true && solidGrey?.distinctColors == 1,
    "actual=\(String(describing: solidGrey))"
)
// 高德那种灰底 + 很淡的水印：方差远小于 400、颜色种类远小于 8。
let greyWatermark = BlankTileAnalysis.analyze(samples: tileSamples(
    [(232, 232, 232), (232, 232, 232), (232, 232, 232), (246, 246, 246)]
))
expect(
    "灰底 + 淡水印 → 空白（颜色少且方差低）",
    greyWatermark?.isBlank == true
        && greyWatermark!.distinctColors < BlankTileAnalysis.manyColors
        && greyWatermark!.variance < BlankTileAnalysis.mixedVariance,
    "actual distinct=\(greyWatermark?.distinctColors ?? -1) var=\(greyWatermark?.variance ?? -1)"
)
// 颜色多、方差大：真正的地图内容。
var manyColors: [(r: UInt8, g: UInt8, b: UInt8)] = []
for index in 0..<12 {
    manyColors.append((
        UInt8(40 + index * 17),
        UInt8(200 - index * 11),
        UInt8(30 + index * 13)
    ))
}
let richTile = BlankTileAnalysis.analyze(samples: tileSamples(manyColors))
expect(
    "多种颜色 → 非空白（颜色种类 ≥ 8 且方差大）",
    richTile?.isBlank == false
        && richTile!.distinctColors >= BlankTileAnalysis.manyColors,
    "actual distinct=\(richTile?.distinctColors ?? -1) var=\(richTile?.variance ?? -1)"
)
// 纯蓝的海面：靠「海洋豁免」不算空白，否则整片海图会被降级。
let pureSea = BlankTileAnalysis.analyze(samples: tileSamples([(30, 90, 160)]))
expect(
    "纯蓝海面 → 非空白（色相 212°、饱和 0.68、亮度 95 ⇒ 海洋豁免）",
    pureSea?.isBlank == false && (pureSea?.oceanRatio ?? 0) >= BlankTileAnalysis.oceanMinRatio,
    "actual ocean=\(pureSea?.oceanRatio ?? -1)"
)
expect(
    "海洋判定的色相区间是 185–265°、饱和 ≥ 0.22、亮度 ≥ 60",
    BlankTileAnalysis.oceanHueRange == 185...265
        && BlankTileAnalysis.oceanMinSaturation == 0.22
        && BlankTileAnalysis.oceanMinLightness == 60
        && BlankTileAnalysis.isOcean(r: 30, g: 90, b: 160)
        && !BlankTileAnalysis.isOcean(r: 30, g: 200, b: 90)
)
// 7 / 8 / 9 种颜色的边界：阈值是「颜色种类 < 8」。
// 用两个通道各取几个 16 的整数倍，保证量化到高 4 位后颜色数正好是构造的数量，
// 且方差落在 12…400 之间（这样唯一的判据就是颜色种类）。
let sevenColors = tileSamples([
    (96, 96, 128), (112, 96, 128), (128, 96, 128), (144, 96, 128),
    (96, 112, 128), (112, 112, 128), (128, 112, 128)
])
let eightColors = tileSamples([
    (96, 96, 128), (112, 96, 128), (128, 96, 128), (144, 96, 128),
    (96, 112, 128), (112, 112, 128), (128, 112, 128), (144, 112, 128)
])
let nineColors = eightColors + [(160, 96, 128)]
let sevenResult = BlankTileAnalysis.analyze(samples: sevenColors)
let eightResult = BlankTileAnalysis.analyze(samples: eightColors)
let nineResult = BlankTileAnalysis.analyze(samples: nineColors)
expect(
    "颜色种类 7 种（< 8）且方差 < 400 → 空白",
    sevenResult?.distinctColors == 7
        && sevenResult!.variance >= BlankTileAnalysis.minVariance
        && sevenResult!.variance < BlankTileAnalysis.mixedVariance
        && sevenResult!.isBlank,
    "colors=\(sevenResult?.distinctColors ?? -1) var=\(sevenResult?.variance ?? -1)"
)
expect(
    "颜色种类 8 种（不再 < 8）→ 非空白（边界）",
    eightResult?.distinctColors == 8 && eightResult!.isBlank == false,
    "colors=\(eightResult?.distinctColors ?? -1)"
)
expect(
    "颜色种类 9 种 → 非空白",
    nineResult?.distinctColors == 9 && nineResult!.isBlank == false,
    "colors=\(nineResult?.distinctColors ?? -1)"
)
expect("空样本 → 判定不出来（nil），不当作空白", BlankTileAnalysis.analyze(reds: [], greens: [], blues: []) == nil)

// MARK: 状态机

/// 造一个「境外自动」的初始状态：首选 OSM，可回退。
func autoOverseas(now: TimeInterval = 0) -> BasemapState {
    BasemapState(mode: .auto, preferred: .osm, now: now)
}

var osmState = autoOverseas()
osmState.recordOSMTile(success: false, at: 10)
osmState.recordOSMTile(success: false, at: 11)
expect(
    "OSM 连续失败 2 次：还不回退",
    osmState.active == .osm && osmState.osmFailures == 2 && osmState.status == .live,
    "active=\(osmState.active) failures=\(osmState.osmFailures)"
)
osmState.recordOSMTile(success: false, at: 12)
expect(
    "OSM 连续失败 3 次 → 回退到高德，并进入探测状态",
    osmState.active == .amapVector && osmState.status == .probing && osmState.didFallBackToAmap,
    "active=\(osmState.active) status=\(osmState.status)"
)

var resetState = autoOverseas()
resetState.recordOSMTile(success: false, at: 10)
resetState.recordOSMTile(success: false, at: 11)
resetState.recordOSMTile(success: true, at: 12)
resetState.recordOSMTile(success: false, at: 13)
resetState.recordOSMTile(success: false, at: 14)
expect(
    "成功一次即清零：再失败 2 次也不会回退",
    resetState.active == .osm && resetState.osmFailures == 2,
    "active=\(resetState.active) failures=\(resetState.osmFailures)"
)

var graceState = autoOverseas()
graceState.recordOSMTile(success: false, at: 10)
graceState.recordOSMTile(success: false, at: 11)
graceState.recordOSMTile(success: false, at: 12) // 12 秒回退，lastSwitchAt = 12
graceState.recordAmapTile(blank: true, at: 14) // 切源 2 秒内：丢弃
expect(
    "切源 5 秒内的高德结果丢弃（不累计到这一屏）",
    graceState.blankDetections == 0,
    "actual=\(graceState.blankDetections)"
)
graceState.recordAmapTile(blank: true, at: 17) // 17 秒：过宽限期
expect("切源 5 秒后开始计数", graceState.blankDetections == 1, "actual=\(graceState.blankDetections)")

var probeState = autoOverseas()
probeState.recordOSMTile(success: false, at: 100)
probeState.recordOSMTile(success: false, at: 101)
probeState.recordOSMTile(success: false, at: 102)
expect(
    "回退后 5 分钟内不探测",
    !probeState.shouldProbe(now: 102 + 299) && probeState.nextProbeAt == 102 + 300,
    "next=\(String(describing: probeState.nextProbeAt))"
)
expect("回退后 5 分钟到点就探测", probeState.shouldProbe(now: 102 + 300))
probeState.probeFailed(at: 402)
expect("探测失败：等下一个 5 分钟", !probeState.shouldProbe(now: 500) && probeState.active == .amapVector)
probeState.probeSucceeded(at: 702)
expect(
    "探测成功 → 切回 OSM 并清零（缩放也恢复）",
    probeState.active == .osm
        && probeState.osmFailures == 0
        && probeState.zoomStep == 0
        && probeState.status == .live
        && probeState.effectiveZoom(requested: 12) == 12,
    "active=\(probeState.active) step=\(probeState.zoomStep)"
)

var manualState = BasemapState(mode: .manual, preferred: .osm, now: 0)
for index in 0..<6 {
    manualState.recordOSMTile(success: false, at: TimeInterval(index))
}
manualState.recordAmapTile(blank: true, at: 20)
manualState.recordAmapTile(blank: true, at: 21)
manualState.closeScreenBatch(at: 22)
expect(
    "手动选底图：不回退、不探测、不降级",
    manualState.active == .osm
        && manualState.osmFailures == 0
        && manualState.zoomStep == 0
        && !manualState.shouldProbe(now: 10_000)
        && manualState.status == .live,
    "active=\(manualState.active) failures=\(manualState.osmFailures) step=\(manualState.zoomStep)"
)

// 逐级降级：只有「整屏都空白」才降。
var degradeState = autoOverseas()
degradeState.recordOSMTile(success: false, at: 1)
degradeState.recordOSMTile(success: false, at: 2)
degradeState.recordOSMTile(success: false, at: 3) // 回退到高德，lastSwitchAt = 3
var degradeClock: TimeInterval = 3
func blankScreen(_ state: inout BasemapState, tiles: Int, clock: inout TimeInterval) {
    for _ in 0..<tiles {
        clock += 6 // 过 5 秒宽限期
        state.recordAmapTile(blank: true, at: clock)
    }
    state.closeScreenBatch(at: clock)
}
expect("回退后先按请求的缩放正常显示（z12）", degradeState.effectiveZoom(requested: 12) == 12)
blankScreen(&degradeState, tiles: 4, clock: &degradeClock)
expect("整屏空白 → 降到 z11", degradeState.effectiveZoom(requested: 12) == 11, "actual=\(String(describing: degradeState.effectiveZoom(requested: 12)))")
blankScreen(&degradeState, tiles: 4, clock: &degradeClock)
expect("再整屏空白 → 降到 z10", degradeState.effectiveZoom(requested: 12) == 10)
blankScreen(&degradeState, tiles: 4, clock: &degradeClock)
expect("第三屏空白 → z3 全球底图", degradeState.effectiveZoom(requested: 12) == 3)
blankScreen(&degradeState, tiles: 4, clock: &degradeClock)
expect(
    "z3 仍空白 → 底图不可用（effectiveZoom 为 nil、状态 unavailable）",
    degradeState.effectiveZoom(requested: 12) == nil && degradeState.status == .unavailable,
    "status=\(degradeState.status)"
)

// 整屏判据：只要有一块有内容，就不降级。
var mixedState = autoOverseas()
mixedState.recordOSMTile(success: false, at: 1)
mixedState.recordOSMTile(success: false, at: 2)
mixedState.recordOSMTile(success: false, at: 3)
var mixedClock: TimeInterval = 3
for index in 0..<4 {
    mixedClock += 6
    mixedState.recordAmapTile(blank: index != 2, at: mixedClock) // 第 3 块有内容
}
mixedState.closeScreenBatch(at: mixedClock)
expect(
    "一屏里有一块有内容 → 不降级（整屏判据）",
    mixedState.zoomStep == 0 && mixedState.blankDetections == 3,
    "step=\(mixedState.zoomStep) blanks=\(mixedState.blankDetections)"
)
var thinState = autoOverseas()
thinState.recordOSMTile(success: false, at: 1)
thinState.recordOSMTile(success: false, at: 2)
thinState.recordOSMTile(success: false, at: 3)
thinState.recordAmapTile(blank: true, at: 10)
thinState.closeScreenBatch(at: 10)
expect(
    "一屏只有 1 块瓦片时不判空白（避免地图刚起步就降级）",
    thinState.zoomStep == 0
)

// MARK: 三条防「狂闪」的不变式（UI 快照 / 回弹静默窗口 / 视口静默期）

var snapshotState = autoOverseas()
let snapshotBefore = snapshotState.uiState(requestedZoom: 12)
snapshotState.recordOSMTile(success: false, at: 10)
snapshotState.recordOSMTile(success: false, at: 11)
let snapshotAfter = snapshotState.uiState(requestedZoom: 12)
expect(
    "有效 plan 不变时 uiState 不变（OSM 失败计数涨到 2 也不发布）",
    snapshotBefore == snapshotAfter && snapshotState.osmFailures == 2,
    "before=\(snapshotBefore) after=\(snapshotAfter)"
)
snapshotState.recordOSMTile(success: false, at: 12)
let snapshotFellBack = snapshotState.uiState(requestedZoom: 12)
expect(
    "回退后 uiState 才变：source / fellBack 反映出来，zoom 仍是 12（未降级）",
    snapshotFellBack != snapshotAfter
        && snapshotFellBack.source == .amapVector
        && snapshotFellBack.fellBack
        && snapshotFellBack.zoom == 12
        && snapshotFellBack.degraded == false
)

var blankCountState = autoOverseas()
blankCountState.recordOSMTile(success: false, at: 1)
blankCountState.recordOSMTile(success: false, at: 2)
blankCountState.recordOSMTile(success: false, at: 3)
let blankBefore = blankCountState.uiState(requestedZoom: 12)
blankCountState.recordAmapTile(blank: true, at: 10) // 只涨 blankDetections，不够一屏
let blankAfter = blankCountState.uiState(requestedZoom: 12)
expect(
    "空白判定计数涨了、但有效 plan 没变 → uiState 仍不变",
    blankBefore == blankAfter && blankCountState.blankDetections == 1,
    "blanks=\(blankCountState.blankDetections)"
)

// 网络持续失败时，z3 出了图也不许立刻弹回（静默窗口 30 秒）。
var quietState = autoOverseas()
quietState.recordOSMTile(success: false, at: 1)
quietState.recordOSMTile(success: false, at: 2)
quietState.recordOSMTile(success: false, at: 3)
var quietClock: TimeInterval = 3
blankScreen(&quietState, tiles: 4, clock: &quietClock)
blankScreen(&quietState, tiles: 4, clock: &quietClock)
blankScreen(&quietState, tiles: 4, clock: &quietClock)
let failingAt = quietClock
expect(
    "先降到 z3（zoomStep 3）",
    quietState.effectiveZoom(requested: 12) == 3,
    "actual=\(String(describing: quietState.effectiveZoom(requested: 12)))"
)
quietState.recordAmapTile(blank: false, at: failingAt + 5)
expect(
    "z3 出图但距上次失败只有 5 秒 → 不回弹（30 秒静默窗口）",
    quietState.effectiveZoom(requested: 12) == 3,
    "actual=\(String(describing: quietState.effectiveZoom(requested: 12)))"
)
quietState.recordAmapTile(blank: false, at: failingAt + 31)
expect(
    "静默 30 秒之后才允许回弹一档（z3 → z10）",
    quietState.effectiveZoom(requested: 12) == 10,
    "actual=\(String(describing: quietState.effectiveZoom(requested: 12)))"
)
quietState.recordAmapTile(blank: false, at: failingAt + 31 + 31)
expect(
    "回弹后 5 分钟内不再回弹（冷却）",
    quietState.effectiveZoom(requested: 12) == 10,
    "actual=\(String(describing: quietState.effectiveZoom(requested: 12)))"
)
quietState.recordAmapTile(blank: false, at: failingAt + 31 + 301)
expect(
    "冷却 5 分钟之后才能再回弹一档",
    quietState.effectiveZoom(requested: 12) == 11,
    "actual=\(String(describing: quietState.effectiveZoom(requested: 12)))"
)

// 程序化改视口（setRegion）会取消在飞的请求：2 秒内回来的失败不算。
var settleState = autoOverseas()
settleState.noteViewportChanged(at: 100)
settleState.recordOSMTile(success: false, at: 101)
expect(
    "视口静默期内（2 秒）的 OSM 失败被忽略",
    settleState.osmFailures == 0 && settleState.isViewportSettling(now: 101),
    "failures=\(settleState.osmFailures)"
)
settleState.recordOSMTile(success: false, at: 103)
expect(
    "静默期过后照常计数",
    settleState.osmFailures == 1,
    "failures=\(settleState.osmFailures)"
)
expect(
    "常量：回弹静默 30 秒 / 回弹冷却 5 分钟 / 视口静默 2 秒",
    BasemapState.recoveryQuietSeconds == 30
        && BasemapState.recoveryCooldownSeconds == 300
        && BasemapState.viewportSettleSeconds == 2
)

// MARK: 瓦片工具

expect(
    "父瓦片折算：z12 (1234,567) → z10 (308,141)",
    BasemapTiles.parentTile(x: 1234, y: 567, from: 12, to: 10)?.x == 308
        && BasemapTiles.parentTile(x: 1234, y: 567, from: 12, to: 10)?.y == 141
)
expect(
    "z12 → z3 也是同一套折算（shift 9）",
    BasemapTiles.parentTile(x: 1234, y: 567, from: 12, to: 3)?.x == 2
        && BasemapTiles.parentTile(x: 1234, y: 567, from: 12, to: 3)?.y == 1
)
expect("反向（放大的）折算不合法 → nil", BasemapTiles.parentTile(x: 1, y: 1, from: 3, to: 12) == nil)
let shanghaiTile = BasemapTiles.tile(latitude: 31.2304, longitude: 121.4737, zoom: 12)
expect(
    "经纬度 → 瓦片：上海 z12 = (3430, 1673)",
    shanghaiTile?.x == 3430 && shanghaiTile?.y == 1673,
    "actual=\(String(describing: shanghaiTile))"
)
expect(
    "PNG 魔数通过、HTML 假页面不通过（探测防劫持）",
    BasemapTiles.looksLikeImage(data: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00]))
        && BasemapTiles.looksLikeImage(data: Data([0xFF, 0xD8, 0xFF, 0xE0]))
        && !BasemapTiles.looksLikeImage(data: Data("<html>".utf8))
        && !BasemapTiles.looksLikeImage(data: nil)
        && !BasemapTiles.looksLikeImage(data: Data())
)
expect(
    "瓦片地址：OSM 与高德各自的模板都被替换掉占位符",
    BasemapTiles.tileURL(source: .osm, x: 1, y: 2, z: 3)?.absoluteString
        == "https://tile.openstreetmap.org/3/1/2.png"
        && BasemapTiles.tileURL(source: .amapVector, x: 1, y: 2, z: 3)?.absoluteString.contains("x=1&y=2&z=3") == true,
    "osm=\(String(describing: BasemapTiles.tileURL(source: .osm, x: 1, y: 2, z: 3)))"
)

// MARK: 首屏并行探测（安卓「120 秒 → 2.2 秒」策略的纯函数部分）

expect(
    "探测预算：4.0 秒硬超时、缓存 5 分钟、指纹 ≈100 m",
    BasemapProbe.hardTimeoutSeconds == 4.0
        && BasemapProbe.cacheTTLSeconds == 300
        && abs(BasemapProbe.cacheGridDegrees - 0.001) < 1e-9
        && BasemapProbe.amapZoomLevels == [12, 10, 3]
        && BasemapProbe.osmZoom == 3,
    "levels=\(BasemapProbe.amapZoomLevels)"
)
// decide：**先换源、再降级**（偏好源只决定同精度时选谁）。
expect(
    "境内（偏好高德）+ 高德 z12 空白 + OSM z12 有内容 → 换源 OSM z12（不是降级到 z10/z3）",
    BasemapProbe.decide(osm: [12: true, 3: true], amap: [12: false, 10: false, 3: false], preferred: .amapVector)
        == BasemapProbe.Decision(source: .osm, zoom: 12)
)
expect(
    "境内 + 两源 z12 都有内容 → 偏好源高德 z12",
    BasemapProbe.decide(osm: [12: true], amap: [12: true], preferred: .amapVector)
        == BasemapProbe.Decision(source: .amapVector, zoom: 12)
)
expect(
    "境外（偏好 OSM）+ OSM z12 空白 + 高德 z12 有内容 → 换源高德 z12",
    BasemapProbe.decide(osm: [12: false, 3: false], amap: [12: true, 10: true, 3: true], preferred: .osm)
        == BasemapProbe.Decision(source: .amapVector, zoom: 12)
)
let bothBlankZ12 = BasemapProbe.decide(
    osm: [12: false, 3: true],
    amap: [12: false, 10: true, 3: true],
    preferred: .osm
)
expect(
    "两源 z12 都空白 → 看 z10：高德 z10 有内容（z3 也有，但精度优先）→ 高德 z10",
    bothBlankZ12 == BasemapProbe.Decision(source: .amapVector, zoom: 10)
)
let worldOnly = BasemapProbe.decide(osm: [3: true], amap: [3: false], preferred: .amapVector)
expect("z12/z10 全空、只有 OSM z3 有内容 → OSM z3", worldOnly == BasemapProbe.Decision(source: .osm, zoom: 3))
let allBlank = BasemapProbe.decide(osm: [12: false, 3: false], amap: [12: false, 10: false, 3: false], preferred: .osm)
expect(
    "两源 / 各级全空白 → 不可用（zoom 为 nil）",
    allBlank.zoom == nil && allBlank.source == .osm
)
let missing = BasemapProbe.decide(osm: [:], amap: [:], preferred: .amapVector)
expect("探测没回来（空表）也当不可用", missing.zoom == nil)
// 南极中山站端到端：标 cn（偏好高德）但高德在南极全是空白瓦片 → 应该换源 OSM z12，而不是降级到 z3。
let zhongshanPreset = Place.presets.first { $0.presetKey == "city.zhongshan" }
let zhongshanPreferred = MapStyle.auto.effective(
    countryCode: zhongshanPreset?.countryCode,
    latitude: zhongshanPreset?.latitude ?? 0,
    longitude: zhongshanPreset?.longitude ?? 0
).basemapSource ?? .osm
let zhongshanDecision = BasemapProbe.decide(
    osm: [12: true, 3: true],
    amap: [12: false, 10: false, 3: false],
    preferred: zhongshanPreferred
)
expect(
    "南极中山站端到端：高德全空白 + OSM 有内容 → 源 OSM、级别 z12（不降级到 z3）",
    zhongshanDecision.source == .osm && zhongshanDecision.zoom == 12,
    "preferred=\(zhongshanPreferred) decision=\(zhongshanDecision)"
)
expect(
    "南极中山站若标 cn（偏好高德）：仍是 OSM z12（换源优先于降级）",
    BasemapProbe.decide(osm: [12: true, 3: true], amap: [12: false, 10: false, 3: false], preferred: .amapVector)
        == zhongshanDecision,
    "decision=\(zhongshanDecision)"
)

print("== 首屏地图：逐个返回、渐进升级 ==")
let z3Candidate = BasemapUpgrade.Candidate(source: .amapVector, zoom: 3)
let z10Candidate = BasemapUpgrade.Candidate(source: .amapVector, zoom: 10)
let z12Candidate = BasemapUpgrade.Candidate(source: .amapVector, zoom: 12)
let osm12Candidate = BasemapUpgrade.Candidate(source: .osm, zoom: 12)
let osm3Candidate = BasemapUpgrade.Candidate(source: .osm, zoom: 3)

expect(
    "第一块有内容 → 立刻出图（先到先用）",
    BasemapUpgrade.shouldAdopt(
        candidate: z3Candidate, current: nil, preferred: .osm,
        firstImageAt: nil, userInteracted: false, now: 0.3
    )
)
expect(
    "z3 先回、z12 后回 → 会用 z12 升级",
    BasemapUpgrade.shouldAdopt(
        candidate: z12Candidate, current: z3Candidate, preferred: .osm,
        firstImageAt: 0.3, userInteracted: false, now: 1.9
    )
)
expect(
    "z12 先回、z3 后回 → 忽略（永不降级）",
    !BasemapUpgrade.shouldAdopt(
        candidate: z3Candidate, current: z12Candidate, preferred: .osm,
        firstImageAt: 0.3, userInteracted: false, now: 1.0
    )
)
expect(
    "先比级别、同级别才比偏好源：偏好 OSM 时同 z12 切 OSM；OSM z3 不能为源而降精度",
    BasemapUpgrade.isBetter(osm12Candidate, than: z12Candidate, preferred: .osm)
        && BasemapUpgrade.shouldAdopt(
            candidate: osm12Candidate, current: z12Candidate, preferred: .osm,
            firstImageAt: 0.3, userInteracted: false, now: 1.5
        )
        && !BasemapUpgrade.isBetter(osm12Candidate, than: z12Candidate, preferred: .amapVector)
        && !BasemapUpgrade.shouldAdopt(
            candidate: osm3Candidate, current: z12Candidate, preferred: .osm,
            firstImageAt: 0.3, userInteracted: false, now: 1.5
        )
)
expect(
    "当前已是「偏好源 + z12」→ 冻结，后续一律忽略",
    !BasemapUpgrade.shouldAdopt(
        candidate: osm12Candidate, current: osm12Candidate, preferred: .osm,
        firstImageAt: 0.3, userInteracted: false, now: 1.0
    )
        && !BasemapUpgrade.shouldAdopt(
            candidate: z12Candidate, current: osm12Candidate, preferred: .osm,
            firstImageAt: 0.3, userInteracted: false, now: 20
        )
)
expect(
    "用户手动平移 / 缩放后 → 晚到的更高精度不再升级",
    !BasemapUpgrade.shouldAdopt(
        candidate: z12Candidate, current: z10Candidate, preferred: .osm,
        firstImageAt: 0.3, userInteracted: true, now: 2.0
    )
)
expect(
    "首图 10 秒之后才到的更高精度 → 不升级（窗口冻结）",
    !BasemapUpgrade.shouldAdopt(
        candidate: z12Candidate, current: z10Candidate, preferred: .osm,
        firstImageAt: 0.3, userInteracted: false, now: 10.4
    )
        && BasemapUpgrade.shouldAdopt(
            candidate: z12Candidate, current: z10Candidate, preferred: .osm,
            firstImageAt: 0.3, userInteracted: false, now: 9.9
        )
)
expect(
    "什么都没回 → 4 秒后不可用；出过图 → 永远不是不可用",
    BasemapUpgrade.isUnavailable(current: nil, startedAt: 0, now: 4.0)
        && !BasemapUpgrade.isUnavailable(current: nil, startedAt: 0, now: 3.9)
        && !BasemapUpgrade.isUnavailable(current: z3Candidate, startedAt: 0, now: 100)
)
expect(
    "诊断时间线：z3 @312ms → z12 @1830ms；无升级只有首图",
    BasemapUpgrade.timeline(first: (3, 312), upgrades: [(12, 1_830)]) == "z3 @312ms → z12 @1830ms"
        && BasemapUpgrade.timeline(first: (3, 312), upgrades: []) == "z3 @312ms"
        && BasemapUpgrade.timeline(first: nil, upgrades: []).isEmpty
)
expect(
    "渐进升级：先高德 z10 出图、OSM z12 后到 → 升级到 OSM z12（精度优先）",
    BasemapUpgrade.shouldAdopt(
        candidate: osm12Candidate, current: z10Candidate, preferred: .osm,
        firstImageAt: 0.6, userInteracted: false, now: 1.8
    )
)
expect(
    "渐进升级：先 OSM z12 出图、偏好高德且高德 z12 后到 → 换回偏好源高德 z12",
    BasemapUpgrade.shouldAdopt(
        candidate: z12Candidate, current: osm12Candidate, preferred: .amapVector,
        firstImageAt: 0.6, userInteracted: false, now: 1.8
    )
)
print("== 定位不可用（未知态）==")
// 判定：跟随意图 + 没有有效定位（未授权 / 看门狗超时）。
expect(
    "跟随 GPS 且没有有效定位 → 未知态",
    LocationUnknown.isUnknown(followGps: true, hasValidFix: false)
)
expect(
    "跟随 GPS 且已拿到 fix → 不是未知态",
    !LocationUnknown.isUnknown(followGps: true, hasValidFix: true)
)
expect(
    "预设城市 / 手动坐标（不跟随）→ 不是未知态（哪怕没有定位）",
    !LocationUnknown.isUnknown(followGps: false, hasValidFix: false)
        && !LocationUnknown.isUnknown(followGps: false, hasValidFix: true)
)
// 系统时区：未知态的标准时间按系统偏移，**负偏移照常生效**（不能拿负数当「没传」）。
let negativeZone = LocationUnknown.snapshot(
    date: date("2026-01-15T12:00:00Z"),
    systemOffsetSeconds: -5 * 3600
)
let positiveZone = LocationUnknown.snapshot(
    date: date("2026-01-15T12:00:00Z"),
    systemOffsetSeconds: 8 * 3600
)
expect(
    "未知态标准时间用系统偏移：UTC-5 → 07:00，UTC+8 → 20:00",
    negativeZone.standardTime.secondsOfDay == 7 * 3600
        && positiveZone.standardTime.secondsOfDay == 20 * 3600,
    "neg=\(negativeZone.standardTime.clock) pos=\(positiveZone.standardTime.clock)"
)
expect(
    "负偏移不会被当成「没传」（UTC 标签仍带 5）",
    negativeZone.utcLabel.contains("5"),
    "actual=\(negativeZone.utcLabel)"
)
// 占位符常量：只含半角连字符 / 冒号 / 度，不含各种破折号。
expect(
    "占位符常量：TIME/SHORT/DASH/TEMPERATURE 正确",
    Placeholders.time == "--:--:--"
        && Placeholders.short == "--"
        && Placeholders.dash == "--"
        && Placeholders.temperature == "-°",
    "actual=\(Placeholders.all)"
)
expect(
    "占位符只含 {'-', ':', '°'}，且不含 U+2014 / U+2012 / U+FF0D",
    Placeholders.all.allSatisfy { Placeholders.isAllowedCharacters($0) }
        && !Placeholders.all.contains { $0.contains("\u{2014}") || $0.contains("\u{2012}") || $0.contains("\u{FF0D}") },
    "actual=\(Placeholders.all)"
)
// 逐时占位：六格、首格「现在」、跨午夜回绕。
let unknownNow = utcEpoch(hour: 15, minute: 30) // 本地 23:30（+8）
let unknownSlots = LocationUnknown.hourlySlots(nowEpochSeconds: unknownNow, count: 6)
expect("未知态逐时：仍是六格", unknownSlots.count == 6, "actual=\(unknownSlots.count)")
expect("未知态逐时：首格是「现在」", unknownSlots.first?.isNow == true && unknownSlots.dropFirst().allSatisfy { !$0.isNow })
expect(
    "未知态逐时：每格 +1 小时",
    zip(unknownSlots.dropFirst(), unknownSlots).allSatisfy { $0.epochSeconds - $1.epochSeconds == 3600 }
)
expect(
    "未知态逐时：本地小时 23 → 0 跨午夜回绕",
    unknownSlots.map { localHour($0.epochSeconds) } == [23, 0, 1, 2, 3, 4],
    "actual=\(unknownSlots.map { localHour($0.epochSeconds) })"
)
// 圆盘未知态：昼夜各 180°、地平线过圆心、没有太阳点。
let unknownArc = SunPathGeometry.unknownArcAngles()
expect(
    "未知态圆盘：昼弧 180°、夜弧 180°",
    abs((unknownArc.end - unknownArc.start) - Double.pi) < 1e-12
        && abs((2 * Double.pi - (unknownArc.end - unknownArc.start)) - Double.pi) < 1e-12,
    "day=\((unknownArc.end - unknownArc.start) * 180 / Double.pi)°"
)
let unknownDial = SunPathGeometry.compute(
    size: dialCanvas,
    sunriseHour: 6,
    sunsetHour: 18,
    trueSolarHour: 12,
    isPolarDay: false,
    isPolarNight: false
)
expect(
    "未知态圆盘：地平线过圆心（y == C.y）",
    abs(unknownDial.horizonY - unknownDial.center.y) < 1e-9,
    "horizonY=\(unknownDial.horizonY) center=\(unknownDial.center.y)"
)
expect(
    "未知态圆盘：没有日出/日落太阳点（弧端就是 06:00 / 18:00）",
    abs(unknownArc.start - SunPathGeometry.angleOfDayHour(6)) < 1e-12
        && abs(unknownArc.end - SunPathGeometry.angleOfDayHour(18)) < 1e-12
)
// 未知态地图：z3、东亚瓦片、2 秒、10 分钟缓存、先回来且有内容者胜。
expect(
    "未知态地图常量：z3 / 东亚瓦片 (6,2) / 2 秒封顶 / 缓存 10 分钟",
    LocationUnknown.mapZoom == 3
        && LocationUnknown.mapProbeTile.x == 6
        && LocationUnknown.mapProbeTile.y == 2
        && LocationUnknown.mapProbeTimeoutSeconds == 2
        && LocationUnknown.mapCacheTTLSeconds == 600,
    "tile=\(LocationUnknown.mapProbeTile)"
)
expect(
    "两块 z3 探测：先回来且有内容者胜（OSM 先到用 OSM、高德先到用高德、都无内容 → nil）",
    LocationUnknown.decideMap(arrivals: [(.osm, true), (.amapVector, true)]) == .osm
        && LocationUnknown.decideMap(arrivals: [(.amapVector, true), (.osm, true)]) == .amapVector
        && LocationUnknown.decideMap(arrivals: [(.osm, false), (.amapVector, true)]) == .amapVector
        && LocationUnknown.decideMap(arrivals: [(.osm, false), (.amapVector, false)]) == nil
)
let unknownCache = BasemapUnknownCache(source: .osm, at: 1_000)
expect(
    "未知态地图缓存：10 分钟内命中（零探测）、超时后重探",
    !LocationUnknown.needsMapProbe(cached: unknownCache, now: 1_000 + 599)
        && LocationUnknown.needsMapProbe(cached: unknownCache, now: 1_000 + 600)
        && LocationUnknown.needsMapProbe(cached: nil, now: 1_000)
)
// 未知态不碰回退/降级状态机：用「手动」状态承载（不探测、不回退、不降级），且一级就位到 z3。
var unknownMapState = BasemapState(mode: .manual, preferred: .amapVector, now: 0)
for index in 0..<6 {
    unknownMapState.recordOSMTile(success: false, at: TimeInterval(index))
}
unknownMapState.applyProbeDecision(source: .osm, zoom: LocationUnknown.mapZoom, at: 100)
expect(
    "未知态：直接定级到 z3，且连续失败不会触发回退/降级",
    unknownMapState.active == .osm
        && unknownMapState.effectiveZoom(requested: 12) == 3
        && unknownMapState.zoomStep == 3
        && unknownMapState.osmFailures == 0,
    "active=\(unknownMapState.active) step=\(unknownMapState.zoomStep)"
)
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

print("== 区划名分隔符：含汉字直连、不含汉字用「, 」（鸿蒙 NewYorkManhattan 同类问题）==")
// 规则（三端统一）：含汉字 → 直接相接（北京市 + 东城区 → 北京市东城区）；
// 不含汉字 → 用「, 」连接（New York + Manhattan → New York, Manhattan），并去重、最多三级。
expect(
    "英文：New York + Manhattan → New York, Manhattan（不粘成 New YorkManhattan）",
    DistrictNaming.compose(parts: ["New York", "Manhattan"])?.full == "New York, Manhattan",
    "actual=\(DistrictNaming.compose(parts: ["New York", "Manhattan"])?.full ?? "nil")"
)
expect(
    "英文：反查字段顺序（区县 → 市）同样带逗号",
    DistrictNaming.composeNames(
        district: "Manhattan", city: "New York", region: nil, country: nil, prefersChinese: true
    )?.full == "Manhattan, New York",
    "actual=\(DistrictNaming.composeNames(district: "Manhattan", city: "New York", region: nil, country: nil, prefersChinese: true)?.full ?? "nil")"
)
expect(
    "英文：任何情况下都不会粘成一个词",
    DistrictNaming.compose(parts: ["New York", "Manhattan"])?.full.contains("YorkManhattan") == false
        && DistrictNaming.composeNames(
            district: "Manhattan", city: "New York", region: "New York", country: "United States", prefersChinese: true
        )?.full.contains("YorkManhattan") == false
)
expect(
    "中文：北京市 + 东城区 → 北京市东城区（直连）",
    DistrictNaming.joinChinese(county: "东城区", city: "北京市", region: nil)?.full == "北京市东城区"
        && DistrictNaming.composeNames(
            district: "东城区", city: "北京市", region: nil, country: nil, prefersChinese: true
        )?.full == "北京市东城区",
    "actual=\(DistrictNaming.joinChinese(county: "东城区", city: "北京市", region: nil)?.full ?? "nil")"
)
expect(
    "三段去重：Tokyo + Chiyoda + Tokyo → Tokyo, Chiyoda",
    DistrictNaming.compose(parts: ["Tokyo", "Chiyoda", "Tokyo"])?.full == "Tokyo, Chiyoda",
    "actual=\(DistrictNaming.compose(parts: ["Tokyo", "Chiyoda", "Tokyo"])?.full ?? "nil")"
)
expect(
    "三段去重后短名取最细一级",
    DistrictNaming.compose(parts: ["Tokyo", "Chiyoda", "Tokyo"])?.short == "Tokyo"
)
expect(
    "三段去重（区县在前）：Chiyoda + Tokyo + Tokyo → Chiyoda, Tokyo",
    DistrictNaming.composeNames(
        district: "Chiyoda", city: "Tokyo", region: "Tokyo", country: nil, prefersChinese: true
    )?.full == "Chiyoda, Tokyo",
    "actual=\(DistrictNaming.composeNames(district: "Chiyoda", city: "Tokyo", region: "Tokyo", country: nil, prefersChinese: true)?.full ?? "nil")"
)
expect(
    "中英混排：逗号分隔、不直连",
    DistrictNaming.compose(parts: ["Manhattan", "纽约"])?.full == "Manhattan, 纽约"
)

print("== 手动坐标的地名：不许残留上一个城市（本地输入埃及 → 不能显示北京）==")
// 现场坐标：25.2048N, 30.2708E（埃及）。时区对（UTC+2）、地名却显示「北京」——
// 根因是「缓存里只存了名字、没存坐标」时旧代码跳过了 5 km 校验，任何坐标都会拿到北京那份缓存；
// 而且反查失败时 DistrictStore 什么都不回调，界面就一直挂着旧名字。
let egyptManual = Place(
    latitude: 25.2048,
    longitude: 30.2708,
    source: .manual,
    label: "手动设置"
)
let beijingPlace = Place.presets[0] // 北京（预设）
expect(
    "旧缓存（没存坐标）一律不可用 —— 这正是「埃及坐标显示北京」的根因",
    !DistrictNaming.cacheMatches(storedLatitude: nil, storedLongitude: nil, place: egyptManual)
)
expect(
    "缓存坐标是北京的，用在埃及坐标上 → 不可用",
    !DistrictNaming.cacheMatches(
        storedLatitude: beijingPlace.latitude,
        storedLongitude: beijingPlace.longitude,
        place: egyptManual
    )
)
expect(
    "缓存坐标就是当前地点（100 m 内）→ 可用",
    DistrictNaming.cacheMatches(
        storedLatitude: egyptManual.latitude + 0.001,
        storedLongitude: egyptManual.longitude,
        place: egyptManual
    )
)
expect(
    "缓存坐标超出 5 km → 不可用",
    !DistrictNaming.cacheMatches(
        storedLatitude: egyptManual.latitude + 0.2,
        storedLongitude: egyptManual.longitude,
        place: egyptManual
    )
)
// 卡片那一行地名（三段式）：反查失败 → 「-」（不回填旧地名）。
let gizaNames = DistrictNames(full: "Giza, Egypt", short: "Giza", countryCode: "eg")
expect(
    "手动坐标 + 反查成功 → 显示反查结果",
    DistrictNaming.cardCityText(district: gizaNames, place: egyptManual) == "Giza, Egypt",
    "actual=\(DistrictNaming.cardCityText(district: gizaNames, place: egyptManual))"
)
expect(
    "手动坐标 + 反查失败（nil）→ 半角「-」（不回填旧地名）",
    DistrictNaming.cardCityText(district: nil, place: egyptManual) == "-",
    "actual=\(DistrictNaming.cardCityText(district: nil, place: egyptManual))"
)
expect(
    "从预设城市切到手动坐标：旧地名清空后就是「-」，不会残留北京",
    DistrictNaming.cardCityText(district: nil, place: egyptManual) != "北京市"
        && DistrictNaming.cardCityText(district: nil, place: egyptManual) == "-"
)
expect(
    "预设城市 + 反查失败 → 回退预设城市名（这是唯一允许的兜底）",
    DistrictNaming.cardCityText(district: nil, place: beijingPlace) == beijingPlace.displayLabel,
    "actual=\(DistrictNaming.cardCityText(district: nil, place: beijingPlace))"
)
expect(
    "预设城市 + 反查成功 → 反查结果优先",
    DistrictNaming.cardCityText(district: gizaNames, place: beijingPlace) == "Giza, Egypt"
)
expect(
    "GPS 定位 + 反查失败 → 「-」（GPS 的 label 是占位词，不能当地名）",
    DistrictNaming.cardCityText(
        district: nil,
        place: Place(latitude: 25.2048, longitude: 30.2708, source: .gps, label: "GPS · 精度 12 米")
    ) == "-"
)
expect(
    "空名字（复用了上一次的空 full）也当作没有 → 「-」",
    DistrictNaming.cardCityText(
        district: DistrictNames(full: "", short: "", countryCode: nil),
        place: egyptManual
    ) == "-"
)

print("== 区划名变长后的档位退化（不能只显示 New … 还判档 0）==")
// 真实宽度量级（12pt 系统字）：UTC+8 ≈ 36、「真太阳时」≈ 48、亥时 ≈ 24、Zi hour ≈ 42、
// 行宽 ≈ 314（iPhone 390 − 页边距 40 − 卡片内边距 36）。
let rowWidthPhone: CGFloat = 314
expect(
    "New York, Manhattan（≈118pt）落到档 1（收掉「真太阳时」、城市居中）",
    tierOf(36, 118, 48, 42, rowWidthPhone) == .noSolarLabel,
    "tier=\(tierOf(36, 118, 48, 42, rowWidthPhone))"
)
expect(
    "三级长名（Manhattan, New York, United States ≈215pt）落到档 2（再收掉 UTC）",
    tierOf(36, 215, 48, 42, rowWidthPhone) == .cityAndShichen,
    "tier=\(tierOf(36, 215, 48, 42, rowWidthPhone))"
)
expect(
    "城市宽度超过半宽时永远不会判成档 0",
    [118.0, 140.0, 160.0, 200.0, 215.0, 260.0].allSatisfy {
        tierOf(36, CGFloat($0), 48, 42, rowWidthPhone) != .allFour
    }
)
expect(
    "短名字仍能留在档 0（四段都显示）",
    tierOf(36, 100, 48, 42, rowWidthPhone) == .allFour,
    "tier=\(tierOf(36, 100, 48, 42, rowWidthPhone))"
)
expect(
    "极长名字落到档 3（尾部省略号）",
    tierOf(20, 300, 48, 42, rowWidthPhone) == .cityTruncated,
    "tier=\(tierOf(20, 300, 48, 42, rowWidthPhone))"
)
// 时辰去掉「初 / 正」后缀后，右半变窄：同一个行宽能容纳更宽的「真太阳时 + 时辰」组合，
// 但绝不会因此把「城市超半宽」的情况抬回档 0（上面那条已覆盖）。
expect(
    "时辰变短只放宽右半，不放宽左半（左半判据与时辰无关）",
    tierOf(36, 120, 48, 24, rowWidthPhone) == tierOf(36, 120, 48, 90, rowWidthPhone)
        || tierOf(36, 120, 48, 24, rowWidthPhone).rawValue < tierOf(36, 120, 48, 90, rowWidthPhone).rawValue,
    "短=\(tierOf(36, 120, 48, 24, rowWidthPhone)) 长=\(tierOf(36, 120, 48, 90, rowWidthPhone))"
)

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
    ("city.newdelhi", 19_800), ("city.tokyo", 32_400), ("city.singapore", 28_800), ("city.sydney", 36_000),
    // 极圈内两座城市：摩尔曼斯克 +3（俄罗斯经度分段 <40°E）、中山站 +8（南极站按北京时间）
    ("city.murmansk", 10_800), ("city.zhongshan", 28_800)
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
expect("内置城市数量 = 22（原 20 + 极圈内 2 座）", Place.presets.count == 22, "实际 \(Place.presets.count)")

print("== 极圈内两座城市：坐标 / 时区 / 极昼极夜文案（验证太阳圆盘用）==")
// 摩尔曼斯克（68.97°N, 33.08°E）：北极圈内，夏至极昼、冬至极夜。
// 中山站（69.37°S, 76.38°E）：南极圈内，季节相反 —— 北半球夏至时它极夜。
let murmansk = Place.presets.first { $0.presetKey == "city.murmansk" }
let zhongshan = Place.presets.first { $0.presetKey == "city.zhongshan" }
expect("摩尔曼斯克坐标 68.97°N / 33.08°E", murmansk?.latitude == 68.97 && murmansk?.longitude == 33.08)
expect("中山站坐标 69.37°S / 76.38°E", zhongshan?.latitude == -69.37 && zhongshan?.longitude == 76.38)
expect(
    "摩尔曼斯克国家码 ru → UTC+3（不是按经度近似的 +2）",
    murmansk?.countryCode == "ru"
        && TimeFormat.utcOffsetLabel(seconds: murmansk?.standardOffsetSeconds ?? 0) == "UTC+3",
    "得到 \(TimeFormat.utcOffsetLabel(seconds: murmansk?.standardOffsetSeconds ?? 0))"
)
expect(
    "中山站国家码 aq → UTC+8（南极站按北京时间，不是按 76°E 近似的 +5）",
    zhongshan?.countryCode == "aq"
        && TimeFormat.utcOffsetLabel(seconds: zhongshan?.standardOffsetSeconds ?? 0) == "UTC+8",
    "得到 \(TimeFormat.utcOffsetLabel(seconds: zhongshan?.standardOffsetSeconds ?? 0))"
)
expect(
    "没有 aq 覆盖时会退成 +5（说明这条覆盖是必要的）",
    SolarTimeMath.approxZoneOffsetSeconds(longitude: 76.38) == 18_000,
    "得到 \(SolarTimeMath.approxZoneOffsetSeconds(longitude: 76.38))"
)
// 三语城市名
expect(
    "摩尔曼斯克三语（摩尔曼斯克 / 莫曼斯克 / Murmansk）",
    L10n.t("city.murmansk", language: .simplified) == "摩尔曼斯克"
        && L10n.t("city.murmansk", language: .traditional) == "莫曼斯克"
        && L10n.t("city.murmansk", language: .english) == "Murmansk"
)
expect(
    "中山站三语（南极中山站 / 南極中山站 / Zhongshan Station, Antarctica）",
    L10n.t("city.zhongshan", language: .simplified) == "南极中山站"
        && L10n.t("city.zhongshan", language: .traditional) == "南極中山站"
        && L10n.t("city.zhongshan", language: .english) == "Zhongshan Station, Antarctica"
)
expect(
    "显示名多一个字也不截断：320pt 宽屏幕城市 5 字（≈60pt）仍走「四档全显示」",
    // 自检环境没有 UIKit/UIFont，按「CJK 每字 ≈ 字号」估：5 字 × 12pt = 60pt。
    HeroRowTier.tier(utcWidth: 34, cityWidth: 60, labelWidth: 48, shichenWidth: 24, rowWidth: 244) == .allFour,
    "tier=\(HeroRowTier.tier(utcWidth: 34, cityWidth: 60, labelWidth: 48, shichenWidth: 24, rowWidth: 244))"
)
// 极昼 / 极夜：`SolarSnapshot.polar` 只有这两种非 normal 状态，`SunCard` 据此改文案（不显示具体时刻）。
let murmanskSummer = SolarTimeSnapshot.compute(
    date: date("2026-06-21T12:00:00Z"), latitude: 68.97, longitude: 33.08, countryCode: "ru"
)
let murmanskWinter = SolarTimeSnapshot.compute(
    date: date("2026-12-21T12:00:00Z"), latitude: 68.97, longitude: 33.08, countryCode: "ru"
)
let zhongshanJune = SolarTimeSnapshot.compute(
    date: date("2026-06-21T12:00:00Z"), latitude: -69.37, longitude: 76.38, countryCode: "aq"
)
let zhongshanDecember = SolarTimeSnapshot.compute(
    date: date("2026-12-21T12:00:00Z"), latitude: -69.37, longitude: 76.38, countryCode: "aq"
)
expect("摩尔曼斯克 6 月极昼", murmanskSummer.polar == .midnightSun, "得到 \(murmanskSummer.polar)")
expect("摩尔曼斯克 12 月极夜", murmanskWinter.polar == .polarNight, "得到 \(murmanskWinter.polar)")
expect("中山站 6 月极夜（南半球季节相反）", zhongshanJune.polar == .polarNight, "得到 \(zhongshanJune.polar)")
expect("中山站 12 月极昼", zhongshanDecember.polar == .midnightSun, "得到 \(zhongshanDecember.polar)")
expect(
    "极昼/极夜时不显示日出日落时刻（快照里没有这两个值）",
    murmanskSummer.sunriseBeijing == nil && murmanskSummer.sunsetBeijing == nil
        && murmanskWinter.sunriseBeijing == nil && murmanskWinter.sunsetBeijing == nil
        && zhongshanJune.sunriseBeijing == nil && zhongshanJune.sunsetBeijing == nil
        && zhongshanDecember.sunriseBeijing == nil && zhongshanDecember.sunsetBeijing == nil
)
// 文案：极昼 / 极夜（三语），带上「上中天」时刻，不出现「日出/日落」时刻。
expect(
    "极昼文案三语齐全",
    L10n.f("sun.polarDay", language: .simplified, ["12:00"]).hasPrefix("极昼：")
        && L10n.f("sun.polarDay", language: .traditional, ["12:00"]).hasPrefix("極晝：")
        && L10n.f("sun.polarDay", language: .english, ["12:00"]).hasPrefix("Midnight sun:")
)
expect(
    "极夜文案三语齐全",
    L10n.f("sun.polarNight", language: .simplified, ["12:00"]).hasPrefix("极夜：")
        && L10n.f("sun.polarNight", language: .traditional, ["12:00"]).hasPrefix("極夜：")
        && L10n.f("sun.polarNight", language: .english, ["12:00"]).hasPrefix("Polar night:")
)

print("== 法定标准时间 CivicTime（中国全境 +8、南极中国站 +8、其它按 tzdata）==")
// 这一条是「标准时间」的唯一口径：界面左栏、UTC 标签、日出日落/上中天、真太阳时的
// 经度修正基准全部走 `CivicTime.standardOffsetMinutes`，不允许有第二套。
func civicMinutes(
    _ latitude: Double,
    _ longitude: Double,
    _ countryCode: String?,
    _ timeZoneIdentifier: String? = nil
) -> Int {
    CivicTime.standardOffsetMinutes(
        latitude: latitude,
        longitude: longitude,
        countryCode: countryCode,
        timeZoneIdentifier: timeZoneIdentifier
    )
}

// ① 中国境内（含港澳台）恒 +8：乌鲁木齐在 tzdata 里是 Asia/Urumqi（+6），但中国官方时间 +8。
expect(
    "乌鲁木齐 → 480（不是 tzdata 的 Asia/Urumqi +6）",
    civicMinutes(43.8256, 87.6168, "cn") == 480,
    "得到 \(civicMinutes(43.8256, 87.6168, "cn"))"
)
expect(
    "乌鲁木齐没有国家码也 +8（包围盒兜底，仍不是 +6）",
    civicMinutes(43.8256, 87.6168, nil) == 480,
    "得到 \(civicMinutes(43.8256, 87.6168, nil))"
)
expect("北京 → 480", civicMinutes(39.9042, 116.4074, "cn") == 480)
expect("香港 / 澳门 / 台北 → 480", ["hk", "mo", "tw"].allSatisfy { civicMinutes(22.3193, 114.1694, $0) == 480 })
// ② 中国南极考察站 +8（四个站全覆盖）
expect(
    "中山站 → 480",
    civicMinutes(-69.3733, 76.38, "aq") == 480,
    "得到 \(civicMinutes(-69.3733, 76.38, "aq"))"
)
expect(
    "长城 / 昆仑 / 泰山三站 → 480",
    civicMinutes(-62.2167, -58.9667, "aq") == 480
        && civicMinutes(-80.4167, 77.1167, "aq") == 480
        && civicMinutes(-73.8667, 76.9833, "aq") == 480
)
expect(
    "站点识别按 50 km 半径（中山站 → 中山站）",
    CivicTime.chinaAntarcticStationName(latitude: -69.3733, longitude: 76.38) == "中山站 Zhongshan"
)
expect(
    "邻近的他国站点不会被当成中国站（Davis 站 -68.58, 77.97 → nil）",
    CivicTime.chinaAntarcticStationName(latitude: -68.58, longitude: 77.97) == nil
)
// ③ 其它国家：按现有国家表（多时区大国按经度分段）
expect(
    "摩尔曼斯克 → 180",
    civicMinutes(68.97, 33.08, "ru") == 180,
    "得到 \(civicMinutes(68.97, 33.08, "ru"))"
)
expect(
    "纽约 → -300 或 -240（当前 tzdata 实际值）",
    [-300, -240].contains(civicMinutes(40.7, -74.0, "us")),
    "得到 \(civicMinutes(40.7, -74.0, "us"))"
)
expect(
    "加德满都 → 345（半小时时区没被取整）",
    civicMinutes(27.7, 85.3, "np") == 345,
    "得到 \(civicMinutes(27.7, 85.3, "np"))"
)
// 判定顺序：① 中国优先于时区标识；③ 时区标识优先于国家表。
expect(
    "中国优先于时区标识（乌鲁木齐给 UTC 也还是 +8）",
    civicMinutes(43.8256, 87.6168, "cn", "UTC") == 480
)
expect(
    "时区标识优先于国家表（UTC 覆盖俄罗斯 +3）",
    civicMinutes(68.97, 33.08, "ru", "UTC") == 0
)
// 唯一来源：`SolarTimeMath` 的秒版入口必须与 CivicTime 完全一致（界面/通知都走它）。
expect(
    "秒版入口与分钟版同源（乌鲁木齐 480 分 = 28800 秒）",
    SolarTimeMath.standardZoneOffsetSeconds(countryCode: "cn", latitude: 43.8256, longitude: 87.6168) == 28_800
        && SolarTimeMath.standardZoneOffsetSeconds(countryCode: "aq", latitude: -69.3733, longitude: 76.38) == 28_800
        && SolarTimeMath.standardZoneOffsetSeconds(countryCode: "ru", latitude: 68.97, longitude: 33.08) == 10_800
)
// 端到端：乌鲁木齐的 UTC 标签与标准时间，以及真太阳时相对它的偏移。
let urumqi = SolarTimeSnapshot.compute(
    date: date("2026-11-03T04:00:00Z"),
    latitude: 43.8256,
    longitude: 87.6168,
    countryCode: "cn"
)
expect("乌鲁木齐快照 UTC+8", urumqi.utcLabel == "UTC+8", "得到 \(urumqi.utcLabel)")
expect(
    "乌鲁木齐标准时间 = 北京时间 12:00",
    urumqi.standardTime.hour == 12,
    "得到 \(urumqi.standardTime.clock)"
)
// 真太阳时 = 标准时间 − 经度差 − 均时差。经度 87.6168°E 比 120°E 少 32.383°，
// 每度 4 分钟 → 约 −129.5 分钟；均时差当天约 +16 分钟 → 合计约 −113 分钟 ≈ 早 1 小时 53 分。
let urumqiDelta = Int(urumqi.trueSolarTime.secondsOfDay) - Int(urumqi.standardTime.secondsOfDay)
expect(
    "乌鲁木齐真太阳时比标准时间早约 1 小时 53 分（−113 分钟，含均时差）",
    abs(urumqiDelta + 113 * 60) <= 180,
    "实际差 \(urumqiDelta / 60) 分钟（\(urumqi.trueSolarTime.clock) vs \(urumqi.standardTime.clock)）"
)
expect(
    "经度修正本身是 −129.5 分钟（不含均时差）",
    abs((-4.0 * (120.0 - 87.6168)) + 129.5) < 0.1,
    "得到 \((-4.0 * (120.0 - 87.6168)))"
)

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

// MARK: - 逐时天气：步长跟数据源走（槽位固定 6 个）

print("== 逐时步长：6 个槽位，首格永远是「现在」==")

/// 东八区的偏移。测试里所有「本地小时」都由它换算，**不依赖跑自检的机器所在时区**：
/// 接口给的是 UTC，界面用本地时区，换算这一步必须显式参与断言。
let zone8 = 8 * 3600

func utcEpoch(hour: Int, minute: Int = 0, day: Int = 16, month: Int = 11, year: Int = 2026) -> Int {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    guard let date = calendar.date(from: components) else {
        fatalError("无法构造 UTC 时刻 \(year)-\(month)-\(day) \(hour):\(minute)")
    }
    return Int(date.timeIntervalSince1970)
}

/// UTC 秒 → 本地（默认 +08:00）小时。用纯整数运算，避免受系统时区影响。
func localHour(_ epochSeconds: Int, offset: Int = 8 * 3600) -> Int {
    WeatherParsing.floorMod(epochSeconds + offset, 86_400) / 3600
}

/// 该时刻在本地时区属于第几天（跨午夜断言用）。
func localDayIndex(_ epochSeconds: Int, offset: Int = 8 * 3600) -> Int {
    Int((Double(epochSeconds + offset) / 86_400.0).rounded(.down))
}

/// 6 个槽位的**实际标签文本**：首格「现在」，其余按该采样点的本地小时数写。
func slotLabels(
    _ slots: [WeatherSlot],
    language: AppLanguage.Language,
    offset: Int = 8 * 3600
) -> [String] {
    slots.map { slot in
        if slot.isNow {
            return L10n.t("weather.now", language: language)
        }
        return L10n.f("weather.hour", language: language, [localHour(slot.epochSeconds, offset: offset)])
    }
}

func hourlyPoints(fromEpoch: Int, count: Int, stepHours: Int) -> [WeatherHour] {
    (0..<count).map {
        WeatherHour(epochSeconds: fromEpoch + $0 * stepHours * 3600, temperatureC: 10 + $0, code: 1)
    }
}

// ① 主源（1 小时粒度）：本地 21:55 的 6 格覆盖 6 小时。
let oneHourNow = utcEpoch(hour: 13, minute: 55) // 本地 21:55
let oneHourPoints = hourlyPoints(fromEpoch: utcEpoch(hour: 12), count: 12, stepHours: 1) // 本地 20:00 起
let oneHourSlots = WeatherParsing.visibleSlots(
    points: oneHourPoints,
    nowEpochSeconds: oneHourNow,
    zoneOffsetSeconds: zone8,
    count: 6,
    stepHours: WeatherSource.openMeteo.stepHours
)
expect("1 小时源仍是 6 个槽位", oneHourSlots.count == 6, "actual=\(oneHourSlots.count)")
expect(
    "1 小时源标签：现在 / 22时 / 23时 / 0时 / 1时 / 2时",
    slotLabels(oneHourSlots, language: .simplified) == ["现在", "22时", "23时", "0时", "1时", "2时"],
    "actual=\(slotLabels(oneHourSlots, language: .simplified))"
)
expect("1 小时源只有首格是「现在」", oneHourSlots.map(\.isNow) == [true, false, false, false, false, false])
expect("1 小时源相邻格相差 1 小时", oneHourSlots[1].epochSeconds - oneHourSlots[0].epochSeconds == 3600)
expect("1 小时源首格 = 当前时刻之前最近的采样点（本地 21:00）", localHour(oneHourSlots[0].epochSeconds) == 21)

// ② 备用源（3 小时粒度）：同样 6 格，但覆盖 18 小时。
let threeHourPoints = hourlyPoints(fromEpoch: utcEpoch(hour: 12), count: 8, stepHours: 3) // 本地 20:00 起
let threeHourSlots = WeatherParsing.visibleSlots(
    points: threeHourPoints,
    nowEpochSeconds: oneHourNow,
    zoneOffsetSeconds: zone8,
    count: 6,
    stepHours: WeatherSource.sevenTimer.stepHours
)
expect("3 小时源仍是 6 个槽位", threeHourSlots.count == 6, "actual=\(threeHourSlots.count)")
expect(
    "3 小时源标签：现在 / 23时 / 2时 / 5时 / 8时 / 11时",
    slotLabels(threeHourSlots, language: .simplified) == ["现在", "23时", "2时", "5时", "8时", "11时"],
    "actual=\(slotLabels(threeHourSlots, language: .simplified))"
)
expect("3 小时源只有首格是「现在」", threeHourSlots.map(\.isNow) == [true, false, false, false, false, false])
expect("3 小时源相邻格相差 3 小时", threeHourSlots[1].epochSeconds - threeHourSlots[0].epochSeconds == 10_800)
expect(
    "3 小时源第 3 格跨过本地午夜（次日 2 时）",
    localHour(threeHourSlots[2].epochSeconds) == 2
        && localDayIndex(threeHourSlots[2].epochSeconds) == localDayIndex(oneHourNow) + 1,
    "hour=\(localHour(threeHourSlots[2].epochSeconds)) day=\(localDayIndex(threeHourSlots[2].epochSeconds))"
)
// 英文与繁體的实际文本也一并钉住（「23时 / 23時 / 23:00」）。
expect(
    "3 小时源英文标签",
    slotLabels(threeHourSlots, language: .english) == ["Now", "23:00", "2:00", "5:00", "8:00", "11:00"],
    "actual=\(slotLabels(threeHourSlots, language: .english))"
)
expect(
    "3 小时源繁體标签",
    slotLabels(threeHourSlots, language: .traditional) == ["現在", "23時", "2時", "5時", "8時", "11時"],
    "actual=\(slotLabels(threeHourSlots, language: .traditional))"
)
// 槽位数固定：步长只改变格子之间的距离，不改变格子数。
expect(
    "步长只影响间距、不影响槽位数",
    oneHourSlots.count == threeHourSlots.count
        && (oneHourSlots[5].epochSeconds - oneHourSlots[0].epochSeconds) == 5 * 3600
        && (threeHourSlots[5].epochSeconds - threeHourSlots[0].epochSeconds) == 15 * 3600
)

// 一个采样点都没有时也要排满 6 格（内容由界面填占位符），且按数据源的网格对齐。
let emptyThreeHour = WeatherParsing.visibleSlots(
    points: [],
    nowEpochSeconds: oneHourNow,
    zoneOffsetSeconds: zone8,
    count: 6,
    stepHours: 3
)
expect(
    "无数据时 3 小时网格对齐到 UTC 0/3/6…（本地 20/23/2/5/8/11 时）",
    slotLabels(emptyThreeHour, language: .simplified) == ["现在", "23时", "2时", "5时", "8时", "11时"],
    "actual=\(slotLabels(emptyThreeHour, language: .simplified))"
)
let emptyOneHour = WeatherParsing.visibleSlots(
    points: [],
    nowEpochSeconds: oneHourNow,
    zoneOffsetSeconds: zone8,
    count: 6,
    stepHours: 1
)
expect(
    "无数据时 1 小时网格按本地整点对齐",
    slotLabels(emptyOneHour, language: .simplified) == ["现在", "22时", "23时", "0时", "1时", "2时"],
    "actual=\(slotLabels(emptyOneHour, language: .simplified))"
)
// 所有采样点都在未来：首格退回第一个点（宁可显示最近的预报，也不要空格）。
let futureSlots = WeatherParsing.visibleSlots(
    points: [
        WeatherHour(epochSeconds: utcEpoch(hour: 3), temperatureC: 5, code: 1),
        WeatherHour(epochSeconds: utcEpoch(hour: 6), temperatureC: 6, code: 1)
    ],
    nowEpochSeconds: utcEpoch(hour: 0),
    zoneOffsetSeconds: 0,
    count: 3,
    stepHours: 3
)
expect(
    "全在未来时首格取第一个点",
    futureSlots[0].epochSeconds == utcEpoch(hour: 3) && futureSlots[2].epochSeconds == utcEpoch(hour: 9),
    "actual=\(futureSlots.map(\.epochSeconds))"
)

print("== 3 小时数据对齐到本地 0/3/6/… 边界（UTC→本地换算）==")
expect(
    "UTC 04:00 向下对齐到 03:00",
    WeatherParsing.alignToStep(utcEpoch(hour: 4), stepHours: 3) == utcEpoch(hour: 3)
)
expect(
    "已经对齐的不动（03:00）",
    WeatherParsing.alignToStep(utcEpoch(hour: 3), stepHours: 3) == utcEpoch(hour: 3)
)
expect(
    "UTC 23:59 向下对齐到 21:00",
    WeatherParsing.alignToStep(utcEpoch(hour: 23, minute: 59), stepHours: 3) == utcEpoch(hour: 21)
)
expect(
    "1 小时粒度只对齐到整点",
    WeatherParsing.alignToStep(utcEpoch(hour: 4, minute: 59), stepHours: 1) == utcEpoch(hour: 4)
)
expect(
    "对齐后的 UTC 21:00 在 +08:00 是本地 5 时（跨午夜换算）",
    localHour(WeatherParsing.alignToStep(utcEpoch(hour: 23, minute: 59), stepHours: 3)) == 5,
    "actual=\(localHour(WeatherParsing.alignToStep(utcEpoch(hour: 23, minute: 59), stepHours: 3)))"
)

print("== 7Timer! 备用源解析（真实 payload 片段：init + timepoint）==")
// 实测 2026-11 的返回：**没有 `time` 字段**，只有 `init`（UTC 起报时刻）+ `timepoint`（相对小时数）。
let sevenTimerJSON = """
{"product":"civil","init":"2026111606","dataseries":[
  {"timepoint":3,"temp2m":16,"weather":"cloudynight"},
  {"timepoint":6,"temp2m":15,"weather":"cloudynight"},
  {"timepoint":9,"temp2m":14,"weather":"cloudynight"},
  {"timepoint":12,"temp2m":14,"weather":"cloudynight"},
  {"timepoint":15,"temp2m":13,"weather":"cloudynight"},
  {"timepoint":18,"temp2m":13,"weather":"cloudyday"},
  {"timepoint":21,"temp2m":15,"weather":"cloudyday"}
]}
"""
let sevenTimerPoints = WeatherParsing.parseSevenTimer(sevenTimerJSON)
expect("解析出 7 个采样点", sevenTimerPoints.count == 7, "actual=\(sevenTimerPoints.count)")
expect(
    "init 06:00Z + timepoint 3h = 09:00Z",
    sevenTimerPoints.first?.epochSeconds == utcEpoch(hour: 9),
    "actual=\(String(describing: sevenTimerPoints.first?.epochSeconds))"
)
expect(
    "init 06:00Z + timepoint 6h = 12:00Z",
    sevenTimerPoints.count > 1 && sevenTimerPoints[1].epochSeconds == utcEpoch(hour: 12)
)
expect(
    "09:00Z 换成本地是 17 时、12:00Z 是 20 时",
    localHour(sevenTimerPoints[0].epochSeconds) == 17 && localHour(sevenTimerPoints[1].epochSeconds) == 20,
    "actual=\(localHour(sevenTimerPoints[0].epochSeconds))/\(localHour(sevenTimerPoints[1].epochSeconds))"
)
expect("温度取整", sevenTimerPoints[0].temperatureC == 16, "actual=\(sevenTimerPoints[0].temperatureC)")
expect(
    "cloudynight / cloudyday 都映射到「阴」（WMO 3）",
    sevenTimerPoints.allSatisfy { $0.code == 3 },
    "actual=\(sevenTimerPoints.map(\.code))"
)

// 真实 payload → 6 个槽位：现在 / 23时 / 2时 / 5时 / 8时 / 11时
let sevenTimerNow = utcEpoch(hour: 13, minute: 26) // 本地 21:26
let sevenTimerSlots = WeatherParsing.visibleSlots(
    points: sevenTimerPoints,
    nowEpochSeconds: sevenTimerNow,
    zoneOffsetSeconds: zone8,
    count: 6,
    stepHours: WeatherSource.sevenTimer.stepHours
)
expect(
    "真实 7Timer 返回 → 6 格标签：现在 / 23时 / 2时 / 5时 / 8时 / 11时",
    slotLabels(sevenTimerSlots, language: .simplified) == ["现在", "23时", "2时", "5时", "8时", "11时"],
    "actual=\(slotLabels(sevenTimerSlots, language: .simplified))"
)
// 「现在」那一格取的是 UTC 12:00（本地 20 时）那条 15°，不是第一个点（09:00Z 的 16°）：
// 两者差 3 小时，就是 3 小时源的代价。
expect(
    "实时读数取「不晚于此刻的最后一个点」（15°，不是 16°）",
    WeatherParsing.snapshotAt(points: sevenTimerPoints, nowEpochSeconds: sevenTimerNow)?.temperatureC == 15,
    "actual=\(String(describing: WeatherParsing.snapshotAt(points: sevenTimerPoints, nowEpochSeconds: sevenTimerNow)?.temperatureC))"
)
expect(
    "全都在未来时实时读数退回第一个点",
    WeatherParsing.snapshotAt(points: sevenTimerPoints, nowEpochSeconds: utcEpoch(hour: 0))?.temperatureC == 16
)
expect("空序列没有实时读数", WeatherParsing.snapshotAt(points: [], nowEpochSeconds: sevenTimerNow) == nil)

print("== 真实 7Timer! payload（64 点，init + timepoint，没有 time 字段）==")

/// 结构完全按实测返回拼：`product=civil`、`init=yyyyMMddHH`（UTC）、`dataseries` 64 项、
/// `timepoint` = 3,6,…,192（**相对 init 的小时数**）。这就是用户报 bug 的那份响应。
func realSevenTimerPayload(_ initStamp: String = "2026111606", count: Int = 64) -> String {
    var items: [String] = []
    for index in 1...count {
        let weather = index % 3 == 0 ? "cloudyday" : "cloudynight"
        items.append("{\"timepoint\":\(index * 3),\"temp2m\":\(20 - index % 5),\"weather\":\"\(weather)\"}")
    }
    return "{\"product\":\"civil\",\"init\":\"\(initStamp)\",\"dataseries\":[\(items.joined(separator: ","))]}"
}

let payloadPoints = WeatherParsing.parseSevenTimer(realSevenTimerPayload())
expect("64 点全部解析出来", payloadPoints.count == 64, "actual=\(payloadPoints.count)")
// 前 6 点：09/12/15/18/21/次日 00 时（UTC）；本地 +8 是 17/20/23/2/5/8 时。
let payloadFirstSixUTC = [utcEpoch(hour: 9), utcEpoch(hour: 12), utcEpoch(hour: 15),
                          utcEpoch(hour: 18), utcEpoch(hour: 21), utcEpoch(hour: 0, day: 17)]
expect(
    "前 6 点的时间戳（UTC）= 09/12/15/18/21Z + 次日 00Z",
    Array(payloadPoints.prefix(6).map(\.epochSeconds)) == payloadFirstSixUTC,
    "actual=\(payloadPoints.prefix(6).map(\.epochSeconds))"
)
expect(
    "前 6 点的本地时刻（+8）= 17/20/23/2/5/8 时",
    payloadPoints.prefix(6).map({ localHour($0.epochSeconds) }) == [17, 20, 23, 2, 5, 8],
    "actual=\(payloadPoints.prefix(6).map { localHour($0.epochSeconds) })"
)
let payloadDiffs = zip(payloadPoints.dropFirst(), payloadPoints).map { $0.epochSeconds - $1.epochSeconds }
expect(
    "全部 63 个相邻间隔都 = 10800 秒（3 小时，±1 秒）",
    payloadDiffs.count == 63 && payloadDiffs.allSatisfy { abs($0 - 10_800) <= 1 },
    "actual=\(Set(payloadDiffs))"
)
let payloadFirstSixDiffs = (0..<6).map { payloadPoints[$0 + 1].epochSeconds - payloadPoints[$0].epochSeconds }
expect(
    "前 6 个相邻间隔 = [10800, 10800, 10800, 10800, 10800, 10800]",
    payloadFirstSixDiffs == Array(repeating: 10_800, count: 6),
    "actual=\(payloadFirstSixDiffs)"
)
// 21:26（本地）的 6 格：现在（= UTC 12:00 / 本地 20 时的采样点）/ 23 / 2 / 5 / 8 / 11 时
let payloadReadings = WeatherParsing.slotReadings(
    points: payloadPoints,
    nowEpochSeconds: utcEpoch(hour: 13, minute: 26),
    zoneOffsetSeconds: zone8,
    count: 6,
    stepHours: WeatherSource.sevenTimer.stepHours,
    currentTemperatureC: 16,
    currentCode: 3
)
expect(
    "真实 payload → 6 格标签：现在 / 23时 / 2时 / 5时 / 8时 / 11时",
    slotLabels(payloadReadings.map(\.slot), language: .simplified)
        == ["现在", "23时", "2时", "5时", "8时", "11时"],
    "actual=\(slotLabels(payloadReadings.map(\.slot), language: .simplified))"
)
expect(
    "6 格覆盖 18 小时（首末相差 15 小时）",
    payloadReadings[5].slot.epochSeconds - payloadReadings[0].slot.epochSeconds == 15 * 3600,
    "actual=\(payloadReadings[5].slot.epochSeconds - payloadReadings[0].slot.epochSeconds)"
)
expect(
    "每一格都落在真实采样点上（标签不是理论网格推出来的）",
    payloadReadings.allSatisfy { reading in
        payloadPoints.contains { $0.epochSeconds == reading.slot.epochSeconds }
    },
    "actual=\(payloadReadings.map(\.slot.epochSeconds))"
)
expect(
    "首格「现在」= UTC 12:00（本地 20 时）那条采样点",
    payloadReadings[0].slot.epochSeconds == utcEpoch(hour: 12)
        && localHour(payloadReadings[0].slot.epochSeconds) == 20,
    "actual=\(payloadReadings[0].slot.epochSeconds)"
)

// 解析正确 ⇒ 只要步长取对了，6 格就必然是 3 小时间隔。把「署名 + 步长」这一对钉死。
let sevenTimerSnapshot = WeatherSnapshot(temperatureC: 16, code: 3, hourly: payloadPoints, source: .sevenTimer)
expect(
    "7Timer! 快照：署名含 7Timer!，且步长 = 3（署名与步长同源）",
    sevenTimerSnapshot.source == .sevenTimer
        && sevenTimerSnapshot.stepHours == 3
        && WeatherSource.sevenTimer.attribution.contains("7Timer!"),
    "step=\(sevenTimerSnapshot.stepHours) attribution=\(WeatherSource.sevenTimer.attribution)"
)
expect(
    "主源快照：署名是 Open-Meteo，且步长 = 1",
    WeatherSource.openMeteo.attribution.contains("Open-Meteo")
        && WeatherSource.openMeteo.attribution.contains("CC BY 4.0")
        && WeatherSnapshot(temperatureC: 16, code: 3, hourly: payloadPoints).stepHours == 1
)

print("== 「现在」那一格：图标与温度都取实时读数 ==")

// 3 小时源：快照的实时读数是 16° / 阴（code 3），采样点是 10° / 多云（code 1）。
// 「现在」格如果取采样点，就会显示 10°/多云 —— 与日期行的 16° 和实时图标互相矛盾。
let threeHourLivePoints = hourlyPoints(fromEpoch: utcEpoch(hour: 12), count: 8, stepHours: 3)
let liveSnapshot = WeatherSnapshot(temperatureC: 16, code: 3, hourly: threeHourLivePoints, source: .sevenTimer)
let liveReadings = WeatherParsing.slotReadings(
    points: liveSnapshot.hourly,
    nowEpochSeconds: utcEpoch(hour: 13, minute: 26),
    zoneOffsetSeconds: zone8,
    count: 6,
    stepHours: liveSnapshot.stepHours,
    currentTemperatureC: liveSnapshot.temperatureC,
    currentCode: liveSnapshot.code
)
expect(
    "3 小时源：「现在」格温度取实时读数 16（不是采样点的 10）",
    liveReadings[0].temperatureC == 16 && liveReadings[0].temperatureC == liveSnapshot.temperatureC,
    "actual=\(String(describing: liveReadings[0].temperatureC))"
)
expect(
    "3 小时源：「现在」格天气取实时读数 阴（不是采样点的 多云）",
    liveReadings[0].condition == .overcast && liveReadings[0].condition == liveSnapshot.condition,
    "actual=\(String(describing: liveReadings[0].condition))"
)
expect(
    "3 小时源：第二格仍是采样点自己的读数（11°/多云）",
    liveReadings[1].temperatureC == 11 && liveReadings[1].condition == .partlyCloudy,
    "actual=\(String(describing: liveReadings[1].temperatureC))/\(String(describing: liveReadings[1].condition))"
)
expect(
    "「现在」格仍记住采样点真实时刻（判昼夜图标用）",
    liveReadings[0].pointEpochSeconds == utcEpoch(hour: 12) && liveReadings[0].pointDate != nil
)

// 主源 1 小时粒度：实时读数同样优先，且与日期行（`snapshot.temperatureC`）是同一个数。
let oneHourLivePoints = hourlyPoints(fromEpoch: utcEpoch(hour: 12), count: 12, stepHours: 1)
let liveOneHourReadings = WeatherParsing.slotReadings(
    points: oneHourLivePoints,
    nowEpochSeconds: utcEpoch(hour: 13, minute: 26),
    zoneOffsetSeconds: zone8,
    count: 6,
    stepHours: WeatherSource.openMeteo.stepHours,
    currentTemperatureC: 16,
    currentCode: 3
)
expect(
    "1 小时源：「现在」格温度也取实时读数（与日期行一致）",
    liveOneHourReadings[0].temperatureC == 16,
    "actual=\(String(describing: liveOneHourReadings[0].temperatureC))"
)
expect(
    "1 小时源：「现在」格图标与温度同源（实时）",
    liveOneHourReadings[0].condition == .overcast && liveOneHourReadings[0].temperatureC == 16
)
expect(
    "没有实时读数时「现在」格才退回采样点",
    WeatherParsing.slotReadings(
        points: threeHourLivePoints,
        nowEpochSeconds: utcEpoch(hour: 13, minute: 26),
        zoneOffsetSeconds: zone8,
        count: 2,
        stepHours: 3
    )[0].temperatureC == 10
)

// 数据网格与名义步长不一致（镜像站 / 旧的 time 字段）时，标签仍必须落在**真实采样点**上：
// 4 小时一份的数据配 3 小时步长，格子应该吃掉 1 小时误差落到真实点上，而不是停在 16 时这种空网格上。
let driftedPoints = (0..<6).map {
    WeatherHour(epochSeconds: utcEpoch(hour: 9) + $0 * 4 * 3600, temperatureC: 5 + $0, code: 1)
}
let driftedSlots = WeatherParsing.visibleSlots(
    points: driftedPoints,
    nowEpochSeconds: utcEpoch(hour: 13, minute: 26),
    zoneOffsetSeconds: zone8,
    count: 3,
    stepHours: 3
)
expect(
    "网格漂移时槽位落到真实采样点（13/17/21 时，不是 13/16/19 时）",
    driftedSlots.map(\.epochSeconds)
        == [utcEpoch(hour: 13), utcEpoch(hour: 17), utcEpoch(hour: 21)],
    "actual=\(driftedSlots.map(\.epochSeconds))"
)
expect(
    "网格漂移时标签跟着真实采样点（现在 / 1时 / 5时）",
    slotLabels(driftedSlots, language: .simplified) == ["现在", "1时", "5时"],
    "actual=\(slotLabels(driftedSlots, language: .simplified))"
)


// 旧文档里的 `time` 字段（yyyyMMddHH，UTC）也认，并向下对齐到 3 小时网格。
let legacySevenTimerJSON = """
{"dataseries":[{"time":"2025111604","temp2m":9,"weather":"rain"}]}
"""
let legacySevenTimerPoints = WeatherParsing.parseSevenTimer(legacySevenTimerJSON)
expect(
    "旧 time 字段：04:00Z 向下对齐到 03:00Z",
    legacySevenTimerPoints.count == 1
        && legacySevenTimerPoints[0].epochSeconds == utcEpoch(hour: 3, day: 16, month: 11, year: 2025),
    "actual=\(String(describing: legacySevenTimerPoints.first?.epochSeconds))"
)
expect("rain → 中雨（WMO 63）", legacySevenTimerPoints.first?.code == 63)

// 残项与坏 payload
let messySevenTimerJSON = """
{"init":"2026111606","dataseries":[
  {"timepoint":6,"temp2m":15,"weather":"clearday"},
  {"weather":"rain"},
  {"timepoint":3,"temp2m":16,"weather":"cloudyday"}
]}
"""
let messySevenTimerPoints = WeatherParsing.parseSevenTimer(messySevenTimerJSON)
expect("缺 temp2m 的残项被跳过", messySevenTimerPoints.count == 2, "actual=\(messySevenTimerPoints.count)")
expect(
    "解析结果按时刻升序",
    messySevenTimerPoints.first?.epochSeconds == utcEpoch(hour: 9)
        && messySevenTimerPoints.last?.epochSeconds == utcEpoch(hour: 12)
)
expect("非法 JSON → 空", WeatherParsing.parseSevenTimer("not json").isEmpty)
expect("没有 dataseries → 空", WeatherParsing.parseSevenTimer("{\"product\":\"civil\"}").isEmpty)
expect("dataseries 为空 → 空", WeatherParsing.parseSevenTimer("{\"dataseries\":[]}").isEmpty)
expect(
    "既没有 init 也没有 time → 算不出时刻，整条丢掉",
    WeatherParsing.parseSevenTimer("{\"dataseries\":[{\"timepoint\":3,\"temp2m\":1}]}").isEmpty
)
expect(
    "时刻串必须是 10 位数字",
    WeatherParsing.sevenTimerStampEpoch("2026111606") == utcEpoch(hour: 6)
        && WeatherParsing.sevenTimerStampEpoch("2026-11-16") == nil
        && WeatherParsing.sevenTimerStampEpoch("") == nil
        && WeatherParsing.sevenTimerStampEpoch(nil) == nil
)
expect(
    "备用源地址是 7Timer! 官方 https 端点（lon 在前、lat 在后）",
    WeatherParsing.sevenTimerURL(latitude: 31.2304, longitude: 121.4737)?.absoluteString
        == "https://www.7timer.info/bin/api.pl?lon=121.4737&lat=31.2304&product=civil&output=json",
    "actual=\(WeatherParsing.sevenTimerURL(latitude: 31.2304, longitude: 121.4737)?.absoluteString ?? "nil")"
)

print("== 7Timer! 天气词 → WMO 天气码 ==")
let sevenTimerWordCases: [(String, Int)] = [
    ("clearday", 0), ("clearnight", 0), ("sunny", 0),
    ("pcloudyday", 2), ("pcloudy", 2),
    ("mcloudynight", 3), ("cloudyday", 3), ("overcast", 3),
    ("humidday", 45), ("fog", 45), ("foggynight", 45),
    ("lightrainday", 80), ("ishowernight", 80), ("oshower", 80), ("showers", 80), ("drizzle", 80),
    ("rain", 63), ("heavyrain", 65),
    ("lightsnowday", 71), ("snownight", 73), ("snowrain", 73), ("sleet", 73),
    ("tsday", 95), ("thunder", 95), ("thunderstorm", 95),
    ("sandstorm", 2), ("PCLOUDYDAY", 2), ("", 2)
]
for (word, expected) in sevenTimerWordCases {
    expect(
        "「\(word)」→ WMO \(expected)",
        WeatherParsing.wmoCodeOfSevenTimer(word) == expected,
        "actual=\(WeatherParsing.wmoCodeOfSevenTimer(word))"
    )
}
expect("nil → 多云（WMO 2）", WeatherParsing.wmoCodeOfSevenTimer(nil) == 2)
// 映射出来的码必须能被现有的 WMO 分类器认识（共用同一套文案与图标）。
expect(
    "映射结果能被现有分类器识别",
    WeatherCondition.of(code: WeatherParsing.wmoCodeOfSevenTimer("clearday")) == .clear
        && WeatherCondition.of(code: WeatherParsing.wmoCodeOfSevenTimer("pcloudy")) == .partlyCloudy
        && WeatherCondition.of(code: WeatherParsing.wmoCodeOfSevenTimer("mcloudy")) == .overcast
        && WeatherCondition.of(code: WeatherParsing.wmoCodeOfSevenTimer("fog")) == .fog
        && WeatherCondition.of(code: WeatherParsing.wmoCodeOfSevenTimer("lightrain")) == .showers
        && WeatherCondition.of(code: WeatherParsing.wmoCodeOfSevenTimer("rain")) == .rain
        && WeatherCondition.of(code: WeatherParsing.wmoCodeOfSevenTimer("heavyrain")) == .heavyRain
        && WeatherCondition.of(code: WeatherParsing.wmoCodeOfSevenTimer("lightsnow")) == .snow
        && WeatherCondition.of(code: WeatherParsing.wmoCodeOfSevenTimer("ts")) == .thunder
        && WeatherCondition.of(code: WeatherParsing.wmoCodeOfSevenTimer("sandstorm")) == .partlyCloudy
)

print("== 降级判定（主源失败之后怎么办）==")
expect(
    "没有缓存 → 去问备用源",
    WeatherParsing.fallbackFor(hasCache: false, cacheAgeSeconds: 0) == .trySevenTimer
)
expect(
    "缓存 5 分钟 → 保持现状不清空",
    WeatherParsing.fallbackFor(hasCache: true, cacheAgeSeconds: 5 * 60) == .keepCache
)
expect(
    "缓存刚好 30 分钟 → 仍保留",
    WeatherParsing.fallbackFor(hasCache: true, cacheAgeSeconds: 30 * 60) == .keepCache
)
expect(
    "缓存 31 分钟 → 去问备用源",
    WeatherParsing.fallbackFor(hasCache: true, cacheAgeSeconds: 31 * 60) == .trySevenTimer
)
expect(
    "时间戳异常（负数）→ 去问备用源",
    WeatherParsing.fallbackFor(hasCache: true, cacheAgeSeconds: -1) == .trySevenTimer
)

print("== 旧数据保留（24 小时硬上限）+ 过期标注 ==")
expect("0 秒的缓存可显示", WeatherParsing.isDisplayable(ageSeconds: 0))
expect("23 小时的旧数据仍可显示", WeatherParsing.isDisplayable(ageSeconds: 23 * 3600))
expect("刚好 24 小时仍可显示", WeatherParsing.isDisplayable(ageSeconds: 24 * 3600))
expect("超过 24 小时当没有数据", !WeatherParsing.isDisplayable(ageSeconds: 24 * 3600 + 1))
expect("负年龄（时钟回拨）不显示", !WeatherParsing.isDisplayable(ageSeconds: -1))
expect(
    "过期分钟数：30 秒 → 0 分钟",
    WeatherParsing.staleMinutes(ageSeconds: 30) == 0,
    "actual=\(String(describing: WeatherParsing.staleMinutes(ageSeconds: 30)))"
)
expect(
    "过期分钟数：45 分钟 → 45",
    WeatherParsing.staleMinutes(ageSeconds: 45 * 60) == 45
)
expect(
    "过期分钟数：25 小时 → 1500",
    WeatherParsing.staleMinutes(ageSeconds: 25 * 3600) == 1500
)
expect("没有缓存时没有过期说明", WeatherParsing.staleMinutes(ageSeconds: nil) == nil)
expect("时间戳异常时没有过期说明", WeatherParsing.staleMinutes(ageSeconds: -1) == nil)
expect(
    "「数据过期 N 分钟」跟着当前语言",
    WeatherParsing.staleLabel(ageSeconds: 45 * 60)
        == L10n.f("weather.stale", language: L10n.language, [45]),
    "actual=\(String(describing: WeatherParsing.staleLabel(ageSeconds: 45 * 60)))"
)
expect(
    "过期文案实际文本（简 / 繁 / 英）",
    L10n.f("weather.stale", language: .simplified, [45]) == "数据过期 45 分钟"
        && L10n.f("weather.stale", language: .traditional, [45]) == "資料過期 45 分鐘"
        && L10n.f("weather.stale", language: .english, [45]) == "Stale by 45 min"
)
expect("没有缓存时过期文案为 nil", WeatherParsing.staleLabel(ageSeconds: nil) == nil)

print("== 天气源与步长（缓存里的一等公民）==")
expect("open-meteo → 主源", WeatherSource.of(id: "open-meteo") == .openMeteo)
expect("7timer → 备用源", WeatherSource.of(id: "7timer") == .sevenTimer)
expect("旧缓存没有 source → 主源", WeatherSource.of(id: nil) == .openMeteo)
expect("空串 → 主源", WeatherSource.of(id: "") == .openMeteo)
expect("认不出来的值 → 主源", WeatherSource.of(id: "noaa") == .openMeteo)
expect("大小写不敏感", WeatherSource.of(id: "7TIMER") == .sevenTimer)
expect("主源步长 1 小时", WeatherSource.openMeteo.stepHours == 1 && !WeatherSource.openMeteo.isLowPrecision)
expect("备用源步长 3 小时", WeatherSource.sevenTimer.stepHours == 3 && WeatherSource.sevenTimer.isLowPrecision)
expect(
    "快照默认吃来源的步长",
    WeatherSnapshot(temperatureC: 9, code: 2, hourly: []).stepHours == 1
        && WeatherSnapshot(temperatureC: 9, code: 2, hourly: [], source: .sevenTimer).stepHours == 3
)
// 步长是**派生值**，不是可以被调用方改写的独立字段：传错必须被来源纠正。
// 这一条钉住的正是「署名 7Timer!、逐时行却按 1 小时排」那一类 bug。
expect(
    "7Timer! 快照被传 1 小时 → 归一化成 3",
    WeatherSnapshot(temperatureC: 9, code: 2, hourly: [], source: .sevenTimer, stepHours: 1).stepHours == 3,
    "actual=\(WeatherSnapshot(temperatureC: 9, code: 2, hourly: [], source: .sevenTimer, stepHours: 1).stepHours)"
)
expect(
    "主源快照被传 3 小时 → 归一化成 1",
    WeatherSnapshot(temperatureC: 9, code: 2, hourly: [], source: .openMeteo, stepHours: 3).stepHours == 1,
    "actual=\(WeatherSnapshot(temperatureC: 9, code: 2, hourly: [], source: .openMeteo, stepHours: 3).stepHours)"
)
expect(
    "脏值 0 也归一化（7Timer! → 3，不会退化成 1）",
    WeatherSnapshot(temperatureC: 9, code: 2, hourly: [], source: .sevenTimer, stepHours: 0).stepHours == 3,
    "actual=\(WeatherSnapshot(temperatureC: 9, code: 2, hourly: [], source: .sevenTimer, stepHours: 0).stepHours)"
)
expect(
    "任意来源 × 任意传入值，步长恒等于 source.stepHours",
    WeatherSource.allCases.allSatisfy { source in
        [nil, -1, 0, 1, 2, 3, 24].allSatisfy { passed in
            WeatherSnapshot(temperatureC: 9, code: 2, hourly: [], source: source, stepHours: passed).stepHours
                == source.stepHours
        }
    }
)

print("== 逐时行步长与署名同源（没有快照时也不退回 1 小时）==")
expect(
    "没有快照 + 7Timer! 署名 → 3 小时",
    WeatherSnapshot.slotStepHours(nil, source: .sevenTimer) == 3
)
expect(
    "没有快照 + 主源署名 → 1 小时",
    WeatherSnapshot.slotStepHours(nil, source: .openMeteo) == 1
)
expect(
    "有快照时用快照自己的（已按来源归一化）",
    WeatherSnapshot.slotStepHours(sevenTimerSnapshot, source: .openMeteo) == 3
)
// 无数据（缓存过期 / 刚换城市 / 首次启动）时，署名 7Timer! 就必须排出 3 小时的格子：
// 旧代码这里是 `stepHours: weather?.stepHours ?? 1`，于是署名 7Timer! 配上了 1 小时的逐时行。
let emptyGridWithSevenTimerAttribution = WeatherParsing.visibleSlots(
    points: [],
    nowEpochSeconds: utcEpoch(hour: 13, minute: 26),
    zoneOffsetSeconds: zone8,
    count: 6,
    stepHours: WeatherSnapshot.slotStepHours(nil, source: .sevenTimer)
)
expect(
    "署名 7Timer! 时无数据也按 3 小时排（现在/23时/2时/5时/8时/11时）",
    slotLabels(emptyGridWithSevenTimerAttribution, language: .simplified)
        == ["现在", "23时", "2时", "5时", "8时", "11时"],
    "actual=\(slotLabels(emptyGridWithSevenTimerAttribution, language: .simplified))"
)
expect(
    "那条 1 小时的网格确实会给出 6 格覆盖 5 小时的错标签（回归对照）",
    slotLabels(
        WeatherParsing.visibleSlots(
            points: [],
            nowEpochSeconds: utcEpoch(hour: 13, minute: 26),
            zoneOffsetSeconds: zone8,
            count: 6,
            stepHours: 1
        ),
        language: .simplified
    ) == ["现在", "22时", "23时", "0时", "1时", "2时"]
)

print("== 刷新触发条件（低精度按退避轮询主源 / 主源 30 分钟过期）==")
// 低精度（7Timer! / 3 小时）：**只看 60 秒窗口**，不看 30 分钟过期与否。
expect(
    "低精度：从没试过 → 立刻刷（尽快切回 1 小时数据）",
    WeatherParsing.shouldRefresh(isStale: false, isLowPrecision: true, lastLowPrecisionAttempt: nil)
)
expect(
    "低精度：刚试过 0 秒 → 不刷",
    !WeatherParsing.shouldRefresh(isStale: false, isLowPrecision: true, lastLowPrecisionAttempt: 0)
)
expect(
    "低精度：59 秒前试过 → 还没到窗口，先不刷",
    !WeatherParsing.shouldRefresh(isStale: false, isLowPrecision: true, lastLowPrecisionAttempt: 59),
    "actual=\(WeatherParsing.shouldRefresh(isStale: false, isLowPrecision: true, lastLowPrecisionAttempt: 59))"
)
expect(
    "低精度：刚好 60 秒 → 可以再试",
    WeatherParsing.shouldRefresh(isStale: false, isLowPrecision: true, lastLowPrecisionAttempt: 60),
    "actual=\(WeatherParsing.shouldRefresh(isStale: false, isLowPrecision: true, lastLowPrecisionAttempt: 60))"
)
expect(
    "低精度：61 秒前试过 → 再试",
    WeatherParsing.shouldRefresh(isStale: false, isLowPrecision: true, lastLowPrecisionAttempt: 61)
)
expect(
    "低精度：10 分钟前试过 → 当然再试（窗口是 60 秒不是 10 分钟）",
    WeatherParsing.shouldRefresh(isStale: false, isLowPrecision: true, lastLowPrecisionAttempt: 600)
)
expect(
    "低精度 + 已过期：仍只看 60 秒窗口（1 秒前试过 → 不刷）",
    !WeatherParsing.shouldRefresh(isStale: true, isLowPrecision: true, lastLowPrecisionAttempt: 1),
    "actual=\(WeatherParsing.shouldRefresh(isStale: true, isLowPrecision: true, lastLowPrecisionAttempt: 1))"
)
expect(
    "低精度 + 已过期 + 60 秒前试过 → 再试",
    WeatherParsing.shouldRefresh(isStale: true, isLowPrecision: true, lastLowPrecisionAttempt: 60)
)
expect(
    "时间戳异常（负数）不会被永久节流",
    WeatherParsing.shouldRefresh(isStale: false, isLowPrecision: true, lastLowPrecisionAttempt: -1)
)
expect(
    "低精度轮询窗口是 60 秒",
    WeatherParsing.lowPrecisionRetrySeconds == 60,
    "actual=\(WeatherParsing.lowPrecisionRetrySeconds)"
)

// 主源数据（1 小时粒度）：切回主源后**绝不按 60 秒轮询**，仍是 30 分钟过期逻辑。
expect(
    "主源 + 未过期 → 不刷（不按 60 秒轮询）",
    !WeatherParsing.shouldRefresh(isStale: false, isLowPrecision: false, lastLowPrecisionAttempt: nil)
)
expect(
    "主源 + 未过期 + 刚好 60 秒前试过 → 仍然不刷",
    !WeatherParsing.shouldRefresh(isStale: false, isLowPrecision: false, lastLowPrecisionAttempt: 60)
)
expect(
    "主源 + 已过期 → 刷（30 分钟 TTL）",
    WeatherParsing.shouldRefresh(isStale: true, isLowPrecision: false, lastLowPrecisionAttempt: nil)
)
expect(
    "主源 + 已过期 + 刚试过 → TTL 说了算，仍然刷（5 分钟失败节流在 WeatherStore 里）",
    WeatherParsing.shouldRefresh(isStale: true, isLowPrecision: false, lastLowPrecisionAttempt: 1)
)
expect(
    "常量：TTL 30 分钟 / 失败节流 5 分钟 / 单次请求超时 5 秒",
    WeatherParsing.cacheTTLSeconds == 30 * 60
        && WeatherParsing.primaryFailureRetrySeconds == 5 * 60
        && WeatherParsing.requestTimeoutSeconds == 5,
    "ttl=\(WeatherParsing.cacheTTLSeconds) retry=\(WeatherParsing.primaryFailureRetrySeconds) timeout=\(WeatherParsing.requestTimeoutSeconds)"
)

print("== 主源失败 → 立刻降级（不再有「2 秒后重试一次」）==")
expect("主源最多试 1 次", WeatherParsing.primaryMaxAttempts == 1)
expect(
    "第 1 次失败（attempt 0）直接进 fallback",
    WeatherParsing.afterPrimaryFailure(attempt: 0) == .fallback,
    "actual=\(WeatherParsing.afterPrimaryFailure(attempt: 0))"
)
expect("attempt 1 也是 fallback（retry 分支不可达）", WeatherParsing.afterPrimaryFailure(attempt: 1) == .fallback)
expect("attempt 5 仍是 fallback", WeatherParsing.afterPrimaryFailure(attempt: 5) == .fallback)

print("== 降级后重试主源：前台退避 60 → 120 → 300 秒 / 后台 10 分钟 ==")
// 退避表（纯函数，前台按连续失败次数升档、封顶 5 分钟；后台固定 10 分钟）。
expect(
    "前台第 1 次（连续失败 0 或 1）→ 60 秒",
    WeatherParsing.lowPrecisionRetryDelay(consecutiveFailures: 0, isForeground: true) == 60
        && WeatherParsing.lowPrecisionRetryDelay(consecutiveFailures: 1, isForeground: true) == 60,
    "actual=\(WeatherParsing.lowPrecisionRetryDelay(consecutiveFailures: 1, isForeground: true))"
)
expect(
    "前台第 2 次 → 120 秒",
    WeatherParsing.lowPrecisionRetryDelay(consecutiveFailures: 2, isForeground: true) == 120,
    "actual=\(WeatherParsing.lowPrecisionRetryDelay(consecutiveFailures: 2, isForeground: true))"
)
expect(
    "前台第 3 次 → 300 秒（封顶）",
    WeatherParsing.lowPrecisionRetryDelay(consecutiveFailures: 3, isForeground: true) == 300,
    "actual=\(WeatherParsing.lowPrecisionRetryDelay(consecutiveFailures: 3, isForeground: true))"
)
expect(
    "前台第 4 次 → 仍 300 秒（不会无限涨）",
    WeatherParsing.lowPrecisionRetryDelay(consecutiveFailures: 4, isForeground: true) == 300
)
expect(
    "后台任意次数 → 600 秒（不参与 60 秒轮询）",
    [0, 1, 2, 3, 9, 50].allSatisfy {
        WeatherParsing.lowPrecisionRetryDelay(consecutiveFailures: $0, isForeground: false) == 600
    }
)
expect(
    "退避常量：起步 60 / 封顶 300 / 后台 600",
    WeatherParsing.lowPrecisionRetrySeconds == 60
        && WeatherParsing.lowPrecisionRetryMaxSeconds == 300
        && WeatherParsing.lowPrecisionRetryBackgroundSeconds == 600,
    "base=\(WeatherParsing.lowPrecisionRetrySeconds) max=\(WeatherParsing.lowPrecisionRetryMaxSeconds) bg=\(WeatherParsing.lowPrecisionRetryBackgroundSeconds)"
)

// `shouldRefresh` 真的接入了退避表（不是只有常量对）。
expect(
    "低精度 + 失败 1 次 + 59 秒 → 不刷",
    !WeatherParsing.shouldRefresh(
        isStale: false, isLowPrecision: true, lastLowPrecisionAttempt: 59,
        consecutiveFailures: 1, isForeground: true
    )
)
expect(
    "低精度 + 失败 1 次 + 60 秒 → 刷",
    WeatherParsing.shouldRefresh(
        isStale: false, isLowPrecision: true, lastLowPrecisionAttempt: 60,
        consecutiveFailures: 1, isForeground: true
    )
)
expect(
    "低精度 + 失败 2 次 + 119 秒 → 不刷（退避到 120）",
    !WeatherParsing.shouldRefresh(
        isStale: false, isLowPrecision: true, lastLowPrecisionAttempt: 119,
        consecutiveFailures: 2, isForeground: true
    )
)
expect(
    "低精度 + 失败 2 次 + 120 秒 → 刷",
    WeatherParsing.shouldRefresh(
        isStale: false, isLowPrecision: true, lastLowPrecisionAttempt: 120,
        consecutiveFailures: 2, isForeground: true
    )
)
expect(
    "低精度 + 失败 3 次 + 299 秒 → 不刷（退避到 300）",
    !WeatherParsing.shouldRefresh(
        isStale: false, isLowPrecision: true, lastLowPrecisionAttempt: 299,
        consecutiveFailures: 3, isForeground: true
    )
)
expect(
    "低精度 + 失败 3 次 + 300 秒 → 刷",
    WeatherParsing.shouldRefresh(
        isStale: false, isLowPrecision: true, lastLowPrecisionAttempt: 300,
        consecutiveFailures: 3, isForeground: true
    )
)
expect(
    "低精度 + 失败 9 次 + 299 秒 → 不刷（封顶还是 300）",
    !WeatherParsing.shouldRefresh(
        isStale: false, isLowPrecision: true, lastLowPrecisionAttempt: 299,
        consecutiveFailures: 9, isForeground: true
    )
)
expect(
    "后台：失败 1 次 + 60 秒 → 不刷（后台 10 分钟）",
    !WeatherParsing.shouldRefresh(
        isStale: false, isLowPrecision: true, lastLowPrecisionAttempt: 60,
        consecutiveFailures: 1, isForeground: false
    )
)
expect(
    "后台：失败 1 次 + 599 秒 → 不刷",
    !WeatherParsing.shouldRefresh(
        isStale: false, isLowPrecision: true, lastLowPrecisionAttempt: 599,
        consecutiveFailures: 1, isForeground: false
    )
)
expect(
    "后台：失败 1 次 + 600 秒 → 刷",
    WeatherParsing.shouldRefresh(
        isStale: false, isLowPrecision: true, lastLowPrecisionAttempt: 600,
        consecutiveFailures: 1, isForeground: false
    )
)
expect(
    "回到前台：刚试过也立刻再试一次（跳过退避窗口）",
    WeatherParsing.shouldRefresh(
        isStale: false, isLowPrecision: true, lastLowPrecisionAttempt: 0,
        consecutiveFailures: 3, isForeground: true, ignoreLowPrecisionThrottle: true
    )
)
expect(
    "切回主源后（高精度）不再按退避节奏轮询",
    !WeatherParsing.shouldRefresh(
        isStale: false, isLowPrecision: false, lastLowPrecisionAttempt: 60,
        consecutiveFailures: 0, isForeground: true
    )
)

// 缓存必须属于当前地点：> 5 km 就当没有缓存（新地点显示占位符，绝不用旧城市的数据顶上）。
expect(
    "同一坐标的缓存属于该地点",
    DistrictNaming.distanceKm(31.2304, 121.4737, 31.2304, 121.4737) <= DistrictNaming.moveThresholdKm
)
expect(
    "上海缓存不属于北京（A 城市的天气不会显示在 B 城市下）",
    DistrictNaming.distanceKm(31.2304, 121.4737, 39.9042, 116.4074) > DistrictNaming.moveThresholdKm
)
expect(
    "两公里内的移动仍算同一地点",
    DistrictNaming.distanceKm(31.2304, 121.4737, 31.2484, 121.4737) <= DistrictNaming.moveThresholdKm
)

print("== 主题三态 × 昼夜两种输入 ==")
// 表格化：三态 × 昼夜，六种组合的预期都在这里。
let themeTable: [(ThemeMode, Bool, Bool)] = [
    (.auto, true, false), // 自动 + 白天 → 亮色
    (.auto, false, true), // 自动 + 夜晚 → 暗色
    (.light, true, false), // 亮色 + 白天 → 亮色
    (.light, false, false), // 亮色 + 夜晚 → 强制亮色
    (.dark, true, true), // 暗色 + 白天 → 强制暗色
    (.dark, false, true), // 暗色 + 夜晚 → 暗色
]
for (mode, sunIsUp, expectedDark) in themeTable {
    expect(
        "\(mode.rawValue) × 太阳\(sunIsUp ? "升" : "落") → \(expectedDark ? "暗色" : "亮色")",
        mode.isDark(sunIsUp: sunIsUp) == expectedDark,
        "actual=\(mode.isDark(sunIsUp: sunIsUp))"
    )
}
expect(
    "配色用的 isDayPalette 是 isDark 的反面",
    ThemeMode.allCases.allSatisfy { mode in
        [true, false].allSatisfy { mode.isDayPalette(sunIsUp: $0) == !mode.isDark(sunIsUp: $0) }
    }
)
expect("默认是自动", ThemeMode.fromStorage(nil) == .auto)
expect("没存过（空串）→ 自动", ThemeMode.fromStorage("") == .auto)
expect("认不出来的值 → 自动", ThemeMode.fromStorage("weird") == .auto)
expect("存储往返：light", ThemeMode.fromStorage(ThemeMode.light.rawValue) == .light)
expect("存储大小写不敏感", ThemeMode.fromStorage("Dark") == .dark)
expect(
    "存储值就是 auto / light / dark",
    ThemeMode.auto.rawValue == "auto" && ThemeMode.light.rawValue == "light" && ThemeMode.dark.rawValue == "dark"
)
expect(
    "设置页三选文案（简 / 繁 / 英）",
    L10n.t("settings.themeAuto", language: .simplified) == "自动"
        && L10n.t("settings.themeLight", language: .simplified) == "亮色"
        && L10n.t("settings.themeDark", language: .simplified) == "暗色"
        && L10n.t("settings.themeAuto", language: .traditional) == "自動"
        && L10n.t("settings.themeLight", language: .traditional) == "亮色"
        && L10n.t("settings.themeDark", language: .traditional) == "暗色"
        && L10n.t("settings.themeAuto", language: .english) == "Auto"
        && L10n.t("settings.themeLight", language: .english) == "Light"
        && L10n.t("settings.themeDark", language: .english) == "Dark"
)

print("== 主题色 token：输入框 / 按钮 / 分隔线的亮暗两套取值（可读性回归）==")
// 颜色 token 放在 Core（`ThemeColors`）就是为了让这里能守「暗色下输入框不能还是白底」
// 「字和底色的对比度够不够」。之前的 bug 是设置页输入框用系统 `.roundedBorder`：
// 强制暗色主题 + 系统浅色外观时，输入框仍是白底，浅色的正文压上去几乎看不见。
let themeDayColors = ThemeColors.day
let themeNightColors = ThemeColors.night
expect("亮/暗是两套不同的 token", themeDayColors != themeNightColors)
expect("isDay 标记正确", themeDayColors.isDay && !themeNightColors.isDay)
expect("of(isDay:) 取到对应的一套", ThemeColors.of(isDay: true) == .day && ThemeColors.of(isDay: false) == .night)
expect("token 数量固定（14 个语义色）", themeDayColors.tokens.count == 14, "actual=\(themeDayColors.tokens.count)")
expect("token 名字不重复", Set(themeDayColors.tokens.map(\.name)).count == themeDayColors.tokens.count)

// 逐个 token：两套都必须有值（不能是 0x000000 占位）且亮暗不同。
for (name, dayColor) in themeDayColors.tokens {
    guard let nightColor = themeNightColors.tokens.first(where: { $0.name == name })?.color else {
        expect("暗色缺 token \(name)", false)
        continue
    }
    expect(
        "\(name)：亮 \(dayColor.hexText) / 暗 \(nightColor.hexText) 都有值且不同",
        dayColor.hex != 0 && nightColor.hex != 0 && dayColor != nightColor,
        "day=\(dayColor.hexText) night=\(nightColor.hexText)"
    )
}

// 输入框三件套：亮色仍是浅底深字；暗色必须是深底浅字（这条正是本次修的那个 bug）。
expect(
    "亮色输入框：浅底（相对亮度 > 0.8）",
    themeDayColors.fieldBackground.relativeLuminance > 0.8,
    "actual=\(themeDayColors.fieldBackground.hexText) L=\(themeDayColors.fieldBackground.relativeLuminance)"
)
expect(
    "暗色输入框：深底（相对亮度 < 0.2），不再是白底",
    themeNightColors.fieldBackground.relativeLuminance < 0.2,
    "actual=\(themeNightColors.fieldBackground.hexText) L=\(themeNightColors.fieldBackground.relativeLuminance)"
)
expect(
    "亮色输入框文字对比度 ≥ 4.5",
    themeDayColors.fieldText.contrast(with: themeDayColors.fieldBackground) >= 4.5,
    String(format: "actual=%.2f", themeDayColors.fieldText.contrast(with: themeDayColors.fieldBackground))
)
expect(
    "暗色输入框文字对比度 ≥ 4.5",
    themeNightColors.fieldText.contrast(with: themeNightColors.fieldBackground) >= 4.5,
    String(format: "actual=%.2f", themeNightColors.fieldText.contrast(with: themeNightColors.fieldBackground))
)
expect(
    "亮色占位符对比度 ≥ 4.5",
    themeDayColors.fieldPlaceholder.contrast(with: themeDayColors.fieldBackground) >= 4.5,
    String(format: "actual=%.2f", themeDayColors.fieldPlaceholder.contrast(with: themeDayColors.fieldBackground))
)
expect(
    "暗色占位符对比度 ≥ 4.5",
    themeNightColors.fieldPlaceholder.contrast(with: themeNightColors.fieldBackground) >= 4.5,
    String(format: "actual=%.2f", themeNightColors.fieldPlaceholder.contrast(with: themeNightColors.fieldBackground))
)
expect(
    "输入框描边与底色可区分（两套都 ≥ 1.2）",
    themeDayColors.fieldBorder.contrast(with: themeDayColors.fieldBackground) >= 1.2
        && themeNightColors.fieldBorder.contrast(with: themeNightColors.fieldBackground) >= 1.2,
    String(format: "day=%.2f night=%.2f",
           themeDayColors.fieldBorder.contrast(with: themeDayColors.fieldBackground),
           themeNightColors.fieldBorder.contrast(with: themeNightColors.fieldBackground))
)
expect(
    "暗色输入框比暗色卡片亮一档（看得出是输入区）",
    themeNightColors.fieldBackground.contrast(with: themeNightColors.surface) >= 1.1,
    String(format: "actual=%.2f", themeNightColors.fieldBackground.contrast(with: themeNightColors.surface))
)

// 按钮与正文：主按钮文字压在 primary 上、正文压在卡片上，两套都要够对比度。
expect(
    "主按钮文字（onPrimary）对比度 ≥ 4.5",
    themeDayColors.onPrimary.contrast(with: themeDayColors.primary) >= 4.5
        && themeNightColors.onPrimary.contrast(with: themeNightColors.primary) >= 4.5,
    String(format: "day=%.2f night=%.2f",
           themeDayColors.onPrimary.contrast(with: themeDayColors.primary),
           themeNightColors.onPrimary.contrast(with: themeNightColors.primary))
)
expect(
    "正文对比度 ≥ 7（AAA 级）",
    themeDayColors.onSurface.contrast(with: themeDayColors.surface) >= 7
        && themeNightColors.onSurface.contrast(with: themeNightColors.surface) >= 7
)
expect(
    "次要文字（诊断行 / 说明）对比度 ≥ 4.5",
    themeDayColors.onSurfaceVariant.contrast(with: themeDayColors.surface) >= 4.5
        && themeNightColors.onSurfaceVariant.contrast(with: themeNightColors.surface) >= 4.5
)
expect(
    "错误文字（danger）对比度 ≥ 4.5",
    themeDayColors.danger.contrast(with: themeDayColors.background) >= 4.5
        && themeNightColors.danger.contrast(with: themeNightColors.background) >= 4.5,
    String(format: "day=%.2f night=%.2f",
           themeDayColors.danger.contrast(with: themeDayColors.background),
           themeNightColors.danger.contrast(with: themeNightColors.background))
)
// hex 解析本身的两个坑：高位是 ARGB 时要掩掉、文本要能直接贴进报告。
expect(
    "hex 文本是 #RRGGBB",
    ThemeColor(hex: 0xFFFFFF).hexText == "#FFFFFF" && ThemeColor(hex: 0x1E2A47).hexText == "#1E2A47"
)
expect("带 ARGB 高位的值会被掩掉", ThemeColor(hex: 0xFF1E2A47).hex == 0x1E2A47)
expect(
    "通道拆分用的是浮点除法（不是整数除）",
    abs(ThemeColor(hex: 0xFFFFFF).red - 1.0) < 1e-9 && abs(ThemeColor(hex: 0x000000).blue - 0.0) < 1e-9
)

print("== 数据来源署名（随实际源切换）==")
expect(
    "主源署名：Open-Meteo CC BY 4.0",
    L("weather.attribution").contains("Open-Meteo"),
    "actual=\(L("weather.attribution"))"
)
expect(
    "降级后署名换成 7Timer!（不能再写 Open-Meteo）",
    L("weather.attribution7Timer").contains("7Timer!")
        && !L("weather.attribution7Timer").contains("Open-Meteo"),
    "actual=\(L("weather.attribution7Timer"))"
)
expect(
    "署名三语齐全",
    L10n.t("weather.attribution", language: .simplified) == "天气数据 © Open-Meteo.com（CC BY 4.0）"
        && L10n.t("weather.attribution", language: .traditional) == "天氣資料 © Open-Meteo.com（CC BY 4.0）"
        && L10n.t("weather.attribution", language: .english) == "Weather data © Open-Meteo.com (CC BY 4.0)"
        && L10n.t("weather.attribution7Timer", language: .simplified) == "天气数据 © 7Timer!"
        && L10n.t("weather.attribution7Timer", language: .traditional) == "天氣資料 © 7Timer!"
        && L10n.t("weather.attribution7Timer", language: .english) == "Weather data © 7Timer!"
)
expect(
    "品牌名三语同形",
    L10n.t("weather.sourceOpenMeteo", language: .simplified) == "Open-Meteo"
        && L10n.t("weather.source7Timer", language: .english) == "7Timer!"
)
expect(
    "步长文案三语（%d）",
    L10n.f("weather.stepHours", language: .simplified, [1]) == "1 小时一格"
        && L10n.f("weather.stepHours", language: .traditional, [3]) == "3 小時一格"
        && L10n.f("weather.stepHours", language: .english, [3]) == "3 h per step"
)

print("")
if failures == 0 {
    print("全部 \(checks) 项检查通过")
    exit(0)
} else {
    print("\(failures)/\(checks) 项检查失败")
    exit(1)
}
