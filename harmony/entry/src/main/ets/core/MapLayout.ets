/**
 * 宽屏首页地图高度的纯计算。
 *
 * `aspectH` 是地图按原比例得到的下限；`fillH` 是「视口 − 上方内容 − 间距 − 页脚 − 卡片装饰」
 * 得到的铺满高度。宽屏取两者较大值；负值 / NaN / Infinity 一律退回 `aspectH`，
 * 避免异常尺寸把地图压成 0 高。
 */
export function fitMapHeight(aspectH: number, fillH: number): number {
  const base: number = Number.isFinite(aspectH) && aspectH > 0 ? aspectH : 0;
  if (!Number.isFinite(fillH) || fillH <= 0) {
    return base;
  }
  return Math.max(base, fillH);
}
