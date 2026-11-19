package com.realsuntime.solartime.widget

/**
 * 时钟「秒数」限宽计算。
 *
 * 桌面卡片的时间用 `Chronometer` 显示，它的文本是 **`M:SS`**（自带冒号）；布局里另有一个静态冒号视图，
 * 靠 `setMaxWidth` 把 Chronometer 的 `M:` 裁掉、只露出秒数。
 *
 * 裁剪宽度必须**严格小于「两位数字 + 一个冒号」**，否则自带冒号会完整露出来，和静态冒号叠成 `::37`。
 * 早先的实现是「两位数字宽 + 2dp 余量」，而冒号本身只有零点几个 em —— 2dp 足以把冒号放出来，
 * 真太阳时那一侧就出现了双冒号。
 */
internal object ClockWidthMath {

    /**
     * 秒数视图的 `maxWidth`（px）。
     *
     * @param digitWidthPx 单个数字在当前字号下的实测宽度
     * @param colonWidthPx 冒号在当前字号下的实测宽度
     * @param slackPx 期望的亚像素余量；会被压到 **小于冒号宽**，保证冒号挤不进来
     */
    fun secondsMaxWidthPx(digitWidthPx: Float, colonWidthPx: Float, slackPx: Float): Int {
        val digits = 2f * digitWidthPx.coerceAtLeast(0f)
        val colon = colonWidthPx.coerceAtLeast(0f)
        // 关键约束：余量最多 1px（且必须 < 冒号宽）。
        // 实测 2dp（≈6px）就足以让冒号露出一个小圆点，和静态冒号并排看就是「::」；
        // 所以这里把余量压到 1px 以内，宁可让第一位数字右边缘差半像素，也不放冒号进来。
        val safeSlack = slackPx.coerceIn(0f, 1f).coerceAtMost((colon - 1f).coerceAtLeast(0f))
        return (digits + safeSlack).toInt().coerceAtLeast(1)
    }
}
