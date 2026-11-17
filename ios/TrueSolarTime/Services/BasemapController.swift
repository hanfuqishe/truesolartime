import Foundation
import UIKit

/// 地图底图的运行时：持有 `BasemapState`（纯逻辑在 Core），负责
///
/// - 按「样式 + 地点」建立 / 重建状态（自动 → 可回退；手动 → 一切兜底关掉）；
/// - 每块瓦片的加载结果喂回状态机（OSM 成败、高德空白）；
/// - 回退后每 5 分钟探测一次 OSM（z3 小瓦片 + 图片魔数校验），成功即切回；
/// - 给界面与诊断页提供一行行文字。
final class BasemapController: ObservableObject {

    static let shared = BasemapController()

    /// 状态变了就自增：`MapCard` 用它触发重建 overlay。
    @Published private(set) var revision = 0

    private(set) var state: BasemapState
    private var configuredStyle: MapStyle?
    private var configuredSiteKey: String?
    private var place: Place?

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
        state = BasemapState(mode: .manual, preferred: .osm, now: 0)
    }

    // MARK: 配置

    /// 样式或地点变了就重建状态机。
    ///
    /// - 位置只按 4 位小数比较（≈11 m）：GPS 抖动不该把「已回退」「已降级」重置掉；
    /// - 手动选底图 → `mode = .manual`（不回退、不探测、不降级）。
    func configure(style: MapStyle, place: Place, now: Date = Date()) {
        let siteKey = String(format: "%.4f,%.4f", place.latitude, place.longitude)
        guard style != configuredStyle || siteKey != configuredSiteKey else { return }
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
        bump()
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
        guard let zoom = state.effectiveZoom(requested: requestedZoom) else { return nil }
        return (state.active, zoom)
    }

    // MARK: 结果回灌

    func noteOSMTile(success: Bool, now: Date = Date()) {
        let before = state
        state.recordOSMTile(success: success, at: now.timeIntervalSince1970)
        if state != before { bump() }
    }

    func noteAmapTile(blank: Bool, now: Date = Date()) {
        let before = state
        state.recordAmapTile(blank: blank, at: now.timeIntervalSince1970)
        if state != before { bump() }
    }

    /// 每请求一块瓦片就调一次：1.2 秒没有新瓦片 = 这一屏画完了 → 判整屏空白。
    func scheduleScreenSettle() {
        settleWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let before = self.state
            self.state.closeScreenBatch(at: Date().timeIntervalSince1970)
            if self.state != before { self.bump() }
        }
        settleWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: item)
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
            bump()
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
                self.bump()
            }
        }.resume()
    }

    // MARK: 诊断 / 署名

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
    func diagnosticsSummary(requestedZoom: Int = 12) -> String {
        let zoom = state.effectiveZoom(requested: requestedZoom) ?? 0
        let suffix = state.isDegraded ? L("map.degraded") : ""
        return Lf(
            "map.diagSummary",
            activeSource.label,
            statusText(),
            zoom,
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

    private func bump() {
        revision &+= 1
    }
}
