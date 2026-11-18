package com.realsuntime.solartime.map

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 首屏并行探测的**纯函数**部分：选源/选级别（先换源、再降级）、渐进升级、探测缓存、瓦片坐标换算。
 *
 * 真发请求的部分在 `BasemapProbeRunner`（要网络与 BitmapFactory，不在单测范围）。
 */
class BasemapProbeTest {

    private fun tile(source: MapStyle, zoom: Int, hasContent: Boolean) =
        BasemapProbe.ProbeTile(source = source, zoom = zoom, hasContent = hasContent)

    private fun osm(zoom: Int, hasContent: Boolean) = tile(MapStyle.OSM, zoom, hasContent)
    private fun amap(zoom: Int, hasContent: Boolean) = tile(MapStyle.AMAP_VECTOR, zoom, hasContent)
    private fun esri(zoom: Int, hasContent: Boolean) = tile(MapStyle.ESRI, zoom, hasContent)

    /** 一次完整的五块探测：OSM z3/z12 + 高德 z12/z10/z3。 */
    private fun allTiles(
        osm3: Boolean,
        osm12: Boolean,
        amap12: Boolean,
        amap10: Boolean,
        amap3: Boolean,
    ) = listOf(
        osm(MapFallback.MIN_ZOOM, osm3),
        osm(MapFallback.DEFAULT_ZOOM, osm12),
        amap(MapFallback.DEFAULT_ZOOM, amap12),
        amap(10, amap10),
        amap(MapFallback.MIN_ZOOM, amap3),
    )

    // ------------------------------------------------------------ 先换源、再降级

    /** 境内（偏好高德）+ 高德 z12 空白 + OSM z12 有内容 → 选 OSM z12，不是降级到 z10/z3。 */
    @Test
    fun domesticFallsBackToOsmAtTheSameZoom() {
        val choice = BasemapProbe.decide(
            allTiles(osm3 = true, osm12 = true, amap12 = false, amap10 = false, amap3 = true),
            preferred = MapStyle.AMAP_VECTOR,
        )
        assertEquals(MapStyle.OSM, choice.source)
        assertEquals(MapFallback.DEFAULT_ZOOM, choice.zoom)
        assertFalse(choice.unavailable)
    }

    /** 境内 + 两源 z12 都有内容 → 用偏好源（高德）。 */
    @Test
    fun domesticPrefersAmapWhenBothHaveContentAtTheSameZoom() {
        val choice = BasemapProbe.decide(
            allTiles(osm3 = true, osm12 = true, amap12 = true, amap10 = true, amap3 = true),
            preferred = MapStyle.AMAP_VECTOR,
        )
        assertEquals(MapStyle.AMAP_VECTOR, choice.source)
        assertEquals(MapFallback.DEFAULT_ZOOM, choice.zoom)
    }

    /** 境外（偏好 OSM）+ OSM 空白 + 高德 z12 有内容 → 选高德 z12。 */
    @Test
    fun overseasFallsBackToAmapWhenOsmIsBlank() {
        val choice = BasemapProbe.decide(
            allTiles(osm3 = false, osm12 = false, amap12 = true, amap10 = true, amap3 = true),
            preferred = MapStyle.OSM,
        )
        assertEquals(MapStyle.AMAP_VECTOR, choice.source)
        assertEquals(MapFallback.DEFAULT_ZOOM, choice.zoom)
        assertFalse(choice.unavailable)
    }

    /** 两源 z12 都空白、高德 z10 有内容 → 高德 z10（降级只看两源都没有的级别）。 */
    @Test
    fun downgradesOnlyWhenNeitherSourceHasThatZoom() {
        val choice = BasemapProbe.decide(
            allTiles(osm3 = false, osm12 = false, amap12 = false, amap10 = true, amap3 = true),
            preferred = MapStyle.OSM,
        )
        assertEquals(MapStyle.AMAP_VECTOR, choice.source)
        assertEquals(10, choice.zoom)
    }

