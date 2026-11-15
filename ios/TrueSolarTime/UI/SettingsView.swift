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
                    section(title: "当前位置") {
                        Text("\(model.place.label)　\(TimeFormat.coordinates(latitude: model.place.latitude, longitude: model.place.longitude))")
                            .font(.system(size: 15))

                        Button {
                            dismiss()
                            model.startGpsTracking()
                        } label: {
                            HStack {
                                if model.trackingGps {
                                    ProgressView()
                                }
                                Text(model.trackingGps ? "重新开始跟随 GPS" : "使用 GPS 自动定位")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 4)
                    }

                    section(title: "手动设置经纬度") {
                        HStack(spacing: 12) {
                            TextField("纬度", text: $latitudeText)
                                .keyboardType(.numbersAndPunctuation)
                                .textFieldStyle(.roundedBorder)
                            TextField("经度", text: $longitudeText)
                                .keyboardType(.numbersAndPunctuation)
                                .textFieldStyle(.roundedBorder)
                        }

                        if let errorText {
                            Text(errorText)
                                .font(.system(size: 12))
                                .foregroundStyle(.red)
                        }

                        Button("应用坐标") { applyManual() }
                            .buttonStyle(.borderedProminent)
                            .frame(maxWidth: .infinity)

                        LazyVGrid(columns: chipColumns, alignment: .leading, spacing: 8) {
                            ForEach(Place.presets, id: \.label) { preset in
                                Button(preset.label) {
                                    model.usePreset(preset)
                                    dismiss()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                        .padding(.top, 4)
                    }

                    section(title: "地图底图") {
                        Text("自动：境内用高德，境外用 OpenStreetMap")
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

                    section(title: "提醒") {
                        Toggle(isOn: remindersBinding) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("时辰交接提醒")
                                    .font(.system(size: 15))
                                Text("每个时辰交接时准时提醒（250 ms 蜂鸣）")
                                    .font(.system(size: 12))
                                    .foregroundStyle(palette.onSurfaceVariant)
                            }
                        }

                        Toggle(isOn: keyTimeChimeBinding) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("进入关键时间报时")
                                    .font(.system(size: 15))
                                Text("每到一段关键时间的起点提醒（500 ms 蜂鸣）")
                                    .font(.system(size: 12))
                                    .foregroundStyle(palette.onSurfaceVariant)
                            }
                        }
                    }

                    Divider()

                    section(title: "屏幕") {
                        Toggle(isOn: keepScreenOnBinding) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("屏幕常亮")
                                    .font(.system(size: 15))
                                Text("应用打开期间不自动熄屏（会更耗电）")
                                    .font(.system(size: 12))
                                    .foregroundStyle(palette.onSurfaceVariant)
                            }
                        }
                    }

                    Divider()

                    section(title: "诊断") {
                        VStack(alignment: .leading, spacing: 6) {
                            diagnosticLine(title: "天气", value: WeatherStore.shared.diagnosticsSummary())
                            diagnosticLine(title: "区划名", value: districtSummary)
                            diagnosticLine(title: "关键时间", value: keyTimeSummary)
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(palette.onSurfaceVariant)

                        // 抓取失败时不用等下一次自动重试：现场手动抓一次，结果立刻写回上面那几行。
                        Button {
                            model.refreshKeyTime()
                        } label: {
                            Text("立即同步关键时间")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Divider()

                    section(title: "关于计算") {
                        Text("真太阳时按太阳的真实位置计时：先由当地经度相对东经 120° 的偏差修正时差（每 1° 相差 4 分钟），再叠加因地球轨道偏心率与黄赤交角产生的均时差。十二时辰按真太阳时划分，子时自 23:00 起，每两小时一个时辰。")
                            .font(.system(size: 12))
                            .foregroundStyle(palette.onSurfaceVariant)
                    }
                }
                .padding(20)
            }
            .background(palette.background.ignoresSafeArea())
            .foregroundStyle(palette.onSurface)
            .navigationTitle("位置与提醒")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
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
                        model.message = "未授予通知权限，提醒可能无法显示"
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
                        model.message = "未授予通知权限，报时可能无法显示"
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
        let text = model.districtName?.full ?? "暂无"
        // 带上来源（Apple / OSM 兜底）、失败原因与 CLGeocoder 的原始字段：
        // 境外坐标只有真机能验证，界面上能看到这些才好判断是「只回了国家」还是「直接报错」。
        return "\(text) · \(DistrictStore.shared.diagnosticsSummary())"
    }

    private var keyTimeSummary: String {
        let status = model.keyTimeStatus
        return status.isEmpty ? "尚未抓取" : status
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
            errorText = "请输入有效的经纬度数值"
            return
        }
        guard (Place.minLatitude...Place.maxLatitude).contains(latitude) else {
            errorText = "纬度需为 -90 至 90 之间的数值"
            return
        }
        guard (Place.minLongitude...Place.maxLongitude).contains(longitude) else {
            errorText = "经度需为 -180 至 180 之间的数值"
            return
        }
        errorText = nil
        model.applyManualPlace(latitude: latitude, longitude: longitude, label: "手动设置")
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
