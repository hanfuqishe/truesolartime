/**
 * 太阳卡圆盘的几何与标签锚点，逐条对齐 Android 的 `ui/SunPathGeometry.kt`。
 *
 * 坐标单位与画布一致（鸿蒙 Canvas 用 vp，Android 用 px），公式与常数完全相同，
 * 所以两端在同一画布尺寸下算出的数值逐个相等。纯逻辑、不依赖任何绘图 API，
 * 便于 `Tools/core-check.ts` 直接断言。
 *
 * 几何模型：**圆 = 一天 24 小时**，圆心在画布中央、半径 = 0.38 × min(w, h)；
 * `θ(t) = (t − 12) / 24 × 360°`，圆上一点 `(x, y) = (C.x + R·sinθ, C.y − R·cosθ)`，
 * 即 12:00 在正上方、00:00 在正下方、06:00 在正左、18:00 在正右。
 * 地平线是由**日出时刻**决定的水平弦：`y_h = C.y − R·cos(θ(日出))`；
 * 昼长 12h 过圆心、> 12h 下移、< 12h 上移；极昼沉到圆下、极夜升到圆上；
 * 日出恰好 0:00 时与圆**相切于最下方**（弦退化成一点）。
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

  constructor(centerX: number, centerY: number, radius: number, horizonY: number,
    sunX: number, sunY: number, isPolarDay: boolean, isPolarNight: boolean) {
    this.centerX = centerX;
    this.centerY = centerY;
    this.radius = radius;
    this.horizonY = horizonY;
    this.sunX = sunX;
    this.sunY = sunY;
    this.isPolarDay = isPolarDay;
    this.isPolarNight = isPolarNight;
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

  private static readonly HOURS_PER_DAY: number = 24;

  /** 真太阳时 [hour] 对应的角度（弧度）：`θ = (hour − 12) / 24 × 2π`。 */
  static angleOfDayHour(hour: number): number {
    return (hour - 12.0) / SunPathGeometry.HOURS_PER_DAY * 2.0 * Math.PI;
  }

  /** 圆上 [hour] 处的 x：`C.x + R·sin θ`。 */
  static hourX(centerX: number, radius: number, hour: number): number {
    return centerX + radius * Math.sin(SunPathGeometry.angleOfDayHour(hour));
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
   */
  static compute(width: number, height: number, sunriseHour: number | null,
    sunsetHour: number | null, trueSolarHour: number,
    isPolarDay: boolean, isPolarNight: boolean): SunPath {
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
      SunPathGeometry.hourX(centerX, radius, trueSolarHour),
      SunPathGeometry.hourY(centerY, radius, trueSolarHour),
      isPolarDay,
      isPolarNight
    );
  }

  /**
   * 白天弧的起止角度；日出或日落缺一个（极昼 / 极夜）时返回 null，按整圆处理。
   * 日落越过 24:00 时按下一圈补 2π，保证扫角为正。
   */
  static dayArcSpan(sunriseHour: number | null, sunsetHour: number | null): SunArcSpan | null {
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
    // θ 以正上方为 0°、canvas arc 以 +x 为 0°：φ = θ − π/2。
    return new SunArcSpan(
      SunPathGeometry.toDegrees(start - Math.PI / 2.0),
      SunPathGeometry.toDegrees(sweep)
    );
  }

  /**
   * 三个时间标签 + 极昼极夜文案的锚点。
   *
   * [sideGap] 标签与圆外沿的水平间距；[noonGap] 上中天标签底边与圆顶的竖直间距；
   * [minLabelDrop] 短昼保护（日出/日落挤在圆顶时至少下沉这么远）；
   * [sideLabelRise] 把日出/日落标签从交点往上抬，让延伸后的地平线从文字底下穿过。
   */
  static labelAnchors(path: SunPath, sunriseHour: number | null, sunsetHour: number | null,
    sideGap: number, noonGap: number, minLabelDrop: number, sideLabelRise: number): SunLabelAnchors {
    const sunriseY: number = SunPathGeometry.sideAnchorY(path, sunriseHour, minLabelDrop, sideLabelRise);
    const sunsetY: number = SunPathGeometry.sideAnchorY(path, sunsetHour, minLabelDrop, sideLabelRise);
    return new SunLabelAnchors(
      SunPathGeometry.sideAnchorX(path, sunriseHour, -1, sideGap, sunriseY),
      sunriseY,
      SunPathGeometry.sideAnchorX(path, sunsetHour, 1, sideGap, sunsetY),
      sunsetY,
      path.centerX,
      path.centerY - path.radius - noonGap,
      path.centerX,
      path.centerY
    );
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
