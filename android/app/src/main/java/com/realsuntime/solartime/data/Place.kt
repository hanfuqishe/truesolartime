package com.realsuntime.solartime.data

enum class PlaceSource { DEFAULT, GPS, MANUAL }

data class Place(
    val latitude: Double,
    val longitude: Double,
    val source: PlaceSource,
    val label: String,
    /** 内置城市使用资源名，便于随系统语言切换显示。 */
    val labelResName: String? = null,
    /**
     * 内置城市所属国家/地区（ISO 3166-1 alpha-2，小写），例如 `cn` / `hk` / `us`。
     *
     * 有了它，选中预设城市后 [ZoneTable] 能**当场**算出标准时区，不必等逆地理编码回来
     * （人在国内手工选纽约时，逆地理既慢又可能失败）。走 GPS 或手动输入坐标时是 null，
     * 由 [DistrictResolver.cachedCountryCode] 补。
     */
    val countryCode: String? = null,
) {
    companion object {
        val DEFAULT = Place(39.9042, 116.4074, PlaceSource.DEFAULT, "", "city_beijing", "cn")

        /** 常用城市，便于在无定位权限时快速切换。 */
        val PRESETS: List<Place> = listOf(
            Place(39.9042, 116.4074, PlaceSource.MANUAL, "", "city_beijing", "cn"),
            Place(31.2304, 121.4737, PlaceSource.MANUAL, "", "city_shanghai", "cn"),
            Place(23.1291, 113.2644, PlaceSource.MANUAL, "", "city_guangzhou", "cn"),
            Place(22.5431, 114.0579, PlaceSource.MANUAL, "", "city_shenzhen", "cn"),
            Place(30.5728, 104.0668, PlaceSource.MANUAL, "", "city_chengdu", "cn"),
            Place(34.3416, 108.9398, PlaceSource.MANUAL, "", "city_xian", "cn"),
            Place(45.8038, 126.5350, PlaceSource.MANUAL, "", "city_harbin", "cn"),
            Place(43.8256, 87.6168, PlaceSource.MANUAL, "", "city_urumqi", "cn"),
            Place(29.6520, 91.1721, PlaceSource.MANUAL, "", "city_lhasa", "cn"),
            Place(22.3193, 114.1694, PlaceSource.MANUAL, "", "city_hongkong", "hk"),
            // 境外常用城市：按 UTC 偏移从西到东排，方便一眼找到。
            Place(21.3069, -157.8583, PlaceSource.MANUAL, "", "city_honolulu", "us"),
            Place(34.0522, -118.2437, PlaceSource.MANUAL, "", "city_los_angeles", "us"),
            Place(40.7128, -74.0060, PlaceSource.MANUAL, "", "city_new_york", "us"),
            Place(51.5074, -0.1278, PlaceSource.MANUAL, "", "city_london", "gb"),
            Place(48.8566, 2.3522, PlaceSource.MANUAL, "", "city_paris", "fr"),
            Place(25.2048, 55.2708, PlaceSource.MANUAL, "", "city_dubai", "ae"),
            Place(28.6139, 77.2090, PlaceSource.MANUAL, "", "city_new_delhi", "in"),
            Place(35.6762, 139.6503, PlaceSource.MANUAL, "", "city_tokyo", "jp"),
            Place(1.3521, 103.8198, PlaceSource.MANUAL, "", "city_singapore", "sg"),
            Place(-33.8688, 151.2093, PlaceSource.MANUAL, "", "city_sydney", "au"),
            // 极圈城市：用来验证极昼／极夜。两个都不在 CityIndex 的行政区划语境里，
            // 但选城市时直接读 labelResName，不依赖逆地理编码。
            // 摩尔曼斯克（68.97°N 33.08°E）：俄罗斯，北极圈内，夏季极昼、冬季极夜。
            //   时区按 `ru` + 经度分段（33.08°E < 40°E）→ UTC+3（莫斯科时间）。
            Place(68.9700, 33.0800, PlaceSource.MANUAL, "", "city_murmansk", "ru"),
            // 中山站（69.37°S 76.38°E）：中国南极考察站，南极圈内，南半球夏季极昼、冬季极夜。
            //   时区显式用 `cn` → UTC+8：中山站按中国站务惯例使用北京时间；ZoneTable 没有
            //   `aq` 条目，若写 aq 会退回「按经度取整」得到 +5，与站上实际使用的 UTC+8 不符。
            Place(-69.3700, 76.3800, PlaceSource.MANUAL, "", "city_zhongshan", "cn"),
            // 开罗（30.04°N 31.24°E）：埃及，UTC+2 且无夏令时（ZoneTable: eg → +120）。
            Place(30.0444, 31.2357, PlaceSource.MANUAL, "", "city_cairo", "eg"),
            // 里约热内卢（22.91°S 43.17°W）：巴西，America/Sao_Paulo = UTC−3
            //（ZoneTable: br 按经度分段，−43.17° 落在 else 段 → −180）。
            Place(-22.9068, -43.1729, PlaceSource.MANUAL, "", "city_rio", "br"),
        )

        const val MIN_LATITUDE = -90.0
        const val MAX_LATITUDE = 90.0
        const val MIN_LONGITUDE = -180.0
        const val MAX_LONGITUDE = 180.0
    }
}