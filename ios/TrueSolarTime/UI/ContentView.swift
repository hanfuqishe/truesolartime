import SwiftUI

struct ContentView: View {

    /// 页面自身的调色板必须**直接按主题设置 + 太阳高度角算**，不能读 `@Environment(\.palette)`：
    /// 环境值是往下传的，`body` 里 `.environment(\.isDay, …)` 只影响子视图，
    /// 本视图自己读到的仍是外层默认值（白天），导致夜里只有卡片变暗、页面背景还是白的。
    ///
    /// 「自动」看太阳高度角（`SolarSnapshot.isDay`）；「亮色 / 暗色」强制忽略日出日落。
    private var palette: ThemePalette {
        ThemePalette.of(isDay: model.uiIsDay)
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
                            isLocationUnknown: model.isLocationUnknown,
                            // 大卡片的渐变按**主题设置**决定（自动 = 日出日落，亮色 / 暗色 = 强制），
                            // 与页面背景同一口径；卡片里太阳弧仍按真实高度角画。
                            isDay: model.uiIsDay,
                            districtName: cityText,
                            weather: model.weather,
                            // 逐时行的步长必须与底部署名同源：没有快照（缓存过期 / 刚换城市）时
                            // 也按这份来源的步长排格子，不能退回 1 小时。
                            weatherSource: model.weatherSource,
                            isWeatherLoading: model.weatherLoading,
                            keyBands: model.keyTime?.bands ?? [],
                            // 关键时段的色段**不看定位**：它是「真太阳时 0–24 时」轴上的固定区间，
                            // 与经纬度无关。之前这里叠了 `waitingForFix` 判定，定位没回来（室内很常见）
                            // 就整块不画，看起来就是「关键时间完全不显示」。
                            bandColor: axisBandColor,
                            // 字色/圆点仍然等定位：真太阳时本身依赖经度，等真位置回来再染色才对。
                            inkColor: (inKeyTime && !model.waitingForFix)
                                ? HeroPalette.ink(model.keyTime?.temperature, isDay: model.uiIsDay)
                                : nil,
                            inKeyTime: inKeyTime,
                            coordinates: TimeFormat.coordinates(
                                latitude: model.place.latitude,
                                longitude: model.place.longitude
                            )
                        )
                        // 只有最上方的大卡片不受系统「粗体文本」影响；
                        // 太阳卡、地图卡、设置页等仍按系统设置走（可读性优先）。
                        .cardLegibilityRegular()

                        SunCard(snapshot: model.snapshot, isLocationUnknown: model.isLocationUnknown)

                        MapCard(place: model.place, mapStyle: model.mapStyle, isLocationUnknown: model.isLocationUnknown)
                    }

                    // 版本号同时是「隐藏的诊断入口」：连续点 7 次（间隔 ≤2 秒）才在设置页
                    // 露出「诊断」区块。不显眼、不会误触，也不写偏好设置（重启回到隐藏）。
                    //
                    // 首页原先还有第二行「天气数据 © …」的来源署名，按用户要求去掉了（没必要，
                    // 而且会把页脚撑成两行）。**署名本身没有取消**：CC BY 4.0 的合规标注移到了
                    // 设置页「关于」里（见 `SettingsView`），仍然是跟着实际数据源切换的那一句。
                    Text(versionLabel)
                        .foregroundStyle(palette.onSurfaceVariant)
                        .font(.system(size: 12))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 6)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            model.registerVersionTap()
                        }
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
                    .environment(\.isDay, model.uiIsDay)
            }
            // 原来的「提示 / 好」弹窗已删除：这些消息都是纯告知，改成底部 Toast，
            // 1.8 秒自动消失、不拦点击（见 `Toast.swift`）。
        }
        .environment(\.isDay, model.uiIsDay)
        .toast(message: $model.message)
        .task {
            model.requestLocationPermissionIfNeeded()
            // 启动恢复：只在「本来就打算跟随 GPS」时启动；再复核一次权限（撤销过就进未知态）。
            model.resumeGpsIfNeeded(announce: false)
            model.syncLocationPermission()
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                // 回到前台：立刻试一次主源（不等退避计时器），并把天气轮询切回前台节奏。
                model.setAppActive(true)
            case .background:
                // 退到后台：重试主源的最小间隔变成 10 分钟（不参与 60 秒轮询）。
                model.setAppActive(false)
            case .inactive:
                // 下拉通知中心 / 切到多任务：什么都不做，别把前台节奏误判成后台。
                break
            @unknown default:
                break
            }
        }
    }

    /// 卡片上那一行城市名。规则抽在 Core 的 `DistrictNaming.cardCityText`（可自检）：
    ///
    /// ① 反查到的行政区划名优先；
    /// ② 反查失败时，只有**预设城市**才回退显示预设城市名（如「纽约」）；
    /// ③ 手工坐标与 GPS 定位没有名字可用 → 半角「-」（失败**不回填**上一个城市的地名）。
    private var cityText: String {
        // 未知态（跟随 GPS 但拿不到定位）：地名位置显示「定位不可用」，可点击去系统设置。
        if model.isLocationUnknown { return L("location.unavailable") }
        return DistrictNaming.cardCityText(district: model.districtName, place: model.place)
    }

    /// 时间轴上关键时段的颜色。
    ///
    /// 优先按页面给出的温度标记（冻或温 = 绿 / 热或温 = 红）；温度标记缺失（页面改版）时
    /// 退到当日强调色 —— 宁可颜色语义不准，也不要让「有关键时间却什么都看不到」重演。
    /// 设置页「诊断 → 关键时间」会写清当前是「温度未标注」还是具体温度。
    private var axisBandColor: Color? {
        guard let schedule = model.keyTime else { return nil }
        let isDay = model.uiIsDay
        return HeroPalette.band(schedule.temperature, isDay: isDay) ?? HeroPalette.accent(isDay: isDay)
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
                Text(L("app.name"))
                    .font(.system(size: 26, weight: .semibold))
                Text(L("app.tagline"))
                    .font(.system(size: 12))
                    .foregroundStyle(palette.onSurfaceVariant)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            Spacer(minLength: 8)

            // 右侧：跟随 GPS 时先显示「GPS」，再是设置齿轮；整体与标题**上边缘**对齐。
            HStack(alignment: .center, spacing: 4) {
                if model.trackingGps && !model.isLocationUnknown {
                    Text(L("gps.badge"))
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
                .accessibilityLabel(L("common.settings"))
            }
            .padding(.top, 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
        .padding(.bottom, 2)
    }

    private var versionLabel: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.4.39"
        return Lf("app.version", version)
    }
}
