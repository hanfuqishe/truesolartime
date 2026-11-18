package com.realsuntime.solartime.map

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 底图兜底：OSM 连不上时用高德顶上。
 *
 * 用例全跑在纯 JVM 上 —— [MapFallback] 是纯函数，[MapFallbackTracker] 只注入时钟与探测函数，
 * 不依赖 Android、网络或 osmdroid。
 */
class MapFallbackTest {

    /** 境外：首选 Esri 街道图。 */
    private val paris = 48.8566 to 2.3522

    /** 境内：首选高德。 */
    private val beijing = 39.9042 to 116.4074

    private val threshold = MapFallback.FAILURE_THRESHOLD

    /** 可控时钟：每个瓦片事件前都跨过「切源残响」窗口，计数才有确定性。 */
    private var now = 1_700_000_000_000L

    private fun newTracker(probe: () -> Boolean = { false }) =
        MapFallbackTracker(clock = { now }, probeOsm = probe)

    private fun advanceToNextTile() {
        now += MapFallback.SWITCH_SETTLE_MILLIS + 1_000L
    }

    private fun MapFallbackTracker.failTiles(
        times: Int,
        point: Pair<Double, Double> = paris,
        zoom: Int = MapFallback.DEFAULT_ZOOM,
        style: MapStyle = MapStyle.AUTO,
    ) = repeat(times) {
        advanceToNextTile()
        onTileFailed(style, point.first, point.second, zoom)
    }

    private fun MapFallbackTracker.loadTiles(
        times: Int = 1,
        point: Pair<Double, Double> = paris,
        zoom: Int = MapFallback.DEFAULT_ZOOM,
        style: MapStyle = MapStyle.AUTO,
    ) = repeat(times) {
        advanceToNextTile()
        onTileLoaded(style, point.first, point.second, zoom)
    }

    /**
     * 空白瓦片事件（高德回 200 但没内容，见 [TileBlank]）。
     *
     * **故意不推进时钟**：空白瓦片不吃「切源残响」窗口 —— 它一定是当前源刚画上来的瓦片
     * （切源时会清 tileCache），等 5 秒只会让用户多盯一会儿灰屏（见 [MapFallback.onTileBlank]）。
     */
    private fun MapFallbackTracker.blankTiles(
        times: Int,
        zoom: Int = MapFallback.DEFAULT_ZOOM,
        point: Pair<Double, Double> = paris,
        style: MapStyle = MapStyle.AUTO,
        colorKinds: Int = 3,
    ) = repeat(times) {
        onTileBlank(style, point.first, point.second, zoom, colorKinds)
    }

    private fun MapFallbackTracker.planAt(style: MapStyle, point: Pair<Double, Double>): MapTilePlan =
        plan(style, point.first, point.second)

    // ------------------------------------------------------------ 首选规则与署名

    @Test
    fun autoModeKeepsTheOldPreferredSource() {
        val tracker = newTracker()
        assertEquals(MapStyle.ESRI, tracker.planAt(MapStyle.AUTO, paris).effective)
        assertEquals(MapStyle.AMAP_VECTOR, tracker.planAt(MapStyle.AUTO, beijing).effective)
        // 手动选的源永远按用户选的来（境内境外都不改）
        assertEquals(MapStyle.OSM, tracker.planAt(MapStyle.OSM, beijing).effective)
        assertEquals(MapStyle.AMAP_SATELLITE, tracker.planAt(MapStyle.AMAP_SATELLITE, paris).effective)
    }

    @Test
    fun autoOverseasSuccessUsesOsmAndOsmAttribution() {
        val tracker = newTracker()
        tracker.loadTiles(5)
        val plan = tracker.planAt(MapStyle.AUTO, paris)
        assertEquals(MapStyle.ESRI, plan.effective)
        assertFalse(plan.fellBack)
        // 署名跟随实际使用的瓦片源（MapText.attribution 就是按 MapStyle 取这两条资源）
        assertEquals("底图 © Esri, HERE, Garmin, © OpenStreetMap contributors", plan.effective.attribution)
    }

    // ------------------------------------------------------------ 回退与记忆

    @Test
    fun osmFailsThreeTimesThenFallsBackToAmapFromTheFourthOnwards() {
        val tracker = newTracker()
        // 前两次失败还在试 OSM
        tracker.failTiles(threshold - 1)
        assertEquals(MapStyle.ESRI, tracker.planAt(MapStyle.AUTO, paris).effective)
        assertFalse(tracker.planAt(MapStyle.AUTO, paris).fellBack)

        // 第 3 次失败：达到阈值 → 回退
        tracker.failTiles(1)
        val fallenBack = tracker.planAt(MapStyle.AUTO, paris)
        assertEquals(MapStyle.AMAP_VECTOR, fallenBack.effective)
        assertTrue(fallenBack.fellBack)
        assertEquals(threshold, fallenBack.fallbackFailures)
        assertEquals("底图 © 高德地图", fallenBack.effective.attribution)

        // 第 4 次及以后：直接用高德，不再先让每张 OSM 瓦片失败一遍
        tracker.failTiles(4)
        assertEquals(MapStyle.AMAP_VECTOR, tracker.planAt(MapStyle.AUTO, paris).effective)
        assertEquals(threshold, tracker.planAt(MapStyle.AUTO, paris).fallbackFailures)
    }

