package com.realsuntime.solartime.map

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 未知态（定位不可用）的地图：**固定的 z3 全球图 + 专用快路径**。
 *
 * 快路径的规则（见 [UnknownBasemap]）：
 * * 有「上次成功出图的源」缓存 → 直接用，不探测；
 * * 没缓存 → 只探两块 z3 瓦片（OSM / 高德），2 秒封顶，先有内容者胜；
 * * 两块都失败 → 「底图不可用」，不降级。
 *
 * 正常态（[MapUiState.of]）的探测/回退/降级行为必须原样不变。
 */
class MapUnknownStateTest {

    private val now = 1_700_000_000_000L

    // ---- 未知态的 UI 状态 ----

    @Test
    fun unknownForcesTheGlobalBasemapZoom() {
        val auto = MapUiState.ofUnknown(MapStyle.AUTO, source = MapStyle.OSM, unavailable = false)
        assertEquals("未知态必须固定 z3", MapFallback.MIN_ZOOM, auto.zoom)
        assertEquals(3, auto.zoom)
        assertFalse("固定 z3 不是「被降级」", auto.degraded)
        assertFalse("有源时不是「底图不可用」", auto.unavailable)
        assertFalse("未知态没有回退概念", auto.fellBack)
        assertEquals(MapStyle.AUTO, auto.requested)
        assertEquals(MapStyle.OSM, auto.source)
        // 无坐标锚点仍然是 (0,0)：全球图不打标记、不沿用上一个城市。
        assertEquals(0.0, MapUiState.UNKNOWN_LATITUDE, 0.0)
        assertEquals(0.0, MapUiState.UNKNOWN_LONGITUDE, 0.0)
    }

    /** 缓存里的源是什么就用什么，哪怕它是高德（不会再按坐标重算一遍）。 */
    @Test
    fun unknownUsesTheCachedSourceAsIs() {
        val amap = MapUiState.ofUnknown(MapStyle.AUTO, source = MapStyle.AMAP_VECTOR, unavailable = false)
        assertEquals(MapStyle.AMAP_VECTOR, amap.source)
        assertEquals(MapFallback.MIN_ZOOM, amap.zoom)
        assertFalse(amap.unavailable)
        assertFalse(amap.fellBack)

        // 手动选的底图同样只是「设置里的 requested」，源按缓存走。
        val manual = MapUiState.ofUnknown(MapStyle.AMAP_SATELLITE, source = MapStyle.AMAP_VECTOR, unavailable = false)
        assertEquals(MapStyle.AMAP_SATELLITE, manual.requested)
        assertEquals(MapStyle.AMAP_VECTOR, manual.source)
    }

    /** 探测还没结论（source = null）时先挂一个兜底源，界面此时显示骨架、不建 MapView。 */
    @Test
    fun unknownWithoutSourceFallsBackToTheGlobalAnchor() {
        val pending = MapUiState.ofUnknown(MapStyle.AUTO, source = null, unavailable = false)
        assertEquals(
            MapStyle.AUTO.effective(MapUiState.UNKNOWN_LATITUDE, MapUiState.UNKNOWN_LONGITUDE),
            pending.source,
        )
        assertEquals(MapFallback.MIN_ZOOM, pending.zoom)
        assertFalse(pending.unavailable)
    }

    /** 两块都失败：直接「底图不可用」，级别仍是 z3（未知态没有级别可降）。 */
    @Test
    fun unknownShowsUnavailableWhenBothProbeTilesFail() {
        val unavailable = MapUiState.ofUnknown(MapStyle.AUTO, source = null, unavailable = true)
        assertTrue(unavailable.unavailable)
        assertEquals(MapFallback.MIN_ZOOM, unavailable.zoom)
        assertFalse("不降级：degraded 必须是 false", unavailable.degraded)
        assertFalse(unavailable.fellBack)
    }

    // ---- 快路径：缓存 ----

    @Test
    fun freshCacheMeansNoProbe() {
        assertFalse(
            "10 分钟内的缓存不该再探测",
            UnknownBasemap.shouldProbe(MapStyle.AMAP_VECTOR, now - 60_000L, now),
        )
        assertEquals(
            MapStyle.AMAP_VECTOR,
            UnknownBasemap.cachedSource(MapStyle.AMAP_VECTOR, now - 60_000L, now),
        )
        assertEquals(
            MapStyle.OSM,
            UnknownBasemap.cachedSource(MapStyle.OSM, now - UnknownBasemap.CACHE_MILLIS, now),
        )
    }

    @Test
    fun missingOrStaleCacheMeansProbe() {
        // 从没成功过。
        assertTrue(UnknownBasemap.shouldProbe(null, null, now))
        assertNull(UnknownBasemap.cachedSource(null, null, now))
        // 时刻缺失。
        assertTrue(UnknownBasemap.shouldProbe(MapStyle.OSM, 0L, now))
        // 过期（超过 10 分钟）。
        assertTrue(
            UnknownBasemap.shouldProbe(MapStyle.OSM, now - UnknownBasemap.CACHE_MILLIS - 1, now),
        )
        // 时钟回拨：宁可重探，也不用一个来路不明的时间戳。
        assertTrue(UnknownBasemap.shouldProbe(MapStyle.OSM, now + 60_000L, now))
        // AUTO 不是「源」。
        assertNull(UnknownBasemap.cachedSource(MapStyle.AUTO, now, now))
    }

