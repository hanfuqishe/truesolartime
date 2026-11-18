import Foundation

/// 轻量的 UserDefaults 封装，字段与 Android 版一致。
struct AppSettings {

    private enum Key {
        static let latitude = "latitude"
        static let longitude = "longitude"
        static let placeSource = "place_source"
        static let placeLabel = "place_label"
        static let placePresetKey = "place_preset_key"
        static let placeCountry = "place_country"
        static let reminders = "shichen_reminders"
        static let keyTimeChime = "keytime_chime"
        static let mapStyle = "map_style"
        static let locationAsked = "location_permission_requested"
        static let keepScreenOn = "keep_screen_on"
        /// 主题三态（自动 / 亮色 / 暗色），存 `ThemeMode.rawValue`。
        static let themeMode = "theme_mode"
        /// 「跟随 GPS」的**意图**（默认 true）。注意：这是「想跟随」，不是「已经有定位」——
        /// 未知态 = 意图为 true 且拿不到有效定位。
        static let followGps = "follow_gps"
        /// 天气数据源（自动 / WeatherKit / Open-Meteo）。
        static let weatherSource = "weather_source"
    }

    private let defaults = UserDefaults.standard

    /// 天气数据源（默认自动：WeatherKit → Open-Meteo → 7Timer）。
    var weatherSource: WeatherSourceSetting {
        get { WeatherSourceSetting.of(id: defaults.string(forKey: Key.weatherSource)) }
        set { defaults.set(newValue.rawValue, forKey: Key.weatherSource) }
    }

    /// 跟随 GPS 的意图（持久化）。预设城市 / 手动坐标会把它置 false。
    var followGps: Bool {
        get {
            guard defaults.object(forKey: Key.followGps) != nil else { return true }
            return defaults.bool(forKey: Key.followGps)
        }
        set { defaults.set(newValue, forKey: Key.followGps) }
    }

    var place: Place {
        get {
            let latitude = defaults.object(forKey: Key.latitude) as? Double
            let longitude = defaults.object(forKey: Key.longitude) as? Double
            let source = (defaults.string(forKey: Key.placeSource)).flatMap(PlaceSource.init(rawValue:)) ?? .preset
            let label = defaults.string(forKey: Key.placeLabel)
            let presetKey = defaults.string(forKey: Key.placePresetKey)
            let country = defaults.string(forKey: Key.placeCountry)
            return Place(
                latitude: latitude ?? Place.shanghai.latitude,
                longitude: longitude ?? Place.shanghai.longitude,
                source: source,
                label: label ?? "",
                presetKey: presetKey,
                countryCode: country
            )
        }
        nonmutating set {
            defaults.set(newValue.latitude, forKey: Key.latitude)
            defaults.set(newValue.longitude, forKey: Key.longitude)
            defaults.set(newValue.source.rawValue, forKey: Key.placeSource)
            defaults.set(newValue.label, forKey: Key.placeLabel)
            defaults.set(newValue.presetKey, forKey: Key.placePresetKey)
            defaults.set(newValue.countryCode, forKey: Key.placeCountry)
        }
    }

    var remindersEnabled: Bool {
        get { defaults.bool(forKey: Key.reminders) }
        nonmutating set { defaults.set(newValue, forKey: Key.reminders) }
    }

    /// 「进入关键时间」报时开关。
    var keyTimeChimeEnabled: Bool {
        get { defaults.bool(forKey: Key.keyTimeChime) }
        nonmutating set { defaults.set(newValue, forKey: Key.keyTimeChime) }
    }

    var mapStyle: MapStyle {
        get { MapStyle(rawValue: defaults.string(forKey: Key.mapStyle) ?? "") ?? .auto }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.mapStyle) }
    }

    /// 屏幕常亮：应用在前台时不自动熄屏（与 Android 的「屏幕常亮」开关一致）。
    var keepScreenOn: Bool {
        get { defaults.bool(forKey: Key.keepScreenOn) }
        nonmutating set { defaults.set(newValue, forKey: Key.keepScreenOn) }
    }

    /// 主题：自动（按日出日落）/ 亮色 / 暗色。默认「自动」。
    ///
    /// 与「屏幕常亮」存在同一片区（设置页的「屏幕」分组），重启后保留。
    var themeMode: ThemeMode {
        get { ThemeMode.fromStorage(defaults.string(forKey: Key.themeMode)) }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.themeMode) }
    }

    /// 定位权限只自动申请一次，避免每次启动都弹窗。
    var locationPermissionRequested: Bool {
        get { defaults.bool(forKey: Key.locationAsked) }
        nonmutating set { defaults.set(newValue, forKey: Key.locationAsked) }
    }
}
