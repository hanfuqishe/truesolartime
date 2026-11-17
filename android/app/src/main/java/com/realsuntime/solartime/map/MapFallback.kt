package com.realsuntime.solartime.map

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 底图兜底策略：OpenStreetMap 连不上时退回高德。
 *
 * 规则（首选与老版本完全一致，只加兜底）：
 * * 首选仍是「境内高德、境外 OSM」（见 [MapStyle.effective]）；
 * * 只有 **自动** 模式才回退：OSM 连续失败 [FAILURE_THRESHOLD] 次后，同一会话内直接用高德，
 *   不再每张瓦片都先失败一次（省流量、省时间）；
 * * 回退之后每 [PROBE_INTERVAL_MILLIS] 探测一次 OSM（只取一块最低级别的小瓦片），
 *   成功即刻切回 OSM 并清零计数 —— 这就是「网络恢复后回到 OSM」的路径；
 * * **手动** 选底图时不回退、不探测：用户明确要求什么就显示什么，失败保持原样；
 * * 高德某级别没有瓦片时，按 [MAX_DEGRADE_STEPS] 逐级下探，最后落到最低级别的全球底图；
 *   连最低级别都拿不到（真没网）才在界面上写「底图不可用」，绝不留一块纯空白。
 *
 * 这里全是纯函数（旧状态进、新状态出），Android / 网络 / 线程都在 [MapFallbackTracker] 里，
 * 单测可以完全脱离设备跑。
 */
object MapFallback {

    /** 连续失败多少次判定「OSM 不可用」。 */
    const val FAILURE_THRESHOLD = 3

    /** 回退到高德后，每隔多久探测一次 OSM。 */
    const val PROBE_INTERVAL_MILLIS = 5 * 60_000L

    /** 缩放范围与 `MapView` 上的设置保持一致。 */
    const val MIN_ZOOM = 3
    const val MAX_ZOOM = 18

    /** 打开地图时使用的级别；降级链从这个级别往下走。 */
    const val DEFAULT_ZOOM = 12

    /** 某级别没瓦片时最多自动降几级，再往下就直接落到最低级别的全球底图。 */
    const val MAX_DEGRADE_STEPS = 2

    /**
     * 切源（回退 / 恢复）后的「残响」窗口。
     *
     * 瓦片回调不带源的身份：切换那一刻还在飞的旧请求，失败也会在这之后才回来。
     * 这几秒内的失败一律不计入统计，否则刚回退到高德就会被若干条旧 OSM 请求的失败
     * 误判成「高德这一级没瓦片」，白白降一级；真没网时失败会持续，5 秒后照样能诊断出来。
     */
    const val SWITCH_SETTLE_MILLIS = 5_000L

    /** 一次底图选择的结果：Composable 与诊断页都只读它。 */
    fun plan(style: MapStyle, latitude: Double, longitude: Double, state: MapFallbackState): MapTilePlan {
        val preferred = style.effective(latitude, longitude)
        if (style != MapStyle.AUTO) {
            // 手动选择：不参与回退与探测，失败就显示原样。
            return MapTilePlan(
                requested = style,
                preferred = preferred,
                effective = preferred,
                fellBack = false,
                fallbackFailures = 0,
                probeAtMillis = null,
            )
        }
        val fellBack = preferred == MapStyle.OSM && state.fellBack
        return MapTilePlan(
            requested = style,
            preferred = preferred,
            effective = if (fellBack) MapStyle.AMAP_VECTOR else preferred,
            fellBack = fellBack,
            fallbackFailures = if (fellBack) state.fallbackFailures else 0,
            probeAtMillis = if (fellBack) state.probeAtMillis else null,
        )
    }

