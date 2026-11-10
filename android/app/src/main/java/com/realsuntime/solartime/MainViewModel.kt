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
import com.realsuntime.solartime.map.MapStyle
import com.realsuntime.solartime.notify.ShiChenReminder
import com.realsuntime.solartime.solar.TimeFormat
import com.realsuntime.solartime.widget.HourlyChime
import com.realsuntime.solartime.widget.WidgetUpdater
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.time.Instant
import kotlin.math.abs

class MainViewModel(application: Application) : AndroidViewModel(application) {

    private val settings = AppSettings(application)
    private val locationTracker = LocationTracker(application)

    private val _now = MutableStateFlow(Instant.now())
    val now: StateFlow<Instant> = _now.asStateFlow()

    private val _place = MutableStateFlow(settings.place)
    val place: StateFlow<Place> = _place.asStateFlow()

    /** 正在跟随 GPS（每分钟采样一次）。 */
    private val _trackingGps = MutableStateFlow(false)
    val trackingGps: StateFlow<Boolean> = _trackingGps.asStateFlow()

    /** 已开始跟随但还没收到任何定位结果。 */
    private val _waitingForFix = MutableStateFlow(false)
    val waitingForFix: StateFlow<Boolean> = _waitingForFix.asStateFlow()

    private val _remindersEnabled = MutableStateFlow(settings.remindersEnabled)
    val remindersEnabled: StateFlow<Boolean> = _remindersEnabled.asStateFlow()

    private val _hourlyChimeEnabled = MutableStateFlow(settings.hourlyChimeEnabled)
    val hourlyChimeEnabled: StateFlow<Boolean> = _hourlyChimeEnabled.asStateFlow()

    private val _mapStyle = MutableStateFlow(settings.mapStyle)
    val mapStyle: StateFlow<MapStyle> = _mapStyle.asStateFlow()

    private val _message = MutableStateFlow<String?>(null)
    val message: StateFlow<String?> = _message.asStateFlow()

    private var stopTracking: (() -> Unit)? = null
    private var announcedFirstFix = false

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
        if (settings.hourlyChimeEnabled) {
            HourlyChime.schedule(application, settings.place)
        }
        // 默认跟随 GPS；用户手动指定过位置时保持手动。
        if (locationTracker.hasPermission() && settings.place.source != PlaceSource.MANUAL) {
            startGpsTracking(announce = false)
        }
    }

    fun shouldRequestLocationPermission(): Boolean =
        !locationTracker.hasPermission() && !settings.locationPermissionRequested

    fun markLocationPermissionRequested() {
        settings.locationPermissionRequested = true
    }

    @SuppressLint("MissingPermission")
    fun startGpsTracking(announce: Boolean = true) {
        if (!locationTracker.hasPermission()) {
            _message.value = "没有定位权限，请授予权限或手动输入经纬度"
            return
        }

        stopTracking?.invoke()
        stopTracking = null
        announcedFirstFix = !announce

        locationTracker.lastKnownLocation()?.let { applyFix(it) }
        _waitingForFix.value = _place.value.source != PlaceSource.GPS
        _trackingGps.value = true

        stopTracking = locationTracker.startTracking(GPS_INTERVAL_MILLIS) { location -> applyFix(location) }

        viewModelScope.launch {
            delay(FIX_TIMEOUT_MILLIS)
            if (_waitingForFix.value && _trackingGps.value) {
                _message.value = "尚未收到 GPS 信号，可能需要在空旷处等待；也可手动设置经纬度"
            }
        }
    }

    fun stopGpsTracking() {
        stopTracking?.invoke()
        stopTracking = null
        _trackingGps.value = false
        _waitingForFix.value = false
    }

    private fun applyFix(location: Location) {
        val accuracy = if (location.hasAccuracy()) "精度 ${location.accuracy.toInt()} 米" else "精度未知"
        _waitingForFix.value = false
        updatePlace(Place(location.latitude, location.longitude, PlaceSource.GPS, "GPS · $accuracy"))

        if (!announcedFirstFix) {
            announcedFirstFix = true
            val place = _place.value
            _message.value = "已跟随 GPS 定位（${TimeFormat.coordinates(place.latitude, place.longitude)}），每分钟更新"
        }
    }

    fun applyManualPlace(latitude: Double, longitude: Double, label: String) {
        stopGpsTracking()
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

    fun setMapStyle(style: MapStyle) {
        settings.mapStyle = style
        _mapStyle.value = style
    }

    fun setHourlyChimeEnabled(enabled: Boolean) {
        _hourlyChimeEnabled.value = enabled
        settings.hourlyChimeEnabled = enabled
        val app = getApplication<Application>()
        if (enabled) {
            HourlyChime.schedule(app, _place.value)
        } else {
            HourlyChime.cancel(app)
        }
    }

    fun postMessage(text: String) {
        _message.value = text
    }

    fun consumeMessage() {
        _message.value = null
    }

    private fun updatePlace(place: Place) {
        val previous = _place.value
        settings.place = place
        _place.value = place

        val app = getApplication<Application>()
        val moved = abs(place.longitude - previous.longitude) > REMINDER_RESCHEDULE_DEGREES ||
            abs(place.latitude - previous.latitude) > REMINDER_RESCHEDULE_DEGREES
        val changed = moved || previous.source != place.source
        if (_remindersEnabled.value && changed) {
            ShiChenReminder.schedule(app, place)
        }
        if (_hourlyChimeEnabled.value && changed) {
            HourlyChime.schedule(app, place)
        }
        if (changed) {
            WidgetUpdater.refreshAll(app)
        }
    }

    override fun onCleared() {
        stopGpsTracking()
        super.onCleared()
    }

    private companion object {
        /** GPS 采样间隔：每分钟一次。 */
        const val GPS_INTERVAL_MILLIS = 60_000L
        const val FIX_TIMEOUT_MILLIS = 20_000L

        /** 位置变化超过该幅度才重排提醒，避免每分钟都重设闹钟。 */
        const val REMINDER_RESCHEDULE_DEGREES = 0.01
    }
}