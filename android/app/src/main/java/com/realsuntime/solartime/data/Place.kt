package com.realsuntime.solartime.data

enum class PlaceSource { DEFAULT, GPS, MANUAL }

/**
 * 常用城市所在大洲（设置页分组用，仅供 UI 与断言；widget 不依赖）。
 */
enum class CityRegion { ASIA, EUROPE, AFRICA, NORTH_AMERICA, SOUTH_AMERICA, OCEANIA, ANTARCTICA }

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
    /** 所属大洲；非预置城市为 null。 */
    val region: CityRegion? = null,
) {
    companion object {
        val DEFAULT = Place(39.9042, 116.4074, PlaceSource.DEFAULT, "", "city_beijing", "cn")

        /** 常用城市，便于在无定位权限时快速切换。 */
        /**
         * 44 个常用城市，按大洲分组排列（亚洲 18 / 欧洲 8 / 非洲 4 / 北美洲 6 / 南美洲 4 / 大洋洲 3 / 南极洲 1）。
         * 坐标与 iOS / 鸿蒙逐位一致；[region] 仅供设置页分组与断言。
         */
        val PRESETS: List<Place> = listOf(
            Place(39.9042, 116.4074, PlaceSource.MANUAL, "", "city_beijing", "cn", CityRegion.ASIA),
            Place(31.2304, 121.4737, PlaceSource.MANUAL, "", "city_shanghai", "cn", CityRegion.ASIA),
            Place(23.1291, 113.2644, PlaceSource.MANUAL, "", "city_guangzhou", "cn", CityRegion.ASIA),
            Place(22.5431, 114.0579, PlaceSource.MANUAL, "", "city_shenzhen", "cn", CityRegion.ASIA),
            Place(30.5728, 104.0668, PlaceSource.MANUAL, "", "city_chengdu", "cn", CityRegion.ASIA),
            Place(34.3416, 108.9398, PlaceSource.MANUAL, "", "city_xian", "cn", CityRegion.ASIA),
            Place(45.8038, 126.5350, PlaceSource.MANUAL, "", "city_harbin", "cn", CityRegion.ASIA),
            Place(52.9721, 122.5388, PlaceSource.MANUAL, "", "city_mohe", "cn", CityRegion.ASIA),
            Place(48.3669, 134.2895, PlaceSource.MANUAL, "", "city_fuyuan", "cn", CityRegion.ASIA),
            Place(43.8256, 87.6168, PlaceSource.MANUAL, "", "city_urumqi", "cn", CityRegion.ASIA),
            Place(39.4704, 75.9898, PlaceSource.MANUAL, "", "city_kashgar", "cn", CityRegion.ASIA),
            Place(29.6520, 91.1721, PlaceSource.MANUAL, "", "city_lhasa", "cn", CityRegion.ASIA),
            Place(22.3193, 114.1694, PlaceSource.MANUAL, "", "city_hongkong", "hk", CityRegion.ASIA),
            Place(25.0330, 121.5654, PlaceSource.MANUAL, "", "city_taipei", "tw", CityRegion.ASIA),
            Place(22.6273, 120.3014, PlaceSource.MANUAL, "", "city_kaohsiung", "tw", CityRegion.ASIA),
            Place(16.8343, 112.3388, PlaceSource.MANUAL, "", "city_sansha", "cn", CityRegion.ASIA),
            Place(25.7459, 123.4776, PlaceSource.MANUAL, "", "city_diaoyu", "cn", CityRegion.ASIA),
            Place(35.6762, 139.6503, PlaceSource.MANUAL, "", "city_tokyo", "jp", CityRegion.ASIA),
            Place(37.5665, 126.9780, PlaceSource.MANUAL, "", "city_seoul", "kr", CityRegion.ASIA),
            Place(39.0392, 125.7625, PlaceSource.MANUAL, "", "city_pyongyang", "kp", CityRegion.ASIA),
            Place(43.1155, 131.8855, PlaceSource.MANUAL, "", "city_vladivostok", "ru", CityRegion.ASIA),
            Place(1.3521, 103.8198, PlaceSource.MANUAL, "", "city_singapore", "sg", CityRegion.ASIA),
            Place(13.7563, 100.5018, PlaceSource.MANUAL, "", "city_bangkok", "th", CityRegion.ASIA),
            Place(17.9757, 102.6331, PlaceSource.MANUAL, "", "city_vientiane", "la", CityRegion.ASIA),
            Place(-6.2088, 106.8456, PlaceSource.MANUAL, "", "city_jakarta", "id", CityRegion.ASIA),
            Place(28.6139, 77.2090, PlaceSource.MANUAL, "", "city_new_delhi", "in", CityRegion.ASIA),
            Place(25.2048, 55.2708, PlaceSource.MANUAL, "", "city_dubai", "ae", CityRegion.ASIA),
            Place(41.0082, 28.9784, PlaceSource.MANUAL, "", "city_istanbul", "tr", CityRegion.ASIA),
            Place(55.7558, 37.6173, PlaceSource.MANUAL, "", "city_moscow", "ru", CityRegion.EUROPE),
            Place(51.5074, -0.1278, PlaceSource.MANUAL, "", "city_london", "gb", CityRegion.EUROPE),
            Place(48.8566, 2.3522, PlaceSource.MANUAL, "", "city_paris", "fr", CityRegion.EUROPE),
            Place(52.5200, 13.4050, PlaceSource.MANUAL, "", "city_berlin", "de", CityRegion.EUROPE),
            Place(41.9028, 12.4964, PlaceSource.MANUAL, "", "city_rome", "it", CityRegion.EUROPE),
            Place(40.4168, -3.7038, PlaceSource.MANUAL, "", "city_madrid", "es", CityRegion.EUROPE),
            Place(64.1466, -21.9426, PlaceSource.MANUAL, "", "city_reykjavik", "is", CityRegion.EUROPE),
            Place(68.9700, 33.0800, PlaceSource.MANUAL, "", "city_murmansk", "ru", CityRegion.EUROPE),
            Place(30.0444, 31.2357, PlaceSource.MANUAL, "", "city_cairo", "eg", CityRegion.AFRICA),
            Place(-33.9249, 18.4241, PlaceSource.MANUAL, "", "city_cape_town", "za", CityRegion.AFRICA),
            Place(-1.2921, 36.8219, PlaceSource.MANUAL, "", "city_nairobi", "ke", CityRegion.AFRICA),
            Place(-1.9441, 30.0619, PlaceSource.MANUAL, "", "city_kigali", "rw", CityRegion.AFRICA),
            Place(6.5244, 3.3792, PlaceSource.MANUAL, "", "city_lagos", "ng", CityRegion.AFRICA),
            Place(21.3069, -157.8583, PlaceSource.MANUAL, "", "city_honolulu", "us", CityRegion.NORTH_AMERICA),
            Place(34.0522, -118.2437, PlaceSource.MANUAL, "", "city_los_angeles", "us", CityRegion.NORTH_AMERICA),
            Place(40.7128, -74.0060, PlaceSource.MANUAL, "", "city_new_york", "us", CityRegion.NORTH_AMERICA),
            Place(41.8781, -87.6298, PlaceSource.MANUAL, "", "city_chicago", "us", CityRegion.NORTH_AMERICA),
            Place(19.4326, -99.1332, PlaceSource.MANUAL, "", "city_mexico_city", "mx", CityRegion.NORTH_AMERICA),
            Place(49.2827, -123.1207, PlaceSource.MANUAL, "", "city_vancouver", "ca", CityRegion.NORTH_AMERICA),
            Place(-22.9068, -43.1729, PlaceSource.MANUAL, "", "city_rio", "br", CityRegion.SOUTH_AMERICA),
            Place(-23.5505, -46.6333, PlaceSource.MANUAL, "", "city_sao_paulo", "br", CityRegion.SOUTH_AMERICA),
            Place(-34.6037, -58.3816, PlaceSource.MANUAL, "", "city_buenos_aires", "ar", CityRegion.SOUTH_AMERICA),
            Place(-12.0464, -77.0428, PlaceSource.MANUAL, "", "city_lima", "pe", CityRegion.SOUTH_AMERICA),
            Place(-33.8688, 151.2093, PlaceSource.MANUAL, "", "city_sydney", "au", CityRegion.OCEANIA),
            Place(-31.9523, 115.8613, PlaceSource.MANUAL, "", "city_perth", "au", CityRegion.OCEANIA),
            Place(-36.8485, 174.7633, PlaceSource.MANUAL, "", "city_auckland", "nz", CityRegion.OCEANIA),
            Place(-80.4169, 77.1161, PlaceSource.MANUAL, "", "city_kunlun", "cn", CityRegion.ANTARCTICA),
        )

        const val MIN_LATITUDE = -90.0
        const val MAX_LATITUDE = 90.0
        const val MIN_LONGITUDE = -180.0
        const val MAX_LONGITUDE = 180.0
    }
}
