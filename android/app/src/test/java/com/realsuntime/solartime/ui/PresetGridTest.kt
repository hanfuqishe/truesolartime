package com.realsuntime.solartime.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 「常用城市」等宽网格的列数计算：保证最长城市名 + 两侧内边距能放进列宽（不截断）。
 */
class PresetGridTest {

    /** 列数选出来后，最长名必须真的放得下：`最长名 + 2*padding <= 列宽`。 */
    @Test
    fun chosenColumnsAlwaysFitTheLongestName() {
        val longest = PresetGrid.estimateTextWidthDp("南极中山站") // 5 个汉字
        for (contentWidth in listOf(260f, 300f, 312f, 352f, 379f, 420f, 520f)) {
            val columns = PresetGrid.columnCount(contentWidth, longest)
            val columnWidth = (contentWidth - (columns - 1) * PresetGrid.GAP_DP) / columns
            assertTrue(
                "content=$contentWidth columns=$columns columnWidth=$columnWidth longest=$longest",
                longest + 2f * PresetGrid.CHIP_PADDING_DP <= columnWidth + 0.001f,
            )
        }
    }

    /** 宽屏自然得到更多列：P40 内容宽 ≈ 379dp → 4 列；窄屏（P30 312dp）→ 3 列。 */
    @Test
    fun widerContentYieldsMoreColumns() {
        val longest = PresetGrid.estimateTextWidthDp("南极中山站")
        assertEquals(4, PresetGrid.columnCount(379f, longest))
        assertEquals(3, PresetGrid.columnCount(312f, longest))
        // 平板级别：5 列也放得下
        assertEquals(5, PresetGrid.columnCount(520f, longest))
    }

    /** 极窄时兜底 3 列（宁可少一列，也不能截断名字）。 */
    @Test
    fun fallsBackToThreeColumnsWhenNothingFits() {
        val longest = PresetGrid.estimateTextWidthDp("南极中山站")
        assertEquals(PresetGrid.MIN_COLUMNS, PresetGrid.columnCount(120f, longest))
        assertEquals(PresetGrid.MIN_COLUMNS, PresetGrid.columnCount(0f, longest))
    }

    /** 行距比列距更紧（6dp < 8dp），chip 高度 32–34dp 且水平内边距 10–12dp。 */
    @Test
    fun rowsAreTighterThanColumnsAndTheChipStaysTappable() {
        assertEquals(6f, PresetGrid.ROW_GAP_DP, 0f)
        assertTrue("行距应比列距小", PresetGrid.ROW_GAP_DP < PresetGrid.GAP_DP)
        assertTrue("chip 高度要 ≥32dp 触控下限", PresetGrid.CHIP_HEIGHT_DP in 32f..34f)
        assertTrue("水平内边距应在 10–12dp", PresetGrid.CHIP_PADDING_DP in 10f..12f)
    }
    /** 估算：汉字 ≈ 字号宽，拉丁 ≈ 0.6 字号宽，空格 ≈ 0.3。 */
    @Test
    fun estimatesTextWidthByCharacterKind() {
        val size = PresetGrid.TEXT_SIZE_SP
        assertEquals(5f * size, PresetGrid.estimateTextWidthDp("南极中山站"), 0.01f)
        assertEquals(4f * size * 0.6f, PresetGrid.estimateTextWidthDp("Rome"), 0.01f)
        assertEquals(
            2f * size + 0.3f * size + 3f * size * 0.6f,
            PresetGrid.estimateTextWidthDp("北京 123"),
            0.01f,
        )
    }

    /**
     * 文字占比检查：同样内容宽下，4 列比 3 列的「新加坡」两侧留白明显更小
     * （P40 反馈的就是 3 列太散；4 列应把留白压到约一半）。
     */
    @Test
    fun fourColumnsTrimTheSlackComparedToThree() {
        val content = 379f
        val longest = PresetGrid.estimateTextWidthDp("南极中山站")
        val singapore = PresetGrid.estimateTextWidthDp("新加坡")

        fun slackOf(columns: Int): Float {
            val width = (content - (columns - 1) * PresetGrid.GAP_DP) / columns
            return width - singapore - 2f * PresetGrid.CHIP_PADDING_DP
        }

        val four = slackOf(PresetGrid.columnCount(content, longest)) // 4
        val three = slackOf(3)
        assertTrue("4 列留白应明显更小：4 列 $four vs 3 列 $three", four < three * 0.6f)
        assertTrue("4 列留白仍偏大：$four", four <= 3f * PresetGrid.TEXT_SIZE_SP)
    }
}
