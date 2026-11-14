package com.realsuntime.solartime.data

/**
 * 国家/地区 → 标准时区偏移（分钟表，对外给秒）。
 *
 * 用于「日出 / 上中天 / 日落」与左栏标准时钟按**当地标准时**展示。优先级：
 *   1. 已知国家（单时区国家直接查表）；
 *   2. 多时区大国按经度分段（美国、加拿大、俄罗斯、澳大利亚、巴西、墨西哥、印尼、哈萨克）；
 *   3. 表里没有的，退回按经度每 15° 取整的近似（[com.realsuntime.solartime.solar.SolarTimeMath.standardZoneOffsetSeconds]）。
 *
 * 中国全境（含港澳台）恒为 +8，不按经度算 —— 否则乌鲁木齐 87°E 会被算成 +6。
 * 不处理夏令时：这里给的是**标准时**偏移，与鸿蒙版口径一致。
 */
object ZoneTable {

    private val MINUTES: Map<String, Int> = mapOf(
        // 东亚 / 东南亚
        "cn" to 480, "hk" to 480, "mo" to 480, "tw" to 480,
        "jp" to 540, "kr" to 540, "kp" to 540,
        "sg" to 480, "my" to 480, "ph" to 480, "bn" to 480,
        "th" to 420, "vn" to 420, "la" to 420, "kh" to 420,
        "mm" to 390, "tl" to 540, "mn" to 480,
        // 南亚 / 中亚 / 西亚
        "bd" to 360, "in" to 330, "lk" to 330, "np" to 345,
        "pk" to 300, "af" to 270, "ir" to 210,
        "iq" to 180, "sa" to 180, "ae" to 240, "om" to 240,
        "qa" to 180, "kw" to 180, "bh" to 180, "ye" to 180,
        "jo" to 180, "il" to 120, "lb" to 120, "sy" to 180,
        "tr" to 180, "ge" to 240, "am" to 240, "az" to 240,
        "uz" to 300, "tm" to 300, "kg" to 360, "tj" to 300,
        // 欧洲
        "gb" to 0, "ie" to 0, "pt" to 0, "is" to 0,
        "fr" to 60, "de" to 60, "it" to 60, "es" to 60,
        "nl" to 60, "be" to 60, "ch" to 60, "at" to 60,
        "se" to 60, "no" to 60, "dk" to 60, "pl" to 60,
        "cz" to 60, "sk" to 60, "hu" to 60, "hr" to 60,
        "si" to 60, "rs" to 60, "ba" to 60, "me" to 60,
        "mk" to 60, "al" to 60, "lu" to 60, "mt" to 60,
        "li" to 60, "ad" to 60, "mc" to 60, "sm" to 60,
        "va" to 60, "gi" to 60,
        "gr" to 120, "bg" to 120, "ro" to 120, "md" to 120,
        "ua" to 120, "fi" to 120, "ee" to 120, "lv" to 120,
        "lt" to 120, "cy" to 120, "by" to 180,
        // 非洲
        "eg" to 120, "ly" to 120, "sd" to 120, "ss" to 120,
        "tn" to 60, "dz" to 60, "ma" to 60, "ne" to 60,
        "td" to 60, "cm" to 60, "cf" to 60, "ga" to 60,
        "cg" to 60, "ao" to 60, "ng" to 60, "gh" to 0,
        "ci" to 0, "sn" to 0, "ml" to 0, "bf" to 0,
        "gm" to 0, "gn" to 0, "sl" to 0, "lr" to 0,
        "tg" to 0, "bj" to 60, "gq" to 60, "mr" to 0,
        "et" to 180, "ke" to 180, "tz" to 180, "ug" to 180,
        "so" to 180, "dj" to 180, "er" to 180, "mg" to 180,
        "cd" to 120, "zm" to 120, "zw" to 120, "mz" to 120,
        "za" to 120, "na" to 120, "bw" to 120, "mw" to 120,
        "rw" to 120, "bi" to 120, "mu" to 240, "sc" to 240,
        // 美洲
        "ar" to -180, "cl" to -240, "pe" to -300, "co" to -300,
        "ve" to -240, "ec" to -300, "bo" to -240, "py" to -240,
        "uy" to -180, "gy" to -240, "sr" to -180, "gf" to -180,
        "cu" to -300, "do" to -240, "ht" to -300, "jm" to -300,
        "pr" to -240, "tt" to -240, "pa" to -300, "cr" to -360,
        "ni" to -360, "hn" to -360, "sv" to -360, "gt" to -360,
        "bz" to -360, "gl" to -180,
        // 大洋洲
        "nz" to 720, "fj" to 720, "pg" to 600, "nc" to 660,
        "sb" to 660, "vu" to 660, "pf" to -600,
    )

    /** 多时区国家按经度分段得到的分钟数；不是多时区国家时返回 [NOT_MULTI_ZONE]。 */
    private const val NOT_MULTI_ZONE = Int.MIN_VALUE

    private fun multiZoneMinutes(country: String, longitude: Double): Int = when (country) {
        "us" -> when {
            longitude < -155 -> -600      // 夏威夷
            longitude < -130 -> -540      // 阿拉斯加
            longitude < -114 -> -480      // 太平洋
            longitude < -101 -> -420      // 山地
            longitude < -86 -> -360       // 中部
            else -> -300                  // 东部
        }
        "ca" -> when {
            longitude < -120 -> -480
            longitude < -95 -> -420
            else -> -300
        }
        "mx" -> if (longitude < -105) -420 else -360
        "br" -> when {
            longitude < -60 -> -300
            longitude < -45 -> -240
            else -> -180
        }
        "ru" -> when {
            longitude < 40 -> 180
            longitude < 52 -> 240
            longitude < 65 -> 300
            longitude < 85 -> 420
            longitude < 105 -> 480
            longitude < 125 -> 540
            longitude < 145 -> 600
            else -> 660
        }
        "au" -> when {
            longitude < 129 -> 480
            longitude < 138 -> 570
            else -> 600
        }
        "id" -> when {
            longitude < 115 -> 420
            longitude < 127 -> 480
            else -> 540
        }
        "kz" -> if (longitude < 65) 300 else 360
        else -> NOT_MULTI_ZONE
    }

    /**
     * 观测点的标准时区偏移（秒）。
     *
     * @param countryCode 逆地理编码得到的 ISO 3166-1 alpha-2（大小写不敏感），未知传 null 或空串。
     * @param fallbackSeconds 表里查不到时的兜底值（通常是按经度取整的近似）。
     */
    fun offsetSeconds(countryCode: String?, longitude: Double, fallbackSeconds: Int): Int {
        val code = countryCode?.trim()?.lowercase().orEmpty()
        if (code.length != 2) return fallbackSeconds
        val minutes = multiZoneMinutes(code, longitude).takeUnless { it == NOT_MULTI_ZONE }
            ?: MINUTES[code]
            ?: return fallbackSeconds
        return minutes * 60
    }

    /** 该国家码是否在表里（含多时区大国）。仅供测试与排查。 */
    internal fun knows(countryCode: String?): Boolean {
        val code = countryCode?.trim()?.lowercase().orEmpty()
        return code.length == 2 && (MINUTES.containsKey(code) || multiZoneMinutes(code, 0.0) != NOT_MULTI_ZONE)
    }
}
