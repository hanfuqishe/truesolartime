import Foundation

/// WGS-84 与 GCJ-02（火星坐标）互转。
///
/// 高德等国内底图使用 GCJ-02，而 GPS 与真太阳时计算必须使用 WGS-84，
/// 因此只在绘制地图这一层做转换。
enum CoordinateTransform {

    private static let pi = Double.pi
    private static let axis = 6378245.0
    private static let eccentricity = 0.00669342162296594323

    /// GCJ-02 的适用边界，境外不加偏移。
    ///
    /// 注意：这是**坐标系**的边界（72–137.8°E / 0.83–55.8°N，比行政区划大一圈），
    /// 不是「是不是中国境内」的判据 —— 印度、尼泊尔、东南亚都在里面。
    /// 「是不是境内」一律看 `GeoRegion.isInChina`（国家码优先），选底图也用它。
    static func isInChina(latitude: Double, longitude: Double) -> Bool {
        longitude >= 72.004 && longitude <= 137.8347 && latitude >= 0.8293 && latitude <= 55.8271
    }

    static func wgs84ToGcj02(latitude: Double, longitude: Double) -> (latitude: Double, longitude: Double) {
        guard isInChina(latitude: latitude, longitude: longitude) else {
            return (latitude, longitude)
        }

        var deltaLat = transformLatitude(longitude - 105.0, latitude - 35.0)
        var deltaLon = transformLongitude(longitude - 105.0, latitude - 35.0)

        let radLat = latitude / 180.0 * pi
        let sinLat = sin(radLat)
        let magic = 1 - eccentricity * sinLat * sinLat
        let sqrtMagic = sqrt(magic)
        deltaLat = deltaLat * 180.0 / (axis * (1 - eccentricity) / (magic * sqrtMagic) * pi)
        deltaLon = deltaLon * 180.0 / (axis / sqrtMagic * cos(radLat) * pi)

        return (latitude + deltaLat, longitude + deltaLon)
    }

    /// 迭代逼近求逆，往返误差可忽略。
    static func gcj02ToWgs84(latitude: Double, longitude: Double) -> (latitude: Double, longitude: Double) {
        guard isInChina(latitude: latitude, longitude: longitude) else {
            return (latitude, longitude)
        }

        var guessLat = latitude
        var guessLon = longitude
        for _ in 0..<6 {
            let converted = wgs84ToGcj02(latitude: guessLat, longitude: guessLon)
            guessLat += latitude - converted.latitude
            guessLon += longitude - converted.longitude
        }
        return (guessLat, guessLon)
    }

    private static func transformLatitude(_ x: Double, _ y: Double) -> Double {
        var result = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(abs(x))
        result += (20.0 * sin(6.0 * x * pi) + 20.0 * sin(2.0 * x * pi)) * 2.0 / 3.0
        result += (20.0 * sin(y * pi) + 40.0 * sin(y / 3.0 * pi)) * 2.0 / 3.0
        result += (160.0 * sin(y / 12.0 * pi) + 320.0 * sin(y * pi / 30.0)) * 2.0 / 3.0
        return result
    }

    private static func transformLongitude(_ x: Double, _ y: Double) -> Double {
        var result = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(abs(x))
        result += (20.0 * sin(6.0 * x * pi) + 20.0 * sin(2.0 * x * pi)) * 2.0 / 3.0
        result += (20.0 * sin(x * pi) + 40.0 * sin(x / 3.0 * pi)) * 2.0 / 3.0
        result += (150.0 * sin(x / 12.0 * pi) + 300.0 * sin(x / 30.0 * pi)) * 2.0 / 3.0
        return result
    }
}

/// 底图选择：境内用高德（中文地名、路网更细），境外用 OpenStreetMap。
enum MapStyle: String, CaseIterable, Identifiable {
    case auto
    /// **iOS 的「自动」= Apple 地图**（MapKit 系统底图：不挂 overlay、不探测、不回退、不降级）。
    case apple
    case osm
    case amapVector
    case amapSatellite

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return L("map.styleAuto")
        case .apple: return L("map.styleApple")
        case .osm: return L("map.styleOsm")
        case .amapVector: return L("map.styleAmapVector")
        case .amapSatellite: return L("map.styleAmapSatellite")
        }
    }

    /// 自动选图：境内高德，境外 OpenStreetMap。
    ///
    /// 「境内」用 `GeoRegion.isInChina`：**有国家码以国家码为准**，没有才退回包围盒。
    /// 之前直接用 GCJ-02 的矩形判断，新德里（77.2°E, 28.6°N）会被当成境内而去拉高德的
    /// 瓦片 —— 境外没有高德数据，标点还会被 GCJ-02 偏移推歪。
    ///
    /// - Parameter countryCode: 观测点的 ISO 3166-1 alpha-2；未知传 nil。
    /// 「自动」在 iOS 上**恒为 Apple 地图**（MapKit 系统底图）。
    ///
    /// 曾经按国家码选高德 / OSM，结果为了空白瓦片、回退、降级、停在旧地点修了近十轮。
    /// Apple 底图走系统通道：大陆可出图（中国区数据本身就是高德）、无需 key、
    /// 坐标系由系统处理，是零风险路径。OSM / 高德三个**手动**选项仍然保留。
    func effective(countryCode: String? = nil, latitude: Double, longitude: Double) -> MapStyle {
        _ = (countryCode, latitude, longitude, GeoRegion.self)
        return self == .auto ? .apple : self
    }

    var isGcj02: Bool { self == .amapVector || self == .amapSatellite }

    /// 是不是 Apple 系统底图（不挂 overlay、不探测，`MKMapView` 默认瓦片）。
    var isSystemBasemap: Bool { self == .apple || self == .auto }

    /// 设置页里给用户选的四个选项：自动（Apple）/ OSM / 高德矢量 / 高德卫星。
    /// `.apple` 是 `.auto` 的解析结果，不作为独立选项展示。
    static let selectable: [MapStyle] = [.auto, .apple, .osm, .amapVector, .amapSatellite]

    var attribution: String {
        switch self {
        case .osm: return L("map.attributionOsm")
        case .amapVector, .amapSatellite: return L("map.attributionAmap")
        case .apple, .auto: return L("map.appleBasemap")
        }
    }

    /// MKTileOverlay 的 URL 模板。高德的栅格瓦片无需 API Key。
    /// **Apple 底图没有模板**（不挂 overlay），返回空串。
    var tileURLTemplate: String {
        switch self {
        case .osm:
            return "https://tile.openstreetmap.org/{z}/{x}/{y}.png"
        case .amapVector:
            return "https://webrd01.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=8&x={x}&y={y}&z={z}"
        case .amapSatellite:
            return "https://webst01.is.autonavi.com/appmaptile?style=6&size=1&scale=1&x={x}&y={y}&z={z}"
        case .apple, .auto:
            return ""
        }
    }

    var maximumZ: Int { self == .osm || self == .auto ? 19 : 18 }
}

enum MapCoordinates {
    /// 数据层的 WGS-84 坐标 → 该底图所用的坐标系。
    static func toMapCoordinates(style: MapStyle, latitude: Double, longitude: Double) -> (latitude: Double, longitude: Double) {
        guard style.isGcj02 else { return (latitude, longitude) }
        return CoordinateTransform.wgs84ToGcj02(latitude: latitude, longitude: longitude)
    }
}
