import MapKit
import SwiftUI

/// 内嵌地图：自动按地区选择底图源，并把 WGS-84 坐标换算到底图坐标系。
///
/// 四级兜底（与 Android 同策略，判定与状态机都在 Core）：
/// 1. 首选不变：境内高德、境外 OpenStreetMap；
/// 2. 只有「自动」模式会在 OSM 连续失败 3 次后回退到高德，之后直接用高德；
/// 3. 高德对境外常返回 **HTTP 200 的空白瓦片** → 整屏都空白就逐级降 z12 → z11 → z10 → z3 全球底图；
/// 4. 连 z3 都空白 → 地图区域显示「底图不可用」小字（不留空白），同时每 5 分钟探测一次 OSM。
struct MapCard: View {

    @Environment(\.palette) private var palette

    let place: Place
    let mapStyle: MapStyle
    /// 定位不可用（未知态）：z3 全球底图、不画标记、经纬度显示 `--`。
    let isLocationUnknown: Bool

    @ObservedObject private var basemap = BasemapController.shared

    /// 加载态是否已经显示（120ms 防闪：探测很快命中缓存时不该闪一下骨架）。
    @State private var skeletonVisible = false
    /// 6 秒兜底：探测万一卡住，也不能一直停在骨架 —— 到点就直接把地图建出来。
    @State private var forceShowMap = false

    private var resolvedStyle: MapStyle {
        // 带上国家码：境内/境外以国家码为准，没有国家码（GPS 刚定位）才退回包围盒。
        mapStyle.effective(
            countryCode: place.countryCode,
            latitude: place.latitude,
            longitude: place.longitude
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L("map.title"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.onSurfaceVariant)
                Spacer()
                Text(isLocationUnknown ? Placeholders.dash : TimeFormat.coordinates(latitude: place.latitude, longitude: place.longitude))
                    .font(.system(size: 12))
                    .foregroundStyle(palette.onSurfaceVariant)
            }

            ZStack {
                if showsMap {
                    // **地图按探测结论出生**：只有 `uiState.ready`（或 6 秒兜底）之后才创建 MKMapView。
                    // 先按默认源建好再切源会让 MapKit 取消在飞请求、旧缓存清掉后不重发 → 一直转圈。
                    MapViewRepresentable(place: place, style: resolvedStyle, plan: basemap.uiState, hidesMarker: isLocationUnknown)
                        .aspectRatio(4.0 / 3.0, contentMode: .fit)

                    if basemap.uiState.unavailable {
                        Text(L("map.unavailable"))
                            .font(.system(size: 12))
                            .foregroundStyle(palette.onSurfaceVariant)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(palette.surface.opacity(0.85), in: Capsule())
                    }
                } else if skeletonVisible {
                    skeleton
                }
            }
            .aspectRatio(4.0 / 3.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.top, 10)

            Text(attributionText)
                .font(.system(size: 12))
                .foregroundStyle(palette.onSurfaceVariant)
                .padding(.top, 8)
        }
        .foregroundStyle(palette.onSurface)
        .cardBackground()
        .onAppear { configure() }
        .onChange(of: place) { _ in configure() }
        .onChange(of: mapStyle) { _ in configure() }
        // **进入 / 退出未知态也要重新配置**：`place` 没变（旧的坐标还在），
        // 只靠 `.onChange(of: place)` 永远不会触发，地图就会停在上一个地点。
        .onChange(of: isLocationUnknown) { _ in configure() }
        .task(id: basemap.uiState.ready) { await runLoadingState() }
    }

    private var showsMap: Bool {
        basemap.uiState.ready || forceShowMap
    }

    /// 加载态：骨架 + 「正在载入底图…」。120ms 防闪、6 秒兜底收起。
    private var skeleton: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(palette.outlineVariant.opacity(0.25))
            VStack(spacing: 6) {
                ProgressView()
                Text(L("map.loading"))
                    .font(.system(size: 12))
                    .foregroundStyle(palette.onSurfaceVariant)
            }
        }
    }

    private func runLoadingState() async {
        forceShowMap = false
        skeletonVisible = false
        guard !basemap.uiState.ready else { return }

        // 120ms 内就出结论的话，骨架根本不出现（不闪）。
        try? await Task.sleep(nanoseconds: 120_000_000)
        guard !Task.isCancelled, !basemap.uiState.ready else { return }
        skeletonVisible = true

        // 6 秒兜底：探测卡住也不再等，直接把地图按当前结论建出来。
        try? await Task.sleep(nanoseconds: 6_000_000_000)
        guard !Task.isCancelled else { return }
        forceShowMap = true
    }

    private func configure() {
        BasemapController.shared.configure(style: mapStyle, place: place)
    }

    /// 署名跟随**实际使用的**瓦片源；自动模式回退过会追加「OSM 不可达，已回退高德」。
    private var attributionText: String {
        let suffix = L("map.autoNote")
        return mapStyle == .auto
            ? "\(basemap.attribution) · \(suffix)"
            : basemap.attribution
    }
}