    /** 两源全空 → 「底图不可用」。 */
    @Test
    fun bothSourcesEmptyMeansUnavailable() {
        val choice = BasemapProbe.decide(
            allTiles(osm3 = false, osm12 = false, amap12 = false, amap10 = false, amap3 = false),
            preferred = MapStyle.OSM,
        )
        assertTrue(choice.unavailable)
        assertEquals(MapFallback.MIN_ZOOM, choice.zoom)
    }

    /** 一块都没回来（列表为空）→ 不可用。 */
    @Test
    fun noTilesMeansUnavailable() {
        assertTrue(BasemapProbe.decide(emptyList(), preferred = MapStyle.OSM).unavailable)
    }

    /** 南极中山站端到端：偏好按坐标算是 Esri；三家瓦片里外网源有内容就选它，而不是降级到 z3。 */
    @Test
    fun antarcticStationEndToEndPicksTheOverseasSourceAtDefaultZoom() {
        val preferred = MapStyle.AUTO.effective(-69.37, 76.38)
        assertEquals(MapStyle.ESRI, preferred)

        // Esri z12 有内容 → Esri z12
        val esriChoice = BasemapProbe.decide(
            tiles = listOf(
                esri(3, true), esri(12, true),
                osm(3, true), osm(12, true),
                amap(12, false), amap(10, false), amap(3, true),
            ),
            preferred = preferred,
        )
        assertEquals(MapStyle.ESRI, esriChoice.source)
        assertEquals(MapFallback.DEFAULT_ZOOM, esriChoice.zoom)

        // Esri 空白、OSM z12 有内容 → OSM z12（不是 z10/z3）
        val osmChoice = BasemapProbe.decide(
            tiles = listOf(
                esri(3, false), esri(12, false),
                osm(3, true), osm(12, true),
                amap(12, false), amap(10, false), amap(3, true),
            ),
            preferred = preferred,
        )
        assertEquals(MapStyle.OSM, osmChoice.source)
        assertEquals(MapFallback.DEFAULT_ZOOM, osmChoice.zoom)
        assertFalse(osmChoice.unavailable)
    }

    /** 三家 z12 都没内容时，先看 z10，再看 z3：z3 优先 Esri，其次高德。 */
    @Test
    fun globalFallbackPrefersEsriAtZoomThree() {
        val choice = BasemapProbe.decide(
            tiles = listOf(
                esri(3, true), esri(12, false),
                osm(3, false), osm(12, false),
                amap(12, false), amap(10, false), amap(3, true),
            ),
            preferred = MapStyle.ESRI,
        )
        assertEquals(MapStyle.ESRI, choice.source)
        assertEquals(MapFallback.MIN_ZOOM, choice.zoom)
        assertFalse(choice.unavailable)
    }

    /** Esri / OSM 都失败、高德 z12 有内容 → 高德 z12（三家顺序：Esri → OSM → 高德）。 */
    @Test
    fun amapIsTheLastResortOverseas() {
        val choice = BasemapProbe.decide(
            tiles = listOf(
                esri(3, false), esri(12, false),
                osm(3, false), osm(12, false),
                amap(12, true), amap(10, true), amap(3, true),
            ),
            preferred = MapStyle.ESRI,
        )
        assertEquals(MapStyle.AMAP_VECTOR, choice.source)
        assertEquals(MapFallback.DEFAULT_ZOOM, choice.zoom)
    }

    /**
     * Esri 瓦片地址顺序是 **z/y/x**（与 OSM 的 z/x/y 相反）：
     * z12 的上海（x=3430, y=1673）→ `…/tile/12/1673/3430`。
     */
    @Test
    fun esriTileUrlUsesZyxOrder() {
        val (x, y) = BasemapProbe.tileOf(31.2304, 121.4737, 12)
        assertEquals(3430 to 1673, x to y)
        assertEquals(
            "https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/12/1673/3430",
            MapTileSources.esriTileUrl("World_Street_Map", 12, x, y),
        )
        // 探针与运行期用的是同一个拼法（y 在前）。
        assertTrue(MapTileSources.esriTileUrl("World_Street_Map", 12, 3430, 1673).endsWith("/12/1673/3430"))
    }

