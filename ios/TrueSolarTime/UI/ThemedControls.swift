import SwiftUI
import UIKit

/// 跟随**主题**（而不是系统外观）的基础控件外观。
///
/// 系统控件（`.roundedBorder` 输入框、`.bordered` / `.borderedProminent` 按钮、`Divider()`、
/// `.secondary` 文字）取的是**系统浅色/深色**，与本 App「按日出日落（或用户强制）」的主题无关。
/// 两者一旦不一致（系统浅色 + App 暗色主题非常常见），就会出现白底输入框 + 浅色字、
/// 浅灰按钮 + 浅色字这类「看不清」的问题 —— 所以这些控件统一在这里按下述 token 重绘：
///
/// | 部位 | token |
/// | --- | --- |
/// | 输入框底色 / 描边 / 文字 / 占位符 / 光标 | `fieldBackground` / `fieldBorder` / `fieldText` / `fieldPlaceholder` / `primary` |
/// | 按钮（chip）底色 / 描边 / 文字 | `surface` / `outlineVariant`（选中时改为 `primary` 系） |
/// | 主按钮底色 / 文字 | `primary` / `onPrimary` |
/// | 分隔线 | `outlineVariant` |
///
/// 色值本身在 `Core/ThemeColors.swift`，自检会对亮/暗两套取值与对比度做断言。

// MARK: - 输入框

/// 经纬度输入框：底色、描边、文字、**光标**、占位符全部取主题色。
///
/// 占位符必须自己画：`TextField` 的 placeholder 用的是系统的 secondary 文字色，
/// 深色输入框配上系统浅色外观时会变成「深灰字压深蓝底」。
struct ThemedTextField: View {

    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .numbersAndPunctuation

    @Environment(\.palette) private var palette

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(.system(size: 15))
                    .foregroundStyle(palette.fieldPlaceholder)
                    .lineLimit(1)
                    .allowsHitTesting(false)
            }

            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundStyle(palette.fieldText)
                .tint(palette.primary) // 光标与选区颜色
                .keyboardType(keyboardType)
                .accessibilityLabel(placeholder)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(shape.fill(palette.fieldBackground))
        .overlay(shape.stroke(palette.fieldBorder, lineWidth: 1))
        .contentShape(shape)
    }
}

// MARK: - 按钮

/// chip 按钮（常用城市、地图底图、主题三选、「立即同步关键时间」）。
///
/// 选中态不用系统 tint（那会跟着系统外观变），而是 `primary` 的文字 + 18% 底 + `primary` 描边。
struct ThemedChipButtonStyle: ButtonStyle {

    var isSelected: Bool = false

    @Environment(\.palette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return configuration.label
            .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? palette.primary : palette.onSurface)
            // **按内容宽度**（不再撑满列宽），也不缩字号：放不下由外层 `FlowLayout` 换行。
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(shape.fill(isSelected ? palette.primary.opacity(0.18) : palette.surface))
            .overlay(shape.stroke(isSelected ? palette.primary : palette.outlineVariant, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.72 : 1)
            .contentShape(shape)
    }
}

/// 主按钮（「使用 GPS 定位」「应用坐标」）：`primary` 底色 + `onPrimary` 文字。
///
/// 文字色必须显式给：夜里 `primary` 是淡金（#F5D68A），沿用白色只有 1.4:1。
struct ThemedPrimaryButtonStyle: ButtonStyle {

    @Environment(\.palette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(palette.onPrimary)
            .tint(palette.onPrimary) // 里面的 ProgressView 也跟着走
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(shape.fill(palette.primary))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(shape)
    }
}

// MARK: - 分隔线

/// 主题分隔线：系统 `Divider()` 的颜色跟着系统外观，暗色主题下常年偏亮或偏暗。
struct ThemedDivider: View {

    @Environment(\.palette) private var palette

    var body: some View {
        Rectangle()
            .fill(palette.outlineVariant)
            .frame(height: 1)
    }
}
