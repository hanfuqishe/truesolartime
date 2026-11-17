package com.realsuntime.solartime.ui

import android.content.Context
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
import com.realsuntime.solartime.map.MapFallbackState
import com.realsuntime.solartime.map.MapStyle
import com.realsuntime.solartime.map.MapTilePlan
import com.realsuntime.solartime.map.MapTileSources
import com.realsuntime.solartime.solar.TimeFormat
import kotlinx.coroutines.delay
import org.osmdroid.tileprovider.MapTileProviderBase
import org.osmdroid.util.GeoPoint
import org.osmdroid.views.CustomZoomButtonsController
import org.osmdroid.views.MapView
import org.osmdroid.views.overlay.Marker
import kotlin.math.roundToInt

/** 连最低级别的全球底图都没有瓦片时，隔多久重画一次等网络恢复（不弹任何提示）。 */
private const val TILE_RETRY_MILLIS = 15_000L

/**
 * 地图卡片。
 *
 * 底图不再是「直接拿设置里的样式去取瓦片」，而是一律经过 [MapFallback.plan]：
 * 自动模式下 OSM 连续失败会回退到高德，缩放级别也可能为了绕开「没瓦片的级别」降级，
 * 「底图不可用」则只在连最低级别的全球底图都拿不到时才出现。
 *
 * 字号缩放由调用方锁死（`MainScreen` 里用 `LockedCardDensity` 包住，fontScale 恒为 1）；
 * 这里的字重也一律显式写出，避免被系统「粗体字」的字重调整带偏。
 */
