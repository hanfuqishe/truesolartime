import Foundation

/// 太阳卡圆盘的几何结果（纯数值，`Core` 里可脱离 UI 断言）。
///
/// 参数化（与 Android / 鸿蒙约定同一套模型）：
/// - **圆 = 一天 24 小时**，圆心 `C`、半径 `R`；
/// - 角度 `θ(t) = (t − 12h) / 24h × 360°`，像素坐标
///   `(x, y) = (C.x + R·sin θ, C.y − R·cos θ)` —— 屏幕 y 轴朝下，所以 `cos` 前面是减号，
///   于是 **12:00 在正上方、00:00 在正下方**（06:00 在圆左、18:00 在圆右）；
/// - **地平线是一条水平弦** `y_h = C.y − R·cos(θ(日出))`：昼长 12h 过圆心、>12h 下移、<12h 上移；
///   极昼沉到圆下方（`y_h > C.y + R`，整圆都是白天）、极夜升到圆上方（`y_h < C.y − R`，整圆都是夜晚）。
///
/// **边界情形（日出恰好 0:00）**：θ(0) = −180°，太阳点在圆的最下方 `(C.x, C.y + R)`；
/// `y_h = C.y − R·cos(−180°) = C.y + R`，于是地平线**与圆相切于最下方**（弦长为 0，
/// 日出、日落两个交点重合在圆底）。昼长 24 小时，整圆都在地平线以上。
///
/// 时刻一律是**当地真太阳时**的小时数（0…24，可带小数）：圆盘的轴线就是真太阳时，
/// 标准时间/时区不参与角度换算。
struct SunPath {
    /// 圆心（区域中央）。
    let center: CGPoint
    /// 半径 = `0.38 × min(宽, 高)`（画布是「内容宽 × 194」，所以实际按短边 194 算）。
    let radius: CGFloat
    /// 地平线的 y 坐标（水平弦所在高度）。
    let horizonY: CGFloat
    /// 当前太阳点（同一参数化求出，可能落在地平线以下）。
    let sunPoint: CGPoint
    /// 极昼：太阳整日不落，整圆都在地平线以上。
    let isPolarDay: Bool
    /// 极夜：太阳整日不出，整圆都在地平线以下。
    let isPolarNight: Bool
    /// 南半球：观察者面朝北，东在右、西在左，太阳从右往左走（逆时针）。
    /// 为 true 时所有点的 x 以圆心镜像（日出在右、日落在左）。
    let isSouthernHemisphere: Bool
}

/// 标签相对锚点的对齐方式：UI 用真正的 `Text` 排版，按这个把文字贴到锚点上。
enum SunPathLabelAlignment: Equatable {
    /// 右边界贴锚点、垂直居中：北半球日出的时间写在**左交点左侧**。
    case trailing
    /// 左边界贴锚点、垂直居中：北半球日落的时间写在**右交点右侧**。
    case leading
    /// 底边贴锚点、水平居中：上中天写在**圆顶点上方**。
    case bottom
    /// 中心贴锚点：极昼 / 极夜那一行在圆心。
    case center
}

/// 一个外侧标签的锚点。
struct SunPathLabel: Equatable {
    /// 画布坐标里的锚点。
    let point: CGPoint
    /// 文字相对锚点的对齐方式。
    let alignment: SunPathLabelAlignment
}

/// 圆盘上的四个标签锚点（坐标原点在画布左上角）。
struct SunPathLabels: Equatable {
    /// 日出：锚在交点外侧（北半球左交点左侧、右对齐；南半球右交点右侧、左对齐）；
    /// 极昼 / 极夜没有交点，为 nil。
    let sunrise: SunPathLabel?
    /// 日落：锚在交点外侧（北半球右交点右侧、左对齐；南半球左交点左侧、右对齐）；
    /// 极昼 / 极夜为 nil。
    let sunset: SunPathLabel?
    /// 上中天：底边离圆顶 8pt、水平居中；**极夜没有**（太阳整日不出）。
    let noon: SunPathLabel?
    /// 极昼 / 极夜时圆心那一行；正常日为 nil。
    let polar: SunPathLabel?
}

enum SunPathGeometry {

