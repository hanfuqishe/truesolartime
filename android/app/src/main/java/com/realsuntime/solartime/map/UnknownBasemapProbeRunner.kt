package com.realsuntime.solartime.map

import android.graphics.Bitmap
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
import java.util.concurrent.atomic.AtomicReference

/**
 * 未知态全球底图的**两块瓦片**并行探测（[UnknownBasemap] 的「跑腿」部分）。
 *
 * 两块同时发：OSM z3 与高德 z3，各几 KB。先回来且有内容的那块胜出，[UnknownBasemap.PROBE_DEADLINE_MILLIS]
 * 封顶；两块都失败（或到点都没回来）就返回 `source = null`，界面直接显示「底图不可用」。
 *
 * 为什么要独立的 [CoroutineScope]：`HttpURLConnection` 的 connect/read 是阻塞调用、**不响应协程取消**。
 * 把请求挂在调用方的结构化并发树上，整个探测就得等最慢那一个跑完（正常态那套实测因此拖到 7 秒）。
 * 这里让请求跑在独立 scope 上，主流程只轮询「有没有胜者 / 两块是不是都结束了」，到点就取消在飞的请求。
 */
object UnknownBasemapProbeRunner {

    private const val USER_AGENT = "com.realsuntime.solartime (unknown basemap probe)"

    /** 轮询等待粒度：20ms，相对 2 秒封顶已经足够细。 */
    private const val WAIT_STEP_MILLIS = 20L

    /**
     * 跑一次未知态探测（**挂起**，调用方保证在后台线程）。
     *
     * @param deadlineMillis 封顶耗时；测试可以传一个很小的值
     */
    suspend fun probe(
        deadlineMillis: Long = UnknownBasemap.PROBE_DEADLINE_MILLIS,
    ): UnknownBasemapResult {
        val startedAt = System.currentTimeMillis()
        val winner = AtomicReference<MapStyle?>(null)
        val pending = AtomicInteger(UnknownBasemap.PROBE_TILES.size)

        val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
        UnknownBasemap.PROBE_TILES.forEach { tile ->
            scope.launch {
                try {
                    // 第一块有内容的瓦片回来就记下它，另一块不必再等。
                    if (fetch(tile)) winner.compareAndSet(null, tile.style)
                } finally {
                    pending.decrementAndGet()
                }
            }
        }

        val finishedEarly = withTimeoutOrNull(deadlineMillis) {
            // 有胜者就收工；两块都失败（pending 归零）也收工；否则等到封顶。
            while (winner.get() == null && pending.get() > 0) {
                delay(WAIT_STEP_MILLIS)
            }
            true
        } != null
        scope.cancel()

        val source = winner.get()
        val elapsed = System.currentTimeMillis() - startedAt
        val detail = when {
            source != null -> "${styleName(source)} 先返回（${elapsed}ms）"
            !finishedEarly -> "两块都没在 ${deadlineMillis}ms 内返回"
            else -> "两块都失败（${elapsed}ms）"
        }
        return UnknownBasemapResult(source = source, elapsedMillis = elapsed, detail = detail)
    }

    /** 取一块瓦片；有内容（OSM 只要魔数，高德要非空白）返回 true。 */
    private fun fetch(tile: UnknownBasemap.ProbeTile): Boolean = runCatching {
        val connection = open(tileUrl(tile))
        try {
            if (connection.responseCode !in 200..299) return false
            if (tile.style == MapStyle.OSM) {
                // OSM：只要 2xx + 真图片（前两字节是 PNG/JPEG 魔数）就算通；
                // 它不会像高德那样回「200 的空白瓦片」，不用解像素。
                val head = connection.inputStream.use { input -> ByteArray(2).also { input.read(it) } }
                val png = head[0] == 0x89.toByte() && head[1] == 'P'.code.toByte()
                val jpeg = head[0] == 0xFF.toByte() && head[1] == 0xD8.toByte()
                png || jpeg
            } else {
                // 高德：解出来 → 用与运行期完全相同的 TileBlank 判空白（空白瓦片 = 没内容）。
                val bytes = connection.inputStream.use { it.readBytes() }
                val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: return false
                try {
                    !sampleContent(bitmap).isBlank
                } finally {
                    bitmap.recycle()
                }
            }
        } finally {
            runCatching { connection.disconnect() }
        }
    }.getOrDefault(false)

    private fun tileUrl(tile: UnknownBasemap.ProbeTile): String =
        if (tile.style == MapStyle.OSM) tile.osmUrl else tile.amapUrl

    /** 缩到 [TileBlank.SAMPLE_SIDE]² 再取像素（最近邻，不做插值），与运行期同一套判据。 */
    private fun sampleContent(bitmap: Bitmap): TileContent {
        val side = TileBlank.SAMPLE_SIDE
        val scaled = Bitmap.createScaledBitmap(bitmap, side, side, false)
        return try {
            val pixels = IntArray(side * side)
            scaled.getPixels(pixels, 0, side, 0, 0, side, side)
            TileBlank.analyzeColors(pixels)
        } finally {
            if (scaled !== bitmap) scaled.recycle()
        }
    }

    private fun open(url: String): HttpURLConnection =
        (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = UnknownBasemap.TILE_TIMEOUT_MILLIS.toInt()
            readTimeout = UnknownBasemap.TILE_TIMEOUT_MILLIS.toInt()
            instanceFollowRedirects = true
            setRequestProperty("User-Agent", USER_AGENT)
        }

    private fun styleName(style: MapStyle): String = when (style) {
        MapStyle.OSM -> "OSM"
        MapStyle.AMAP_VECTOR -> "高德"
        MapStyle.AMAP_SATELLITE -> "高德卫星"
        MapStyle.AUTO -> "自动"
    }
}

/**
 * 未知态探测结果。
 *
 * @param source 选中的源；null = 两块都没内容 → 界面显示「底图不可用」（不降级）
 * @param elapsedMillis 实际耗时（诊断/报告用）
 * @param detail 一句话结论，例如 `OSM 先返回（430ms）`
 */
data class UnknownBasemapResult(
    val source: MapStyle?,
    val elapsedMillis: Long,
    val detail: String,
)
