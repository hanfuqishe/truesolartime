import CoreLocation
import Foundation

/// 用系统 `CLGeocoder` 把经纬度反查成「市 + 区县」。
///
/// 选它而不是高德/OSM 的原因：iOS 自带、无需 Key，而且返回的名字**跟随系统语言**
/// （中文得到「黄浦区」，英文得到「Huangpu District」），正好符合「区划名跟着界面语言走」。
/// 结果按位置缓存：移动超过 5 km 或缓存超过 30 天才重查；语言变了也重查。
final class DistrictStore {

    static let shared = DistrictStore()

    private enum Key {
        static let full = "district.full"
        static let short = "district.short"
        static let country = "district.country"
        static let latitude = "district.latitude"
        static let longitude = "district.longitude"
        static let fetchedAt = "district.fetched_at"
        static let language = "district.language"
    }

    private let defaults = UserDefaults.standard
    private let geocoder = CLGeocoder()
    private var inFlight = false
    /// 正在反查的那个地点（坐标取 4 位小数 ≈ 11 m）：同一地点的重复请求不再互相取消。
    private var inFlightSiteKey: String?
    /// 请求代号：切换城市时自增，用来丢弃迟到的旧结果。
    private var generation = 0

    /// 最近一次反查的失败原因（成功时为 nil）。设置页「诊断」会显示它 ——
    /// 境外坐标的 `CLGeocoder` 行为只有真机能验证，把错误码留在界面上才能快速定位。
    private(set) var lastErrorDescription: String?

    private init() {}

    /// 读缓存的地名。
    ///
    /// 传入 `place` 时会核对缓存对应的坐标：换了城市（相距超过 5 km）就当作没有缓存，
    /// 避免切到纽约后卡片上还挂着北京上一次的「北京市东城区」。
    func cachedNames(for place: Place? = nil) -> DistrictNames? {
        guard let full = defaults.string(forKey: Key.full) else { return nil }
        if let place, defaults.object(forKey: Key.latitude) != nil {
            let lat = defaults.double(forKey: Key.latitude)
            let lon = defaults.double(forKey: Key.longitude)
            let moved = DistrictNaming.distanceKm(lat, lon, place.latitude, place.longitude)
            if moved > DistrictNaming.moveThresholdKm { return nil }
        }
        let short = defaults.string(forKey: Key.short) ?? full
        return DistrictNames(full: full, short: short, countryCode: defaults.string(forKey: Key.country))
    }

    /// 需要且允许时反查一次；成功后在主线程回调。
    ///
    /// - Parameter force: 用户**明确换了地点**（点常用城市 / 应用手工坐标）时传 true，
    ///   跳过 `needsRefresh` 的距离与时限判定，一定真的发一次 `reverseGeocodeLocation`。
    ///   否则「先上海、再纽约」这类切换一旦被缓存判定挡住，卡片就永远只有预设城市名。
    ///
    /// 连续切换城市时：旧请求会被取消，并用「代号」把迟到的旧结果丢掉，
    /// 否则会出现「切到纽约，卡片却回填北京的地名」。
    /// 但**同一个地点**的请求还在路上时不做取消 —— 反复 cancel 会让回调丢失
    /// （表现就是「圈一下就没反应」，区划名一直是空的）。
    func requestRefresh(place: Place, force: Bool = false, completion: ((DistrictNames) -> Void)? = nil) {
        let siteKey = Self.siteKey(place)
        if inFlight, siteKey == inFlightSiteKey, !force { return }
        if !force, !needsRefresh(place) { return }

        if inFlight {
            geocoder.cancelGeocode()
            inFlight = false
        }
        generation += 1
        inFlight = true
        inFlightSiteKey = siteKey
        reverseGeocode(
            place: place,
            locale: AppLanguage.geocoderLocale,
            isRetry: false,
            generation: generation,
            completion: completion
        )
    }

