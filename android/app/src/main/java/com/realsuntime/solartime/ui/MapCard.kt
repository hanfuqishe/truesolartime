package com.realsuntime.solartime.ui

import android.content.Context
import android.view.MotionEvent
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
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import com.realsuntime.solartime.data.MapConfig
import com.realsuntime.solartime.R
import com.realsuntime.solartime.data.Place
import com.realsuntime.solartime.map.MapStyle
import com.realsuntime.solartime.map.MapTileSources
import com.realsuntime.solartime.solar.TimeFormat
import org.osmdroid.util.GeoPoint
import org.osmdroid.views.CustomZoomButtonsController
import org.osmdroid.views.MapView
import org.osmdroid.views.overlay.Marker

@Composable
fun MapCard(
    place: Place,
    mapStyle: MapStyle,
    modifier: Modifier = Modifier,
    mapAspectRatio: Float = 4f / 3f,
) {
    val context = LocalContext.current
    var mapView by remember { mutableStateOf<MapView?>(null) }
    val style = mapStyle.effective(place.latitude, place.longitude)

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
                    style = MaterialTheme.typography.titleSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(Modifier.weight(1f))
                Text(
                    text = TimeText.coordinates(context, place.latitude, place.longitude),
                    style = MaterialTheme.typography.bodySmall,
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
                    factory = { context -> createMapView(context, place, style).also { mapView = it } },
                    update = { view -> syncMap(view, place, style) },
                )
            }
            Spacer(Modifier.height(8.dp))
            Text(
                text = attributionText(context, mapStyle, style),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }

    LaunchedEffect(place, style, mapView) {
        val view = mapView ?: return@LaunchedEffect
        val (latitude, longitude) = markerPointOf(place, style)
        view.controller.animateTo(GeoPoint(latitude, longitude))
    }

    DisposableEffect(Unit) {
        onDispose {
            mapView?.onPause()
            mapView?.onDetach()
            mapView = null
        }
    }
}

private fun attributionText(context: Context, mapStyle: MapStyle, resolved: MapStyle): String =
    if (mapStyle == MapStyle.AUTO) {
        MapText.attribution(context, resolved) + " · " + context.getString(R.string.map_auto_selected)
    } else {
        MapText.attribution(context, resolved)
    }

/** 高德底图为 GCJ-02，需把 WGS-84 坐标偏移后再标点。 */
private fun markerPointOf(place: Place, style: MapStyle): Pair<Double, Double> =
    MapTileSources.toMapCoordinates(style, place.latitude, place.longitude)

private fun createMapView(context: Context, place: Place, style: MapStyle): MapView {
    MapConfig.init(context)
    val (latitude, longitude) = markerPointOf(place, style)
    val center = GeoPoint(latitude, longitude)
    return MapView(context).apply {
        setTileSource(MapTileSources.tileSourceOf(style))
        setMultiTouchControls(true)
        setUseDataConnection(true)
        zoomController.setVisibility(CustomZoomButtonsController.Visibility.NEVER)
        minZoomLevel = 3.0
        maxZoomLevel = 18.0
        controller.setZoom(12.0)
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
        onResume()
    }
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