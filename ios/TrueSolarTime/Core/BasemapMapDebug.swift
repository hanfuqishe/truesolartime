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

    /// 一行文字：`未知态 · 中心 20.0,0.0 · 跨度 90×120 · 缩放 3 · 标记 0 个 · 源 OSM`
    var text: String {
        let mode = isUnknown ? "未知态" : "正常态"
        let center = String(format: "%.1f,%.1f", centerLatitude, centerLongitude)
        let span = String(format: "%.0f×%.0f", latitudeDelta, longitudeDelta)
        return "\(mode) · 中心 \(center) · 跨度 \(span) · 缩放 \(zoom) · 标记 \(markerCount) 个 · 源 \(source.label)"
    }
}
