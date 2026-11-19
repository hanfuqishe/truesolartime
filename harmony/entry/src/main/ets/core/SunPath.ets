/**
 * 太阳卡圆盘的几何与标签锚点，逐条对齐 Android 的 `ui/SunPathGeometry.kt`。
 *
 * 坐标单位与画布一致（鸿蒙 Canvas 用 vp，Android 用 px），公式与常数完全相同，
 * 所以两端在同一画布尺寸下算出的数值逐个相等。纯逻辑、不依赖任何绘图 API，
 * 便于 `Tools/core-check.ts` 直接断言。
 *
 * 几何模型：**圆 = 一天 24 小时**，圆心在画布中央、半径 = 0.38 × min(w, h)；
 * `θ(t) = (t − 12) / 24 × 360°`，圆上一点 `(x, y) = (C.x + s·R·sinθ, C.y − R·cosθ)`。
 * `s = +1` 是北半球视角（12:00 在上、00:00 在下、06:00 在左、18:00 在右）；
 * `s = −1` 是南半球视角（面朝北，东在右、西在左，太阳从右往左走 → 06:00 在右、18:00 在左）。
 * 地平线是由**日出时刻**决定的水平线：`y_h = C.y − R·cos(θ(日出))`，南北半球相同；
 * 昼长 12h 过圆心、> 12h 下移、< 12h 上移；极昼沉到圆下、极夜升到圆上；
 * 日出恰好 0:00 时与圆**相切于最下方**。
 *
 * 时刻一律是**当地真太阳时**的小时数（0–24，可越界），换成标准时会与日出刻度对不上。
 */

/** 圆盘的一次投影结果（画布坐标，y 向下）。 */
export class SunPath {
  centerX: number;
  centerY: number;
  radius: number;
  horizonY: number;
  sunX: number;
  sunY: number;
  isPolarDay: boolean;
  isPolarNight: boolean;
  /** 南半球视角：x 轴镜像（日出在右、日落在左），y 不变。 */
  southernHemisphere: boolean;

  constructor(centerX: number, centerY: number, radius: number, horizonY: number,
    sunX: number, sunY: number, isPolarDay: boolean, isPolarNight: boolean,
    southernHemisphere: boolean = false) {
    this.centerX = centerX;
    this.centerY = centerY;
    this.radius = radius;
    this.horizonY = horizonY;
    this.sunX = sunX;
    this.sunY = sunY;
    this.isPolarDay = isPolarDay;
    this.isPolarNight = isPolarNight;
    this.southernHemisphere = southernHemisphere;
  }

  /** 圆顶（12:00 所在）的 y。 */
  topY(): number {
    return this.centerY - this.radius;
  }

  /** 圆底（00:00 所在）的 y。 */
  bottomY(): number {
    return this.centerY + this.radius;
  }

  /** 圆最左（06:00 所在）的 x。 */
  leftX(): number {
    return this.centerX - this.radius;
  }

  /** 圆最右（18:00 所在）的 x。 */
  rightX(): number {
    return this.centerX + this.radius;
  }

  /** 整圆都在地平线以上（极昼 / 昼长 ≥ 24h）。 */
  isWholeCircleDay(): boolean {
    return this.horizonY >= this.bottomY();
  }

  /** 整圆都在地平线以下（极夜）。 */
  isWholeCircleNight(): boolean {
    return this.horizonY <= this.topY();
  }

  /** 当前太阳点是否在地平线以上（y 向下，所以是「不大于地平线」）。 */
  isSunUp(): boolean {
    return this.sunY <= this.horizonY;
  }

  /** 要不要画「上中天」标签：极夜没有（太阳整日不升，标 12:00 只会误导）。 */
  hasTransitLabel(): boolean {
    return !this.isPolarNight;
  }
}

/** 白天弧的绘制角度，口径与 canvas `arc` 一致：0° 指向 +x、顺时针为正。 */
export class SunArcSpan {
  startDegrees: number;
  sweepDegrees: number;

  constructor(startDegrees: number, sweepDegrees: number) {
    this.startDegrees = startDegrees;
    this.sweepDegrees = sweepDegrees;
  }
}

