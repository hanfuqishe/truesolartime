package com.realsuntime.solartime.data

/**
 * 界面与桌面卡片的配色模式：自动 / 强制亮色 / 强制暗色。
 *
 * 「自动」是**默认值，也是 1.4.x 之前的唯一行为**：白天（太阳在地平线上）用亮色、夜里用暗色，
 * 不看系统的深色开关 —— 太阳落山的那一刻整个界面一起换色。
 * 强制模式只是忽略日出日落，其余渲染逻辑（关键时间配色、时间轴、卡片渐变）完全一样。
 */
enum class ThemeMode {

    /** 按日出日落自动切换（默认）。 */
    AUTO,

    /** 永远亮色。 */
    LIGHT,

    /** 永远暗色。 */
    DARK,
    ;

    /**
     * 当前该不该用暗色。
     *
     * @param sunIsUp 太阳是否在地平线之上（`SolarSnapshot.isDay` / 小组件的太阳高度角判断）。
     *   [AUTO] 用它，[LIGHT]/[DARK] 直接忽略它。
     */
    fun isDark(sunIsUp: Boolean): Boolean = when (this) {
        AUTO -> !sunIsUp
        LIGHT -> false
        DARK -> true
    }

    companion object {
        /** 存储里的名字 → 枚举。认不出来（旧版本没有这个键、或值被改坏）一律回「自动」。 */
        fun fromName(name: String?): ThemeMode = entries.firstOrNull { it.name == name } ?: AUTO
    }
}
