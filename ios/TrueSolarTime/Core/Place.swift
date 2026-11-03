import Foundation

enum PlaceSource: String {
    case preset
    case gps
    case manual
}

struct Place: Equatable {
    var latitude: Double
    var longitude: Double
    var source: PlaceSource
    var label: String

    static let shanghai = Place(latitude: 31.2304, longitude: 121.4737, source: .preset, label: "上海")

    /// 常用城市，便于在无定位权限时快速切换。
    static let presets: [Place] = [
        Place(latitude: 39.9042, longitude: 116.4074, source: .manual, label: "北京"),
        Place(latitude: 31.2304, longitude: 121.4737, source: .manual, label: "上海"),
        Place(latitude: 23.1291, longitude: 113.2644, source: .manual, label: "广州"),
        Place(latitude: 22.5431, longitude: 114.0579, source: .manual, label: "深圳"),
        Place(latitude: 30.5728, longitude: 104.0668, source: .manual, label: "成都"),
        Place(latitude: 34.3416, longitude: 108.9398, source: .manual, label: "西安"),
        Place(latitude: 45.8038, longitude: 126.5350, source: .manual, label: "哈尔滨"),
        Place(latitude: 43.8256, longitude: 87.6168, source: .manual, label: "乌鲁木齐"),
        Place(latitude: 29.6520, longitude: 91.1721, source: .manual, label: "拉萨"),
        Place(latitude: 22.3193, longitude: 114.1694, source: .manual, label: "香港"),
    ]

    static let minLatitude = -90.0
    static let maxLatitude = 90.0
    static let minLongitude = -180.0
    static let maxLongitude = 180.0
}
