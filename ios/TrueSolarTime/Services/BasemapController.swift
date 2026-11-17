import Foundation
import UIKit

/// 地图底图的运行时：持有 `BasemapState`（纯逻辑在 Core），负责
///
/// - 按「样式 + 地点」建立 / 重建状态（自动 → 可回退；手动 → 一切兜底关掉）；
/// - 每块瓦片的加载结果喂回状态机（OSM 成败、高德空白）；
/// - 回退后每 5 分钟探测一次 OSM（z3 小瓦片 + 图片魔数校验），成功即切回；
/// - **只把「有效 plan 快照」（`BasemapUiState`）发布给界面**：计数变化不发通知，
///   所以不会出现安卓那种「2 秒 441 次状态发布 + 缩放来回弹 → 狂闪」；
/// - 给界面与诊断页提供一行行文字。
final class BasemapController: ObservableObject {

    static let shared = BasemapController()

    /// 界面**唯一**订阅的东西：有效 plan 的快照。等值时不赋值，SwiftUI 就不会重组。
    @Published private(set) var uiState: BasemapUiState

    private(set) var state: BasemapState
    private var configuredStyle: MapStyle?
    private var configuredSiteKey: String?
    private var place: Place?
    /// 最近一次 MapKit 请求的缩放（不算「计数」，但也只有它变化才需要重算快照）。
    private var lastRequestedZoom = 12

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
        publishIfChanged()
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
        // 静默期只影响内部计数，不改变有效 plan，故不发布。
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

    /// **只在有效 plan 变了才发布**。计数（OSM 失败次数 / 空白判定次数 / 内部屏幕计数）变化时
    /// 这里什么都不做 —— 界面不会因为「又失败了一块瓦片」而整块重组。
    private func publishIfChanged() {
        let next = state.uiState(requestedZoom: lastRequestedZoom)
        guard next != uiState else { return }
        uiState = next
    }
}
