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

    @Test
    fun mapStyleResolvesByRegion() {
        assertEquals(MapStyle.AMAP_VECTOR, MapStyle.AUTO.effective(39.9042, 116.4074))
        assertEquals(MapStyle.OSM, MapStyle.AUTO.effective(48.8566, 2.3522))
        assertEquals(MapStyle.OSM, MapStyle.AUTO.effective(37.4220, -122.0840))
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