    @Test
    fun osmSuccessClearsTheFailureStreak() {
        val tracker = newTracker()
        tracker.failTiles(threshold - 1)
        tracker.loadTiles()
        assertEquals(0, tracker.snapshot().osmFailures)

        // 中途成功过 → 重新从 0 开始数，不该凑够阈值就回退
        tracker.failTiles(threshold - 1)
        val plan = tracker.planAt(MapStyle.AUTO, paris)
        assertEquals(MapStyle.ESRI, plan.effective)
        assertFalse(plan.fellBack)
    }

    @Test
    fun failuresRightAfterTheSwitchAreIgnored() {
        val tracker = newTracker()
        tracker.failTiles(threshold) // 第 3 次触发回退，switchedAt = now

        // 切换瞬间还在飞的旧 OSM 请求紧接着失败：不能算成「高德这一级没瓦片」
        repeat(threshold + 2) { tracker.onTileFailed(MapStyle.AUTO, paris.first, paris.second, 12) }

        assertTrue(tracker.snapshot().fellBack)
        assertEquals(12, tracker.zoomPlan(tracker.planAt(MapStyle.AUTO, paris), 12).zoom)

        // 窗口过去后，真没瓦片仍然能被诊断出来
        tracker.failTiles(threshold, zoom = 12)
        assertEquals(11, tracker.zoomPlan(tracker.planAt(MapStyle.AUTO, paris), 12).zoom)
    }

    // ------------------------------------------------------------ 5 分钟探测 / 网络恢复

    @Test
    fun probeRestoresOsmAfterCooldownAndClearsTheCounter() {
        var reachable = false
        val tracker = newTracker(probe = { reachable })
        tracker.failTiles(threshold)

        val fallenBack = tracker.planAt(MapStyle.AUTO, paris)
        assertEquals(MapStyle.AMAP_VECTOR, fallenBack.effective)
        assertEquals(now + MapFallback.PROBE_INTERVAL_MILLIS, fallenBack.probeAtMillis ?: -1L)

        // 冷却没到：不探测
        now += MapFallback.PROBE_INTERVAL_MILLIS - 1
        assertFalse(tracker.probeIfDue())

        // 冷却到点 + 网络恢复：探测成功 → 切回 OSM、失败计数清零
        now += 1
        reachable = true
        assertTrue(tracker.probeIfDue())
        val restored = tracker.planAt(MapStyle.AUTO, paris)
        assertEquals(MapStyle.ESRI, restored.effective)
        assertFalse(restored.fellBack)
        assertEquals(0, tracker.snapshot().osmFailures)
        assertNull(tracker.snapshot().probeAtMillis)
    }

    @Test
    fun probeFailureKeepsAmapAndSchedulesTheNextProbe() {
        val tracker = newTracker(probe = { false })
        tracker.failTiles(threshold)

        now += MapFallback.PROBE_INTERVAL_MILLIS
        assertTrue(tracker.probeIfDue())
        assertEquals(MapStyle.AMAP_VECTOR, tracker.planAt(MapStyle.AUTO, paris).effective)
        val state = tracker.snapshot()
        assertTrue(state.fellBack)
        assertEquals(now + MapFallback.PROBE_INTERVAL_MILLIS, state.probeAtMillis ?: -1L)
        // 冷却刚推后，立刻再问也不会重复发请求
        assertFalse(tracker.probeIfDue())
    }

    @Test
    fun autoInsideChinaNeverProbes() {
        val tracker = newTracker()
        val plan = tracker.planAt(MapStyle.AUTO, beijing)
        assertEquals(MapStyle.AMAP_VECTOR, plan.effective)
        assertFalse(plan.fellBack)
        assertFalse(tracker.probeIfDue())
        assertNull(tracker.snapshot().probeAtMillis)
    }

    // ------------------------------------------------------------ 手动选择：不回退、不探测

    @Test
    fun manualOsmNeverFallsBackAndNeverProbes() {
        var probes = 0
        val tracker = newTracker(probe = { probes++; true })
        tracker.failTiles(10, style = MapStyle.OSM)

        val plan = tracker.planAt(MapStyle.OSM, paris)
        assertEquals(MapStyle.OSM, plan.effective)
        assertFalse(plan.fellBack)
        assertEquals("地图数据 © OpenStreetMap 贡献者", plan.effective.attribution)
        assertEquals(0, tracker.snapshot().osmFailures)

        now += MapFallback.PROBE_INTERVAL_MILLIS * 3
        assertFalse(tracker.probeIfDue())
        assertEquals(0, probes)
    }