/**
 * 圆盘外侧标签的锚点（画布坐标）：
 * - 日出：文字**右边缘** = sunriseX、竖直中心 = sunriseY；
 * - 日落：文字**左边缘** = sunsetX、竖直中心 = sunsetY；
 * - 上中天：水平中心 = noonX、文字**底边** = noonY；
 * - 极昼／极夜：文字中心 = polarX / polarY。
 */
export class SunLabelAnchors {
  sunriseX: number;
  sunriseY: number;
  sunsetX: number;
  sunsetY: number;
  noonX: number;
  noonY: number;
  polarX: number;
  polarY: number;

  constructor(sunriseX: number, sunriseY: number, sunsetX: number, sunsetY: number,
    noonX: number, noonY: number, polarX: number, polarY: number) {
    this.sunriseX = sunriseX;
    this.sunriseY = sunriseY;
    this.sunsetX = sunsetX;
    this.sunsetY = sunsetY;
    this.noonX = noonX;
    this.noonY = noonY;
    this.polarX = polarX;
    this.polarY = polarY;
  }
}

/**
 * 太阳运动方向箭头（画布坐标）：0.72R 的一段短弧 + 末端箭头。
 *
 * [startX]/[startY] 与 [endX]/[endY] 是短弧的两端，[tipX]/[tipY] 是箭头尖端（= end）。
 * 方向跟着半球走：北半球顺时针（end 在 start 顺时针下游），南半球镜像后逆时针。
 */
export class MotionArrow {
  startX: number;
  startY: number;
  endX: number;
  endY: number;
  tipX: number;
  tipY: number;

  constructor(startX: number, startY: number, endX: number, endY: number,
    tipX: number, tipY: number) {
    this.startX = startX;
    this.startY = startY;
    this.endX = endX;
    this.endY = endY;
    this.tipX = tipX;
    this.tipY = tipY;
  }
}

/**
 * 地平线的绘制范围（x 起止）。
 *
 * 长度是**固定**的：画布左右各内缩 `horizonSpan` 的 `sideInset`（4vp），与圆心 / 半径 / 昼长
 * 都无关 —— 普通日、短昼、极昼、极夜、0:00 相切五种场景画出来一样长，读起来才是「地平线」，
 * 而不是某一段圆弧的弦。
 */
export class HorizonSpan {
  startX: number;
  endX: number;

  constructor(startX: number, endX: number) {
    this.startX = startX;
    this.endX = endX;
  }

  length(): number {
    return this.endX - this.startX;
  }
}

export class SunPathGeometry {
  /** 半径占画布短边的比例：0.38，上下各留 12% 放圆顶的上中天标签。 */
  static readonly RADIUS_RATIO: number = 0.38;

  /** 极昼 / 极夜时地平线离圆心的距离（半径的倍数），必须 > 1。 */
  static readonly POLAR_HORIZON_RATIO: number = 1.25;

  /** 白天弧两端各外扩的角度（度）：起点 -0.8°、扫角 +1.6°，让弧端略穿过地平线。 */
  static readonly ARC_END_EXTENSION_DEGREES: number = 0.8;

  /** 夜间弧的扫角（度）：`360 − |白天扫角|`，为 0 时不画（极昼）。 */
  static nightSweepDegrees(daySweepDegrees: number): number {
    return Math.max(0, 360 - Math.abs(daySweepDegrees));
  }

  /**
   * 夜间弧的终点角度（度）：从外扩后的日落点绕回日出点。
   *
   * 北半球 `start + 360`、南半球 `start − 360`；与起点 `start + daySweep` 之间的弧长
   * 恰为 `360 − |daySweep|`，不会把整圈再画一遍。
   */
  static nightEndDegrees(startDegrees: number, southernHemisphere: boolean): number {
    return startDegrees + (southernHemisphere ? -360 : 360);
  }

  private static readonly HOURS_PER_DAY: number = 24;

  /** 真太阳时 [hour] 对应的角度（弧度）：`θ = (hour − 12) / 24 × 2π`。 */
  static angleOfDayHour(hour: number): number {
    return (hour - 12.0) / SunPathGeometry.HOURS_PER_DAY * 2.0 * Math.PI;
  }

