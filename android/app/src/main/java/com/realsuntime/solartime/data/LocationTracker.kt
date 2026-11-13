package com.realsuntime.solartime.data

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat

/** 基于系统 LocationManager 的定位，不依赖 Google Play 服务。 */
class LocationTracker(context: Context) {

    private val appContext = context.applicationContext
    private val manager = appContext.getSystemService(Context.LOCATION_SERVICE) as LocationManager

    fun hasPermission(): Boolean =
        ContextCompat.checkSelfPermission(appContext, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
            ContextCompat.checkSelfPermission(appContext, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED

    // 调用前已通过 hasPermission() 校验，并在 runCatching 中兜底 SecurityException。
    @SuppressLint("MissingPermission")
    fun lastKnownLocation(): Location? {
        if (!hasPermission()) return null
        return activeProviders()
            .mapNotNull { provider -> runCatching { manager.getLastKnownLocation(provider) }.getOrNull() }
            .maxByOrNull { it.time }
    }

    /**
     * 持续监听定位，按 [intervalMillis] 间隔回调，返回取消函数。
     *
     * minTime 只是下限，实际回调频率由系统决定；信号变化时可能更频繁。
     */
    @SuppressLint("MissingPermission")
    fun startTracking(intervalMillis: Long, onLocation: (Location) -> Unit): () -> Unit {
        if (!hasPermission()) return {}

        val listener = object : LocationListener {
            override fun onLocationChanged(location: Location) = onLocation(location)
        }
        val providers = activeProviders()
        providers.forEach { provider ->
            runCatching {
                manager.requestLocationUpdates(provider, intervalMillis, 0f, listener, Looper.getMainLooper())
            }
        }

        return {
            providers.forEach { provider ->
                runCatching { manager.removeUpdates(listener) }
            }
        }
    }

    /**
     * 取一次定位就停：桌面卡片在后台用这个（进程随时可能被回收，不能常驻监听）。
     *
     * @param timeoutMillis 超时后自动摘掉监听，避免进程里残留定位请求
     * @return 取消函数
     */
    @SuppressLint("MissingPermission")
    fun requestSingleFix(timeoutMillis: Long = 20_000L, onFix: (Location) -> Unit): () -> Unit {
        if (!hasPermission()) return {}

        val handler = Handler(Looper.getMainLooper())
        var done = false
        lateinit var stop: () -> Unit
        val listener = object : LocationListener {
            override fun onLocationChanged(location: Location) {
                if (done) return
                done = true
                stop()
                onFix(location)
            }
        }
        val providers = activeProviders()
        providers.forEach { provider ->
            runCatching { manager.requestLocationUpdates(provider, 0L, 0f, listener, Looper.getMainLooper()) }
        }
        stop = {
            handler.removeCallbacksAndMessages(null)
            providers.forEach { provider -> runCatching { manager.removeUpdates(listener) } }
        }
        if (providers.isNotEmpty()) {
            handler.postDelayed({ if (!done) { done = true; stop() } }, timeoutMillis)
        }
        return stop
    }

    private fun activeProviders(): List<String> =
        listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER, LocationManager.PASSIVE_PROVIDER)
            .filter { provider ->
                runCatching { manager.isProviderEnabled(provider) }.getOrDefault(false)
            }
}