    /// 半径占「短边」的比例（±0.5pt 的自检就是守这个值）。
    /// 画布高度固定 194 → 半径 0.38 × 194 ≈ 73.7（与安卓同一档）。
    static let radiusRatio: CGFloat = 0.38

    /// 极昼 / 极夜时地平线离圆心的距离（单位：半径）。
    ///
    /// 必须 **> 1** 才能落到圆外（极昼在圆下方、极夜在圆上方）；
    /// 取 1.12 是为了在圆盘边框和地平线之间留一条窄缝，看得出「地平线在圆外」而不是「贴着圆」。
    /// 同时 1.12R 仍落在方框内（0.38 × 1.12 = 0.4256 < 0.5），不会被画布裁掉。
    static let polarHorizonRatio: CGFloat = 1.12

    // MARK: - 轨迹线线宽（UI 与自检共用同一组常量）

    /// 白天弧线宽：**1.6pt**（4.3 版是 2.5pt，用户反馈「轨迹线太粗」）。
    static let dayArcLineWidth: CGFloat = 1.6
    /// 夜晚虚线线宽：**1.5pt**。
    static let nightArcLineWidth: CGFloat = 1.5
    /// 夜晚虚线的间隔（与线宽同量级：原来 2.5pt 线配 5/5pt，1.5pt 配 **4/4pt**）。
    static let nightArcDash: [CGFloat] = [4, 4]

    // MARK: - 标签参数（UI 与自检共用同一组常量）

    /// 太阳点**实心核心**半径：时间轴「现在」圆点核心的**一半**（`SunHaloStyle.coreRadius`，2.75pt）。
    ///
    /// 真机上「5.5pt 核心 + 平铺柔光」偏大且没有渐变，所以太阳点单独缩到一半、外加径向渐变柔光；
    /// 时间轴那个点保持原样，两者**故意不同**。
    static var sunRadius: CGFloat { SunHaloStyle.coreRadius }
    /// 太阳点**柔光**外沿半径：核心的 2 倍（5.5pt）⇒ 整体直径 11pt。
    static var sunGlowRadius: CGFloat { SunHaloStyle.shared.endRadius }
    /// 太阳点光晕的起点半径 = 核心半径（光从核心边缘开始，不从圆心）。
    static var sunHaloStartRadius: CGFloat { SunHaloStyle.shared.startRadius }
    /// 地平线以下那个点：半径 = 核心半径（同尺寸），描边细一点（`sunHollowLineWidth`）。
    static var sunHollowRadius: CGFloat { SunHaloStyle.coreRadius }
    /// 地平线以下空心圈的描边宽度：1pt（不抢戏，也不留一道粗硬边）。
    static let sunHollowLineWidth: CGFloat = 1
    /// 日出 / 日落标签：锚点离交点 10pt、比交点抬高 10pt（让延伸的地平线从字下面过去）。
    static let labelOffsetX: CGFloat = 10
    static let labelOffsetY: CGFloat = 10
    /// 上中天标签：底边离圆顶的距离。
    static let noonGap: CGFloat = 8
    /// 短昼阈值（小时）与「圆顶下方一行」的中心偏移。
    static let shortDayHours: Double = 2
    static let shortDayRowOffset: CGFloat = 26

    /// 标签的「预算」尺寸：Core 只拿它做防重叠 / 越界断言，UI 用 `Text` 的自然宽度排。
    /// 宽度取英文最长那一版（`Sunrise 05:56`、`Solar noon 12:03`、`Midnight sun`）。
    static let sideLabelBudget = CGSize(width: 66, height: 14)
    static let noonLabelBudget = CGSize(width: 84, height: 14)
    static let polarLabelBudget = CGSize(width: 90, height: 16)

    /// 地平线在画布左右各留的边距：所有场景都画成 `画布宽 − 2 × 这个值` 的一条横线。
    static let horizonInset: CGFloat = 4

    // MARK: - 角度与坐标

