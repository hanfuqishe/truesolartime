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

  constructor(page: string, card: string, chip: string, text: string, subtle: string, divider: string,
    accent: string, onAccent: string) {
    this.page = page;
    this.card = card;
    this.chip = chip;
    this.text = text;
    this.subtle = subtle;
    this.divider = divider;
    this.accent = accent;
    this.onAccent = onAccent;
  }
}

const DAY: AppPalette = new AppPalette(
  '#FFF8F1', '#FFFDFA', '#F2E3D3', '#211A15', '#6E5A49', '#E7D8C8', '#B4550A', '#FFFFFF'
);

const NIGHT: AppPalette = new AppPalette(
  '#0B1220', '#16203A', '#24304F', '#E8EDF7', '#9AA7BF', '#24304F', '#F5D68A', '#0B1220'
);

export function paletteFor(isDay: boolean): AppPalette {
  return isDay ? DAY : NIGHT;
}
