package com.realsuntime.solartime.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** 贪心分行：chip 按「文字自然宽 + 内边距」排，放不下就换行。 */
class PresetGridPackRowsTest {

    private val gap = 8f
    private val rowWidth = 300f

    @Test
    fun exactlyFitsOnOneRow() {
        // 100 + 8 + 100 + 8 + 84 = 300
        val rows = PresetGrid.packRows(listOf(100f, 100f, 84f), rowWidth, gap)
        assertEquals(1, rows.size)
        assertEquals(listOf(0, 1, 2), rows[0])
    }

    @Test
    fun oneDpShortWrapsToTheNextRow() {
        // 100 + 8 + 100 + 8 + 85 = 301 > 300 → 第三个换行
        val rows = PresetGrid.packRows(listOf(100f, 100f, 85f), rowWidth, gap)
        assertEquals(2, rows.size)
        assertEquals(listOf(0, 1), rows[0])
        assertEquals(listOf(2), rows[1])
    }

    @Test
    fun itemWiderThanTheRowGetsItsOwnRow() {
        val rows = PresetGrid.packRows(listOf(80f, 400f, 80f), rowWidth, gap)
        assertEquals(3, rows.size)
        assertEquals(listOf(0), rows[0])
        assertEquals(listOf(1), rows[1])
        assertEquals(listOf(2), rows[2])
    }

    @Test
    fun emptyListProducesNoRows() {
        assertTrue(PresetGrid.packRows(emptyList(), rowWidth, gap).isEmpty())
    }

    @Test
    fun singleItemIsOneRow() {
        assertEquals(listOf(listOf(0)), PresetGrid.packRows(listOf(120f), rowWidth, gap))
    }

    /** 每次换行都意味着「本行剩余宽度 < gap + 下一个 chip」，不会提前换行。 */
    @Test
    fun neverWrapsWhileTheNextChipStillFits() {
        val widths = listOf(90f, 60f, 70f, 50f, 40f, 30f)
        val rows = PresetGrid.packRows(widths, rowWidth, gap)
        for (row in rows) {
            val used = row.sumOf { widths[it].toDouble() }.toFloat() + gap * (row.size - 1)
            assertTrue("行超宽：$used > $rowWidth", used <= rowWidth + 0.001f)
        }
    }
}
