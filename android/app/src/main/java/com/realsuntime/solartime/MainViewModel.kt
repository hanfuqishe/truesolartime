package com.realsuntime.solartime

import android.annotation.SuppressLint
import android.app.Application
import android.location.Location
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.realsuntime.solartime.R
import com.realsuntime.solartime.data.AppSettings
import com.realsuntime.solartime.data.DistrictResolver
import com.realsuntime.solartime.data.LocationTracker
import com.realsuntime.solartime.data.Place
import com.realsuntime.solartime.data.PlaceSource
import com.realsuntime.solartime.data.WeatherRepository
import com.realsuntime.solartime.map.MapStyle
import com.realsuntime.solartime.notify.ShiChenReminder
import com.realsuntime.solartime.solar.TimeFormat
import com.realsuntime.solartime.widget.KeyTimeChime
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

    private val app: Application = application
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

    private val _keyTimeChimeEnabled = MutableStateFlow(settings.keyTimeChimeEnabled)
    val keyTimeChimeEnabled: StateFlow<Boolean> = _keyTimeChimeEnabled.asStateFlow()

    private val _mapStyle = MutableStateFlow(settings.mapStyle)
    val mapStyle: StateFlow<MapStyle> = _mapStyle.asStateFlow()

    private val _keepScreenOn = MutableStateFlow(settings.keepScreenOn)
    val keepScreenOn: StateFlow<Boolean> = _keepScreenOn.asStateFlow()

    /** 反查到的行政区划（如「上海市宝山区」）；没有时首页仍显示「当地真太阳时」。 */
    private val _districtName = MutableStateFlow(DistrictResolver.cachedName(application))
    val districtName: StateFlow<String?> = _districtName.asStateFlow()

    private val _message = MutableStateFlow<String?>(null)
    val message: StateFlow<String?> = _message.asStateFlow()

    private var stopTracking: (() -> Unit)? = null
    private var announcedFirstFix = false

    init {
        viewModelScope.launch {
            while (isActive) {
                _now.value = Instant.now()
                // 区县反查在后台跑完会写缓存；这里读的是内存里的 prefs，代价可忽略。
                _districtName.value = DistrictResolver.cachedName(application)
                delay(1_000L - System.currentTimeMillis() % 1_000L)
            }
        }
        // 没加小组件时也要能反查出区划；换了界面语言会重查（见 DistrictResolver.needsRefresh）。
        DistrictResolver.requestRefresh(application, settings.place)
        // 打开应用时整体刷一次并重排刷新闹钟：被「强行停止」过的应用其闹钟会被系统清空、
        // 小组件也会被系统屏蔽（桌面显示「加载失败」），打开一次就恢复。
        // 这条路径本来就在主线程跑（广播接收器），这里保持一致，避免踩线程限制。
        val app = application
        viewModelScope.launch {
            runCatching { WidgetUpdater.refreshAll(app, forceChronometer = true) }
        }
        if (settings.remindersEnabled) {
            ShiChenReminder.schedule(application, settings.place)
        }
        if (settings.keyTimeChimeEnabled) {
            KeyTimeChime.schedule(application)
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
            _message.value = app.getString(R.string.msg_location_permission)
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
                _message.value = app.getString(R.string.msg_gps_timeout)
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
        val accuracy = if (location.hasAccuracy()) app.getString(R.string.gps_label_accuracy, location.accuracy.toInt()) else app.getString(R.string.gps_label)
        _waitingForFix.value = false
        updatePlace(Place(location.latitude, location.longitude, PlaceSource.GPS, accuracy))

        if (!announcedFirstFix) {
            announcedFirstFix = true
            val place = _place.value
            _message.value = app.getString(R.string.msg_following_gps, TimeFormat.coordinates(place.latitude, place.longitude))
        }
    }

    fun applyManualPlace(latitude: Double, longitude: Double, label: String) {
        stopGpsTracking()
        // 用户明确指定了新地点：天气与区划名不等 30 分钟窗口，立刻重取。
        updatePlace(Place(latitude, longitude, PlaceSource.MANUAL, label), userChosen = true)
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

    fun setKeepScreenOn(enabled: Boolean) {
        settings.keepScreenOn = enabled
        _keepScreenOn.value = enabled
    }

    fun setKeyTimeChimeEnabled(enabled: Boolean) {
        _keyTimeChimeEnabled.value = enabled
        settings.keyTimeChimeEnabled = enabled
        val app = getApplication<Application>()
        if (enabled) {
            KeyTimeChime.schedule(app)
        } else {
            KeyTimeChime.cancel(app)
        }
    }

    fun postMessage(text: String) {
        _message.value = text
    }

    fun consumeMessage() {
        _message.value = null
    }

    private fun updatePlace(place: Place, userChosen: Boolean = false) {
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
        if (_keyTimeChimeEnabled.value && changed) {
            KeyTimeChime.schedule(app)
        }
        if (userChosen) {
            // 手工换地点后缓存里的天气属于旧坐标：不等 30 分钟窗口，立刻取一次新的。
            WeatherRepository.requestRefresh(app, place, force = true)
            DistrictResolver.requestRefresh(app, place)
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