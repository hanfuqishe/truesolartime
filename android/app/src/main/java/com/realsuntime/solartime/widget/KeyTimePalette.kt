package com.realsuntime.solartime.widget

import com.realsuntime.solartime.data.TakeTemperature

/**
 * 关键时间段用的配色：冻或温用暗绿，热或温用暗红。
 *
 * 用暗色而不是亮色：亮绿/亮红在橙色背景上过于抢眼，暗一档反而与底色的明度差更大、更沉稳。
 * 时间轴上的色带与真太阳时的数字都取这里的颜色，保证两处始终一致。
 */
object KeyTimePalette {

    val COLD: Int = 0xFF2E7D32.toInt()
    val HOT: Int = 0xFFB3261E.toInt()

    fun of(temperature: TakeTemperature?): Int? = when (temperature) {
        TakeTemperature.COLD_OR_MILD -> COLD
        TakeTemperature.HOT_OR_MILD -> HOT
        null -> null
    }
}