    /// 把**真太阳时**的小时数换算成圆盘上的角度 θ。
    ///
    /// **单位：弧度**（直接喂给 `sin` / `cos`），不是度。
    /// 公式 `θ = (hour − 12) / 24 × 2π`，输入 0…24 时取值范围 (−π, π]：
    /// 12:00 → 0（圆顶）、06:00 → −π/2（圆左）、18:00 → +π/2（圆右）、00:00 → −π（圆底）。
    static func angleOfDayHour(_ hour: Double) -> Double {
        let halfDayOffset = (hour - 12.0).truncatingRemainder(dividingBy: 24.0)
        return halfDayOffset / 24.0 * 2.0 * Double.pi
    }

    /// 圆盘上角度 θ（弧度）对应的像素点。
    ///
    /// **半球决定 x 的方向**：北半球 `x = C.x + R·sin θ`（06:00 在左、18:00 在右，太阳从左往右）；
    /// 南半球观察者面朝北，东在右、西在左，所以 `x = C.x − R·sin θ`（太阳从右往左，逆时针）。
    /// 两种情况下 y 都是 `C.y − R·cos θ`：12:00 在圆顶、00:00 在圆底，与半球无关。
    static func point(
        center: CGPoint,
        radius: CGFloat,
        theta: Double,
        southernHemisphere: Bool = false
    ) -> CGPoint {
        let dx = radius * CGFloat(sin(theta))
        return CGPoint(
            x: southernHemisphere ? center.x - dx : center.x + dx,
            y: center.y - radius * CGFloat(cos(theta))
        )
    }

    /// 圆盘上「某真太阳时」对应的点（同一参数化）。
    static func point(
        center: CGPoint,
        radius: CGFloat,
        hour: Double,
        southernHemisphere: Bool = false
    ) -> CGPoint {
        point(
            center: center,
            radius: radius,
            theta: angleOfDayHour(hour),
            southernHemisphere: southernHemisphere
        )
    }

    // MARK: - 主计算

    /// 算出整张圆盘的几何。
    ///
    /// - `sunriseHour` / `sunsetHour`：日出 / 日落的**真太阳时**小时数；极昼极夜时为 nil；
    /// - `trueSolarHour`：当前时刻的**真太阳时**小时数；
    /// - `isPolarDay` / `isPolarNight`：极昼 / 极夜（来自 `PolarState`，圆的朝向由它决定）；
    /// - `southernHemisphere`：南半球（`latitude < 0`）。为 true 时点的 x 以圆心镜像 ——
    ///   太阳从右往左走（逆时针），日出在右、日落在左；**地平线位置不受影响**（只由昼长决定）。
    ///
    /// 地平线的口径：有日出时刻就用 `C.y − R·cos(θ(日出))`；只有日落时刻时用日落（两者对称，结果相同）；
    /// 两者都缺又不是极昼极夜（数据异常）时退回「12 小时白昼」，地平线过圆心。
    ///
    /// **日出 0:00 的边界**：`θ = −180°` → `horizonY = C.y + R`，与圆相切于最下方（弦长 0）。
    static func compute(
        size: CGSize,
        sunriseHour: Double?,
        sunsetHour: Double?,
        trueSolarHour: Double,
        isPolarDay: Bool,
        isPolarNight: Bool,
        southernHemisphere: Bool = false
    ) -> SunPath {
        let radius = radiusRatio * min(size.width, size.height)
        let center = CGPoint(x: size.width / 2.0, y: size.height / 2.0)

        let horizonY: CGFloat
        if isPolarDay {
            horizonY = center.y + radius * polarHorizonRatio
        } else if isPolarNight {
            horizonY = center.y - radius * polarHorizonRatio
        } else if let sunriseHour {
            horizonY = center.y - radius * CGFloat(cos(angleOfDayHour(sunriseHour)))
        } else if let sunsetHour {
            horizonY = center.y - radius * CGFloat(cos(angleOfDayHour(sunsetHour)))
        } else {
            horizonY = center.y
        }

        return SunPath(
            center: center,
            radius: radius,
            horizonY: horizonY,
            sunPoint: point(
                center: center,
                radius: radius,
                hour: trueSolarHour,
                southernHemisphere: southernHemisphere
            ),
            isPolarDay: isPolarDay,
            isPolarNight: isPolarNight,
            isSouthernHemisphere: southernHemisphere
        )
    }

    // MARK: - 画弧 / 弦用的小工具

