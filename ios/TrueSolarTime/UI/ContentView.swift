import SwiftUI

struct ContentView: View {

    /// 页面自身的调色板必须**直接按太阳高度角算**，不能读 `@Environment(\.palette)`：
    /// 环境值是往下传的，`body` 里 `.environment(\.isDay, …)` 只影响子视图，
    /// 本视图自己读到的仍是外层默认值（白天），导致夜里只有卡片变暗、页面背景还是白的。
    private var palette: ThemePalette {
        ThemePalette.of(isDay: model.snapshot.isDay)
    }

    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    header

                    // 卡片区（大卡片 / 太阳 / 地图）统一不跟随系统「粗体文本」：
                    // 版式是按固定 em 排的，笔画一变粗，栏宽、行高、分档都会跟着偏。
                    // 页头与版本号仍跟随系统设置（见 CardLegibility.swift）。
                    Group {
                        HeroCard(
                            snapshot: model.snapshot,
                            districtName: cityText,
                            weather: model.weather,
                            keyBands: model.keyTime?.bands ?? [],
                            // 定位还没回来时先不画旧地点的关键时段色段与字色（与 Android 的 waitingForFix 判定一致）。
                            bandColor: model.waitingForFix
                                ? nil
                                : HeroPalette.band(model.keyTime?.temperature, isDay: model.snapshot.isDay),
                            inkColor: (inKeyTime && !model.waitingForFix)
                                ? HeroPalette.ink(model.keyTime?.temperature, isDay: model.snapshot.isDay)
                                : nil,
                            inKeyTime: inKeyTime,
                            coordinates: TimeFormat.coordinates(
                                latitude: model.place.latitude,
                                longitude: model.place.longitude
                            )
                        )


                        SunCard(snapshot: model.snapshot)

                        MapCard(place: model.place, mapStyle: model.mapStyle)
                    }
                    .cardLegibilityRegular()

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
            .background(palette.background.ignoresSafeArea())
            // 默认文字色跟随日/夜主题（子视图里显式设过色的不受影响）
            .foregroundStyle(palette.onSurface)
            // 设置按钮移进页头（与标题上边缘对齐），导航栏留空就直接隐藏。
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showSettings) {
                SettingsView(model: model)
                    .environment(\.isDay, model.snapshot.isDay)
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

    /// 卡片上那一行城市名，三段式（与 Android `MainScreen.cityText` 一致）：
    ///
    /// ① 反查到的行政区划名优先（`DistrictStore` 带 5 km 校验：换了城市就当作没有缓存）；
    /// ② 反查尚未返回 / 失败时，只有**预设城市**才回退显示预设城市名（如「纽约」）；
    /// ③ 手工坐标与 GPS 定位没有名字可用（label 是「手动设置」这类占位词），显示半角「-」。
    private var cityText: String {
        if let district = model.districtName?.full, !district.isEmpty {
            return district
        }
        if let preset = model.place.presetLabel, !preset.isEmpty {
            return preset
        }
        return "-"
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