  /** 圆上 [hour] 处的 x：`C.x + s·R·sin θ`（s = −1 为南半球镜像）。 */
  static hourX(centerX: number, radius: number, hour: number,
    southernHemisphere: boolean = false): number {
    const sign: number = southernHemisphere ? -1 : 1;
    return centerX + sign * radius * Math.sin(SunPathGeometry.angleOfDayHour(hour));
  }

  /** 圆上 [hour] 处的 y：`C.y − R·cos θ`（y 向下，所以用减号）。 */
  static hourY(centerY: number, radius: number, hour: number): number {
    return centerY - radius * Math.cos(SunPathGeometry.angleOfDayHour(hour));
  }

  /**
   * 地平线的 y：`C.y − R·cos(θ(日出))`。
   *
   * [sunriseHour] 为 null（极昼/极夜）时没有交点，由 polar 标志把地平线沉到圆下 / 升到圆上；
   * 两个标志都为 false 又拿不到日出时退回圆心。日出 0:00 时 `cos θ = −1` → `y_h = C.y + R`，
   * 地平线与圆相切于最下方。
   */
  static horizonY(centerY: number, radius: number, sunriseHour: number | null,
    isPolarDay: boolean, isPolarNight: boolean): number {
    if (sunriseHour !== null) {
      return centerY - radius * Math.cos(SunPathGeometry.angleOfDayHour(sunriseHour));
    }
    if (isPolarDay) {
      return centerY + radius * SunPathGeometry.POLAR_HORIZON_RATIO;
    }
    if (isPolarNight) {
      return centerY - radius * SunPathGeometry.POLAR_HORIZON_RATIO;
    }
    return centerY;
  }

  /**
   * 算出圆盘的全部几何。
   *
   * [sunsetHour] 不参与地平线计算（日出已唯一确定弦），只在「只有日落没有日出」时兜底：
   * 真太阳时里日出与日落关于 12:00 对称（日出 = 24 − 日落）。
   * [southernHemisphere] 为 true 时 x 轴镜像（南半球观察者面朝北，东在右、西在左）。
   */
  static compute(width: number, height: number, sunriseHour: number | null,
    sunsetHour: number | null, trueSolarHour: number,
    isPolarDay: boolean, isPolarNight: boolean,
    southernHemisphere: boolean = false): SunPath {
    const radius: number = SunPathGeometry.RADIUS_RATIO * Math.min(width, height);
    const centerX: number = width / 2.0;
    const centerY: number = height / 2.0;
    // 极昼极夜不能套「24 − 日落」的对称关系，交给 polar 标志决定。
    let horizonAnchor: number | null = sunriseHour;
    if (horizonAnchor === null && !isPolarDay && !isPolarNight && sunsetHour !== null) {
      horizonAnchor = SunPathGeometry.HOURS_PER_DAY - sunsetHour;
    }
    const horizon: number = SunPathGeometry.horizonY(centerY, radius, horizonAnchor, isPolarDay, isPolarNight);
    return new SunPath(
      centerX,
      centerY,
      radius,
      horizon,
      SunPathGeometry.hourX(centerX, radius, trueSolarHour, southernHemisphere),
      SunPathGeometry.hourY(centerY, radius, trueSolarHour),
      isPolarDay,
      isPolarNight,
      southernHemisphere
    );
  }

  /**
   * 圆心到 [hour] 的 canvas 角度（弧度，0 = +x、顺时针为正）。
   *
   * 北半球 `φ = θ − π/2`（06:00 在左、18:00 在右）；南半球 x 镜像后 `φ = −(θ + π/2)`
   * （06:00 在右、18:00 在左），因此白天弧从右往左、扫角为负。
   */
  static arcAngleOfDayHour(hour: number, southernHemisphere: boolean = false): number {
    const theta: number = SunPathGeometry.angleOfDayHour(hour);
    return southernHemisphere ? -(theta + Math.PI / 2.0) : theta - Math.PI / 2.0;
  }

