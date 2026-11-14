import Foundation

/// 应用界面语言。
///
/// iOS 版目前是**纯中文界面**（所有文案硬编码在 SwiftUI 里），所以区划名也应当固定按中文反查——
/// 之前用 `Locale.current`（跟随系统语言）时，系统是英文的手机就会反查出
/// 「Dongcheng District, Beijing」，与界面上的中文对不上。
///
/// 以后接入多语言（String Catalog / Localizable.strings）时，把 `code`
/// 改成 `Bundle.main.preferredLocalizations.first` 即可，其余调用点不用动。
enum AppLanguage {

    /// 当前界面语言代码，例如 "zh-Hans" / "en"。
    static let code = "zh-Hans"

    static var prefersChinese: Bool {
        DistrictNaming.prefersChinese(code)
    }

    /// 交给 `CLGeocoder` 的 preferredLocale：让系统直接返回对应语言的地名。
    static var geocoderLocale: Locale {
        Locale(identifier: prefersChinese ? "zh_CN" : "en_US")
    }
}
