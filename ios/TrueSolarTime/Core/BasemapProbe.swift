import Foundation

/// 切城市 / 换地点时的**并行多精度探测**（安卓把境外首屏从 120 秒压到 2.2 秒的同一策略）。
///
/// 做法：AUTO 模式下**并行**发 4 个单块探测（每块几 KB）——
/// OSM z3、高德 z12、z10、z3 —— 谁先回来算谁，然后「取有内容的最高精度」：
///
/// 1. OSM z3 通（拿到真图片）→ **OSM + z12**；
/// 2. 否则用**高德里有内容（非空白）的最高级别**：z12 > z10 > z3；
/// 3. 全失败 / 全空白 → 底图不可用。
///
/// 时间预算：**4.0 秒硬超时**；一旦已经知道「高德有内容」就 **2.0 秒提前收工**，
/// 不去死等被墙的 OSM。
///
/// 探测结果直接定级：选中级别**之上**的级别一律视为「无内容」，`zoomStep` 一步落位
/// （不再一屏一屏地降），并打上 **5 分钟恢复冷却**（否则 z3 一出图又弹回 z12，就是猛跳）。
enum BasemapProbe {

    /// 硬超时：4 秒内没凑齐也必须给结论。
    static let hardTimeoutSeconds: TimeInterval = 4.0
    /// 提前收工：已知「高德有内容」时等 2 秒就够，不再等 OSM。
    static let earlyExitSeconds: TimeInterval = 2.0
    /// 探测结果缓存有效期：5 分钟。
    static let cacheTTLSeconds: TimeInterval = 300
    /// 缓存指纹的粒度（度）：0.001° ≈ 111 m，即「~100 米」。
    static let cacheGridDegrees: Double = 0.001
    /// 高德探测的精度档：从高到低。
    static let amapZoomLevels: [Int] = [12, 10, 3]
    /// 探测 OSM 用的精度（全球底图那一块，最小、最容易通）。
    static let osmZoom = BasemapState.worldZoom
    /// 选定 OSM 时显示的精度。
    static let displayZoom = 12

    /// 探测结论（纯值）。
    struct Decision: Equatable {
        /// 用哪个源。
        let source: BasemapSource
        /// 显示用的精度；`nil` = 连全球底图都没有内容（底图不可用）。
        let zoom: Int?
    }

    /// 纯函数：按「OSM 通不通 + 高德各精度有没有内容」给结论。
    static func decide(osmReachable: Bool, amap: [Int: Bool]) -> Decision {
        if osmReachable {
            return Decision(source: .osm, zoom: displayZoom)
        }
        for zoom in amapZoomLevels where amap[zoom] == true {
            return Decision(source: .amapVector, zoom: zoom)
        }
        return Decision(source: .amapVector, zoom: nil)
    }

    /// 选中级别**之上**的精度档（这些档已经确定「没有内容」，不必再试）。
    static func zoomsAbove(_ zoom: Int) -> [Int] {
        amapZoomLevels.filter { $0 > zoom }
    }

    /// 什么时候可以**提前收工**（2 秒那一枪该不该开）。
    ///
    /// 条件：**不存在比当前最优精度更高、且还没有结论的档**。
    /// 否则会出现「z3 先回来 → 2 秒一到就出结论 → 选了低精度」，而 z12 其实还在飞
    /// （单块 2.5 秒超时、整体 4 秒硬顶，完全等得起）。
    ///
    /// 「有结论」= 已经出现在 `amap` 里：无论 `true`（有内容）还是 `false`（空白 / 失败）；
    /// 只有**还在飞**（字典里没有这个键）才算没结论。
    ///
    /// - Parameters:
    ///   - amap: 已回来的高德探测结果（精度 → 是否有内容）。
    ///   - zooms: 参与探测的档位（默认 `[12, 10, 3]`）。
    static func shouldEarlyExit(amap: [Int: Bool], zooms: [Int] = amapZoomLevels) -> Bool {
        guard let best = amap.filter({ $0.value }).keys.max() else { return false }
        // 还有更高的档没结论（还在飞）→ 不许早退，必须等它。
        return !zooms.contains { $0 > best && amap[$0] == nil }
    }

    /// 由结论换算 `zoomStep`：0 正常、1 降一级、2 降两级、3 = z3 全球、4 = 不可用。
    ///
    /// **一步落位**：选中 z10 就直接 `zoomStep = 2`，不再「先 z11 再 z10」。
    static func zoomStep(for decision: Decision, requestedZoom: Int = displayZoom) -> Int {
        guard let zoom = decision.zoom else { return 4 }
        if zoom >= requestedZoom { return 0 }
        if zoom > BasemapState.worldZoom {
            return min(requestedZoom - zoom, BasemapState.maxZoomDrop)
        }
        return 3
    }

    /// 缓存指纹：按 `cacheGridDegrees`（≈100 m）量化，同一格内的移动复用结果。
    static func cacheKey(latitude: Double, longitude: Double) -> String {
        let lat = Int((latitude / cacheGridDegrees).rounded())
        let lon = Int((longitude / cacheGridDegrees).rounded())
        return "\(lat),\(lon)"
    }

    /// 需要重新探测吗？（没缓存 / 换了地点格 / 超过 5 分钟 → 是）
    static func needsProbe(cached: BasemapProbeCache?, key: String, now: TimeInterval) -> Bool {
        guard let cached else { return true }
        guard cached.key == key else { return true }
        return now - cached.decidedAt >= cacheTTLSeconds
    }

    /// 「现在该不该探测」—— 与 `needsProbe` 同一条判定（两边命名对齐，方便对照安卓）。
    static func shouldProbe(cached: BasemapProbeCache?, key: String, now: TimeInterval) -> Bool {
        needsProbe(cached: cached, key: key, now: now)
    }

    /// 探测用的那一块瓦片的坐标（探测只取 1 块，几 KB）。
    static func tileOf(latitude: Double, longitude: Double, zoom: Int) -> (x: Int, y: Int)? {
        BasemapTiles.tile(latitude: latitude, longitude: longitude, zoom: zoom)
    }
}

/// 探测结果缓存（地点指纹 + 结论 + 时间）。
struct BasemapProbeCache: Equatable {
    let key: String
    let source: BasemapSource
    let zoom: Int?
    let decidedAt: TimeInterval
}