    /// 白天弧两端各**外扩**的角度（度）：0.8°。
    ///
    /// 圆盘上不再画日出 / 日落那两个刻度圆点（与安卓一致）：弧端各自越过地平线一点点，
    /// 交点自然被弧「盖住」。R ≈ 73.7pt 时 0.8° 的弧长约 **1pt**，肉眼刚好是「出线一点」。
    static let dayArcOvershootDegrees: Double = 0.8
    /// 同上，换算成弧度。
    static var dayArcOvershootRadians: Double { dayArcOvershootDegrees * Double.pi / 180 }

    /// 白天弧的起止角（θ，弧度），从日出角**递增**到日落角，途中经过圆顶（12:00）。
    ///
    /// - 极昼：整圆都是白天 → `(0, 2π)`；
    /// - 极夜：整圆都在地平线以下 → `nil`（没有白天弧）；
    /// - 正常：日出/日落缺一个时按「12 小时白昼」兜底（06:00 / 18:00）；
    /// - **两端各外扩 `dayArcOvershootRadians`（0.8°）**：起点 = 日出 − 0.8°、扫角 = 跨度 + 1.6°，
    ///   扫角封顶 2π（昼长接近 24 小时时就是整圆）。
    ///
    /// 夜间弧是它的补集 `(end, start + 2π)`，扫角 = 2π − 白天扫角；为 0 时不该画。
    static func dayArcAngles(
        sunriseHour: Double?,
        sunsetHour: Double?,
        isPolarDay: Bool,
        isPolarNight: Bool
    ) -> (start: Double, end: Double)? {
        if isPolarNight { return nil }
        if isPolarDay { return (0.0, 2.0 * Double.pi) }

        let overshoot = dayArcOvershootRadians
        let sunrise = angleOfDayHour(sunriseHour ?? 6.0)
        var sunset = angleOfDayHour(sunsetHour ?? 18.0)
        while sunset <= sunrise { sunset += 2.0 * Double.pi }

        // 两端各外扩 0.8°：起点往前、终点往后，扫角因此 +1.6°；封顶整圆。
        let span = min(sunset - sunrise + 2 * overshoot, 2.0 * Double.pi)
        let start = sunrise - overshoot
        return (start, start + span)
    }

    /// 白天 / 夜间弧的扫角（弧度）：`night + day == 2π`，夜间为 0 时不该画虚线。
    static func arcSweeps(
        sunriseHour: Double?,
        sunsetHour: Double?,
        isPolarDay: Bool,
        isPolarNight: Bool
    ) -> (day: Double, night: Double)? {
        guard let arc = dayArcAngles(
            sunriseHour: sunriseHour,
            sunsetHour: sunsetHour,
            isPolarDay: isPolarDay,
            isPolarNight: isPolarNight
        ) else { return nil }
        let day = arc.end - arc.start
        return (day, max(2.0 * Double.pi - day, 0))
    }

    /// 地平线与圆的交点（日出 / 日落交点；标签锚点用）。地平线落到圆外（极昼 / 极夜）时返回 nil。
    ///
    /// 日出 0:00 时两端重合在圆底 `(C.x, C.y + R)`：`start == end`。
    static func horizonChord(path: SunPath) -> (start: CGPoint, end: CGPoint)? {
        let dy = Double(path.horizonY - path.center.y)
        let radius = Double(path.radius)
        guard radius > 0, abs(dy) <= radius else { return nil }
        let half = (radius * radius - dy * dy).squareRoot()
        return (
            CGPoint(x: path.center.x - CGFloat(half), y: path.horizonY),
            CGPoint(x: path.center.x + CGFloat(half), y: path.horizonY)
        )
    }

    /// **未知态**（定位不可用）的圆盘弧：昼弧 / 夜弧各 **180°**，地平线因此正好过圆心。
    ///
    /// 起点取 06:00 那个角度（圆左），扫 π 到 18:00（圆右）。未知态**不画**太阳点、运动箭头、
    /// 日出/日落标签 —— 只留这个「对半」的圆。
    static func unknownArcAngles() -> (start: Double, end: Double) {
        let start = angleOfDayHour(6)
        return (start, start + Double.pi)
    }

    /// 未知态的地平线高度：过圆心（昼 / 夜各一半）。
    static func unknownHorizonY(center: CGPoint) -> CGFloat { center.y }

