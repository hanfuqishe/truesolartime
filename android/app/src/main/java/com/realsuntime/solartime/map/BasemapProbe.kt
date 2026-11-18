package com.realsuntime.solartime.map

/**
 * 首屏「并行探测」：切城市 / 换地点时**同时**发几块单瓦片（每块几 KB），
 * 而不是串行地「OSM 失败 3 次 → 回退高德 → 判空白 3 次 → z12→z11→z10→z3 逐级下探」。
 *
 * 串行那套在境外要几十秒（HTTP 超时 + 3 次失败 + 每级 3 次空白），首屏体验极差。
 *
 * 本文件**只放纯函数**（不碰 Android / 网络），便于单测；真正发请求的是
 * `BasemapProbeRunner`。
 *
 * 选择规则（**渐进升级**，取代旧的「早退 + 一次定级」）：
 * 1. 每块瓦片一出结论就尝试应用：**第一块有内容的立刻出图**（通常是 z3，几百毫秒就能看到东西）；
 * 2. 后续只有比当前**更好**的才升级：先比源（OSM > 高德），同源再比级别（z12 > z10 > z3）；
 * 3. 冻结（不再改图）：已经 `OSM z12` / 用户手动平移缩放过 / 首次出图后超过 [UPGRADE_WINDOW_MILLIS]；
 * 4. 4 秒内一块有内容的都没有 → 「底图不可用」；**只要出过图就永远不再显示不可用**
 *    （[OVERALL_TIMEOUT_MILLIS] 只用于这个判定，不再用来截断升级）。
 */
object BasemapProbe {

    /** 什么都没有返回时的硬超时：超过就判「底图不可用」。只要出过图就不再受它限制。 */
    const val OVERALL_TIMEOUT_MILLIS = 4_000L

    /** 单块请求自己的超时。 */
    const val TILE_TIMEOUT_MILLIS = 2_500L

    /** 高德侧要探的级别：默认级别、降 2 级、以及全球底图。 */
    val AMAP_PROBE_ZOOMS = intArrayOf(MapFallback.DEFAULT_ZOOM, 10, MapFallback.MIN_ZOOM)

    /** OSM 侧要探的级别：全球底图（判可达）+ 默认级别（判高精度有没有内容）。 */
    val OSM_PROBE_ZOOMS = intArrayOf(MapFallback.MIN_ZOOM, MapFallback.DEFAULT_ZOOM)

    /** Esri 侧要探的级别：全球底图 + 默认级别（境外首选源，见 [MapStyle.effective]）。 */
    val ESRI_PROBE_ZOOMS = intArrayOf(MapFallback.MIN_ZOOM, MapFallback.DEFAULT_ZOOM)

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

    /**
     * 渐进升级用的「一块瓦片出结论」事件：Runner 每拿到一块就回调一次。
     *
     * OSM 侧只探一块 z3 判可达性，成功后按默认级别上报（`zoom = DEFAULT_ZOOM`，与 decide 一致）；
     * 高德侧是 z12 / z10 / z3。
     */
    data class ProbeTile(val source: MapStyle, val zoom: Int, val hasContent: Boolean)

    /** 探测的最终选择。 */
    data class Choice(
        val source: MapStyle,
        val zoom: Int,
        /** 连全球底图都没内容：界面显示「底图不可用」。 */
        val unavailable: Boolean,
        /** 一句话诊断，例如 `OSM 不通；高德 z12 空白 / z10 有内容`。 */
        val summary: String,
    )

    /** 探测级别，从高到低（选择时按这个顺序扫）。 */
    val PROBE_ZOOMS_DESC = listOf(MapFallback.DEFAULT_ZOOM, 10, MapFallback.MIN_ZOOM)

