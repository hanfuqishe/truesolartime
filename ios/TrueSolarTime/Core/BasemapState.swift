import Foundation

/// 一块瓦片实际由哪个源提供（`MapStyle.auto` 不算源，它只是「自动选」这个策略）。
enum BasemapSource: String, Equatable, CaseIterable {
    case osm
    case amapVector
    case amapSatellite

    /// 高德的两个源（境内首选；也是 OSM 不可达时的回退目标）。
    var isAmap: Bool { self != .osm }

    var mapStyle: MapStyle {
        switch self {
        case .osm: return .osm
        case .amapVector: return .amapVector
        case .amapSatellite: return .amapSatellite
        }
    }

    var label: String { mapStyle.label }
    var attribution: String { mapStyle.attribution }
}

extension MapStyle {
    /// 具体的瓦片源；`.auto` 没有固定源（由 `BasemapState` 决定）。
    var basemapSource: BasemapSource? {
        switch self {
        case .auto: return nil
        case .osm: return .osm
        case .amapVector: return .amapVector
        case .amapSatellite: return .amapSatellite
        }
    }
}

/// 地图底图的四级兜底状态机（纯逻辑：时间全部由调用方传入，自检可以逐帧驱动）。
///
/// 与 Android 同策略：
/// 1. **首选不变**：境内高德、境外 OSM（`preferred` 由 `MapStyle.effective` 给出）；
/// 2. **只有「自动」模式会回退**：OSM **连续失败 3 次** → 换成高德，之后直接用高德
///    （不再每块瓦片先失败一遍）；切源后 **5 秒内**的失败一律丢弃（那是上一个源的迟到结果）；
/// 3. **手动选择底图**（OSM / 高德矢量 / 高德卫星）→ 不回退、不探测、不降级；
/// 4. **空白瓦片**按「整屏」判：一屏里看过的所有瓦片都空白才算这一屏空白（`closeScreenBatch`），
///    然后 **z12 → z11 → z10**（降 2 级）→ **z3 全球底图** → 仍空白则 `unavailable`（界面显示小字）；
/// 5. **恢复**：回退后每 **5 分钟**探测一次 OSM（一块 z3 瓦片 + 图片魔数校验），成功即切回并清零。
struct BasemapState: Equatable {

    enum Mode: Equatable {
        /// 自动（跟随地点）：会回退、会探测、会降级。
        case auto
        /// 用户明确选了某个底图：一切兜底都关掉。
        case manual
    }

    enum Status: Equatable {
        /// 正常。
        case live
        /// OSM 已回退到高德，正在等下一次探测。
        case probing
        /// 连 z3 全球底图都空白：界面显示「底图不可用」。
        case unavailable
    }

    // MARK: 常量（与 Android 对齐）

    /// OSM 连续失败多少次触发回退。连续：中间成功一次就清零。
    static let osmFailureLimit = 3
    /// 切源后的宽限期：这段时间内的失败属于上一个源的迟到结果，丢弃。
    static let switchGraceSeconds: TimeInterval = 5
    /// 回退后探测 OSM 的间隔：5 分钟。
    static let probeIntervalSeconds: TimeInterval = 300
    /// 逐级降级的级数（z12 → z11 → z10）。
    static let maxZoomDrop = 2
    /// 全球底图的缩放级。
    static let worldZoom = 3
    /// 一屏至少看过这么多块瓦片才判「整屏空白」（只有 1 块也可能是地图刚起步的边缘瓦片）。
    static let minTilesPerScreen = 2
    /// **回弹静默窗口**：最近 30 秒内有过新的失败，就不许把降级档位往回调。
    ///
    /// 安卓真机的教训：z3 一出图就立刻弹回 z12，z12 又失败 → 11 → 10 → 3 → 又出图 → 弹回…
    /// 2 秒内发了 441 次状态。回弹必须有静默窗口，否则就是一个自激循环。
    static let recoveryQuietSeconds: TimeInterval = 30
    /// **回弹冷却**：回弹过一次之后，5 分钟内不再回弹（否则会在两档之间来回抖）。
    static let recoveryCooldownSeconds: TimeInterval = 300
    /// 程序化改视口（`setRegion`）后的静默期：这段时间里回来的失败**不计**。
    ///
    /// 改视口会取消在飞的瓦片请求，网络层会把「被取消」也报成失败；把它当真实失败计数，
    /// 就等于自己给自己喂失败，正好喂出上面那个循环。
    static let viewportSettleSeconds: TimeInterval = 2

    // MARK: 状态

