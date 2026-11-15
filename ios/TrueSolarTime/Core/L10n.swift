import Foundation

/// 三语取词。key 与 `Resources/<lang>.lproj/Localizable.strings` 一一对应。
///
/// App 运行时按当前语言载入对应的 `.lproj`；自检（命令行、没有 .lproj）用
/// `LocalizationCatalog` 直接从源码目录读表，所以三语都能离线测。
enum L10n {

    /// 自检注入的表（语言 code → key → 文案）；为 nil 时走 bundle。
    private static var injectedTables: [String: [String: String]]?

    /// 当前语言（跟随系统，见 `AppLanguage`）。
    static var language: AppLanguage.Language { AppLanguage.current }

    /// 取当前语言的文案；缺翻译时退英文，最后退 key 本身（便于发现漏翻）。
    static func t(_ key: String) -> String {
        t(key, language: language)
    }

    static func t(_ key: String, language: AppLanguage.Language) -> String {
        if let value = lookup(key, language: language) { return value }
        if language != .english, let value = lookup(key, language: .english) { return value }
        return key
    }

    /// 带格式参数的文案（`%d` / `%@` / `%.1f` …）。
    static func f(_ key: String, _ arguments: [CVarArg]) -> String {
        String(format: t(key), arguments: arguments)
    }

    static func f(_ key: String, language: AppLanguage.Language, _ arguments: [CVarArg]) -> String {
        String(format: t(key, language: language), arguments: arguments)
    }

    /// 自检用：把源码目录里的三份表注入进来（`nil` 表示回到 bundle）。
    static func useTablesForTesting(_ tables: [String: [String: String]]?) {
        injectedTables = tables
    }

    private static func lookup(_ key: String, language: AppLanguage.Language) -> String? {
        if let tables = injectedTables, let value = tables[language.code]?[key], !value.isEmpty {
            return value
        }
        if let bundle = bundle(for: language) {
            let value = bundle.localizedString(forKey: key, value: "", table: nil)
            if !value.isEmpty { return value }
        }
        return nil
    }

    private static var bundleCache: [String: Bundle] = [:]

    private static func bundle(for language: AppLanguage.Language) -> Bundle? {
        if let cached = bundleCache[language.code] { return cached }
        guard
            let path = Bundle.main.path(forResource: language.code, ofType: "lproj"),
            let bundle = Bundle(path: path)
        else { return nil }
        bundleCache[language.code] = bundle
        return bundle
    }
}

/// App 里取词的简写（`L("hero.trueSolar")`）。
func L(_ key: String) -> String { L10n.t(key) }

/// 带格式参数的取词（`Lf("keytime.st.bands", 3, "15:00-17:00")`）。
func Lf(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: L10n.t(key), arguments: arguments)
}

/// 三份 `.strings` 的解析与一致性检查。
///
/// App 运行时不用它：自检（`Scripts/main.swift`）和 `Scripts/check-localization` 共用同一套规则，
/// 免得两边判断标准不一致。
enum LocalizationCatalog {

    /// 必须齐备的三种语言（与 `.lproj` 目录同名）。
    static let languages = ["zh-Hans", "zh-Hant", "en"]

    /// 简体里不该出现的繁体专用字。
    ///
    /// 只收「简体写法与之不同、且本项目确实可能用到」的字，避免把两体同形的字误判
    /// （例如「台 / 臺」「于 / 於」这类两可写法不收）。
    static let traditionalOnlyCharacters = Array(
        "設資網預連螢檔軟體訊質時後發開關閉應週點線鐘曆級別選擇確認錯誤載儲讀顯隱數據溫濕風雲陰霧陣陽間標準護"
    )

    /// 繁體里不该出现的简体专用字（上面那张表的简体对应写法）。
    static let simplifiedOnlyCharacters = Array(
        "设资网预连萤档软体讯质时后发开关闭应周点线钟历级别选择确认错误载储读显隐数据温湿风云阴雾阵阳间标准护"
    )

    // MARK: - 解析

