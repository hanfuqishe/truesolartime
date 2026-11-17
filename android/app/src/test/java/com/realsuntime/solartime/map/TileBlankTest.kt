package com.realsuntime.solartime.map

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 空白瓦片判定：[TileBlank] 是纯函数，全在 JVM 上跑，不需要 Bitmap、不碰设备。
 *
 * 这些用例同时是对**判据数值**的说明：什么样的瓦片会被判空白、边界在哪、
 * 海面与正常城市瓦片为什么不会被误伤。
 */
class TileBlankTest {

    /** 1024 个采样点（[TileBlank.SAMPLE_SIDE]²，对应 256 像素瓦片每 8 像素取一点）。 */
    private fun samples(fill: (Int) -> Int): IntArray =
        IntArray(TileBlank.SAMPLE_SIDE * TileBlank.SAMPLE_SIDE) { fill(it) }

    private fun argb(r: Int, g: Int, b: Int): Int = (0xFF shl 24) or (r shl 16) or (g shl 8) or b

    private fun solid(color: Int): IntArray = samples { color }

    private fun analyze(colors: IntArray): TileContent = TileBlank.analyzeColors(colors)

    // ------------------------------------------------------------ 空白瓦片

    @Test
    fun solidTileIsBlank() {
        // 高德境外最常见的空白瓦片：整块 #E8E8E8 灰底。
        val content = analyze(solid(0xFFE8E8E8.toInt()))

        assertTrue(content.isBlank)
        assertEquals(1, content.colorKinds)
        assertEquals(0.0, content.variance, 0.001)
        assertEquals(TileBlank.SAMPLE_SIDE * TileBlank.SAMPLE_SIDE, content.sampleCount)
        assertFalse(content.isOcean)
    }

    @Test
    fun grayTileWithWhiteWatermarkIsBlank() {
        // 灰底 + 「高德地图」白字水印：只有两种颜色，方差也被文字拉开了一点，但远不够「有内容」。
        val gray = 0xFFE8E8E8.toInt()
        val white = 0xFFFFFFFF.toInt()
        val pixels = samples { gray }
        val side = TileBlank.SAMPLE_SIDE
        for (y in 12..16) {
            for (x in 8..24) {
                pixels[y * side + x] = white
            }
        }

        val content = analyze(pixels)

        assertEquals(2, content.colorKinds)
        assertTrue("两种颜色应该有一点方差，实际 ${content.variance}", content.variance > 1.0)
        assertTrue("方差 ${content.variance} 仍在空白阈值内", content.variance < TileBlank.VARIANCE_THRESHOLD)
        assertTrue(content.isBlank)
    }

    @Test
    fun nearMonochromeTileWithCompressionNoiseIsBlank() {
        // PNG/JPEG 编码后的灰底会有 ±3 的抖动；没有纹理就是没有纹理。
        val content = analyze(
            samples { index ->
                val noise = (index % 7) - 3
                argb(232 + noise, 232 + noise, 232 + noise)
            },
        )

        assertTrue("方差 ${content.variance} 应该很小", content.variance < TileBlank.MONO_VARIANCE)
        assertTrue(content.isBlank)
    }

    @Test
    fun emptySamplesAreNotBlank() {
        // 没采到像素（bitmap 读失败等）：宁可不降级，也不要因为一次读取失败把好底图踢下去。
        val content = analyze(IntArray(0))

        assertEquals(0, content.sampleCount)
        assertFalse(content.isBlank)
    }

    // ------------------------------------------------------------ 有内容的瓦片

    @Test
    fun normalCityTileIsNotBlank() {
        // 模拟高德矢量城市瓦片：浅灰底 + 白/黄道路 + 深色地名 + 绿地 + 水系。
        val palette = intArrayOf(
            0xFFF7F7F7.toInt(), 0xFFFFFFFF.toInt(), 0xFFFFD200.toInt(), 0xFF333333.toInt(),
            0xFFD5EDD5.toInt(), 0xFF2B7FD0.toInt(), 0xFFE8A33D.toInt(), 0xFF6B6B6B.toInt(),
            0xFF9E9E9E.toInt(), 0xFFC0392B.toInt(), 0xFF1B5E20.toInt(), 0xFFB3D9F7.toInt(),
        )

        val content = analyze(samples { palette[it % palette.size] })

        // 注意：量化会把 #FFFFFF 与 #F7F7F7 这种「差不到 16」的颜色并成一类，
        // 所以 12 种原始颜色只留下 11 种量化颜色 —— 依然远多于空白阈值的 8 种。
        assertTrue("颜色种类应该很多，实际 ${content.colorKinds}", content.colorKinds >= 10)
        assertTrue("方差应该很大，实际 ${content.variance}", content.variance > TileBlank.VARIANCE_THRESHOLD)
        assertFalse(content.isBlank)
    }