    // ------------------------------------------------------------ 渐进升级（先到先用，更好的才换）

    private fun applied(source: MapStyle, zoom: Int) = BasemapProbe.AppliedChoice(source, zoom)

    private fun step(
        current: BasemapProbe.AppliedChoice?,
        source: MapStyle,
        zoom: Int,
        preferred: MapStyle,
        hasContent: Boolean = true,
        elapsedMillis: Long = 0L,
        firstPaintAtMillis: Long? = null,
        userMoved: Boolean = false,
    ): BasemapProbe.AppliedChoice? = BasemapProbe.nextApplied(
        current = current,
        source = source,
        zoom = zoom,
        hasContent = hasContent,
        elapsedMillis = elapsedMillis,
        firstPaintAtMillis = firstPaintAtMillis,
        userMoved = userMoved,
        preferred = preferred,
    )

    /** z3 先回、z12 后回：先用 z3 出图，再升级到 z12。 */
    @Test
    fun progressiveUpgradeFromZ3ToZ12() {
        val z3 = step(null, MapStyle.AMAP_VECTOR, 3, MapStyle.OSM, elapsedMillis = 312)
        assertEquals(applied(MapStyle.AMAP_VECTOR, 3), z3)

        val z12 = step(
            z3,
            MapStyle.AMAP_VECTOR,
            12,
            MapStyle.OSM,
            elapsedMillis = 1_830,
            firstPaintAtMillis = 312,
        )
        assertEquals(applied(MapStyle.AMAP_VECTOR, 12), z12)
    }

    /** 先高德 z10 出图，OSM z12 后到 → 升级到 OSM z12（级别更高，先换源再降级的逆过程）。 */
    @Test
    fun lateOsmZ12UpgradesFromAmapZ10() {
        val amap10 = step(null, MapStyle.AMAP_VECTOR, 10, MapStyle.OSM, elapsedMillis = 500)
        assertEquals(applied(MapStyle.AMAP_VECTOR, 10), amap10)

        val osm12 = step(
            amap10,
            MapStyle.OSM,
            12,
            MapStyle.OSM,
            elapsedMillis = 1_600,
            firstPaintAtMillis = 500,
        )
        assertEquals(applied(MapStyle.OSM, 12), osm12)
    }

    /** 同级别时偏好源更优：偏好高德时，OSM z12 先到 → 高德 z12 后到应升级（换回偏好源）。 */
    @Test
    fun preferredSourceWinsAtTheSameZoom() {
        val osm12 = applied(MapStyle.OSM, 12)
        val after = step(
            osm12,
            MapStyle.AMAP_VECTOR,
            12,
            MapStyle.AMAP_VECTOR,
            elapsedMillis = 900,
            firstPaintAtMillis = 300,
        )
        assertEquals(applied(MapStyle.AMAP_VECTOR, 12), after)
    }

    /** z12 先回、z3 后回：只用 z12，后到的 z3 被忽略（不降级）。 */
    @Test
    fun lateLowerZoomNeverDowngrades() {
        val z12 = step(null, MapStyle.AMAP_VECTOR, 12, MapStyle.OSM, elapsedMillis = 400)
        val afterZ3 = step(
            z12,
            MapStyle.AMAP_VECTOR,
            3,
            MapStyle.OSM,
            elapsedMillis = 900,
            firstPaintAtMillis = 400,
        )
        assertEquals(applied(MapStyle.AMAP_VECTOR, 12), afterZ3)
    }