@Composable
fun MapCard(
    place: Place,
    mapStyle: MapStyle,
    fallback: MapFallbackState,
    onTileEvent: (Boolean, Int) -> Unit,
    onZoomApplied: (Int) -> Unit,
    modifier: Modifier = Modifier,
    mapAspectRatio: Float = 4f / 3f,
) {
    val context = LocalContext.current
    var mapView by remember { mutableStateOf<MapView?>(null) }
    val plan = remember(mapStyle, place.latitude, place.longitude, fallback) {
        MapFallback.plan(mapStyle, place.latitude, place.longitude, fallback)
    }
    val zoomPlan = remember(plan, fallback) {
        MapFallback.zoomPlan(plan, MapFallback.DEFAULT_ZOOM, fallback)
    }
    val style = plan.effective
    // 瓦片回调挂在很久以前创建的 MapView 上，必须拿「最新一版」回调，不能记住 factory 那一刻的。
    val latestTileEvent = rememberUpdatedState(onTileEvent)

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
                    text = TimeText.coordinates(context, place.latitude, place.longitude),
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
                AndroidView(
                    modifier = Modifier.fillMaxSize(),
                    factory = { context ->
                        createMapView(context, place, style, zoomPlan.zoom) { success, zoom ->
                            latestTileEvent.value(success, zoom)
                        }.also { mapView = it }
                    },
                    update = { view -> syncMap(view, place, style) },
                )
                if (zoomPlan.unavailable) {
                    // 真没网：地图区域给一行字，别让用户对着一块空白以为功能坏了。
                    MapUnavailableLabel()
                }
            }
            Spacer(Modifier.height(8.dp))
            Text(
                text = attributionText(context, plan),
                style = cardTextStyle(MaterialTheme.typography.bodySmall, FontWeight.Normal),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }

    LaunchedEffect(place, style, mapView) {
        val view = mapView ?: return@LaunchedEffect
        val (latitude, longitude) = markerPointOf(place, style)
        view.controller.animateTo(GeoPoint(latitude, longitude))
    }

    // 只在我们主动改级别（首次进入 / 降级链下探）时动缩放，用户自己捏合放大后不再抢回来。
    LaunchedEffect(zoomPlan.zoom, mapView) {
        val view = mapView ?: return@LaunchedEffect
        if (view.zoomLevelDouble.roundToInt() != zoomPlan.zoom) {
            view.controller.setZoom(zoomPlan.zoom.toDouble())
        }
        onZoomApplied(zoomPlan.zoom)
    }

    // 连最低级别都没瓦片：定期重画，网络一恢复就自己出图（静默，不打扰用户）。
    LaunchedEffect(zoomPlan.unavailable, mapView) {
        if (!zoomPlan.unavailable) return@LaunchedEffect
        val view = mapView ?: return@LaunchedEffect
        while (true) {
            delay(TILE_RETRY_MILLIS)
            view.invalidate()
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
private fun attributionText(context: Context, plan: MapTilePlan): String =
    if (plan.requested == MapStyle.AUTO) {
        val hint = if (plan.fellBack) R.string.map_auto_fallback else R.string.map_auto_selected
        MapText.attribution(context, plan.effective) + " · " + context.getString(hint)
    } else {
        MapText.attribution(context, plan.effective)
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

/** 高德底图为 GCJ-02，需把 WGS-84 坐标偏移后再标点。 */
private fun markerPointOf(place: Place, style: MapStyle): Pair<Double, Double> =
    MapTileSources.toMapCoordinates(style, place.latitude, place.longitude)

private fun createMapView(
    context: Context,
    place: Place,
    style: MapStyle,
    zoom: Int,
    onTileEvent: (Boolean, Int) -> Unit,
): MapView {
    MapConfig.init(context)
    val (latitude, longitude) = markerPointOf(place, style)
    val center = GeoPoint(latitude, longitude)
    return MapView(context).apply {
        setTileSource(MapTileSources.tileSourceOf(style))
        setMultiTouchControls(true)
        setUseDataConnection(true)
        zoomController.setVisibility(CustomZoomButtonsController.Visibility.NEVER)
        minZoomLevel = MapFallback.MIN_ZOOM.toDouble()
        maxZoomLevel = MapFallback.MAX_ZOOM.toDouble()
        controller.setZoom(zoom.toDouble())
        controller.setCenter(center)
        overlays.add(
            Marker(this).apply {
                position = center
                setAnchor(Marker.ANCHOR_CENTER, Marker.ANCHOR_BOTTOM)
                title = place.label
            },
        )
        // 地图嵌在可滚动列表中：手势落在图上时由地图接管，避免父级滚动抢夺。
        setOnTouchListener { view, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN, MotionEvent.ACTION_MOVE ->
                    view.parent?.requestDisallowInterceptTouchEvent(true)
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL ->
                    view.parent?.requestDisallowInterceptTouchEvent(false)
            }
            false
        }
        observeTileLoad(onTileEvent)
        onResume()
    }
}

/**
 * 挂上 osmdroid 的「瓦片请求结束」回调。
 *
 * osmdroid 把 HTTP 非 2xx、连接超时、解码失败统一收敛成 [MapTileProviderBase.MAPTILE_FAIL_ID]，
 * 所以这里收到的失败就是「这一块瓦片真的没拿到」，不用自己再解析网络异常。
 * 只上报、不弹提示：底图网络问题不该用 toast 打扰用户。
 */
private fun MapView.observeTileLoad(onEvent: (Boolean, Int) -> Unit) {
    val handler = object : Handler(Looper.getMainLooper()) {
        override fun handleMessage(msg: Message) {
            val success = when (msg.what) {
                MapTileProviderBase.MAPTILE_SUCCESS_ID -> true
                MapTileProviderBase.MAPTILE_FAIL_ID -> false
                else -> return
            }
            onEvent(success, zoomLevelDouble.roundToInt())
        }
    }
    // MapView 自己也是往这个集合里塞 Handler 的（见其构造里的 getTileRequestCompleteHandlers().add），
    // 所以这里追加即可，不会顶掉地图自身的重绘回调。
    tileProvider.tileRequestCompleteHandlers.add(handler)
}

private fun syncMap(view: MapView, place: Place, style: MapStyle) {
    val tileSource = MapTileSources.tileSourceOf(style)
    if (view.tileProvider.tileSource.name() != tileSource.name()) {
        view.setTileSource(tileSource)
    }
    val marker = view.overlays.filterIsInstance<Marker>().firstOrNull() ?: return
    val (latitude, longitude) = markerPointOf(place, style)
    if (marker.position.latitude != latitude || marker.position.longitude != longitude) {
        marker.position = GeoPoint(latitude, longitude)
        marker.title = place.label
        view.invalidate()
    }
}
