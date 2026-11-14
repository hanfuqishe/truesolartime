import Foundation

/// 国家/地区 → 标准时区偏移（分钟表，对外给秒）。
///
/// 移植自 Android 的 `data/ZoneTable.kt`，口径完全一致：
///   1. 已知国家（单时区国家直接查表）；
///   2. 多时区大国按经度分段（美国、加拿大、俄罗斯、澳大利亚、巴西、墨西哥、印尼、哈萨克）；
///   3. 表里没有的，退回按经度每 15° 取整的近似（`SolarTimeMath.approxZoneOffsetSeconds`）。
///
/// 中国全境（含港澳台）恒为 +8，不按经度算 —— 否则乌鲁木齐 87°E 会被算成 +6。
/// 不处理夏令时：这里给的是**标准时**偏移，与 Android / 鸿蒙口径一致。
enum ZoneTable {

    static let minutes = 60

    private static let table: [String: Int] = [
        // 东亚 / 东南亚
        "cn": 480, "hk": 480, "mo": 480, "tw": 480,
        "jp": 540, "kr": 540, "kp": 540,
        "sg": 480, "my": 480, "ph": 480, "bn": 480,
        "th": 420, "vn": 420, "la": 420, "kh": 420,
        "mm": 390, "tl": 540, "mn": 480,
        // 南亚 / 中亚 / 西亚
        "bd": 360, "in": 330, "lk": 330, "np": 345,
        "pk": 300, "af": 270, "ir": 210,
        "iq": 180, "sa": 180, "ae": 240, "om": 240,
        "qa": 180, "kw": 180, "bh": 180, "ye": 180,
        "jo": 180, "il": 120, "lb": 120, "sy": 180,
        "tr": 180, "ge": 240, "am": 240, "az": 240,
        "uz": 300, "tm": 300, "kg": 360, "tj": 300,
        // 欧洲
        "gb": 0, "ie": 0, "pt": 0, "is": 0,
        "fr": 60, "de": 60, "it": 60, "es": 60,
        "nl": 60, "be": 60, "ch": 60, "at": 60,
        "se": 60, "no": 60, "dk": 60, "pl": 60,
        "cz": 60, "sk": 60, "hu": 60, "hr": 60,
        "si": 60, "rs": 60, "ba": 60, "me": 60,
        "mk": 60, "al": 60, "lu": 60, "mt": 60,
        "li": 60, "ad": 60, "mc": 60, "sm": 60,
        "va": 60, "gi": 60,
        "gr": 120, "bg": 120, "ro": 120, "md": 120,
        "ua": 120, "fi": 120, "ee": 120, "lv": 120,
        "lt": 120, "cy": 120, "by": 180,
        // 非洲
        "eg": 120, "ly": 120, "sd": 120, "ss": 120,
        "tn": 60, "dz": 60, "ma": 60, "ne": 60,
        "td": 60, "cm": 60, "cf": 60, "ga": 60,
        "cg": 60, "ao": 60, "ng": 60, "gh": 0,
        "ci": 0, "sn": 0, "ml": 0, "bf": 0,
        "gm": 0, "gn": 0, "sl": 0, "lr": 0,
        "tg": 0, "bj": 60, "gq": 60, "mr": 0,
        "et": 180, "ke": 180, "tz": 180, "ug": 180,
        "so": 180, "dj": 180, "er": 180, "mg": 180,
        "cd": 120, "zm": 120, "zw": 120, "mz": 120,
        "za": 120, "na": 120, "bw": 120, "mw": 120,
        "rw": 120, "bi": 120, "mu": 240, "sc": 240,
        // 美洲
        "ar": -180, "cl": -240, "pe": -300, "co": -300,
        "ve": -240, "ec": -300, "bo": -240, "py": -240,
        "uy": -180, "gy": -240, "sr": -180, "gf": -180,
        "cu": -300, "do": -240, "ht": -300, "jm": -300,
        "pr": -240, "tt": -240, "pa": -300, "cr": -360,
        "ni": -360, "hn": -360, "sv": -360, "gt": -360,
        "bz": -360, "gl": -180,
        // 大洋洲
        "nz": 720, "fj": 720, "pg": 600, "nc": 660,
        "sb": 660, "vu": 660, "pf": -600,
    ]

    /// 多时区国家按经度分段；不是多时区国家时返回 nil。
    private static func multiZoneMinutes(_ country: String, longitude: Double) -> Int? {
        switch country {
        case "us":
            if longitude < -155 { return -600 }   // 夏威夷
            if longitude < -130 { return -540 }   // 阿拉斯加
            if longitude < -114 { return -480 }   // 太平洋
            if longitude < -101 { return -420 }   // 山地
            if longitude < -86 { return -360 }    // 中部
            return -300                           // 东部
        case "ca":
            if longitude < -120 { return -480 }
            if longitude < -95 { return -420 }
            return -300
        case "mx":
            return longitude < -105 ? -420 : -360
        case "br":
            if longitude < -60 { return -300 }
            if longitude < -45 { return -240 }
            return -180
        case "ru":
            if longitude < 40 { return 180 }
            if longitude < 52 { return 240 }
            if longitude < 65 { return 300 }
            if longitude < 85 { return 420 }
            if longitude < 105 { return 480 }
            if longitude < 125 { return 540 }
            if longitude < 145 { return 600 }
            return 660
        case "au":
            if longitude < 129 { return 480 }
            if longitude < 138 { return 570 }
            return 600
        case "id":
            if longitude < 115 { return 420 }
            if longitude < 127 { return 480 }
            return 540
        case "kz":
            return longitude < 65 ? 300 : 360
        default:
            return nil
        }
    }

    /// 观测点的标准时区偏移（秒）。
    ///
    /// - Parameters:
    ///   - countryCode: 逆地理编码得到的 ISO 3166-1 alpha-2（大小写不敏感），未知传 nil。
    ///   - fallbackSeconds: 表里查不到时的兜底值（通常是按经度取整的近似）。
    static func offsetSeconds(countryCode: String?, longitude: Double, fallbackSeconds: Int) -> Int {
        let code = (countryCode ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard code.count == 2 else { return fallbackSeconds }
        if let minutes = multiZoneMinutes(code, longitude: longitude) {
            return seconds(fromMinutes: minutes)
        }
        if let minutes = table[code] {
            return seconds(fromMinutes: minutes)
        }
        return fallbackSeconds
    }

    /// 该国家码是否在表里（含多时区大国）。仅供排查与自检。
    static func knows(_ countryCode: String?) -> Bool {
        let code = (countryCode ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard code.count == 2 else { return false }
        return table[code] != nil || multiZoneMinutes(code, longitude: 0) != nil
    }

    private static func seconds(fromMinutes minutes: Int) -> Int { minutes * 60 }
}