  /**
   * 白天弧的起止角度；日出或日落缺一个（极昼 / 极夜）时返回 null，按整圆处理。
   * 日落越过 24:00 时按下一圈补 2π，保证扫角大小正确；南半球扫角取负（逆时针）。
   *
   * 弧端外扩 [ARC_END_EXTENSION_DEGREES]：起点往前挪 0.8°、扫角加 1.6°，让弧端略穿过地平线
   * （R≈73.7 时约 1dp）；扫角封顶 360°，接近极昼时不会绕过头。
   */
  static dayArcSpan(sunriseHour: number | null, sunsetHour: number | null,
    southernHemisphere: boolean = false): SunArcSpan | null {
    if (sunriseHour === null || sunsetHour === null) {
      return null;
    }
    const start: number = SunPathGeometry.angleOfDayHour(sunriseHour);
    let sweep: number = SunPathGeometry.angleOfDayHour(sunsetHour) - start;
    while (sweep <= 0.0) {
      sweep += 2.0 * Math.PI;
    }
    while (sweep > 2.0 * Math.PI) {
      sweep -= 2.0 * Math.PI;
    }
    const baseStart: number = SunPathGeometry.toDegrees(
      SunPathGeometry.arcAngleOfDayHour(sunriseHour, southernHemisphere));
    let signedSweep: number = SunPathGeometry.toDegrees(southernHemisphere ? -sweep : sweep);
    const direction: number = signedSweep >= 0 ? 1 : -1;
    const startDegrees: number = baseStart - direction * SunPathGeometry.ARC_END_EXTENSION_DEGREES;
    signedSweep = signedSweep + direction * SunPathGeometry.ARC_END_EXTENSION_DEGREES * 2;
    if (Math.abs(signedSweep) > 360) {
      signedSweep = direction * 360;
    }
    return new SunArcSpan(startDegrees, signedSweep);
  }

