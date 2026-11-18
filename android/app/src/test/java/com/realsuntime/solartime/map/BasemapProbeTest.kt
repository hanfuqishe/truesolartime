package com.realsuntime.solartime.map

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 首屏并行探测的**纯函数**部分：选源/选级别、探测缓存、瓦片坐标换算。
 *
 * 真发请求的部分在 `BasemapProbeRunner`（要网络与 BitmapFactory，不在单测范围）。
 */
class BasemapProbeTest {

    private fun amap(zoom: Int, hasContent: Boolean, kinds: Int = 0) =
        BasemapProbe.AmapProbe(zoom = zoom, hasContent = hasContent, colorKinds = kinds, fetched = true)

    // ------------------------------------------------------------ 四种组合

    @Test
    fun osmReachableWinsAndUsesDefaultZoom() {
        val choice = BasemapProbe.decide(
            osmReachable = true,
            amap = listOf(amap(12, true), amap(10, true), amap(3, true)),
        )
        assertEquals(MapStyle.OSM, choice.source)
        assertEquals(MapFallback.DEFAULT_ZOOM, choice.zoom)
        assertFalse(choice.unavailable)
    }

    @Test
    fun osmDownButAmapHasContentAtDefaultZoom() {
        val choice = BasemapProbe.decide(
            osmReachable = false,
            amap = listOf(amap(12, true), amap(10, true), amap(3, true)),
        )
        assertEquals(MapStyle.AMAP_VECTOR, choice.source)
        assertEquals(12, choice.zoom)
        assertFalse(choice.unavailable)
        assertTrue("摘要要写清楚高德那三块各自的结论", choice.summary.contains("z12 有内容"))
    }

    @Test
    fun osmDownAndOnlyLowerZoomsHaveContent() {
        // z12 空白、z10 空白、z3 有全球图 → 选 z3
        val onlyGlobal = BasemapProbe.decide(
            osmReachable = false,
            amap = listOf(amap(12, false, kinds = 1), amap(10, false, kinds = 1), amap(3, true, kinds = 6)),
        )
        assertEquals(MapStyle.AMAP_VECTOR, onlyGlobal.source)
        assertEquals(MapFallback.MIN_ZOOM, onlyGlobal.zoom)
        assertFalse(onlyGlobal.unavailable)

        // z12 空白、z10 有内容 → 选 z10（不是最差的 z3）
        val mid = BasemapProbe.decide(
            osmReachable = false,
            amap = listOf(amap(12, false, kinds = 1), amap(10, true, kinds = 40), amap(3, true, kinds = 6)),
        )
        assertEquals(10, mid.zoom)
    }

    @Test
    fun everythingBlankOrFailedMeansUnavailable() {
        val blank = BasemapProbe.decide(
            osmReachable = false,
            amap = listOf(amap(12, false), amap(10, false), amap(3, false)),
        )
        assertEquals(MapStyle.AMAP_VECTOR, blank.source)
        assertEquals(MapFallback.MIN_ZOOM, blank.zoom)
        assertTrue(blank.unavailable)

        // 全部网络失败（fetched=false）同样算不可用
        val failed = BasemapProbe.decide(
            osmReachable = false,
            amap = listOf(
                BasemapProbe.AmapProbe(12, false, fetched = false),
                BasemapProbe.AmapProbe(10, false, fetched = false),
                BasemapProbe.AmapProbe(3, false, fetched = false),
            ),
        )
        assertTrue(failed.unavailable)
    }

    @Test
    fun overallTimeoutCountsAsAllFailed() {
        // 超时被截断时 Runner 会用「全失败」的空结果喂进来（fetched=false）：
        // 决策必须落到「不可用」，而不是挑一块没拿到的瓦片。
        val timedOut = BasemapProbeResult(
            osmReachable = false,
            amap = BasemapProbe.AMAP_PROBE_ZOOMS.map { BasemapProbe.AmapProbe(it, false) },
            elapsedMillis = BasemapProbe.OVERALL_TIMEOUT_MILLIS,
            timedOut = true,
        )
        assertTrue(timedOut.choice.unavailable)
        assertEquals(MapStyle.AMAP_VECTOR, timedOut.choice.source)
    }

    // ------------------------------------------------------------ 降级链种子