    /**
     * 纯决策：给定所有探测瓦片的结论与「偏好源」，按**先换源、再降级**选出源与级别。
     *
     * 顺序：z12 → z10 → z3；同一级别优先 [preferred]（区域偏好只决定同精度时选谁），
     * 偏好源在该级空白/失败、另一个源有内容 → 用另一个源（Esri → OSM → 高德）。
     *
     * @param tiles 三家各自的探测结论（Esri z3/z12、OSM z3/z12、高德 z12/z10/z3）
     * @param preferred 区域偏好源（境内高德、境外 OSM；见 [MapStyle.effective]）
     */
    fun decide(tiles: List<ProbeTile>, preferred: MapStyle): Choice {
        val picked = choose(tiles, preferred)
        val detail = PROBE_ZOOMS_DESC.joinToString(" / ") { zoom ->
            val parts = listOf(MapStyle.ESRI, MapStyle.OSM, MapStyle.AMAP_VECTOR).mapNotNull { source ->
                val tile = tiles.firstOrNull { it.source == source && it.zoom == zoom } ?: return@mapNotNull null
                val verdict = if (tile.hasContent) "有内容" else "空白"
                "${sourceShort(source)} z$zoom $verdict"
            }
            if (parts.isEmpty()) "z$zoom 未探" else parts.joinToString("、")
        }
        return if (picked != null) {
            Choice(
                source = picked.source,
                zoom = picked.zoom,
                unavailable = false,
                summary = "偏好 ${sourceShort(preferred)}；$detail",
            )
        } else {
            Choice(
                source = MapStyle.AMAP_VECTOR,
                zoom = MapFallback.MIN_ZOOM,
                unavailable = true,
                summary = "两源都无内容；$detail",
            )
        }
    }

    /**
     * 取第一个命中：级别从高到低，同一级别优先 [preferred] 源。
     *
     * 例：境内（偏好高德）+ 高德 z12 空白 + OSM z12 有内容 → 返回 OSM z12（不是降级到 z10）。
     */
    fun choose(tiles: List<ProbeTile>, preferred: MapStyle): ProbeTile? {
        val content = tiles.filter { it.hasContent }
        for (zoom in PROBE_ZOOMS_DESC) {
            val atZoom = content.filter { it.zoom == zoom }
            if (atZoom.isEmpty()) continue
            return atZoom.maxByOrNull { sourcePriority(it.source, preferred) }
        }
        return null
    }

    /**
     * 同一级别里各源的优先级：偏好源最高，其余按 **Esri > OSM > 高德**。
     *
     * 境外偏好 Esri：ESRI 3 / OSM 1 / 高德 0；境内偏好高德：高德 3 / ESRI 2 / OSM 1。
     */
    fun sourcePriority(source: MapStyle, preferred: MapStyle): Int = when {
        source == preferred -> 3
        source == MapStyle.ESRI -> 2
        source == MapStyle.OSM -> 1
        else -> 0
    }

