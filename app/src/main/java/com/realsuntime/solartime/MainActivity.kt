package com.realsuntime.solartime

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.realsuntime.solartime.data.MapConfig
import com.realsuntime.solartime.ui.MainScreen
import com.realsuntime.solartime.ui.theme.TrueSolarTimeTheme

class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        MapConfig.init(this)
        enableEdgeToEdge()
        setContent {
            TrueSolarTimeTheme {
                MainScreen()
            }
        }
    }
}
