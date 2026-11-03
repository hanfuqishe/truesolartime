package com.realsuntime.solartime.map

import org.osmdroid.tileprovider.tilesource.OnlineTileSourceBase
import org.osmdroid.tileprovider.tilesource.TileSourceFactory
import org.osmdroid.util.MapTileIndex

/**
 * 底图选择。
 *
 * AUTO 按坐标判断：境内用高德（中文地名、路网更细），境外用 OpenStreetMap。
 * 高德的栅格瓦片无需 API Key，但内容为 GCJ-02 坐标，叠加 WGS-84 数据时需要偏移修正。
 */
enum class MapStyle(val label: String) {
    AUTO("自动"),
    OSM("OpenStreetMap"),
    AMAP_VECTOR("高德矢量"),
    AMAP_SATELLITE("高德卫星"),
    ;

    fun effective(latitude: Double, longitude: Double): MapStyle = when {
        this != AUTO -> this
        CoordinateTransform.isInChina(latitude, longitude) -> AMAP_VECTOR
        else -> OSM
    }

    val isGcj02: Boolean get() = this == AMAP_VECTOR || this == AMAP_SATELLITE

    val attribution: String
        get() = when (this) {
            OSM -> "地图数据 © OpenStreetMap 贡献者"
            AMAP_VECTOR, AMAP_SATELLITE -> "底图 © 高德地图"
            AUTO -> ""
        }

    companion object {
        fun fromName(name: String?): MapStyle = entries.firstOrNull { it.name == name } ?: AUTO
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

    fun tileSourceOf(style: MapStyle): OnlineTileSourceBase = when (style) {
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
