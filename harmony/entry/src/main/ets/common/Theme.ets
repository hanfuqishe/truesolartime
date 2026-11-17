/**
 * 白天／夜间两套主题。
 *
 * 与首页大卡片的底色同一套判定：太阳高度角高于 -0.833° 就是白天，否则夜间。
 * 白天用浅色纸面（浅米底 + 白卡片），夜间用深蓝（与桌面卡片的夜间底色一致），
 * 两套主题的强调色分别是橙与金。
 */

export class AppPalette {
  /** 页面底色。 */
  page: string;
  /** 普通卡片底色。 */
  card: string;
  /** 卡片里的次级底（按钮、输入框、选中态）。 */
  chip: string;
  /** 主要文字。 */
  text: string;
  /** 次要文字与说明。 */
  subtle: string;
  /** 分隔线。 */
  divider: string;
  /** 强调色（标题旁的地名、按钮主色）。 */
  accent: string;
  /** 强调色上的文字。 */
  onAccent: string;
  /**
   * 太阳卡圆盘「白天弧」的颜色。
   *
   * 白天用 accent 的 65% 不透明度（`#A6B4550A`）：在白卡片上更轻，又仍与夜晚虚线明显区分；
   * 夜间保持原来的金色实色（`#F5D68A`），与地平线/太阳点/刻度/箭头区分开 —— 那几样都不用它。
   */
  sunArc: string;

  constructor(page: string, card: string, chip: string, text: string, subtle: string, divider: string,
    accent: string, onAccent: string, sunArc: string) {
    this.page = page;
    this.card = card;
    this.chip = chip;
    this.text = text;
    this.subtle = subtle;
    this.divider = divider;
    this.accent = accent;
    this.onAccent = onAccent;
    this.sunArc = sunArc;
  }
}

const DAY: AppPalette = new AppPalette(
  '#FFF8F1', '#FFFDFA', '#F2E3D3', '#211A15', '#6E5A49', '#E7D8C8', '#B4550A', '#FFFFFF',
  // 白天弧：强调色橙棕的 65% 不透明度，浅色卡片上不再发沉。
  '#A6B4550A'
);

const NIGHT: AppPalette = new AppPalette(
  '#0B1220', '#16203A', '#24304F', '#E8EDF7', '#9AA7BF', '#24304F', '#F5D68A', '#0B1220',
  // 夜间弧：保持原来的金色实色（与改版前完全一致）。
  '#F5D68A'
);

export function paletteFor(isDay: boolean): AppPalette {
  return isDay ? DAY : NIGHT;
}
