package com.realsuntime.solartime.map

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 未知态（定位不可用）的地图状态：**缩到最低级别的全球底图（z3）**，且不参与「给具体地点定源定级」那套。
 *
 * 源仍按现有规则：自动模式按境内高德 / 境外 OSM 选，没有坐标就算境外（OSM），
 * OSM 连不上仍会回退高德 —— 兜底链原样保留。
 */
class MapUnknownStateTest {

    @Test
    fun unknownForcesTheGlobalBasemapZoom() {
        val auto = MapUiState.ofUnknown(MapStyle.AUTO, MapFallbackState())
        assertEquals("未知态必须固定 z3", MapFallback.MIN_ZOOM, auto.zoom)
        assertEquals(3, auto.zoom)
        assertFalse("固定 z3 不是「被降级」", auto.degraded)
        assertFalse("正常有网时不是「底图不可用」", auto.unavailable)
        assertFalse("没有回退", auto.fellBack)
        assertEquals(MapStyle.AUTO, auto.requested)
        // 没有坐标 → 按境外处理 → OSM。
        assertEquals(MapStyle.OSM, auto.source)
        // 无坐标锚点落在境外，不是上一个城市（北京）的坐标。
        assertEquals(0.0, MapUiState.UNKNOWN_LATITUDE, 0.0)
        assertEquals(0.0, MapUiState.UNKNOWN_LONGITUDE, 0.0)
        assertEquals(
            MapStyle.OSM,
            MapStyle.AUTO.effective(MapUiState.UNKNOWN_LATITUDE, MapUiState.UNKNOWN_LONGITUDE),
        )
    }

    @Test
    fun unknownKeepsTheExistingFallbackChain() {
        // 自动模式下 OSM 已失败并回退：未知态照样回退到高德，级别仍是 z3。
        val fellBack = MapUiState.ofUnknown(
            MapStyle.AUTO,
            MapFallbackState(fellBack = true, fallbackFailures = 3),
        )
        assertEquals(MapStyle.AMAP_VECTOR, fellBack.source)
        assertTrue(fellBack.fellBack)
        assertEquals(MapFallback.MIN_ZOOM, fellBack.zoom)

        // 连最低级别的全球底图都判过「没瓦片」：界面显示「底图不可用」（沿用现有兜底）。
        val unavailable = MapUiState.ofUnknown(
            MapStyle.AUTO,
            MapFallbackState(
                fellBack = true,
                unavailableZooms = mapOf(MapStyle.AMAP_VECTOR to setOf(MapFallback.MIN_ZOOM)),
            ),
        )
        assertTrue(unavailable.unavailable)
        assertEquals(MapFallback.MIN_ZOOM, unavailable.zoom)
    }

    @Test
    fun unknownRespectsAManuallyChosenBasemap() {
        val amap = MapUiState.ofUnknown(MapStyle.AMAP_SATELLITE, MapFallbackState())
        assertEquals("手动选的底图不被改写", MapStyle.AMAP_SATELLITE, amap.source)
        assertEquals(MapStyle.AMAP_SATELLITE, amap.requested)
        assertEquals(MapFallback.MIN_ZOOM, amap.zoom)
        assertFalse("手动模式不回退", amap.fellBack)
    }

    /**
     * 未知态与「有坐标」的常规状态互不干扰：同样的会话状态下，常规状态还是从 z12 起。
     */
    @Test
    fun normalStateStillStartsFromTheDefaultZoom() {
        val normal = MapUiState.of(MapStyle.AUTO, 31.23, 121.47, MapFallbackState())
        assertEquals("境内 → 高德", MapStyle.AMAP_VECTOR, normal.source)
        assertEquals(MapFallback.DEFAULT_ZOOM, normal.zoom)
        assertTrue("未知态才是 z3", normal.zoom > MapFallback.MIN_ZOOM)
    }
}
