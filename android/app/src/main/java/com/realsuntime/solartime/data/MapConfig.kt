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
        // 瓦片下载并发：osmdroid 默认 2 条，手机网络上一屏十几块瓦片要串着拉好几秒才铺满
        // （未知态的 z3 全球图尤其明显：第一块 200ms 就出来了，右边几列却在排队）。
        // 提到 4 条，整屏铺满的时间大致减半；对正常态同样是净收益。
        config.tileDownloadThreads = 4
        initialized = true
    }
}