    /// 当前太阳点是否在地平线以上（极昼恒真、极夜恒假）。
    static func isSunAboveHorizon(path: SunPath) -> Bool {
        if path.isPolarDay { return true }
        if path.isPolarNight { return false }
        return path.sunPoint.y <= path.horizonY
    }

    // MARK: - 地平线（固定长度，贯穿画布）

    /// 地平线画在画布上的起点 x：**画布内缩 `horizonInset`（4pt）**。
    ///
    /// 所有场景（普通日 / 短昼 / 极昼 / 极夜 / 相切）都画成同一条贯穿画布的横线，
    /// 长度恒为 `画布宽 − 2 × horizonInset`；不再按「弦 + 0.2R」延伸，也不再分圆内 / 圆外两段。
    static func horizonStartX(size: CGSize) -> CGFloat {
        min(horizonInset, max(size.width / 2.0, 0))
    }

    /// 地平线画在画布上的终点 x：`画布宽 − horizonInset`。
    static func horizonEndX(size: CGSize) -> CGFloat {
        max(size.width - horizonInset, horizonStartX(size: size))
    }

    // MARK: - 标签锚点

    /// 算出四个标签的锚点。
    ///
    /// 规则（与安卓 v2 逐条对齐）：
    /// 1. **日出**：右对齐，锚点在**左交点左侧 10pt**；**日落**：左对齐，锚点在**右交点右侧 10pt**；
    ///    两者都**比交点抬高 10pt** —— 延伸出去的地平线正好从文字下面穿过，不会压字；
    /// 2. **上中天**：水平居中，底边离圆顶 8pt；
    /// 3. **短昼保护**（昼长 ≤ 2 小时）：两个交点几乎重合，把两块标签改放到「圆顶下方一行」，
    ///    左右仍各离圆 10pt，免得和上中天挤在一起；
    /// 4. **极昼**：没有交点，只在圆心写「极昼」，**保留**上中天；
    ///    **极夜**：圆心写「极夜」，**不画上中天**（太阳整日不出，没有中天可言）。
    ///
    /// `dayLengthHours` 只用于判断「短昼」；传 nil 时按正常日处理。
    static func labels(path: SunPath, size: CGSize, dayLengthHours: Double? = nil) -> SunPathLabels {
        let center = path.center
        let noon = path.isPolarNight ? nil : SunPathLabel(
            point: CGPoint(x: center.x, y: center.y - path.radius - noonGap),
            alignment: .bottom
        )

        if path.isPolarDay || path.isPolarNight {
            return SunPathLabels(
                sunrise: nil,
                sunset: nil,
                noon: noon,
                polar: SunPathLabel(point: center, alignment: .center)
            )
        }

        let dy = Double(path.horizonY - center.y)
        let radius = Double(path.radius)
        let halfChord: CGFloat = abs(dy) <= radius
            ? CGFloat((radius * radius - dy * dy).squareRoot())
            : 0
        let xLeft = center.x - halfChord
        let xRight = center.x + halfChord

        let isShortDay = (dayLengthHours ?? 24.0) <= shortDayHours
        let isLongDay = (dayLengthHours ?? 24.0) >= 24.0 - shortDayHours
        // 半球决定哪一端是日出：北半球日出在左交点（太阳从左往右），南半球在右交点（从右往左）。
        let southern = path.isSouthernHemisphere
        let sunriseSideX = southern ? xRight : xLeft
        let sunsetSideX = southern ? xLeft : xRight
        let sunriseOutward = southern ? labelOffsetX : -labelOffsetX
        let sunsetOutward = southern ? -labelOffsetX : labelOffsetX

        let labelY: CGFloat
        let sunriseAnchorX: CGFloat
        let sunsetAnchorX: CGFloat
        if isShortDay {
            // 圆顶下方一行：标签中心落在这一行，左右各离圆弧 10pt（南半球左右对调）。
            labelY = center.y - path.radius + shortDayRowOffset
            let rowDy = Double(labelY - center.y)
            let halfWidth = abs(rowDy) <= radius
                ? CGFloat((radius * radius - rowDy * rowDy).squareRoot())
                : 0
            let leftX = center.x - halfWidth - labelOffsetX
            let rightX = center.x + halfWidth + labelOffsetX
            sunriseAnchorX = southern ? rightX : leftX
            sunsetAnchorX = southern ? leftX : rightX
        } else if isLongDay {
            // 昼长接近 24h：弦几乎退化成一个切点（日出 0:00 时就是切在圆底），
            // 「抬高 10pt」会顶进圆里，所以改放到地平线**远离圆心**的那一侧。
            labelY = path.horizonY + (path.horizonY >= center.y ? labelOffsetY : -labelOffsetY)
            sunriseAnchorX = sunriseSideX + sunriseOutward
            sunsetAnchorX = sunsetSideX + sunsetOutward
        } else {
            // **南半球放地平线下方**（夜弧在下方，几何上不会压到昼弧）；北半球维持上方。
            labelY = southern ? path.horizonY + labelOffsetY : path.horizonY - labelOffsetY
            sunriseAnchorX = sunriseSideX + sunriseOutward
            sunsetAnchorX = sunsetSideX + sunsetOutward
        }

        // 标签永远放在交点的**外侧**：北半球日出在左（右对齐）、南半球日出在右（左对齐）。
        // 重叠检测：近极昼时日出 / 日落 / 上中天会挤到圆顶同一处，改用边缘退让布局。
        let estSunrise = estimatedLabelWidth(characters: 9)
        let estSunset = estimatedLabelWidth(characters: 9)
        let estNoon = estimatedLabelWidth(characters: noonWidthCharacters)
        let baseRects = [
            labelRect(point: CGPoint(x: sunriseAnchorX, y: labelY), alignment: southern ? .leading : .trailing, width: estSunrise),
            labelRect(point: CGPoint(x: sunsetAnchorX, y: labelY), alignment: southern ? .trailing : .leading, width: estSunset),
            labelRect(point: CGPoint(x: center.x, y: center.y - path.radius - noonGap), alignment: .bottom, width: estNoon),
        ]
        // **紧凑行布局（几何判据，不用固定阈值）**：昼长短时地平线贴近圆顶，正常锚点会贴上中天。
        // 只要「日出/日落标签」与「上中天标签」的垂直间隙 < 6pt（或已相交），就改成一整行：
        // 行 y = 上中天底边 + 6 + 半行高；两个标签贴画布左右内边距（弦退化成一个点时贴弦必然互相压）。
        // 南半球不走这条：它的标签在地平线下方，与上中天天然远离。
        if !southern {
            let noonRect = baseRects[2]
            let riseRect = baseRects[0]
            let setRect = baseRects[1]
            let gap = min(abs(riseRect.minY - noonRect.maxY), abs(setRect.minY - noonRect.maxY))
            if gap < 6 || riseRect.intersects(noonRect) || setRect.intersects(noonRect) {
                let rowY = noonRect.maxY + 6 + labelHeight / 2
                return SunPathLabels(
                    sunrise: SunPathLabel(
                        point: CGPoint(x: edgeInset + estSunrise, y: rowY),
                        alignment: .trailing
                    ),
                    sunset: SunPathLabel(
                        point: CGPoint(x: size.width - edgeInset - estSunset, y: rowY),
                        alignment: .leading
                    ),
                    noon: noon,
                    polar: nil
                )
            }
        }
        // 南半球：近极昼时两个交点几乎重合 → 分别贴左右内边距，避免标签叠在一起。
        let tooClose = southern && abs(sunriseAnchorX - sunsetAnchorX) < size.width * 0.2
        if labelsOverlap(baseRects) || tooClose {
            return SunPathLabels(
                sunrise: fallbackLabelAnchors(path: path, size: size, sunriseWidth: estSunrise, sunsetWidth: estSunset, noonWidth: estNoon).sunrise,
                sunset: fallbackLabelAnchors(path: path, size: size, sunriseWidth: estSunrise, sunsetWidth: estSunset, noonWidth: estNoon).sunset,
                noon: fallbackLabelAnchors(path: path, size: size, sunriseWidth: estSunrise, sunsetWidth: estSunset, noonWidth: estNoon).noon,
                polar: nil
            )
        }
        return SunPathLabels(
            sunrise: SunPathLabel(
                point: CGPoint(x: sunriseAnchorX, y: labelY),
                alignment: southern ? .leading : .trailing
            ),
            sunset: SunPathLabel(
                point: CGPoint(x: sunsetAnchorX, y: labelY),
                alignment: southern ? .trailing : .leading
            ),
            noon: noon,
            polar: nil
        )
    }

