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
    /// 逆地理编码得到的 ISO 3166-1 alpha-2（小写），例如 "cn" / "us"；未知为 nil。
    var countryCode: String?

    /// 观测地的法定标准时区偏移（秒）。查不到国家时按经度每 15° 近似。
    var standardOffsetSeconds: Int {
        SolarTimeMath.standardZoneOffsetSeconds(countryCode: countryCode, longitude: longitude)
    }

    static let shanghai = Place(latitude: 31.2304, longitude: 121.4737, source: .preset, label: "上海", countryCode: "cn")

    /// 常用城市，便于在无定位权限时快速切换。
    ///
    /// 每个城市都带 `countryCode`：标准时区直接由 `ZoneTable` 查表得到，
    /// 不必等逆地理编码回来（否则乌鲁木齐这种西边城市会被按经度近似算成 +6）。
    /// 后面几个是境外城市，用于验证「切到境外后标准时间、UTC 标签、日出日落是否正常」。
    static let presets: [Place] = [
        Place(latitude: 39.9042, longitude: 116.4074, source: .manual, label: "北京", countryCode: "cn"),
        Place(latitude: 31.2304, longitude: 121.4737, source: .manual, label: "上海", countryCode: "cn"),
        Place(latitude: 23.1291, longitude: 113.2644, source: .manual, label: "广州", countryCode: "cn"),
        Place(latitude: 22.5431, longitude: 114.0579, source: .manual, label: "深圳", countryCode: "cn"),
        Place(latitude: 30.5728, longitude: 104.0668, source: .manual, label: "成都", countryCode: "cn"),
        Place(latitude: 34.3416, longitude: 108.9398, source: .manual, label: "西安", countryCode: "cn"),
        Place(latitude: 45.8038, longitude: 126.5350, source: .manual, label: "哈尔滨", countryCode: "cn"),
        Place(latitude: 43.8256, longitude: 87.6168, source: .manual, label: "乌鲁木齐", countryCode: "cn"),
        Place(latitude: 29.6520, longitude: 91.1721, source: .manual, label: "拉萨", countryCode: "cn"),
        Place(latitude: 22.3193, longitude: 114.1694, source: .manual, label: "香港", countryCode: "hk"),
        // 境外（按 UTC 偏移从西到东）
        Place(latitude: 21.3069, longitude: -157.8583, source: .manual, label: "檀香山", countryCode: "us"),
        Place(latitude: 34.0522, longitude: -118.2437, source: .manual, label: "洛杉矶", countryCode: "us"),
        Place(latitude: 40.7128, longitude: -74.0060, source: .manual, label: "纽约", countryCode: "us"),
        Place(latitude: 51.5074, longitude: -0.1278, source: .manual, label: "伦敦", countryCode: "gb"),
        Place(latitude: 48.8566, longitude: 2.3522, source: .manual, label: "巴黎", countryCode: "fr"),
        Place(latitude: 25.2048, longitude: 55.2708, source: .manual, label: "迪拜", countryCode: "ae"),
        Place(latitude: 28.6139, longitude: 77.2090, source: .manual, label: "新德里", countryCode: "in"),
        Place(latitude: 35.6762, longitude: 139.6503, source: .manual, label: "东京", countryCode: "jp"),
        Place(latitude: 1.3521, longitude: 103.8198, source: .manual, label: "新加坡", countryCode: "sg"),
        Place(latitude: -33.8688, longitude: 151.2093, source: .manual, label: "悉尼", countryCode: "au"),
    ]

    static let minLatitude = -90.0
    static let maxLatitude = 90.0
    static let minLongitude = -180.0
    static let maxLongitude = 180.0
}
