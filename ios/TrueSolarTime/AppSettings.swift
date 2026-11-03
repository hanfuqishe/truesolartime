import Foundation

/// 轻量的 UserDefaults 封装，字段与 Android 版一致。
struct AppSettings {

    private enum Key {
        static let latitude = "latitude"
        static let longitude = "longitude"
        static let placeSource = "place_source"
        static let placeLabel = "place_label"
        static let reminders = "shichen_reminders"
        static let mapStyle = "map_style"
        static let locationAsked = "location_permission_requested"
    }

    private let defaults = UserDefaults.standard

    var place: Place {
        get {
            let latitude = defaults.object(forKey: Key.latitude) as? Double
            let longitude = defaults.object(forKey: Key.longitude) as? Double
            let source = (defaults.string(forKey: Key.placeSource)).flatMap(PlaceSource.init(rawValue:)) ?? .preset
            let label = defaults.string(forKey: Key.placeLabel)
            return Place(
                latitude: latitude ?? Place.shanghai.latitude,
                longitude: longitude ?? Place.shanghai.longitude,
                source: source,
                label: label ?? Place.shanghai.label
            )
        }
        nonmutating set {
            defaults.set(newValue.latitude, forKey: Key.latitude)
            defaults.set(newValue.longitude, forKey: Key.longitude)
            defaults.set(newValue.source.rawValue, forKey: Key.placeSource)
            defaults.set(newValue.label, forKey: Key.placeLabel)
        }
    }

    var remindersEnabled: Bool {
        get { defaults.bool(forKey: Key.reminders) }
        nonmutating set { defaults.set(newValue, forKey: Key.reminders) }
    }

    var mapStyle: MapStyle {
        get { MapStyle(rawValue: defaults.string(forKey: Key.mapStyle) ?? "") ?? .auto }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.mapStyle) }
    }

    /// 定位权限只自动申请一次，避免每次启动都弹窗。
    var locationPermissionRequested: Bool {
        get { defaults.bool(forKey: Key.locationAsked) }
        nonmutating set { defaults.set(newValue, forKey: Key.locationAsked) }
    }
}