// MARK: - MKMapView 包装

private struct MapViewRepresentable: UIViewRepresentable {

    let place: Place
    let style: MapStyle
    /// 有效 plan 快照（源 / 缩放 / 不可用）：**只有它变了才重建 overlay**。
    /// 计数（OSM 失败次数 / 空白判定次数）不在里面，所以不会因为「又失败一块瓦片」而重组地图。
    let plan: BasemapUiState
    /// 未知态：不画标记（只有全球底图）。
    ///
    /// 注意：**必须放在 `plan` 之后** —— memberwise init 的实参顺序要和声明顺序一致，
    /// 调用点是 `place:style:plan:hidesMarker:`（之前顺序写反，CI 直接编译不过）。
    let hidesMarker: Bool

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.isRotateEnabled = false
        mapView.isPitchEnabled = false
        mapView.pointOfInterestFilter = .excludingAll
        mapView.delegate = context.coordinator
        context.coordinator.attach(style: style, plan: plan, to: mapView)
        context.coordinator.applyViewportIfNeeded(to: place, style: style, on: mapView)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        if context.coordinator.currentStyle != style || context.coordinator.plan != plan {
            context.coordinator.attach(style: style, plan: plan, to: mapView)
        }
        // 视口只在**一个地方**、且只在「地点真的变了」时才动：
        // 每次状态发布都 `setRegion` 会把用户手动平移/缩放顶回去，也会和动画互相打断。
        context.coordinator.applyViewportIfNeeded(to: place, style: style, on: mapView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, MKMapViewDelegate {

        var currentStyle: MapStyle?
        var plan: BasemapUiState?
        private var tileOverlay: BasemapTileOverlay?
        private var annotation: MKPointAnnotation?
        /// 正在程序化改视口（`setRegion`）。`regionDidChangeAnimated` 里用它区分「我们改的」与「用户手势」。
        private var isApplyingProgrammaticRegion = false
        /// 上一次真正应用过的视口：WGS-84 坐标 + 底图样式 + 实际画到地图上的坐标（已按底图换算）。
        /// 只在「地点 / 样式」变化时才动地图；重建 overlay 时用它把标记放回原位。
        private var appliedViewport: (
            latitude: Double,
            longitude: Double,
            style: MapStyle,
            mapCoordinate: CLLocationCoordinate2D,
            label: String
        )?
        private let viewportSpanMeters: CLLocationDistance = 12_000

        func attach(style: MapStyle, plan: BasemapUiState, to mapView: MKMapView) {
            if let existing = tileOverlay {
                mapView.removeOverlay(existing)
            }
            mapView.removeAnnotations(mapView.annotations)

            // 瓦片URL由 `BasemapTileOverlay.loadTile` 自己算（要按兜底状态换源 / 换缩放）。
            let overlay = BasemapTileOverlay()
            overlay.canReplaceMapContent = true
            overlay.minimumZ = BasemapState.worldZoom
            overlay.maximumZ = style.maximumZ
            mapView.addOverlay(overlay, level: .aboveLabels)

            let point = MKPointAnnotation()
            // 重建 overlay 不代表地点变了：把标记放回上次的坐标，别让它留在 (0,0)。
            if let viewport = appliedViewport {
                point.coordinate = viewport.mapCoordinate
                point.title = viewport.label
            }
            mapView.addAnnotation(point)

            tileOverlay = overlay
            annotation = point
            currentStyle = style
            self.plan = plan
        }

        /// 未知态：**z3 全球底图**（跨约 90°×120°）。不画标记、也不跟随地点。
        static let unknownRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 20, longitude: 0),
            span: MKCoordinateSpan(latitudeDelta: 90, longitudeDelta: 120)
        )

        /// 未知态视口是否已经落过（避免每次状态发布都 setRegion）。
        private var appliedUnknownViewport = false