    let mode: Mode
    /// 首选源：境内高德、境外 OSM。
    let preferred: BasemapSource
    /// 当前实际使用的源。
    private(set) var active: BasemapSource
    /// OSM 连续失败次数（成功一次清零）。
    private(set) var osmFailures = 0
    /// 被判为「空白」的瓦片累计块数（诊断用）。
    private(set) var blankDetections = 0
    /// 降级档位：0 正常、1 降一级、2 降两级、3 = z3 全球底图、4 = 不可用。
    private(set) var zoomStep = 0
    private(set) var lastSwitchAt: TimeInterval
    private(set) var lastProbeAt: TimeInterval?
    /// 最近一次**真实**失败的时刻（OSM 失败 / 高德空白 / 整屏空白降级）。回弹静默窗口用它。
    private(set) var lastFailureAt: TimeInterval?
    /// 最近一次「降级档位往回弹」的时刻。回弹冷却用它。
    private(set) var lastRecoveryAt: TimeInterval?
    /// 程序化改视口之后的静默期截止时刻（这之前回来的失败不计）。
    private(set) var viewportSettleUntil: TimeInterval = -Double.greatestFiniteMagnitude
    private var screenTiles = 0
    private var screenBlankTiles = 0

    init(
        mode: Mode,
        preferred: BasemapSource,
        now: TimeInterval,
        active: BasemapSource? = nil
    ) {
        self.mode = mode
        self.preferred = preferred
        self.active = active ?? preferred
        self.lastSwitchAt = -Double.greatestFiniteMagnitude
        self.lastProbeAt = nil
        _ = now
    }

    // MARK: 派生状态

    /// 对外暴露的**唯一**快照：UI 只订阅它。
    ///
    /// 为什么要压成一个值类型：安卓真机上「441 次状态发布」里有大量只是 `zoomFailures` 变了，
    /// 每次都触发整块地图重组，叠加缩放来回弹就是「狂闪」。把「有效 plan」快照化之后，
    /// **计数类字段（failures / blankCount / zoomFailures）变化不会改变 `BasemapUiState`**，
    /// 界面自然不会因为计数而重绘。
    func uiState(requestedZoom: Int) -> BasemapUiState {
        BasemapUiState(
            requestedZoom: requestedZoom,
            source: active,
            zoom: effectiveZoom(requested: requestedZoom),
            degraded: isDegraded,
            unavailable: status == .unavailable,
            fellBack: didFallBackToAmap,
            ready: true
        )
    }

    /// 首屏探测还没结论时的快照（界面显示加载态）。
    func pendingUiState(requestedZoom: Int) -> BasemapUiState {
        BasemapUiState(
            requestedZoom: requestedZoom,
            source: active,
            zoom: effectiveZoom(requested: requestedZoom),
            degraded: false,
            unavailable: false,
            fellBack: false,
            ready: false
        )
    }

    var status: Status {
        if zoomStep >= 4 { return .unavailable }
        if mode == .auto, preferred == .osm, active != .osm { return .probing }
        return .live
    }

    var isDegraded: Bool { zoomStep > 0 }

    /// 是否处于「OSM 不可达 → 已回退高德」的状态（署名要追加一句说明）。
    var didFallBackToAmap: Bool {
        mode == .auto && preferred == .osm && active != .osm
    }

    /// 实际请求的缩放级别；`nil` 表示「底图不可用」（连 z3 都是空白）。
    func effectiveZoom(requested: Int) -> Int? {
        switch zoomStep {
        case 0: return requested
        case 1: return max(requested - 1, Self.worldZoom)
        case 2: return max(requested - 2, Self.worldZoom)
        case 3: return Self.worldZoom
        default: return nil
        }
    }

    /// 下一次探测 OSM 的时刻（不可探测时为 nil）。
    var nextProbeAt: TimeInterval? {
        guard mode == .auto, active != .osm else { return nil }
        guard let last = lastProbeAt else { return nil }
        return last + Self.probeIntervalSeconds
    }

    func shouldProbe(now: TimeInterval) -> Bool {
        guard mode == .auto, active != .osm else { return false }
        guard let last = lastProbeAt else { return true }
        return now - last >= Self.probeIntervalSeconds
    }

    /// 允许把降级档位往回弹吗？
    ///
    /// 三个条件缺一不可：
    /// 1. 自动模式、确实处于降级中（0 < `zoomStep` < 4）；
    /// 2. **最近 30 秒没有新的失败**（回弹静默窗口）—— 否则「z3 出图 → 立刻弹回 z12」会自激；
    /// 3. **距上次回弹 ≥ 5 分钟**（回弹冷却）—— 否则会在相邻两档之间来回抖。
    func canRecoverChain(now: TimeInterval) -> Bool {
        guard mode == .auto, zoomStep > 0, zoomStep < 4 else { return false }
        if let lastFailureAt, now - lastFailureAt < Self.recoveryQuietSeconds { return false }
        if let lastRecoveryAt, now - lastRecoveryAt < Self.recoveryCooldownSeconds { return false }
        return true
    }

