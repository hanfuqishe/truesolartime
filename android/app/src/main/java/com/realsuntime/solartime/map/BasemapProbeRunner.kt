package com.realsuntime.solartime.map

import android.graphics.BitmapFactory
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.atomic.AtomicInteger

/**
 * 并行探测的「跑腿」部分：**同时**取 5 块单瓦片（OSM z3/z12 + 高德 z12/z10/z3），
 * 每块自己带短超时，整体再套一个硬封顶。
 *
 * 为什么两个源都探：「先换源、再降级」要求知道另一个源在同精度有没有内容
 * （典型：南极中山站高德全空白，OSM 有海岸线）。
 *
 * 为什么要一个独立的 [CoroutineScope]：`HttpURLConnection` 的 connect/read 是阻塞调用，
 * **不响应协程取消**。之前把请求放在 `coroutineScope { async { … } }` 里，结构化的父子关系
 * 让整个探测等最慢的那一个跑完 —— 实测「4.5 秒封顶」实际花了 **7 秒**（connect 3.5s + read 3.5s）。
 * 现在请求跑在独立 scope 上，调用方只等到「五块都有结论」或升级窗口结束，然后取消还在飞的请求
 * （它们的 socket 会按自身超时收尾，不再拖住返回）。
 *
 * 判定逻辑全在纯函数 [BasemapProbe.decide] / [BasemapProbe.choose] 里；这里只负责
 * 「发请求 + 解图片 + 交给 [TileBlank] 判空白」。
 */
object BasemapProbeRunner {

    private const val USER_AGENT = "com.realsuntime.solartime (basemap probe)"

    /** OSM 单块瓦片模板（z3 判可达性 + z12 判高精度；都走同一个 host）。 */
    private const val OSM_TILE_URL = "https://tile.openstreetmap.org"

    /** 与 [MapTileSources] 里高德矢量用的模板一致（探测只要一块，取第一个 host 即可）。 */
    private const val AMAP_TILE_URL =
        "https://webrd01.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=8"

    /** 轮询等待粒度：20ms 对首屏来说已经够细。 */
    private const val WAIT_STEP_MILLIS = 20L

    /**
     * 跑一次并行探测（**阻塞**，调用方保证在后台线程）。
     *
     * 每块瓦片一出结论就通过 [onTile] 回调（渐进升级：先到先用，更好的才升级）；
     * 没来得及出结论的按「失败」算（[BasemapProbeResult.timedOut] = true）。
     *
     * 等待策略：**出过图**就等到升级窗口结束（或全部出结论）；一块有内容的都没有才在
     * [BasemapProbe.OVERALL_TIMEOUT_MILLIS] 处放弃 —— 那个 4 秒只用于判「底图不可用」，不再截断升级。
     */
    suspend fun probe(
        latitude: Double,
        longitude: Double,
        onTile: (BasemapProbe.ProbeTile, Long) -> Unit = { _, _ -> },
    ): BasemapProbeResult {
        val startedAt = System.currentTimeMillis()
        // 区域偏好只决定「同级时选谁」；两个源都要探。
        val preferred = MapStyle.AUTO.effective(latitude, longitude)
        val amapZooms = BasemapProbe.AMAP_PROBE_ZOOMS.toList()
        val osmZooms = BasemapProbe.OSM_PROBE_ZOOMS.toList()
        val tiles = java.util.Collections.synchronizedList(mutableListOf<BasemapProbe.ProbeTile>())
        val pending = AtomicInteger(osmZooms.size + amapZooms.size)
        fun elapsed(): Long = System.currentTimeMillis() - startedAt
        fun record(tile: BasemapProbe.ProbeTile) {
            tiles.add(tile)
            onTile(tile, elapsed())
        }

        // 独立 scope：阻塞请求不响应取消，不能挂在调用方的结构化并发树上。
        val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
        osmZooms.forEach { zoom ->
            scope.launch {
                try {
                    record(
                        BasemapProbe.ProbeTile(
                            source = MapStyle.OSM,
                            zoom = zoom,
                            hasContent = probeOsmTile(latitude, longitude, zoom),
                        ),
                    )
                } finally {
                    pending.decrementAndGet()
                }
            }
        }
        amapZooms.forEach { zoom ->
            scope.launch {
                try {
                    val probe = probeAmap(latitude, longitude, zoom)
                    record(BasemapProbe.ProbeTile(MapStyle.AMAP_VECTOR, zoom, probe.hasContent))
                } finally {
                    pending.decrementAndGet()
                }
            }
        }

        val finished = withTimeoutOrNull(
            BasemapProbe.UPGRADE_WINDOW_MILLIS + BasemapProbe.TILE_TIMEOUT_MILLIS,
        ) {
            while (pending.get() > 0) {
                // 出过图：等到升级窗口结束；一块内容都没有：4 秒就判不可用。
                val anyContent = synchronized(tiles) { tiles.any { it.hasContent } }
                val limit = if (anyContent) {
                    startedAt + BasemapProbe.UPGRADE_WINDOW_MILLIS
                } else {
                    startedAt + BasemapProbe.OVERALL_TIMEOUT_MILLIS
                }
                if (System.currentTimeMillis() >= limit) break
                delay(WAIT_STEP_MILLIS)
            }
            true
        } != null
        scope.cancel() // 还在飞的请求：取消（socket 会按自身超时收尾）

        return BasemapProbeResult(
            preferred = preferred,
            tiles = synchronized(tiles) { tiles.toList() },
            elapsedMillis = elapsed(),
            timedOut = !finished,
        )
    }

