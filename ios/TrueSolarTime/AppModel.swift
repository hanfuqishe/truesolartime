import Combine
import Foundation
import CoreLocation
import UIKit

/// 界面状态与业务逻辑。所有方法都在主线程调用（Timer、定位回调均由主 RunLoop 驱动）。
final class AppModel: ObservableObject {

    @Published private(set) var now = Date()
    @Published private(set) var place: Place
    @Published private(set) var trackingGps = false
    @Published private(set) var waitingForFix = false
    @Published private(set) var remindersEnabled: Bool
    @Published private(set) var keyTimeChimeEnabled: Bool
    @Published private(set) var mapStyle: MapStyle
    @Published private(set) var weather: WeatherSnapshot?
    @Published private(set) var keyTime: TakeTimeSchedule?
    @Published private(set) var districtName: DistrictNames?
    @Published private(set) var keepScreenOn: Bool = false
    /// 主题三态（自动 / 亮色 / 暗色），默认自动。首页与大卡片的配色由它 + 太阳高度角共同决定。
    @Published private(set) var themeMode: ThemeMode
    /// 天气取不到时给界面看的说明（成功时为空串）。
    @Published private(set) var weatherStatus: String = ""
    /// 是否正有一次天气取数在飞（新地点还没有缓存时，卡片显示「更新中…」而不是旧城市的数据）。
    @Published private(set) var weatherLoading: Bool = false
    /// 关键时间（抓取）的状态说明，设置页「诊断」用；随抓取结果变化。
    @Published private(set) var keyTimeStatus: String = ""
    /// 设置页「诊断」区块是否可见。
    ///
    /// 默认隐藏：**连续点 7 次版本号**（相邻两次间隔 ≤2 秒）才打开，见 `registerVersionTap()`。
    /// 刻意不写 UserDefaults —— 只在本次 App 生命周期内有效，重启回到隐藏。
    @Published private(set) var showDiagnostics = false
    @Published var message: String?

    private let settings = AppSettings()
    private let location = LocationProvider()
    private var clockTimer: Timer?
    private var fixWatchdog: Timer?
    private var announcedFirstFix = false
    /// 「连点 7 次版本号」的计数器（纯逻辑在 `Core/DiagnosticsUnlock.swift`）。
    private var diagnosticsUnlock = DiagnosticsUnlock()

    init() {
        place = settings.place
        remindersEnabled = settings.remindersEnabled
        keyTimeChimeEnabled = settings.keyTimeChimeEnabled
        mapStyle = settings.mapStyle
        weather = WeatherStore.shared.cached(for: settings.place)
        keyTime = KeyTimeStore.shared.schedule()
        keyTimeStatus = KeyTimeStore.shared.diagnosticsSummary()
        districtName = DistrictStore.shared.cachedNames(for: settings.place)
        keepScreenOn = settings.keepScreenOn
        themeMode = settings.themeMode
        applyKeepScreenOn()
        startClock()
        refreshData()
        rescheduleReminders()
    }

    var snapshot: SolarSnapshot {
        SolarTimeSnapshot.compute(date: now, latitude: place.latitude, longitude: place.longitude, countryCode: place.countryCode)
    }

    /// 配色用的「当前是不是白天」：自动模式按太阳高度角，亮色 / 暗色强制忽略日出日落。
    ///
    /// 页面背景、卡片、大卡片渐变都读它；`SunCard` 里的太阳弧仍按真实高度角画（事实，不是配色）。
    var uiIsDay: Bool {
        themeMode.isDayPalette(sunIsUp: snapshot.isDay)
    }

    /// 当前天气来自哪个源（底部署名跟着它切换）。
    var weatherSource: WeatherSource {
        weather?.source ?? WeatherStore.shared.source
    }

    /// 底部的数据来源署名（Open-Meteo CC BY 4.0 ↔ 7Timer!）。
    var weatherAttribution: String {
        weatherSource.attribution
    }

    // MARK: - 时钟