    /** 已经「偏好源 z12」（最优）→ 后续一律忽略。 */
    @Test
    fun nothingUpgradesAfterBestChoice() {
        val best = applied(MapStyle.OSM, 12)
        assertTrue(BasemapProbe.isFrozen(best, elapsedSinceFirstPaintMillis = 0L, userMoved = false, preferred = MapStyle.OSM))
        assertEquals(best, step(best, MapStyle.AMAP_VECTOR, 12, MapStyle.OSM, elapsedMillis = 900, firstPaintAtMillis = 400))
        assertEquals(best, step(best, MapStyle.OSM, 13, MapStyle.OSM, elapsedMillis = 900, firstPaintAtMillis = 400))
    }

    /** 用户手动平移 / 缩放后：z12 晚到也不升级（保持用户视图）。 */
    @Test
    fun userGestureFreezesUpgrades() {
        val z3 = step(null, MapStyle.AMAP_VECTOR, 3, MapStyle.OSM, elapsedMillis = 312)
        val after = step(
            z3,
            MapStyle.AMAP_VECTOR,
            12,
            MapStyle.OSM,
            elapsedMillis = 1_830,
            firstPaintAtMillis = 312,
            userMoved = true,
        )
        assertEquals(z3, after)
    }

    /** 距首次出图超过 10 秒：不再升级；10 秒以内还可以。 */
    @Test
    fun upgradesStopTenSecondsAfterFirstPaint() {
        val z3 = step(null, MapStyle.AMAP_VECTOR, 3, MapStyle.OSM, elapsedMillis = 312)
        val within = step(
            z3,
            MapStyle.AMAP_VECTOR,
            12,
            MapStyle.OSM,
            elapsedMillis = 312 + 9_999,
            firstPaintAtMillis = 312,
        )
        assertEquals(applied(MapStyle.AMAP_VECTOR, 12), within)

        val tooLate = step(
            z3,
            MapStyle.AMAP_VECTOR,
            12,
            MapStyle.OSM,
            elapsedMillis = 312 + 10_000,
            firstPaintAtMillis = 312,
        )
        assertEquals(z3, tooLate)
    }

    /** 没内容的瓦片不会出图，也不会把已有选择改掉。 */
    @Test
    fun blankTilesNeverBecomeTheChoice() {
        assertNull(step(null, MapStyle.AMAP_VECTOR, 12, MapStyle.OSM, hasContent = false, elapsedMillis = 600))
        val z3 = applied(MapStyle.AMAP_VECTOR, 3)
        assertEquals(
            z3,
            step(
                z3,
                MapStyle.AMAP_VECTOR,
                12,
                MapStyle.OSM,
                hasContent = false,
                elapsedMillis = 900,
                firstPaintAtMillis = 300,
            ),
        )
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

        assertTrue(BasemapProbe.shouldProbe(key, lastKey = null, lastAtMillis = null, nowMillis = now))
        assertFalse(BasemapProbe.shouldProbe(key, key, now, now + 1_000L))
        assertTrue(
            BasemapProbe.shouldProbe(
                BasemapProbe.cacheKey(39.9042, 116.4074),
                lastKey = key,
                lastAtMillis = now,
                nowMillis = now + 1_000L,
            ),
        )
        assertTrue(BasemapProbe.shouldProbe(key, key, now, now + BasemapProbe.CACHE_MILLIS))
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
        // 巴黎 z3 → (4, 2)；迪拜 z3 → (5, 3)；北京 z12 → (3372, 1552)
        assertEquals(4 to 2, BasemapProbe.tileOf(48.8566, 2.3522, 3))
        assertEquals(5 to 3, BasemapProbe.tileOf(25.2048, 55.2708, 3))
        assertEquals(3372 to 1552, BasemapProbe.tileOf(39.9042, 116.4074, 12))
        // 边界不越界
        assertEquals(0 to 0, BasemapProbe.tileOf(85.0, -180.0, 3))
        assertEquals(7 to 7, BasemapProbe.tileOf(-85.0, 180.0, 3))
    }
}
