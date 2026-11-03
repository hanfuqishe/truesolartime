package com.realsuntime.solartime

import android.annotation.SuppressLint
import android.app.Application
import android.location.Location
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.realsuntime.solartime.data.AppSettings
import com.realsuntime.solartime.data.LocationTracker
import com.realsuntime.solartime.data.Place
import com.realsuntime.solartime.data.PlaceSource
import com.realsuntime.solartime.notify.ShiChenReminder
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.time.Instant

class MainViewModel(application: Application) : AndroidViewModel(application) {

    private val settings = AppSettings(application)
    private val locationTracker = LocationTracker(application)

    private val _now = MutableStateFlow(Instant.now())
    val now: StateFlow<Instant> = _now.asStateFlow()

    private val _place = MutableStateFlow(settings.place)
    val place: StateFlow<Place> = _place.asStateFlow()

    private val _locating = MutableStateFlow(false)
    val locating: StateFlow<Boolean> = _locating.asStateFlow()

    private val _remindersEnabled = MutableStateFlow(settings.remindersEnabled)
    val remindersEnabled: StateFlow<Boolean> = _remindersEnabled.asStateFlow()

    private val _message = MutableStateFlow<String?>(null)
    val message: StateFlow<String?> = _message.asStateFlow()

    private var stopLocation: (() -> Unit)? = null
    private var gpsAttempt = 0

    init {
        viewModelScope.launch {
            while (isActive) {
                _now.value = Instant.now()
                delay(1_000L - System.currentTimeMillis() % 1_000L)
            }
        }
        if (settings.remindersEnabled) {
            ShiChenReminder.schedule(application, settings.place)
        }
    }

    @SuppressLint("MissingPermission")
    fun startGps() {
        if (!locationTracker.hasPermission()) {
            _message.value = "没有定位权限，请授予权限或手动输入经纬度"
            return
        }
        if (_locating.value) return

        val attempt = ++gpsAttempt
        val lastKnown = locationTracker.lastKnownLocation()
        if (lastKnown != null) {
            applyGpsFix(lastKnown)
            return
        }

        _locating.value = true
        stopLocation = locationTracker.start { location ->
            if (attempt == gpsAttempt) {
                applyGpsFix(location)
            }
        }

        viewModelScope.launch {
            delay(LOCATION_TIMEOUT_MILLIS)
            if (attempt == gpsAttempt && _locating.value) {
                stopLocation?.invoke()
                stopLocation = null
                _locating.value = false
                _message.value = "定位超时，请到空旷处重试或手动输入经纬度"
            }
        }
    }

    private fun applyGpsFix(location: Location) {
        stopLocation?.invoke()
        stopLocation = null
        _locating.value = false

        val accuracyText = if (location.hasAccuracy()) "GPS 定位 · 精度 ${location.accuracy.toInt()} 米" else "GPS 定位"
        updatePlace(Place(location.latitude, location.longitude, PlaceSource.GPS, accuracyText))
        _message.value = "已定位到当前位置（${accuracyText}）"
    }

    fun applyManualPlace(latitude: Double, longitude: Double, label: String) {
        gpsAttempt++
        stopLocation?.invoke()
        stopLocation = null
        _locating.value = false
        updatePlace(Place(latitude, longitude, PlaceSource.MANUAL, label))
    }

    fun usePreset(preset: Place) {
        applyManualPlace(preset.latitude, preset.longitude, preset.label)
    }

    fun setRemindersEnabled(enabled: Boolean) {
        _remindersEnabled.value = enabled
        settings.remindersEnabled = enabled
        val app = getApplication<Application>()
        if (enabled) {
            ShiChenReminder.schedule(app, _place.value)
        } else {
            ShiChenReminder.cancel(app)
        }
    }

    fun postMessage(text: String) {
        _message.value = text
    }

    fun consumeMessage() {
        _message.value = null
    }

    private fun updatePlace(place: Place) {
        settings.place = place
        _place.value = place
        if (_remindersEnabled.value) {
            ShiChenReminder.schedule(getApplication(), place)
        }
    }

    override fun onCleared() {
        stopLocation?.invoke()
        stopLocation = null
        super.onCleared()
    }

    private companion object {
        const val LOCATION_TIMEOUT_MILLIS = 20_000L
    }
}
