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
    case osm
    case amapVector
    case amapSatellite

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "自动"
        case .osm: return "OpenStreetMap"
        case .amapVector: return "高德矢量"
        case .amapSatellite: return "高德卫星"
        }
    }

    func effective(latitude: Double, longitude: Double) -> MapStyle {
        guard self == .auto else { return self }
        return CoordinateTransform.isInChina(latitude: latitude, longitude: longitude) ? .amapVector : .osm
    }

    var isGcj02: Bool { self == .amapVector || self == .amapSatellite }

    var attribution: String {
        switch self {
        case .osm: return "地图数据 © OpenStreetMap 贡献者"
        case .amapVector, .amapSatellite: return "底图 © 高德地图"
        case .auto: return ""
        }
    }

    /// MKTileOverlay 的 URL 模板。高德的栅格瓦片无需 API Key。
    var tileURLTemplate: String {
        switch self {
        case .osm, .auto:
            return "https://tile.openstreetmap.org/{z}/{x}/{y}.png"
        case .amapVector:
            return "https://webrd01.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=8&x={x}&y={y}&z={z}"
        case .amapSatellite:
            return "https://webst01.is.autonavi.com/appmaptile?style=6&size=1&scale=1&x={x}&y={y}&z={z}"
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