  /**
   * 三个时间标签 + 极昼极夜文案的锚点。
   *
   * [sideGap] 标签与圆外沿的水平间距；[noonGap] 上中天标签底边与圆顶的竖直间距；
   * [minLabelDrop] 短昼保护（日出/日落挤在圆顶时至少下沉这么远）；
   * [sideLabelRise] 把日出/日落标签从交点往上抬，让地平线从文字底下穿过。
   *
   * 日出/日落锚点与太阳点同源推导：北半球日出在左、日落在右；南半球 x 镜像后日出在右、
   * 日落在左（见 [SunPath.southernHemisphere]）。竖直方向（上中天在圆顶、极昼极夜在圆心）不变。
   */
  static labelAnchors(path: SunPath, sunriseHour: number | null, sunsetHour: number | null,
    sideGap: number, noonGap: number, minLabelDrop: number, sideLabelRise: number,
    labelFontSize: number = 11, labelPadding: number = 4, textChars: number = 5,
    labelTexts: string[] = [], labelOffset: number = 14): SunLabelAnchors {
    const sunriseY: number = SunPathGeometry.sideAnchorY(path, sunriseHour, minLabelDrop, sideLabelRise);
    const sunsetY: number = SunPathGeometry.sideAnchorY(path, sunsetHour, minLabelDrop, sideLabelRise);
    // 南半球：日出在右（+1）、日落在左（−1）；北半球反过来。
    const sunriseSign: number = path.southernHemisphere ? 1 : -1;
    const sunsetSign: number = -sunriseSign;
    const normal: SunLabelAnchors = new SunLabelAnchors(
      SunPathGeometry.sideAnchorX(path, sunriseHour, sunriseSign, sideGap, sunriseY),
      sunriseY,
      SunPathGeometry.sideAnchorX(path, sunsetHour, sunsetSign, sideGap, sunsetY),
      sunsetY,
      path.centerX,
      path.centerY - path.radius - noonGap,
      path.centerX,
      path.centerY
    );
    // 极昼/极夜没有日出日落标签，保持原样。
    if (sunriseHour === null || sunsetHour === null) {
      return normal;
    }
    const fallbackWidth: number = textChars * labelFontSize * 0.6 + labelPadding;
    // 文案改成「说明 + 时间」后必须按真实文案估宽（CJK 视作 1 个字宽，ASCII 0.6）。
    const sunriseWidth: number = labelTexts.length >= 3
      ? SunPathGeometry.estimateLabelWidth(labelTexts[0], labelFontSize, labelPadding) : fallbackWidth;
    const sunsetWidth: number = labelTexts.length >= 3
      ? SunPathGeometry.estimateLabelWidth(labelTexts[1], labelFontSize, labelPadding) : fallbackWidth;
    const noonWidth: number = labelTexts.length >= 3
      ? SunPathGeometry.estimateLabelWidth(labelTexts[2], labelFontSize, labelPadding) : fallbackWidth;
    const labelHeight: number = labelFontSize * 1.2 + labelPadding;
    // 文案带说明后上中天更宽/更高：保证标签顶边不越出画布。
    const noonY: number = labelTexts.length >= 3
      ? Math.max(labelHeight, normal.noonY) : normal.noonY;
    // 南半球：日出/日落标签一律放到地平线**下方**，不会再压到轨迹圆上。
    if (path.southernHemisphere) {
      return SunPathGeometry.southernBelowAnchors(path, sideGap, noonGap, sunriseWidth,
        sunsetWidth, labelHeight, labelOffset, noonY);
    }
    // 北半球接近极昼时两个交点挤在圆顶：水平间距不足，或任一与上中天相交 → 边缘退让布局。
    const canvasWidth: number = path.centerX * 2;
    // 文案变宽后先做「画布内」最小夹取，避免标签伸出画布（正常日仍保持原锚点 y）。
    let sunriseX: number = normal.sunriseX;
    let sunsetX: number = normal.sunsetX;
    if (sunriseSign < 0) {
      sunriseX = Math.max(sunriseWidth, sunriseX);
    } else {
      sunriseX = Math.min(canvasWidth - sunriseWidth, sunriseX);
    }
    if (sunsetSign < 0) {
      sunsetX = Math.max(sunsetWidth, sunsetX);
    } else {
      sunsetX = Math.min(canvasWidth - sunsetWidth, sunsetX);
    }
    const sunriseRect: number[] = SunPathGeometry.rectOf(sunriseX, normal.sunriseY,
      sunriseWidth, labelHeight, sunriseSign < 0);
    const sunsetRect: number[] = SunPathGeometry.rectOf(sunsetX, normal.sunsetY,
      sunsetWidth, labelHeight, sunsetSign < 0);
    const noonRect: number[] = SunPathGeometry.rectOf(normal.noonX, noonY,
      noonWidth, labelHeight, false, true);
    if (!SunPathGeometry.rectsOverlap(sunriseRect, sunsetRect) &&
      !SunPathGeometry.rectsOverlap(sunriseRect, noonRect) &&
      !SunPathGeometry.rectsOverlap(sunsetRect, noonRect)) {
      return new SunLabelAnchors(sunriseX, normal.sunriseY, sunsetX, normal.sunsetY,
        normal.noonX, noonY, normal.polarX, normal.polarY);
    }
    return SunPathGeometry.retreatAnchors(path, sunriseSign, sideLabelRise, sideGap,
      Math.max(sunriseWidth, Math.max(sunsetWidth, noonWidth)), labelHeight);
  }

  /** 估算标签像素宽：CJK 记 1 个字宽，ASCII（含空格/冒号）记 0.6。 */
  static estimateLabelWidth(text: string, fontSize: number, padding: number): number {
    let units: number = 0;
    for (let index: number = 0; index < text.length; index++) {
      const code: number = text.charCodeAt(index);
      units += code > 0x2e80 ? 1 : 0.6;
    }
    return units * fontSize + padding;
  }

  /** 标签矩形 [left, top, right, bottom]：横向按对齐方式（rightAligned = 文字右边缘在 x）。 */
  static rectOf(x: number, y: number, width: number, height: number, rightAligned: boolean,
      bottomAligned: boolean = false): number[] {
    const left: number = rightAligned ? x - width : (bottomAligned ? x - width / 2 : x);
    const top: number = bottomAligned ? y - height : y - height / 2;
    return [left, top, left + width, top + height];
  }

  static rectsOverlap(a: number[], b: number[]): boolean {
    return a[0] < b[2] && b[0] < a[2] && a[1] < b[3] && b[1] < a[3];
  }