    @Test
    fun manualAmapAlwaysStaysAmap() {
        val tracker = newTracker()
        assertEquals(MapStyle.AMAP_VECTOR, tracker.planAt(MapStyle.AMAP_VECTOR, paris).effective)
        assertEquals(MapStyle.AMAP_SATELLITE, tracker.planAt(MapStyle.AMAP_SATELLITE, paris).effective)
        // 手动高德就算失败也不改源、不探测
        tracker.failTiles(threshold * 2, style = MapStyle.AMAP_VECTOR)
        assertEquals(MapStyle.AMAP_VECTOR, tracker.planAt(MapStyle.AMAP_VECTOR, paris).effective)
        assertFalse(tracker.probeIfDue())
        assertEquals(0, tracker.snapshot().osmFailures)
    }

    // ------------------------------------------------------------ 记忆重置

    @Test
    fun switchingToAutoAndChoosingAnotherCityResetsTheMemory() {
        val tracker = newTracker()
        tracker.failTiles(threshold)
        assertTrue(tracker.planAt(MapStyle.AUTO, paris).fellBack)

        // MainViewModel 在「切到自动」或「用户重新选地点」时调 reset()
        tracker.reset()
        val plan = tracker.planAt(MapStyle.AUTO, paris)
        assertEquals(MapStyle.ESRI, plan.effective)
        assertFalse(plan.fellBack)
        assertEquals(0, tracker.snapshot().osmFailures)

        // 换回境内城市：本来就是高德，且不带任何回退标记
        val home = tracker.planAt(MapStyle.AUTO, beijing)
        assertEquals(MapStyle.AMAP_VECTOR, home.effective)
        assertFalse(home.fellBack)
    }

    // ------------------------------------------------------------ 缩放降级链

    @Test
    fun missingZoomDegradesStepByStepToALowerLevelWithTiles() {
        val tracker = newTracker()
        tracker.failTiles(threshold) // OSM 失败 → 回退到高德
        val plan = tracker.planAt(MapStyle.AUTO, paris)
        assertTrue(plan.fellBack)

        // 高德 z12 也没瓦片 → 降 1 级
        tracker.failTiles(threshold, zoom = 12)
        val at11 = tracker.zoomPlan(plan, 12)
        assertEquals(11, at11.zoom)
        assertTrue(at11.degraded)
        assertFalse(at11.unavailable)

        // z11 也没有 → 再降 1 级（最多降 2 级，所以止步 z10）
        tracker.failTiles(threshold, zoom = 11)
        val at10 = tracker.zoomPlan(plan, 12)
        assertEquals(10, at10.zoom)
        assertTrue(at10.degraded)
        assertFalse(at10.unavailable)
    }

    @Test
    fun exhaustedChainFallsBackToTheLowestGlobalLevel() {
        val tracker = newTracker()
        tracker.failTiles(threshold)
        val plan = tracker.planAt(MapStyle.AUTO, paris)
        listOf(12, 11, 10).forEach { tracker.failTiles(threshold, zoom = it) }

        // 逐级下探都试过了 → 用最低级别的全球底图（尚未试过，所以还不算「不可用」）
        val floor = tracker.zoomPlan(plan, 12)
        assertEquals(MapFallback.MIN_ZOOM, floor.zoom)
        assertTrue(floor.degraded)
        assertFalse(floor.unavailable)
    }

    @Test
    fun noNetworkAtAllShowsBaseMapUnavailableAndRecoversLater() {
        val tracker = newTracker()
        tracker.failTiles(threshold)
        val plan = tracker.planAt(MapStyle.AUTO, paris)
        listOf(12, 11, 10, MapFallback.MIN_ZOOM).forEach { tracker.failTiles(threshold, zoom = it) }

        val offline = tracker.zoomPlan(plan, 12)
        assertEquals(MapFallback.MIN_ZOOM, offline.zoom)
        assertTrue(offline.unavailable) // 界面显示「底图不可用」，不是一块空白

        // 网络回来：最低级别出图 + 安静够久 → 「某级别没瓦片」的记忆被清掉，缩放回到默认级别
        now += MapFallback.RECOVERY_QUIET_MILLIS + MapFallback.RECOVERY_COOLDOWN_MILLIS
        tracker.loadTiles(zoom = MapFallback.MIN_ZOOM)
        val recovered = tracker.zoomPlan(tracker.planAt(MapStyle.AUTO, paris), 12)
        assertEquals(12, recovered.zoom)
        assertFalse(recovered.unavailable)
    }