    /// 真正的系统反查。
    ///
    /// 中文 locale 拿不到名字时（Apple 对部分境外小城市没有中文译名，或该 locale 直接失败），
    /// 用系统 locale 再试一次：宁可显示原文「Manhattan」也不要什么都不显示。
    private func reverseGeocode(
        place: Place,
        locale: Locale,
        isRetry: Bool,
        generation: Int,
        completion: ((DistrictNames) -> Void)?
    ) {
        let location = CLLocation(latitude: place.latitude, longitude: place.longitude)
        geocoder.reverseGeocodeLocation(location, preferredLocale: locale) { [weak self] placemarks, error in
            guard let self else { return }
            guard generation == self.generation else { return }
            if let mark = placemarks?.first, let names = Self.names(from: mark) {
                self.lastErrorDescription = nil
                self.inFlight = false
                DispatchQueue.main.async {
                    self.save(place: place, names: names)
                    completion?(names)
                }
                return
            }
            let reason = Self.describe(error: error, hasPlacemark: placemarks?.first != nil)
            if !isRetry {
                self.lastErrorDescription = "中文 locale 无结果（\(reason)），已用系统 locale 重试"
                self.reverseGeocode(
                    place: place,
                    locale: Locale.current,
                    isRetry: true,
                    generation: generation,
                    completion: completion
                )
                return
            }
            self.lastErrorDescription = reason
            self.inFlight = false
        }
    }

    /// 失败原因的一行说明，给设置页「诊断」用（境外坐标只有真机能查，留在界面上才能定位问题）。
    private static func describe(error: Error?, hasPlacemark: Bool) -> String {
        if let error {
            let ns = error as NSError
            return "\(ns.domain) \(ns.code)"
        }
        return hasPlacemark ? "各级地名都为空" : "系统没有返回地址"
    }

    /// 同一地点的判定键：坐标取 4 位小数（约 11 m），GPS 抖动不算换了地点。
    private static func siteKey(_ place: Place) -> String {
        String(format: "%.4f,%.4f", place.latitude, place.longitude)
    }

    /// 把 `CLPlacemark` 的各级字段交给 `DistrictNaming.composeNames`；任何一级有值就出名字。
    ///
    /// 境外地址（Apple 常只给 `locality` / `administrativeArea` / `country`）必须有结果：
    /// 旧实现把「区县」当必需项，`subLocality` 一缺就整串退化成 nil，界面只能显示预设城市名
    /// —— 这就是用户看到的「选了外国城市没有反查出来」。
    static func names(from mark: CLPlacemark) -> DistrictNames? {
        guard var names = DistrictNaming.composeNames(
            district: mark.subLocality ?? mark.subAdministrativeArea,
            city: mark.locality,
            region: mark.administrativeArea,
            country: mark.country,
            prefersChinese: AppLanguage.prefersChinese
        ) else { return nil }
        // 国家码用来查标准时区（`ZoneTable`），反查不到时保持 nil，由经度近似兜底。
        let country = mark.isoCountryCode?.lowercased()
        names.countryCode = (country?.count == 2) ? country : nil
        return names
    }

    private func needsRefresh(_ place: Place) -> Bool {
        guard defaults.string(forKey: Key.full) != nil else { return true }
        if defaults.string(forKey: Key.language) != AppLanguage.code { return true }
        let lat = defaults.double(forKey: Key.latitude)
        let lon = defaults.double(forKey: Key.longitude)
        let moved = DistrictNaming.distanceKm(lat, lon, place.latitude, place.longitude)
        let age = Date().timeIntervalSince1970 - defaults.double(forKey: Key.fetchedAt)
        return DistrictNaming.shouldQuery(movedKm: moved, ageSeconds: age)
    }

    private func save(place: Place, names: DistrictNames) {
        defaults.set(names.full, forKey: Key.full)
        defaults.set(names.short, forKey: Key.short)
        defaults.set(names.countryCode, forKey: Key.country)
        defaults.set(place.latitude, forKey: Key.latitude)
        defaults.set(place.longitude, forKey: Key.longitude)
        defaults.set(Date().timeIntervalSince1970, forKey: Key.fetchedAt)
        defaults.set(AppLanguage.code, forKey: Key.language)
    }
}
