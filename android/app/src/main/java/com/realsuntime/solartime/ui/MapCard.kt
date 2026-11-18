package com.realsuntime.solartime.ui

import android.content.Context
import android.graphics.Bitmap
import android.graphics.drawable.BitmapDrawable
import android.os.Handler
import android.os.Looper
import android.os.Message
import android.view.MotionEvent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import com.realsuntime.solartime.data.MapConfig
import com.realsuntime.solartime.R
import com.realsuntime.solartime.data.Place
import com.realsuntime.solartime.map.MapFallback
import com.realsuntime.solartime.map.MapStyle
import com.realsuntime.solartime.map.MapTileSources
import com.realsuntime.solartime.map.MapUiState
import com.realsuntime.solartime.map.TileBlank
import com.realsuntime.solartime.map.TileContent
import com.realsuntime.solartime.map.TileEvent
import com.realsuntime.solartime.map.TileResult
import com.realsuntime.solartime.solar.Placeholders
import com.realsuntime.solartime.solar.TimeFormat
import kotlinx.coroutines.delay
import org.osmdroid.tileprovider.MapTileProviderBase
import org.osmdroid.util.GeoPoint
import org.osmdroid.util.MapTileIndex
import org.osmdroid.views.CustomZoomButtonsController
import org.osmdroid.views.MapView
import org.osmdroid.views.overlay.Marker
import kotlin.math.roundToInt

/** 连最低级别的全球底图都没有瓦片时，隔多久重画一次等网络恢复（不弹任何提示）。 */
private const val TILE_RETRY_MILLIS = 15_000L

/** 空白检测的「已分析瓦片」备忘录上限：长时间平移后清一次，别让它无限涨。 */
private const val MAX_TRACKED_TILES = 512

/** 地图中心周围检查几圈瓦片（1 = 3×3，含中心）。 */
private const val BLANK_SCAN_RADIUS = 1

/** 高德源定时重扫中心瓦片的间隔（覆盖「瓦片已在缓存、没有成功回调」的情况）。 */
private const val BLANK_RESCAN_MILLIS = 2_000L

/** 加载态最长盖住地图的时间：超过就收起，绝不能一直挡着（真出不来还有别的兜底）。 */
private const val LOADING_SKELETON_TIMEOUT_MILLIS = 6_000L

/**
 * 地图卡片。
 *
 * 底图不再是「直接拿设置里的样式去取瓦片」，而是一律经过 [MapFallback.plan]：
 * 自动模式下 OSM 连续失败会回退到高德，缩放级别也可能为了绕开「没瓦片的级别」降级，
 * 「底图不可用」则只在连最低级别的全球底图都拿不到时才出现。
 *
 * 高德对境外回 200 的空白瓦片（灰底 + 水印、没有地理内容）也是靠这张卡片认出来的：
 * [TileBlankWatcher] 在瓦片回调里从 tileCache 取 bitmap 采样，判空白就上报
 * [TileResult.BLANK]，由状态机当失败处理（见 [MapFallback.onTileBlank]）。
 *
 * 字号缩放由调用方锁死（`MainScreen` 里用 `LockedCardDensity` 包住，fontScale 恒为 1）；
 * 这里的字重也一律显式写出，避免被系统「粗体字」的字重调整带偏。
 */