    /**
     * 缩放级别解析（纯函数）：从 [requestedZoom] 往下找第一个「还没被判定没有瓦片」的级别，
     * 最多降 [MAX_DEGRADE_STEPS] 级；都不行就直接落到 [MIN_ZOOM] 的全球底图。
     *
     * 手动模式不做降级：用户选的级别就是他要看的级别。
     */
    fun zoomPlan(plan: MapTilePlan, requestedZoom: Int, state: MapFallbackState): MapZoomPlan {
        val requested = requestedZoom.coerceIn(MIN_ZOOM, MAX_ZOOM)
        if (plan.requested != MapStyle.AUTO) {
            return MapZoomPlan(requested = requested, zoom = requested, degraded = false, unavailable = false)
        }
        for (step in 0..MAX_DEGRADE_STEPS) {
            val zoom = (requested - step).coerceAtLeast(MIN_ZOOM)
            if (!state.zoomUnavailable(plan.effective, zoom)) {
                return MapZoomPlan(
                    requested = requested,
                    zoom = zoom,
                    degraded = zoom != requested,
                    unavailable = false,
                )
            }
        }
        // 逐级下探都试过了：兜底看最低级别的全球底图（还没试过的级别不算「不可用」）。
        return MapZoomPlan(
            requested = requested,
            zoom = MIN_ZOOM,
            degraded = MIN_ZOOM != requested,
            unavailable = state.zoomUnavailable(plan.effective, MIN_ZOOM),
        )
    }

    /** 一块瓦片加载成功：清掉该级别的「没瓦片」标记；OSM 成功即视为网络恢复。 */
    fun onTileLoaded(
        style: MapStyle,
        latitude: Double,
        longitude: Double,
        zoom: Int,
        state: MapFallbackState,
        nowMillis: Long,
    ): MapFallbackState {
        if (style != MapStyle.AUTO) return state
        val plan = plan(style, latitude, longitude, state)
        var next = state
            .markZoom(plan.effective, zoom, available = true)
            .copy(lastFailedZoom = null, zoomFailures = 0)
        if (zoom <= MIN_ZOOM) {
            // 最低级别的全球底图都出图了 = 网络回来了：把「某级别没瓦片」的记忆一起清掉，
            // 让降级链回到默认级别重试（万一真缺瓦片，会被重新学一遍）。
            next = next.copy(unavailableZooms = next.unavailableZooms - plan.effective)
        }
        if (plan.effective == MapStyle.OSM) {
            next = next.recovered(nowMillis)
        }
        return next
    }

    /**
     * 一块瓦片加载失败（osmdroid 已把 HTTP 非 2xx / 连接超时 / 解码失败统一收敛成失败回调）：
     * * 正在用 OSM：累计连续失败，够 [FAILURE_THRESHOLD] 次就回退到高德；
     * * 正在用高德：同一级别连续失败够 [FAILURE_THRESHOLD] 次才判「这个级别没瓦片」，交给 [zoomPlan] 降级。
     */
    fun onTileFailed(
        style: MapStyle,
        latitude: Double,
        longitude: Double,
        zoom: Int,
        state: MapFallbackState,
        nowMillis: Long,
    ): MapFallbackState {
        if (style != MapStyle.AUTO) return state
        // 刚切过源：这些失败多半属于切换前就发出去的请求，丢了不算。
        if (state.isSettling(nowMillis)) return state
        val plan = plan(style, latitude, longitude, state)
        if (plan.effective != MapStyle.OSM) {
            val streak = if (state.lastFailedZoom == zoom) state.zoomFailures + 1 else 1
            var next = state.copy(lastFailedZoom = zoom, zoomFailures = streak)
            if (streak >= FAILURE_THRESHOLD) {
                next = next
                    .markZoom(plan.effective, zoom, available = false)
                    .copy(lastFailedZoom = null, zoomFailures = 0)
            }
            return next
        }
        val failures = state.osmFailures + 1
        if (failures < FAILURE_THRESHOLD) return state.copy(osmFailures = failures)
        return state.copy(
            osmFailures = failures,
            fellBack = true,
            fallbackFailures = failures,
            probeAtMillis = nowMillis + PROBE_INTERVAL_MILLIS,
            lastFailedZoom = null,
            zoomFailures = 0,
            switchedAtMillis = nowMillis,
        )
    }

    /** 清空会话记忆（切到「自动」或重新选地点时调用）。 */
    fun reset(): MapFallbackState = MapFallbackState()
}

