/**
 * 顶部标签行的「档位 + 字号」联合求解。
 *
 * 字号与档位互相依赖：先用 12fp 的自然宽度试档，档内放不下再逐 0.5fp 缩到 9fp，
 * 9fp 也放不下才退下一档 —— 不能先无条件缩字号再判档。
 */
export class DistrictLayoutPlan {
  tier: number;
  fontSize: number;

  constructor(tier: number, fontSize: number) {
    this.tier = tier;
    this.fontSize = fontSize;
  }
}

export class DistrictLayoutSolver {
  static readonly MIN_FONT: number = 9;
  static readonly BASE_FONT: number = 12;

  /**
   * @param utcWidth UTC 标签在 12fp 下的宽度
   * @param placeWidth 地点名在 12fp 下的自然宽度
   * @param labelWidth 「真太阳时」在 12fp 下的宽度
   * @param shichenWidth 时辰在 12fp 下的宽度
   * @param halfWidth 左右半栏宽度（档 0 用）
   * @param rowWidth 整行宽度（档 1/2/3 用）
   */
  static solve(utcWidth: number, placeWidth: number, labelWidth: number, shichenWidth: number,
      halfWidth: number, rowWidth: number): DistrictLayoutPlan {
    // 第一轮：12fp 自然宽度逐档试（0→1→2→3），能放下就保 12fp。
    for (let tier: number = 0; tier <= 3; tier++) {
      if (DistrictLayoutSolver.fits(tier, 12, utcWidth, placeWidth, labelWidth, shichenWidth,
        halfWidth, rowWidth)) {
        return new DistrictLayoutPlan(tier, DistrictLayoutSolver.BASE_FONT);
      }
    }
    // 第二轮：所有档在 12fp 都放不下，才在每档内从 11.5 缩到 9fp。
    for (let tier: number = 0; tier <= 3; tier++) {
      for (let size: number = DistrictLayoutSolver.BASE_FONT - 0.5;
        size >= DistrictLayoutSolver.MIN_FONT; size -= 0.5) {
        if (DistrictLayoutSolver.fits(tier, size, utcWidth, placeWidth, labelWidth, shichenWidth,
          halfWidth, rowWidth)) {
          return new DistrictLayoutPlan(tier, size);
        }
      }
    }
    // 40 字级别：档 3、最小字号、交给省略号。
    return new DistrictLayoutPlan(3, DistrictLayoutSolver.MIN_FONT);
  }

  private static fits(tier: number, size: number, utcWidth: number, placeWidth: number,
      labelWidth: number, shichenWidth: number, halfWidth: number, rowWidth: number): boolean {
    const scale: number = size / DistrictLayoutSolver.BASE_FONT;
    if (tier === 0) {
      // 右半（真太阳时 + 时辰）在 12fp 下也要放得下。
      if (labelWidth + shichenWidth + 6 > halfWidth) {
        return false;
      }
      return placeWidth * scale <= halfWidth - utcWidth * scale - 6;
    }
    if (tier === 1) {
      return placeWidth * scale <= rowWidth - (utcWidth + shichenWidth) * scale - 12;
    }
    return placeWidth * scale <= rowWidth - shichenWidth * scale - 6;
  }
}

/**
 * 大卡片顶部「UTC + 地名 + 真太阳时 + 时辰」的四档退化（纯函数）。
 *
 * 目标：**地名优先保完整**，宁可先隐藏标签、再隐藏 UTC，最后才用省略号。
 * 输入宽度由调用方按「字符数 × 字号」估算（与 Android 同思路），本文件不依赖 UI。
 *
 * 档 0：UTC + 地名 + 「真太阳时」+ 时辰 都能放下；
 * 档 1：放不下 → 隐藏「真太阳时」标签，地名占用它的宽度；
 * 档 2：还放不下 → 再隐藏 UTC，地名占满整行；
 * 档 3：仍放不下 → 只能用省略号。
 */
