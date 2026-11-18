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
import com.realsuntime.solartime.data.LocationAvailability
import com.realsuntime.solartime.data.LocationTracker
import com.realsuntime.solartime.data.Place
import com.realsuntime.solartime.data.PlaceSource
import com.realsuntime.solartime.data.ThemeMode
import com.realsuntime.solartime.data.WeatherRepository
import com.realsuntime.solartime.map.BasemapProbe
import com.realsuntime.solartime.map.BasemapProbeRunner
import com.realsuntime.solartime.map.MapFallbackSession
import com.realsuntime.solartime.map.MapFallbackState
import com.realsuntime.solartime.map.MapStyle
import com.realsuntime.solartime.map.MapUiState
import com.realsuntime.solartime.map.TileEvent
import com.realsuntime.solartime.map.TileResult
import com.realsuntime.solartime.map.UnknownBasemap
import com.realsuntime.solartime.map.UnknownBasemapProbeRunner
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
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
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

    /**
     * 用户是否处于「跟随 GPS」：记的是**意图**（点过「实时跟随 GPS」或默认跟随），
     * 不等于「已经拿到定位」。手动选城市 / 输入经纬度后置 false（见 [stopFollowingGps]）。
     */
    private val _followGps = MutableStateFlow(settings.followGps)
    val followGps: StateFlow<Boolean> = _followGps.asStateFlow()

    /** 本次跟随会话里是否已有可信定位（新 fix，或刚启动时手上那个上一次的 GPS 地点）。 */
    private val _hasFix = MutableStateFlow(false)

    /**
     * **定位不可用（未知态）**：跟随 GPS 却拿不到有效定位（未授权，或授权后等不到 fix）。
     *
     * 界面据此把太阳相关的读数全部换成占位符、标准时间改用系统时区、地图缩到全球底图 ——
     * 绝不沿用上一个地点的坐标假装「定位到了那里」（判定本身在 `LocationAvailability`）。
     */
    private val _locationUnknown = MutableStateFlow(false)
    val locationUnknown: StateFlow<Boolean> = _locationUnknown.asStateFlow()

    /** 重新推导未知态；[followGps] / [hasFix] 一变就必须调它。 */
    private fun refreshLocationUnknown() {
        _locationUnknown.value = LocationAvailability.isUnknown(_followGps.value, _hasFix.value)
    }

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
    /** 会话原始状态：只给诊断/排查用，**不要**拿它驱动 Compose（见下面的 [mapUi]）。 */
    val mapFallbackState: StateFlow<MapFallbackState> = mapFallback.state

    /**
     * 地图卡片**唯一**应该观察的状态：只有「换源 / 换级别 / 是否降级 / 是否底图不可用」这几件事变了才发。
     *
     * `mapFallbackState` 里的失败计数、空白计数每来一块瓦片都在变，直接拿去驱动 Compose 就是
     * 「每块瓦片重组一次」——真机上表现为地图狂闪（实测 2 秒 441 次状态发布、缩放 3↔12↔11↔10 狂跳）。
     * 这里用 [MapUiState.of] 把状态压成「有效 plan」，再由 `distinctUntilChanged` 卡住。
     */
    private val _mapUi = MutableStateFlow(
        MapUiState.of(settings.mapStyle, settings.place.latitude, settings.place.longitude, mapFallback.snapshot()),
    )
    val mapUi: StateFlow<MapUiState> = _mapUi.asStateFlow()

    /**
     * 地图还没出图（切城市 / 换源 / 首屏探测期间）：地图区域立刻显示「正在载入底图…」，
     * 第一块瓦片画出来（或判定「底图不可用」）就收起来。
     *
     * 与 [mapUi] 分开是因为它的变化节奏不同：它只在「开始等」和「等到了」这两个时刻各变一次。
     */
    private val _mapLoading = MutableStateFlow(true)
    val mapLoading: StateFlow<Boolean> = _mapLoading.asStateFlow()

    /**
     * 地图「可以出场了」：境外要等并行探测有结论再建 MapView。
     *
     * 为什么要等：MapView 一旦用错的源/级别建出来，随后切源 + 改级别会清空瓦片缓存、取消在飞请求，
     * osmdroid 在新队列上不一定马上重发（真机实测：一直停在加载态，手指划一下地图才出图）。
     * 让 MapView 一出生就是探测选定的源 + 级别，首屏既快又稳。
     */
    private val _mapReady = MutableStateFlow(true)
    val mapReady: StateFlow<Boolean> = _mapReady.asStateFlow()

    /** 首屏并行探测的任务（换城市就取消上一次，避免旧结论盖掉新地点）。 */
    private var probeJob: kotlinx.coroutines.Job? = null

    /**
     * **未知态**全球底图快路径（见 [UnknownBasemap]）：选定的源；null = 还没结论。
     *
     * 与正常态的 [mapFallback] 状态机完全独立：这里只关心「一张 z3 全球图用哪个源」，
     * 不参与「OSM 连续失败回退 / 逐级降级 / 5 分钟冷却回弹」那一整套。
     */
    private val _unknownMapSource = MutableStateFlow(
        UnknownBasemap.cachedSource(
            source = settings.unknownMapSource,
            atMillis = settings.unknownMapSourceAtMillis,
            nowMillis = System.currentTimeMillis(),
        ),
    )
    val unknownMapSource: StateFlow<MapStyle?> = _unknownMapSource.asStateFlow()

    /** 未知态两块探测瓦片都没内容 → 地图卡直接显示「底图不可用」（不降级）。 */
    private val _unknownMapUnavailable = MutableStateFlow(false)
    val unknownMapUnavailable: StateFlow<Boolean> = _unknownMapUnavailable.asStateFlow()

    /** 未知态探测任务（同一时刻只跑一次）。 */
    private var unknownProbeJob: kotlinx.coroutines.Job? = null

    /**
     * 「进入未知态」的时刻（[android.os.SystemClock.elapsedRealtime]）：用来量**切到未知态 → 地图出图**
     * 到底花了多久（目标 ≤5 秒）。只打一条 info 日志，排查「地图多久才出来」时直接看 logcat。
     */
    private var unknownMapEnteredAtMillis = 0L
    private var unknownMapReadyLogged = false

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

    /**
     * 本次跟随会话里是否收到过**新的**定位（区别于启动时沿用上一次会话的 GPS 地点）。
     *
     * 看门狗据此判断「授权了但一直拿不到 fix」：只有旧地点、没有新 fix 时，20 秒后进未知态。
     */
    private var liveFixReceived = false

    /** 跟随会话序号：旧的看门狗到点时若会话已经换了，直接作废（不要拿上一轮的超时判新会话）。 */
    private var trackingSession = 0

    /**
     * 手上那个「上一次的 GPS 地点」还值不值得当定位用。
     *
     * 一旦看门狗判过「等不到新 fix」，它就**不再**被当成定位（否则每次回到前台都会先演 20 秒
     * 旧城市、再退回未知态）；真拿到新 fix 时由 [applyFix] 重新置 true。
     */
    private var storedPlaceTrusted = true

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
                // 未知态没有坐标：不拿上一个地点的坐标去刷天气（那正是要避免的「假装定位到了那里」）。
                if (!_locationUnknown.value) {
                    runCatching { WeatherRepository.requestRefresh(application, _place.value) }
                }
                delay(1_000L - System.currentTimeMillis() % 1_000L)
            }
        }
        // 没加小组件时也要能反查出区划；换了界面语言会重查（见 DistrictResolver.needsRefresh）。
        DistrictResolver.requestRefresh(application, settings.place)
        // 底图回退后的 OSM 探测：回退到高德之后每 5 分钟试一次 OSM（只取一块最低级别的小瓦片）。
        // 放在 IO 线程上，绝不挡 UI；成功即刻切回 OSM 并清零失败计数（见 MapFallbackTracker.probeIfDue）。
        // 顺带负责「首屏并行探测」的 5 分钟重探：结论过期（或上次判了「不可用」）就重新探一次。
        viewModelScope.launch(Dispatchers.IO) {
            while (isActive) {
                runCatching { mapFallback.probeIfDue() }
                runCatching { maybeProbeBasemap() }
                delay(MAP_PROBE_TICK_MILLIS)
            }
        }
        // 地图卡片的 UI 状态：把「会话状态 + 地点 + 设置」压成 MapUiState，只在其真的变化时才发。
        // 未知态走自己的快路径（见 [UnknownBasemap]）：源由「上次成功出图的源」缓存或两块瓦片探测决定，
        // 级别固定 z3；它**不读** [mapFallback] 的失败/回退/冷却状态，也不写它。
        viewModelScope.launch {
            val unknownMap = combine(_unknownMapSource, _unknownMapUnavailable) { source, unavailable ->
                source to unavailable
            }
            combine(mapFallback.state, _place, _mapStyle, _locationUnknown, unknownMap) { state, place, style, unknown, unknownState ->
                if (unknown) {
                    MapUiState.ofUnknown(style, unknownState.first, unknownState.second)
                } else {
                    MapUiState.of(style, place.latitude, place.longitude, state)
                }
            }.distinctUntilChanged().collect {
                _mapUi.value = it
                if (it.unavailable) _mapLoading.value = false // 「底图不可用」也是一种结论，别一直转圈
            }
        }
        // 未知态的全球底图快路径：进入未知态就立刻「有缓存直接用 / 没缓存探两块 z3（≤2 秒）」。
        viewModelScope.launch {
            _locationUnknown.collect { unknown ->
                if (unknown) enterUnknownBasemap() else leaveUnknownBasemap()
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
        // 「跟随 GPS」是**意图**：没授权 / 等不到 fix 时它就是未知态的依据，所以先记下来再决定要不要开监听。
        _followGps.value = settings.followGps && LocationAvailability.followsGps(settings.place.source)
        if (locationTracker.hasPermission() && _followGps.value) {
            startGpsTracking(announce = false)
        } else {
            // 没权限（或本来就是手动地点）：不装监听；跟随 GPS 时立刻进未知态，别拿上一个地点顶替。
            _hasFix.value = false
            refreshLocationUnknown()
        }
    }

    fun shouldRequestLocationPermission(): Boolean =
        !locationTracker.hasPermission() && !settings.locationPermissionRequested

    fun markLocationPermissionRequested() {
        settings.locationPermissionRequested = true
    }

    /**
     * 进入未知态：给那张全球底图定源（专用快路径，见 [UnknownBasemap]）。
     *
     * 1. **有「上次成功出图的源」缓存**（10 分钟内）→ 直接用它 + z3，一次请求都不发；
     * 2. **没有缓存** → 只并行探两块 z3 瓦片（OSM / 高德，各几 KB），2 秒封顶，先有内容者胜；
     * 3. **两块都失败** → 「底图不可用」（未知态只在 z3，没有级别可降、也不进回退/冷却那套）。
     *
     * 探测期间不建 MapView（界面显示骨架），MapView 一出生就是选定的源 + z3。
     */
    private fun enterUnknownBasemap() {
        unknownMapEnteredAtMillis = android.os.SystemClock.elapsedRealtime()
        unknownMapReadyLogged = false
        val cached = UnknownBasemap.cachedSource(
            source = settings.unknownMapSource,
            atMillis = settings.unknownMapSourceAtMillis,
            nowMillis = System.currentTimeMillis(),
        )
        if (cached != null) {
            _unknownMapSource.value = cached
            _unknownMapUnavailable.value = false
            _mapReady.value = true
            return
        }
        if (unknownProbeJob?.isActive == true) return
        _unknownMapSource.value = null
        _unknownMapUnavailable.value = false
        _mapReady.value = false
        unknownProbeJob = viewModelScope.launch(Dispatchers.IO) {
            val result = runCatching { UnknownBasemapProbeRunner.probe() }.getOrNull()
            val source = result?.source
            if (source != null) {
                // 记下「上次成功出图的源 + 时间」：下次进未知态直接命中，不再探测。
                settings.unknownMapSource = source
                settings.unknownMapSourceAtMillis = System.currentTimeMillis()
                _unknownMapSource.value = source
                _unknownMapUnavailable.value = false
                _mapReady.value = true
                android.util.Log.i(MAP_LOG_TAG, "unknown basemap probe: ${result.detail} → $source")
            } else {
                // 两块都没内容：直接显示「底图不可用」，不降级、也不去建 MapView。
                _unknownMapUnavailable.value = true
                _mapReady.value = false
                android.util.Log.i(
                    MAP_LOG_TAG,
                    "unknown basemap probe: ${result?.detail ?: "探测异常"} → 底图不可用",
                )
            }
        }
    }

    /** 离开未知态：只收掉还在飞的探测；缓存留着（下次进未知态直接用），正常态的判断照旧。 */
    private fun leaveUnknownBasemap() {
        unknownProbeJob?.cancel()
        unknownProbeJob = null
    }

    @SuppressLint("MissingPermission")
    fun startGpsTracking(announce: Boolean = true) {
        // 点「实时跟随 GPS」就是明确的跟随意图：即便这次拿不到定位，也要记下来（未知态据此判定）。
        _followGps.value = true
        settings.followGps = true
        if (!locationTracker.hasPermission()) {
            // 没权限 = 不可能拿到定位：立刻进未知态，把上一个地点的太阳数据收起来。
            stopTracking?.invoke()
            stopTracking = null
            _trackingGps.value = false
            _waitingForFix.value = false
            _hasFix.value = false
            refreshLocationUnknown()
            _message.value = app.getString(R.string.msg_location_permission)
            return
        }

        stopTracking?.invoke()
        stopTracking = null
        announcedFirstFix = !announce
        liveFixReceived = false
        // 用户主动点了「实时跟随 GPS」：重新给系统缓存里那次定位一次机会（他想再看一次结果）。
        if (announce) storedPlaceTrusted = true

        val lastKnown = locationTracker.lastKnownLocation()
        when {
            // 系统缓存里那次定位：正常启动时先拿来顶着（不在冷启动阶段闪占位符）；
            // 但看门狗已经判过「等不到 fix」之后就不再采信 —— 它和手上那个旧地点是同一份缓存，
            // 再信一次会让「回到前台 → 演 20 秒旧城市 → 又变未知」来回跳。
            lastKnown != null && storedPlaceTrusted -> applyFix(lastKnown)
            // 手上原本就是 GPS 地点（上一次会话留下的已知位置）：先当「有定位」，别一启动就闪占位符；
            // 它只是**过渡**，看门狗到点还没有新 fix 就会进未知态（见下面的 20 秒协程）。
            _place.value.source == PlaceSource.GPS && storedPlaceTrusted -> _hasFix.value = true
            // 默认坐标 / 预设城市 / 手动坐标：没有任何定位依据 → 未知态。
            else -> _hasFix.value = false
        }
        _waitingForFix.value = _place.value.source != PlaceSource.GPS
        _trackingGps.value = true
        refreshLocationUnknown()

        stopTracking = locationTracker.startTracking(GPS_INTERVAL_MILLIS) { location -> applyFix(location) }

        // 看门狗：20 秒还没等到**新的** fix，就承认「定位不可用」——
        // 授权了却一直拿不到 fix（室内、遮挡、定位服务异常）同样属于未知态，
        // 不能拿上一次会话的旧坐标一直演下去；真拿到 fix 时 [applyFix] 会立刻恢复显示。
        val session = ++trackingSession
        viewModelScope.launch {
            delay(FIX_TIMEOUT_MILLIS)
            if (session != trackingSession || !_trackingGps.value) return@launch
            if (_waitingForFix.value) _message.value = app.getString(R.string.msg_gps_timeout)
            if (!liveFixReceived) {
                // 旧坐标不再可信：以后每次回到前台都直接进未知态，不要再演一遍旧城市。
                storedPlaceTrusted = false
                _hasFix.value = false
                refreshLocationUnknown()
            }
        }
    }

    fun stopGpsTracking() {
        stopTracking?.invoke()
        stopTracking = null
        _trackingGps.value = false
        _waitingForFix.value = false
    }

    /**
     * 点了「实时跟随 GPS」但当前**没有定位权限**（权限弹窗由界面去要）。
     *
     * 记下跟随意图并立刻进未知态：用户明明说了要跟随定位，界面就不能继续显示上一个地点。
     * 授权成功后走 [startGpsTracking]，拿到 fix 即刻恢复正常显示。
     */
    fun beginGpsFollowingWithoutPermission() {
        _followGps.value = true
        settings.followGps = true
        stopTracking?.invoke()
        stopTracking = null
        _trackingGps.value = false
        _waitingForFix.value = false
        _hasFix.value = false
        liveFixReceived = false
        refreshLocationUnknown()
    }

    /**
     * 用户改成了手动指定位置（预设城市 / 手动坐标）：跟随 GPS 的意图随之结束，
     * 未知态立刻解除（[LocationAvailability.isUnknown] 见到 followGps=false 就返回 false）。
     */
    private fun stopFollowingGps() {
        _followGps.value = false
        settings.followGps = false
        _hasFix.value = true
        refreshLocationUnknown()
    }

    /**
     * 回到前台（例如用户刚从系统设置里改完定位权限）：重新核对「跟随 GPS + 有没有定位」。
     *
     * 授权被撤销 → 立刻进未知态（别继续显示旧地点）；授权被补上 → 重新开监听等 fix。
     */
    fun syncLocationState() {
        if (!_followGps.value) return
        if (!locationTracker.hasPermission()) {
            _hasFix.value = false
            refreshLocationUnknown()
            // 还在未知态、而上次两块探测瓦片都没探到（源还是空的）：回前台时重试一次快路径。
            if (_locationUnknown.value && _unknownMapSource.value == null) enterUnknownBasemap()
            return
        }
        if (!_hasFix.value) startGpsTracking(announce = false)
    }

    private fun applyFix(location: Location) {
        val accuracy = if (location.hasAccuracy()) app.getString(R.string.gps_label_accuracy, location.accuracy.toInt()) else app.getString(R.string.gps_label)
        _waitingForFix.value = false
        // 拿到真实定位：未知态立刻解除（所有占位符随之换回真实读数）。
        liveFixReceived = true
        storedPlaceTrusted = true
        _hasFix.value = true
        _followGps.value = true
        updatePlace(Place(location.latitude, location.longitude, PlaceSource.GPS, accuracy))
        refreshLocationUnknown()

        if (!announcedFirstFix) {
            announcedFirstFix = true
            val place = _place.value
            _message.value = app.getString(R.string.msg_following_gps, TimeFormat.coordinates(place.latitude, place.longitude))
        }
    }

    fun applyManualPlace(latitude: Double, longitude: Double, label: String) {
        stopGpsTracking()
        stopFollowingGps()
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
        stopFollowingGps()
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
        if (style != previous) {
            mapFallback.reset()
            startLoading()
            _mapReady.value = !BasemapProbe.needsProbe(style, _place.value.latitude, _place.value.longitude)
            // 切回自动 = 重新给探测一次机会（用户明确换了模式，别拿旧结论糊弄他）。
            maybeProbeBasemap(force = true)
        }
    }

    /**
     * 地图瓦片加载结果（自动模式才有意义，手动选择时状态机内部直接忽略）。
     *
     * 三种结果：正常出图、真实失败、以及**高德返回的 200 空白瓦片**（[TileResult.BLANK]）。
     * 空白瓦片按失败处理，走与真实失败同一条降级路径（见 [MapFallback.onTileBlank]）；
     * 失败/回退/降级全程静默：不弹 toast，只写进 [mapFallbackState] 供诊断页展示。
     */
    fun onMapTileEvent(event: TileEvent) {
        // 未知态走专用快路径：源已经定好、级别固定 z3，瓦片成败不进正常态那套统计/降级/回弹。
        if (_locationUnknown.value) {
            if (event.result == TileResult.LOADED) {
                _mapLoading.value = false
                if (!unknownMapReadyLogged && unknownMapEnteredAtMillis > 0L) {
                    unknownMapReadyLogged = true
                    val cost = android.os.SystemClock.elapsedRealtime() - unknownMapEnteredAtMillis
                    android.util.Log.i(MAP_LOG_TAG, "unknown basemap: 首块瓦片已画出（进入未知态后 ${cost}ms）")
                }
            }
            return
        }
        val style = _mapStyle.value
        val (latitude, longitude) = mapAnchor()
        // 有瓦片画出来了：收起「正在载入底图…」。
        if (event.result == TileResult.LOADED) _mapLoading.value = false
        // 只记诊断用的「当下级别」，**不**开「刚改过视口」的残响窗口：
        // 瓦片事件是结果不是原因，拿它当视口变化会把窗口无限续期，真失败就再也数不到了。
        mapFallback.noteTileZoom(event.zoom)
        when (event.result) {
            TileResult.LOADED ->
                mapFallback.onTileLoaded(style, latitude, longitude, event.zoom)

            TileResult.FAILED ->
                mapFallback.onTileFailed(style, latitude, longitude, event.zoom)

            TileResult.BLANK ->
                mapFallback.onTileBlank(style, latitude, longitude, event.zoom, event.colorKinds)
        }
    }

    /** 地图卡片「程序化应用完视口」：记级别 + 打开残响窗口（见 [MapFallbackTracker.onZoomApplied]）。 */
    fun onMapZoomApplied(zoom: Int) {
        // 未知态的视口（z3 全球图）不属于正常态的降级链，别去动那套「刚改过视口」的计时。
        if (_locationUnknown.value) return
        mapFallback.onZoomApplied(zoom)
    }

    /**
     * 地图的坐标锚点：未知态没有坐标，一律用 (0, 0)（境外口径 → OSM + 高德兜底），
     * 免得底图的源/级别还按**上一个地点**在境内外的判断走。
     */
    private fun mapAnchor(): Pair<Double, Double> =
        if (_locationUnknown.value) {
            MapUiState.UNKNOWN_LATITUDE to MapUiState.UNKNOWN_LONGITUDE
        } else {
            _place.value.latitude to _place.value.longitude
        }

    /** 这一级是否已被判「没内容/没瓦片」（空白检测的定时重扫据此跳过已经判过的级别）。 */
    fun isMapZoomUnavailable(zoom: Int): Boolean {
        val (latitude, longitude) = mapAnchor()
        val state = mapFallback.snapshot()
        val plan = com.realsuntime.solartime.map.MapFallback.plan(
            _mapStyle.value,
            latitude,
            longitude,
            state,
        )
        return state.zoomUnavailable(plan.effective, zoom)
    }

    /** 地图「还没出图」：切城市/换源后立刻置 true，第一块瓦片出来（或判定不可用）后置 false。 */
    private fun startLoading() {
        _mapLoading.value = true
    }

    /**
     * 首屏并行探测（见 [BasemapProbe]）：境外（自动 + 首选 OSM）时并发取 4 块单瓦片，
     * 用「有内容的最高精度」直接定源与级别，避免串行等三次超时 + 逐级降级。
     *
     * 缓存：同地点 + 5 分钟内只探一次（[MapFallbackState.probeKey]）。
     * 境内（首选高德）与手动选择都不探测。
     */
    private fun maybeProbeBasemap(force: Boolean = false) {
        val place = _place.value
        val style = _mapStyle.value
        // 未知态没有坐标：它有自己的快路径（[enterUnknownBasemap]），不走「给具体地点定源定级」的探测。
        if (_locationUnknown.value) return
        if (!BasemapProbe.needsProbe(style, place.latitude, place.longitude)) return
        val key = BasemapProbe.cacheKey(place.latitude, place.longitude)
        if (!force && mapFallback.probeFresh(key)) return
        probeJob?.cancel()
        if (!mapFallback.probeFresh(key)) {
            // 要探测：先把地图藏起来等结论（骨架已经在显示），MapView 直接按选定的源/级别出生。
            _mapReady.value = false
        }
        probeJob = viewModelScope.launch(Dispatchers.IO) {
            // 探测自身出异常时不改状态：让运行期的失败统计兜底，别凭一次异常就判「不可用」。
            val result = runCatching {
                BasemapProbeRunner.probe(place.latitude, place.longitude)
            }.getOrNull() ?: run {
                _mapReady.value = true // 探测失败也要把地图放出来（走运行期兜底）
                return@launch
            }
            mapFallback.onProbeResult(style, place.latitude, place.longitude, key, result)
            _mapReady.value = true
        }
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
        // 立刻进入加载态，并（境外）并发探测底图：首屏不再干等串行超时 + 逐级降级。
        startLoading()
        _mapReady.value = !BasemapProbe.needsProbe(_mapStyle.value, place.latitude, place.longitude)
        maybeProbeBasemap()
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
        /** 未知态底图的时间日志（logcat 里 `adb logcat -s SolarMap` 就能看到）。 */
        const val MAP_LOG_TAG = "SolarMap"

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