    // MARK: 事件

    /// 程序化改了视口（`setRegion`）—— 紧接着 2 秒内回来的失败一律丢弃。
    mutating func noteViewportChanged(at now: TimeInterval) {
        viewportSettleUntil = now + Self.viewportSettleSeconds
    }

    /// 还在视口静默期内吗（这期间的瓦片结果不算数）。
    func isViewportSettling(now: TimeInterval) -> Bool {
        now < viewportSettleUntil
    }

    /// 一块 OSM 瓦片的结果（成功 = 拿到了非空图片；失败 = 超时 / 非 2xx / 解析不出来）。
    mutating func recordOSMTile(success: Bool, at now: TimeInterval) {
        // 手动模式：不回退、不计失败。
        guard mode == .auto else { return }
        // 已经回退到高德了：OSM 结果只可能来自探测，走 `probeSucceeded`。
        guard active == .osm else { return }
        // 程序化改视口后的静默期：这时回来的「失败」多半是改视口把自己的请求取消了，不算。
        guard !isViewportSettling(now: now) else { return }
        // 切源宽限期内的失败丢弃（上一个源的迟到结果）。
        guard now - lastSwitchAt >= Self.switchGraceSeconds else { return }

        if success {
            osmFailures = 0
            return
        }
        osmFailures += 1
        lastFailureAt = now
        guard osmFailures >= Self.osmFailureLimit else { return }

        // 连续 3 次失败：回退到高德，并开始 5 分钟一次的探测。
        active = .amapVector
        osmFailures = 0
        zoomStep = 0
        screenTiles = 0
        screenBlankTiles = 0
        lastSwitchAt = now
        lastProbeAt = now
    }

    /// 一块高德瓦片的像素判定结果（`blank` 来自 `BlankTileAnalysis`）。
    mutating func recordAmapTile(blank: Bool, at now: TimeInterval) {
        guard mode == .auto else { return }
        guard active != .osm else { return }
        // 程序化改视口后的静默期内的结果不算（那批瓦片可能是被我们取消的）。
        guard !isViewportSettling(now: now) else { return }
        // 切源宽限期内的结果丢弃，免得拿上一个源的残瓦片判空白。
        guard now - lastSwitchAt >= Self.switchGraceSeconds else { return }

        screenTiles += 1
        if blank {
            blankDetections += 1
            screenBlankTiles += 1
            lastFailureAt = now
            return
        }
        // 这一档能出图：在**静默窗口 + 冷却**都满足时才允许把降级档位往回弹。
        recoverChainIfAllowed(at: now)
    }

    /// 降级档位往回弹一档（受 `canRecoverChain` 约束）。
    private mutating func recoverChainIfAllowed(at now: TimeInterval) {
        guard canRecoverChain(now: now) else { return }
        zoomStep = max(zoomStep - 1, 0)
        lastRecoveryAt = now
        screenTiles = 0
        screenBlankTiles = 0
    }

    /// 「这一屏画完了」：整屏都空白才降一级。
    ///
    /// - 只有**所有**看过的瓦片都空白才算空白屏（撒哈拉、冰原这类纯色**真**瓦片里也有细节，
    ///   而且只要有一块有内容，这一屏就不算空白）；
    /// - 瓦片数太少（< `minTilesPerScreen`）时不判，避免地图刚起步时误降。
    mutating func closeScreenBatch(at now: TimeInterval) {
        defer {
            screenTiles = 0
            screenBlankTiles = 0
        }
        guard mode == .auto, active != .osm else { return }
        guard screenTiles >= Self.minTilesPerScreen, screenBlankTiles == screenTiles else { return }
        zoomStep = min(zoomStep + 1, 4)
        // 降级本身就是一次失败：把静默窗口重新拉开，别让下一屏的图马上把档位弹回去。
        lastFailureAt = now
    }

    /// 探测结果：成功就切回 OSM 并全部清零（缩放也回到正常）。
    mutating func probeSucceeded(at now: TimeInterval) {
        guard mode == .auto else { return }
        active = preferred
        osmFailures = 0
        zoomStep = 0
        screenTiles = 0
        screenBlankTiles = 0
        lastSwitchAt = now
        lastProbeAt = now
        lastRecoveryAt = now
    }

    /// 探测失败：只更新时间戳，等下一个 5 分钟。
    mutating func probeFailed(at now: TimeInterval) {
        lastProbeAt = now
    }

