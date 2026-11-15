package com.realsuntime.solartime.ui

import kotlin.math.roundToInt

/**
 * 「系统加粗」到「实际字重」的换算，纯函数，可单测（不碰 Android / Compose）。
 *
 * 卡片排版把字重写死（Medium / Normal），但系统的「加粗」会在**我们写死的字重之上**再加一层。
 * 实测有两条互相独立的通道：
 *
 * 1. **加法**：`Configuration.fontWeightAdjustment`（Android 12+，AOSP「加粗文字」开关）。
 *    框架把 `fontWeightAdjustment` 直接加到最终字重上，于是 Medium(500) 渲染成 800。
 *    抵消办法是把请求的字重减掉同样的量：请求 200 → 渲染 500。
 *
 * 2. **乘法**：华为 EMUI / HarmonyOS 的 `Settings.System.font_weight_scale`（「加粗字体」）。
 *    这是华为自加的一层，**不经过** `Configuration`。注意它的正常态**不是 1**：
 *    这台 ELS-AN00 上正常态是 `font_weight_scale = font_weight_scale_normal = 0.79`，
 *    也就是说「加粗」真正加的是**相对 normal 的比值**，而不是绝对值本身。
 *    所以这里必须传 [scaleRatio]（= `font_weight_scale / font_weight_scale_normal`），
 *    不能直接把 0.79 当成倍率 —— 那会把正常态的字重反过来放大 1.27 倍。
 *
 * 两条通道同时开时按「先加后乘」反解：请求 = nominal / ratio - adjustment。
 * （单通道时与逐条抵消等价，所以两条一起做不会互相干扰。）
 */
internal object CardFontMath {

    /** 合法字重区间，与 Compose `FontWeight` 一致。 */
    const val MIN_WEIGHT: Int = 1
    const val MAX_WEIGHT: Int = 1000

    /**
     * 乘法通道在字重上造成的偏移量：`ratio = 1.2`、`nominal = 500` 时返回 100。
     *
     * 只给诊断/日志用（报告里要写「华为这一档相当于在字重上加了多少」）。
     */
    fun scaleWeightDelta(nominal: Int, ratio: Float): Int {
        if (!ratio.isFinite() || ratio <= 0f || ratio == 1f) return 0
        return ((ratio - 1f) * nominal).roundToInt()
    }

    /**
     * 把「期望字重」反解成「应该请求的字重」。
     *
     * - [adjustment] 来自 `Configuration.fontWeightAdjustment`（加法，单位就是字重刻度）；
     * - [scaleRatio] 是华为 `font_weight_scale / font_weight_scale_normal` 的比值（正常态 1）。
     *
     * 结果钳在 [[MIN_WEIGHT], [MAX_WEIGHT]]：字重低于 1 没有意义，高于 1000 也没有意义。
     * 钳位会带来残差（例如 adjustment=+300、nominal=400 时 400-300=100 正常；
     * 但 nominal=200 时只能到 1，残差 99），卡片的 nominal 只取 Normal/Medium，不会触底。
     */
    fun requestWeight(nominal: Int, adjustment: Int, scaleRatio: Float): Int {
        val s = if (scaleRatio.isFinite() && scaleRatio > 0f) scaleRatio else 1f
        // 先除掉乘法（华为），再减掉加法（AOSP）。
        val requested = nominal.toFloat() / s - adjustment
        return requested.roundToInt().coerceIn(MIN_WEIGHT, MAX_WEIGHT)
    }

    /**
     * 华为 EMUI / HarmonyOS「字体粗细」滑杆的系统默认档。
     *
     * 实测这台 ELS-AN00：滑杆最细 0.6、默认 0.79、粗 0.88，还能往右到 1.12 以上；
     * `font_weight_scale_normal` 只是当前的镜像（0.88/0.88、0.6/0.6、1.12/1.12 都出现过），
     * **不能**当参照。
     */
    const val HUAWEI_DEFAULT_WEIGHT_SCALE: Float = 0.79f

    /**
     * 华为两个设置键 → 乘法倍率。
     *
     * 正常态是 `font_weight_scale == font_weight_scale_normal`（实测 0.79 / 0.79 → 倍率 1.0）。
     * 任一键缺失、非正数或非有限值都退回 1f —— 宁可不补偿，也不能凭空把字重改掉。
     */
    fun huaweiScaleRatio(scale: Float?, normal: Float?): Float {
        if (scale == null || normal == null) return 1f
        if (!scale.isFinite() || !normal.isFinite()) return 1f
        if (scale <= 0f || normal <= 0f) return 1f
        return scale / normal
    }

    /*
     * 华为「字体粗细」为什么**没有**用字重去抵消（这是实测结论，不是偷懒）：
     *
     * ELS-AN00 上把滑杆从 0.79（默认）拨到 0.88（粗），卡片 bbox 与三段文字带的 x 范围
     * 一个像素都不变（1088x618、label 105-1097、date 105-1095），只有墨迹量涨：
     * label 4186 → 4625（+10.5%）、date 3640 → 4153（+14.1%）。字形形状一致、笔画变粗、
     * 步进不变 → 这是**渲染层描粗（fake bold）**，不是换字面。
     *
     * 试过用更细的字面去抵（把请求字重从 500 压到 200/170/157/110）：
     *   - 170 与 157 落在同一个字面（label 3707，−11.4%）
     *   - 200 是另一个字面（label 4625，+10.5%）
     *   - 基线 4186 正好夹在两个可用字面之间，**够不着**
     * 系统 `sans-serif` 在这一段只暴露了两三个字面，没有中间档；再压只会从 +10.5% 翻到 −11.4%，
     * 比不补偿更差。所以这里保持「不做字重补偿」，把结论写进报告：
     * 加粗开/关的**版式完全一致**，残留只有笔画粗细（粗档 +10% 左右墨迹）。
     */
}
