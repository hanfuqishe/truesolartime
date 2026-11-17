package com.realsuntime.solartime

import android.annotation.SuppressLint
import android.app.Application
import android.location.Location
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.realsuntime.solartime.R
import com.realsuntime.solartime.data.AppSettings
import com.realsuntime.solartime.data.DistrictResolver
import com.realsuntime.solartime.data.LocalZone
import com.realsuntime.solartime.data.LocationTracker
import com.realsuntime.solartime.data.Place
import com.realsuntime.solartime.data.PlaceSource
import com.realsuntime.solartime.data.ThemeMode
import com.realsuntime.solartime.data.WeatherRepository
import com.realsuntime.solartime.map.MapFallbackSession
import com.realsuntime.solartime.map.MapFallbackState
import com.realsuntime.solartime.map.MapStyle
import com.realsuntime.solartime.map.TileEvent
import com.realsuntime.solartime.map.TileResult
import com.realsuntime.solartime.notify.ShiChenReminder
import com.realsuntime.solartime.solar.TimeFormat
import com.realsuntime.solartime.ui.TimeText
import com.realsuntime.solartime.widget.KeyTimeChime
import com.realsuntime.solartime.widget.WidgetUpdater
import kotlinx.coroutines.Dispatchers
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

    /**
     * 底图回退状态（会话级，见 [MapFallbackSession]）。
     *
     * 地图卡片只读它推导「实际用哪个源、缩放要不要降级、要不要显示底图不可用」，
     * 计数与探测都写在这个状态机里，不散落在 Composable 里。
     */
    private val mapFallback = MapFallbackSession.tracker
    val mapFallbackState: StateFlow<MapFallbackState> = mapFallback.state

    private val _keepScreenOn = MutableStateFlow(settings.keepScreenOn)
    val keepScreenOn: StateFlow<Boolean> = _keepScreenOn.asStateFlow()

    private val _themeMode = MutableStateFlow(settings.themeMode)
    val themeMode: StateFlow<ThemeMode> = _themeMode.asStateFlow()

    /** 反查到的行政区划（如「上海市宝山区」）；没有时首页仍显示「当地真太阳时」。 */
    private val _districtName = MutableStateFlow(
        DistrictResolver.cachedNameFor(application, settings.place),
    )
    val districtName: StateFlow<String?> = _districtName.asStateFlow()

    /**
     * 观测点所在地的**标准时区偏移**（秒）：左栏标准时钟与太阳卡片都用它换算。
     *
     * 依赖逆地理带回来的国家码（多时区大国要靠它），所以每一拍都跟着区划缓存一起重读 ——
     * 区划名是后台查回来的，查完这一拍就能切到正确的时区，不用等重启。
     */
    private val _zoneOffsetSeconds = MutableStateFlow(
        LocalZone.offsetSeconds(application, settings.place, Instant.now()),
    )
    val zoneOffsetSeconds: StateFlow<Int> = _zoneOffsetSeconds.asStateFlow()

    private val _message = MutableStateFlow<String?>(null)
    val message: StateFlow<String?> = _message.asStateFlow()

    private var stopTracking: (() -> Unit)? = null
    private var announcedFirstFix = false

    init {
        viewModelScope.launch {
            while (isActive) {
                _now.value = Instant.now()
                // 区县反查在后台跑完会写缓存；这里读的是内存里的 prefs，代价可忽略。
                _districtName.value = DistrictResolver.cachedNameFor(application, _place.value)
                _zoneOffsetSeconds.value = LocalZone.offsetSeconds(application, _place.value, _now.value)
                // 天气心跳：只问「该刷新了吗」，真正的网络请求由 WeatherRepository 的节流决定
                // （低精度前台 60/120/300 秒退避、后台 10 分钟、30 分钟过期、5 分钟失败节流）。
                // 没有这条心跳，低精度的 60 秒轮询只能靠桌面小组件的每分钟刷新来带，没加小组件就永远不升级。
                runCatching { WeatherRepository.requestRefresh(application, _place.value) }
                delay(1_000L - System.currentTimeMillis() % 1_000L)
            }
        }
        // 没加小组件时也要能反查出区划；换了界面语言会重查（见 DistrictResolver.needsRefresh）。
        DistrictResolver.requestRefresh(application, settings.place)
        // 底图回退后的 OSM 探测：回退到高德之后每 5 分钟试一次 OSM（只取一块最低级别的小瓦片）。
        // 放在 IO 线程上，绝不挡 UI；成功即刻切回 OSM 并清零失败计数（见 MapFallbackTracker.probeIfDue）。
        viewModelScope.launch(Dispatchers.IO) {
            while (isActive) {
                runCatching { mapFallback.probeIfDue() }
                delay(MAP_PROBE_TICK_MILLIS)
            }
        }
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
        // 手动坐标与上一个地点毫无关系：先把旧地名清掉，别让上一个城市（预设或上一次反查结果）
        // 在新坐标反查回来之前继续挂在卡片上。反查成功会写入新名字，失败就一直是 null → 显示「-」。
        _districtName.value = null
        // 用户明确指定了新地点：天气与区划名不等 30 分钟窗口，立刻按**新坐标**重取。
        updatePlace(Place(latitude, longitude, PlaceSource.MANUAL, label), userChosen = true)
    }

    /**
     * 选中常用城市。
     *
     * 不能只传经纬度和名字：预设城市自带的 [Place.countryCode] 是**当场**算出标准时区的依据
     * （见 [LocalZone.standardOffsetSeconds]），丢了它就又得等逆地理编码。名字同时写进 label
     * 与 labelResName —— 前者给地图标注用，后者保证换系统语言时跟着变。
     */
    fun usePreset(preset: Place) {
        stopGpsTracking()
        updatePlace(
            preset.copy(source = PlaceSource.MANUAL, label = TimeText.placeLabel(app, preset)),
            userChosen = true,
        )
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
        val previous = _mapStyle.value
        settings.mapStyle = style
        _mapStyle.value = style
        // 「自动 / 手动」是一整套不同的规则：换过就清掉会话里学到的回退记忆，
        // 否则刚在手动高德下看过的失败计数会被带进自动模式（反之亦然）。
        if (style != previous) mapFallback.reset()
    }

    /**
     * 地图瓦片加载结果（自动模式才有意义，手动选择时状态机内部直接忽略）。
     *
     * 三种结果：正常出图、真实失败、以及**高德返回的 200 空白瓦片**（[TileResult.BLANK]）。
     * 空白瓦片按失败处理，走与真实失败同一条降级路径（见 [MapFallback.onTileBlank]）；
     * 失败/回退/降级全程静默：不弹 toast，只写进 [mapFallbackState] 供诊断页展示。
     */
    fun onMapTileEvent(event: TileEvent) {
        val place = _place.value
        val style = _mapStyle.value
        // 瓦片事件里的级别就是地图当下的真实级别：顺便记进诊断，省一次监听。
        mapFallback.onZoomApplied(event.zoom)
        when (event.result) {
            TileResult.LOADED ->
                mapFallback.onTileLoaded(style, place.latitude, place.longitude, event.zoom)

            TileResult.FAILED ->
                mapFallback.onTileFailed(style, place.latitude, place.longitude, event.zoom)

            TileResult.BLANK ->
                mapFallback.onTileBlank(style, place.latitude, place.longitude, event.zoom, event.colorKinds)
        }
    }

    /** 地图上真正生效的缩放级别（被降级链改过时也要如实记下来）。 */
    fun onMapZoomApplied(zoom: Int) {
        mapFallback.onZoomApplied(zoom)
    }

    fun setKeepScreenOn(enabled: Boolean) {
        settings.keepScreenOn = enabled
        _keepScreenOn.value = enabled
    }

    /**
     * 切换配色模式（自动 / 亮色 / 暗色）。
     *
     * 桌面卡片也要立刻跟着换色：它的昼夜配色是每次构建时读同一个设置算的，
     * 所以这里主动重绘一次，用户不用等下一分钟的刷新节拍。
     * 放到后台线程里做 —— 重绘要画时间轴位图，别让点击那一下卡在 UI 线程上
     * （与 WeatherRepository 取到新天气后重绘走同一条路径）。
     */
    fun setThemeMode(mode: ThemeMode) {
        settings.themeMode = mode
        _themeMode.value = mode
        val app = getApplication<Application>()
        Thread { WidgetUpdater.refreshAll(app) }.apply { isDaemon = true }.start()
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
        // 用户重新选了地点：自动模式下的回退记忆跟着地点走 —— 换城市就重新给 OSM 一次机会。
        // GPS 漂移（不是用户选择）不算，否则每分钟的定位刷新都会把回退清掉、白折腾一遍瓦片。
        if (userChosen && _mapStyle.value == MapStyle.AUTO) {
            mapFallback.reset()
        }
        // 换地点后旧区划名立即失效：查不到新名字之前，卡片上不显示城市
        _districtName.value = DistrictResolver.cachedNameFor(getApplication(), place)
        // 换地点后时区可能整个变掉（例如从上海切到纽约），当拍就跟上，不必等下一秒的 tick。
        _zoneOffsetSeconds.value = LocalZone.offsetSeconds(getApplication(), place, Instant.now())

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

        /**
         * OSM 探测的心跳间隔。
         *
         * 「该不该探测」由 [MapFallbackTracker.probeIfDue] 按 5 分钟冷却判断，
         * 这里只是每 30 秒问一次，保证冷却一到就有人去发请求（不多不少）。
         */
        const val MAP_PROBE_TICK_MILLIS = 30_000L
    }
}