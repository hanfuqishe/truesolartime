import Foundation

/// 切城市 / 换地点时的**并行多精度探测**（安卓把境外首屏从 120 秒压到 2.2 秒的同一策略）。
///
/// 做法：AUTO 模式下**并行**发 **5 个**单块探测（每块几 KB）——
/// **OSM z3 / OSM z12**、高德 z12 / z10 / z3 —— 谁先回来算谁。
///
/// **先换源，再降级**（区域偏好只决定「同精度时选谁」，不再决定「只用谁」）：
/// 1. 同一精度上，偏好源有内容 → 用**偏好源**；
/// 2. 偏好源在这一级空白 / 失败、另一源有内容 → **用另一源**（这是「南极中山站」的关键：
///    它标 `cn` 走高德，可高德在南极是空白瓦片，OSM 反而有海岸线 —— 应该换源而不是一路降级）；
/// 3. z12 两源都无内容 → 看 z10，再看 z3；全无 → 底图不可用。
///
/// 时间预算：**4.0 秒硬超时**（只用于「一块都没回来 → 不可用」）；
/// 回来一块就**先到先用**出图，之后由 `BasemapUpgrade` 逐个比较、**渐进升级**（10 秒窗口）。
///
/// 结论直接定级：选中级别**之上**的级别一律视为「无内容」，`zoomStep` 一步落位
/// （不再一屏一屏地降），并打上 **5 分钟恢复冷却**（否则 z3 一出图又弹回 z12，就是猛跳）。
enum BasemapProbe {

    /// 硬超时：4 秒内没凑齐也必须给结论。
    static let hardTimeoutSeconds: TimeInterval = 4.0

    /// 探测结果缓存有效期：5 分钟。
    static let cacheTTLSeconds: TimeInterval = 300
    /// 缓存指纹的粒度（度）：0.001° ≈ 111 m，即「~100 米」。
    static let cacheGridDegrees: Double = 0.001
    /// 高德探测的精度档：从高到低。
    static let amapZoomLevels: [Int] = [12, 10, 3]
    /// OSM 探测的精度档：z12（局部细节）+ z3（全球底图，最容易通）。
    static let osmZoomLevels: [Int] = [12, 3]
    /// 探测 OSM 用的全球那一块（z3）。
    static let osmZoom = BasemapState.worldZoom
    /// 选定 OSM 时显示的精度。
    static let displayZoom = 12
    /// 判定的精度顺序：z12 → z10 → z3（**精度优先于源**）。
    static let decisionZooms: [Int] = [12, 10, 3]

    /// 探测结论（纯值）。
    struct Decision: Equatable {
        /// 用哪个源。
        let source: BasemapSource
        /// 显示用的精度；`nil` = 连全球底图都没有内容（底图不可用）。
        let zoom: Int?
    }

    /// 纯函数：**先换源、再降级**的选源规则。
    ///
    /// 从 z12 往下逐级看：某一级只要**任一源有内容**就定下来 —— 两源都有内容时用**偏好源**，
    /// 只有另一源有内容时用**另一源**（换源优先于降级）。全无内容 → 不可用。
    ///
    /// - Parameters:
    ///   - osm: OSM 各级别是否有内容（z12 / z3 已在 `osmZoomLevels` 探过）。
    ///   - amap: 高德各级别是否有内容。
    ///   - preferred: 区域偏好源（同精度时优先）。
    static func decide(
        osm: [Int: Bool],
        amap: [Int: Bool],
        preferred: BasemapSource
    ) -> Decision {
        for zoom in decisionZooms {
            let osmHasContent = osm[zoom] == true
            let amapHasContent = amap[zoom] == true
            switch (osmHasContent, amapHasContent) {
            case (true, true):
                // 同级两源都有内容 → 用偏好源。
                return Decision(source: preferred, zoom: zoom)
            case (true, false):
                return Decision(source: .osm, zoom: zoom)
            case (false, true):
                return Decision(source: .amapVector, zoom: zoom)
            case (false, false):
                continue
            }
        }
        return Decision(source: preferred, zoom: nil)
    }

    /// 选中级别**之上**的精度档（这些档已经确定「没有内容」，不必再试）。
    static func zoomsAbove(_ zoom: Int) -> [Int] {
        amapZoomLevels.filter { $0 > zoom }
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
