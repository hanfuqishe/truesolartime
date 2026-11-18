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
    /// 「跟随 GPS」的**意图**（持久化，默认 true）。注意这不是「已经有定位」。
    @Published private(set) var followGps: Bool
    /// 本次会话是否拿到过**有效定位**（未授权 / 20 秒看门狗超时后为 false）。
    @Published private(set) var hasValidFix: Bool
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

    /// `AppSettings` 是 **struct**：要给它的属性赋值（如 `settings.followGps = …`）必须用 `var`。
    private var settings = AppSettings()
    private let location = LocationProvider()
    private var clockTimer: Timer?
    private var fixWatchdog: Timer?
    private var announcedFirstFix = false
    /// 「连点 7 次版本号」的计数器（纯逻辑在 `Core/DiagnosticsUnlock.swift`）。
    private var diagnosticsUnlock = DiagnosticsUnlock()

    init() {
        place = settings.place
        followGps = settings.followGps
        hasValidFix = settings.place.source == .gps && settings.followGps
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

    /// 当前是否「定位不可用（未知态）」：跟随 GPS 的意图成立、但拿不到有效定位。
    var isLocationUnknown: Bool {
        LocationUnknown.isUnknown(followGps: followGps, hasValidFix: hasValidFix)
    }

    var snapshot: SolarSnapshot {
        // 未知态：标准时间按**系统时区**（偏移显式传入，负偏移照常生效），太阳量由界面隐藏。
        if isLocationUnknown {
            return LocationUnknown.snapshot(date: now, systemOffsetSeconds: TimeZone.current.secondsFromGMT(for: now))
        }
        return SolarTimeSnapshot.compute(date: now, latitude: place.latitude, longitude: place.longitude, countryCode: place.countryCode)
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
            // 底图回退后每 5 分钟探测一次 OSM（`tick` 内部判定，到点才真的发请求）。
            BasemapController.shared.tick()
            // 降级到 7Timer! 之后要「尽快切回主源」：每秒判一次该不该试主源。
            // 真正的间隔由退避表决定（前台 60 → 120 → 300 秒、后台 10 分钟），
            // 所以这里不会真的每秒发请求；切回主源后这条自动失效。
            if WeatherStore.shared.source.isLowPrecision {
                self.refreshWeather()
            }
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

    /// 启动 / 回前台时的「恢复定位」：**只在用户本来就打算跟随时**才启动。
    ///
    /// 不能直接调 `startGpsTracking`：那个方法会写跟随意图（`followGps = true`），
    /// 预设城市 / 手动坐标的用户会在启动时被翻成「跟随 GPS」，进而误进未知态。
    func resumeGpsIfNeeded(announce: Bool = false) {
        guard followGps else { return }
        startGpsTracking(announce: announce)
    }

    /// 复核系统定位权限（启动 / 回前台都调）：撤销或拒绝 → 没有有效定位。
    ///
    /// `notDetermined`（还没弹过系统弹窗）不算撤销，避免首启就闪一下未知态。
    func syncLocationPermission() {
        guard followGps else { return }
        guard location.authorizationStatus != .notDetermined else { return }
        if !location.hasPermission {
            hasValidFix = false
        }
    }

    func startGpsTracking(announce: Bool = true) {
        // 状态转移在 Core 里（`LocationUnknown.startFollowing`），**先落意图、再提示**：
        // 无权限时也要把 followGps 记成 true，否则界面永远进不了「定位不可用」未知态
        // （build 70 的 bug：`guard ... return` 把后面的 setFollowGps 挡掉了）。
        let next = LocationUnknown.startFollowing(
            hasPermission: location.hasPermission,
            hasCurrentFix: hasValidFix
        )
        setFollowGps(next.followGps)
        hasValidFix = next.hasValidFix
        trackingGps = next.trackingGps
        waitingForFix = next.waitingForFix

        guard location.hasPermission else {
            message = L("msg.noLocationPermission")
            return
        }

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
            // 看门狗超时 = 这次没拿到有效定位 → 若仍在「跟随 GPS」，界面进入未知态。
            self.hasValidFix = false
        }
        RunLoop.main.add(watchdog, forMode: .common)
        fixWatchdog = watchdog
    }

    /// 设置「跟随 GPS 的意图」并落盘（预设城市 / 手工坐标会关掉它）。
    private func setFollowGps(_ value: Bool) {
        guard followGps != value else { return }
        followGps = value
        settings.followGps = value
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
        hasValidFix = true

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
        setFollowGps(false)
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
        setFollowGps(false)
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
            // **先清空，再只看同一地点的缓存**：
            // 换城市 / 手工输入新坐标时，上一个城市的地名一秒都不许留在卡片上
            // （曾经出现过「手动输入埃及坐标，地名还显示北京」）。
            // `cachedNames(for:)` 现在要求缓存里**存过坐标**且相距 ≤5 km，否则返回 nil。
            districtName = DistrictStore.shared.cachedNames(for: newPlace)
        }
        // 天气缓存与地点绑定：**只显示属于当前地点的数据**（≤5 km 匹配）。
        // 新地点没有缓存时这里拿到 nil，卡片就显示占位符，绝不拿上一个地点的数据顶替；
        // 有缓存就立刻显示、随后由 `refreshData` 在后台按 30 分钟窗口刷新。
        weather = WeatherStore.shared.cached(for: newPlace)

        if moved || userChosen || previous.source != newPlace.source {
            // 切换地点可以立刻触发一次（包括「低精度升级」那条，不受 60 秒窗口限制）。
            refreshData(forceDistrict: userChosen, ignoreLowPrecisionThrottle: true)
            rescheduleReminders()
        }
    }

    // MARK: - 数据刷新

    /// 天气、区划、关键时间各自带缓存，命中缓存时不会重复联网。
    ///
    /// - Parameters:
    ///   - forceDistrict: 用户刚选了地点，忽略区划缓存的 5 km / 30 天判定，强制反查一次。
    ///   - ignoreLowPrecisionThrottle: 回到前台 / 切换地点时为 true：降级后「重试主源」的退避窗口
    ///     直接跳过（用户刚打开 App，值得立刻试着回到 1 小时数据）。
    func refreshData(
        forceWeather: Bool = false,
        forceDistrict: Bool = false,
        ignoreLowPrecisionThrottle: Bool = false
    ) {
        let currentPlace = place
        refreshWeather(force: forceWeather, ignoreLowPrecisionThrottle: ignoreLowPrecisionThrottle)
        DistrictStore.shared.requestRefresh(place: currentPlace, force: forceDistrict) { [weak self] names in
            guard let self else { return }
            // 反查失败 → names 为 nil → 名字清成 nil（卡片显示「-」），
            // **绝不保留上一个城市的地名**（既定产品决策）。
            self.districtName = names
            self.adoptCountryCodeIfNeeded(names?.countryCode)
        }
        KeyTimeStore.shared.requestRefresh { [weak self] schedule in
            guard let self else { return }
            self.keyTime = schedule
            self.keyTimeStatus = KeyTimeStore.shared.diagnosticsSummary()
            // 关键时间可能刚更新，重排「进入关键时间」报时。
            self.rescheduleReminders()
        }
    }

    /// 只刷新天气（不牵动区划名与关键时间）。
    ///
    /// 逐时行拿到 7Timer! 数据时，主源的「秒级判定 + 退避窗口」走的就是这条路 ——
    /// 每判定一次都去反查区划名 / 抓关键时间会白白多打网络。
    private func refreshWeather(force: Bool = false, ignoreLowPrecisionThrottle: Bool = false) {
        let started = WeatherStore.shared.requestRefresh(
            place: place,
            force: force,
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
    }

    /// 前后台变化（由 `ContentView` 的 `scenePhase` 驱动）。
    ///
    /// 前台：立刻试一次主源（不等计时器）；后台：退避窗口退到 10 分钟（`WeatherStore.setForeground`），
    /// 不参与 60 秒轮询。
    func setAppActive(_ active: Bool) {
        WeatherStore.shared.setForeground(active)
        if active {
            handleBecameActive()
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
        // 系统设置里改过定位权限 → 这里复核一次（撤销权限立刻进未知态，重新授权就继续定位）。
        syncLocationPermission()
        if trackingGps {
            location.startSampling { [weak self] fix in
                self?.applyFix(fix, announce: false)
            }
        } else if location.hasPermission && place.source != .manual {
            resumeGpsIfNeeded(announce: false)
        }
        // 回到前台：降级后「重试主源」立刻试一次（跳过退避窗口，不等计时器）。
        refreshData(ignoreLowPrecisionThrottle: true)
        rescheduleReminders()
    }
}
