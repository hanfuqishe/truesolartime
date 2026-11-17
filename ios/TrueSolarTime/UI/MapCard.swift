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

    @ObservedObject private var basemap = BasemapController.shared

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
                Text(TimeFormat.coordinates(latitude: place.latitude, longitude: place.longitude))
                    .font(.system(size: 12))
                    .foregroundStyle(palette.onSurfaceVariant)
            }

            ZStack {
                MapViewRepresentable(place: place, style: resolvedStyle, revision: basemap.revision)
                    .aspectRatio(4.0 / 3.0, contentMode: .fit)

                // 连 z3 全球底图都空白：原地显示一行小字，不要空着。
                if basemap.isUnavailable {
                    Text(L("map.unavailable"))
                        .font(.system(size: 12))
                        .foregroundStyle(palette.onSurfaceVariant)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(palette.surface.opacity(0.85), in: Capsule())
                }
            }
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
    /// 底图状态版本号：源 / 缩放变了就重建 overlay（MapKit 会丢掉旧的瓦片缓存）。
    let revision: Int

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.isRotateEnabled = false
        mapView.isPitchEnabled = false
        mapView.pointOfInterestFilter = .excludingAll
        mapView.delegate = context.coordinator
        context.coordinator.attach(style: style, revision: revision, to: mapView)
        context.coordinator.move(to: place, style: style, on: mapView, animated: false)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        if context.coordinator.currentStyle != style || context.coordinator.revision != revision {
            context.coordinator.attach(style: style, revision: revision, to: mapView)
        }
        context.coordinator.move(to: place, style: style, on: mapView, animated: true)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, MKMapViewDelegate {

        var currentStyle: MapStyle?
        var revision = -1
        private var tileOverlay: BasemapTileOverlay?
        private var annotation: MKPointAnnotation?

        func attach(style: MapStyle, revision: Int, to mapView: MKMapView) {
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
            mapView.addAnnotation(point)

            tileOverlay = overlay
            annotation = point
            currentStyle = style
            self.revision = revision
        }

        func move(to place: Place, style: MapStyle, on mapView: MKMapView, animated: Bool) {
            let converted = MapCoordinates.toMapCoordinates(
                style: style,
                latitude: place.latitude,
                longitude: place.longitude
            )
            let coordinate = CLLocationCoordinate2D(latitude: converted.latitude, longitude: converted.longitude)

            annotation?.coordinate = coordinate
            annotation?.title = place.displayLabel

            let region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 12_000, longitudinalMeters: 12_000)
            mapView.setRegion(region, animated: animated)
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

/// 瓦片解码 + 32×32 采样（步长 8、最近邻），交给 Core 的 `BlankTileAnalysis` 判定。
private enum BasemapTileSampler {

    static let side = BlankTileAnalysis.sampleSide

    static func blankAnalysis(data: Data) -> BlankTileAnalysis? {
        guard let image = UIImage(data: data)?.cgImage else { return nil }
        return analyze(image: image)
    }

    private static func analyze(image: CGImage) -> BlankTileAnalysis? {
        let dimension = side
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              // 让 CoreGraphics 自己分配缓冲区（`data: nil`）：指针归 context 所有，
              // 比把 Swift 数组的指针借出去再在外面用要安全。
              let context = CGContext(
                data: nil,
                width: dimension,
                height: dimension,
                bitsPerComponent: 8,
                bytesPerRow: dimension * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }

        // 最近邻：不要插值 —— 与 Android 的「256×256 步长 8 取点」等价。
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: dimension, height: dimension))

        guard let base = context.data else { return nil }
        let buffer = base.bindMemory(to: UInt8.self, capacity: dimension * dimension * 4)

        let count = dimension * dimension
        var reds = [UInt8](repeating: 0, count: count)
        var greens = [UInt8](repeating: 0, count: count)
        var blues = [UInt8](repeating: 0, count: count)
        for index in 0..<count {
            reds[index] = buffer[index * 4]
            greens[index] = buffer[index * 4 + 1]
            blues[index] = buffer[index * 4 + 2]
        }
        return BlankTileAnalysis.analyze(reds: reds, greens: greens, blues: blues)
    }
}
