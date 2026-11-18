import Foundation

/// 首屏地图的**渐进升级**（取代「一次性定级」）。
///
/// 规则：
/// 1. **先到先用**：第一块有内容的瓦片（任何源 / 级别）立刻出图 —— 通常 z3 几百毫秒就有东西；
/// 2. **只有更好才升级**：后续结果比当前正在用的更好才更新，否则忽略（**永不降级**）；
/// 3. 「更好」= 先比**源**（OSM 优于高德），同源再比**级别**（z12 > z10 > z3）；
/// 4. **冻结**（任一满足就不再升级）：当前已是 `OSM z12`、用户已经手动平移/缩放过地图、
///    距首次出图超过 **10 秒**；
/// 5. 4 秒硬超时**只**用于「一块都没回来 → 不可用」；只要出过图，
///    就**永远不显示「底图不可用」**。
struct BasemapUpgrade: Equatable {

    /// 候选：哪个源、哪个级别。
    struct Candidate: Equatable {
        let source: BasemapSource
        let zoom: Int
    }

    /// 首次出图之后多久冻结升级。
    static let freezeSeconds: TimeInterval = 10
    /// 「一块都没回来 → 不可用」的硬超时。
    static let unavailableTimeoutSeconds: TimeInterval = BasemapProbe.hardTimeoutSeconds

    /// 是否比当前更好：**先比源**（OSM 优先），**同源再比级别**。
    static func isBetter(_ candidate: Candidate, than current: Candidate) -> Bool {
        let candidateSourceRank = candidate.source == .osm ? 1 : 0
        let currentSourceRank = current.source == .osm ? 1 : 0
        if candidateSourceRank != currentSourceRank { return candidateSourceRank > currentSourceRank }
        return candidate.zoom > current.zoom
    }

    /// 已经冻结了吗（不再接受更高精度）。
    static func isFrozen(current: Candidate, firstImageAt: TimeInterval, userInteracted: Bool, now: TimeInterval) -> Bool {
        if current.source == .osm, current.zoom == BasemapProbe.displayZoom { return true }
        if userInteracted { return true }
        return now - firstImageAt >= freezeSeconds
    }

    /// 是否应该采用这个候选（返回 true 表示「出图 / 升级」）。
    ///
    /// - 还没有当前图：**先到先用**，直接采用（并记下首次出图时刻）；
    /// - 已经冻结：忽略；
    /// - 比当前更好：升级（首次出图时刻不变，冻结计时从首图算）。
    static func shouldAdopt(
        candidate: Candidate,
        current: Candidate?,
        firstImageAt: TimeInterval?,
        userInteracted: Bool,
        now: TimeInterval
    ) -> Bool {
        guard let current, let firstImageAt else { return true }
        if isFrozen(current: current, firstImageAt: firstImageAt, userInteracted: userInteracted, now: now) {
            return false
        }
        return isBetter(candidate, than: current)
    }

    /// 4 秒硬超时到了，而且**一块都没回来** → 不可用；出过图就永远不是不可用。
    static func isUnavailable(current: Candidate?, startedAt: TimeInterval, now: TimeInterval) -> Bool {
        guard current == nil else { return false }
        return now - startedAt >= unavailableTimeoutSeconds
    }

    /// 诊断那一行：`z3 @312ms → z12 @1830ms`；没有升级时只有首图，没有首图时返回空串。
    static func timeline(first: (zoom: Int, ms: Int)?, upgrades: [(zoom: Int, ms: Int)]) -> String {
        var parts: [String] = []
        if let first { parts.append("z\(first.zoom) @\(first.ms)ms") }
        parts.append(contentsOf: upgrades.map { "z\($0.zoom) @\($0.ms)ms" })
        return parts.joined(separator: " → ")
    }
}
