import Foundation
import UIKit

/// 地图底图的运行时：持有 `BasemapState`（纯逻辑在 Core），负责
///
/// - 切城市 / 换地点时先做**并行多精度探测**（`BasemapProbe`：4 个单块请求、4 秒硬超时、
///   已知高德有内容就 2 秒提前收工），再用结论**一步定级**；
/// - 每块瓦片的加载结果喂回状态机（OSM 成败、高德空白）；
/// - 回退后每 5 分钟探测一次 OSM（z3 小瓦片 + 图片魔数校验），成功即切回；
/// - **只把「有效 plan 快照」（`BasemapUiState`）发布给界面**：计数变化不发通知。
final class BasemapController: ObservableObject {

    static let shared = BasemapController()

    /// 界面**唯一**订阅的东西：有效 plan 的快照（含「首屏是否已有结论」的 `ready`）。
    @Published private(set) var uiState: BasemapUiState

    private(set) var state: BasemapState
    private var configuredStyle: MapStyle?
    private var configuredSiteKey: String?
    private var place: Place?
    /// 最近一次 MapKit 请求的缩放。
    private var lastRequestedZoom = 12

    // MARK: 首屏探测

    /// 当前这次探测（旧的一律作废）。
    private final class ProbeSession {
        let token: Int
        let key: String
        let place: Place
        var pending: Int
        var osmReachable = false
        var amapResults: [Int: Bool] = [:]
        var done = false

        init(token: Int, key: String, place: Place, pending: Int) {
            self.token = token
            self.key = key
            self.place = place
            self.pending = pending
        }
    }

    private var probeSession: ProbeSession?
    private var probeToken = 0

    private enum CacheKey {
        static let key = "basemap.probe.key"
        static let source = "basemap.probe.source"
        static let zoom = "basemap.probe.zoom"
        static let at = "basemap.probe.at"
    }

    private let defaults = UserDefaults.standard
    /// 一屏瓦片的「静默」计时：最后一块瓦片回来 1.2 秒后判整屏。
    private var settleWorkItem: DispatchWorkItem?
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 16
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()
    private var probeInFlight = false

    private init() {
        let initial = BasemapState(mode: .manual, preferred: .osm, now: 0)
        state = initial
        uiState = initial.uiState(requestedZoom: 12)
    }

    // MARK: 配置

    /// 样式或地点变了就重建状态机（自动模式还要做一次首屏探测）。
    ///
    /// - 位置只按 4 位小数比较（≈11 m）：GPS 抖动不该把「已回退」「已降级」重置掉；
    /// - 手动选底图 → `mode = .manual`（**不探测**、不回退、不降级）；
    /// - 从手动切回「自动」→ 缓存失效，重新探测。
    func configure(style: MapStyle, place: Place, now: Date = Date()) {
        let siteKey = String(format: "%.4f,%.4f", place.latitude, place.longitude)
        guard style != configuredStyle || siteKey != configuredSiteKey else { return }
        let previousStyle = configuredStyle

        let preferred: BasemapSource = style.basemapSource ?? MapStyle.auto.effective(
            countryCode: place.countryCode,
            latitude: place.latitude,
            longitude: place.longitude
        ).basemapSource ?? .osm
        state = BasemapState(
            mode: style == .auto ? .auto : .manual,
            preferred: preferred,
            now: now.timeIntervalSince1970
        )
        configuredStyle = style
        configuredSiteKey = siteKey
        self.place = place

        guard style == .auto else {
            // 手动选底图：不探测，直接按选择出生。
            state.applyProbeDecision(
                source: preferred,
                zoom: BasemapProbe.displayZoom,
                at: now.timeIntervalSince1970
            )
            publishIfChanged()
            return
        }

        // 自动模式：有新鲜缓存就直接用，否则先发「加载态」再并行探测。
        let key = BasemapProbe.cacheKey(latitude: place.latitude, longitude: place.longitude)
        let cameBackToAuto = previousStyle != nil && previousStyle != .auto
        let cached = cameBackToAuto ? nil : cachedProbe()
        if !BasemapProbe.needsProbe(cached: cached, key: key, now: now.timeIntervalSince1970),
           let cached {
            state.applyProbeDecision(source: cached.source, zoom: cached.zoom, at: now.timeIntervalSince1970)
            publishIfChanged()
            return
        }

        // 加载态：地图**先不建**（按结论出生），避免「先建默认源再切源 → 一直转圈」。
        let pending = state.pendingUiState(requestedZoom: lastRequestedZoom)
        if pending != uiState { uiState = pending }
        startProbe(place: place, key: key)
    }

    /// 未知态（定位不可用）：固定 z3、不降级、不触发回退状态机。
    private(set) var isUnknownMode = false

    private enum UnknownCacheKey {
        static let source = "basemap.unknown.source"
        static let at = "basemap.unknown.at"
    }