  /**
   * 南半球的日出/日落标签：固定放在地平线下方，**以交点为基准**。
   *
   * 先让标签 x 正好落在交点上；只有当两个矩形会相交 / 间距不足时，才把左右两边各向外
   * 推开「最小必要距离」；推到画布内边距仍不够（极端极昼、两交点几乎重合）才退到边缘布局。
   */
  private static southernBelowAnchors(path: SunPath, sideGap: number, noonGap: number,
    sunriseWidth: number, sunsetWidth: number, labelHeight: number,
    labelOffset: number, noonY: number): SunLabelAnchors {
    const pad: number = Math.max(sideGap, 4);
    const canvasWidth: number = path.centerX * 2;
    const y: number = path.horizonY + labelOffset;
    const halfChord: number = SunPathGeometry.horizonHalfChord(path);
    const sunrisePoint: number = path.centerX + halfChord;
    const sunsetPoint: number = path.centerX - halfChord;
    let sunriseX: number = sunrisePoint;
    let sunsetX: number = sunsetPoint;
    // 两个标签之间至少留 8 的缝；宽度取两者较大者。
    const requiredGap: number = Math.max(sunriseWidth, sunsetWidth) + 8;
    let gap: number = sunriseX - sunsetX;
    // 日出=日落（两个交点重合）这种极端情形：直接退到边缘，保证分开。
    const coincident: boolean = gap < 1;
    if (gap < requiredGap && !coincident) {
      const shift: number = (requiredGap - gap) / 2;
      sunriseX = sunrisePoint + shift;
      sunsetX = sunsetPoint - shift;
      gap = requiredGap;
    }
    const sunriseRect: number[] = SunPathGeometry.rectOf(sunriseX, y, sunriseWidth, labelHeight, false);
    const sunsetRect: number[] = SunPathGeometry.rectOf(sunsetX, y, sunsetWidth, labelHeight, true);
    // 推到最小必要距离后仍出界 / 相交，或交点重合：退到画布边缘。
    if (coincident || sunriseRect[2] > canvasWidth - pad || sunsetRect[0] < pad ||
      SunPathGeometry.rectsOverlap(sunriseRect, sunsetRect)) {
      sunriseX = canvasWidth - pad - sunriseWidth;
      sunsetX = pad + sunsetWidth;
    }
    return new SunLabelAnchors(sunriseX, y, sunsetX, y, path.centerX,
      noonY, path.centerX, path.centerY);
  }

  private static retreatAnchors(path: SunPath, sunriseSign: number, sideLabelRise: number,
    sideGap: number, labelWidth: number, labelHeight: number): SunLabelAnchors {
    const pad: number = Math.max(sideGap, 4);
    const canvasWidth: number = path.centerX * 2;
    const y: number = path.horizonY - sideLabelRise;
    const sunriseX: number = sunriseSign < 0 ? pad + labelWidth : canvasWidth - pad - labelWidth;
    const sunsetX: number = sunriseSign < 0 ? canvasWidth - pad - labelWidth : pad + labelWidth;
    const noonX: number = path.centerX;
    let noonY: number = path.centerY - path.radius - pad;
    // 若仍与两侧退让标签相交，再上移到顶部内边距。
    const noonRect: number[] = SunPathGeometry.rectOf(noonX, noonY, labelWidth, labelHeight, false, true);
    const sunriseRect: number[] = SunPathGeometry.rectOf(sunriseX, y, labelWidth, labelHeight,
      sunriseSign < 0);
    const sunsetRect: number[] = SunPathGeometry.rectOf(sunsetX, y, labelWidth, labelHeight,
      sunriseSign > 0);
    if (SunPathGeometry.rectsOverlap(noonRect, sunriseRect) ||
      SunPathGeometry.rectsOverlap(noonRect, sunsetRect)) {
      noonY = pad + labelHeight;
    }
    return new SunLabelAnchors(sunriseX, y, sunsetX, y, noonX, noonY, path.centerX, path.centerY);
  }

