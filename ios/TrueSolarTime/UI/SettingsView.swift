import SwiftUI

struct SettingsView: View {

    @Environment(\.palette) private var palette

    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var latitudeText = ""
    @State private var longitudeText = ""
    @State private var errorText: String?


    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    section(title: L("settings.sectionCurrent")) {
                        Text("\(model.place.displayLabel)  \(TimeFormat.coordinates(latitude: model.place.latitude, longitude: model.place.longitude))")
                            .font(.system(size: 15))

                        Button {
                            dismiss()
                            model.startGpsTracking()
                        } label: {
                            // 不放 ProgressView：那是「当前处于跟随模式」的状态标记，不是加载进度，
                            // 一直转会让人误以为在定位。三端统一去掉，靠点击行为表达。
                            Text(model.trackingGps ? L("settings.gpsRestart") : L("settings.gpsStart"))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(ThemedPrimaryButtonStyle())
                        .padding(.top, 4)
                    }

                    section(title: L("settings.sectionManual")) {
                        // 输入框底色/描边/文字/光标/占位符全部取主题色，不跟系统外观 ——
                        // 用系统 `.roundedBorder` 时，暗色主题下会是白底 + 浅色字（看不清）。
                        HStack(spacing: 12) {
                            ThemedTextField(placeholder: L("settings.latitude"), text: $latitudeText)
                            ThemedTextField(placeholder: L("settings.longitude"), text: $longitudeText)
                        }

                        if let errorText {
                            Text(errorText)
                                .font(.system(size: 12))
                                .foregroundStyle(palette.danger)
                        }

                        Button(L("settings.applyCoordinates")) { applyManual() }
                            .buttonStyle(ThemedPrimaryButtonStyle())

                        // 常用城市按**大洲分组**（与 Android / 鸿蒙一致）：组标题 11pt、
                        // 组间上间距 10、标题与 chips 间距 4；组内仍是内容宽 chip + 自动换行。
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(CityRegion.allCases) { region in
                                let cities = Place.presets.filter { $0.region == region }
                                if !cities.isEmpty {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(region.title)
                                            .font(.system(size: 11))
                                            .foregroundStyle(palette.onSurfaceVariant)
                                        FlowLayout(spacing: 8, lineSpacing: 8) {
                                            ForEach(cities, id: \.presetKey) { preset in
                                                Button(preset.displayLabel) {
                                                    model.usePreset(preset)
                                                    dismiss()
                                                }
                                                .buttonStyle(ThemedChipButtonStyle())
                                            }
                                        }
                                    }
                                    .padding(.top, region == CityRegion.allCases.first ? 0 : 10)
                                }
                            }
                        }
                        .padding(.top, 4)
                        .padding(.top, 4)
                    }

                    section(title: L("settings.sectionMap")) {
                        Text(L("settings.mapHint"))
                            .font(.system(size: 12))
                            .foregroundStyle(palette.onSurfaceVariant)

                        FlowLayout(spacing: 8, lineSpacing: 8) {
                            ForEach(MapStyle.selectable) { style in
                                Button(style.label) { model.setMapStyle(style) }
                                    .buttonStyle(ThemedChipButtonStyle(isSelected: style == model.mapStyle))
                            }
                        }
                    }

                    // **独立 section**：天气数据源（不要塞进地图那块，否则说明文字与芯片同行会互相挤压）。
                    section(title: L("settings.weatherSource")) {
                        // 说明文字整行宽、可换行；芯片另起一行。
                        Text(L("weather.sourceHint"))
                            .font(.system(size: 12))
                            .foregroundStyle(palette.onSurfaceVariant)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        FlowLayout(spacing: 8, lineSpacing: 8) {
                            ForEach(WeatherSourceSetting.allCases) { setting in
                                Button(setting.label) { model.setWeatherSource(setting) }
                                    .buttonStyle(ThemedChipButtonStyle(isSelected: setting == model.weatherSourceSetting))
                                    // 芯片不参与压缩：文字完整（必要时空出宽度换行到下一格）。
                                    .fixedSize()
                            }
                        }
                    }

                    section(title: L("settings.sectionReminders")) {
                        Toggle(isOn: remindersBinding) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L("settings.shichenTitle"))
                                    .font(.system(size: 15))
                                Text(L("settings.shichenDesc"))
                                    .font(.system(size: 12))
                                    .foregroundStyle(palette.onSurfaceVariant)
                            }
                        }

                        Toggle(isOn: keyTimeChimeBinding) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L("settings.keyTimeTitle"))
                                    .font(.system(size: 15))
                                Text(L("settings.keyTimeDesc"))
                                    .font(.system(size: 12))
                                    .foregroundStyle(palette.onSurfaceVariant)
                            }
                        }
                    }

                    ThemedDivider()

                    section(title: L("settings.sectionScreen")) {
                        Toggle(isOn: keepScreenOnBinding) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L("settings.keepScreenOn"))
                                    .font(.system(size: 15))
                                Text(L("settings.keepScreenOnDesc"))
                                    .font(.system(size: 12))
                                    .foregroundStyle(palette.onSurfaceVariant)
                            }
                        }

                        // 主题三态与「屏幕常亮」同一片区：自动（默认，按日出日落）/ 亮色 / 暗色。
                        // 强制模式只是忽略日出日落，其余渲染逻辑完全一样；写进设置存储，重启保留。
                        ThemedDivider()
                            .padding(.vertical, 2)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(L("settings.themeTitle"))
                                .font(.system(size: 15))
                            Text(L("settings.themeDesc"))
                                .font(.system(size: 12))
                                .foregroundStyle(palette.onSurfaceVariant)

                            FlowLayout(spacing: 8, lineSpacing: 8) {
                                ForEach(ThemeMode.allCases, id: \.self) { mode in
                                    Button(mode.label) { model.setThemeMode(mode) }
                                        .buttonStyle(ThemedChipButtonStyle(isSelected: mode == model.themeMode))
                                }
                            }
                        }
                    }

                    // 「诊断」默认整个隐藏（连标题、三行状态与「立即同步关键时间」按钮一起）：
                    // 只有连点 7 次首页版本号后 `model.showDiagnostics` 才为 true，
                    // 而且是本次 App 生命周期内的内存开关，重启回到隐藏。
                    // 诊断的代码全部保留，只是默认没有入口。
                    if model.showDiagnostics {
                        ThemedDivider()

                        section(title: L("settings.sectionDiagnostics")) {
                            VStack(alignment: .leading, spacing: 6) {
                                diagnosticLine(title: L("settings.diagWeather"), value: WeatherStore.shared.diagnosticsSummary())
                                // 天气用哪个源、几小时一格、数据有多旧、最近一次为什么失败 ——
                                // 排查「天气不刷新 / 时间对不上」先看这四行。
                                diagnosticLine(title: L("settings.diagSource"), value: WeatherStore.shared.sourceSummary())
                                diagnosticLine(title: L("settings.diagAge"), value: WeatherStore.shared.ageSummary())
                                diagnosticLine(title: L("settings.diagHourly"), value: WeatherStore.shared.hourlyDiagnostics())
                                diagnosticLine(title: L("settings.weatherDiagSource"), value: WeatherStore.shared.weatherKitSummary())
                                diagnosticLine(title: L("settings.diagLastFailure"), value: WeatherStore.shared.failureSummary())
                                diagnosticLine(title: L("settings.diagAttribution"), value: WeatherAttributionStore.shared.diagnosticsSummary())
                                diagnosticLine(title: L("settings.diagDistrict"), value: districtSummary)
                                diagnosticLine(title: L("settings.diagKeyTime"), value: keyTimeSummary)
                                // 报时是否真的排进了系统队列：授权状态 + 待发条数 + 最近一条的时刻。
                                // 「没声音」十次有九次是这里没有待发通知（没排上 / 权限被关）。
                                diagnosticLine(
                                    title: L("settings.diagChime"),
                                    value: KeyTimeReminder.diagnosticsSummary
                                )
                                // 地图底图：实际源（含「OSM 失败 3 次后回退」）、状态、缩放降级、
                                // 首选源、OSM 失败次数、空白瓦片判定次数、下次探测时间。
                                diagnosticLine(
                                    title: L("map.diagBasemap"),
                                    value: BasemapController.shared.diagnosticsSummary()
                                )
                                diagnosticLine(title: "", value: BasemapController.shared.diagnosticsDetail())
                                // 地图**自证**行：未知态/正常态 · 中心 · 跨度 · 缩放 · 标记数 · 源。
                                // 用户截图一眼就能判断是「视口没动」还是「标记没清」。
                                diagnosticLine(
                                    title: L("map.diagMapTitle"),
                                    value: BasemapController.shared.mapDiagnostics
                                )
                            }
                            .font(.system(size: 12))
                            .foregroundStyle(palette.onSurfaceVariant)

                            // 抓取失败时不用等下一次自动重试：现场手动抓一次，结果立刻写回上面那几行。
                            Button {
                                model.refreshKeyTime()
                            } label: {
                                Text(L("settings.syncKeyTime"))
                            }
                            .buttonStyle(ThemedChipButtonStyle())
                        }
                    }

                    ThemedDivider()

                    section(title: L("settings.sectionAbout")) {
                        // 署名标识图按需加载（进程内只拉一次；失败退化成文字）。
                        let _ = WeatherAttributionStore.shared.loadIfNeeded()
                        Text(L("settings.aboutBody"))
                            .font(.system(size: 12))
                            .foregroundStyle(palette.onSurfaceVariant)

                        // 数据来源署名（许可要求的合规标注）：首页那行已按用户要求去掉，
                        // 这一句必须留着 —— 主源 Open-Meteo 是 CC BY 4.0，降级到 7Timer! 之后
                        // 不能再写 Open-Meteo，所以文案跟着 `AppModel.weatherAttribution` 切换。
                        Text(model.weatherAttribution)
                            .font(.system(size: 12))
                            .foregroundStyle(palette.onSurfaceVariant)
                            .padding(.top, 2)
                    }
                }
                .padding(20)
            }
            .background(palette.background.ignoresSafeArea())
            .foregroundStyle(palette.onSurface)
            // 「通知权限没开」这类消息是在这一页产生的；设置页是 sheet，会盖住主界面的
            // Toast，所以这里自己挂一个（同一套 Toast，1.8 秒自动消失、不拦点击）。
            .toast(message: $model.message)
            .navigationTitle(L("settings.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("settings.done")) { dismiss() }
                }
            }
            .onAppear {
                latitudeText = String(format: "%.4f", model.place.latitude)
                longitudeText = String(format: "%.4f", model.place.longitude)
            }
        }
        // 开关、导航栏「完成」等系统控件也用主题强调色（否则强制主题下会露出系统默认蓝）。
        .tint(palette.primary)
    }

    private var remindersBinding: Binding<Bool> {
        Binding(
            get: { model.remindersEnabled },
            set: { enabled in
                guard enabled else {
                    model.setRemindersEnabled(false)
                    return
                }
                requestAuthorization { granted in
                    model.setRemindersEnabled(granted)
                    if !granted {
                        model.message = L("settings.notifDeniedReminders")
                    }
                }
            }
        )
    }

    private var keyTimeChimeBinding: Binding<Bool> {
        Binding(
            get: { model.keyTimeChimeEnabled },
            set: { enabled in
                guard enabled else {
                    model.setKeyTimeChimeEnabled(false)
                    return
                }
                requestAuthorization { granted in
                    model.setKeyTimeChimeEnabled(granted)
                    if !granted {
                        model.message = L("settings.notifDeniedChime")
                    }
                }
            }
        )
    }

    // MARK: - 诊断

    private func diagnosticLine(title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(title)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var districtSummary: String {
        let text = model.districtName?.full ?? L("common.none")
        // 带上来源（Apple / OSM 兜底）、失败原因与 CLGeocoder 的原始字段：
        // 境外坐标只有真机能验证，界面上能看到这些才好判断是「只回了国家」还是「直接报错」。
        return "\(text) · \(DistrictStore.shared.diagnosticsSummary())"
    }

    private var keyTimeSummary: String {
        let status = model.keyTimeStatus
        return status.isEmpty ? L("keytime.st.never") : status
    }

    private var keepScreenOnBinding: Binding<Bool> {
        Binding(
            get: { model.keepScreenOn },
            set: { model.setKeepScreenOn($0) }
        )
    }

    private func requestAuthorization(_ completion: @escaping (Bool) -> Void) {
        Task {
            let granted = await KeyTimeReminder.shared.requestAuthorization()
            await MainActor.run { completion(granted) }
        }
    }

    private func applyManual() {
        guard let latitude = Double(latitudeText.trimmingCharacters(in: .whitespaces)),
              let longitude = Double(longitudeText.trimmingCharacters(in: .whitespaces)) else {
            errorText = L("settings.errorLatLon")
            return
        }
        guard (Place.minLatitude...Place.maxLatitude).contains(latitude) else {
            errorText = L("settings.errorLatRange")
            return
        }
        guard (Place.minLongitude...Place.maxLongitude).contains(longitude) else {
            errorText = L("settings.errorLonRange")
            return
        }
        errorText = nil
        model.applyManualPlace(latitude: latitude, longitude: longitude, label: L("settings.manualLabel"))
        dismiss()
    }

    /// 设置页「关于」里的天气署名（与卡片页脚同源：`WeatherAttributionStore`）。
    @ViewBuilder private var weatherAttributionAbout: some View {
        let presentation = WeatherAttributionStore.shared.presentation(
            source: WeatherStore.shared.source,
            isDark: !model.uiIsDay
        )
        switch presentation {
        case .mark(_, _, let legal):
            if let url = URL(string: presentation.markURL(isDark: !model.uiIsDay) ?? ""),
               let link = URL(string: legal) {
                Link(destination: link) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image): image.resizable().scaledToFit().frame(height: 11.5)
                        default: Text(model.weatherAttributionText).font(.system(size: 12))
                        }
                    }
                }
            } else {
                Text(model.weatherAttributionText).font(.system(size: 12))
            }
        case .text(let text, let link):
            if let link, let url = URL(string: link) {
                Link(text, destination: url).font(.system(size: 12))
            } else {
                Text(text).font(.system(size: 12))
            }
        }
    }
    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                // 与 Android 的 `colorScheme.primary` 一致：系统的 `.orange` 在浅色底上只有 2.2:1。
                .foregroundStyle(palette.primary)
            content()
        }
    }
}