    /// 进入未知态：先用「上次成功出图的源」缓存（10 分钟），没有缓存就只探 2 块 z3（2 秒封顶）。
    ///
    /// 关键：**不要**拿 (0,0) 走正常地点探测（那会退回串行等超时），也**不要**进回退/降级状态机。
    func configureUnknown(now: Date = Date()) {
        guard !isUnknownMode || configuredStyle != nil else { return }
        isUnknownMode = true
        configuredStyle = .auto
        let stamp = now.timeIntervalSince1970
        let cached = unknownCachedSource()
        if !LocationUnknown.needsMapProbe(cached: cached, now: stamp), let cached {
            // 有缓存：直接用该源 + z3，零探测。
            applyUnknown(source: cached.source, at: stamp)
            return
        }
        // 无缓存：只探 2 块 z3，谁先回来且有内容谁赢。
        state = BasemapState(mode: .manual, preferred: .amapVector, now: stamp)
        let pending = state.pendingUiState(requestedZoom: lastRequestedZoom)
        if pending != uiState { uiState = pending }
        probeUnknownMap(stamp: stamp)
    }

    private func applyUnknown(source: BasemapSource?, at now: TimeInterval) {
        state.applyProbeDecision(source: source ?? .amapVector, zoom: source == nil ? nil : LocationUnknown.mapZoom, at: now)
        publishIfChanged()
    }

    private func unknownCachedSource() -> BasemapUnknownCache? {
        guard let raw = defaults.string(forKey: UnknownCacheKey.source),
              let source = BasemapSource(rawValue: raw)
        else { return nil }
        return BasemapUnknownCache(source: source, at: defaults.double(forKey: UnknownCacheKey.at))
    }

    private func saveUnknownCache(source: BasemapSource) {
        defaults.set(source.rawValue, forKey: UnknownCacheKey.source)
        defaults.set(Date().timeIntervalSince1970, forKey: UnknownCacheKey.at)
    }

    /// 两块 z3 探测（东亚瓦片 x=6,y=2），2 秒封顶。
    private func probeUnknownMap(stamp: TimeInterval) {
        let tile = LocationUnknown.mapProbeTile
        var arrivals: [(source: BasemapSource, hasContent: Bool)] = []
        var finished = false
        let deadline = DispatchWorkItem { [weak self] in
            guard let self, !finished else { return }
            finished = true
            let winner = LocationUnknown.decideMap(arrivals: arrivals)
            if let winner { self.saveUnknownCache(source: winner) }
            self.applyUnknown(source: winner, at: Date().timeIntervalSince1970)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + LocationUnknown.mapProbeTimeoutSeconds, execute: deadline)

        for source in [BasemapSource.osm, .amapVector] {
            guard let url = BasemapTiles.tileURL(source: source, x: tile.x, y: tile.y, z: LocationUnknown.mapZoom) else {
                continue
            }
            var request = URLRequest(url: url)
            request.timeoutInterval = LocationUnknown.mapProbeTimeoutSeconds
            request.setValue("TrueSolarTime-iOS", forHTTPHeaderField: "User-Agent")
            session.dataTask(with: request) { data, response, _ in
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                var ok = (200..<300).contains(status) && BasemapTiles.looksLikeImage(data: data)
                if ok, source.isAmap, let data {
                    if let analysis = BasemapTileSampler.blankAnalysis(data: data), analysis.isBlank { ok = false }
                }
                DispatchQueue.main.async {
                    guard !finished else { return }
                    arrivals.append((source, ok))
                    // 先回来且有内容者胜：一有结果就收工，不必等另一块。
                    if ok {
                        finished = true
                        self.saveUnknownCache(source: source)
                        self.applyUnknown(source: source, at: Date().timeIntervalSince1970)
                    }
                }
            }.resume()
        }
    }

    /// 诊断用：当前是不是「自动」。
    var isAuto: Bool { configuredStyle == .auto }

    var activeSource: BasemapSource { state.active }
    var activeMapStyle: MapStyle { state.active.mapStyle }
    var isDegraded: Bool { state.isDegraded }
    var isUnavailable: Bool { state.status == .unavailable }
    var didFallBack: Bool { state.didFallBackToAmap }
    var osmFailures: Int { state.osmFailures }
    var blankDetections: Int { state.blankDetections }

    // MARK: 瓦片计划

    /// 这一块瓦片该从哪个源、哪个缩放级别取；`nil` = 底图不可用（连 z3 都空白）。
    func plan(requestedZoom: Int) -> (source: BasemapSource, zoom: Int)? {
        if requestedZoom != lastRequestedZoom {
            lastRequestedZoom = requestedZoom
            publishIfChanged()
        }
        guard let zoom = state.effectiveZoom(requested: requestedZoom) else { return nil }
        return (state.active, zoom)
    }

