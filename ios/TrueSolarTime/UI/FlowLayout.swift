import SwiftUI

/// 流式布局：chip **按内容宽度**排列，一行放不下就换行（行内左对齐、chip 间距 / 行距可配）。
///
/// 为什么不用 `LazyVGrid(.adaptive(minimum: 84))`：iPhone 上会排成 4 列、每列约 84pt，
/// 而 chip 里又被 `.frame(maxWidth: .infinity)` 撑满列宽 —— 英文长标签（`Apple Weather`、
/// `Open-Meteo`、`AutoNavi vector`）装不下就会溢出 / 与隔壁 chip 连成一片（英文界面实测）。
///
/// 语义：每个 chip 用**自然宽度**，行内放不下就换行；不放不下的单个 chip（比整行还宽）才截断。
struct FlowLayout: Layout {

    /// chip 之间的水平间距。
    var spacing: CGFloat = 8
    /// 行与行之间的垂直间距。
    var lineSpacing: CGFloat = 8
    /// 行内对齐方式（默认左对齐）。
    var alignment: HorizontalAlignment = .leading

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = arrange(subviews: subviews, maxWidth: maxWidth)
        let height = rows.reduce(CGFloat.zero) { $0 + $1.height } +
            lineSpacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: min(width, maxWidth), height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) {
        let rows = arrange(subviews: subviews, maxWidth: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x: CGFloat
            switch alignment {
            case .center:
                x = bounds.minX + (bounds.width - row.width) / 2
            case .trailing:
                x = bounds.minX + bounds.width - row.width
            default:
                x = bounds.minX
            }
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    // MARK: - 排布

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            // **自然宽度**：不传 proposal，让 chip 按内容决定大小。
            let size = subviews[index].sizeThatFits(.unspecified)
            let extra = current.indices.isEmpty ? size.width : size.width + spacing
            if !current.indices.isEmpty, current.width + extra > maxWidth {
                rows.append(current)
                current = Row()
            }
            if current.indices.isEmpty {
                current.width = size.width
            } else {
                current.width += size.width + spacing
            }
            current.indices.append(index)
            current.height = max(current.height, size.height)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
