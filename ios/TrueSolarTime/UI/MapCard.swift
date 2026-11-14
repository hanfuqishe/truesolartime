import MapKit
import SwiftUI

/// 内嵌地图：自动按地区选择高德或 OpenStreetMap 瓦片，并把 WGS-84 坐标换算到底图坐标系。
struct MapCard: View {

    let place: Place
    let mapStyle: MapStyle

    private var resolvedStyle: MapStyle {
        mapStyle.effective(latitude: place.latitude, longitude: place.longitude)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("位置地图")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(TimeFormat.coordinates(latitude: place.latitude, longitude: place.longitude))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            MapViewRepresentable(place: place, style: resolvedStyle)
                .aspectRatio(4.0 / 3.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.top, 10)

            Text(attributionText)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.top, 8)
        }
        .cardBackground()
    }

    private var attributionText: String {
        mapStyle == .auto
            ? "\(resolvedStyle.attribution) · 按所在地区自动选择"
            : resolvedStyle.attribution
    }
}

private struct MapViewRepresentable: UIViewRepresentable {

    let place: Place
    let style: MapStyle

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.isRotateEnabled = false
        mapView.isPitchEnabled = false
        mapView.pointOfInterestFilter = .excludingAll
        mapView.delegate = context.coordinator
        context.coordinator.attach(style: style, to: mapView)
        context.coordinator.move(to: place, style: style, on: mapView, animated: false)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        if context.coordinator.currentStyle != style {
            context.coordinator.attach(style: style, to: mapView)
        }
        context.coordinator.move(to: place, style: style, on: mapView, animated: true)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, MKMapViewDelegate {

        var currentStyle: MapStyle?
        private var tileOverlay: MKTileOverlay?
        private var annotation: MKPointAnnotation?

        func attach(style: MapStyle, to mapView: MKMapView) {
            if let existing = tileOverlay {
                mapView.removeOverlay(existing)
            }
            mapView.removeAnnotations(mapView.annotations)

            let overlay = MKTileOverlay(urlTemplate: style.tileURLTemplate)
            overlay.canReplaceMapContent = true
            overlay.maximumZ = style.maximumZ
            overlay.minimumZ = 3
            mapView.addOverlay(overlay, level: .aboveLabels)

            let point = MKPointAnnotation()
            mapView.addAnnotation(point)

            tileOverlay = overlay
            annotation = point
            currentStyle = style
        }

        func move(to place: Place, style: MapStyle, on mapView: MKMapView, animated: Bool) {
            let converted = MapCoordinates.toMapCoordinates(
                style: style,
                latitude: place.latitude,
                longitude: place.longitude
            )
            let coordinate = CLLocationCoordinate2D(latitude: converted.latitude, longitude: converted.longitude)

            annotation?.coordinate = coordinate
            annotation?.title = place.label

            let region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 12_000, longitudinalMeters: 12_000)
            mapView.setRegion(region, animated: animated)
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tile = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(tileOverlay: tile)
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}
