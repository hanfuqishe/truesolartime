import CoreLocation
import Foundation

/// 把经纬度反查成「区县 + 市 + 州/省」。
///
/// 主用系统 `CLGeocoder`（iOS 自带、无需 Key、名字跟随语言）；它拿不到地名、或者只回了
/// 国家一级时，**再用 OpenStreetMap Nominatim 兜底**（与 Android 对境外坐标的做法一致）。
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
        static let provider = "district.provider"
    }

    private let defaults = UserDefaults.standard
    private let geocoder = CLGeocoder()
    /// OSM 兜底用的会话：12 秒超时（与 Android 的 12 s 一致）、允许等网络。
    private let nominatimSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 24
        config.waitsForConnectivity = true
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    private var inFlight = false
    /// 正在反查的那个地点（坐标取 4 位小数 ≈ 11 m）：同一地点的重复请求不再互相取消。
    private var inFlightSiteKey: String?
    /// 请求代号：切换城市时自增，用来丢弃迟到的旧结果。
    private var generation = 0

    // MARK: - 诊断（设置 → 诊断 → 区划名）

    /// 最近一次反查的失败原因（成功时为 nil）。
    private(set) var lastErrorDescription: String?
    /// 最近一次成功的地名来源："Apple" / "OSM"。
    private(set) var lastProvider: String = "-"
    /// 最近一次 `CLGeocoder` 到底回了什么（逐字段），排查「境外只回国家」用。
    private(set) var lastAppleFields: String = "-"

    // MARK: 反查节流（最小接线，不改 OSM 分支）
    /// 成功过的地名，按**约 100 m 网格**（`PlaceNameThrottle.cacheKey`）缓存：同一键永不重复请求。
    private var geocodeCache: [String: DistrictNames] = [:]
    /// 上一次真正发出请求的时刻（全局保留，不随地点清理）。
    private var lastGeocodeRequestAt: Date?
    /// 上一次成功反查的时刻（诊断「上次成功 N 分钟前」）。
    private var lastGeocodeSuccessAt: Date?
    /// 这一次为什么没发请求（命中缓存 / 等待间隔 / 在飞）。
    private(set) var geocodeSkipReason: String?

    /// **换地点时清空诊断残留**：否则 `CLGeocoder：locality=上海市…` 会一直挂在新城市（东京）上。
    func resetDiagnosticsForNewPlace() {
        lastAppleFields = "-"
        lastErrorDescription = nil
        geocodeSkipReason = nil
        lastProvider = "-"
    }

    /// 诊断一行：`反查 = 命中缓存 / 已请求 / 等待间隔 / 在飞 · 上次成功 N 分钟前`。
    func geocodeSummary() -> String {
        var parts: [String] = []
        if inFlight {
            parts.append(L("district.geoInFlight"))
        } else if let reason = geocodeSkipReason {
            parts.append(reason)
        } else if lastGeocodeRequestAt != nil {
            parts.append(L("district.geoRequested"))
        } else {
            parts.append(L("district.geoNotYet"))
        }
        if let success = lastGeocodeSuccessAt {
            let minutes = max(0, Int(Date().timeIntervalSince(success) / 60))
            parts.append(Lf("district.geoSucceededAgo", minutes))
        }
        return parts.joined(separator: " · ")
    }

    private init() {
        lastProvider = defaults.string(forKey: Key.provider) ?? "-"
    }

    /// 读缓存的地名。
    ///
    /// 传入 `place` 时会**核对缓存对应的坐标**：没存过坐标（旧版本缓存）或换了城市（> 5 km）
    /// 都当作没有缓存 —— 否则手动输入埃及坐标时，卡片上会挂着上一次的「北京」。
    func cachedNames(for place: Place? = nil) -> DistrictNames? {
        guard let full = defaults.string(forKey: Key.full) else { return nil }
        if let place {
            let storedLatitude = defaults.object(forKey: Key.latitude) != nil
                ? defaults.double(forKey: Key.latitude)
                : nil
            let storedLongitude = defaults.object(forKey: Key.longitude) != nil
                ? defaults.double(forKey: Key.longitude)
                : nil
            guard DistrictNaming.cacheMatches(
                storedLatitude: storedLatitude,
                storedLongitude: storedLongitude,
                place: place
            ) else { return nil }
        }
        let short = defaults.string(forKey: Key.short) ?? full
        return DistrictNames(full: full, short: short, countryCode: defaults.string(forKey: Key.country))
    }

    /// 需要且允许时反查一次；成功后在主线程回调。
    ///
    /// - Parameter force: 用户**明确换了地点**（点常用城市 / 应用手工坐标）时传 true，
    ///   跳过 `needsRefresh` 的距离与时限判定，一定真的发一次请求。
    ///
    /// 连续切换城市时：旧请求会被取消，并用「代号」把迟到的旧结果丢掉，
    /// 否则会出现「切到纽约，卡片却回填北京的地名」。
    /// 但**同一个地点**的请求还在路上时不做取消 —— 反复 cancel 会让回调丢失。
    func requestRefresh(place: Place, force: Bool = false, completion: ((DistrictNames?) -> Void)? = nil) {
        let siteKey = Self.siteKey(place)
        // **入口节流**（最小接线）：
        //  1) 命中网格缓存 → 直接用缓存名，不发请求；
        //  2) 在飞 / 未到 3 秒间隔 → 记下原因并返回（不排队堆积，下次触发再发）。
        let throttleKey = PlaceNameThrottle.cacheKey(latitude: place.latitude, longitude: place.longitude)
        if let cached = geocodeCache[throttleKey] {
            geocodeSkipReason = L("district.geoHitCache")
            finish(place: place, names: cached, provider: lastProvider == "-" ? "Apple" : lastProvider, completion: completion)
            return
        }
        let now = Date()
        guard PlaceNameThrottle.shouldRequest(
            key: throttleKey,
            cachedKeys: Set(geocodeCache.keys),
            lastRequestAt: lastGeocodeRequestAt?.timeIntervalSince1970,
            now: now.timeIntervalSince1970,
            inFlight: inFlight
        ) else {
            geocodeSkipReason = inFlight ? L("district.geoInFlight") : L("district.geoWaiting")
            return
        }
        geocodeSkipReason = nil
        lastGeocodeRequestAt = now

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

    /// 第一步：系统反查。
    ///
    /// 中文 locale 拿不到结果时用系统 locale 再试一次；两次都「只有国家一级」或干脆没有结果，
    /// 就转 `fetchNominatim` 兜底 —— 境外坐标在大陆网络下经常就是这样。
    private func reverseGeocode(
        place: Place,
        locale: Locale,
        isRetry: Bool,
        generation: Int,
        completion: ((DistrictNames?) -> Void)?
    ) {
        let location = CLLocation(latitude: place.latitude, longitude: place.longitude)
        geocoder.reverseGeocodeLocation(location, preferredLocale: locale) { [weak self] placemarks, error in
            guard let self else { return }
            guard generation == self.generation else { return }

            if let mark = placemarks?.first {
                self.lastAppleFields = Self.describe(mark)
                let appleNames = Self.names(from: mark)
                if let appleNames, !Self.isWeak(appleNames, country: mark.country) {
                    self.lastErrorDescription = nil
                    self.finish(place: place, names: appleNames, provider: "Apple", completion: completion)
                    return
                }
                // 只有国家一级（或什么都没解析出来）：上屏没意义，交给 OSM 补区县/市。
                self.lastErrorDescription = Lf("district.appleOnly", appleNames?.full ?? "-")
                if !isRetry {
                    self.reverseGeocode(
                        place: place,
                        locale: Locale.current,
                        isRetry: true,
                        generation: generation,
                        completion: completion
                    )
                    return
                }
                self.fetchNominatim(place: place, generation: generation, attempt: 1, completion: completion)
                return
            }

            self.lastErrorDescription = Lf("district.appleNoResult", Self.describe(error: error, hasPlacemark: false))
            if !isRetry {
                self.reverseGeocode(
                    place: place,
                    locale: Locale.current,
                    isRetry: true,
                    generation: generation,
                    completion: completion
                )
                return
            }
            self.fetchNominatim(place: place, generation: generation, attempt: 1, completion: completion)
        }
    }

    /// 第二步：OpenStreetMap Nominatim 兜底（12 秒超时 + 失败重试一次，与 Android 同策略）。
    private func fetchNominatim(
        place: Place,
        generation: Int,
        attempt: Int,
        completion: ((DistrictNames?) -> Void)?
    ) {
        guard let url = NominatimReverse.url(
            latitude: place.latitude,
            longitude: place.longitude,
            language: Self.nominatimLanguage
        ) else {
            lastErrorDescription = L("district.osmUrlFailed")
            fail(completion: completion)
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue(NominatimReverse.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.nominatimLanguage, forHTTPHeaderField: "Accept-Language")

        nominatimSession.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            guard generation == self.generation else { return }

            let status = (response as? HTTPURLResponse)?.statusCode
            let json = data.flatMap { String(data: $0, encoding: .utf8) }
            let names = json.flatMap {
                NominatimReverse.names(json: $0, prefersChinese: AppLanguage.prefersChinese)
            }
            if let names {
                self.lastErrorDescription = nil
                self.finish(place: place, names: names, provider: "OSM", completion: completion)
                return
            }

            let reason: String
            if let error {
                let ns = error as NSError
                reason = Lf("diag.networkError", ns.domain, ns.code)
            } else if let status, !(200..<300).contains(status) {
                reason = "HTTP \(status)"
            } else {
                reason = L("district.osmNoName")
            }
            if attempt < 2 {
                // 境外网络偶发抖动：与 Android 一样再试一次。
                self.lastErrorDescription = Lf("district.osmRetrying", reason)
                DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                    self.fetchNominatim(
                        place: place,
                        generation: generation,
                        attempt: attempt + 1,
                        completion: completion
                    )
                }
                return
            }
            self.lastErrorDescription = Lf("district.osmFailed", reason)
            self.fail(completion: completion)
        }.resume()
    }

    /// 成功收尾：落盘 + 主线程回调。
    private func finish(
        place: Place,
        names: DistrictNames,
        provider: String,
        completion: ((DistrictNames?) -> Void)?
    ) {
        inFlight = false
        let key = PlaceNameThrottle.cacheKey(latitude: place.latitude, longitude: place.longitude)
        geocodeCache[key] = names
        lastGeocodeSuccessAt = Date()
        DispatchQueue.main.async {
            self.lastProvider = provider
            self.save(place: place, names: names, provider: provider)
            completion?(names)
        }
    }

    /// 失败收尾：复位 in-flight 并**把 nil 回调出去**。
    ///
    /// 界面拿到 nil 就显示半角「-」（既定产品决策）。绝不能「什么都不回调」——
    /// 那样卡片会一直挂着上一个城市的地名（手动输入埃及坐标却显示「北京」就是这么来的）。
    private func fail(completion: ((DistrictNames?) -> Void)?) {
        inFlight = false
        lastProvider = "-"
        DispatchQueue.main.async {
            completion?(nil)
        }
    }

    /// 「只有国家一级」的弱结果：值得继续找细节（Apple 对境外常见）。
    private static func isWeak(_ names: DistrictNames?, country: String?) -> Bool {
        guard let names else { return true }
        guard let countryName = DistrictNaming.clean(country) else { return false }
        return names.full == countryName
    }

    /// `CLGeocoder` 逐字段快照，给「诊断」看。
    private static func describe(_ mark: CLPlacemark) -> String {
        func value(_ text: String?) -> String {
            guard let text, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return "—" }
            return text
        }
        return [
            "locality=\(value(mark.locality))",
            "subLocality=\(value(mark.subLocality))",
            "subAdmin=\(value(mark.subAdministrativeArea))",
            "admin=\(value(mark.administrativeArea))",
            "country=\(value(mark.country))",
        ].joined(separator: " ")
    }

    /// 失败原因的一行说明。
    private static func describe(error: Error?, hasPlacemark: Bool) -> String {
        if let error {
            let ns = error as NSError
            return "\(ns.domain) \(ns.code)"
        }
        return hasPlacemark ? L("district.emptyFields") : L("district.noAddress")
    }

    /// Nominatim 的 `accept-language`：中文界面用 zh-CN。
    private static var nominatimLanguage: String {
        AppLanguage.geocoderLocale.identifier.replacingOccurrences(of: "_", with: "-")
    }

    /// 同一地点的判定键：坐标取 4 位小数（约 11 m），GPS 抖动不算换了地点。
    private static func siteKey(_ place: Place) -> String {
        String(format: "%.4f,%.4f", place.latitude, place.longitude)
    }

    /// 把 `CLPlacemark` 的各级字段交给 `DistrictNaming.composeNames`；任何一级有值就出名字。
    ///
    /// 境外地址（Apple 常只给 `locality` / `administrativeArea` / `country`）必须有结果：
    /// 早先的实现把「区县」当必需项，`subLocality` 一缺就整串退化成 nil，界面只能显示预设城市名。
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

    /// 诊断：缓存里的名字来自哪儿、最近一次失败原因、`CLGeocoder` 到底回了什么。
    func diagnosticsSummary() -> String {
        var parts: [String] = [Lf("district.source", lastProvider), geocodeSummary()]
        if let lastErrorDescription { parts.append(lastErrorDescription) }
        parts.append(Lf("district.appleFields", lastAppleFields))
        return parts.joined(separator: " · ")
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

    private func save(place: Place, names: DistrictNames, provider: String) {
        defaults.set(names.full, forKey: Key.full)
        defaults.set(names.short, forKey: Key.short)
        defaults.set(names.countryCode, forKey: Key.country)
        defaults.set(place.latitude, forKey: Key.latitude)
        defaults.set(place.longitude, forKey: Key.longitude)
        defaults.set(Date().timeIntervalSince1970, forKey: Key.fetchedAt)
        defaults.set(AppLanguage.code, forKey: Key.language)
        defaults.set(provider, forKey: Key.provider)
    }
}
