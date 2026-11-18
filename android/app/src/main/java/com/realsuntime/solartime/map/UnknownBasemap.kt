package com.realsuntime.solartime.map

/**
 * 未知态（定位不可用）的**全球底图快路径**。
 *
 * 未知态的诉求很单纯：**就要一张全球图（z3）**，不需要知道自己在哪，也就没有「探具体地点」
 * 的必要。所以它完全不碰正常态那套「并行探 4 块 → OSM 连续失败 3 次回退 → 逐级降级 →
 * 5 分钟冷却回弹」的状态机（真机上那套在境外要 1~3 分钟才出图），而是：
 *
 * 1. **有缓存**（上次成功出图的源 + 时间，10 分钟内有效）→ 直接用该源 + z3，**一次请求都不发**；
 * 2. **没缓存** → 只并行取 **两块 z3 瓦片**（OSM 一块、高德一块，都只有几 KB），
 *    谁先回来且有内容就用谁；**2 秒**封顶，到点就用手上已有的结论；
 * 3. **两块都失败** → 直接显示「底图不可用」（未知态只在 z3，没有级别可降）。
 *
 * 探测结果写回缓存，下次进未知态直接命中。这个缓存**只被未知态读取**，
 * 正常态的探测/回退结论完全不受它影响（见 `MainViewModel` 里两套状态各自独立）。
 *
 * 这里全是纯函数（不碰 Android / 网络），单测可以直接钉住「要不要探测 / 探哪两块 / 选谁」。
 */
object UnknownBasemap {

    /** 未知态永远只画最低级别的全球底图。 */
    const val ZOOM = MapFallback.MIN_ZOOM

    /** 两块瓦片并行探测的**硬**封顶：到点无论如何收工（目标：切到未知态后 ≤5 秒出图）。 */
    const val PROBE_DEADLINE_MILLIS = 2_000L

    /** 单块瓦片自己的 connect/read 超时：比封顶略短，保证「有结论的那块」能在收工前回来。 */
    const val TILE_TIMEOUT_MILLIS = 1_800L

    /**
     * 「上次成功出图的源」缓存的有效期。
     *
     * 太短等于每次都探（白等 2 秒），太长会在换了网络（例如从 Wi-Fi 切到流量、
     * 或从境外回到境内）之后一直用已经不可达的源。10 分钟是折中。
     */
    const val CACHE_MILLIS = 10 * 60_000L

    /** 一块探测瓦片：哪个源、哪一级、哪一块。 */
    data class ProbeTile(val style: MapStyle, val zoom: Int, val x: Int, val y: Int) {
        /** OSM 的瓦片地址（z/x/y.png）。 */
        val osmUrl: String get() = "https://tile.openstreetmap.org/$zoom/$x/$y.png"

        /** 高德矢量瓦片地址（与 [MapTileSources] 的模板同源，取第一个 host）。 */
        val amapUrl: String
            get() = "https://webrd01.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=8" +
                "&x=$x&y=$y&z=$zoom"
    }

    /**
     * 探测集合：**只有两块**，都是 z3。
     *
     * 取东亚那一块（x=6,y=2）而不是 (0,0) 附近的大洋瓦片：z3 的海面瓦片几乎是纯色，
     * 高德侧会被空白检测判成「没内容」，白白得出「高德不可用」的结论。
     */
    val PROBE_TILES: List<ProbeTile> = listOf(
        ProbeTile(MapStyle.OSM, zoom = ZOOM, x = 6, y = 2),
        ProbeTile(MapStyle.AMAP_VECTOR, zoom = ZOOM, x = 6, y = 2),
    )

    /** 探测的源集合（两块各一个），单测直接断言「只有这两个、且都是 z3」。 */
    val PROBE_CANDIDATES: List<MapStyle> = PROBE_TILES.map { it.style }

    /**
     * 缓存里那个源现在还能不能用。
     *
     * @param source 上次成功出图的源（null = 从没成功过）
     * @param atMillis 那次成功的时刻（null / 0 = 没记过）
     * @return 可用的源；null = 缓存缺失或已过期
     */
    fun cachedSource(source: MapStyle?, atMillis: Long?, nowMillis: Long): MapStyle? {
        if (source == null || source == MapStyle.AUTO) return null
        val at = atMillis ?: return null
        if (at <= 0L) return null
        val age = nowMillis - at
        // 时钟回拨（age < 0）也当过期：宁可重探 2 秒，也别拿一个来路不明的时间戳当新鲜。
        if (age < 0 || age > CACHE_MILLIS) return null
        return source
    }

    /**
     * 要不要跑一次探测：**有缓存就不探**（这是 ≤5 秒出图的关键 —— 常规路径是稳定命中缓存的）。
     */
    fun shouldProbe(source: MapStyle?, atMillis: Long?, nowMillis: Long): Boolean =
        cachedSource(source, atMillis, nowMillis) == null

    /**
     * 同一次探测里「先回来的有内容者」胜出；[fetched] 是各源是否已拿到有内容的瓦片。
     *
     * @return 用哪个源；null = 两块都还没内容（调用方显示「底图不可用」，未知态不降级）
     */
    fun choose(fetched: Map<MapStyle, Boolean>): MapStyle? =
        PROBE_CANDIDATES.firstOrNull { fetched[it] == true }
}