    // MARK: 结果回灌（计数变化**不**发布）

    func noteOSMTile(success: Bool, now: Date = Date()) {
        state.recordOSMTile(success: success, at: now.timeIntervalSince1970)
        publishIfChanged()
    }

    func noteAmapTile(blank: Bool, now: Date = Date()) {
        state.recordAmapTile(blank: blank, at: now.timeIntervalSince1970)
        publishIfChanged()
    }

    /// 程序化改了视口：接下来 2 秒内回来的失败不算（那是被我们自己取消掉的请求）。
    func noteViewportChanged(now: Date = Date()) {
        state.noteViewportChanged(at: now.timeIntervalSince1970)
    }

    /// 每请求一块瓦片就调一次：1.2 秒没有新瓦片 = 这一屏画完了 → 判整屏空白。
    func scheduleScreenSettle() {
        settleWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.state.closeScreenBatch(at: Date().timeIntervalSince1970)
            self.publishIfChanged()
        }
        settleWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: item)
    }

    // MARK: 首屏并行探测

    /// 并行发 4 个单块请求，谁的结论先到算谁；**不挂在调用方的结构化并发上**。
    ///
    /// 组织方式：
    /// - 4 个 `URLSession.dataTask` 各自独立跑，`pending` 计数归零即收工；
    /// - 一个 **4.0 秒硬超时**（到点不论凑没凑齐都出结论，缺的按「无内容」算）；
    /// - 一个 **2.0 秒提前收工**：只要已确认「高德有内容」，就不去死等被墙的 OSM；
    /// - 每次探测带 `token`，旧结果直接丢弃（换城市时不会串）。
    private func startProbe(place: Place, key: String) {
        probeToken += 1
        let session = ProbeSession(
            token: probeToken,
            key: key,
            place: place,
            pending: 1 + BasemapProbe.amapZoomLevels.count
        )
        probeSession = session

        let hard = DispatchWorkItem { [weak self] in
            self?.finishProbe(session)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + BasemapProbe.hardTimeoutSeconds, execute: hard)
        let early = DispatchWorkItem { [weak self] in
            self?.earlyExitIfAmapContent(session)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + BasemapProbe.earlyExitSeconds, execute: early)

        probeTile(source: .osm, zoom: BasemapProbe.osmZoom, place: place) { [weak self] ok in
            self?.recordProbe(session, source: .osm, zoom: BasemapProbe.osmZoom, ok: ok)
        }
        for zoom in BasemapProbe.amapZoomLevels {
            probeTile(source: .amapVector, zoom: zoom, place: place) { [weak self] ok in
                self?.recordProbe(session, source: .amapVector, zoom: zoom, ok: ok)
            }
        }
    }

    /// 取一块瓦片并判定「有没有内容」：OSM 看魔数即可；高德还要过空白像素判定。
    private func probeTile(
        source: BasemapSource,
        zoom: Int,
        place: Place,
        completion: @escaping (Bool) -> Void
    ) {
        guard let coords = BasemapProbe.tileOf(latitude: place.latitude, longitude: place.longitude, zoom: zoom),
              let url = BasemapTiles.tileURL(source: source, x: coords.x, y: coords.y, z: zoom)
        else {
            completion(false)
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = BasemapProbe.hardTimeoutSeconds
        request.setValue("TrueSolarTime-iOS", forHTTPHeaderField: "User-Agent")

        session.dataTask(with: request) { data, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            var ok = (200..<300).contains(status) && BasemapTiles.looksLikeImage(data: data)
            if ok, source.isAmap, let data {
                // 高德的「有内容」= 非空白瓦片。
                if let analysis = BasemapTileSampler.blankAnalysis(data: data), analysis.isBlank {
                    ok = false
                }
            }
            completion(ok)
        }.resume()
    }

    private func recordProbe(_ session: ProbeSession, source: BasemapSource, zoom: Int, ok: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.probeSession === session, !session.done else { return }
            if source == .osm {
                session.osmReachable = ok
            } else {
                session.amapResults[zoom] = ok
            }
            session.pending -= 1
            if session.pending <= 0 {
                self.finishProbe(session)
            }
        }
    }

    /// 2 秒到点：只有「**不存在比当前最优精度更高、且还在飞**的档」时才收工（`BasemapProbe.shouldEarlyExit`）。
    ///
    /// 以前这里是「任意一档有内容就早退」，会把「z3 先回、z12 还在飞」判成结论 → 只能选到低精度。
    /// 现在更高的档只要还没结论（`amap[zoom] == nil`）就继续等，直到它回来（空白 / 失败也算有结论）。
    private func earlyExitIfAmapContent(_ session: ProbeSession) {
        guard probeSession === session, !session.done else { return }
        guard BasemapProbe.shouldEarlyExit(amap: session.amapResults) else { return }
        finishProbe(session)
    }

    /// 出结论：`decide` → 缓存 → 一步定级 → 发布（界面的地图在这之后才出生）。
    private func finishProbe(_ session: ProbeSession) {
        guard probeSession === session, !session.done else { return }
        session.done = true

        let decision = BasemapProbe.decide(osmReachable: session.osmReachable, amap: session.amapResults)
        saveProbe(BasemapProbeCache(
            key: session.key,
            source: decision.source,
            zoom: decision.zoom,
            decidedAt: Date().timeIntervalSince1970
        ))
        state.applyProbeDecision(
            source: decision.source,
            zoom: decision.zoom,
            at: Date().timeIntervalSince1970
        )
        publishIfChanged()
    }

    private func cachedProbe() -> BasemapProbeCache? {
        guard let key = defaults.string(forKey: CacheKey.key),
              let source = BasemapSource(rawValue: defaults.string(forKey: CacheKey.source) ?? "")
        else { return nil }
        let zoom = defaults.object(forKey: CacheKey.zoom) == nil ? nil : defaults.integer(forKey: CacheKey.zoom)
        return BasemapProbeCache(
            key: key,
            source: source,
            zoom: zoom,
            decidedAt: defaults.double(forKey: CacheKey.at)
        )
    }

    private func saveProbe(_ cache: BasemapProbeCache) {
        defaults.set(cache.key, forKey: CacheKey.key)
        defaults.set(cache.source.rawValue, forKey: CacheKey.source)
        if let zoom = cache.zoom {
            defaults.set(zoom, forKey: CacheKey.zoom)
        } else {
            defaults.removeObject(forKey: CacheKey.zoom)
        }
        defaults.set(cache.decidedAt, forKey: CacheKey.at)
    }

    // MARK: OSM 恢复探测（每 5 分钟）

    /// 每秒由 `AppModel` 的时钟调一次：到点就探测。
    func tick(now: Date = Date()) {
        guard state.shouldProbe(now: now.timeIntervalSince1970) else { return }
        guard !probeInFlight else { return }
        probeOSM()
    }

    private func probeOSM() {
        guard let place else { return }
        guard let coords = BasemapTiles.tile(latitude: place.latitude, longitude: place.longitude, zoom: BasemapState.worldZoom),
              let url = BasemapTiles.tileURL(source: .osm, x: coords.x, y: coords.y, z: BasemapState.worldZoom)
        else {
            state.probeFailed(at: Date().timeIntervalSince1970)
            publishIfChanged()
            return
        }

        probeInFlight = true
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("TrueSolarTime-iOS", forHTTPHeaderField: "User-Agent")

        session.dataTask(with: request) { [weak self] data, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let ok = (200..<300).contains(status) && BasemapTiles.looksLikeImage(data: data)
            DispatchQueue.main.async {
                guard let self else { return }
                self.probeInFlight = false
                if ok {
                    self.state.probeSucceeded(at: Date().timeIntervalSince1970)
                } else {
                    self.state.probeFailed(at: Date().timeIntervalSince1970)
                }
                self.publishIfChanged()
            }
        }.resume()
    }

    // MARK: 署名 / 诊断

    /// 署名：实际使用的瓦片源；自动模式回退过就追加一句「OSM 不可达，已回退高德」。
    var attribution: String {
        guard didFallBack else { return activeSource.attribution }
        return "\(activeSource.attribution) · \(L("map.fallbackNote"))"
    }

    private func statusText() -> String {
        switch state.status {
        case .live: return L("map.statusLive")
        case .probing: return L("map.statusProbing")
        case .unavailable: return L("map.statusUnavailable")
        }
    }

    /// 诊断第一行：实际源 · 状态 · 缩放（降级时带标记）。
    func diagnosticsSummary() -> String {
        let suffix = state.isDegraded ? L("map.degraded") : ""
        return Lf(
            "map.diagSummary",
            activeSource.label,
            statusText(),
            uiState.zoom ?? 0,
            suffix
        )
    }

    /// 诊断第二行：首选 · OSM 失败次数 · 空白判定次数 · 下次探测时间。
    func diagnosticsDetail() -> String {
        let probe: String
        if let next = state.nextProbeAt {
            let seconds = Int(max(next - Date().timeIntervalSince1970, 0).rounded(.up))
            probe = Lf("map.probeIn", seconds)
        } else {
            probe = L("common.none")
        }
        return Lf(
            "map.diagDetail",
            state.preferred.label,
            state.osmFailures,
            state.blankDetections,
            probe
        )
    }

    /// **只在有效 plan 变了才发布**（计数变化不发）。
    private func publishIfChanged() {
        let next = state.uiState(requestedZoom: lastRequestedZoom)
        guard next != uiState else { return }
        uiState = next
    }
}
