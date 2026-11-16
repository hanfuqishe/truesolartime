package com.realsuntime.solartime

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.realsuntime.solartime.data.AppSettings
import com.realsuntime.solartime.data.MapConfig
import com.realsuntime.solartime.data.WeatherRepository
import com.realsuntime.solartime.ui.MainScreen

class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        MapConfig.init(this)
        enableEdgeToEdge()
        // 主题由 MainScreen 按「白天／夜间」与设置里的主题选项选（见 TrueSolarTimeTheme 调用处）。
        setContent {
            MainScreen()
        }
    }

    /**
     * 回到前台时补一次「低精度升级」尝试。
     *
     * 当前若是备用源 7Timer! 的 3 小时粒度数据，即使还没到 30 分钟，也值得立刻问一次主源
     * —— 用户刚从后台切回来，正是他最容易盯着卡片看的时候。
     * 这条路径**不受「低精度最多每 10 分钟一次」的节流限制**（那条限制是给每分钟的自动刷新用的）；
     * 但新鲜的主源数据仍不会白打一次网络（[WeatherRepository.requestRefresh] 内部还有过期判定）。
     */
    override fun onResume() {
        super.onResume()
        val app = applicationContext
        runCatching {
            WeatherRepository.requestRefresh(
                app,
                AppSettings(app).place,
                ignoreLowPrecisionThrottle = true,
            )
        }
    }
}