    private func startClock() {
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.now = Date()
            WeatherStore.shared.watchdog()
            let status = self.weather == nil ? WeatherStore.shared.diagnosticsSummary() : ""
            if status != self.weatherStatus {
                self.weatherStatus = status
            }
            // 关键时间的抓取状态每秒同步一次（每秒读一次偏好设置，代价可以忽略），
            // 这样设置页「诊断」一打开就能看到最新结果，不用手动刷新。
            let keyTimeStatus = KeyTimeStore.shared.diagnosticsSummary()
            if keyTimeStatus != self.keyTimeStatus {
                self.keyTimeStatus = keyTimeStatus
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        clockTimer = timer
    }

    // MARK: - 定位

    /// 首次启动自动申请一次定位权限。
    func requestLocationPermissionIfNeeded() {
        guard !settings.locationPermissionRequested else { return }
        guard location.authorizationStatus == .notDetermined else { return }
        settings.locationPermissionRequested = true
        location.requestPermissionIfNeeded()
    }

    func startGpsTracking(announce: Bool = true) {
        guard location.hasPermission else {
            message = L("msg.noLocationPermission")
            return
        }

        trackingGps = true
        waitingForFix = place.source != .gps

        location.startSampling { [weak self] fix in
            self?.applyFix(fix, announce: announce)
        }

        fixWatchdog?.invalidate()
        let watchdog = Timer(timeInterval: 20, repeats: false) { [weak self] _ in
            guard let self, self.waitingForFix else { return }
            self.message = L("msg.noFix")
            // 一直等不到定位时不要再拿「等定位」当遮罩：会把关键时段的颜色一起藏起来
            // （关键时段是地点无关的，只有「当前是否落在时段内」才依赖经度）。
            self.waitingForFix = false
        }
        RunLoop.main.add(watchdog, forMode: .common)
        fixWatchdog = watchdog
    }

    func stopGpsTracking() {
        location.stopSampling()
        trackingGps = false
        waitingForFix = false
        fixWatchdog?.invalidate()
        fixWatchdog = nil
    }

    private func applyFix(_ fix: CLLocation, announce: Bool) {
        let accuracy = fix.horizontalAccuracy > 0
            ? Lf("gps.accuracy", Int(fix.horizontalAccuracy))
            : L("gps.accuracyUnknown")
        waitingForFix = false

        updatePlace(Place(
            latitude: fix.coordinate.latitude,
            longitude: fix.coordinate.longitude,
            source: .gps,
            label: Lf("gps.label", accuracy)
        ))

        if announce && !announcedFirstFix {
            announcedFirstFix = true
            let current = place
            let text = TimeFormat.coordinates(latitude: current.latitude, longitude: current.longitude)
            message = Lf("msg.followingGps", text)
        }
    }

    // MARK: - 位置

    /// 手动指定坐标（用户明确选的地点）。
    ///
    /// `countryCode` 一定要带上：内置城市都已知国家，靠它直接查 `ZoneTable` 得到法定时区；
    /// 丢了它就只能按经度近似（德里 77.2°E 会被算成 UTC+5，正确是 UTC+5:30）。
    func applyManualPlace(
        latitude: Double,
        longitude: Double,
        label: String,
        countryCode: String? = nil
    ) {
        stopGpsTracking()
        updatePlace(
            Place(
                latitude: latitude,
                longitude: longitude,
                source: .manual,
                label: label,
                countryCode: countryCode
            ),
            userChosen: true
        )
    }

    func usePreset(_ preset: Place) {
        stopGpsTracking()
        // 用 `presetKey` 记住「这是哪个预设城市」：显示名按界面语言取（北京 / 北京 / Beijing），
        // 数据也随语言切换，不需要把某个语言的城市名写进偏好设置。
        updatePlace(
            Place(
                latitude: preset.latitude,
                longitude: preset.longitude,
                source: .manual,
                label: "",
                presetKey: preset.presetKey,
                countryCode: preset.countryCode
            ),
            userChosen: true
        )
    }

    /// - Parameter userChosen: 用户**明确选了这个地点**（常用城市 / 手工坐标）。此时无条件发起一次
    ///   区划名反查，不受「距上次反查不到 5 km」的缓存判定阻挡 —— 否则同城换点或上次反查失败后，
    ///   卡片会一直停在预设城市名上（境外城市尤其明显）。
    private func updatePlace(_ newPlace: Place, userChosen: Bool = false) {
        let previous = place
        settings.place = newPlace
        place = newPlace

        let moved = DistrictNaming.distanceKm(
            previous.latitude, previous.longitude,
            newPlace.latitude, newPlace.longitude
        ) > DistrictNaming.moveThresholdKm

        if moved || userChosen {
            // 换了地点：立刻把上一个地点的区划名撤掉，新名字回来之前卡片显示预设城市名 / 减号。
            // （`cachedNames(for:)` 自带 5 km 校验，跨城时必然得到 nil。）
            districtName = DistrictStore.shared.cachedNames(for: newPlace)
        }
        // 天气缓存与地点绑定：**只显示属于当前地点的数据**（≤5 km 匹配）。
        // 新地点没有缓存时这里拿到 nil，卡片就显示占位符，绝不拿上一个地点的数据顶替；
        // 有缓存就立刻显示、随后由 `refreshData` 在后台按 30 分钟窗口刷新。
        weather = WeatherStore.shared.cached(for: newPlace)

        if moved || userChosen || previous.source != newPlace.source {
            // 切换地点可以立刻触发一次（包括「低精度升级」那条，不受 10 分钟窗口限制）。
            refreshData(forceDistrict: userChosen, ignoreLowPrecisionThrottle: true)
            rescheduleReminders()
        }
    }

    // MARK: - 数据刷新

    /// 天气、区划、关键时间各自带缓存，命中缓存时不会重复联网。
    ///
    /// - Parameters:
    ///   - forceDistrict: 用户刚选了地点，忽略区划缓存的 5 km / 30 天判定，强制反查一次。
    ///   - ignoreLowPrecisionThrottle: 回到前台 / 切换地点时为 true：低精度数据的「升级刷新」
    ///     不受 10 分钟节流限制（用户刚打开 App，值得立刻试着回到 1 小时数据）。
    func refreshData(
        forceWeather: Bool = false,
        forceDistrict: Bool = false,
        ignoreLowPrecisionThrottle: Bool = false
    ) {
        let currentPlace = place
        let started = WeatherStore.shared.requestRefresh(
            place: currentPlace,
            force: forceWeather,
            ignoreLowPrecisionThrottle: ignoreLowPrecisionThrottle
        ) { [weak self] _ in
            guard let self else { return }
            self.weatherLoading = false
            // 请求在飞的时候可能已经换了城市：一律按**当前地点**重新读缓存。
            // `cached(for:)` 自带 ≤5 km 校验，所以 A 城市的天气永远不会被写到 B 城市下。
            self.weather = WeatherStore.shared.cached(for: self.place)
        }
        if started {
            weatherLoading = true
        }
        DistrictStore.shared.requestRefresh(place: currentPlace, force: forceDistrict) { [weak self] names in
            guard let self else { return }
            self.districtName = names
            self.adoptCountryCodeIfNeeded(names.countryCode)
        }
        KeyTimeStore.shared.requestRefresh { [weak self] schedule in
            guard let self else { return }
            self.keyTime = schedule
            self.keyTimeStatus = KeyTimeStore.shared.diagnosticsSummary()
            // 关键时间可能刚更新，重排「进入关键时间」报时。
            self.rescheduleReminders()
        }
    }

    /// 设置页「立即同步关键时间」：绕过节流强行抓一次，并把结果写回界面。
    func refreshKeyTime() {
        KeyTimeStore.shared.refreshNow { [weak self] schedule in
            guard let self else { return }
            self.keyTime = schedule
            self.keyTimeStatus = KeyTimeStore.shared.diagnosticsSummary()
            self.rescheduleReminders()
        }
        keyTimeStatus = KeyTimeStore.shared.diagnosticsSummary()
    }

    /// 区划名反查带回国家码时写进 `place`：标准时区由它决定（`ZoneTable`），
    /// 变了就落盘并立刻重算界面（左栏时间与 UTC 标签、日出日落时刻）。
    private func adoptCountryCodeIfNeeded(_ countryCode: String?) {
        guard let countryCode, countryCode.count == 2 else { return }
        guard place.countryCode != countryCode else { return }
        var updated = place
        updated.countryCode = countryCode
        place = updated
        settings.place = updated
        rescheduleReminders()
    }

    /// 按当前开关把通知重新排一遍（关掉的会先被清掉）。
    func rescheduleReminders() {
        KeyTimeReminder.shared.reschedule(
            place: place,
            schedule: keyTime,
            chimeEnabled: keyTimeChimeEnabled,
            shichenEnabled: remindersEnabled
        )
    }

    // MARK: - 隐藏的诊断入口

    /// 记录一次「点版本号」。连点 7 次（相邻两次 ≤2 秒）后打开设置页的「诊断」区块，
    /// 并 Toast 一句「已开启诊断」。已经打开后不再重复提示。
    ///
    /// 这个开关**不持久化**：`showDiagnostics` 只在内存里，App 重启就回到隐藏。
    func registerVersionTap() {
        guard !showDiagnostics else { return }
        guard diagnosticsUnlock.register() else { return }
        showDiagnostics = true
        message = L("settings.diagnosticsUnlocked")
    }

    // MARK: - 设置

    func setRemindersEnabled(_ enabled: Bool) {
        remindersEnabled = enabled
        settings.remindersEnabled = enabled
        rescheduleReminders()
    }

    func setKeyTimeChimeEnabled(_ enabled: Bool) {
        keyTimeChimeEnabled = enabled
        settings.keyTimeChimeEnabled = enabled
        rescheduleReminders()
    }

    /// 屏幕常亮开关（与 Android 的同名开关一致）：写设置并立即作用于系统。
    func setKeepScreenOn(_ enabled: Bool) {
        keepScreenOn = enabled
        settings.keepScreenOn = enabled
        applyKeepScreenOn()
    }

    /// 主题三态（自动 / 亮色 / 暗色）：写设置并立刻重绘（首页与大卡片的配色一起变）。
    func setThemeMode(_ mode: ThemeMode) {
        themeMode = mode
        settings.themeMode = mode
    }

    /// 把设置同步到系统的「自动熄屏」标志。
    private func applyKeepScreenOn() {
        UIApplication.shared.isIdleTimerDisabled = keepScreenOn
    }

    func setMapStyle(_ style: MapStyle) {
        mapStyle = style
        settings.mapStyle = style
    }

    /// 回到前台时刷新位置、数据与提醒。
    func handleBecameActive() {
        now = Date()
        if trackingGps {
            location.startSampling { [weak self] fix in
                self?.applyFix(fix, announce: false)
            }
        } else if location.hasPermission && place.source != .manual {
            startGpsTracking(announce: false)
        }
        // 回到前台：低精度数据的「升级刷新」立刻试一次（不受 10 分钟节流限制）。
        refreshData(ignoreLowPrecisionThrottle: true)
        rescheduleReminders()
    }
}
