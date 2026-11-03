package com.realsuntime.solartime.data

enum class PlaceSource { DEFAULT, GPS, MANUAL }

data class Place(
    val latitude: Double,
    val longitude: Double,
    val source: PlaceSource,
    val label: String,
) {
    companion object {
        val DEFAULT = Place(39.9042, 116.4074, PlaceSource.DEFAULT, "北京（默认）")

        /** 常用城市，便于在无定位权限时快速切换。 */
        val PRESETS: List<Place> = listOf(
            Place(39.9042, 116.4074, PlaceSource.MANUAL, "北京"),
            Place(31.2304, 121.4737, PlaceSource.MANUAL, "上海"),
            Place(23.1291, 113.2644, PlaceSource.MANUAL, "广州"),
            Place(22.5431, 114.0579, PlaceSource.MANUAL, "深圳"),
            Place(30.5728, 104.0668, PlaceSource.MANUAL, "成都"),
            Place(34.3416, 108.9398, PlaceSource.MANUAL, "西安"),
            Place(45.8038, 126.5350, PlaceSource.MANUAL, "哈尔滨"),
            Place(43.8256, 87.6168, PlaceSource.MANUAL, "乌鲁木齐"),
            Place(29.6520, 91.1721, PlaceSource.MANUAL, "拉萨"),
            Place(22.3193, 114.1694, PlaceSource.MANUAL, "香港"),
        )

        const val MIN_LATITUDE = -90.0
        const val MAX_LATITUDE = 90.0
        const val MIN_LONGITUDE = -180.0
        const val MAX_LONGITUDE = 180.0
    }
}