    /// 把「锚点 + 对齐 + 预算尺寸」还原成矩形：自检用它断「不压圆 / 不越界 / 互不重叠」。
    // MARK: - Label overlap detection / edge fallback

    static let labelFontSize: CGFloat = 11
    static let labelWidthPerChar: CGFloat = 0.6
    static let labelPadding: CGFloat = 4
    static let labelHeight: CGFloat = 15
    static let edgeInset: CGFloat = 4
    /// 上中天标签的估算字符数：`上中天 11:39 · 正南` ≈ 15（加方位后缀后必须放宽，否则重叠检测漏判）。
    static let noonWidthCharacters = 15

    /// 上中天时太阳的方位文字（北半球「正南」、南半球「正北」）。
    ///
    /// 圆盘是「面朝赤道的竖直平面」投影：北半球观测者面朝南、南半球面朝北。
    /// 把上中天的方位直接标出来，用户就不会把日出/日落的方向看反。
    static func noonDirection(southernHemisphere: Bool) -> String {
        L(southernHemisphere ? "sun.dueNorth" : "sun.dueSouth")
    }
    static func estimatedLabelWidth(characters: Int) -> CGFloat {
        CGFloat(max(characters, 1)) * labelFontSize * labelWidthPerChar + labelPadding * 2
    }