/** 会话内的底图回退状态（不可变，Compose 直接观察）。 */
data class MapFallbackState(
    /** OSM 连续失败次数：任意一块 OSM 瓦片成功即清零。 */
    val osmFailures: Int = 0,
    /** 是否已经回退到高德。 */
    val fellBack: Boolean = false,
    /** 触发这次回退时累计的 OSM 失败次数（诊断文案「OSM 失败 3 次后回退」）。 */
    val fallbackFailures: Int = 0,
    /** 回退后「下次探测 OSM」的时间；null = 没在回退。 */
    val probeAtMillis: Long? = null,
    /** 会话内学到的「某底图在某级别没有瓦片」，降级链据此下探。 */
    val unavailableZooms: Map<MapStyle, Set<Int>> = emptyMap(),
    /** 当前源最近一次失败发生在哪个级别（配合 [zoomFailures] 判断「这级别真的没瓦片」）。 */
    val lastFailedZoom: Int? = null,
    /** 同一级别连续失败次数：成功一次就清零，够阈值才判该级别没瓦片。 */
    val zoomFailures: Int = 0,
    /** 最近一次切源（回退 / 恢复）的时刻，用来丢弃切换瞬间还在飞的旧请求的失败。 */
    val switchedAtMillis: Long? = null,
) {
    /** 该底图在这个级别上是否已被判定「没有瓦片」。 */
    fun zoomUnavailable(style: MapStyle, zoom: Int): Boolean = zoom in unavailableZooms[style].orEmpty()

    /** 是否落在切源后的「残响」窗口里（这些失败不计入统计）。 */
    fun isSettling(nowMillis: Long): Boolean {
        val at = switchedAtMillis ?: return false
        return nowMillis - at in 0 until MapFallback.SWITCH_SETTLE_MILLIS
    }

    /**
     * 网络恢复：清掉失败计数与回退标记，连「某级别没瓦片」的记忆也一起丢掉
     * （那批记忆是断网时学来的，已经过期；真缺瓦片会被重新学一遍）。
     */
    fun recovered(nowMillis: Long): MapFallbackState = copy(
        osmFailures = 0,
        fellBack = false,
        fallbackFailures = 0,
        probeAtMillis = null,
        unavailableZooms = emptyMap(),
        lastFailedZoom = null,
        zoomFailures = 0,
        switchedAtMillis = nowMillis,
    )

    internal fun markZoom(style: MapStyle, zoom: Int, available: Boolean): MapFallbackState {
        val current = unavailableZooms[style].orEmpty()
        val next = if (available) current - zoom else current + zoom
        if (next == current) return this
        return copy(unavailableZooms = unavailableZooms + (style to next))
    }
}

/** 一次底图选择：实际用哪个源、是不是回退出来的。 */
data class MapTilePlan(
    /** 设置里的模式：自动或某个手动底图。 */
    val requested: MapStyle,
    /** 按地区规则算出来的首选底图。 */
    val preferred: MapStyle,
    /** 真正去取瓦片的底图（回退后是高德）。 */
    val effective: MapStyle,
    /** 是否正在用回退的底图。 */
    val fellBack: Boolean,
    /** 触发回退时的 OSM 连续失败次数。 */
    val fallbackFailures: Int,
    /** 下次探测 OSM 的时间；没回退时是 null。 */
    val probeAtMillis: Long?,
)

/** 缩放级别解析结果。 */
data class MapZoomPlan(
    val requested: Int,
    val zoom: Int,
    /** 是否为了绕开「没瓦片的级别」降过级。 */
    val degraded: Boolean,
    /** 连最低级别的全球底图都拿不到：界面显示「底图不可用」。 */
    val unavailable: Boolean,
)

/**
 * 会话级的底图回退状态机。
 *
 * 线程约定：瓦片回调挂在主线程 Handler 上，OSM 探测在 IO 线程上跑；
 * 内部用 [synchronized] 串起来，Compose 侧只读 [state]。
 */
