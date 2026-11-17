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
     * 进程进入前台：低精度数据从此按 60/120/300 秒的退避重试主源（后台是 10 分钟）。
     * 只置一个标志，真正的刷新由 [onResume] 立刻触发一次。
     */
    override fun onStart() {
        super.onStart()
        WeatherRepository.setForeground(true)
    }

    /** 进程退到后台（或只剩小组件在跑）：低精度重试降到 10 分钟一次。 */
    override fun onStop() {
        WeatherRepository.setForeground(false)
        super.onStop()
    }

    /**
     * 回到前台时补一次「低精度升级」尝试。
     *
     * 当前若是备用源 7Timer! 的 3 小时粒度数据，即使还没到 30 分钟、也没到退避时间，也值得
     * 立刻问一次主源 —— 用户刚从后台切回来，正是他最容易盯着卡片看的时候。
     * 这条路径**不受前台退避阶梯（60/120/300 秒）与后台 10 分钟的限制**；
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