    static func labelRect(point: CGPoint, alignment: SunPathLabelAlignment, width: CGFloat) -> CGRect {
        let h = labelHeight
        switch alignment {
        case .trailing: return CGRect(x: point.x - width, y: point.y - h / 2, width: width, height: h)
        case .leading: return CGRect(x: point.x, y: point.y - h / 2, width: width, height: h)
        case .bottom: return CGRect(x: point.x - width / 2, y: point.y - h, width: width, height: h)
        default: return CGRect(x: point.x - width / 2, y: point.y - h / 2, width: width, height: h)
        }
    }

    static func labelsOverlap(_ rects: [CGRect]) -> Bool {
        for i in 0..<rects.count {
            for j in (i + 1)..<rects.count where rects[i].intersects(rects[j]) { return true }
        }
        return false
    }

    static func fallbackLabelAnchors(
        path: SunPath,
        size: CGSize,
        sunriseWidth: CGFloat,
        sunsetWidth: CGFloat,
        noonWidth: CGFloat
    ) -> (sunrise: SunPathLabel, sunset: SunPathLabel, noon: SunPathLabel?) {
        let center = path.center
        let southern = path.isSouthernHemisphere
        let y = southern ? path.horizonY + labelOffsetY : path.horizonY - labelOffsetY
        let dy = Double(path.horizonY - center.y)
        let radius = Double(path.radius)
        let halfChord: CGFloat = abs(dy) <= radius ? CGFloat((radius * radius - dy * dy).squareRoot()) : 0
        let leftX = center.x - halfChord - labelOffsetX
        let rightX = center.x + halfChord + labelOffsetX
        let need = max(sunriseWidth, sunsetWidth) + 8
        let push = max(0, (need - (rightX - leftX)) / 2)
        let minX = sunsetWidth + edgeInset
        let maxX = size.width - sunriseWidth - edgeInset
        var left = max(minX, min(leftX - push, maxX))
        var right = min(maxX, max(rightX + push, minX))
        if right - left < need {
            left = sunsetWidth + edgeInset
            right = size.width - sunriseWidth - edgeInset
        }
        let sunrise = SunPathLabel(point: CGPoint(x: southern ? right : left, y: y), alignment: southern ? .trailing : .leading)
        let sunset = SunPathLabel(point: CGPoint(x: southern ? left : right, y: y), alignment: southern ? .leading : .trailing)
        var noonPoint = CGPoint(x: center.x, y: center.y - path.radius - noonGap)
        if !path.isPolarNight {
            let sunriseRect = labelRect(point: sunrise.point, alignment: sunrise.alignment, width: sunriseWidth)
            let sunsetRect = labelRect(point: sunset.point, alignment: sunset.alignment, width: sunsetWidth)
            let noonRect = labelRect(point: noonPoint, alignment: .bottom, width: noonWidth)
            if noonRect.intersects(sunriseRect) || noonRect.intersects(sunsetRect) {
                noonPoint.y = edgeInset + labelHeight
            }
        }
        let noon: SunPathLabel? = path.isPolarNight ? nil : SunPathLabel(point: noonPoint, alignment: .bottom)
        return (sunrise, sunset, noon)
    }

