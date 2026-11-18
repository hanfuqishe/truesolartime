package com.realsuntime.solartime.map

/**
 * 首屏「并行探测」：切城市 / 换地点时**同时**发几块单瓦片（每块几 KB），
 * 用「有内容的最高精度」直接决定用哪个源、哪个级别，而不是串行地
 * 「OSM 失败 3 次 → 回退高德 → 判空白 3 次 → z12→z11→z10→z3 逐级下探」。
 *
 * 串行那套在境外要几十秒（HTTP 超时 + 3 次失败 + 每级 3 次空白），首屏体验极差；
 * 并行探测把这段时间压到一个整体超时（[OVERALL_TIMEOUT_MILLIS]）内。
 *
 * 本文件**只放纯函数**（不碰 Android / 网络），便于单测；真正发请求的是
 * `BasemapProbeRunner`。
 *
 * 选择规则（与产品定义一致）：
 * 1. OSM 的 z3 拿到真图片 → 用 OSM，缩放用默认级别（z12）；
 * 2. 否则看高德：z12 > z10 > z3 里**有内容（非空白）的最高级别**；
 * 3. 都失败或都空白 → 「底图不可用」（保留现有的 5 分钟重探测）。
 */
object BasemapProbe {

    /** 整体封顶：并行探测最多等这么久，超时的一律按失败算。 */
    const val OVERALL_TIMEOUT_MILLIS = 4_000L

    /** 单块请求自己的超时（比整体略短，保证整体超时前大部分都有结论）。 */
    const val TILE_TIMEOUT_MILLIS = 2_500L

    /**
     * 提前收工：只要已经探到「高德有内容」，等到这个时刻就不再等 OSM 了。
     *
     * OSM 被墙时它的 DNS/连接会一直挂到超时（几秒），而高德通常 1 秒内就有结论；
     * 死等 OSM 会让首屏白等好几秒。慢到 2 秒还没回的 OSM，本来也不适合当首屏底图
     * （5 分钟后的重探还会把它切回来）。
     */
    const val EARLY_EXIT_MILLIS = 2_000L

    /** 高德侧要探的级别：默认级别、降 2 级、以及全球底图。 */
    val AMAP_PROBE_ZOOMS = intArrayOf(MapFallback.DEFAULT_ZOOM, 10, MapFallback.MIN_ZOOM)

    /** 同一个地点 + 同一个会话内，探测结果的保鲜期（与 OSM 重探间隔一致）。 */
    const val CACHE_MILLIS = 5 * 60_000L

    /** 一块瓦片的探测结论（高德侧）。 */
    data class AmapProbe(
        val zoom: Int,
        /** 是否拿到了图片**且**判为非空白。 */
        val hasContent: Boolean,
        /** 量化颜色种类（诊断/报告用）。 */
        val colorKinds: Int = 0,
        /** 这块瓦片有没有拿到（false = 网络失败/超时）。 */
        val fetched: Boolean = false,
    )

    /** 探测的最终选择。 */
    data class Choice(
        val source: MapStyle,
        val zoom: Int,
        /** 连全球底图都没内容：界面显示「底图不可用」。 */
        val unavailable: Boolean,
        /** 一句话诊断，例如 `OSM 不通；高德 z12 空白 / z10 有内容`。 */
        val summary: String,
    )

    /**
     * 纯决策：给定 OSM 是否可用、高德三块瓦片的结论，选出源与级别。
     *
     * @param osmReachable OSM z3 探测是否成功（2xx + 真图片）。
     * @param amap 高德 z12/z10/z3 的探测结论（缺的当失败）。
     */
    fun decide(osmReachable: Boolean, amap: List<AmapProbe>): Choice {
        if (osmReachable) {
            return Choice(
                source = MapStyle.OSM,
                zoom = MapFallback.DEFAULT_ZOOM,
                unavailable = false,
                summary = "OSM 可用（z${MapFallback.DEFAULT_ZOOM}）",
            )
        }
        val best = amap
            .filter { it.hasContent }
            .maxByOrNull { it.zoom }
        val detail = AMAP_PROBE_ZOOMS.joinToString(" / ") { zoom ->
            val probe = amap.firstOrNull { it.zoom == zoom }
            val verdict = when {
                probe == null || !probe.fetched -> "失败"
                probe.hasContent -> "有内容"
                else -> "空白"
            }
            "z$zoom $verdict"
        }
        return if (best != null) {
            Choice(
                source = MapStyle.AMAP_VECTOR,
                zoom = best.zoom,
                unavailable = false,
                summary = "OSM 不通；高德 $detail",
            )
        } else {
            Choice(
                source = MapStyle.AMAP_VECTOR,
                zoom = MapFallback.MIN_ZOOM,
                unavailable = true,
                summary = "OSM 不通；高德 $detail",
            )
        }
    }