export class DistrictLayoutTier {
  static readonly FULL: number = 0;
  static readonly HIDE_LABEL: number = 1;
  static readonly HIDE_UTC: number = 2;
  static readonly ELLIPSIS: number = 3;

  /** 相邻元素之间的最小间距（与视图里的 margin 一致）。 */
  static readonly GAP: number = 8;

  /** 地区与竖线之间、地区与 UTC 之间留的间距（安卓为 6dp）。 */
  static readonly CITY_GAP: number = 6;

  /**
   * 左右两半结构下的档位（与 Android `SmallRowLayout.cityRowTier` 等价）。
   *
   * 左半：`UTC + 地区`；右半：`真太阳时 + 时辰`。右半放不下 → 隐藏「真太阳时」；
   * 左半仍放不下 → 隐藏 UTC；还放不下 → 省略号。
   */
  static ofHalves(utcWidth: number, placeWidth: number, labelWidth: number, shichenWidth: number,
      halfWidth: number): number {
    const gap: number = DistrictLayoutTier.CITY_GAP;
    if (utcWidth + placeWidth + gap <= halfWidth && labelWidth + shichenWidth + gap <= halfWidth) {
      return DistrictLayoutTier.FULL;
    }
    if (utcWidth + placeWidth + gap <= halfWidth) {
      return DistrictLayoutTier.HIDE_LABEL;
    }
    if (placeWidth <= halfWidth) {
      return DistrictLayoutTier.HIDE_UTC;
    }
    return DistrictLayoutTier.ELLIPSIS;
  }

  /**
   * 按地点名称长度选档（先缩字号，再退档）：
   * - 名称 ≤ 6 字（短）→ 档 0；
   * - 7–20 字符 → 档 1（收「真太阳时」，保留时区与时辰）；
   * - ≤ 30 字符 → 档 2（再收时区）；
   * - 更长 → 档 3（地点尾部省略号）。
   */
  static ofNameLength(utcWidth: number, placeWidth: number, labelWidth: number, shichenWidth: number,
      halfWidth: number, nameLength: number): number {
    // 短名称（≤6 字）一律档 0；缩字号后仍放不下才按长度退档。
    if (nameLength <= 6 || DistrictLayoutTier.ofHalves(utcWidth, placeWidth, labelWidth, shichenWidth,
      halfWidth) === DistrictLayoutTier.FULL) {
      return DistrictLayoutTier.FULL;
    }
    if (nameLength <= 20) {
      return DistrictLayoutTier.HIDE_LABEL;
    }
    if (nameLength <= 30) {
      return DistrictLayoutTier.HIDE_UTC;
    }
    return DistrictLayoutTier.ELLIPSIS;
  }

  /**
   * 计算档位。
   *
   * @param utcWidth UTC 标签宽度（如 `UTC+8`）
   * @param placeWidth 地名宽度（已按缩字号后的字号估算）
   * @param labelWidth 「真太阳时」标签宽度
   * @param shichenWidth 时辰宽度（如 `申时`）
   * @param rowWidth 整行可用宽度
   */
  static of(utcWidth: number, placeWidth: number, labelWidth: number, shichenWidth: number,
      rowWidth: number): number {
    const gap: number = DistrictLayoutTier.GAP;
    // 档 0：四段 + 三个间距。
    if (utcWidth + placeWidth + labelWidth + shichenWidth + gap * 3 <= rowWidth) {
      return DistrictLayoutTier.FULL;
    }
    // 档 1：隐藏标签，地名仍与 UTC、时辰同排。
    if (utcWidth + placeWidth + shichenWidth + gap <= rowWidth) {
      return DistrictLayoutTier.HIDE_LABEL;
    }
    // 档 2：再隐藏 UTC。
    if (placeWidth + shichenWidth + gap <= rowWidth) {
      return DistrictLayoutTier.HIDE_UTC;
    }
    return DistrictLayoutTier.ELLIPSIS;
  }
}
