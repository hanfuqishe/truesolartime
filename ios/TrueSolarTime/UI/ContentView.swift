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
                        waitingForFix: model.waitingForFix,
                        weather: model.weather,
                        keyBands: model.keyTime?.bands ?? [],
                        keyHighlight: keyHighlight,
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
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 6)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(Color(uiColor: .systemGroupedBackground))
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

    /// 真太阳时落在关键时段内时用的**淡金色**；不在时段内返回 nil（保持白色）。
    ///
    /// 不再按「冷/热」区分颜色：时间轴上的关键时段统一显示为亮白，
    /// 只有当前真太阳时进入时段时，数字与圆点才换成淡金色。
    private var keyHighlight: Color? {
        guard let schedule = model.keyTime,
              schedule.band(containing: Double(model.snapshot.trueSolarTime.secondsOfDay) / 60) != nil
        else { return nil }
        return Color(red: 1.0, green: 0.90, blue: 0.62)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("真太阳时")
                    .font(.system(size: 26, weight: .semibold))
                Text("以太阳经过当地子午线的时刻为正午")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            Spacer(minLength: 8)

            // 右侧：跟随 GPS 时先显示「GPS」，再是设置齿轮；整体与标题**上边缘**对齐。
            HStack(alignment: .center, spacing: 4) {
                if model.trackingGps {
                    Text("GPS")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
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
