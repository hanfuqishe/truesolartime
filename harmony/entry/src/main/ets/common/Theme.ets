/**
 * 白天／夜间两套主题。
 *
 * 与首页大卡片的底色同一套判定：太阳高度角高于 -0.833° 就是白天，否则夜间。
 * 白天用浅色纸面（浅米底 + 白卡片），夜间用深蓝（与桌面卡片的夜间底色一致），
 * 两套主题的强调色分别是橙与金。
 */

import { SunDialColors } from '../core/SunDialColors';

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
   * 太阳卡圆盘「白天弧」的颜色（取值见 [SunDialColors]）。
   *
   * 白天是淡金色 `#E8CFA0`（只作路径示意，白卡上对比 ≈1.5）；夜间保持原来的金色 `#F5D68A`。
   */
  sunArc: string;
  /**
   * 太阳卡圆盘「当前太阳点」渐变的中段色 / 核心主色（取值见 [SunDialColors]）。
   *
   * 白天是金色 `#D9A520`；夜间保持原来的金色 `#F5D68A`。
   * 地平线 / 运动箭头 / 刻度点不用它（分别用 subtle / subtle / accent）。
   */
  sunDot: string;
  /**
   * 太阳点径向渐变的**中心**色（外沿是该色的全透明版本）。
   *
   * 白天亮金 `#F5C842`，夜间 `#F5D68A`；不再画硬描边。
   */
  sunDotCenter: string;

  constructor(page: string, card: string, chip: string, text: string, subtle: string, divider: string,
    accent: string, onAccent: string, sunArc: string, sunDot: string, sunDotCenter: string) {
    this.page = page;
    this.card = card;
    this.chip = chip;
    this.text = text;
    this.subtle = subtle;
    this.divider = divider;
    this.accent = accent;
    this.onAccent = onAccent;
    this.sunArc = sunArc;
    this.sunDot = sunDot;
    this.sunDotCenter = sunDotCenter;
  }
}

const DAY: AppPalette = new AppPalette(
  '#FFF8F1', '#FFFDFA', '#F2E3D3', '#211A15', '#6E5A49', '#E7D8C8', '#B4550A', '#FFFFFF',
  // 白天弧：淡金色；太阳点：中心亮金 → 中段金 → 外沿透明的径向渐变（无硬描边）。
  SunDialColors.DAY_ARC, SunDialColors.DAY_SUN_DOT, SunDialColors.DAY_SUN_DOT_CENTER
);

const NIGHT: AppPalette = new AppPalette(
  '#0B1220', '#16203A', '#24304F', '#E8EDF7', '#9AA7BF', '#24304F', '#F5D68A', '#0B1220',
  // 夜间：弧与太阳点都保持原来的金色，太阳点同样是径向渐变（中心/中段同色）。
  SunDialColors.NIGHT_ARC, SunDialColors.NIGHT_SUN_DOT, SunDialColors.NIGHT_SUN_DOT_CENTER
);

export function paletteFor(isDay: boolean): AppPalette {
  return isDay ? DAY : NIGHT;
}