@Composable
fun MapCard(
    place: Place,
    ui: MapUiState,
    /**
     * 定位不可用（未知态）：没有坐标可标 —— 不画定位标记、右上角经纬度显示 `—`，
     * 视口由 [MapUiState.ofUnknown] 固定为最低级别的全球底图（z3）。
     */
    locationUnknown: Boolean,
    loading: Boolean,
    ready: Boolean,
    isZoomUnavailable: (Int) -> Boolean,
    onTileEvent: (TileEvent) -> Unit,
    onViewportApplied: (Int) -> Unit,
    /**
     * 用户**手动**平移 / 缩放过地图：渐进升级据此冻结（不把用户的视图顶回去）。
     * 程序化的 setCenter / setZoom 不会触发它。
     */
    onUserMapGesture: () -> Unit,
    modifier: Modifier = Modifier,
    mapAspectRatio: Float = 4f / 3f,
) {
    val context = LocalContext.current
    var mapView by remember { mutableStateOf<MapView?>(null) }
    val style = ui.source
    // 加载态延迟 120ms 再显示：国内/缓存命中时瓦片 1 帧就出来，别闪一下骨架。
    // 6 秒兜底：无论如何都不能让骨架长期盖住地图（真出不来还有「底图不可用」或地图本身兜底）。
    var showSkeleton by remember { mutableStateOf(false) }
    LaunchedEffect(loading) {
        if (loading) {
            delay(120L)
            showSkeleton = true
            delay(LOADING_SKELETON_TIMEOUT_MILLIS)
            showSkeleton = false
        } else {
            showSkeleton = false
        }
    }
    // 瓦片回调挂在很久以前创建的 MapView 上，必须拿「最新一版」回调，不能记住 factory 那一刻的。
    val latestTileEvent = rememberUpdatedState(onTileEvent)
    // 空白检测也要看「最新一版」的源：factory 里记住的 style 在回退之后就是旧的了。
    val latestStyle = rememberUpdatedState(style)
    // 定时重扫要看「最新一版」的判定（这一级是否已经判过没内容），别拿旧值反复刷新计数。
    val latestUnavailable = rememberUpdatedState(isZoomUnavailable)
    // 空白检测器整个卡片生命周期只有一个：已分析瓦片的记忆要跨重组保留。
    val blankWatcher = remember { TileBlankWatcher { latestStyle.value } }

    Card(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(24.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
    ) {
        Column(Modifier.padding(20.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = stringResource(R.string.location_map_title),
                    style = cardTextStyle(MaterialTheme.typography.titleSmall, FontWeight.Medium),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(Modifier.weight(1f))
                Text(
                    // 未知态没有坐标：右上角显示 `—`（不要写上一次地点的经纬度）。
                    text = if (locationUnknown) {
                        Placeholders.coordinates()
                    } else {
                        TimeText.coordinates(context, place.latitude, place.longitude)
                    },
                    style = cardTextStyle(MaterialTheme.typography.bodySmall, FontWeight.Normal),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Spacer(Modifier.height(10.dp))
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .aspectRatio(mapAspectRatio)
                    .clip(RoundedCornerShape(16.dp)),
            ) {
                if (ready) {
                    AndroidView(
                        modifier = Modifier.fillMaxSize(),
                        factory = { context ->
                            createMapView(
                                context = context,
                                place = place,
                                style = style,
                                zoom = ui.zoom,
                                showMarker = !locationUnknown,
                                watcher = blankWatcher,
                                onTileEvent = { event -> latestTileEvent.value(event) },
                                onUserGesture = onUserMapGesture,
                            ).also { mapView = it }
                        },
                        update = { view -> syncMap(view, place, style, showMarker = !locationUnknown) },
                    )
                }
                if (ui.unavailable) {
                    // 真没网：地图区域给一行字，别让用户对着一块空白以为功能坏了。
                    MapUnavailableLabel()
                } else if (!ready || showSkeleton) {
                    // 还没出图（并行探测中 / 切城市后等第一块瓦片）：立刻给骨架 + 一行小字，别让用户干等。
                    MapLoadingLabel()
                }
            }
            Spacer(Modifier.height(8.dp))
            Text(
                text = attributionText(context, ui),
                style = cardTextStyle(MaterialTheme.typography.bodySmall, FontWeight.Normal),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }

    // 唯一一处视口操作，顺序固定：**居中 → 缩放 → 再确认居中**。
    //
    // 这三步必须在一个效果里、且不能用 animateTo：
    // * 以前用 `animateTo`（带动画）+ 另一个 `LaunchedEffect` 里 `setZoom`，两个效果会互相打断 ——
    //   `setZoom` 会 `forceFinished` 掉平移动画，地图就停在中途，真机上就是「标记不在中心」；
    // * 居中放在缩放之后再做一次，是因为缩放会按当前滚动中心重算，先居中再缩放偶尔会差几个像素。
    LaunchedEffect(place, ui.source, ui.zoom, mapView, locationUnknown) {
        val view = mapView ?: return@LaunchedEffect
        // 未知态没有观测点：视口落在 (0, 0)（境外口径的全球底图中心），不标任何位置。
        val (latitude, longitude) = if (locationUnknown) {
            MapUiState.UNKNOWN_LATITUDE to MapUiState.UNKNOWN_LONGITUDE
        } else {
            markerPointOf(place, ui.source)
        }
        val target = GeoPoint(latitude, longitude)
        view.controller.setCenter(target)
        if (view.zoomLevelDouble.roundToInt() != ui.zoom) {
            view.controller.setZoom(ui.zoom.toDouble())
        }
        view.controller.setCenter(target)
        // **必须重绘一次**：切源（OSM→高德）和改级别都会把在飞的请求取消掉，
        // osmdroid 只有在下一次 draw 时才会按新的 tile 队列重新发请求 ——
        // 不主动 invalidate 的话，真机上会出现「探测已经定好级别、地图却一直不请求瓦片」
        // （实测：不重绘就一直停在骨架，手指轻扫一下地图瓦片立刻全出来）。
        view.invalidate()
        // 告诉状态机「视口刚被程序化改过」：这之后 2 秒内回来的瓦片失败是被取消的旧请求，不计入降级。
        onViewportApplied(ui.zoom)
    }

    // 连最低级别都没瓦片：定期重画，网络一恢复就自己出图（静默，不打扰用户）。
    LaunchedEffect(ui.unavailable, mapView) {
        if (!ui.unavailable) return@LaunchedEffect
        val view = mapView ?: return@LaunchedEffect
        while (true) {
            delay(TILE_RETRY_MILLIS)
            view.invalidate()
        }
    }

    // 高德源：定时重扫中心瓦片。
    //
    // 空白瓦片一旦进了磁盘缓存，重启 App / 平移回看过的区域时**不会再有成功回调**，
    // 只靠回调就永远发现不了（用户看到的就是「重启后又变回一片灰」）。
    // 每 BLANK_RESCAN_MILLIS 看一眼；这一级已经判过「没内容」就跳过，不再刷计数。
    LaunchedEffect(style, mapView) {
        val view = mapView ?: return@LaunchedEffect
        if (!style.isGcj02) return@LaunchedEffect
        while (true) {
            delay(BLANK_RESCAN_MILLIS)
            val zoom = view.zoomLevelDouble.roundToInt()
            if (latestUnavailable.value(zoom)) continue
            val scan = blankWatcher.scan(view, zoom, maxBlank = MapFallback.FAILURE_THRESHOLD)
            when {
                scan.blanks.isNotEmpty() -> scan.blanks.forEach { latestTileEvent.value(it) }
                scan.inspected > 0 -> latestTileEvent.value(TileEvent(zoom, TileResult.LOADED))
                else -> Unit
            }
        }
    }

    DisposableEffect(Unit) {
        onDispose {
            mapView?.onPause()
            mapView?.onDetach()
            mapView = null
        }
    }
}

/** 底图署名必须跟着**实际使用的源**走：回退到高德就署高德，自动模式再补一句为什么。 */
private fun attributionText(context: Context, ui: MapUiState): String =
    if (ui.requested == MapStyle.AUTO) {
        val hint = if (ui.fellBack) R.string.map_auto_fallback else R.string.map_auto_selected
        MapText.attribution(context, ui.source) + " · " + context.getString(hint)
    } else {
        MapText.attribution(context, ui.source)
    }

@Composable
private fun MapUnavailableLabel() {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.surface.copy(alpha = 0.72f)),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = stringResource(R.string.map_unavailable),
            style = cardTextStyle(MaterialTheme.typography.bodySmall, FontWeight.Medium),
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

/**
 * 加载态：几块静态骨架 + 一行「正在载入底图…」。
 *
 * 刻意用**静态**骨架（不用转圈/呼吸动画）：这张卡片在滚动列表里，动画会一直请求下一帧，
 * 反过来又容易和「停止刷新」的预期打架；静态块 + 小字已经足够表达「在等」。
 */
@Composable
private fun MapLoadingLabel() {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.surface),
        contentAlignment = Alignment.Center,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            val barColor = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.10f)
            listOf(0.62f, 0.86f, 0.48f).forEach { widthFraction ->
                Box(
                    modifier = Modifier
                        .padding(vertical = 4.dp)
                        .fillMaxWidth(widthFraction)
                        .height(12.dp)
                        .clip(RoundedCornerShape(6.dp))
                        .background(barColor),
                )
            }
            Spacer(Modifier.height(10.dp))
            Text(
                text = stringResource(R.string.map_loading),
                style = cardTextStyle(MaterialTheme.typography.bodySmall, FontWeight.Normal),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

/** 高德底图为 GCJ-02，需把 WGS-84 坐标偏移后再标点。 */
private fun markerPointOf(place: Place, style: MapStyle): Pair<Double, Double> =
    MapTileSources.toMapCoordinates(style, place.latitude, place.longitude)

private fun createMapView(
    context: Context,
    place: Place,
    style: MapStyle,
    zoom: Int,
    /** 是否画定位标记：未知态（定位不可用）为 false —— 没有坐标可标。 */
    showMarker: Boolean,
    watcher: TileBlankWatcher,
    onTileEvent: (TileEvent) -> Unit,
    /** 用户手动平移 / 缩放（不是程序化改视口）时回调。 */
    onUserGesture: () -> Unit,
): MapView {
    MapConfig.init(context)
    val (latitude, longitude) = markerPointOf(place, style)
    val center = GeoPoint(latitude, longitude)
    // 手势判定：按下后移动超过系统 touchSlop、或出现第二根手指（缩放）就算「用户动过」。
    val touchSlop = android.view.ViewConfiguration.get(context).scaledTouchSlop
    return MapView(context).apply {
        setTileSource(MapTileSources.tileSourceOf(style))
        setMultiTouchControls(true)
        setUseDataConnection(true)
        zoomController.setVisibility(CustomZoomButtonsController.Visibility.NEVER)
        minZoomLevel = MapFallback.MIN_ZOOM.toDouble()
        maxZoomLevel = MapFallback.MAX_ZOOM.toDouble()
        controller.setZoom(zoom.toDouble())
        controller.setCenter(center)
        if (showMarker) overlays.add(newMarker(this, place, style))
        // 地图嵌在可滚动列表中：手势落在图上时由地图接管，避免父级滚动抢夺。
        // 同时判定「用户真的平移/缩放过」——只有这种情况才冻结渐进升级；程序化改视口不经过这里。
        var downX = 0f
        var downY = 0f
        var moved = false
        setOnTouchListener { view, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downX = event.x
                    downY = event.y
                    moved = false
                    view.parent?.requestDisallowInterceptTouchEvent(true)
                }
                MotionEvent.ACTION_POINTER_DOWN -> moved = true
                MotionEvent.ACTION_MOVE -> {
                    if (event.pointerCount > 1) {
                        moved = true
                    } else if (kotlin.math.hypot(event.x - downX, event.y - downY) > touchSlop) {
                        moved = true
                    }
                    view.parent?.requestDisallowInterceptTouchEvent(true)
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    view.parent?.requestDisallowInterceptTouchEvent(false)
                    if (moved) onUserGesture()
                }
            }
            false
        }
        observeTileLoad(watcher, onTileEvent)
        onResume()
    }
}

/**
 * 挂上 osmdroid 的「瓦片请求结束」回调。
 *
 * osmdroid 把 HTTP 非 2xx、连接超时、解码失败统一收敛成 [MapTileProviderBase.MAPTILE_FAIL_ID]，
 * 所以这里收到的失败就是「这一块瓦片真的没拿到」，不用自己再解析网络异常。
 * 成功这一侧则不一定真拿到了内容（高德境外会给空白瓦片），交给 [TileBlankWatcher] 看一眼像素。
 * 只上报、不弹提示：底图网络问题不该用 toast 打扰用户。
 */
private fun MapView.observeTileLoad(
    watcher: TileBlankWatcher,
    onEvent: (TileEvent) -> Unit,
) {
    val handler = object : Handler(Looper.getMainLooper()) {
        override fun handleMessage(msg: Message) {
            val zoom = zoomLevelDouble.roundToInt()
            when (msg.what) {
                MapTileProviderBase.MAPTILE_SUCCESS_ID -> {
                    val scan = watcher.scan(this@observeTileLoad, zoom, maxBlank = 1)
                    when {
                        // 空白瓦片：状态机当失败处理，继续降级。
                        scan.blanks.isNotEmpty() -> onEvent(scan.blanks.first())
                        // 真的看过瓦片且有内容：正常成功（清失败计数、标记该级别可用）。
                        scan.inspected > 0 -> onEvent(TileEvent(zoom, TileResult.LOADED))
                        // 没有新瓦片可看（视口里十几块瓦片的成功通知远多于 9 块分析目标）：
                        // **什么都不报** —— 报成 LOADED 会把空白的连续计数清零，永远凑不够阈值
                        // （真机实测过：8 次空白判定却一次也没降级）。
                        else -> Unit
                    }
                }

                MapTileProviderBase.MAPTILE_FAIL_ID -> onEvent(TileEvent(zoom, TileResult.FAILED))
                else -> return
            }
        }
    }
    // MapView 自己也是往这个集合里塞 Handler 的（见其构造里的 getTileRequestCompleteHandlers().add），
    // 所以这里追加即可，不会顶掉地图自身的重绘回调。
    tileProvider.tileRequestCompleteHandlers.add(handler)
}

/**
 * 高德「空白瓦片」检测器。
 *
 * 为什么不是从回调里直接拿 bitmap：osmdroid 的完成通知是
 * `MapTileProviderBase.sendMessage()` → `sendEmptyMessage()`，**只有一个 what**，
 * 既没有瓦片坐标也没有图像。好在 `mapTileRequestCompleted()` 是「先把瓦片塞进 tileCache、
 * 再发通知」，所以通知到手时刚画上去的 bitmap 一定在 `tileProvider.tileCache` 里。
 *
 * 定位办法：按地图中心算出瓦片坐标，检查它周围 3×3 共 9 块（视口一般就这么多块）。
 * 每块只分析一次（按 级别 + 瓦片坐标 记忆），平移 / 降级换级别时才重新开始。
 *
 * 除了「瓦片成功」通知，[MapCard] 还会每 [BLANK_RESCAN_MILLIS] 调一次 [scan]：
 * 空白瓦片一旦进了磁盘缓存，重启 App 或平移回看过的区域时**不会再有任何成功回调**，
 * 只靠回调就永远发现不了（用户看到的就是「重启后又变回一片灰」）。
 *
 * 只在高德源上做：OSM 的瓦片不必多花这份开销，也避免把 OSM 的特殊瓦片误判成空白。
 */
private class TileBlankWatcher(private val latestStyle: () -> MapStyle) {

    /** 已经分析过的瓦片（同一 source + zoom 内有效）。 */
    private val analyzed = HashSet<Long>()

    private var watchedStyle: MapStyle? = null
    private var watchedZoom = -1

    /** 当前这一屏上一次的结论：全都空白（true）/ 有内容（false）。没看过是 null。 */
    private var viewportBlank: Boolean? = null

    /** 最近一块空白瓦片的量化颜色种类（诊断文案用）。 */
    private var lastBlankKinds = 0

    /**
     * 扫一遍中心 3×3 里还没分析过的瓦片，看这一屏是不是「一片空白」。
     *
     * **判据是「这一屏全都空白」，不是「有没有一块空白」**：低级别（z3 全球图）上，
     * 撒哈拉、西伯利亚、南极冰盖这种真·纯色瓦片和「没数据」的空白瓦片在像素上根本没法区分
     * （实测高德 z3 的沙漠瓦片就是一块 #F7F3EA 纯色，和境外空白瓦片一模一样）。
     * 但真在出图的视口里一定混着海岸线、国界、地名 —— 只要混进一块有内容的，就不算空白。
     *
     * 每块瓦片只分析一次，所以「上一次的结论」要记住：这一屏的瓦片全分析完了、后面没有
     * 新瓦片可看时，仍然按上次的结论继续报空白（否则状态机停在「同一级别连续 2 次」上，
     * 永远凑不够 [MapFallback.FAILURE_THRESHOLD]，真机上就是这么卡在 z10 的）。
     *
     * @param maxBlank 一次最多报几块空白（够触发一级降级即可，不必把计数刷爆）。
     */
    fun scan(view: MapView, zoom: Int, maxBlank: Int): TileScan {
        val style = latestStyle()
        if (!style.isGcj02) return TileScan.NOTHING
        // 切源是 Compose 的 update 里做的：plan 已经变成高德、MapView 还挂着他源的这一小段窗口，
        // 缓存里可能还是别的源的瓦片，直接跳过，等下一块。
        if (view.tileProvider.tileSource.name() != MapTileSources.tileSourceOf(style).name()) {
            return TileScan.NOTHING
        }
        if (zoom < 0 || zoom > MAX_TILE_ZOOM) return TileScan.NOTHING
        if (style != watchedStyle || zoom != watchedZoom) {
            analyzed.clear()
            viewportBlank = null
            lastBlankKinds = 0
            watchedStyle = style
            watchedZoom = zoom
        }
        if (analyzed.size > MAX_TRACKED_TILES) {
            analyzed.clear()
            viewportBlank = null
        }

        val tileSystem = MapView.getTileSystem()
        val center = view.mapCenter
        val centerX = tileSystem.getTileXFromLongitude(center.longitude, zoom)
        val centerY = tileSystem.getTileYFromLatitude(center.latitude, zoom)
        val last = (1 shl zoom) - 1
        val contents = ArrayList<TileContent>(9)
        for (dx in -BLANK_SCAN_RADIUS..BLANK_SCAN_RADIUS) {
            for (dy in -BLANK_SCAN_RADIUS..BLANK_SCAN_RADIUS) {
                val x = centerX + dx
                val y = centerY + dy
                if (x < 0 || y < 0 || x > last || y > last) continue
                val index = MapTileIndex.getTileIndex(zoom, x, y)
                if (index in analyzed) continue
                val drawable = view.tileProvider.tileCache.getMapTile(index) ?: continue
                val bitmap = (drawable as? BitmapDrawable)?.bitmap ?: continue
                val content = sample(bitmap) ?: continue
                analyzed.add(index)
                contents.add(content)
            }
        }
        if (contents.isNotEmpty()) {
            viewportBlank = TileBlank.viewportIsBlank(contents)
            val blank = contents.lastOrNull { it.isBlank }
            if (blank != null) lastBlankKinds = blank.colorKinds
            if (viewportBlank == true) {
                // 这一屏全是空白：一块空白瓦片记一次失败，最多记 maxBlank 次。
                return TileScan(
                    inspected = contents.size,
                    blanks = List(minOf(contents.size, maxBlank)) {
                        TileEvent(zoom, TileResult.BLANK, lastBlankKinds)
                    },
                )
            }
            return TileScan(inspected = contents.size, blanks = emptyList())
        }
        // 这一轮没有新瓦片可看：按上一次的结论继续报（保证「同一级别连续 3 次」能凑够）。
        return if (viewportBlank == true) {
            TileScan(inspected = 0, blanks = listOf(TileEvent(zoom, TileResult.BLANK, lastBlankKinds)))
        } else {
            TileScan.NOTHING
        }
    }
    /**
     * 把瓦片缩到 [TileBlank.SAMPLE_SIDE]² 再取像素（相当于 256 像素的瓦片每 8 像素取一点）。
     *
     * `filter = false`（最近邻）是有意的：一旦做插值平均，方差就被抹平了，
     * 正常瓦片会被算得跟纯色差不多，反而更容易误判成空白。
     */
    private fun sample(bitmap: Bitmap): TileContent? = runCatching {
        val side = TileBlank.SAMPLE_SIDE
        val scaled = Bitmap.createScaledBitmap(bitmap, side, side, false)
        try {
            val pixels = IntArray(side * side)
            scaled.getPixels(pixels, 0, side, 0, 0, side, side)
            TileBlank.analyzeColors(pixels)
        } finally {
            if (scaled !== bitmap) scaled.recycle()
        }
    }.getOrNull()

    private companion object {
        /** osmdroid 的 MapTileIndex 打包上限（long 里放得下的最大级别）。 */
        const val MAX_TILE_ZOOM = 22
    }
}

/**
 * 一次扫描的结果：看过几块瓦片（[inspected]）、其中有几块是空白（[blanks]）。
 *
 * `inspected == 0` 说明这一轮没有任何新瓦片可看 —— 调用方**不要**把它当成「成功」。
 */
private data class TileScan(val inspected: Int, val blanks: List<TileEvent>) {
    companion object {
        val NOTHING = TileScan(0, emptyList())
    }
}

/** 定位标记：位置取该底图坐标系里的坐标，标题是地名（未知态不建它）。 */
private fun newMarker(view: MapView, place: Place, style: MapStyle): Marker {
    val (latitude, longitude) = markerPointOf(place, style)
    return Marker(view).apply {
        position = GeoPoint(latitude, longitude)
        setAnchor(Marker.ANCHOR_CENTER, Marker.ANCHOR_BOTTOM)
        title = place.label
    }
}

private fun syncMap(view: MapView, place: Place, style: MapStyle, showMarker: Boolean) {
    val tileSource = MapTileSources.tileSourceOf(style)
    if (view.tileProvider.tileSource.name() != tileSource.name()) {
        view.setTileSource(tileSource)
        // 切源会清空瓦片缓存：再推一次重绘，别让地图停在旧队列上等下一次手势。
        view.invalidate()
    }
    val marker = view.overlays.filterIsInstance<Marker>().firstOrNull()
    if (!showMarker) {
        // 进入未知态：把标记摘掉（地图上不能留一个「看起来就是这里」的点）。
        if (marker != null) {
            view.overlays.remove(marker)
            view.invalidate()
        }
        return
    }
    if (marker == null) {
        // 从未知态恢复：补回标记。
        view.overlays.add(newMarker(view, place, style))
        view.invalidate()
        return
    }
    val (latitude, longitude) = markerPointOf(place, style)
    if (marker.position.latitude != latitude || marker.position.longitude != longitude) {
        marker.position = GeoPoint(latitude, longitude)
        marker.title = place.label
        view.invalidate()
    }
}
