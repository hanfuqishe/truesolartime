package com.realsuntime.solartime.map

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
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

    /** 境外：首选 OpenStreetMap。 */
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

    private fun MapFallbackTracker.planAt(style: MapStyle, point: Pair<Double, Double>): MapTilePlan =
        plan(style, point.first, point.second)

    // ------------------------------------------------------------ 首选规则与署名

    @Test
    fun autoModeKeepsTheOldPreferredSource() {
        val tracker = newTracker()
        assertEquals(MapStyle.OSM, tracker.planAt(MapStyle.AUTO, paris).effective)
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
        assertEquals(MapStyle.OSM, plan.effective)
        assertFalse(plan.fellBack)
        // 署名跟随实际使用的瓦片源（MapText.attribution 就是按 MapStyle 取这两条资源）
        assertEquals("地图数据 © OpenStreetMap 贡献者", plan.effective.attribution)
    }

    // ------------------------------------------------------------ 回退与记忆

    @Test
    fun osmFailsThreeTimesThenFallsBackToAmapFromTheFourthOnwards() {
        val tracker = newTracker()
        // 前两次失败还在试 OSM
        tracker.failTiles(threshold - 1)
        assertEquals(MapStyle.OSM, tracker.planAt(MapStyle.AUTO, paris).effective)
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
        assertEquals(MapStyle.OSM, plan.effective)
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
        assertEquals(MapStyle.OSM, restored.effective)
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
        assertEquals(MapStyle.OSM, plan.effective)
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

        // 网络回来：最低级别出图 → 「某级别没瓦片」的记忆被清掉，缩放回到默认级别
        tracker.loadTiles(zoom = MapFallback.MIN_ZOOM)
        val recovered = tracker.zoomPlan(tracker.planAt(MapStyle.AUTO, paris), 12)
        assertEquals(12, recovered.zoom)
        assertFalse(recovered.unavailable)
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

    // ------------------------------------------------------------ 诊断文案

    @Test
    fun diagnosticsShowFallbackReasonFailureCountAndNextProbe() {
        val tracker = newTracker(probe = { false })
        tracker.failTiles(threshold)
        val plan = tracker.planAt(MapStyle.AUTO, paris)
        val zoom = tracker.zoomPlan(plan, 12)
        val lines = MapFallbackDiagnostics.lines(plan, zoom, tracker.snapshot(), now)

        assertEquals("地图底图 = 高德（OSM 失败 3 次后回退）", lines.first())
        assertTrue(lines.contains("地图底图样式 = 自动"))
        assertTrue(lines.contains("首选底图 = OpenStreetMap"))
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
}
