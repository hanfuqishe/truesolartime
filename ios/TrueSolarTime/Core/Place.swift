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
    /// 手工坐标 / GPS 的显示标签（例如「GPS · 精度 12 米」）。预设城市用 `presetKey`，
    /// 这里留空串，靠 `displayLabel` 取本地化名字。
    var label: String
    /// 预设城市名的本地化 key（例如 "city.beijing"）；手工坐标 / GPS 为 nil。
    var presetKey: String? = nil
    /// 逆地理编码得到的 ISO 3166-1 alpha-2（小写），例如 "cn" / "us"；未知为 nil。
    var countryCode: String? = nil

    /// 这个地点算不算中国境内（含港澳台）：国家码优先，没有国家码才退回经纬度包围盒。
    /// 见 `GeoRegion`。
    var isInChina: Bool {
        GeoRegion.isInChina(countryCode: countryCode, latitude: latitude, longitude: longitude)
    }

    /// 观测地的法定标准时区偏移（秒）。
    ///
    /// 有国家码按国家码查表；没有国家码时境内恒为 +8、境外按经度每 15° 近似。
    var standardOffsetSeconds: Int {
        SolarTimeMath.standardZoneOffsetSeconds(
            countryCode: countryCode,
            latitude: latitude,
            longitude: longitude
        )
    }

    /// 显示用名字：预设城市走本地化表（北京 / 北京 / Beijing），手工与 GPS 用原样 label。
    var displayLabel: String {
        if let presetKey { return L(presetKey) }
        if !label.isEmpty { return label }
        // 老数据（从旧版本升上来的，只存了坐标/旧中文名）：按坐标认回预设城市。
        return presetLabel ?? ""
    }

    /// 预设城市名：只有从「常用城市」里点选的城市才有名字可用，手工坐标 / GPS 一律没有。
    ///
    /// 与 Android 的 `place.labelResName != nil` 是同一个判定：手工输入的 `label` 是「手动设置」、
    /// GPS 的是「GPS · 精度 12 米」，都是占位词，不能当城市名显示在卡片上（那种情况显示「-」）。
    ///
    /// 老版本把城市名直接存成中文标签（`label` 有值、`presetKey` 为空），这里按坐标兜底识别，
    /// 免得升级后预设城市突然变成「-」。
    var presetLabel: String? {
        if let presetKey { return L(presetKey) }
        if source == .preset { return label.isEmpty ? nil : label }
        guard source != .gps else { return nil }
        let match = Place.presets.first {
            abs($0.latitude - latitude) < 1e-6 && abs($0.longitude - longitude) < 1e-6
        }
        return match?.displayLabel
    }

    static let shanghai = Place(
        latitude: 31.2304,
        longitude: 121.4737,
        source: .preset,
        label: "",
        presetKey: "city.shanghai",
        countryCode: "cn"
    )

    /// 常用城市，便于在无定位权限时快速切换。
    ///
    /// 每个城市都带 `countryCode`：标准时区直接由 `ZoneTable` 查表得到，
    /// 不必等逆地理编码回来（否则乌鲁木齐这种西边城市会被按经度近似算成 +6）。
    /// 城市名走 `city.*` 这组本地化 key，三语各一份。
    static let presets: [Place] = [
        Place(latitude: 39.9042, longitude: 116.4074, source: .manual, label: "", presetKey: "city.beijing", countryCode: "cn"),
        Place(latitude: 31.2304, longitude: 121.4737, source: .manual, label: "", presetKey: "city.shanghai", countryCode: "cn"),
        Place(latitude: 23.1291, longitude: 113.2644, source: .manual, label: "", presetKey: "city.guangzhou", countryCode: "cn"),
        Place(latitude: 22.5431, longitude: 114.0579, source: .manual, label: "", presetKey: "city.shenzhen", countryCode: "cn"),
        Place(latitude: 30.5728, longitude: 104.0668, source: .manual, label: "", presetKey: "city.chengdu", countryCode: "cn"),
        Place(latitude: 34.3416, longitude: 108.9398, source: .manual, label: "", presetKey: "city.xian", countryCode: "cn"),
        Place(latitude: 45.8038, longitude: 126.5350, source: .manual, label: "", presetKey: "city.harbin", countryCode: "cn"),
        Place(latitude: 43.8256, longitude: 87.6168, source: .manual, label: "", presetKey: "city.urumqi", countryCode: "cn"),
        Place(latitude: 29.6520, longitude: 91.1721, source: .manual, label: "", presetKey: "city.lhasa", countryCode: "cn"),
        Place(latitude: 22.3193, longitude: 114.1694, source: .manual, label: "", presetKey: "city.hongkong", countryCode: "hk"),
        // 境外（按 UTC 偏移从西到东）
        Place(latitude: 21.3069, longitude: -157.8583, source: .manual, label: "", presetKey: "city.honolulu", countryCode: "us"),
        Place(latitude: 34.0522, longitude: -118.2437, source: .manual, label: "", presetKey: "city.losangeles", countryCode: "us"),
        Place(latitude: 40.7128, longitude: -74.0060, source: .manual, label: "", presetKey: "city.newyork", countryCode: "us"),
        Place(latitude: 51.5074, longitude: -0.1278, source: .manual, label: "", presetKey: "city.london", countryCode: "gb"),
        Place(latitude: 48.8566, longitude: 2.3522, source: .manual, label: "", presetKey: "city.paris", countryCode: "fr"),
        Place(latitude: 25.2048, longitude: 55.2708, source: .manual, label: "", presetKey: "city.dubai", countryCode: "ae"),
        Place(latitude: 28.6139, longitude: 77.2090, source: .manual, label: "", presetKey: "city.newdelhi", countryCode: "in"),
        Place(latitude: 35.6762, longitude: 139.6503, source: .manual, label: "", presetKey: "city.tokyo", countryCode: "jp"),
        Place(latitude: 1.3521, longitude: 103.8198, source: .manual, label: "", presetKey: "city.singapore", countryCode: "sg"),
        Place(latitude: -33.8688, longitude: 151.2093, source: .manual, label: "", presetKey: "city.sydney", countryCode: "au"),
        // 北极圈内（68.97°N）：摩尔曼斯克时间 = UTC+3（俄罗斯按经度分段，33.08°E 落在 <40 那一段）。
        // 夏至前后极昼、冬至前后极夜，用来验证极昼/极夜文案与太阳圆盘。
        Place(latitude: 68.97, longitude: 33.08, source: .manual, label: "", presetKey: "city.murmansk", countryCode: "ru"),
        // 南极内陆（80.42°S）：昆仑站（中国距南极点最近的考察站）。南极没有民用时区，
        // 中国各站按北京时间（UTC+8）。
        // 与 Android / 鸿蒙保持一致（三端需同步修改，别单独改这一端）。两条路径都得到 +8：
        // ① `GeoRegion.isInChina(countryCode: "cn")` → 480 分钟；
        // ② `CivicTime.isChinaAntarcticStation` 的坐标匹配（50 km 内的中国站）→ 480 分钟。
        // 南半球季节相反：北半球夏至时它极夜、冬至时它极昼。
        Place(latitude: -80.4169, longitude: 77.1161, source: .manual, label: "", presetKey: "city.kunlun", countryCode: "cn"),
        // 2024 补到 24 个（4 列 × 6 行整）：开罗 / 里约热内卢，接在中山站之后（其余城市顺序不变）。
        Place(latitude: 30.0444, longitude: 31.2357, source: .manual, label: "", presetKey: "city.cairo", countryCode: "eg"),
        Place(latitude: -22.9068, longitude: -43.1729, source: .manual, label: "", presetKey: "city.rio", countryCode: "br"),
    ]

    static let minLatitude = -90.0
    static let maxLatitude = 90.0
    static let minLongitude = -180.0
    static let maxLongitude = 180.0
}
