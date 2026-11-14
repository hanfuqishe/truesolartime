import SwiftUI

struct ContentView: View {

    @Environment(\.palette) private var palette

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
                        waitingForFix: model.waitingForFix,
                        weather: model.weather,
                        keyBands: model.keyTime?.bands ?? [],
                        bandColor: HeroPalette.band(model.keyTime?.temperature, isDay: model.snapshot.isDay),
                        inkColor: inKeyTime
                            ? HeroPalette.ink(model.keyTime?.temperature, isDay: model.snapshot.isDay)
                            : nil,
                        coordinates: TimeFormat.coordinates(
                            latitude: model.place.latitude,
                            longitude: model.place.longitude
                        ),
                        weatherNote: model.weather == nil ? model.weatherStatus : nil
                    )


                    SunCard(snapshot: model.snapshot)

                    MapCard(place: model.place, mapStyle: model.mapStyle)

                    Text(versionLabel)
                        .font(.system(size: 12))
                        .foregroundStyle(palette.onSurfaceVariant)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 6)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(palette.background)
            // 默认文字色跟随日/夜主题（子视图里显式设过色的不受影响）
            .foregroundStyle(palette.onSurface)
            // 设置按钮移进页头（与标题上边缘对齐），导航栏留空就直接隐藏。
            .toolbar(.hidden, for: .navigationBar)
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
        .environment(\.isDay, model.snapshot.isDay)
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

    /// 当前真太阳时是否落在某个关键时段内。
    ///
    /// 落在时段内时：真太阳时数字与时间轴圆点都换成该时段对应的绿/红（白天淡一档），
    /// 与 Android 的 `solarColor = if (inKeyTime) inkTint ?: accent else accent` 一致。
    private var inKeyTime: Bool {
        guard let schedule = model.keyTime else { return false }
        return schedule.band(containing: Double(model.snapshot.trueSolarTime.secondsOfDay) / 60) != nil
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("真太阳时时钟")
                    .font(.system(size: 26, weight: .semibold))
                Text("以太阳经过当地子午线的时刻为正午")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.onSurfaceVariant)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            Spacer(minLength: 8)

            // 右侧：跟随 GPS 时先显示「GPS」，再是设置齿轮；整体与标题**上边缘**对齐。
            HStack(alignment: .center, spacing: 4) {
                if model.trackingGps {
                    Text("GPS")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.onSurfaceVariant)
                }

                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 20, weight: .regular))
                        .frame(width: 32, height: 32, alignment: .center)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("设置")
            }
            .padding(.top, 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
        .padding(.bottom, 2)
    }

    private var versionLabel: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.4.39"
        return "版本 \(version)"
    }
}