class MapFallbackTracker(
    private val clock: () -> Long = { System.currentTimeMillis() },
    private val probeOsm: () -> Boolean = { false },
) {

    private val lock = Any()
    private val _state = MutableStateFlow(MapFallbackState())
    val state: StateFlow<MapFallbackState> = _state.asStateFlow()

    /** 地图上实际生效的缩放级别（诊断用）；null = 还没应用过。 */
    @Volatile
    private var zoomApplied: Int? = null

    @Volatile
    private var probing = false

    fun snapshot(): MapFallbackState = _state.value

    fun plan(style: MapStyle, latitude: Double, longitude: Double): MapTilePlan =
        MapFallback.plan(style, latitude, longitude, snapshot())

    fun zoomPlan(plan: MapTilePlan, requestedZoom: Int = MapFallback.DEFAULT_ZOOM): MapZoomPlan =
        MapFallback.zoomPlan(plan, requestedZoom, snapshot())

    fun appliedZoom(): Int? = zoomApplied

    fun onZoomApplied(zoom: Int) {
        zoomApplied = zoom
    }

    fun onTileLoaded(style: MapStyle, latitude: Double, longitude: Double, zoom: Int) {
        val now = clock()
        update { MapFallback.onTileLoaded(style, latitude, longitude, zoom, it, now) }
    }

    fun onTileFailed(style: MapStyle, latitude: Double, longitude: Double, zoom: Int) {
        val now = clock()
        update { MapFallback.onTileFailed(style, latitude, longitude, zoom, it, now) }
    }

    /** 切到「自动」或重新选地点时清空记忆。 */
    fun reset() {
        zoomApplied = null
        update { MapFallback.reset() }
    }

    /**
     * 到点了就探测一次 OSM（**阻塞**，调用方保证在后台线程）。
     *
     * 探测只取一块最低级别的小瓦片：成功 → 切回 OSM 并清零失败计数；
     * 失败 → 继续用高德，并把下次探测往后推 [MapFallback.PROBE_INTERVAL_MILLIS]。
     *
     * @return 这次是否真的发了探测请求（没回退 / 没到点 / 已有探测在飞 → false）。
     */
    fun probeIfDue(): Boolean {
        val current = snapshot()
        if (!current.fellBack) return false
        val due = current.probeAtMillis ?: return false
        if (clock() < due) return false
        if (probing) return false
        probing = true
        return try {
            val now = clock()
            if (runCatching(probeOsm).getOrDefault(false)) {
                update { it.recovered(clock()) }
            } else {
                update { it.copy(probeAtMillis = now + MapFallback.PROBE_INTERVAL_MILLIS) }
            }
            true
        } finally {
            probing = false
        }
    }

    private fun update(block: (MapFallbackState) -> MapFallbackState) {
        synchronized(lock) { _state.value = block(_state.value) }
    }
}

/**
 * 会话级的底图回退状态：ViewModel 与诊断页读同一份（进程内有效，杀进程即清零）。
 *
 * 为什么不做成 ViewModel 私有：诊断页是独立 Dialog、只拿得到 Context，而
 * 「现在用的哪个底图 / OSM 失败几次」正是排查「境外地图空白」时最需要对齐的信息。
 */
object MapFallbackSession {
    val tracker: MapFallbackTracker by lazy {
        MapFallbackTracker(probeOsm = { OsmTileProbe.reachable() })
    }
}

/**
 * OSM 可达性探测：只取一块最低级别的全球瓦片（几 KB），2xx 且非空即算通。
 *
 * 用固定的 `tile.openstreetmap.org`（与 osmdroid 的 MAPNIK 同源），按 OSM 使用政策带 User-Agent。
 * 走的是普通 HttpURLConnection：不依赖 osmdroid 的下载队列，也就不会被它的 URL backoff 拦住。
 */
internal object OsmTileProbe {

    /** z=3 的全球瓦片：任何地区都在，且体积小。 */
    private const val PROBE_URL = "https://tile.openstreetmap.org/3/4/3.png"
    private const val TIMEOUT_MILLIS = 4_000
    private const val USER_AGENT = "com.realsuntime.solartime (map fallback probe)"