    /// 并行探测给出的结论**一步落位**：直接定源 + 定级，并打上 5 分钟恢复冷却。
    ///
    /// 为什么不是「先按 z12 出生、再一屏一屏降」：那样地图还没出图就先建一次 overlay、
    /// 失败、再重建 —— MapKit 会取消在飞请求、旧缓存清掉后不重发，表现就是一直转圈。
    /// 这里一次定到位，overlay 是「按结论出生」的。
    mutating func applyProbeDecision(
        source: BasemapSource,
        zoom: Int?,
        requestedZoom: Int = BasemapProbe.displayZoom,
        at now: TimeInterval
    ) {
        let decision = BasemapProbe.Decision(source: source, zoom: zoom)
        active = source
        zoomStep = BasemapProbe.zoomStep(for: decision, requestedZoom: requestedZoom)
        osmFailures = 0
        screenTiles = 0
        screenBlankTiles = 0
        lastSwitchAt = now
        // 冷却：5 分钟内不许因为「这一档出图了」把级别弹回去（z3 一出图就弹 z12 = 猛跳）。
        lastRecoveryAt = now
        if zoom == nil { lastFailureAt = now }
    }
}

/// UI 只订阅这个快照。**计数（failures / blankCount / zoomFailures）不在里面** ——
/// 它们变了界面不重绘，也就不会出现「2 秒 441 次状态发布 + 缩放来回弹」那种狂闪。
struct BasemapUiState: Equatable {
    /// 地图当前请求的缩放（MapKit 给的）。
    let requestedZoom: Int
    /// 实际使用的瓦片源。
    let source: BasemapSource
    /// 实际请求的缩放；`nil` = 底图不可用。
    let zoom: Int?
    /// 是否处于降级状态。
    let degraded: Bool
    /// 是否连 z3 都空白（界面显示「底图不可用」）。
    let unavailable: Bool
    /// 是否因为 OSM 不可达回退到了高德。
    let fellBack: Bool
    /// 首屏探测是否已经有结论：`false` 时界面显示加载态（骨架 + 「正在载入底图…」），
    /// **不要**先用默认源把地图建出来再切 —— 那会让 MapKit 取消在飞请求、一直转圈。
    let ready: Bool
}

/// 瓦片几何 / URL / 魔数校验（纯函数，自检覆盖）。
enum BasemapTiles {

    /// 把 `fromZoom` 的瓦片坐标折算到 `toZoom`（降级时显示父瓦片，靠 MapKit 放大绘制）。
    static func parentTile(x: Int, y: Int, from fromZoom: Int, to toZoom: Int) -> (x: Int, y: Int)? {
        guard toZoom >= 0, fromZoom >= toZoom, fromZoom - toZoom < 31 else { return nil }
        let shift = fromZoom - toZoom
        return (x >> shift, y >> shift)
    }

    /// 经纬度 → Web Mercator 瓦片坐标（探测 z3 小瓦片用）。
    static func tile(latitude: Double, longitude: Double, zoom: Int) -> (x: Int, y: Int)? {
        guard zoom >= 0, zoom <= 22 else { return nil }
        let count = Double(1 << zoom)
        let clampedLatitude = min(max(latitude, -85.05112878), 85.05112878)
        let clampedLongitude = min(max(longitude, -180), 180)
        let x = (clampedLongitude + 180) / 360 * count
        let latRad = clampedLatitude * Double.pi / 180
        let y = (1 - log(tan(latRad) + 1 / cos(latRad)) / Double.pi) / 2 * count
        let maxIndex = Int(count) - 1
        return (
            max(0, min(Int(x.rounded(.down)), maxIndex)),
            max(0, min(Int(y.rounded(.down)), maxIndex))
        )
    }

    /// 具体的瓦片地址（`MapStyle.tileURLTemplate` 里的 `{z}/{x}/{y}` 替换）。
    static func tileURL(source: BasemapSource, x: Int, y: Int, z: Int) -> URL? {
        let text = source.mapStyle.tileURLTemplate
            .replacingOccurrences(of: "{x}", with: "\(x)")
            .replacingOccurrences(of: "{y}", with: "\(y)")
            .replacingOccurrences(of: "{z}", with: "\(z)")
        return URL(string: text)
    }

    /// 响应的前几个字节是不是真的图片（PNG / JPEG）。
    ///
    /// 恢复探测必须校验：被劫持 / 被运营商插页时经常返回 **200 的 HTML**，
    /// 只看状态码会以为「OSM 恢复了」，切回去又满屏空白。
    static func looksLikeImage(data: Data?) -> Bool {
        guard let data, data.count >= 4 else { return false }
        return isPNG(data) || isJPEG(data)
    }

    static func isPNG(_ data: Data) -> Bool {
        let magic: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        guard data.count >= magic.count else { return false }
        return Array(data.prefix(magic.count)) == magic
    }

    static func isJPEG(_ data: Data) -> Bool {
        guard data.count >= 3 else { return false }
        let prefix = Array(data.prefix(3))
        return prefix == [0xFF, 0xD8, 0xFF]
    }
}