    /** 诊断用的源简称。 */
    fun sourceShort(source: MapStyle): String = when (source) {
        MapStyle.ESRI -> "ESRI"
        MapStyle.OSM -> "OSM"
        else -> "高德"
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
     * 渐进升级（取代「早退 + 一次定级」）。
     *
     * 每有一块瓦片出结论就调一次；**先到先用**（第一块有内容的立刻出图），
     * 后续只有「更好」的才升级：**先看级别**（z12 > z10 > z3），
     * 同级再看源（区域偏好源优先）—— 这就是「先换源、再降级」。
     *
     * 冻结条件（任一满足就不再改图）：已经是「偏好源 z12」；用户手动平移/缩放过；
     * 距首次出图超过 [UPGRADE_WINDOW_MILLIS]。
     */
    data class AppliedChoice(val source: MapStyle, val zoom: Int)

    /** 渐进升级窗口：从**首次出图**起最多再升级这么久，之后冻结，避免地图长时间抖动。 */
    const val UPGRADE_WINDOW_MILLIS = 10_000L

    /**
     * 候选 (source, zoom) 是否严格优于 [current]；[current] 为 null 时任何有内容的候选都更好。
     *
     * 顺序按「先换源、再降级」：**级别优先**（z12 > z10 > z3），同级才看源 ——
     * 同一级别里 [preferred] 源更好；当前已是偏好源时同级不换。
     */
    fun isBetter(
        current: AppliedChoice?,
        source: MapStyle,
        zoom: Int,
        preferred: MapStyle,
    ): Boolean {
        if (current == null) return true
        if (zoom != current.zoom) return zoom > current.zoom
        if (source == current.source) return false
        return sourcePriority(source, preferred) > sourcePriority(current.source, preferred)
    }

    /** 已经是最优：偏好源的默认级别（z12）。 */
    fun isBest(choice: AppliedChoice, preferred: MapStyle): Boolean =
        choice.zoom == MapFallback.DEFAULT_ZOOM && choice.source == preferred

    /**
     * 是否已经冻结（不再接受升级）。
     *
     * @param elapsedSinceFirstPaintMillis 距首次出图的毫秒数；null = 还没出过图。
     */
    fun isFrozen(
        current: AppliedChoice?,
        elapsedSinceFirstPaintMillis: Long?,
        userMoved: Boolean,
        preferred: MapStyle,
    ): Boolean {
        if (current == null) return false
        if (isBest(current, preferred)) return true
        if (userMoved) return true
        val elapsed = elapsedSinceFirstPaintMillis ?: return false
        return elapsed >= UPGRADE_WINDOW_MILLIS
    }

    /**
     * 渐进升级的核心（纯函数）：一块新瓦片出结论后，现在应该用哪个「源 + 级别」。
     *
     * @param current 当前正在用的（null = 还没出图）
     * @param firstPaintAtMillis 首次出图那一刻的 elapsed（与 [elapsedMillis] 同一时钟）
     * @param preferred 区域偏好源（同级时选它）
     * @return null = 还没出过图且这块没内容；否则返回应用后的选择（可能与 [current] 相同 = 忽略）
     */
    fun nextApplied(
        current: AppliedChoice?,
        source: MapStyle,
        zoom: Int,
        hasContent: Boolean,
        elapsedMillis: Long,
        firstPaintAtMillis: Long?,
        userMoved: Boolean,
        preferred: MapStyle,
    ): AppliedChoice? {
        if (!hasContent) return current
        val sinceFirst = firstPaintAtMillis?.let { elapsedMillis - it }
        if (isFrozen(current, sinceFirst, userMoved, preferred)) return current
        return if (isBetter(current, source, zoom, preferred)) AppliedChoice(source, zoom) else current
    }

    /**
     * 该地点按「自动」应该首选哪个源（与 [MapStyle.effective] 一致）。
     *
     * 只有首选是「外网源」（境外：Esri / OSM）才值得并行探测；境内用高德本来就能 1 秒内出图，
     * 探测只会白等一个超时。
     */
    fun needsProbe(style: MapStyle, latitude: Double, longitude: Double): Boolean =
        style == MapStyle.AUTO && style.effective(latitude, longitude) != MapStyle.AMAP_VECTOR

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
    /** 区域偏好源（境内高德 / 境外 OSM），只用于同级取舍。 */
    val preferred: MapStyle,
    /** 两块 OSM（z3 / z12）与三块高德（z12 / z10 / z3）的结论；没回来的不在列表里。 */
    val tiles: List<BasemapProbe.ProbeTile>,
    /** 探测整体耗时（毫秒，报告用）。 */
    val elapsedMillis: Long,
    /** 是否因为整体超时被截断（没来得及出结论的当失败）。 */
    val timedOut: Boolean = false,
) {
    /** 选择结果（纯函数转发，便于单测与日志共用同一份判定）。 */
    val choice: BasemapProbe.Choice get() = BasemapProbe.decide(tiles, preferred)
}