    /**
     * 真机上「地图狂闪」的根因回归：网络一直坏时，z3 一出图就把降级链弹回 z12，
     * z12 又失败 → 再降到 z3 → 又弹回……实测 2 秒内 441 次状态发布、缩放 3↔12↔11↔10 狂跳。
     * 现在要求「安静 30 秒 + 距上次恢复尝试 5 分钟」，网络坏时必须原地不动。
     */
    @Test
    fun globalTileLoadDoesNotBounceBackWhileTheNetworkKeepsFailing() {
        val tracker = newTracker()
        tracker.failTiles(threshold)
        val plan = tracker.planAt(MapStyle.AUTO, paris)
        listOf(12, 11, 10, MapFallback.MIN_ZOOM).forEach { tracker.failTiles(threshold, zoom = it) }
        assertEquals(MapFallback.MIN_ZOOM, tracker.zoomPlan(plan, 12).zoom)

        // 刚失败完（1 秒后）z3 就出图：不允许弹回
        now += 1_000L
        tracker.loadTiles(zoom = MapFallback.MIN_ZOOM)
        assertEquals(MapFallback.MIN_ZOOM, tracker.zoomPlan(plan, 12).zoom)

        // 安静够久：允许弹一次
        now += MapFallback.RECOVERY_QUIET_MILLIS
        tracker.loadTiles(zoom = MapFallback.MIN_ZOOM)
        assertEquals(12, tracker.zoomPlan(plan, 12).zoom)

        // 回去仍然失败（网络没真恢复）→ 再降下来；冷却期内不许再弹回
        listOf(12, 11, 10, MapFallback.MIN_ZOOM).forEach {
            now += MapFallback.VIEWPORT_SETTLE_MILLIS + 500L // 越过「视口残响」窗口
            tracker.failTiles(threshold, zoom = it)
        }
        assertEquals(MapFallback.MIN_ZOOM, tracker.zoomPlan(plan, 12).zoom)
        now += MapFallback.RECOVERY_QUIET_MILLIS + 1_000L
        tracker.loadTiles(zoom = MapFallback.MIN_ZOOM)
        assertEquals("冷却期内不许再弹回", MapFallback.MIN_ZOOM, tracker.zoomPlan(plan, 12).zoom)
    }

    /**
     * 第二条真机回归：`setCenter` / `setZoom` 会取消在飞的瓦片请求，osmdroid 对取消的请求也报失败。
     * 这些失败若照常计数 → 判该级别没瓦片 → 再改级别 → 又取消一批 → 自激循环（狂闪的另一半）。
     */
    @Test
    fun failuresRightAfterAProgrammaticViewportChangeAreIgnored() {
        val tracker = newTracker()
        tracker.failTiles(threshold)
        val plan = tracker.planAt(MapStyle.AUTO, paris)
        assertTrue(plan.fellBack)

        // 刚程序化改过视口：这一批「失败」是被取消的旧请求，不能算
        tracker.onZoomApplied(12)
        repeat(threshold * 3) {
            now += 10L
            tracker.onTileFailed(MapStyle.AUTO, paris.first, paris.second, 12)
        }
        assertEquals(0, tracker.snapshot().zoomFailures)
        assertEquals(12, tracker.zoomPlan(plan, 12).zoom)
        assertFalse(tracker.snapshot().zoomUnavailable(MapStyle.AMAP_VECTOR, 12))

        // 窗口过去后，真没网仍然能被诊断出来
        now += MapFallback.VIEWPORT_SETTLE_MILLIS
        tracker.failTiles(threshold, zoom = 12)
        assertEquals(11, tracker.zoomPlan(plan, 12).zoom)
    }

    /** 视口残响只该保护高德：OSM 的失败是「网络不通」的证据，不能被它吞掉（否则回退会变慢）。 */
    @Test
    fun viewportSettleDoesNotSwallowOsmFailures() {
        val tracker = newTracker()
        tracker.onZoomApplied(12) // 刚切完城市，视口残响窗口开着
        tracker.failTiles(threshold) // OSM 连不上
        val plan = tracker.planAt(MapStyle.AUTO, paris)
        assertTrue("OSM 失败必须照常累计并回退", plan.fellBack)
        assertEquals(MapStyle.AMAP_VECTOR, plan.effective)
    }

    // ------------------------------------------------------------ 空白瓦片：一次即降级

    @Test
    fun aSingleBlankViewportDegradesOneLevel() {
        // 空白是确定性判据（有内容就是有内容），不像网络失败会抖 → 一次就降一级。
        val tracker = newTracker()
        tracker.failTiles(threshold) // 先回退到高德
        val plan = tracker.planAt(MapStyle.AUTO, paris)
        assertEquals(12, tracker.zoomPlan(plan, 12).zoom)

        tracker.blankTiles(1, zoom = 12)
        assertEquals(11, tracker.zoomPlan(plan, 12).zoom)
        assertEquals(1, tracker.snapshot().blankTileCount)
    }

