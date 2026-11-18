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
