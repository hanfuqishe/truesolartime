package com.realsuntime.solartime.data

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/**
 * **临时调试开关**：只在开发期用来预览首页大卡片的配色，不写任何持久化。
 *
 * 用法：首页大卡片下方的「配色预览（临时）」卡片。
 * - [isDayOverride]：强制白天/夜间；null 表示跟随太阳高度角
 * - [temperatureOverride]：强制「冻或温」/「热或温」；null 表示跟随网页
 * - [forceInKeyTime]：强制认为「当前落在关键时段内」，方便看数字与圆点的颜色
 * - [inkIntensity]：白天数字色的浓淡 0…1，1 表示与时间轴色段同色
 *
 * 想去掉这个调试功能时：删掉本文件、`ui/DebugPaletteCard.kt`，
 * 以及 `MainScreen.kt` / `SolarSnapshot.kt` / `HeroPalette.kt` 里对它的少量引用即可。
 */
object DebugPalette {

    var isDayOverride: Boolean? by mutableStateOf(null)
    var temperatureOverride: TakeTemperature? by mutableStateOf(null)
    var forceInKeyTime: Boolean by mutableStateOf(false)
    var inkIntensity: Float by mutableFloatStateOf(0.35f)

    fun anyActive(): Boolean =
        isDayOverride != null || temperatureOverride != null || forceInKeyTime
}
