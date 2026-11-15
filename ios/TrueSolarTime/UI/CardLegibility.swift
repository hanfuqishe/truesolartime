import SwiftUI

/// 卡片区与「辅助功能 → 粗体文本」的隔离层。
///
/// 为什么需要它：卡片是「版式即内容」的界面 —— 数字要正好撑满一栏、行高与竖分隔线都按固定
/// em 算出来、顶部标签行还要按文字宽度分档退化。系统级的「粗体文本」
/// （设置 → 辅助功能 → 显示与文字大小 → 粗体文本）会把**系统字体**整体换成更粗的字面，
/// 笔画变粗、字宽也会变，上面这些假设全部失效（Android 端实测同一行墨迹 +10~14%）。
///
/// iOS 的卡片字号是固定的 `.system(size:)`，**不跟 Dynamic Type**（「更大字体」只影响
/// `.body` / `.title` 这类文本样式），所以这里唯一要处理的就是粗体文本。
///
/// 处理方式不是自带字体，而是官方开关：SwiftUI 把「粗体文本」原样暴露成环境值
/// `legibilityWeight`（Apple 文档 *LegibilityWeight*：`.regular` = "Use regular font weight
/// (no Accessibility Bold)"），并明确写了 **iOS 16 起 App 可以覆盖用户的选择**
/// （"The app can't override the user's choice before iOS 16"）。本工程的最低版本就是
/// iOS 16.0，所以把卡片子树的这个环境值钉成 `.regular` 即可 —— 不换字面、不动行盒、
/// 不增加安装包体积，比塞一份自带字体更贴合「版式即内容」的约束。
///
/// 页头、版本号、设置页**不套**这一层，仍跟随系统设置（与 Android 版「只锁卡片」一致）。
extension View {

    /// 让这个子树不跟随系统的「粗体文本」（iOS 16+）。
    func cardLegibilityRegular() -> some View {
        environment(\.legibilityWeight, .regular)
    }
}