    /** 命中缓存后再次进入未知态：不再探测（这是 ≤5 秒出图的关键路径）。 */
    @Test
    fun reenteringUnknownWithACachedSourceDoesNotProbeAgain() {
        // 第一次：没缓存 → 探一次，写缓存（模拟 ViewModel 的写入）。
        assertTrue(UnknownBasemap.shouldProbe(null, null, now))
        val cachedAt = now + UnknownBasemap.PROBE_DEADLINE_MILLIS
        val chosen = MapStyle.AMAP_VECTOR
        // 第二次（4 分钟后重新进入未知态）。
        val later = cachedAt + 4 * 60_000L
        assertFalse(UnknownBasemap.shouldProbe(chosen, cachedAt, later))
        assertEquals(chosen, UnknownBasemap.cachedSource(chosen, cachedAt, later))
        // 对应的地图状态也不再等探测：源已经定了。
        val ui = MapUiState.ofUnknown(MapStyle.AUTO, UnknownBasemap.cachedSource(chosen, cachedAt, later), false)
        assertEquals(chosen, ui.source)
        assertEquals(MapFallback.MIN_ZOOM, ui.zoom)
    }

    // ---- 快路径：探测集合与选择 ----

    /** 探测是三块 z3：ESRI / OSM / 高德（顺序即优先级；不再探 z12/z10，也没有「逐级降级」）。 */
    @Test
    fun probeCoversThreeZ3TilesInPriorityOrder() {
        assertEquals(3, UnknownBasemap.PROBE_TILES.size)
        assertEquals(3, UnknownBasemap.PROBE_CANDIDATES.size)
        assertEquals(
            listOf(MapStyle.ESRI, MapStyle.OSM, MapStyle.AMAP_VECTOR),
            UnknownBasemap.PROBE_CANDIDATES,
        )
        assertTrue("三块都必须是 z3", UnknownBasemap.PROBE_TILES.all { it.zoom == MapFallback.MIN_ZOOM })
        assertTrue(UnknownBasemap.PROBE_TILES.all { it.zoom == 3 })
        // 都是在东亚那块（x=6,y=2），不是纯色大洋瓦片。
        assertTrue(UnknownBasemap.PROBE_TILES.all { it.x == 6 && it.y == 2 })
        // ESRI 地址必须与运行期同一个拼法（z/y/x）。
        assertTrue(
            UnknownBasemap.PROBE_TILES.first { it.style == MapStyle.ESRI }.esriUrl
                .endsWith("/tile/3/2/6"),
        )
        // 探测别的级别会被断言抓住：正常态才探 z12/z10/z3。
        assertTrue(BasemapProbe.AMAP_PROBE_ZOOMS.any { it != MapFallback.MIN_ZOOM })
        // 封顶时间必须 ≤ 5 秒目标。
        assertTrue(UnknownBasemap.PROBE_DEADLINE_MILLIS in 1..5_000L)
        assertTrue(UnknownBasemap.TILE_TIMEOUT_MILLIS <= UnknownBasemap.PROBE_DEADLINE_MILLIS)
    }

    /** 选择按优先级 ESRI > OSM > 高德，而不是「谁先回来」。 */
    @Test
    fun chooseFollowsPriorityNotArrivalOrder() {
        // ESRI 有内容 → ESRI（哪怕 OSM/高德也有内容）
        assertEquals(
            MapStyle.ESRI,
            UnknownBasemap.choose(
                mapOf(MapStyle.ESRI to true, MapStyle.OSM to true, MapStyle.AMAP_VECTOR to true),
            ),
        )
        // ESRI 失败 + OSM 有 → OSM
        assertEquals(
            MapStyle.OSM,
            UnknownBasemap.choose(
                mapOf(MapStyle.ESRI to false, MapStyle.OSM to true, MapStyle.AMAP_VECTOR to true),
            ),
        )
        // ESRI/OSM 都失败 + 高德有 → 高德
        assertEquals(
            MapStyle.AMAP_VECTOR,
            UnknownBasemap.choose(
                mapOf(MapStyle.ESRI to false, MapStyle.OSM to false, MapStyle.AMAP_VECTOR to true),
            ),
        )
        // 只有高德还没结论时，ESRI 先到就有内容 → 还是 ESRI
        assertEquals(
            MapStyle.ESRI,
            UnknownBasemap.choose(mapOf(MapStyle.ESRI to true)),
        )
        // 全失败 / 都没回来 → 不可用
        assertNull(
            UnknownBasemap.choose(
                mapOf(MapStyle.ESRI to false, MapStyle.OSM to false, MapStyle.AMAP_VECTOR to false),
            ),
        )
        assertNull("三块都没回来 → 没有源", UnknownBasemap.choose(emptyMap()))
    }

    // ---- 正常态回归 ----

    /**
     * 正常态完全不受快路径影响：源按坐标算、级别从 z12 起、境外才需要并行探测。
     */
    @Test
    fun normalStateBehaviourIsUnchanged() {
        val china = MapUiState.of(MapStyle.AUTO, 31.23, 121.47, MapFallbackState())
        assertEquals("境内 → 高德", MapStyle.AMAP_VECTOR, china.source)
        assertEquals(MapFallback.DEFAULT_ZOOM, china.zoom)
        assertTrue("正常态从 z12 起，不是未知态的 z3", china.zoom > MapFallback.MIN_ZOOM)
        assertFalse(BasemapProbe.needsProbe(MapStyle.AUTO, 31.23, 121.47))

        val abroad = MapUiState.of(MapStyle.AUTO, 35.68, 139.65, MapFallbackState())
        assertEquals("境外 → Esri", MapStyle.ESRI, abroad.source)
        assertEquals(MapFallback.DEFAULT_ZOOM, abroad.zoom)
        assertTrue("正常态境外仍要并行探测", BasemapProbe.needsProbe(MapStyle.AUTO, 35.68, 139.65))
        // 正常态的探测级别集合仍是 z12/z10/z3（没被未知态的三块快路径改掉）。
        assertEquals(listOf(12, 10, 3), BasemapProbe.AMAP_PROBE_ZOOMS.toList())
    }
}
