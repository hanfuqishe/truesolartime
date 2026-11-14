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
        weather = WeatherStore.shared.cached()
        keyTime = KeyTimeStore.shared.schedule()
        districtName = DistrictStore.shared.cachedNames()
        keepScreenOn = settings.keepScreenOn
        applyKeepScreenOn()
        startClock()
        refreshData()
        rescheduleReminders()
    }

    var snapshot: SolarSnapshot {
        SolarTimeSnapshot.compute(date: now, latitude: place.latitude, longitude: place.longitude)
    }

    // MARK: - 时钟

    private func startClock() {
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.now = Date()
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

    func applyManualPlace(latitude: Double, longitude: Double, label: String) {
        stopGpsTracking()
        updatePlace(Place(latitude: latitude, longitude: longitude, source: .manual, label: label))
    }

    func usePreset(_ preset: Place) {
        applyManualPlace(latitude: preset.latitude, longitude: preset.longitude, label: preset.label)
    }

    private func updatePlace(_ newPlace: Place) {
        let previous = place
        settings.place = newPlace
        place = newPlace

        let moved = abs(newPlace.longitude - previous.longitude) > 0.01 ||
            abs(newPlace.latitude - previous.latitude) > 0.01
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
            self?.districtName = names
        }
        KeyTimeStore.shared.requestRefresh { [weak self] schedule in
            guard let self else { return }
            self.keyTime = schedule
            // 关键时间可能刚更新，重排「进入关键时间」报时。
            self.rescheduleReminders()
        }
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