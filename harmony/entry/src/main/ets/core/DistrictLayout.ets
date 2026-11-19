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
