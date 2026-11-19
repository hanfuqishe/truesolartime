package com.realsuntime.solartime.map

/**
 * 设置页「地图数据来源」要展示的署名（**完整版**，与卡片底部那行短署名分开）。
 *
 * 为什么分两层：Esri World Street Map 官方 `copyrightText` 有 14 个来源，卡片一行放不下；
 * 只列 4 个又不完整。所以卡片保留 4 个主要来源的短署名，设置页放**英文原文全量**
 * （不翻译，符合 Esri 的署名要求）。
 */
data class MapSourceNote(
    /** 展示文本。 */
    val text: String,
    /** 点击要打开的链接；null = 没有可点的链接（高德）。 */
    val url: String?,
)

/** 各底图源的完整署名与版权链接（纯数据 + 纯函数，单测直接盯）。 */
object MapSourceAttribution {

    /**
     * Esri World Street Map 的官方 `copyrightText`（英文原文，故意不翻译、不缩短）。
     *
     * 单测钉住 `OpenStreetMap contributors` 与 `GIS User Community` 两段，防止以后被删短。
     */
    const val ESRI_FULL: String =
        "Sources: Esri, HERE, Garmin, USGS, Intermap, INCREMENT P, NRCan, Esri Japan, METI, " +
            "Esri China (Hong Kong), Esri Korea, Esri (Thailand), NGCC, © OpenStreetMap contributors, " +
            "and the GIS User Community"

    /** Esri 服务页（点开能看到官方版权声明）。 */
    const val ESRI_URL: String =
        "https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer"

    /** OSM 的版权页。 */
    const val OSM_URL: String = "https://www.openstreetmap.org/copyright"

    /**
     * 按当前设置与地点，解析出**实际使用的源**（自动模式：境内高德 / 境外 Esri）。
     */
    fun resolveSource(
        style: MapStyle,
        latitude: Double,
        longitude: Double,
        countryCode: String?,
    ): MapStyle = style.effective(latitude, longitude, countryCode)

    /**
     * 该源在设置页要显示的署名。
     *
     * @param osmText 本地化的 OSM 署名（来自 strings.xml）
     * @param amapText 本地化的高德署名（来自 strings.xml）
     */
    fun noteFor(source: MapStyle, osmText: String, amapText: String): MapSourceNote = when (source) {
        MapStyle.ESRI -> MapSourceNote(text = ESRI_FULL, url = ESRI_URL)
        MapStyle.OSM -> MapSourceNote(text = osmText, url = OSM_URL)
        // 高德没有任何可点的版权页：只署名，不给链接。
        MapStyle.AMAP_VECTOR, MapStyle.AMAP_SATELLITE -> MapSourceNote(text = amapText, url = null)
        MapStyle.AUTO -> MapSourceNote(text = amapText, url = null)
    }
}