    // ------------------------------------------------------------ 首屏并行探测：直接定源与级别

    @Test
    fun probeResultPicksTheSourceAndZoomDirectly() {
        val tracker = newTracker()
        val key = BasemapProbe.cacheKey(paris.first, paris.second)

        // OSM 通 → OSM + 默认级别
        tracker.onProbeResult(
            MapStyle.AUTO,
            paris.first,
            paris.second,
            key,
            BasemapProbeResult(
                preferred = MapStyle.OSM,
                tiles = listOf(
                    BasemapProbe.ProbeTile(MapStyle.OSM, 3, hasContent = true),
                    BasemapProbe.ProbeTile(MapStyle.OSM, 12, hasContent = true),
                ),
                elapsedMillis = 300,
            ),
        )
        var plan = tracker.planAt(MapStyle.AUTO, paris)
        assertEquals(MapStyle.ESRI, plan.effective)
        assertFalse(plan.fellBack)
        assertEquals(12, tracker.zoomPlan(plan, 12).zoom)

        // OSM 不通 + 高德只有 z10 有内容 → 高德 + 直接落 z10（不再逐级降）
        tracker.onProbeResult(
            MapStyle.AUTO,
            paris.first,
            paris.second,
            key,
            BasemapProbeResult(
                preferred = MapStyle.OSM,
                tiles = listOf(
                    BasemapProbe.ProbeTile(MapStyle.OSM, 3, hasContent = false),
                    BasemapProbe.ProbeTile(MapStyle.OSM, 12, hasContent = false),
                    BasemapProbe.ProbeTile(MapStyle.AMAP_VECTOR, 12, hasContent = false),
                    BasemapProbe.ProbeTile(MapStyle.AMAP_VECTOR, 10, hasContent = true),
                    BasemapProbe.ProbeTile(MapStyle.AMAP_VECTOR, 3, hasContent = true),
                ),
                elapsedMillis = 900,
            ),
        )
        plan = tracker.planAt(MapStyle.AUTO, paris)
        assertEquals(MapStyle.AMAP_VECTOR, plan.effective)
        assertTrue(plan.fellBack)
        assertEquals(10, tracker.zoomPlan(plan, 12).zoom)
        assertTrue(tracker.snapshot().probeSummary?.contains("z10 有内容") == true)

        // 高德全空 → 底图不可用
        tracker.onProbeResult(
            MapStyle.AUTO,
            paris.first,
            paris.second,
            key,
            BasemapProbeResult(
                preferred = MapStyle.OSM,
                tiles = listOf(3, 12).map {
                    BasemapProbe.ProbeTile(MapStyle.OSM, it, hasContent = false)
                } + BasemapProbe.AMAP_PROBE_ZOOMS.map {
                    BasemapProbe.ProbeTile(MapStyle.AMAP_VECTOR, it, hasContent = false)
                },
                elapsedMillis = 800,
            ),
        )
        plan = tracker.planAt(MapStyle.AUTO, paris)
        val offline = tracker.zoomPlan(plan, 12)
        assertEquals(MapFallback.MIN_ZOOM, offline.zoom)
        assertTrue(offline.unavailable)
    }

    @Test
    fun probeResultIsIgnoredInsideChinaAndInManualMode() {
        val key = BasemapProbe.cacheKey(beijing.first, beijing.second)
        val choice = BasemapProbeResult(MapStyle.OSM, emptyList(), elapsedMillis = 100)

        // 境内：首选就是高德，探测结论不该改任何东西（尤其不该把 z12 标成没内容）
        val tracker = newTracker()
        tracker.onProbeResult(MapStyle.AUTO, beijing.first, beijing.second, key, choice)
        val plan = tracker.planAt(MapStyle.AUTO, beijing)
        assertEquals(MapStyle.AMAP_VECTOR, plan.effective)
        assertFalse(plan.fellBack)
        assertEquals(12, tracker.zoomPlan(plan, 12).zoom)
        assertEquals(null, tracker.snapshot().probeKey)

        // 手动选择：不探测、不改源
        tracker.onProbeResult(MapStyle.AMAP_SATELLITE, paris.first, paris.second, key, choice)
        assertEquals(MapStyle.AMAP_SATELLITE, tracker.planAt(MapStyle.AMAP_SATELLITE, paris).effective)
        assertEquals(null, tracker.snapshot().probeKey)
    }

