import Foundation

#if canImport(WeatherKit)
import WeatherKit
import CoreLocation
#endif

/// **Apple WeatherKit** 取数封装（原生 SDK，不需要 key）。
///
/// - 坐标：直接用 **WGS-84 原始经纬度**（不做 GCJ-02 偏移 —— 那只是高德底图的事）；
/// - 粒度：`hourlyForecast.forecast` 前 24 小时是 1 小时、之后是 3 小时；
///   这里**只取 1 小时段**（`stepHours == 1`），六格按 1 小时排；
/// - 失败（无 entitlement / 网络错 / 该地区不可用）→ 抛 `Failure`，
///   由 `WeatherStore` 静默回退 Open-Meteo 并把原因写进诊断；
/// - 天气现象：**按 `WeatherCondition` 的描述文字映射到现有 WMO 代码**
///   （不直接引用枚举成员，避免 SDK 版本间成员差异导致编译失败）。
enum WeatherKitProvider {

    enum Failure: Error, Equatable {
        /// 系统版本不够（iOS 16 以下）。
        case unavailableSystem
        /// 本机没有 WeatherKit entitlement / 未授权。
        case notAuthorized
        /// 网络 / 服务端错误。
        case requestFailed(String)

        var displayText: String {
            switch self {
            case .unavailableSystem: return "iOS < 16"
            case .notAuthorized: return "无 entitlement / 未授权"
            case .requestFailed(let reason): return reason
            }
        }
    }

    /// 取一份快照；失败抛 `Failure`（回调都在主线程）。
    static func fetch(
        latitude: Double,
        longitude: Double,
        now: Date = Date(),
        completion: @escaping (Result<WeatherSnapshot, Failure>) -> Void
    ) {
        #if canImport(WeatherKit)
        guard #available(iOS 16.0, *) else {
            completion(.failure(.unavailableSystem))
            return
        }
        // **WGS-84 原始坐标**：WeatherKit 自己处理坐标系，绝不能传 GCJ-02。
        let location = CLLocation(latitude: latitude, longitude: longitude)
        Task {
            do {
                let weather = try await WeatherService.shared.weather(for: location)
                if let snapshot = makeSnapshot(weather: weather, now: now) {
                    completion(.success(snapshot))
                } else {
                    completion(.failure(.requestFailed("逐时数据为空")))
                }
            } catch {
                completion(.failure(classify(error)))
            }
        }
        #else
        _ = (latitude, longitude, now)
        completion(.failure(.unavailableSystem))
        #endif
    }

    #if canImport(WeatherKit)
    @available(iOS 16.0, *)
    private static func makeSnapshot(weather: Weather, now: Date) -> WeatherSnapshot? {
        let current = weather.currentWeather
        // 只保留前 24 条（1 小时段），最多 24 条。
        let oneHour = weather.hourlyForecast.forecast.prefix(24).map { hour in
            WeatherHour(
                epochSeconds: Int(hour.date.timeIntervalSince1970),
                temperatureC: Int(hour.temperature.converted(to: .celsius).value.rounded()),
                code: wmoCode(for: hour.condition)
            )
        }
        guard !oneHour.isEmpty else { return nil }
        return WeatherSnapshot(
            temperatureC: Int(current.temperature.converted(to: .celsius).value.rounded()),
            code: wmoCode(for: current.condition),
            hourly: Array(oneHour),
            source: .weatherKit
        )
    }

    /// `WeatherCondition` → 现有 WMO 代码：**按描述文字匹配**，不引用枚举成员。
    ///
    /// 参数故意写成 **`WeatherKit.WeatherCondition`** 全名：本模块里也有一个
    /// `WeatherCondition`（`TrueSolarTime.WeatherCondition`），不加模块名会被它遮蔽，
    /// 于是把 WeatherKit 的实例传进来就会报「cannot convert ... to expected argument type
    /// 'TrueSolarTime.WeatherCondition'」（build 82 的两个错误就是这么来的）。
    /// 下面再用一个**显式标注的中间变量**把意图钉死：以后误用会直接编译失败。
    @available(iOS 16.0, *)
    static func wmoCode(for condition: WeatherKit.WeatherCondition) -> Int {
        let wkCondition: WeatherKit.WeatherCondition = condition
        return wmoCode(forDescription: String(describing: wkCondition))
    }

    /// 纯字符串映射（便于自检，也不会被 SDK 成员改名影响）。
    static func wmoCode(forDescription description: String) -> Int {
        let text = description.lowercased()
        if text.contains("thunder") || text.contains("storm") { return 95 }
        if text.contains("blizzard") || text.contains("heavy snow") { return 75 }
        if text.contains("snow") || text.contains("flurr") || text.contains("sleet") || text.contains("wintry") { return 71 }
        if text.contains("freezing rain") || text.contains("freezing drizzle") { return 66 }
        if text.contains("heavy rain") { return 65 }
        if text.contains("rain") || text.contains("shower") { return 61 }
        if text.contains("drizzle") { return 51 }
        if text.contains("fog") || text.contains("haze") || text.contains("smoke") { return 45 }
        if text.contains("mostly cloudy") || text.contains("cloud") { return 2 }
        if text.contains("clear") || text.contains("hot") { return 0 }
        return 3
    }

    private static func classify(_ error: Error) -> Failure {
        let text = String(describing: error).lowercased()
        if text.contains("entitlement") || text.contains("not authorized") || text.contains("unauthorized") {
            return .notAuthorized
        }
        return .requestFailed(String(describing: error))
    }
    #endif
}
