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

    /**
     * 选源看「国家码 / 中国包围盒」，不看 GCJ-02 边界：
     * 新加坡（1.35°N）曾被 GCJ 边界（纬度 ≥0.83°）误判成境内，一路降级到 z3 全球图。
     */
    @Test
    fun planUsesTheStateCountryCodeNotTheGcjBoundary() {
        val singapore = 1.3521 to 103.8198
        // 有 sg → ESRI
        val sg = trackerWithCountryCode("sg")
        assertEquals(MapStyle.ESRI, sg.planAt(MapStyle.AUTO, singapore).effective)
        assertEquals(12, sg.zoomPlan(sg.planAt(MapStyle.AUTO, singapore), 12).zoom)
        assertFalse(sg.zoomPlan(sg.planAt(MapStyle.AUTO, singapore), 12).unavailable)

        // 无国家码 → 按 73–135°E / 18–54°N 包围盒：新加坡在框外 → ESRI
        val unknown = newTracker()
        assertEquals(MapStyle.ESRI, unknown.planAt(MapStyle.AUTO, singapore).effective)

        // 香港带 hk → 高德
        assertEquals(
            MapStyle.AMAP_VECTOR,
            trackerWithCountryCode("hk").planAt(MapStyle.AUTO, 22.32 to 114.17).effective,
        )
    }

    private fun trackerWithCountryCode(code: String) = newTracker().also { it.setCountryCode(code) }

    // ------------------------------------------------------------ 回退与记忆

    @Test
    fun overseasFailuresDegradeTheZoomButNeverSwitchSource() {
        // **新契约**：境外失败不再「整源回退到高德」——那会让地图更糊（高德境外只有 z3）。
        // 失败只让 zoomPlan 逐级下降，源始终是 ESRI。
        val tracker = newTracker()
        tracker.failTiles(threshold - 1)
        val beforeThreshold = tracker.planAt(MapStyle.AUTO, paris)
        assertEquals(MapStyle.ESRI, beforeThreshold.effective)
        assertFalse(beforeThreshold.fellBack)

        // 第 3 次失败：达到阈值 → 判 z12 没瓦片 → 降一级，**源不变**
        tracker.failTiles(1)
        val afterThreshold = tracker.planAt(MapStyle.AUTO, paris)
        assertEquals(MapStyle.ESRI, afterThreshold.effective)
        assertFalse(afterThreshold.fellBack)
        assertEquals("底图 © Esri, HERE, Garmin, © OpenStreetMap contributors", afterThreshold.effective.attribution)
        assertEquals(11, tracker.zoomPlan(afterThreshold, 12).zoom)

        // 继续失败：只沿降级链往下走，永远不回高德
        tracker.failTiles(6)
        val later = tracker.planAt(MapStyle.AUTO, paris)
        assertEquals(MapStyle.ESRI, later.effective)
        assertFalse(later.fellBack)
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
        val plan = tracker.planAt(MapStyle.AUTO, paris)
        tracker.failTiles(threshold) // 3 连失败 → 判 z12 没瓦片（源仍是 ESRI）
        assertEquals(11, tracker.zoomPlan(plan, 12).zoom)

        // 换到 z11 后，连续失败要**重新数**：z12 的旧计数不能顺延到 z11
        tracker.failTiles(threshold - 1, zoom = 11)
        assertEquals(2, tracker.snapshot().zoomFailures)
        assertEquals(11, tracker.zoomPlan(plan, 12).zoom)

        // 再失败 1 次才够阈值 → 判 z11 没瓦片 → 降到 z10
        tracker.failTiles(1, zoom = 11)
        assertEquals(10, tracker.zoomPlan(plan, 12).zoom)
    }

    // ------------------------------------------------------------ 5 分钟探测 / 网络恢复

    @Test
    fun probeRestoresOsmAfterCooldownAndClearsTheCounter() {
        var reachable = false
        val tracker = newTracker(probe = { reachable })
        tracker.failTiles(threshold)

        // 失败后源不变（仍是 ESRI），只是降到 z11
        val degraded = tracker.planAt(MapStyle.AUTO, paris)
        assertEquals(MapStyle.ESRI, degraded.effective)
        assertFalse(degraded.fellBack)

        // 网络恢复后：安静够久 + 冷却到期，最低级别出图即把降级链收回默认级别
        reachable = true
        now += MapFallback.RECOVERY_QUIET_MILLIS + MapFallback.RECOVERY_COOLDOWN_MILLIS
        tracker.loadTiles(zoom = MapFallback.MIN_ZOOM)
        assertEquals(12, tracker.zoomPlan(degraded, 12).zoom)
    }

    @Test
    fun probeFailureKeepsAmapAndSchedulesTheNextProbe() {
        val tracker = newTracker(probe = { false })
        tracker.failTiles(threshold)

        // 新契约：失败不再触发「换源 + 探测回退」。源始终是 ESRI，只沿降级链下降，
        // 恢复由「最低级别出图 + 安静/冷却」负责，不靠探测切源。
        assertEquals(MapStyle.ESRI, tracker.planAt(MapStyle.AUTO, paris).effective)
        assertFalse(tracker.snapshot().fellBack)
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

    /** 手动选 ESRI：不探测、不回退、不降级；真拿不到瓦片就显示「底图不可用」，出图自动恢复。 */
    @Test
    fun manualEsriNeverFallsBackButShowsUnavailableOnFailure() {
        val tracker = newTracker()
        val style = MapStyle.ESRI
        var plan = tracker.planAt(style, paris)
        assertEquals(MapStyle.ESRI, plan.effective)
        assertFalse(plan.fellBack)
        assertEquals(12, tracker.zoomPlan(plan, 12).zoom)
        assertFalse(tracker.zoomPlan(plan, 12).unavailable)

        // 连续失败：源不变、级别不降，只落「底图不可用」
        tracker.failTiles(threshold, style = style, zoom = 12)
        plan = tracker.planAt(style, paris)
        assertEquals(MapStyle.ESRI, plan.effective)
        assertFalse(plan.fellBack)
        val offline = tracker.zoomPlan(plan, 12)
        assertEquals(12, offline.zoom)
        assertFalse("手动模式不降级", offline.degraded)
        assertTrue("真拿不到瓦片要显示「底图不可用」", offline.unavailable)

        // 又出图了：标记被清掉，地图回来
        tracker.loadTiles(style = style, zoom = 12)
        assertFalse(tracker.zoomPlan(tracker.planAt(style, paris), 12).unavailable)

        // 全程不探测
        now += MapFallback.PROBE_INTERVAL_MILLIS * 2
        assertFalse(tracker.probeIfDue())
    }

    /** 设置页手动选项：自动 → ESRI → OSM → 高德矢量 → 高德卫星（ESRI 紧跟自动）。 */
    @Test
    fun manualOptionsPutEsriRightAfterAuto() {
        assertEquals(
            listOf(
                MapStyle.AUTO,
                MapStyle.ESRI,
                MapStyle.OSM,
                MapStyle.AMAP_VECTOR,
                MapStyle.AMAP_SATELLITE,
            ),
            MapStyle.manualOptions,
        )
        // 手动 ESRI 不探测（境内境外都不探）
        assertFalse(BasemapProbe.needsProbe(MapStyle.ESRI, paris.first, paris.second))
        assertFalse(BasemapProbe.needsProbe(MapStyle.ESRI, beijing.first, beijing.second))
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
        assertFalse(tracker.planAt(MapStyle.AUTO, paris).fellBack)
        assertEquals(11, tracker.zoomPlan(tracker.planAt(MapStyle.AUTO, paris), 12).zoom)

        // MainViewModel 在「切到自动」或「用户重新选择地点」时调 reset()
        // —— 必须把「哪一级没瓦片」的记忆一起清掉，否则新城市会继承旧城市的降级
        tracker.reset()
        val plan = tracker.planAt(MapStyle.AUTO, paris)
        assertEquals(MapStyle.ESRI, plan.effective)
        assertFalse(plan.fellBack)
        assertEquals(12, tracker.zoomPlan(plan, 12).zoom)
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
        tracker.failTiles(threshold) // 第一次 3 连失败：判 z12 没瓦片
        val plan = tracker.planAt(MapStyle.AUTO, paris)
        assertEquals(MapStyle.ESRI, plan.effective)
        assertFalse(plan.fellBack)
        assertEquals(11, tracker.zoomPlan(plan, 12).zoom) // 已经降到 z11

        // z11 也没瓦片 → 再降 1 级
        tracker.failTiles(threshold, zoom = 11)
        val at10 = tracker.zoomPlan(plan, 12)
        assertEquals(10, at10.zoom)
        assertTrue(at10.degraded)
        assertFalse(at10.unavailable)

        // z10 也没有 → 继续往下降到最低级别（源头仍是 ESRI）
        tracker.failTiles(threshold, zoom = 10)
        val floor = tracker.zoomPlan(plan, 12)
        assertEquals(MapFallback.MIN_ZOOM, floor.zoom)
        assertTrue(floor.degraded)
        assertFalse(floor.unavailable)
        assertEquals(MapStyle.ESRI, tracker.planAt(MapStyle.AUTO, paris).effective)
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
        val plan = tracker.planAt(MapStyle.AUTO, paris) // 失败前
        // 新契约：失败只降级、**永不换源**，所以这里不再出现「回退」标记
        assertFalse(plan.fellBack)
        assertEquals(MapStyle.ESRI, plan.effective)
        assertEquals(12, tracker.zoomPlan(plan, 12).zoom)

        tracker.failTiles(threshold) // 3 连失败 → 判 z12 没瓦片
        assertEquals(11, tracker.zoomPlan(plan, 12).zoom)

        // 刚程序化改过视口：这一批「失败」是被取消的旧请求，不能算（否则自激降级）
        tracker.onZoomApplied(12)
        repeat(threshold * 3) {
            now += 10L
            tracker.onTileFailed(MapStyle.AUTO, paris.first, paris.second, 11)
        }
        assertEquals(0, tracker.snapshot().zoomFailures)
        assertEquals(11, tracker.zoomPlan(plan, 12).zoom)
        assertFalse(tracker.snapshot().zoomUnavailable(MapStyle.ESRI, 11))

        // 窗口过去后，真没网仍然能被诊断出来（只降级，不换源）
        now += MapFallback.VIEWPORT_SETTLE_MILLIS
        tracker.failTiles(threshold, zoom = 11)
        assertEquals(10, tracker.zoomPlan(plan, 12).zoom)
        assertEquals(MapStyle.ESRI, tracker.planAt(MapStyle.AUTO, paris).effective)
    }

    /** 视口残响只该保护高德：OSM 的失败是「网络不通」的证据，不能被它吞掉（否则回退会变慢）。 */
    @Test
    fun viewportSettleSwallowsCancelFailuresForEverySource() {
        // 程序化改视口会取消在飞请求，osmdroid 把「取消」也报成失败。
        // 现在境外源同样靠「降级」应对失败，而降级又会改视口 —— 若不吞掉这些取消，
        // 就会「降级 → 取消 → 失败 → 再降级」自激到最低级别，所以这道闸必须对所有源生效。
        val tracker = newTracker()
        tracker.onZoomApplied(12)
        repeat(threshold * 2) { tracker.onTileFailed(MapStyle.AUTO, paris.first, paris.second, 12) }
        assertEquals(0, tracker.snapshot().zoomFailures)
        val plan = tracker.planAt(MapStyle.AUTO, paris)
        assertEquals(12, tracker.zoomPlan(plan, 12).zoom)
        assertEquals(MapStyle.ESRI, plan.effective)

        // 窗口过后，真实失败照常生效（同源降级）
        now += MapFallback.VIEWPORT_SETTLE_MILLIS
        tracker.failTiles(threshold, zoom = 12)
        assertEquals(11, tracker.zoomPlan(plan, 12).zoom)
    }

    // ------------------------------------------------------------ 空白瓦片：一次即降级

    @Test
    fun aSingleBlankViewportDegradesOneLevel() {
        // 空白是确定性判据（有内容就是有内容），不像网络失败会抖 → 一次就降一级。
        val tracker = newTracker()
        val plan = tracker.planAt(MapStyle.AUTO, paris)
        assertEquals(12, tracker.zoomPlan(plan, 12).zoom)

        tracker.blankTiles(1, zoom = 12)
        assertEquals(11, tracker.zoomPlan(plan, 12).zoom)
        assertEquals(1, tracker.snapshot().blankTileCount)
        // 空白只降级，不换源
        assertEquals(MapStyle.ESRI, tracker.planAt(MapStyle.AUTO, paris).effective)
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
        // 新契约：探测到「高德有内容」也**不换源**（高德境外只有 z3），
        // 只把「z10 之上没内容」种进当前源的降级链 → 落到 z10，源仍是 ESRI
        assertEquals(MapStyle.ESRI, plan.effective)
        assertFalse(plan.fellBack)
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

        // 旧字段 fellBack 不再影响底图：即使被置上，UI 状态也不该变（否则每块瓦片都会重组）
        val legacyFellBack = MapFallbackState(fellBack = true, fallbackFailures = MapFallback.FAILURE_THRESHOLD)
        assertEquals(base, MapUiState.of(MapStyle.AUTO, paris.first, paris.second, legacyFellBack))

        // 降级（z12 判没瓦片；**源仍是 ESRI**）→ 必须变
        val degraded = MapUiState.of(
            MapStyle.AUTO,
            paris.first,
            paris.second,
            MapFallbackState(unavailableZooms = mapOf(MapStyle.ESRI to setOf(12))),
        )
        assertNotEquals(base, degraded)
        assertEquals(MapStyle.ESRI, degraded.source)
        assertEquals(11, degraded.zoom)
        assertTrue(degraded.degraded)
        assertFalse(degraded.fellBack)

        // 连 z3 也没瓦片 → 「底图不可用」必须变
        val offline = MapUiState.of(
            MapStyle.AUTO,
            paris.first,
            paris.second,
            MapFallbackState(unavailableZooms = mapOf(MapStyle.ESRI to setOf(12, 11, 10, MapFallback.MIN_ZOOM))),
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
        // 手动模式不降级，但这一级真拿不到瓦片时要显示「底图不可用」（不再永远留白）。
        assertTrue(zoom.unavailable)
    }

    @Test
    fun zoomPlanResolvesAgainstInjectedTileAvailability() {
        // 「哪些级别有瓦片」是注入进纯函数的：这里直接给状态塞一份不可用级别表
        val base = MapFallbackState()
        val plan = MapFallback.plan(MapStyle.AUTO, paris.first, paris.second, base)
        // 境外首选 ESRI，且**不因任何失败换源**
        assertEquals(MapStyle.ESRI, plan.effective)

        // z12、z11 没瓦片 → 降 2 级到 z10
        val noHighZooms = base.copy(
            unavailableZooms = mapOf(MapStyle.ESRI to setOf(12, 11)),
        )
        val degraded = MapFallback.zoomPlan(plan, 12, noHighZooms)
        assertEquals(10, degraded.zoom)
        assertTrue(degraded.degraded)
        assertFalse(degraded.unavailable)

        // 连最低级别都没有瓦片 → 「底图不可用」
        val nothing = base.copy(
            unavailableZooms = mapOf(MapStyle.ESRI to setOf(12, 11, 10, MapFallback.MIN_ZOOM)),
        )
        val offline = MapFallback.zoomPlan(plan, 12, nothing)
        assertEquals(MapFallback.MIN_ZOOM, offline.zoom)
        assertTrue(offline.unavailable)
    }

    // ------------------------------------------------------------ 空白瓦片：按失败处理

    @Test
    fun blankAmapTilesDegradeExactlyLikeRealFailures() {
        val tracker = newTracker()
        val plan = tracker.planAt(MapStyle.AUTO, paris)
        assertEquals(12, tracker.zoomPlan(plan, 12).zoom)

        // 境外 Esri 在 z12 来一块空白：空白是**确定性**判据，1 次就判「这一级没内容」→ 降到 z11，
        // 而且**不换源**（这是与旧契约最大的区别：空白不再被当成「整个源连不上」）
        tracker.blankTiles(1)
        val degraded = tracker.zoomPlan(plan, 12)
        assertEquals(11, degraded.zoom)
        assertTrue(degraded.degraded)
        assertFalse(degraded.unavailable)
        assertEquals(MapStyle.ESRI, tracker.planAt(MapStyle.AUTO, paris).effective)

        // 同一个失败路径也用掉了「同一级别连续失败」计数：够阈值就清零重新数
        assertEquals(0, tracker.snapshot().zoomFailures)
        // 另记一份诊断计数：触发几次、最近一次的级别与颜色种类
        assertEquals(1, tracker.snapshot().blankTileCount)
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
        // 整屏空白是确定性判据：手动模式也判「底图不可用」（只是不换源、不降级）。
        assertTrue(zoom.unavailable)
        // 手动模式不参与回退统计，但诊断上仍要看得出「见过空白瓦片」
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

        // 外网源失败不再导致换源：诊断应显示仍是 ESRI（境外），并把失败次数如实列出
        assertEquals("地图底图 = ESRI（自动：境外）", lines.first())
        assertTrue(lines.contains("地图底图样式 = 自动"))
        assertTrue(lines.contains("首选底图 = ESRI"))
        // 3 次失败 → 判 z12 没瓦片 → 降到 z11（诊断要能看出「降过级」）
        assertTrue(lines.contains("地图缩放 = 11（已降级：请求 12）"))
        assertTrue(lines.contains("瓦片状态 = 正常"))
        assertTrue(lines.any { it.startsWith("下次探测 OSM = ") })
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
