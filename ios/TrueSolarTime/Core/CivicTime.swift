import Foundation

/// 观测地的**法定（民用）标准时间**偏移，单位分钟。
///
/// 这是「标准时间」的**唯一来源**：界面左栏的标准时间、左上角 `UTC+8` 文案、
/// 日出 / 日落 / 上中天、以及真太阳时的经度修正基准，全都走这一个函数 ——
/// 混用两套口径会出现「时间一处对、一处差两小时」。
///
/// 规则（三端一致，与 Android / 鸿蒙同一套判定顺序）：
///
/// 1. **中国境内（含港澳台）→ 恒为 UTC+8**。
///    这里刻意**不看坐标落在哪个 tzdata 时区**：`Asia/Shanghai` 是 UTC+8，
///    而 `Asia/Urumqi` 是 UTC+6 —— 但中国全境官方时间都是 UTC+8，
///    所以乌鲁木齐（87.6°E）必须是 +8，绝不能被 `Asia/Urumqi` 带成 +6。
/// 2. **中国南极考察站（中山 / 长城 / 昆仑 / 泰山）→ UTC+8**：
///    南极没有民用时区，各国考察站用自己的时间，中国各站一律北京时间。
/// 3. **其它国家 → 该地点实际的 tzdata 时区**（有 `timeZoneIdentifier` 时用它，
///    含夏令时；`TimeZone(identifier:)` 取的是**当前时刻**的偏移）。
/// 4. 没有可用的时区标识时，退回 `ZoneTable`（国家码 → 偏移、多时区大国按经度分段），
///    与 Android / 鸿蒙同一张表 —— 也就是本规则之前的行为。
enum CivicTime {

    /// 中国的标准时间：UTC+8。
    static let chinaMinutes = 480

    /// 中国南极考察站的坐标（WGS-84）。站点很小，用「距离 < `stationRadiusKm`」判定，
    /// 不用大包围盒 —— 同扇区最近的澳大利亚 Davis 站（-68.58, 77.97）只有约 108 km，
    /// 包围盒会把它一起圈进来。
    static let chinaAntarcticStations: [(name: String, latitude: Double, longitude: Double)] = [
        ("中山站 Zhongshan", -69.3733, 76.3800),
        ("长城站 Great Wall", -62.2167, -58.9667),
        ("昆仑站 Kunlun", -80.4167, 77.1167),
        ("泰山站 Taishan", -73.8667, 76.9833),
    ]

    /// 判定「这就是某个中国南极站」的半径（公里）。
    /// GPS 漂移在米级，50 km 足够宽松，又不会误伤邻近的他国站点。
    static let stationRadiusKm = 50.0

    /// 观测点的法定标准时间偏移（分钟）。
    ///
    /// - Parameters:
    ///   - latitude: WGS-84 纬度。
    ///   - longitude: WGS-84 经度。
    ///   - countryCode: ISO 3166-1 alpha-2（大小写不敏感），未知传 nil。
    ///   - timeZoneIdentifier: 该地点实际的 tzdata 时区标识（如 `Asia/Tokyo`）。
    ///     iOS 目前没有「坐标 → 时区」的本地数据库，调用方传 nil 时走 `ZoneTable`；
    ///     将来若从 `CLPlacemark.timeZone` 拿到标识，直接传进来即可（判定顺序不变）。
    static func standardOffsetMinutes(
        latitude: Double,
        longitude: Double,
        countryCode: String?,
        timeZoneIdentifier: String? = nil
    ) -> Int {
        // ① 中国境内（含港澳台）：恒 +8，不看 tzdata 的分区。
        if GeoRegion.isInChina(countryCode: countryCode, latitude: latitude, longitude: longitude) {
            return chinaMinutes
        }

        // ② 中国南极考察站：+8（北京时间）。
        if isChinaAntarcticStation(latitude: latitude, longitude: longitude) {
            return chinaMinutes
        }

        // ③ 该地点实际的 tzdata 时区（含夏令时，取当前时刻的偏移）。
        if let identifier = timeZoneIdentifier,
           let zone = TimeZone(identifier: identifier) {
            return zone.secondsFromGMT() / 60
        }

        // ④ 退回国家表 / 经度分段（规则落地之前的行为，保持现状）。
        //    注意 `ZoneTable` 给的是**秒**，这里要换成分钟。
        return ZoneTable.offsetSeconds(
            countryCode: countryCode,
            longitude: longitude,
            fallbackSeconds: SolarTimeMath.approxZoneOffsetSeconds(longitude: longitude)
        ) / 60
    }

    /// 该坐标是不是中国的南极考察站（半径见 `stationRadiusKm`）。
    static func isChinaAntarcticStation(latitude: Double, longitude: Double) -> Bool {
        chinaAntarcticStations.contains { station in
            DistrictNaming.distanceKm(
                latitude, longitude,
                station.latitude, station.longitude
            ) <= stationRadiusKm
        }
    }

    /// 命中的站点名（诊断 / 自检用）；不是站点返回 nil。
    static func chinaAntarcticStationName(latitude: Double, longitude: Double) -> String? {
        chinaAntarcticStations.first { station in
            DistrictNaming.distanceKm(
                latitude, longitude,
                station.latitude, station.longitude
            ) <= stationRadiusKm
        }?.name
    }
}
