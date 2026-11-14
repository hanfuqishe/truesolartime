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

    private init() {}

    func cachedNames() -> DistrictNames? {
        guard let full = defaults.string(forKey: Key.full) else { return nil }
        let short = defaults.string(forKey: Key.short) ?? full
        return DistrictNames(full: full, short: short, countryCode: defaults.string(forKey: Key.country))
    }

    /// 需要且允许时反查一次；成功后在主线程回调。
    func requestRefresh(place: Place, completion: ((DistrictNames) -> Void)? = nil) {
        guard !inFlight, !geocoder.isGeocoding else { return }
        guard needsRefresh(place) else { return }

        inFlight = true
        let location = CLLocation(latitude: place.latitude, longitude: place.longitude)
        geocoder.reverseGeocodeLocation(location, preferredLocale: Locale.current) { [weak self] placemarks, _ in
            guard let self else { return }
            self.inFlight = false
            guard let mark = placemarks?.first else { return }
            guard let names = Self.names(from: mark) else { return }
            DispatchQueue.main.async {
                self.save(place: place, names: names)
                completion?(names)
            }
        }
    }

    /// 把 `CLPlacemark` 的各级字段拼成显示名；中文走「市+区县」，其他语言走逗号拼接。
    static func names(from mark: CLPlacemark) -> DistrictNames? {
        let county = mark.subLocality ?? mark.subAdministrativeArea
        let city = mark.locality ?? mark.subAdministrativeArea
        let region = mark.administrativeArea
        let country = mark.isoCountryCode?.lowercased()

        var names: DistrictNames?
        if DistrictNaming.prefersChinese(Locale.current.languageCode ?? "en") {
            names = DistrictNaming.joinChinese(county: county, city: city, region: region)
        }
        if names == nil {
            names = DistrictNaming.compose(parts: [county, city, region])
        }
        guard var resolved = names else { return nil }
        // 国家码用来查标准时区（`ZoneTable`），反查不到时保持 nil，由经度近似兜底。
        resolved.countryCode = (country?.count == 2) ? country : nil
        return resolved
    }

    private func needsRefresh(_ place: Place) -> Bool {
        guard defaults.string(forKey: Key.full) != nil else { return true }
        if defaults.string(forKey: Key.language) != Locale.current.languageCode { return true }
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
        defaults.set(Locale.current.languageCode, forKey: Key.language)
    }
}
