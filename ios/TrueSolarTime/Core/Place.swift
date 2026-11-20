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
    /// 所属大洲（仅预设城市有意义；设置页按它分组）。
    var region: CityRegion = .asia

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
        // asia
        Place(latitude: 39.9042, longitude: 116.4074, source: .manual, label: "", presetKey: "city.beijing", countryCode: "cn", region: .asia),
        Place(latitude: 31.2304, longitude: 121.4737, source: .manual, label: "", presetKey: "city.shanghai", countryCode: "cn", region: .asia),
        Place(latitude: 23.1291, longitude: 113.2644, source: .manual, label: "", presetKey: "city.guangzhou", countryCode: "cn", region: .asia),
        Place(latitude: 22.5431, longitude: 114.0579, source: .manual, label: "", presetKey: "city.shenzhen", countryCode: "cn", region: .asia),
        Place(latitude: 30.5728, longitude: 104.0668, source: .manual, label: "", presetKey: "city.chengdu", countryCode: "cn", region: .asia),
        Place(latitude: 34.3416, longitude: 108.9398, source: .manual, label: "", presetKey: "city.xian", countryCode: "cn", region: .asia),
        Place(latitude: 45.8038, longitude: 126.5350, source: .manual, label: "", presetKey: "city.harbin", countryCode: "cn", region: .asia),
        Place(latitude: 52.9721, longitude: 122.5388, source: .manual, label: "", presetKey: "city.mohe", countryCode: "cn", region: .asia),
        Place(latitude: 48.3669, longitude: 134.2895, source: .manual, label: "", presetKey: "city.fuyuan", countryCode: "cn", region: .asia),
        Place(latitude: 43.8256, longitude: 87.6168, source: .manual, label: "", presetKey: "city.urumqi", countryCode: "cn", region: .asia),
        Place(latitude: 39.4704, longitude: 75.9898, source: .manual, label: "", presetKey: "city.kashgar", countryCode: "cn", region: .asia),
        Place(latitude: 29.6520, longitude: 91.1721, source: .manual, label: "", presetKey: "city.lhasa", countryCode: "cn", region: .asia),
        Place(latitude: 22.3193, longitude: 114.1694, source: .manual, label: "", presetKey: "city.hongkong", countryCode: "hk", region: .asia),
        Place(latitude: 25.0330, longitude: 121.5654, source: .manual, label: "", presetKey: "city.taipei", countryCode: "tw", region: .asia),
        Place(latitude: 22.6273, longitude: 120.3014, source: .manual, label: "", presetKey: "city.kaohsiung", countryCode: "tw", region: .asia),
        Place(latitude: 16.8343, longitude: 112.3388, source: .manual, label: "", presetKey: "city.sansha", countryCode: "cn", region: .asia),
        Place(latitude: 25.7459, longitude: 123.4776, source: .manual, label: "", presetKey: "city.diaoyu", countryCode: "cn", region: .asia),
        Place(latitude: 35.6762, longitude: 139.6503, source: .manual, label: "", presetKey: "city.tokyo", countryCode: "jp", region: .asia),
        Place(latitude: 37.5665, longitude: 126.9780, source: .manual, label: "", presetKey: "city.seoul", countryCode: "kr", region: .asia),
        Place(latitude: 39.0392, longitude: 125.7625, source: .manual, label: "", presetKey: "city.pyongyang", countryCode: "kp", region: .asia),
        Place(latitude: 43.1155, longitude: 131.8855, source: .manual, label: "", presetKey: "city.vladivostok", countryCode: "ru", region: .asia),
        Place(latitude: 1.3521, longitude: 103.8198, source: .manual, label: "", presetKey: "city.singapore", countryCode: "sg", region: .asia),
        Place(latitude: 13.7563, longitude: 100.5018, source: .manual, label: "", presetKey: "city.bangkok", countryCode: "th", region: .asia),
        Place(latitude: 17.9757, longitude: 102.6331, source: .manual, label: "", presetKey: "city.vientiane", countryCode: "la", region: .asia),
        Place(latitude: -6.2088, longitude: 106.8456, source: .manual, label: "", presetKey: "city.jakarta", countryCode: "id", region: .asia),
        Place(latitude: 28.6139, longitude: 77.2090, source: .manual, label: "", presetKey: "city.newdelhi", countryCode: "in", region: .asia),
        Place(latitude: 25.2048, longitude: 55.2708, source: .manual, label: "", presetKey: "city.dubai", countryCode: "ae", region: .asia),
        Place(latitude: 41.0082, longitude: 28.9784, source: .manual, label: "", presetKey: "city.istanbul", countryCode: "tr", region: .asia),
        // europe
        Place(latitude: 55.7558, longitude: 37.6173, source: .manual, label: "", presetKey: "city.moscow", countryCode: "ru", region: .europe),
        Place(latitude: 51.5074, longitude: -0.1278, source: .manual, label: "", presetKey: "city.london", countryCode: "gb", region: .europe),
        Place(latitude: 48.8566, longitude: 2.3522, source: .manual, label: "", presetKey: "city.paris", countryCode: "fr", region: .europe),
        Place(latitude: 52.5200, longitude: 13.4050, source: .manual, label: "", presetKey: "city.berlin", countryCode: "de", region: .europe),
        Place(latitude: 41.9028, longitude: 12.4964, source: .manual, label: "", presetKey: "city.rome", countryCode: "it", region: .europe),
        Place(latitude: 40.4168, longitude: -3.7038, source: .manual, label: "", presetKey: "city.madrid", countryCode: "es", region: .europe),
        Place(latitude: 64.1466, longitude: -21.9426, source: .manual, label: "", presetKey: "city.reykjavik", countryCode: "is", region: .europe),
        Place(latitude: 68.97, longitude: 33.08, source: .manual, label: "", presetKey: "city.murmansk", countryCode: "ru", region: .europe),
        // africa
        Place(latitude: 30.0444, longitude: 31.2357, source: .manual, label: "", presetKey: "city.cairo", countryCode: "eg", region: .africa),
        Place(latitude: -33.9249, longitude: 18.4241, source: .manual, label: "", presetKey: "city.capetown", countryCode: "za", region: .africa),
        Place(latitude: -1.2921, longitude: 36.8219, source: .manual, label: "", presetKey: "city.nairobi", countryCode: "ke", region: .africa),
        Place(latitude: -1.9441, longitude: 30.0619, source: .manual, label: "", presetKey: "city.kigali", countryCode: "rw", region: .africa),
        Place(latitude: 6.5244, longitude: 3.3792, source: .manual, label: "", presetKey: "city.lagos", countryCode: "ng", region: .africa),
        // northAmerica
        Place(latitude: 21.3069, longitude: -157.8583, source: .manual, label: "", presetKey: "city.honolulu", countryCode: "us", region: .northAmerica),
        Place(latitude: 34.0522, longitude: -118.2437, source: .manual, label: "", presetKey: "city.losangeles", countryCode: "us", region: .northAmerica),
        Place(latitude: 40.7128, longitude: -74.0060, source: .manual, label: "", presetKey: "city.newyork", countryCode: "us", region: .northAmerica),
        Place(latitude: 41.8781, longitude: -87.6298, source: .manual, label: "", presetKey: "city.chicago", countryCode: "us", region: .northAmerica),
        Place(latitude: 19.4326, longitude: -99.1332, source: .manual, label: "", presetKey: "city.mexicocity", countryCode: "mx", region: .northAmerica),
        Place(latitude: 49.2827, longitude: -123.1207, source: .manual, label: "", presetKey: "city.vancouver", countryCode: "ca", region: .northAmerica),
        // southAmerica
        Place(latitude: -22.9068, longitude: -43.1729, source: .manual, label: "", presetKey: "city.rio", countryCode: "br", region: .southAmerica),
        Place(latitude: -23.5505, longitude: -46.6333, source: .manual, label: "", presetKey: "city.saopaulo", countryCode: "br", region: .southAmerica),
        Place(latitude: -34.6037, longitude: -58.3816, source: .manual, label: "", presetKey: "city.buenosaires", countryCode: "ar", region: .southAmerica),
        Place(latitude: -12.0464, longitude: -77.0428, source: .manual, label: "", presetKey: "city.lima", countryCode: "pe", region: .southAmerica),
        // oceania
        Place(latitude: -33.8688, longitude: 151.2093, source: .manual, label: "", presetKey: "city.sydney", countryCode: "au", region: .oceania),
        Place(latitude: -31.9523, longitude: 115.8613, source: .manual, label: "", presetKey: "city.perth", countryCode: "au", region: .oceania),
        Place(latitude: -36.8485, longitude: 174.7633, source: .manual, label: "", presetKey: "city.auckland", countryCode: "nz", region: .oceania),
        // antarctica
        Place(latitude: -80.4169, longitude: 77.1161, source: .manual, label: "", presetKey: "city.kunlun", countryCode: "cn", region: .antarctica),
    ]

    static let minLatitude = -90.0
    static let maxLatitude = 90.0
    static let minLongitude = -180.0
    static let maxLongitude = 180.0
}