        /// 视口入口（**唯一**）：未知态 → 全球 z3；正常态 → 按地点落一次。
        ///
        /// 进入未知态时把 `appliedViewport` 清空，退出时才能按当前地点重新落一次；
        /// 标记的显隐由 `hidesMarker` 在 `attach` 里处理。
        func updateViewport(isUnknown: Bool, place: Place, style: MapStyle, on mapView: MKMapView) {
            if isUnknown {
                guard !appliedUnknownViewport else { return }
                appliedUnknownViewport = true
                appliedViewport = nil
                BasemapController.shared.noteViewportChanged()
                mapView.setRegion(Self.unknownRegion, animated: false)
                return
            }
            appliedUnknownViewport = false
            applyViewportIfNeeded(to: place, style: style, on: mapView)
        }

        /// 正常态：一次 `setRegion` 同时给 center + span（只在「地点 / 样式」变化时动）。
        ///
        /// 不做「先 setCenter 再 setZoom」、也不在别处单独改 span —— 两次动画会互相打断
        /// （安卓那边就是这样停在半路、标记不居中的）。地点没变就直接返回，因此
        /// 底图状态变化（回退 / 降级）不会把用户的平移缩放顶回去。
        func applyViewportIfNeeded(to place: Place, style: MapStyle, on mapView: MKMapView) {
            let last = appliedViewport
            let sameSpot = last.map {
                abs($0.latitude - place.latitude) < 1e-6
                    && abs($0.longitude - place.longitude) < 1e-6
                    && $0.style == style
            } ?? false
            guard !sameSpot else { return }

            let converted = MapCoordinates.toMapCoordinates(
                style: style,
                latitude: place.latitude,
                longitude: place.longitude
            )
            let coordinate = CLLocationCoordinate2D(latitude: converted.latitude, longitude: converted.longitude)

            annotation?.coordinate = coordinate
            annotation?.title = place.displayLabel

            // 程序化改视口会取消在飞的瓦片请求：接下来 2 秒内回来的失败一律不计。
            BasemapController.shared.noteViewportChanged()

            let region = MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: viewportSpanMeters,
                longitudinalMeters: viewportSpanMeters
            )
            mapView.setRegion(region, animated: false)
            appliedViewport = (place.latitude, place.longitude, style, coordinate, place.displayLabel)
        }

        /// 视口变化回调：**程序化** `setRegion` 会在里面被过滤掉；剩下的都是用户手势
        /// （拖动 / 捏合 / 双击缩放，含惯性），用于冻结底图升级。
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            if isApplyingProgrammaticRegion {
                isApplyingProgrammaticRegion = false
                return
            }
            BasemapController.shared.userDidInteractWithMap()
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tile = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(tileOverlay: tile)
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}

// MARK: - 自定义瓦片加载（四级兜底在这里落地）

/// 一块瓦片的错误：MapKit 收到错误就不画那块（空白 / 失败的瓦片不会留下半张图）。
private enum BasemapTileError: Error {
    case unavailable
    case failed
    case blank
}

/// 按 `BasemapController` 的计划加载瓦片：
/// - 源与缩放由 Core 状态机给（降级时取父瓦片，靠 MapKit 放大绘制）；
/// - **高德瓦片要做像素判定**：空白就当失败，累计到「整屏空白」后触发降级；
/// - OSM 的成功 / 失败喂回状态机（连续 3 次失败回退）。
private final class BasemapTileOverlay: MKTileOverlay {

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 16
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    init() {
        super.init(urlTemplate: nil)
    }

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        let controller = BasemapController.shared
        // 这一屏的瓦片都请求完了就判「整屏空白」。
        controller.scheduleScreenSettle()

        guard let plan = controller.plan(requestedZoom: path.z),
              let coords = BasemapTiles.parentTile(x: path.x, y: path.y, from: path.z, to: plan.zoom),
              let url = BasemapTiles.tileURL(source: plan.source, x: coords.x, y: coords.y, z: plan.zoom)
        else {
            result(nil, BasemapTileError.unavailable)
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("TrueSolarTime-iOS", forHTTPHeaderField: "User-Agent")

        session.dataTask(with: request) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let ok = error == nil
                && (200..<300).contains(status)
                && BasemapTiles.looksLikeImage(data: data)

            guard ok, let data else {
                if plan.source == .osm {
                    controller.noteOSMTile(success: false)
                }
                result(nil, BasemapTileError.failed)
                return
            }

            if plan.source.isAmap {
                // 高德的空白瓦片是 200 + 灰底水印：像素判定为空白就按失败处理。
                if let analysis = BasemapTileSampler.blankAnalysis(data: data), analysis.isBlank {
                    controller.noteAmapTile(blank: true)
                    result(nil, BasemapTileError.blank)
                    return
                }
                controller.noteAmapTile(blank: false)
            } else {
                controller.noteOSMTile(success: true)
            }
            result(data, nil)
        }.resume()
    }
}
