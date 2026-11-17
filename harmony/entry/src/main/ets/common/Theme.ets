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
   * 太阳卡圆盘「当前太阳点」的颜色（取值见 [SunDialColors]）。
   *
   * 白天是亮金色 `#D9A520`（实心）；夜间保持原来的金色 `#F5D68A`。
   * 地平线 / 运动箭头 / 刻度点不用它（分别用 subtle / subtle / accent）。
   */
  sunDot: string;
  /**
   * 太阳点外加的一圈细描边（绘制时叠 0.5 不透明度、1vp）。
   *
   * 白天 `#8A6508`：把亮金点从淡金弧上「抠」出来；夜间全透明，视觉与改版前完全一致。
   */
  sunDotRing: string;

  constructor(page: string, card: string, chip: string, text: string, subtle: string, divider: string,
    accent: string, onAccent: string, sunArc: string, sunDot: string, sunDotRing: string) {
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
    this.sunDotRing = sunDotRing;
  }
}

const DAY: AppPalette = new AppPalette(
  '#FFF8F1', '#FFFDFA', '#F2E3D3', '#211A15', '#6E5A49', '#E7D8C8', '#B4550A', '#FFFFFF',
  // 白天弧：淡金色，路径示意；太阳点：亮金色；点外再叠一圈深金细描边。
  SunDialColors.DAY_ARC, SunDialColors.DAY_SUN_DOT, SunDialColors.DAY_SUN_DOT_RING
);

const NIGHT: AppPalette = new AppPalette(
  '#0B1220', '#16203A', '#24304F', '#E8EDF7', '#9AA7BF', '#24304F', '#F5D68A', '#0B1220',
  // 夜间：弧与太阳点都保持原来的金色，描边全透明（视觉与改版前完全一致）。
  SunDialColors.NIGHT_ARC, SunDialColors.NIGHT_SUN_DOT, SunDialColors.NIGHT_SUN_DOT_RING
);

export function paletteFor(isDay: boolean): AppPalette {
  return isDay ? DAY : NIGHT;
}