    static func rect(for label: SunPathLabel, size: CGSize) -> CGRect {
        switch label.alignment {
        case .trailing:
            return CGRect(
                x: label.point.x - size.width,
                y: label.point.y - size.height / 2,
                width: size.width,
                height: size.height
            )
        case .leading:
            return CGRect(
                x: label.point.x,
                y: label.point.y - size.height / 2,
                width: size.width,
                height: size.height
            )
        case .bottom:
            return CGRect(
                x: label.point.x - size.width / 2,
                y: label.point.y - size.height,
                width: size.width,
                height: size.height
            )
        case .center:
            return CGRect(
                x: label.point.x - size.width / 2,
                y: label.point.y - size.height / 2,
                width: size.width,
                height: size.height
            )
        }
    }

    /// 标签预算矩形（给自检与报告用）。
    static func rect(for label: SunPathLabel?, budget: CGSize) -> CGRect? {
        guard let label else { return nil }
        return rect(for: label, size: budget)
    }

    // MARK: - 太阳运动方向的小弧箭头

    /// 圆盘内侧「太阳往哪走」的小弧：起点、终点（= 箭头尖）、指向。
    ///
    /// 弧半径 `0.72R`（离太阳点 0.28R，够远不会糊在一起），跨 `30°`，中心对准当前太阳点的角度。
    struct MotionArrow: Equatable {
        /// 弧的起点（当前角 − span/2）。
        let start: CGPoint
        /// 弧的终点（当前角 + span/2）——**运动方向的下游**。
        let end: CGPoint
        /// 箭头尖（等于 `end`，UI 直接拿来画箭头）。
        let tip: CGPoint
    }

    /// 运动小弧的起止角（θ，弧度）：当前角 ± span/2。
    ///
    /// 时间往前走就是 θ 递增（06:00 → 12:00 → 18:00），所以 `end` 永远在运动的下游；
    /// 南半球只是把 x 镜像（看起来逆时针），角度顺序不变。
    static func motionArrowAngles(
        currentTrueSolarHour: Double,
        spanDegrees: CGFloat = 30
    ) -> (start: Double, end: Double) {
        let half = Double(spanDegrees) / 2.0 * Double.pi / 180.0
        let theta = angleOfDayHour(currentTrueSolarHour)
        return (theta - half, theta + half)
    }

    /// 算出运动方向小弧的三个点（纯数值，自检直接断坐标与方向）。
    ///
    /// - 半径 = `radiusRatio × R`（默认 0.72R），跨 `spanDegrees`（默认 30°），中心是当前太阳点的角度；
    /// - 两端点都走 `point(θ:...)`，所以**南半球自动镜像**：北半球顺时针、南半球逆时针；
    /// - `tip == end`：箭头画在终点、指向 θ 递增的方向。
    static func motionArrow(
        path: SunPath,
        currentTrueSolarHour: Double,
        radiusRatio: CGFloat = 0.72,
        spanDegrees: CGFloat = 30
    ) -> MotionArrow {
        let angles = motionArrowAngles(currentTrueSolarHour: currentTrueSolarHour, spanDegrees: spanDegrees)
        let radius = path.radius * radiusRatio
        let start = point(
            center: path.center,
            radius: radius,
            theta: angles.start,
            southernHemisphere: path.isSouthernHemisphere
        )
        let end = point(
            center: path.center,
            radius: radius,
            theta: angles.end,
            southernHemisphere: path.isSouthernHemisphere
        )
        return MotionArrow(start: start, end: end, tip: end)
    }
}
