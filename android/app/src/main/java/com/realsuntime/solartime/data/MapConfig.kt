package com.realsuntime.solartime.data

import android.content.Context
import org.osmdroid.config.Configuration

/** osmdroid 的全局配置：缓存目录使用应用私有空间，并按 OSM 要求设置 User-Agent。 */
object MapConfig {

    @Volatile
    private var initialized = false

    fun init(context: Context) {
        if (initialized) return
        val config = Configuration.getInstance()
        config.load(context.applicationContext, context.getSharedPreferences("osmdroid", Context.MODE_PRIVATE))
        config.userAgentValue = context.packageName
        initialized = true
    }
}