    @Test
    fun probeCacheIsFreshForTheSamePlaceOnly() {
        val tracker = newTracker()
        val key = BasemapProbe.cacheKey(paris.first, paris.second)
        assertFalse("没探过不算新鲜", tracker.probeFresh(key))

        tracker.onProbeResult(
            MapStyle.AUTO,
            paris.first,
            paris.second,
            key,
            BasemapProbeResult(
                preferred = MapStyle.OSM,
                tiles = listOf(BasemapProbe.ProbeTile(MapStyle.OSM, 12, hasContent = true)),
                elapsedMillis = 200,
            ),
        )
        assertTrue("同地点刚探过 → 缓存命中", tracker.probeFresh(key))
        assertFalse("换城市 → 必须重探", tracker.probeFresh(BasemapProbe.cacheKey(beijing.first, beijing.second)))

        // 5 分钟后过期
        now += BasemapProbe.CACHE_MILLIS + 1_000L
        assertTrue("过期 → 重探", BasemapProbe.shouldProbe(key, key, now - BasemapProbe.CACHE_MILLIS - 1_000L, now))
    }

    // ------------------------------------------------------------ 只有「有效 plan」变化才对外发状态

    @Test
    fun uiStateOnlyChangesWhenTheEffectivePlanChanges() {
        // 同一份 plan 下，纯计数（失败次数 / 空白次数 / 连续失败）怎么变，UI 状态都必须相等 ——
        // 否则每块瓦片都会让 MapCard 重组一次（真机上的狂闪就是 441 次发布）。
        val base = MapUiState.of(MapStyle.AUTO, paris.first, paris.second, MapFallbackState())
        val noisy = MapUiState.of(
            MapStyle.AUTO,
            paris.first,
            paris.second,
            MapFallbackState(
                osmFailures = 2,
                zoomFailures = 2,
                lastFailedZoom = 12,
                blankTileCount = 7,
                lastBlankZoom = 12,
                lastBlankColorKinds = 3,
                lastFailedAtMillis = now,
                switchedAtMillis = now,
            ),
        )
        assertEquals(base, noisy)

        // 回退（换成高德）→ 必须变
        val fallenBackState = MapFallbackState(fellBack = true, fallbackFailures = MapFallback.FAILURE_THRESHOLD)
        val fallenBack = MapUiState.of(MapStyle.AUTO, paris.first, paris.second, fallenBackState)
        assertNotEquals(base, fallenBack)
        assertEquals(MapStyle.AMAP_VECTOR, fallenBack.source)
        assertTrue(fallenBack.fellBack)

        // 降级（z12 判没瓦片）→ 必须变
        val degraded = MapUiState.of(
            MapStyle.AUTO,
            paris.first,
            paris.second,
            MapFallbackState(fellBack = true, fallbackFailures = 1, unavailableZooms = mapOf(MapStyle.AMAP_VECTOR to setOf(12))),
        )
        assertNotEquals(fallenBack, degraded)
        assertEquals(11, degraded.zoom)
        assertTrue(degraded.degraded)

        // 连 z3 也没瓦片 → 「底图不可用」必须变
        val offline = MapUiState.of(
            MapStyle.AUTO,
            paris.first,
            paris.second,
            MapFallbackState(
                fellBack = true,
                fallbackFailures = 1,
                unavailableZooms = mapOf(MapStyle.AMAP_VECTOR to setOf(12, 11, 10, MapFallback.MIN_ZOOM)),
            ),
        )
        assertNotEquals(degraded, offline)
        assertTrue(offline.unavailable)
        assertEquals(MapFallback.MIN_ZOOM, offline.zoom)
    }

    @Test
    fun amapFailuresInsideChinaDoNotTriggerOsmFallbackButDoDegrade() {
        val tracker = newTracker()
        tracker.failTiles(threshold * 2, point = beijing, zoom = 12)

        val plan = tracker.planAt(MapStyle.AUTO, beijing)
        assertEquals(MapStyle.AMAP_VECTOR, plan.effective)
        assertFalse(plan.fellBack)
        assertEquals(0, tracker.snapshot().osmFailures)
        assertEquals(11, tracker.zoomPlan(plan, 12).zoom)
    }

    @Test
    fun manualZoomNeverDegrades() {
        val tracker = newTracker()
        tracker.failTiles(10, style = MapStyle.AMAP_VECTOR, zoom = 15)
        val plan = tracker.planAt(MapStyle.AMAP_VECTOR, paris)
        val zoom = tracker.zoomPlan(plan, 15)
        assertEquals(15, zoom.zoom)
        assertFalse(zoom.degraded)
        assertFalse(zoom.unavailable)
    }

