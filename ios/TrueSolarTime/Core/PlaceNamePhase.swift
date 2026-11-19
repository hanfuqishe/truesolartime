import Foundation

/// 地名解析的**阶段模型**（纯函数，可离线断言）。
///
/// 目标流程（用户确认）：
/// 1. 首帧（同步、零网络）：预设城市 → 预设名；GPS / 手工坐标 → `--`（查询中占位）；有网格缓存 → 缓存名；
/// 2. Apple 反查成功 → 替换首帧文字；
/// 3. Apple 失败 → Nominatim 兜底；两个都失败 → `-`（项目既有规则）。
///
/// 三个占位符的语义必须分清（混用就是又一轮 bug）：
/// - `--`：**查询中**（`PlaceNamePhase.dash`）
/// - `-`：**Apple 与 Nominatim 都失败**（`PlaceNamePhase.hyphen`）
/// - 未知态：另有既有占位（`LocationUnknown` 的 `--`/`-`），不归这里管。
enum PlaceNamePhase {

    /// 查询中占位（半角两个减号）。
    static let dash = "--"
    /// 两者都失败（半角单个减号）。
    static let hyphen = "-"

    /// 反查结果状态。
    enum Result: Equatable {
        case pending
        case ok(DistrictNames)
        case failed(String)
    }

    /// 地名是否「查询中」（决定显示 `--` 还是真实名字 / `-`）。
    ///
    /// 规则（用户要求）：**尚未开始**也必须是 `--`，不是 `-`：
    /// - 已经失败（`didFail`）→ `false`（显示 `-` / 预设名）；
    /// - 正在飞 → `true`；
    /// - 否则看**当前网格**有没有缓存：没缓存 = 尚未开始 → `true`（`--`）；有缓存 → `false`（显示缓存名）。
    static func isQuerying(
        didFail: Bool,
        inFlight: Bool,
        key: String?,
        cachedKeys: Set<String>
    ) -> Bool {
        if didFail { return false }
        if inFlight { return true }
        guard let key else { return true }        // 还没算过网格 = 尚未开始 → `--`
        return !cachedKeys.contains(key)
    }
    /// 首帧要显示什么（`district` 为网格缓存）。
    static func firstFrame(presetName: String?, cached: DistrictNames?) -> String {
        if let cached, !cached.full.isEmpty { return cached.full }
        if let presetName, !presetName.isEmpty { return presetName }
        // GPS / 手工坐标：不知道名字，先给「查询中」占位（不是 `-`）。
        return dash
    }

    /// 并行两路（Apple + Nominatim）合并后的结果：谁成功用谁；**Apple 后到也覆盖**。
    static func winner(apple: Result, osm: Result) -> Result {
        // Apple 成功优先（更准），哪怕它比 Nominatim 晚回来。
        if case .ok = apple { return apple }
        if case .ok = osm { return osm }
        switch (apple, osm) {
        case (.pending, _), (_, .pending):
            // 还有一路没回来：继续查询中。
            return .pending
        case (.failed(let a), .failed(let o)):
            return .failed("\(a) / \(o)")
        default:
            return .pending
        }
    }

    /// 最终显示文字：成功 → 名字；仍在查 → `--`；都失败 → `-`。
    static func text(_ result: Result, presetName: String? = nil) -> String {
        switch result {
        case .ok(let names):
            return names.full
        case .failed:
            // 预设城市失败时仍显示预设名（既有规则），GPS / 手工才是 `-`。
            if let presetName, !presetName.isEmpty { return presetName }
            return hyphen
        case .pending:
            if let presetName, !presetName.isEmpty { return presetName }
            return dash
        }
    }

    /// 诊断一行：`黃浦區 · Apple` / `… · Nominatim` / `… · 缓存` / `-- 查詢中（Apple）` / `- 均失敗（…）`。
    static func diagnostics(result: Result, provider: String?) -> String {
        switch result {
        case .ok(let names):
            let source = provider ?? "Apple"
            return "\(names.full) · \(source)"
        case .pending:
            return "\(dash) 查詢中（Apple）"
        case .failed(let reason):
            return "\(hyphen) 均失敗（\(reason)）"
        }
    }
}
