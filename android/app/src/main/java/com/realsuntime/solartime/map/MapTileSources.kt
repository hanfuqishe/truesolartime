package com.realsuntime.solartime.map

import com.realsuntime.solartime.solar.SolarTimeMath
import org.osmdroid.tileprovider.tilesource.OnlineTileSourceBase
import org.osmdroid.tileprovider.tilesource.TileSourceFactory
import org.osmdroid.util.MapTileIndex

/**
 * 底图选择。
 *
 * AUTO 按「境内 / 境外」判断：境内用高德（中文地名、路网更细），境外用 **Esri 街道图**
 * （国内可直连；OSM 的 tile.openstreetmap.org 在部分网络被污染/不可达）。
 *
 * 「境内」用的是与**中国时区**同一套口径（[com.realsuntime.solartime.solar.SolarTimeMath.isInChinaRegion]：
 * 国家码 cn/hk/mo/tw，或没有国家码时 73–135°E / 18–54°N 的包围盒），
 * **不能**用 `CoordinateTransform.isInChina` —— 那是 GCJ-02 偏移的边界（纬度下限 0.83°），
 * 会把新加坡、马来西亚、印尼北部、菲律宾整片误判成境内。
 *
 * 高德的栅格瓦片无需 API Key，但内容为 GCJ-02 坐标，叠加 WGS-84 数据时需要偏移修正。
 */
enum class MapStyle(val label: String) {
    AUTO("自动"),
            // 境外不用高德的理由见 docs/AGENTS.md §12：高德有全球数据（世界地图），
        // 但那是**付费开通的高级能力**；未开通时公开瓦片境外只有全球概览（z12 稀疏、z14 空）。
        // 所以境外走公开免费的 Esri，境内才用高德。
    ESRI("Esri 街道图"),
    OSM("OpenStreetMap"),
    AMAP_VECTOR("高德矢量"),
    AMAP_SATELLITE("高德卫星"),
    ;

    /**
     * 自动模式下该用哪个源。
     *
     * @param countryCode 观测点国家码（ISO 3166-1 alpha-2）；有值就以它为准，null 才退回包围盒。
     */
    fun effective(latitude: Double, longitude: Double, countryCode: String? = null): MapStyle = when {
        this != AUTO -> this
        SolarTimeMath.isInChinaRegion(latitude, longitude, countryCode) -> AMAP_VECTOR
        else -> ESRI
    }

    val isGcj02: Boolean get() = this == AMAP_VECTOR || this == AMAP_SATELLITE

    val attribution: String
        get() = when (this) {
            ESRI -> "底图 © Esri, HERE, Garmin, © OpenStreetMap contributors"
            OSM -> "地图数据 © OpenStreetMap 贡献者"
            AMAP_VECTOR, AMAP_SATELLITE -> "底图 © 高德地图"
            AUTO -> ""
        }

    companion object {
        fun fromName(name: String?): MapStyle = entries.firstOrNull { it.name == name } ?: AUTO

        /**
         * 设置页「底图」里可以手动选的项（顺序即界面顺序）。
         *
         * [ESRI] 既是境外自动的偏好源，也允许手动选：手动选它时只走 ESRI，不探测 / 不回退 / 不降级。
         */
        val manualOptions: List<MapStyle> = listOf(AUTO, ESRI, OSM, AMAP_VECTOR, AMAP_SATELLITE)
    }
}

object MapTileSources {

    private const val MIN_ZOOM = 3
    private const val TILE_SIZE = 256

    private val amapVector: OnlineTileSourceBase = AmapTileSource(
        name = "AMapVector",
        zoomMax = 18,
        extension = ".png",
        templates = arrayOf(
            "https://webrd01.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=8",
            "https://webrd02.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=8",
            "https://webrd03.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=8",
            "https://webrd04.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=8",
        ),
    )

    private val amapSatellite: OnlineTileSourceBase = AmapTileSource(
        name = "AMapSatellite",
        zoomMax = 18,
        extension = ".jpg",
        templates = arrayOf(
            "https://webst01.is.autonavi.com/appmaptile?style=6&size=1&scale=1",
            "https://webst02.is.autonavi.com/appmaptile?style=6&size=1&scale=1",
            "https://webst03.is.autonavi.com/appmaptile?style=6&size=1&scale=1",
            "https://webst04.is.autonavi.com/appmaptile?style=6&size=1&scale=1",
        ),
    )

    /**
     * Esri ArcGIS 在线瓦片。
     *
     * ⚠️ 路径顺序是 **`{z}/{y}/{x}`**（与 OSM 的 `{z}/{x}/{y}` 相反），
     * 写反会让地图上下左右颠倒 —— 单测专门盯这一条。
     */
    private class EsriTileSource(
        name: String,
        private val service: String,
        extension: String,
    ) : OnlineTileSourceBase(
        name,
        MIN_ZOOM,
        ESRI_ZOOM_MAX,
        TILE_SIZE,
        extension,
        arrayOf("$ESRI_BASE/$service/MapServer/tile"),
    ) {

        override fun getTileURLString(pMapTileIndex: Long): String = esriTileUrl(
            service = service,
            zoom = MapTileIndex.getZoom(pMapTileIndex),
            x = MapTileIndex.getX(pMapTileIndex),
            y = MapTileIndex.getY(pMapTileIndex),
        )
    }

    /** Esri 图源根地址（`server.arcgisonline.com` 国内可直连）。 */
    const val ESRI_BASE = "https://server.arcgisonline.com/ArcGIS/rest/services"

    /** Esri 街图最高级别（World_Street_Map 支持到 19，这里按应用的 MAX_ZOOM 走）。 */
    private const val ESRI_ZOOM_MAX = 19

    /**
     * 拼 Esri 瓦片地址（纯函数，单测直接断言顺序）。
     *
     * **顺序是 z/y/x**：z12 的上海（x=3430, y=1673）→ `…/tile/12/1673/3430`。
     */
    fun esriTileUrl(service: String, zoom: Int, x: Int, y: Int): String =
        "$ESRI_BASE/$service/MapServer/tile/$zoom/$y/$x"

    private val esriStreet: OnlineTileSourceBase =
        EsriTileSource("EsriStreet", "World_Street_Map", ".jpg")

    fun tileSourceOf(style: MapStyle): OnlineTileSourceBase = when (style) {
        MapStyle.ESRI -> esriStreet
        MapStyle.OSM, MapStyle.AUTO -> TileSourceFactory.MAPNIK
        MapStyle.AMAP_VECTOR -> amapVector
        MapStyle.AMAP_SATELLITE -> amapSatellite
    }

    /** 数据层的 WGS-84 坐标 → 该底图所用的坐标系。 */
    fun toMapCoordinates(style: MapStyle, latitude: Double, longitude: Double): Pair<Double, Double> =
        if (style.isGcj02) CoordinateTransform.wgs84ToGcj02(latitude, longitude) else latitude to longitude

    private class AmapTileSource(
        name: String,
        zoomMax: Int,
        extension: String,
        private val templates: Array<String>,
    ) : OnlineTileSourceBase(name, MIN_ZOOM, zoomMax, TILE_SIZE, extension, templates) {

        override fun getTileURLString(pMapTileIndex: Long): String {
            val x = MapTileIndex.getX(pMapTileIndex)
            val y = MapTileIndex.getY(pMapTileIndex)
            val z = MapTileIndex.getZoom(pMapTileIndex)
            val index = ((x + y) % templates.size + templates.size) % templates.size
            return "${templates[index]}&x=$x&y=$y&z=$z"
        }
    }
}
