import Foundation
import SwiftUI

#if canImport(WeatherKit)
import WeatherKit
#endif

/// WeatherKit 的**官方署名**（标识图 + 法律声明页），带缓存。
///
/// - 取法：`try await WeatherService.shared.attribution`，拿到 `legalPageURL` 与
///   `combinedMarkLightURL` / `combinedMarkDarkURL`；
/// - 缓存：**进程内一次** + `UserDefaults` 24 小时（Apple 的 URL 很稳定，没必要每次开屏都拉）；
/// - 失败：保持 `nil`，由 `WeatherAttributionPresentation.choose` 退化成文字（Apple 允许）。
@MainActor
final class WeatherAttributionStore: ObservableObject {

    static let shared = WeatherAttributionStore()

    private enum Key {
        static let light = "weatherkit.mark.light"
        static let dark = "weatherkit.mark.dark"
        static let legal = "weatherkit.legal"
        static let fetchedAt = "weatherkit.attribution.at"
    }

    private let defaults = UserDefaults.standard
    /// 缓存有效期：24 小时。
    static let cacheTTLSeconds: TimeInterval = 24 * 60 * 60

    private var lightURL: String?
    private var darkURL: String?
    private var legalURL: String?
    /// 是否已经在飞（一次就够）。
    private var loading = false
    /// 拉过一次就置 true，避免反复重试。
    private var attempted = false
    /// 加载状态（诊断一行用）。
    private(set) var status: WeatherAttributionStatus = .notRequested

    private init() {
        loadFromDisk()
    }

    /// 诊断一行：状态 + 是否有标识图 URL。
    func diagnosticsSummary() -> String {
        status.summary(hasMarkURL: lightURL != nil || darkURL != nil)
    }

    private func loadFromDisk() {
        let fetchedAt = defaults.double(forKey: Key.fetchedAt)
        guard fetchedAt > 0, Date().timeIntervalSince1970 - fetchedAt < Self.cacheTTLSeconds else { return }
        lightURL = defaults.string(forKey: Key.light)
        darkURL = defaults.string(forKey: Key.dark)
        legalURL = defaults.string(forKey: Key.legal)
    }

    private func saveToDisk() {
        defaults.set(lightURL, forKey: Key.light)
        defaults.set(darkURL, forKey: Key.dark)
        defaults.set(legalURL, forKey: Key.legal)
        defaults.set(Date().timeIntervalSince1970, forKey: Key.fetchedAt)
    }

    /// 当前署名该怎么显示（UI 直接用）。
    func presentation(source: WeatherSource, isDark: Bool) -> WeatherAttributionPresentation {
        WeatherAttributionPresentation.choose(
            source: source,
            markLightURL: lightURL,
            markDarkURL: darkURL,
            legalURL: legalURL,
            isDark: isDark
        )
    }

    /// 首次需要时拉一次（异步，失败静默）。
    func loadIfNeeded() {
        guard !attempted else { return }
        attempted = true
        #if canImport(WeatherKit)
        guard #available(iOS 16.0, *) else { return }
        guard !loading else { return }
        loading = true
        Task { [weak self] in
            defer { self?.loading = false }
            do {
                let attribution = try await WeatherService.shared.attribution
                self?.lightURL = attribution.combinedMarkLightURL.absoluteString
                self?.darkURL = attribution.combinedMarkDarkURL.absoluteString
                self?.legalURL = attribution.legalPageURL.absoluteString
                self?.status = .loaded
                self?.saveToDisk()
                self?.objectWillChange.send()
            } catch {
                // 静默：退化成文字署名（Apple 允许），但把原因记进诊断。
                let ns = error as NSError
                self?.status = .failed("\(ns.domain) \(ns.code)")
                self?.objectWillChange.send()
            }
        }
        #endif
    }
}
