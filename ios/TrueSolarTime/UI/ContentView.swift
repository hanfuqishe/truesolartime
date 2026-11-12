import SwiftUI

struct ContentView: View {

    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    header

                    HeroCard(
                        snapshot: model.snapshot,
                        placeLabel: model.place.label,
                        districtName: model.districtName,
                        trackingGps: model.trackingGps,
                        waitingForFix: model.waitingForFix
                    )

                    BeijingCard(snapshot: model.snapshot)

                    WeatherCard(
                        weather: model.weather,
                        isDay: model.snapshot.isDay,
                        waitingForGPS: model.waitingForFix
                    )

                    KeyTimeCard(
                        schedule: model.keyTime,
                        trueSolarSeconds: Double(model.snapshot.trueSolarTime.secondsOfDay)
                    )

                    SunCard(snapshot: model.snapshot)

                    MapCard(place: model.place, mapStyle: model.mapStyle)

                    Text(versionLabel)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 6)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("设置")
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(model: model)
            }
            .alert("提示", isPresented: Binding(
                get: { model.message != nil },
                set: { if !$0 { model.message = nil } }
            )) {
                Button("好", role: .cancel) { model.message = nil }
            } message: {
                Text(model.message ?? "")
            }
        }
        .task {
            model.requestLocationPermissionIfNeeded()
            model.startGpsTracking(announce: false)
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                model.handleBecameActive()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("真太阳时")
                .font(.system(size: 26, weight: .semibold))
            Text("以太阳经过当地子午线的时刻为正午")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
        .padding(.bottom, 2)
    }

    private var versionLabel: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.2"
        return "版本 \(version)"
    }
}