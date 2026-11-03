import Combine
import CoreLocation
import Foundation

/// 定位采样：每 60 秒请求一次单次定位，避免持续定位带来的耗电与后台权限问题。
/// 所有回调都在主线程（CLLocationManager 在主线程创建，Timer 也挂在主 RunLoop）。
final class LocationProvider: NSObject, ObservableObject {

    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var lastLocation: CLLocation?

    private let manager = CLLocationManager()
    private var timer: Timer?
    private var onFix: ((CLLocation) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authorizationStatus = manager.authorizationStatus
    }

    var hasPermission: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    func requestPermissionIfNeeded() {
        guard authorizationStatus == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }

    /// 开始每分钟采样；启动时立即请求一次。
    func startSampling(interval: TimeInterval = 60, onFix: @escaping (CLLocation) -> Void) {
        self.onFix = onFix
        guard hasPermission else { return }

        timer?.invalidate()
        requestSample()

        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.requestSample()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stopSampling() {
        timer?.invalidate()
        timer = nil
        onFix = nil
    }

    private func requestSample() {
        guard hasPermission else { return }
        manager.requestLocation()
    }
}

extension LocationProvider: CLLocationManagerDelegate {

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if hasPermission {
            requestSample()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        lastLocation = location
        onFix?(location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // 单次定位失败时等待下一个采样周期即可，无需打断界面。
    }
}