    /** OSM 单块瓦片：2xx + 真图片（前两字节是 PNG/JPEG 魔数）就算有内容。 */
    private fun probeOsmTile(latitude: Double, longitude: Double, zoom: Int): Boolean = runCatching {
        val (x, y) = BasemapProbe.tileOf(latitude, longitude, zoom)
        val connection = open("$OSM_TILE_URL/$zoom/$x/$y.png")
        try {
            if (connection.responseCode !in 200..299) return false
            val head = connection.inputStream.use { input ->
                ByteArray(2).also { input.read(it) }
            }
            val png = head[0] == 0x89.toByte() && head[1] == 'P'.code.toByte()
            val jpeg = head[0] == 0xFF.toByte() && head[1] == 0xD8.toByte()
            png || jpeg
        } finally {
            runCatching { connection.disconnect() }
        }
    }.getOrDefault(false)

    /** 高德：取一块瓦片 → 解出来 → 用与运行期完全相同的 [TileBlank] 判空白。 */
    private fun probeAmap(latitude: Double, longitude: Double, zoom: Int): BasemapProbe.AmapProbe {
        val (x, y) = BasemapProbe.tileOf(latitude, longitude, zoom)
        return runCatching {
            val connection = open("$AMAP_TILE_URL&x=$x&y=$y&z=$zoom")
            val bytes = try {
                if (connection.responseCode !in 200..299) return BasemapProbe.AmapProbe(zoom, false)
                connection.inputStream.use { it.readBytes() }
            } finally {
                runCatching { connection.disconnect() }
            }
            val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                ?: return BasemapProbe.AmapProbe(zoom, false)
            val content = try {
                val side = TileBlank.SAMPLE_SIDE
                val scaled = android.graphics.Bitmap.createScaledBitmap(bitmap, side, side, false)
                try {
                    val pixels = IntArray(side * side)
                    scaled.getPixels(pixels, 0, side, 0, 0, side, side)
                    TileBlank.analyzeColors(pixels)
                } finally {
                    if (scaled !== bitmap) scaled.recycle()
                }
            } finally {
                bitmap.recycle()
            }
            BasemapProbe.AmapProbe(
                zoom = zoom,
                hasContent = !content.isBlank,
                colorKinds = content.colorKinds,
                fetched = true,
            )
        }.getOrDefault(BasemapProbe.AmapProbe(zoom = zoom, hasContent = false))
    }

    private fun open(url: String): HttpURLConnection =
        (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = BasemapProbe.TILE_TIMEOUT_MILLIS.toInt()
            readTimeout = BasemapProbe.TILE_TIMEOUT_MILLIS.toInt()
            instanceFollowRedirects = true
            setRequestProperty("User-Agent", USER_AGENT)
            // 不手动设 Accept-Encoding：Android 的 HttpURLConnection 会透明处理 gzip，
            // 手动设反而可能拿到未解压的字节，BitmapFactory 解不出来。
        }
}
