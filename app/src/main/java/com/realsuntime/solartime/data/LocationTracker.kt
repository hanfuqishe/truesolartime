package com.realsuntime.solartime.data

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
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

    /** 开始监听定位，返回取消函数。 */
    @SuppressLint("MissingPermission")
    fun start(onLocation: (Location) -> Unit): () -> Unit {
        if (!hasPermission()) return {}

        val listener = object : LocationListener {
            override fun onLocationChanged(location: Location) = onLocation(location)
        }
        val providers = activeProviders()
        providers.forEach { provider ->
            runCatching { manager.requestLocationUpdates(provider, 1_000L, 0f, listener, Looper.getMainLooper()) }
        }

        return {
            providers.forEach { provider ->
                runCatching { manager.removeUpdates(listener) }
            }
        }
    }

    private fun activeProviders(): List<String> =
        listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER, LocationManager.PASSIVE_PROVIDER)
            .filter { provider ->
                runCatching { manager.isProviderEnabled(provider) }.getOrDefault(false)
            }
}