    @Test
    fun solidOceanBlueTileIsNotBlank() {
        // 纯蓝海面：颜色种类只有 1、方差为 0，但它是有效内容 —— 海洋不算空白。
        val content = analyze(solid(0xFF1E6EB5.toInt()))

        assertTrue(content.isOcean)
        assertEquals(1, content.colorKinds)
        assertEquals(0.0, content.variance, 0.001)
        assertFalse(content.isBlank)
    }

    @Test
    fun paleOceanBlueTileIsNotBlank() {
        // 高德矢量海面的浅蓝（#B3D9F7）也要算海：饱和度只是低，不是灰。
        val content = analyze(solid(0xFFB3D9F7.toInt()))

        assertTrue("蓝色占比 ${content.blueShare}", content.isOcean)
        assertFalse(content.isBlank)
    }

    @Test
    fun oceanTileWithALittleLandIsNotBlank() {
        val sea = 0xFF1E6EB5.toInt()
        val land = 0xFFD8C79A.toInt()
        val pixels = samples { sea }
        for (index in 0 until 200) {
            pixels[index] = land
        }

        val content = analyze(pixels)

        assertTrue("蓝色占比 ${content.blueShare}", content.blueShare >= TileBlank.OCEAN_BLUE_SHARE)
        assertTrue(content.isOcean)
        assertFalse(content.isBlank)
    }

    // ------------------------------------------------------------ 颜色种类阈值边界

    /**
     * 8 种「彼此很近」的颜色：每通道只在 0x80 / 0x90 两档里取，
     * 量化后是不同种类，方差却很小 —— 于是可以把「颜色种类」这一条的边界单独测出来。
     */
    private fun nearColors(count: Int): IntArray {
        val all = ArrayList<Int>(9)
        for (r in intArrayOf(0x80, 0x90)) {
            for (g in intArrayOf(0x80, 0x90)) {
                for (b in intArrayOf(0x80, 0x90)) {
                    all.add(argb(r, g, b))
                }
            }
        }
        if (count > all.size) all.add(argb(0x90, 0xA0, 0xB0))
        val picked = all.take(count).toIntArray()
        return samples { picked[it % picked.size] }
    }

    @Test
    fun sevenColorKindsAreBlank() {
        val content = analyze(nearColors(7))

        assertEquals(7, content.colorKinds)
        assertTrue("方差 ${content.variance} 应低于阈值", content.variance < TileBlank.VARIANCE_THRESHOLD)
        assertTrue(content.isBlank)
    }

    @Test
    fun eightColorKindsAreNotBlank() {
        // 边界是「少于 8 种」：正好 8 种就不再判空白（正常瓦片的量化种类远多于 8）。
        val content = analyze(nearColors(8))

        assertEquals(TileBlank.MIN_COLOR_KINDS, content.colorKinds)
        assertFalse(content.isBlank)
    }

    @Test
    fun nineColorKindsAreNotBlank() {
        val content = analyze(nearColors(9))

        assertEquals(9, content.colorKinds)
        assertFalse(content.isBlank)
    }

    // ------------------------------------------------------------ 一屏的结论

    @Test
    fun viewportIsBlankOnlyWhenEveryTileIsBlank() {
        val blank = analyze(solid(0xFFE8E8E8.toInt()))
        val ocean = analyze(solid(0xFF1E6EB5.toInt()))

        assertTrue(TileBlank.viewportIsBlank(listOf(blank, blank, blank)))
        // 混进一块海面（内容）就不能判这一屏没内容 —— z3 全球图上「沙漠纯色瓦片 + 海 + 国界」
        // 是正常画面，不是空白。
        assertFalse(TileBlank.viewportIsBlank(listOf(blank, ocean, blank)))
        // 还没看到任何瓦片：不判空白（宁可不降级，也不要把「还没加载完」当没内容）。
        assertFalse(TileBlank.viewportIsBlank(emptyList()))
    }
}
