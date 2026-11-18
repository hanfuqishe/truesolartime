import Foundation

/// 设置页「诊断」里那一行**地图自证信息**：用户截图就能判断到底是
/// 「视口没动」（中心/跨度不对）还是「标记没清」（标记数不对）。
///
/// 取值来源：
/// - `isUnknown` / `source` / `zoom`：来自 `BasemapController` 的有效 plan（Core 状态机）；
/// - `centerLatitude/Longitude`、`latitudeDelta/longitudeDelta`、`markerCount`：来自 `MKMapView`
///   的运行时实际值（`Coordinator` 每次视口变化后回灌）。
struct BasemapMapDebug: Equatable {

    let isUnknown: Bool
    let centerLatitude: Double
    let centerLongitude: Double
    let latitudeDelta: Double
    let longitudeDelta: Double
    let zoom: Int
    let markerCount: Int
    let source: BasemapSource

    /// 未知态的默认值（中心 20°/0°、跨度 90°×120°、z3、无标记）：
    ///
    /// `configureUnknown()` 之后**立刻**用它回灌一次，不必等地图回调 ——
    /// 否则诊断行会一直停在「尚未回灌」。
    static func unknownDefault(source: BasemapSource, zoom: Int) -> BasemapMapDebug {
        BasemapMapDebug(
            isUnknown: true,
            centerLatitude: 20,
            centerLongitude: 0,
            latitudeDelta: 90,
            longitudeDelta: 120,
            zoom: zoom,
            markerCount: 0,
            source: source
        )
    }
    /// 一行文字：`未知态 · 中心 20.0,0.0 · 跨度 90×120 · 缩放 3 · 标记 0 个 · 源 OSM`
    var text: String {
        let mode = isUnknown ? "未知态" : "正常态"
        let center = String(format: "%.1f,%.1f", centerLatitude, centerLongitude)
        let span = String(format: "%.0f×%.0f", latitudeDelta, longitudeDelta)
        // 未知态用的是**系统底图**（Apple），不是我们探测出来的源。
        let sourceText = isUnknown ? "Apple（系统底图）" : source.label
        return "\(mode) · 中心 \(center) · 跨度 \(span) · 缩放 \(zoom) · 标记 \(markerCount) 个 · 源 \(sourceText)"
    }
}