    fun reachable(): Boolean = runCatching {
        val connection = (URL(PROBE_URL).openConnection() as HttpURLConnection).apply {
            connectTimeout = TIMEOUT_MILLIS
            readTimeout = TIMEOUT_MILLIS
            instanceFollowRedirects = true
            setRequestProperty("User-Agent", USER_AGENT)
        }
        try {
            connection.responseCode in 200..299 && looksLikeTileImage(connection)
        } finally {
            runCatching { connection.disconnect() }
        }
    }.getOrDefault(false)

    /**
     * 前两字节是 PNG / JPEG 的魔数才算「真拿到了瓦片」。
     *
     * 只判状态码不够：DNS 污染 / 运营商劫持常返回 200 的假页面，
     * 那会让探测误报「OSM 通」→ 切回 OSM 又失败，白折腾一轮。
     */
    private fun looksLikeTileImage(connection: HttpURLConnection): Boolean {
        val head = connection.inputStream?.use { input ->
            ByteArray(2).also { input.read(it) }
        } ?: return false
        val png = head[0] == 0x89.toByte() && head[1] == 'P'.code.toByte()
        val jpeg = head[0] == 0xFF.toByte() && head[1] == 0xD8.toByte()
        return png || jpeg
    }
}

/**
 * 诊断页的底图摘要：每行一个 `键 = 值`，纯函数（不碰 Android），便于单测。
 *
 * 报障「境外出差地图空白」时，一眼要能看出：现在是高德还是 OSM、是不是回退来的、
 * 缩放有没有降过、OSM 失败几次、什么时候会再探一次。
 */
internal object MapFallbackDiagnostics {

    fun lines(plan: MapTilePlan, zoom: MapZoomPlan, state: MapFallbackState, nowMillis: Long): List<String> = listOf(
        "地图底图 = ${sourceLine(plan)}",
        "地图底图样式 = ${styleName(plan.requested)}",
        "首选底图 = ${styleName(plan.preferred)}",
        "地图缩放 = ${zoom.zoom}" + if (zoom.degraded) "（已降级：请求 ${zoom.requested}）" else "",
        "瓦片状态 = " + if (zoom.unavailable) "最低级别也没有瓦片（界面显示「底图不可用」）" else "正常",
        "OSM 失败次数 = ${if (plan.requested == MapStyle.AUTO) state.osmFailures else 0}",
        "下次探测 OSM = ${probeLine(plan, state, nowMillis)}",
    )

    private fun sourceLine(plan: MapTilePlan): String = when {
        // 手动选择：说清楚「不回退」，免得看日志的人以为兜底没生效。
        plan.requested != MapStyle.AUTO -> "${styleName(plan.effective)}（手动选择，不回退）"
        plan.fellBack -> "高德（OSM 失败 ${plan.fallbackFailures} 次后回退）"
        else -> "${styleName(plan.effective)}（自动：${if (plan.effective == MapStyle.OSM) "境外" else "境内"}）"
    }

    private fun probeLine(plan: MapTilePlan, state: MapFallbackState, nowMillis: Long): String {
        if (plan.requested != MapStyle.AUTO) return "不探测（手动选择底图）"
        val at = state.probeAtMillis ?: return "无（未回退）"
        val atText = SimpleDateFormat("HH:mm:ss", Locale.US).format(Date(at))
        val wait = (at - nowMillis).coerceAtLeast(0L)
        val waitText = if (wait == 0L) "已到时间，下次心跳就探测" else "约 ${durationText(wait)}后"
        return "$atText（$waitText）"
    }

    /** 毫秒时长 → 诊断文案：「42 秒」「3 分 20 秒」「5 分钟」。 */
    private fun durationText(millis: Long): String {
        val seconds = (millis / 1000).coerceAtLeast(0L)
        return when {
            seconds < 60 -> "$seconds 秒"
            seconds % 60 == 0L -> "${seconds / 60} 分钟"
            else -> "${seconds / 60} 分 ${seconds % 60} 秒"
        }
    }

    private fun styleName(style: MapStyle): String = when (style) {
        MapStyle.AUTO -> "自动"
        MapStyle.OSM -> "OpenStreetMap"
        MapStyle.AMAP_VECTOR -> "高德矢量"
        MapStyle.AMAP_SATELLITE -> "高德卫星"
    }
}
