import Foundation

/// 地图视图的**身份**（SwiftUI `.id`）：纯函数、可断言。
///
/// 为什么要有它：`.id` 变了 SwiftUI 才会销毁旧 `MKMapView` 并新建 ——
/// 换底图样式、换地点、未知态切换都必须改变身份，否则地图会「看起来没反应」
/// （build 77 的问题：切换底图后首页地图不更新）。
enum MapViewIdentity {

    /// 地点指纹：4 位小数（≈11 m），GPS 抖动不会导致重建。
    static func placeKey(latitude: Double, longitude: Double) -> String {
        String(format: "%.4f,%.4f", latitude, longitude)
    }

    /// Apple（自动 / 手动 Apple）路径：**只含地点 + 样式**，不含源与缩放（Apple 没有这些概念）。
    static func apple(place: Place, style: MapStyle) -> String {
        "apple|\(placeKey(latitude: place.latitude, longitude: place.longitude))|\(style.rawValue)"
    }

    /// 手动 OSM / 高德路径：地点 + 样式 + 实际源 + 实际缩放（换源 / 降级也要重建，避免旧瓦片残留）。
    static func manual(place: Place, style: MapStyle, source: BasemapSource, zoom: Int?) -> String {
        let sourceKey = source.rawValue
        let zoomKey = zoom.map(String.init) ?? "-"
        return "manual|\(placeKey(latitude: place.latitude, longitude: place.longitude))|\(style.rawValue)|\(sourceKey)|\(zoomKey)"
    }

    /// 未知态（纯 Apple 世界地图）：与地点无关，固定一个身份。
    static let unknown = "unknown-world-map"

    /// 当前该用哪个身份。
    static func current(
        isLocationUnknown: Bool,
        place: Place,
        style: MapStyle,
        source: BasemapSource,
        zoom: Int?
    ) -> String {
        if isLocationUnknown { return unknown }
        if style.isSystemBasemap { return apple(place: place, style: style) }
        return manual(place: place, style: style, source: source, zoom: zoom)
    }
}
