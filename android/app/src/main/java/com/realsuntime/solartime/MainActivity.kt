package com.realsuntime.solartime

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.realsuntime.solartime.data.MapConfig
import com.realsuntime.solartime.ui.MainScreen

class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        MapConfig.init(this)
        enableEdgeToEdge()
        // 主题由 MainScreen 按「白天／夜间」选（见 TrueSolarTimeTheme 调用处）。
        setContent {
            MainScreen()
        }
    }
}
