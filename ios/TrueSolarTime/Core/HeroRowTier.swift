import Foundation

/// 首页大卡片顶部那一行（`UTC+8` · 行政区划 · `真太阳时` · 时辰）的退化规则。
///
/// 这一行是**整行一个逻辑单元**（不是左右两列各自一行）。四段文本的相对位置随行宽分 4 档，
/// 与 Android `SmallRowLayout.cityRowTier` / `dividerReachesLabelRow` 逐条对应；本文件是纯函数，
/// 不依赖 SwiftUI，便于离线断言。
///
/// - 档 0（四段都放得下）：整行分左右两半（各占整行一半，与下面两列等宽一致）。
///   左半 `UTC` 贴左、城市贴右（贴着两半分界）；右半 `真太阳时` 贴左、时辰贴右。
/// - 档 1（城市超过左半）：**收掉「真太阳时」**，整行合一 —— `UTC` 贴左、**城市居中**、时辰贴右。
/// - 档 2（连 UTC + 城市 + 时辰 都放不下）：**再收掉 UTC** —— 城市贴左、时辰贴右。
/// - 档 3（仍放不下）：排布同档 2，城市尾部省略号。
///
/// **任何档位时辰都保留**，且始终贴整行最右。
enum HeroRowTier {

    /// 相邻两段文本之间的间距（pt）。与 Android 的 `cityRowGap = 8.dp` 一致。
    static let gap: CGFloat = 8

    /// 档 0 里城市与竖分隔线之间让出的间隙（pt）。
    ///
    /// 竖线正落在两半分界上，右半「真太阳时」从分界右侧 8pt 起排，左侧再留 6pt，
    /// 线两侧都不会贴着字。判档时必须把它计入城市宽度，否则那一档会「看起来刚好放下、
    /// 实际被挤掉 6pt」。
    static let cityEndInset: CGFloat = 6

    /// 竖分隔线在时钟行里的上内边距（pt），与 Android 的 `dividerTopPadding` 一致。
    static let dividerTopPadding: CGFloat = 3

    enum Tier: Int, CaseIterable {
        /// 四段都放得下：左右各半。
        case allFour = 0
        /// 收掉「真太阳时」：UTC 贴左、城市居中、时辰贴右。
        case noSolarLabel = 1
        /// 再收掉 UTC：城市贴左、时辰贴右。
        case cityAndShichen = 2
        /// 同档 2，城市尾部省略号。
        case cityTruncated = 3
    }

    /// 屏幕上实际会出现的四段文本。
    enum Label {
        case utc
        case city
        case solarLabel
        case shichen
    }

    // MARK: - 判档

    /// 判档。所有宽度都是**自然宽度**（pt），`rowWidth` 是整行可用宽度（还没量出来时传 0）。
    ///
    /// 与 Android 的差异只有一处：那个实现由调用方把 6pt 间隙与 8pt 间距预先加进
    /// `wCity` / `wLabel`，这里把 `cityEndInset`、`gap` 收进函数内部，签名更完整、也更好断言；
    /// 判据本身逐项一致。
    static func tier(
        utcWidth: CGFloat,
        cityWidth: CGFloat,
        labelWidth: CGFloat,
        shichenWidth: CGFloat,
        rowWidth: CGFloat,
        gap: CGFloat = HeroRowTier.gap,
        cityEndInset: CGFloat = HeroRowTier.cityEndInset
    ) -> Tier {
        // 行宽还没量出来（第一帧）：先按档 0 排，免得闪一下「只剩城市」。
        guard rowWidth > 0 else { return .allFour }
        let utc = max(utcWidth, 0)
        // 档 0 里城市右侧要让出间隙；城市本身为空（宽度 0）时不算这个间隙。
        let city = cityWidth > 0 ? cityWidth + max(cityEndInset, 0) : 0
        // 档 0 的右半从两半分界处起排，先让一个间距，所以标签宽度也要加上间距。
        let label = max(labelWidth, 0) + max(gap, 0)
        let shichen = max(shichenWidth, 0)
        let space = max(gap, 0)
        let half = rowWidth / 2

        // 档 0：两半各自装得下 —— 左半 UTC + 间距 + 城市，右半 真太阳时 + 间距 + 时辰。
        if utc + city + space <= half && label + shichen + space <= half { return .allFour }
        // 档 1：收掉「真太阳时」后，UTC + 城市 + 时辰 在整行内放得下。
        if utc + city + shichen + 2 * space <= rowWidth { return .noSolarLabel }
        // 档 2：再收掉 UTC，城市 + 时辰 在整行内放得下。
        if city + shichen + space <= rowWidth { return .cityAndShichen }
        return .cityTruncated
    }

    /// 这一档还要不要显示 `UTC+8`（档 2 / 3 收掉）。
    static func showsUTC(tier: Tier) -> Bool {
        tier == .allFour || tier == .noSolarLabel
    }

    /// 这一档还要不要显示「真太阳时」（只有档 0 显示）。
    static func showsSolarLabel(tier: Tier) -> Bool {
        tier == .allFour
    }

    /// 这一档实际可见的文本段（按整行从左到右的顺序）。**时辰永远在里面。**
    static func labels(tier: Tier) -> [Label] {
        var result: [Label] = []
        if showsUTC(tier: tier) { result.append(.utc) }
        result.append(.city)
        if showsSolarLabel(tier: tier) { result.append(.solarLabel) }
        // 时辰任何档位都保留，且始终贴整行最右。
        result.append(.shichen)
        return result
    }

    /// 城市这一档要不要居中（只有档 1 居中；档 0 贴右、档 2/3 贴左）。
    static func cityCentered(tier: Tier) -> Bool {
        tier == .noSolarLabel
    }

    // MARK: - 竖分隔线

    /// 竖分隔线要不要向上延伸到标签行顶部。只有档 0 需要：
    /// 那一档标签行仍是左右两半，两半的分界**就是**下面两列的分界，
    /// 线从标签行顶部一路贯下来，才正好落在「城市」与「真太阳时」之间。
    static func dividerReachesLabelRow(tier: Tier) -> Bool {
        tier == .allFour
    }

    /// 竖分隔线的位置与长度（相对「标签行 + 时钟行」这个整体的顶端）。
    struct DividerGeometry: Equatable {
        /// 线的顶端（pt）。
        var top: CGFloat
        /// 线的长度（pt）。
        var height: CGFloat
    }

    /// 计算竖分隔线的几何。
    ///
    /// - 档 0：**总高度 = 标签行高 + 时钟行高**，上端与「真太阳时」文字的上沿齐平
    ///   （`labelTopInset` = 行盒里字形上沿之上的空白，而不是行盒顶边）；
    /// - 档 1~3：只覆盖下方两列（时钟行），即从标签行底边开始、长度等于时钟行高。
    ///
    /// 两段都相对「标签行 + 时钟行」这个整体的顶端定位，调用方直接 `offset(y: top)` 即可。
    static func divider(
        tier: Tier,
        labelRowHeight: CGFloat,
        clockRowHeight: CGFloat,
        labelTopInset: CGFloat
    ) -> DividerGeometry {
        let labelRow = max(labelRowHeight, 0)
        let clockRow = max(clockRowHeight, 0)
        guard dividerReachesLabelRow(tier: tier) else {
            return DividerGeometry(top: labelRow, height: clockRow)
        }
        let top = max(labelTopInset, 0)
        return DividerGeometry(top: top, height: max(labelRow + clockRow - top, 0))
    }
}