    @Test
    fun zoomsAboveSeedsTheDegradeChain() {
        assertEquals(
            setOf(12, 11),
            BasemapProbe.zoomsAbove(BasemapProbe.Choice(MapStyle.AMAP_VECTOR, 10, false, "")),
        )
        assertEquals(
            setOf(12, 11, 10),
            BasemapProbe.zoomsAbove(BasemapProbe.Choice(MapStyle.AMAP_VECTOR, MapFallback.MIN_ZOOM, false, "")),
        )
        // 全空：连 z3 一起标，于是 zoomPlan 直接给出「底图不可用」
        assertEquals(
            setOf(12, 11, 10, MapFallback.MIN_ZOOM),
            BasemapProbe.zoomsAbove(BasemapProbe.Choice(MapStyle.AMAP_VECTOR, MapFallback.MIN_ZOOM, true, "")),
        )
        // OSM 选中：不需要动降级链
        assertEquals(
            emptySet<Int>(),
            BasemapProbe.zoomsAbove(BasemapProbe.Choice(MapStyle.OSM, MapFallback.DEFAULT_ZOOM, false, "")),
        )
    }

    // ------------------------------------------------------------ 缓存

    @Test
    fun probeCacheKeyFollowsTheCity() {
        val parisKey = BasemapProbe.cacheKey(48.8566, 2.3522)
        val beijingKey = BasemapProbe.cacheKey(39.9042, 116.4074)
        assertTrue(parisKey != beijingKey)
        // ~100m 以内的抖动算同一地点（GPS 漂移不该触发重探）
        assertTrue(BasemapProbe.cacheKey(48.85661, 2.35221) == parisKey)
    }

    @Test
    fun probeRunsOncePerPlaceAndAgainAfterFiveMinutes() {
        val key = BasemapProbe.cacheKey(48.8566, 2.3522)
        val now = 1_700_000_000_000L

        // 第一次：没探过 → 要探
        assertTrue(BasemapProbe.shouldProbe(key, lastKey = null, lastAtMillis = null, nowMillis = now))
        // 同地点、刚探过 → 不探
        assertFalse(BasemapProbe.shouldProbe(key, key, now, now + 1_000L))
        // 换城市 → 探
        assertTrue(
            BasemapProbe.shouldProbe(
                BasemapProbe.cacheKey(39.9042, 116.4074),
                lastKey = key,
                lastAtMillis = now,
                nowMillis = now + 1_000L,
            ),
        )
        // 过期 → 探
        assertTrue(BasemapProbe.shouldProbe(key, key, now, now + BasemapProbe.CACHE_MILLIS))
        // 用户切回自动（force）→ 探
        assertTrue(BasemapProbe.shouldProbe(key, key, now, now + 1_000L, force = true))
    }

    @Test
    fun onlyOverseasAutoModeNeedsProbe() {
        assertTrue(BasemapProbe.needsProbe(MapStyle.AUTO, 48.8566, 2.3522)) // 巴黎
        assertFalse(BasemapProbe.needsProbe(MapStyle.AUTO, 39.9042, 116.4074)) // 北京：境内直接高德
        assertFalse(BasemapProbe.needsProbe(MapStyle.AMAP_VECTOR, 48.8566, 2.3522)) // 手动：不探测
        assertFalse(BasemapProbe.needsProbe(MapStyle.OSM, 39.9042, 116.4074))
    }

    // ------------------------------------------------------------ 瓦片坐标

    @Test
    fun tileCoordinatesMatchTheWebMercatorScheme() {
        // 巴黎 z3 → (4, 2)；迪拜 z3 → (5, 3)；北京 z12 → (3371, 1552)
        assertEquals(4 to 2, BasemapProbe.tileOf(48.8566, 2.3522, 3))
        assertEquals(5 to 3, BasemapProbe.tileOf(25.2048, 55.2708, 3))
        assertEquals(3372 to 1552, BasemapProbe.tileOf(39.9042, 116.4074, 12))
        // 边界不越界
        assertEquals(0 to 0, BasemapProbe.tileOf(85.0, -180.0, 3))
        assertEquals(7 to 7, BasemapProbe.tileOf(-85.0, 180.0, 3))
    }
}