    @Test
    fun zoomPlanResolvesAgainstInjectedTileAvailability() {
        // 「哪些级别有瓦片」是注入进纯函数的：这里直接给状态塞一份不可用级别表
        val fallenBack = MapFallbackState(fellBack = true, fallbackFailures = threshold)
        val plan = MapFallback.plan(MapStyle.AUTO, paris.first, paris.second, fallenBack)
        assertEquals(MapStyle.AMAP_VECTOR, plan.effective)

        // z12、z11 没瓦片 → 降 2 级到 z10
        val noHighZooms = fallenBack.copy(
            unavailableZooms = mapOf(MapStyle.AMAP_VECTOR to setOf(12, 11)),
        )
        val degraded = MapFallback.zoomPlan(plan, 12, noHighZooms)
        assertEquals(10, degraded.zoom)
        assertTrue(degraded.degraded)
        assertFalse(degraded.unavailable)

        // 连最低级别都没有瓦片 → 「底图不可用」
        val nothing = fallenBack.copy(
            unavailableZooms = mapOf(MapStyle.AMAP_VECTOR to setOf(12, 11, 10, MapFallback.MIN_ZOOM)),
        )
        val offline = MapFallback.zoomPlan(plan, 12, nothing)
        assertEquals(MapFallback.MIN_ZOOM, offline.zoom)
        assertTrue(offline.unavailable)
    }

    // ------------------------------------------------------------ 空白瓦片：按失败处理

    @Test
    fun blankAmapTilesDegradeExactlyLikeRealFailures() {
        val tracker = newTracker()
        tracker.failTiles(threshold) // OSM 失败 → 回退高德
        val plan = tracker.planAt(MapStyle.AUTO, paris)
        assertTrue(plan.fellBack)
        assertEquals(12, tracker.zoomPlan(plan, 12).zoom)

        // 高德 z12 连来三块空白：与三次真实失败一样，判「这一级没瓦片」→ 降到 z11
        tracker.blankTiles(threshold)
        val degraded = tracker.zoomPlan(plan, 12)
        assertEquals(11, degraded.zoom)
        assertTrue(degraded.degraded)
        assertFalse(degraded.unavailable)

        // 同一个失败路径也用掉了「同一级别连续失败」计数：够阈值就清零重新数
        assertEquals(0, tracker.snapshot().zoomFailures)
        // 另记一份诊断计数：触发几次、最近一次的级别与颜色种类
        assertEquals(threshold, tracker.snapshot().blankTileCount)
        assertEquals(12, tracker.snapshot().lastBlankZoom)
        assertEquals(3, tracker.snapshot().lastBlankColorKinds)
    }

    @Test
    fun blankTilesWalkTheWholeDegradeChainDownToTheGlobalMap() {
        val tracker = newTracker()
        tracker.failTiles(threshold)
        val plan = tracker.planAt(MapStyle.AUTO, paris)

        tracker.blankTiles(threshold, zoom = 12)
        assertEquals(11, tracker.zoomPlan(plan, 12).zoom)

        tracker.blankTiles(threshold, zoom = 11)
        assertEquals(10, tracker.zoomPlan(plan, 12).zoom)

        tracker.blankTiles(threshold, zoom = 10)
        val global = tracker.zoomPlan(plan, 12)
        assertEquals(MapFallback.MIN_ZOOM, global.zoom)
        assertTrue(global.degraded)
        assertFalse("z3 还没试过，先不算「不可用」", global.unavailable)
    }

    @Test
    fun blankGlobalTileKeepsBaseMapUnavailableInsteadOfLooping() {
        val tracker = newTracker()
        tracker.failTiles(threshold)
        val plan = tracker.planAt(MapStyle.AUTO, paris)
        listOf(12, 11, 10).forEach { tracker.blankTiles(threshold, zoom = it) }

        // 降到 z3 全球图还是空白：保持现状（界面写「底图不可用」），不再无限往下探
        tracker.blankTiles(threshold, zoom = MapFallback.MIN_ZOOM)
        val bottom = tracker.zoomPlan(plan, 12)
        assertEquals(MapFallback.MIN_ZOOM, bottom.zoom)
        assertTrue(bottom.unavailable)
    }

    @Test
    fun blankLearnedZoomStaysDegradedWhenTheGlobalTileHasContent() {
        val tracker = newTracker()
        tracker.failTiles(threshold)
        val plan = tracker.planAt(MapStyle.AUTO, paris)
        listOf(12, 11, 10).forEach { tracker.blankTiles(threshold, zoom = it) }
        assertEquals(MapFallback.MIN_ZOOM, tracker.zoomPlan(plan, 12).zoom)

        // z3 的全球底图**有内容**（真机实测：高德 z3 是全球海陆图）：不能因此把
        // 「z12/z11/z10 是空白」忘掉再弹回去，否则地图会在「z3 有图」和「z12 一片灰」之间来回跳，
        // 而且第二次 z12 的空白瓦片已在缓存里、不会再有成功回调 —— 跳回去就再也降不下来。
        tracker.loadTiles(zoom = MapFallback.MIN_ZOOM)
        val stable = tracker.zoomPlan(plan, 12)
        assertEquals(MapFallback.MIN_ZOOM, stable.zoom)
        assertTrue(stable.degraded)
        assertFalse(stable.unavailable)

        // 但真在 z12 画出一块有内容的瓦片时（高德恢复了 / 换到有数据的地区），记忆必须清掉
        tracker.loadTiles(zoom = 12)
        assertEquals(12, tracker.zoomPlan(plan, 12).zoom)
    }