  /**
   * 太阳运动方向箭头：圆**内侧**一段半径 ≈ 0.72R 的短弧，跨 [spanDeg] 度、以当前太阳点角度为中心。
   *
   * 北半球顺时针：start = 当前角 − span/2、end = +span/2；南半球镜像后运动方向是逆时针，
   * start/end 对调，于是 end 永远落在运动下游，tip = end。弧取在 0.72R 处，与 R 上的太阳点
   * （4.5vp + 柔光）之间留出空隙，不会重叠。极昼／极夜也照画（当前太阳点仍在圆上）。
   */
  static motionArrow(path: SunPath, currentTrueSolarHour: number,
    radiusRatio: number = 0.72, spanDeg: number = 30): MotionArrow {
    const ringRadius: number = path.radius * radiusRatio;
    const centerAngle: number = SunPathGeometry.arcAngleOfDayHour(currentTrueSolarHour,
      path.southernHemisphere);
    const halfSpan: number = spanDeg * Math.PI / 360.0;
    // 南半球运动方向是逆时针（canvas 角度递减）：start/end 对调。
    const startAngle: number = path.southernHemisphere
      ? centerAngle + halfSpan
      : centerAngle - halfSpan;
    const endAngle: number = path.southernHemisphere
      ? centerAngle - halfSpan
      : centerAngle + halfSpan;
    const startX: number = path.centerX + ringRadius * Math.cos(startAngle);
    const startY: number = path.centerY + ringRadius * Math.sin(startAngle);
    const endX: number = path.centerX + ringRadius * Math.cos(endAngle);
    const endY: number = path.centerY + ringRadius * Math.sin(endAngle);
    return new MotionArrow(startX, startY, endX, endY, endX, endY);
  }

  /**
   * 地平线的绘制范围：**固定为画布左右各内缩 [sideInset]**，与圆心、半径、昼长全都无关。
   *
   * 长度恒等于 `canvasWidth − 2 × sideInset`（卡片里 sideInset = 4vp），所以普通日、短昼、
   * 极昼、极夜、0:00 相切五种场景画出来一样长 —— 它是一条贯穿整个画面的地平线，
   * 不是「圆的那条弦」。极昼极夜时地平线在圆外，同样画满这一条。
   */
  static horizonSpan(canvasWidth: number, sideInset: number): HorizonSpan {
    const inset: number = Math.min(Math.max(sideInset, 0), canvasWidth / 2.0);
    return new HorizonSpan(inset, canvasWidth - inset);
  }

  /**
   * 地平线这条弦的半宽：`sqrt(R² − (y_h − C.y)²)`，两端正好落在日出/日落刻度上；
   * 极昼/极夜/相切时返回 0（没有弦）。
   */
  static horizonHalfChord(path: SunPath): number {
    const dy: number = path.horizonY - path.centerY;
    const r: number = path.radius;
    if (Math.abs(dy) <= r) {
      return Math.sqrt(Math.max(0, r * r - dy * dy));
    }
    return 0;
  }

  /** 一侧标签的竖直锚点：先给地平线让路（上抬），再做短昼保护（下沉），取更靠下的那个。 */
  private static sideAnchorY(path: SunPath, hour: number | null, minLabelDrop: number,
    sideLabelRise: number): number {
    if (hour === null) {
      return path.centerY;
    }
    const intersectionY: number = SunPathGeometry.hourY(path.centerY, path.radius, hour);
    return Math.max(intersectionY - sideLabelRise, path.centerY - path.radius + minLabelDrop);
  }

  /** 一侧标签的水平锚点：贴在「该标签行」上圆边界的外侧 [sideGap] 处。 */
  private static sideAnchorX(path: SunPath, hour: number | null, sign: number,
    sideGap: number, labelY: number): number {
    if (hour === null) {
      return path.centerX + sign * (path.radius + sideGap);
    }
    const dy: number = Math.min(path.radius, Math.max(-path.radius, labelY - path.centerY));
    const halfWidth: number = Math.sqrt(Math.max(0, path.radius * path.radius - dy * dy));
    return path.centerX + sign * (halfWidth + sideGap);
  }

  private static toDegrees(radians: number): number {
    return radians * 180.0 / Math.PI;
  }
}
