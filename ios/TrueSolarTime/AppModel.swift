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
    /// 天气取不到时给界面看的说明（成功时为空串）。
    @Published private(set) var weatherStatus: String = ""
    @Published var message: String?

    private let settings = AppSettings()
    private let location = LocationProvider()
    private var clockTimer: Timer?
    private var fixWatchdog: Timer?
    private var announcedFirstFix = false

    init() {
        place = settings.place
        remindersEnabled = settings.remindersEnabled
        keyTimeChimeEnabled = settings.keyTimeChimeEnabled
        mapStyle = settings.mapStyle
        weather = WeatherStore.shared.cached(for: settings.place)
        keyTime = KeyTimeStore.shared.schedule()
        districtName = DistrictStore.shared.cachedNames(for: settings.place)
        keepScreenOn = settings.keepScreenOn
        applyKeepScreenOn()
        startClock()
        refreshData()
        rescheduleReminders()
    }

    var snapshot: SolarSnapshot {
        SolarTimeSnapshot.compute(date: now, latitude: place.latitude, longitude: place.longitude, countryCode: place.countryCode)
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
            message = "没有定位权限，请在系统设置中允许，或手动输入经纬度"
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
            self.message = "尚未收到定位结果，可能需要在空旷处等待；也可手动设置经纬度"
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
        let accuracy = fix.horizontalAccuracy > 0 ? "精度 \(Int(fix.horizontalAccuracy)) 米" : "精度未知"
        waitingForFix = false

        updatePlace(Place(
            latitude: fix.coordinate.latitude,
            longitude: fix.coordinate.longitude,
            source: .gps,
            label: "GPS · \(accuracy)"
        ))

        if announce && !announcedFirstFix {
            announcedFirstFix = true
            let current = place
            let text = TimeFormat.coordinates(latitude: current.latitude, longitude: current.longitude)
            message = "已跟随 GPS 定位（\(text)），每分钟更新"
        }
    }

    // MARK: - 位置

    /// 手动指定坐标。
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
        updatePlace(Place(
            latitude: latitude,
            longitude: longitude,
            source: .manual,
            label: label,
            countryCode: countryCode
        ))
    }

    func usePreset(_ preset: Place) {
        applyManualPlace(
            latitude: preset.latitude,
            longitude: preset.longitude,
            label: preset.label,
            countryCode: preset.countryCode
        )
    }

    private func updatePlace(_ newPlace: Place) {
        let previous = place
        settings.place = newPlace
        place = newPlace

        let moved = DistrictNaming.distanceKm(
            previous.latitude, previous.longitude,
            newPlace.latitude, newPlace.longitude
        ) > DistrictNaming.moveThresholdKm

        if moved {
            // 换了城市：立刻把上一个地点的地名/天气撤掉，别让卡片挂着旧地址。
            // 新地址查到之前，`districtName` 为 nil，卡片退回显示城市名（preset 的 label）。
            districtName = DistrictStore.shared.cachedNames(for: newPlace)
            weather = WeatherStore.shared.cached(for: newPlace)
        }

        if moved || previous.source != newPlace.source {
            refreshData()
            rescheduleReminders()
        }
    }

    // MARK: - 数据刷新

    /// 天气、区划、关键时间各自带缓存，命中缓存时不会重复联网。
    func refreshData(forceWeather: Bool = false) {
        let currentPlace = place
        WeatherStore.shared.requestRefresh(place: currentPlace, force: forceWeather) { [weak self] snapshot in
            self?.weather = snapshot
        }
        DistrictStore.shared.requestRefresh(place: currentPlace) { [weak self] names in
            guard let self else { return }
            self.districtName = names
            self.adoptCountryCodeIfNeeded(names.countryCode)
        }
        KeyTimeStore.shared.requestRefresh { [weak self] schedule in
            guard let self else { return }
            self.keyTime = schedule
            // 关键时间可能刚更新，重排「进入关键时间」报时。
            self.rescheduleReminders()
        }
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
        refreshData()
        rescheduleReminders()
    }
}