    /**
     * 探测缓存键：同一地点（~100 m 粒度）+ 同一模式算「同一个」。换城市就变，因此缓存自动失效。
     */
    fun cacheKey(latitude: Double, longitude: Double): String =
        "%.3f,%.3f".format(latitude, longitude)

    /**
     * 现在还要不要探测（纯函数，单测直接盯）。
     *
     * @param lastKey 上次探测用的地点指纹；null = 从没探过。
     * @param lastAtMillis 上次探测完成时刻；null = 从没探过。
     */
    fun shouldProbe(
        key: String,
        lastKey: String?,
        lastAtMillis: Long?,
        nowMillis: Long,
        force: Boolean = false,
    ): Boolean {
        if (force) return true
        if (lastKey == null || lastAtMillis == null) return true
        if (lastKey != key) return true
        return nowMillis - lastAtMillis >= CACHE_MILLIS
    }

    /**
     * 该地点按「自动」应该首选哪个源（与 [MapStyle.effective] 一致）。
     *
     * 只有首选 OSM（境外）才值得并行探测；境内用高德本来就能 1 秒内出图，
     * 探测只会白等一个超时。
     */
    fun needsProbe(style: MapStyle, latitude: Double, longitude: Double): Boolean =
        style == MapStyle.AUTO && style.effective(latitude, longitude) == MapStyle.OSM

    /**
     * 该级别之上的「肯定没内容」的级别（用于把降级链直接推到探测选中的级别）。
     *
     * 例：选 z10 → {12, 11}；选 z3 → {12, 11, 10}；全空 → {12, 11, 10, MIN_ZOOM}。
     */
    fun zoomsAbove(choice: Choice): Set<Int> = buildSet {
        if (choice.unavailable) {
            add(MapFallback.MIN_ZOOM)
        }
        for (zoom in intArrayOf(MapFallback.DEFAULT_ZOOM, MapFallback.DEFAULT_ZOOM - 1, 10)) {
            if (zoom > choice.zoom) add(zoom)
        }
    }

    /** 经纬度 → 该级别的瓦片坐标（Web Mercator，纯函数，便于单测）。 */
    fun tileOf(latitude: Double, longitude: Double, zoom: Int): Pair<Int, Int> {
        val n = 1 shl zoom
        val x = ((longitude + 180.0) / 360.0 * n).toInt().coerceIn(0, n - 1)
        val latRad = Math.toRadians(latitude.coerceIn(-85.05112878, 85.05112878))
        val y = ((1.0 - Math.log(Math.tan(latRad) + 1.0 / Math.cos(latRad)) / Math.PI) / 2.0 * n)
            .toInt()
            .coerceIn(0, n - 1)
        return x to y
    }
}

/** 一次并行探测的原始结果（纯数据，不含网络）。 */
data class BasemapProbeResult(
    /** OSM z3 是否可用。 */
    val osmReachable: Boolean,
    /** 高德 z12 / z10 / z3 的结论。 */
    val amap: List<BasemapProbe.AmapProbe>,
    /** 探测整体耗时（毫秒，报告用）。 */
    val elapsedMillis: Long,
    /** 是否因为整体超时被截断（没来得及出结论的当失败）。 */
    val timedOut: Boolean = false,
) {
    /** 选择结果（纯函数转发，便于单测与日志共用同一份判定）。 */
    val choice: BasemapProbe.Choice get() = BasemapProbe.decide(osmReachable, amap)
}
