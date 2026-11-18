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
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

/**
 * 并行探测的「跑腿」部分：**同时**取 4 块单瓦片（OSM z3 + 高德 z12/z10/z3），
 * 每块自己带短超时，整体再套一个 [BasemapProbe.OVERALL_TIMEOUT_MILLIS] 的**硬**封顶。
 *
 * 为什么要一个独立的 [CoroutineScope]：`HttpURLConnection` 的 connect/read 是阻塞调用，
 * **不响应协程取消**。之前把请求放在 `coroutineScope { async { … } }` 里，结构化的父子关系
 * 让整个探测等最慢的那一个跑完 —— 实测「4.5 秒封顶」实际花了 **7 秒**（connect 3.5s + read 3.5s）。
 * 现在请求跑在独立 scope 上，调用方只等到「四块都有结论」或整体超时，然后取消还在飞的请求
 * （它们的 socket 会按自身超时收尾，不再拖住返回）。
 *
 * 判定逻辑全在纯函数 [BasemapProbe.decide] 里；这里只负责「发请求 + 解图片 + 交给 [TileBlank] 判空白」。
 */
object BasemapProbeRunner {

    private const val USER_AGENT = "com.realsuntime.solartime (basemap probe)"

    /** OSM 的 z3 全球瓦片（任何地区都在，体积几 KB）。 */
    private const val OSM_PROBE_URL = "https://tile.openstreetmap.org/3/4/3.png"

    /** 与 [MapTileSources] 里高德矢量用的模板一致（探测只要一块，取第一个 host 即可）。 */
    private const val AMAP_TILE_URL =
        "https://webrd01.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=8"

    /** 轮询等待粒度：20ms 对首屏来说已经够细。 */
    private const val WAIT_STEP_MILLIS = 20L

    /**
     * 跑一次并行探测（**阻塞**，调用方保证在后台线程）。
     *
     * 整体超时后立刻返回：没来得及出结论的瓦片按「失败」算（[BasemapProbeResult.timedOut] = true）。
     */
    suspend fun probe(latitude: Double, longitude: Double): BasemapProbeResult {
        val startedAt = System.currentTimeMillis()
        val zooms = BasemapProbe.AMAP_PROBE_ZOOMS.toList()
        val amap = ConcurrentHashMap<Int, BasemapProbe.AmapProbe>()
        val osmReachable = AtomicBoolean(false)
        val pending = AtomicInteger(1 + zooms.size)

        // 独立 scope：阻塞请求不响应取消，不能挂在调用方的结构化并发树上。
        val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
        scope.launch {
            try {
                osmReachable.set(probeOsm())
            } finally {
                pending.decrementAndGet()
            }
        }
        zooms.forEach { zoom ->
            scope.launch {
                try {
                    amap[zoom] = probeAmap(latitude, longitude, zoom)
                } finally {
                    pending.decrementAndGet()
                }
            }
        }

        val finished = withTimeoutOrNull(BasemapProbe.OVERALL_TIMEOUT_MILLIS) {
            while (pending.get() > 0) {
                // 提前收工：已经探到「有内容」，**并且比它精度更高的档都已有结论**（空白 / 失败也算），
                // 才允许停。之前的「任意一档有内容就退」会让 z3 先回来、z12 还在飞时立刻收工，
                // decide 只看到 z3 → 选低精度。
                // 另外，OSM 已经通了的话高德结果根本不会被采用（decide 先判 OSM），不必再等高精度档。
                val earlyEnough = System.currentTimeMillis() - startedAt >= BasemapProbe.EARLY_EXIT_MILLIS &&
                    (osmReachable.get() || BasemapProbe.shouldEarlyExit(amap, zooms))
                if (earlyEnough) break
                delay(WAIT_STEP_MILLIS)
            }
            true
        } != null
        scope.cancel() // 还在飞的请求：取消（socket 会按自身超时收尾）

        val elapsed = System.currentTimeMillis() - startedAt
        val probes = zooms.map { zoom ->
            amap[zoom] ?: BasemapProbe.AmapProbe(zoom = zoom, hasContent = false, fetched = false)
        }
        return BasemapProbeResult(
            osmReachable = osmReachable.get(),
            amap = probes,
            elapsedMillis = elapsed,
            timedOut = !finished,
        )
    }

    /** OSM：2xx + 真图片（前两字节是 PNG/JPEG 魔数）就算通。 */
    private fun probeOsm(): Boolean = runCatching {
        val connection = open(OSM_PROBE_URL)
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