    @Test
    fun blankTilesInManualModeOnlyCountAndNeverDegrade() {
        val tracker = newTracker()
        tracker.blankTiles(10, zoom = 15, style = MapStyle.AMAP_VECTOR)

        val plan = tracker.planAt(MapStyle.AMAP_VECTOR, paris)
        assertEquals(MapStyle.AMAP_VECTOR, plan.effective)
        val zoom = tracker.zoomPlan(plan, 15)
        assertEquals(15, zoom.zoom)
        assertFalse(zoom.degraded)
        assertFalse(zoom.unavailable)
        // 手动模式不参与失败统计，但诊断上仍要看得出「见过空白瓦片」
        assertEquals(0, tracker.snapshot().zoomFailures)
        assertEquals(0, tracker.snapshot().osmFailures)
        assertEquals(10, tracker.snapshot().blankTileCount)
        assertEquals(15, tracker.snapshot().lastBlankZoom)
    }

    @Test
    fun aRealTileClearsTheBlankVerdict() {
        val tracker = newTracker()
        tracker.failTiles(threshold)
        val plan = tracker.planAt(MapStyle.AUTO, paris)

        // 整屏空白 → 该级别立刻判「没内容」（空白是确定性判据，不用连击）
        tracker.blankTiles(1, zoom = 12)
        assertEquals(11, tracker.zoomPlan(plan, 12).zoom)

        // 真画出一块有内容的瓦片（高德恢复了 / 换到有数据的地区）→ 该级别恢复可用
        tracker.loadTiles(1, zoom = 12)
        assertEquals(12, tracker.zoomPlan(plan, 12).zoom)
        assertEquals(1, tracker.snapshot().blankTileCount)
    }

    // ------------------------------------------------------------ 诊断文案

    @Test
    fun diagnosticsShowFallbackReasonFailureCountAndNextProbe() {
        val tracker = newTracker(probe = { false })
        tracker.failTiles(threshold)
        val plan = tracker.planAt(MapStyle.AUTO, paris)
        val zoom = tracker.zoomPlan(plan, 12)
        val lines = MapFallbackDiagnostics.lines(plan, zoom, tracker.snapshot(), now)

        assertEquals("地图底图 = 高德（外网源失败 3 次后回退）", lines.first())
        assertTrue(lines.contains("地图底图样式 = 自动"))
        assertTrue(lines.contains("首选底图 = ESRI"))
        assertTrue(lines.contains("地图缩放 = 12"))
        assertTrue(lines.contains("瓦片状态 = 正常"))
        assertTrue(lines.contains("OSM 失败次数 = 3"))
        assertTrue(lines.any { it.startsWith("下次探测 OSM = ") && it.endsWith("约 5 分钟后）") })
    }

    @Test
    fun diagnosticsSayManualSelectionNeverFallsBack() {
        val tracker = newTracker(probe = { true })
        val plan = tracker.planAt(MapStyle.AMAP_VECTOR, paris)
        val lines = MapFallbackDiagnostics.lines(plan, tracker.zoomPlan(plan, 12), tracker.snapshot(), now)

        assertEquals("地图底图 = 高德矢量（手动选择，不回退）", lines.first())
        assertTrue(lines.contains("下次探测 OSM = 不探测（手动选择底图）"))
    }

    @Test
    fun diagnosticsShowHowManyBlankTilesAndTheLatestOne() {
        val tracker = newTracker(probe = { false })
        tracker.failTiles(threshold)
        tracker.blankTiles(threshold, colorKinds = 3)
        val plan = tracker.planAt(MapStyle.AUTO, paris)
        val lines = MapFallbackDiagnostics.lines(plan, tracker.zoomPlan(plan, 12), tracker.snapshot(), now)

        assertTrue(lines.contains("空白瓦片判定 = 已触发 3 次（最近：z12 颜色种类 3）"))
        assertTrue("降级后的级别要如实写出来", lines.contains("地图缩放 = 11（已降级：请求 12）"))
    }

    @Test
    fun diagnosticsSayNoBlankTileBeforeAnyDetection() {
        val tracker = newTracker()
        val plan = tracker.planAt(MapStyle.AUTO, paris)
        val lines = MapFallbackDiagnostics.lines(plan, tracker.zoomPlan(plan, 12), tracker.snapshot(), now)

        assertTrue(lines.contains("空白瓦片判定 = 未触发（只检测高德瓦片）"))
    }
}
