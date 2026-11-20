/**
 * 常用城市 chip 的贪心排布（与 Android / iOS 的 `packRows` 同语义）。
 *
 * chip 宽度由调用方实测后传入；`gap` 是相邻 chip 间距。放不下就换行；
 * 单个 chip 比整行宽时独占一行，不做缩放。
 */
export function packRows(itemWidths: number[], rowWidth: number, gap: number = 8): number[][] {
  const rows: number[][] = [];
  if (itemWidths.length === 0) {
    return rows;
  }
  if (rowWidth <= 0) {
    for (let index: number = 0; index < itemWidths.length; index++) {
      rows.push([index]);
    }
    return rows;
  }
  let current: number[] = [];
  let used: number = 0;
  for (let index: number = 0; index < itemWidths.length; index++) {
    const width: number = itemWidths[index];
    const needed: number = current.length === 0 ? width : used + gap + width;
    if (current.length === 0 || needed <= rowWidth) {
      current.push(index);
      used = needed;
    } else {
      rows.push(current);
      current = [index];
      used = width;
    }
  }
  if (current.length > 0) {
    rows.push(current);
  }
  return rows;
}
