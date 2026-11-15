import SwiftUI

struct SettingsView: View {

    @Environment(\.palette) private var palette

    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var latitudeText = ""
    @State private var longitudeText = ""
    @State private var errorText: String?

    private let chipColumns = [GridItem(.adaptive(minimum: 84), spacing: 8)]

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
                            HStack {
                                if model.trackingGps {
                                    ProgressView()
                                }
                                Text(model.trackingGps ? L("settings.gpsRestart") : L("settings.gpsStart"))
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 4)
                    }

                    section(title: L("settings.sectionManual")) {
                        HStack(spacing: 12) {
                            TextField(L("settings.latitude"), text: $latitudeText)
                                .keyboardType(.numbersAndPunctuation)
                                .textFieldStyle(.roundedBorder)
                            TextField(L("settings.longitude"), text: $longitudeText)
                                .keyboardType(.numbersAndPunctuation)
                                .textFieldStyle(.roundedBorder)
                        }

                        if let errorText {
                            Text(errorText)
                                .font(.system(size: 12))
                                .foregroundStyle(.red)
                        }

                        Button(L("settings.applyCoordinates")) { applyManual() }
                            .buttonStyle(.borderedProminent)
                            .frame(maxWidth: .infinity)

                        LazyVGrid(columns: chipColumns, alignment: .leading, spacing: 8) {
                            ForEach(Place.presets, id: \.presetKey) { preset in
                                Button(preset.displayLabel) {
                                    model.usePreset(preset)
                                    dismiss()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                        .padding(.top, 4)
                    }

                    section(title: L("settings.sectionMap")) {
                        Text(L("settings.mapHint"))
                            .font(.system(size: 12))
                            .foregroundStyle(palette.onSurfaceVariant)

                        LazyVGrid(columns: chipColumns, alignment: .leading, spacing: 8) {
                            ForEach(MapStyle.allCases) { style in
                                Button(style.label) { model.setMapStyle(style) }
                                    .buttonStyle(.bordered)
                                    .tint(style == model.mapStyle ? Color.orange : Color.gray)
                                    .controlSize(.small)
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

                    Divider()

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
                    }

                    // 「诊断」默认整个隐藏（连标题、三行状态与「立即同步关键时间」按钮一起）：
                    // 只有连点 7 次首页版本号后 `model.showDiagnostics` 才为 true，
                    // 而且是本次 App 生命周期内的内存开关，重启回到隐藏。
                    // 诊断的代码全部保留，只是默认没有入口。
                    if model.showDiagnostics {
                        Divider()

                        section(title: L("settings.sectionDiagnostics")) {
                            VStack(alignment: .leading, spacing: 6) {
                                diagnosticLine(title: L("settings.diagWeather"), value: WeatherStore.shared.diagnosticsSummary())
                                diagnosticLine(title: L("settings.diagDistrict"), value: districtSummary)
                                diagnosticLine(title: L("settings.diagKeyTime"), value: keyTimeSummary)
                            }
                            .font(.system(size: 12))
                            .foregroundStyle(palette.onSurfaceVariant)

                            // 抓取失败时不用等下一次自动重试：现场手动抓一次，结果立刻写回上面那几行。
                            Button {
                                model.refreshKeyTime()
                            } label: {
                                Text(L("settings.syncKeyTime"))
                                    .font(.system(size: 12))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }

                    Divider()

                    section(title: L("settings.sectionAbout")) {
                        Text(L("settings.aboutBody"))
                            .font(.system(size: 12))
                            .foregroundStyle(palette.onSurfaceVariant)
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
                .frame(width: 56, alignment: .leading)
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

    @ViewBuilder
    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.orange)
            content()
        }
    }
}
