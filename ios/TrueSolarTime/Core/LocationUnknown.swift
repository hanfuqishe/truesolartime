import Foundation

/// 未知态（拿不到定位）时界面上的占位符。
///
/// 全部用**半角**字符：真太阳时 `--:--:--` 的宽度要接近真实时间（不跳版），
/// 且绝不能混进 U+2014 / U+2012 / U+FF0D 这类「看起来像连字符」的字符 —— 字体一换宽度就变。
enum Placeholders {

    /// 真太阳时：`--:--:--`
    static let time = "--:--:--"
    /// 短占位：时辰、白昼、地名行里的短值。
    static let short = "--"
    /// 一般占位：高度角、经纬度、日期行天气。
    static let dash = "--"
    /// 逐时行每格的温度。
    static let temperature = "-°"

    static var all: [String] { [time, short, dash, temperature] }

    /// 只允许半角连字符（0x2D）、冒号（0x3A）、度（0xB0）。
    static func isAllowedCharacters(_ text: String) -> Bool {
        let allowed: Set<UInt32> = [0x2D, 0x3A, 0xB0]
        return text.unicodeScalars.allSatisfy { allowed.contains($0.value) }
    }
}

/// 「定位不可用（未知态）」：**跟随 GPS 的意图** + 拿不到有效定位。
///
/// 注意这是两件事的组合：**不是**「有没有定位」这么简单 —— 用户明确选了预设城市 / 手动坐标时，
/// 即使没有定位也**不是**未知态（那是他选了别的地点）。
enum LocationUnknown {

    /// 触发条件：跟随意图（`followGps`）成立，且当前**没有有效定位**（未授权 / 看门狗超时）。
    static func isUnknown(followGps: Bool, hasValidFix: Bool) -> Bool {
        followGps && !hasValidFix
    }

    // MARK: 未知态的昼夜（按系统时钟，不看太阳）

    /// 白天起点（含）：06:00。
    static let isDaytimeStartHour = 6
    /// 白天终点（不含）：18:00。
    static let isDaytimeEndHour = 18

    /// 未知态该用白天还是夜间配色：**按系统时区的钟点**判断（06:00 ≤ 小时 < 18:00 → 白天）。
    ///
    /// 为什么不用 `snapshot.isDay`（太阳高度角）：未知态没有可信坐标（lat/lon 传 0），
    /// 高度角恒为负 → 手机系统时间是白天也会被渲染成夜间（build 71 的 bug）。
    /// 与 Android `LocationAvailability.isDaytime` 同一套规则；只影响主题与卡片配色，
    /// **不影响**占位符逻辑。
    static func isDaytime(epochSeconds: Int, systemOffsetSeconds: Int) -> Bool {
        let secondsOfDay = ((epochSeconds % 86_400) + 86_400) % 86_400
        let local = ((secondsOfDay + systemOffsetSeconds) % 86_400 + 86_400) % 86_400
        let hour = local / 3_600
        return hour >= isDaytimeStartHour && hour < isDaytimeEndHour
    }
    // MARK: 跟随意图的状态转移（纯函数，回归断言用）

    /// 用户点「跟随 GPS」之后四个状态位的目标值。
    struct FollowStart: Equatable {
        let followGps: Bool
        let hasValidFix: Bool
        let trackingGps: Bool
        let waitingForFix: Bool
    }

    /// **无权限也必须先落意图**：`followGps` 恒为 `true`，界面才能进入未知态。
    ///
    /// 真机 bug（build 70）：`startGpsTracking` 在无权限时 `guard ... return` 直接返回，
    /// 后面的 `setFollowGps(true)` 永远不执行 → 意图仍是 false → `isLocationUnknown` 恒 false
    /// → 「撤销权限 + 打开跟随 GPS」后界面继续显示上一个地点。这条纯函数把这个顺序钉死。
    static func startFollowing(hasPermission: Bool, hasCurrentFix: Bool) -> FollowStart {
        if hasPermission {
            return FollowStart(
                followGps: true,
                hasValidFix: hasCurrentFix,
                trackingGps: true,
                waitingForFix: true
            )
        }
        // 没授权：意图照样记下来，但**不算有有效定位**，也不启动采样 / 看门狗。
        return FollowStart(followGps: true, hasValidFix: false, trackingGps: false, waitingForFix: false)
    }
    /// 未知态的标准时间快照：**按系统时区**（显式传偏移，负偏移照常生效），太阳量不可用。
    ///
    /// 为什么 latitude/longitude 给 0：未知态根本不显示任何太阳量（真太阳时 / 高度角 / 时辰
    /// 全是占位符），但标准时间与 UTC 标签要用系统时区，所以只有偏移是有效的。
    static func snapshot(date: Date, systemOffsetSeconds: Int) -> SolarSnapshot {
        SolarTimeSnapshot.compute(
            date: date,
            latitude: 0,
            longitude: 0,
            offsetSeconds: systemOffsetSeconds
        )
    }

    /// 未知态的逐时占位：**保留六格**，首格「现在」，之后按系统时间逐小时（跨午夜自然回绕）。
    static func hourlySlots(nowEpochSeconds: Int, count: Int = 6) -> [WeatherSlot] {
        (0..<count).map { index in
            WeatherSlot(epochSeconds: nowEpochSeconds + index * 3600, isNow: index == 0)
        }
    }

    // MARK: 未知态地图（恒 z3、不降级、2 秒封顶）

    /// 未知态固定用 z3 全球底图，**不逐级降级**。
    static let mapZoom = BasemapState.worldZoom
    /// 探测用的东亚 z3 瓦片（x=6, y=2）。
    ///
    /// 不能用 (0,0)：那是太平洋中间的大洋瓦片，高德会返回灰底 → 被空白判定误判成「不可用」。
    static let mapProbeTile = (x: 6, y: 2)
    /// 未知态探测预算：**2 秒**封顶（比正常态首屏探测更短，未知态优先「快」）。
    static let mapProbeTimeoutSeconds: TimeInterval = 2
    /// 「上次成功出图的源」缓存 TTL：**10 分钟**，只被未知态读写，不影响正常态探测结论。
    static let mapCacheTTLSeconds: TimeInterval = 600

    /// 两块 z3 探测谁赢：**先回来且有内容**者胜（`arrivals` 按到达顺序给）。
    static func decideMap(arrivals: [(source: BasemapSource, hasContent: Bool)]) -> BasemapSource? {
        arrivals.first { $0.hasContent }?.source
    }

    /// 缓存还能用吗（10 分钟内、有源）。
    static func needsMapProbe(cached: BasemapUnknownCache?, now: TimeInterval) -> Bool {
        guard let cached else { return true }
        return now - cached.at >= mapCacheTTLSeconds
    }
}

/// 「上次成功出图的源」：未知态地图的缓存（与正常态的探测缓存 `basemap.probe.*` 分开存）。
struct BasemapUnknownCache: Equatable {
    let source: BasemapSource
    let at: TimeInterval
}
