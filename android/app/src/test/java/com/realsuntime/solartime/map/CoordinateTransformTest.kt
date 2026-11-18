package com.realsuntime.solartime.map

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs
import kotlin.math.max

class CoordinateTransformTest {

    @Test
    fun beijingShiftsEastAndNorthInGcj02() {
        val (gcjLat, gcjLon) = CoordinateTransform.wgs84ToGcj02(39.9042, 116.4074)
        assertEquals(39.905603, gcjLat, 1e-5)
        assertEquals(116.413642, gcjLon, 1e-5)
        assertTrue(gcjLon > 116.4074)
        assertTrue(gcjLat > 39.9042)
    }

    @Test
    fun shanghaiAndShenzhenMatchKnownOffsets() {
        val (shLat, shLon) = CoordinateTransform.wgs84ToGcj02(31.2304, 121.4737)
        assertEquals(31.228458, shLat, 1e-5)
        assertEquals(121.478223, shLon, 1e-5)

        val (szLat, szLon) = CoordinateTransform.wgs84ToGcj02(22.5431, 114.0579)
        assertEquals(22.540383, szLat, 1e-5)
        assertEquals(114.063014, szLon, 1e-5)
    }

    @Test
    fun outsideChinaIsUntouched() {
        listOf(35.6762 to 139.6503, 48.8566 to 2.3522, -33.8688 to 151.2093, 37.4220 to -122.0840)
            .forEach { (lat, lon) ->
                val (gcjLat, gcjLon) = CoordinateTransform.wgs84ToGcj02(lat, lon)
                assertEquals(lat, gcjLat, 0.0)
                assertEquals(lon, gcjLon, 0.0)
                assertFalse(CoordinateTransform.isInChina(lat, lon))
            }
    }

    @Test
    fun chinaBoundsCoverMainlandCities() {
        assertTrue(CoordinateTransform.isInChina(39.9042, 116.4074))
        assertTrue(CoordinateTransform.isInChina(43.8256, 87.6168))
        assertTrue(CoordinateTransform.isInChina(22.5431, 114.0579))
        // 边界是矩形范围，东南亚部分国家（如新加坡）也落在其中，会使用高德底图。
        assertTrue(CoordinateTransform.isInChina(1.3521, 103.8198))
        assertFalse(CoordinateTransform.isInChina(51.5072, -0.1276))
    }

    @Test
    fun inverseRoundTripIsAccurate() {
        val samples = listOf(
            39.9042 to 116.4074,
            31.2304 to 121.4737,
            43.8256 to 87.6168,
            29.6520 to 91.1721,
            22.3193 to 114.1694,
        )
        samples.forEach { (lat, lon) ->
            val (gcjLat, gcjLon) = CoordinateTransform.wgs84ToGcj02(lat, lon)
            val (backLat, backLon) = CoordinateTransform.gcj02ToWgs84(gcjLat, gcjLon)
            val error = max(abs(backLat - lat), abs(backLon - lon))
            assertTrue("round trip error $error for ($lat, $lon)", error < 1e-6)
        }
    }

    /**
     * 选源用的「境内」口径 = 中国时区口径（国家码优先，其次 73–135°E / 18–54°N），
     * **不是** GCJ-02 的边界。回归：新加坡/吉隆坡/雅加达曾被 GCJ 边界（纬度 ≥0.83°）误判成境内。
     */
    @Test
    fun mapStyleUsesCountryCodeAndChinaBboxNotTheGcjBoundary() {
        // 东南亚：即使坐标落在 GCJ 边界内，也必须是境外 → ESRI
        assertEquals(MapStyle.ESRI, MapStyle.AUTO.effective(1.3521, 103.8198, "sg")) // 新加坡
        assertEquals(MapStyle.ESRI, MapStyle.AUTO.effective(3.139, 101.6869, "my")) // 吉隆坡
        assertEquals(MapStyle.ESRI, MapStyle.AUTO.effective(-6.2, 106.8, "id")) // 雅加达
        // 港澳台：国家码算境内 → 高德
        assertEquals(MapStyle.AMAP_VECTOR, MapStyle.AUTO.effective(22.32, 114.17, "hk"))
        assertEquals(MapStyle.AMAP_VECTOR, MapStyle.AUTO.effective(25.03, 121.56, "tw"))
        assertEquals(MapStyle.AMAP_VECTOR, MapStyle.AUTO.effective(39.9, 116.4, "cn"))
        // 没有国家码：退回包围盒（新加坡 1.35°N 在 18–54 之外 → 境外）
        assertEquals(MapStyle.ESRI, MapStyle.AUTO.effective(1.3521, 103.8198))
        assertEquals(MapStyle.AMAP_VECTOR, MapStyle.AUTO.effective(39.9042, 116.4074))
        // 包围盒内但国家码不是中国：境外（新德里 28°N/77°E 在框内）
        assertEquals(MapStyle.ESRI, MapStyle.AUTO.effective(28.6139, 77.2090, "in"))
        // 手动选项不受影响
        assertEquals(MapStyle.OSM, MapStyle.OSM.effective(1.3521, 103.8198, "sg"))
        assertEquals(MapStyle.AMAP_SATELLITE, MapStyle.AMAP_SATELLITE.effective(1.3521, 103.8198))
    }

    /** GCJ-02 的边界仍只用于坐标偏移：新加坡坐标确实落在它里面（但不再影响选源）。 */
    @Test
    fun gcjBoundaryStillCoversSoutheastAsiaButIsNotUsedForSourceChoice() {
        assertTrue(CoordinateTransform.isInChina(1.3521, 103.8198))
        assertEquals(MapStyle.ESRI, MapStyle.AUTO.effective(1.3521, 103.8198, "sg"))
    }

    @Test
    fun mapStyleResolvesByRegion() {
        assertEquals(MapStyle.AMAP_VECTOR, MapStyle.AUTO.effective(39.9042, 116.4074))
        assertEquals(MapStyle.ESRI, MapStyle.AUTO.effective(48.8566, 2.3522))
        assertEquals(MapStyle.ESRI, MapStyle.AUTO.effective(37.4220, -122.0840))
        assertEquals(MapStyle.AMAP_SATELLITE, MapStyle.AMAP_SATELLITE.effective(48.8566, 2.3522))
        assertEquals(MapStyle.OSM, MapStyle.OSM.effective(39.9042, 116.4074))
    }

    @Test
    fun gcjStylesUseOffsetAndOsmDoesNot() {
        val (osmLat, osmLon) = MapTileSources.toMapCoordinates(MapStyle.OSM, 39.9042, 116.4074)
        assertEquals(39.9042, osmLat, 0.0)
        assertEquals(116.4074, osmLon, 0.0)

        val (amapLat, amapLon) = MapTileSources.toMapCoordinates(MapStyle.AMAP_VECTOR, 39.9042, 116.4074)
        assertTrue(amapLat > 39.9042)
        assertTrue(amapLon > 116.4074)
    }
}