    /// 解析 `.strings`：`"key" = "value";`，支持 `/* … */` 与 `//` 注释。
    static func parse(_ text: String) -> [String: String] {
        let withoutBlockComments = stripBlockComments(text)
        let pattern = "\"((?:[^\"\\\\]|\\\\.)*)\"\\s*=\\s*\"((?:[^\"\\\\]|\\\\.)*)\"\\s*;"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [:] }
        let ns = withoutBlockComments as NSString
        var table: [String: String] = [:]
        regex.enumerateMatches(in: withoutBlockComments, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match, match.numberOfRanges == 3 else { return }
            let key = unescape(ns.substring(with: match.range(at: 1)))
            let value = unescape(ns.substring(with: match.range(at: 2)))
            table[key] = value
        }
        return table
    }

    /// 去掉 `/* … */` 块注释（可以跨行），保留行内其它内容。
    private static func stripBlockComments(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: "/\\*.*?\\*/",
            options: [.dotMatchesLineSeparators]
        ) else { return text }
        let ns = text as NSString
        return regex.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: ns.length), withTemplate: "")
    }

    /// 从源码目录读三份表：`<root>/TrueSolarTime/Resources/<lang>.lproj/Localizable.strings`。
    static func load(root: URL) -> [String: [String: String]] {
        var tables: [String: [String: String]] = [:]
        for language in languages {
            let url = root
                .appendingPathComponent("TrueSolarTime")
                .appendingPathComponent("Resources")
                .appendingPathComponent("\(language).lproj")
                .appendingPathComponent("Localizable.strings")
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            tables[language] = parse(text)
        }
        return tables
    }

    /// 扫描源码里用到的 key（`L(key)` / `Lf(key, …)` / `L10n.t(key, …)` 这类调用）。
    static func keysUsedInSources(root: URL) -> (keys: Set<String>, unreadable: Bool) {
        var keys = Set<String>()
        var unreadable = false
        let pattern = "\\b(?:L|Lf|L10n\\.t|L10n\\.f)\\(\\s*\"([^\"]+)\""
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return (keys, true) }
        let base = root.appendingPathComponent("TrueSolarTime")
        guard let enumerator = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else {
            return (keys, true)
        }
        var anyFile = false
        for case let url as URL in enumerator {
            guard url.pathExtension == "swift" else { continue }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                unreadable = true
                continue
            }
            anyFile = true
            let ns = text as NSString
            regex.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
                guard let match, match.numberOfRanges == 2 else { return }
                keys.insert(ns.substring(with: match.range(at: 1)))
            }
        }
        return (keys, unreadable || !anyFile)
    }

    // MARK: - 检查

    struct Report {
        var errors: [String] = []
        var keyCount = 0
        var counts: [String: Int] = [:]
        var isOK: Bool { errors.isEmpty }
    }

    static func check(_ tables: [String: [String: String]]) -> Report {
        var report = Report()
        for language in languages {
            let count = tables[language]?.count ?? 0
            report.counts[language] = count
            if count == 0 {
                report.errors.append("\(language): 缺少整份 strings 表（或解析不到任何 key）")
            }
        }

        // 1) key 集合必须完全一致
        var union = Set<String>()
        for language in languages { union.formUnion((tables[language] ?? [:]).keys) }
        report.keyCount = union.count
        for language in languages {
            let keys = Set((tables[language] ?? [:]).keys)
            let missing = union.subtracting(keys).sorted()
            let extra = keys.subtracting(union).sorted()
            if !missing.isEmpty {
                report.errors.append("\(language): 缺少 \(missing.count) 个 key —— \(missing.joined(separator: ", "))")
            }
            if !extra.isEmpty {
                report.errors.append("\(language): 多出 \(extra.count) 个 key —— \(extra.joined(separator: ", "))")
            }
        }

        // 2) 每条都非空、不是 key 本身
        for language in languages {
            for (key, value) in (tables[language] ?? [:]).sorted(by: { $0.key < $1.key }) {
                if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    report.errors.append("\(language):「\(key)」的文案为空")
                } else if value == key {
                    report.errors.append("\(language):「\(key)」的文案还是 key 本身（没翻译）")
                }
            }
        }

        // 3) 三语的格式参数必须一致（否则 %d 对不上会崩或显示错位）
        for key in union.sorted() {
            let signatures = languages.map { language in
                formatSignature(tables[language]?[key] ?? "")
            }
            if Set(signatures).count > 1 {
                let detail = zip(languages, signatures).map { "\($0): \($1)" }.joined(separator: " / ")
                report.errors.append("「\(key)」的格式参数不一致 —— \(detail)")
            }
        }

        // 4) 简体里不能出现繁体专用字
        report.errors.append(contentsOf: characterIssues(
            tables["zh-Hans"] ?? [:],
            language: "zh-Hans",
            forbidden: traditionalOnlyCharacters,
            description: "繁体专用字"
        ))

        // 5) 繁體里不能出现简体专用字
        report.errors.append(contentsOf: characterIssues(
            tables["zh-Hant"] ?? [:],
            language: "zh-Hant",
            forbidden: simplifiedOnlyCharacters,
            description: "简体专用字"
        ))

        // 6) 英文里不能有 CJK（汉字、CJK 标点、全角符号）
        for (key, value) in (tables["en"] ?? [:]).sorted(by: { $0.key < $1.key }) {
            if let bad = value.first(where: isCJK) {
                report.errors.append("en:「\(key)」里出现 CJK 字符「\(bad)」")
            }
        }

        return report
    }

    private static func characterIssues(
        _ table: [String: String],
        language: String,
        forbidden: [Character],
        description: String
    ) -> [String] {
        let forbiddenSet = Set(forbidden)
        var issues: [String] = []
        for (key, value) in table.sorted(by: { $0.key < $1.key }) {
            let found = Set(value.filter { forbiddenSet.contains($0) })
            if !found.isEmpty {
                let list = found.map(String.init).sorted().joined(separator: "、")
                issues.append("\(language):「\(key)」里出现\(description)「\(list)」")
            }
        }
        return issues
    }

    /// 格式参数的「指纹」：把 `%d`、`%@`、`%02d`、`%.1f` 之类按出现顺序排好。
    static func formatSignature(_ value: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "%[0-9.\\-+']*[@a-zA-Z]") else { return "" }
        let ns = value as NSString
        var tokens: [String] = []
        regex.enumerateMatches(in: value, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match else { return }
            tokens.append(ns.substring(with: match.range))
        }
        return tokens.joined(separator: ",")
    }

    /// 是否 CJK（汉字 / CJK 标点 / 全角符号）。
    static func isCJK(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            let value = scalar.value
            return (0x4E00...0x9FFF).contains(value)
                || (0x3400...0x4DBF).contains(value)
                || (0x3000...0x303F).contains(value)
                || (0xFF00...0xFFEF).contains(value)
                || (0x2E80...0x2EFF).contains(value)
                || (0xF900...0xFAFF).contains(value)
        }
    }

    private static func unescape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
}
