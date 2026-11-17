/**
 * 太阳卡圆盘的配色、线宽与太阳点三层画法参数，以及可测的对比度工具。
 *
 * 这些常量放在 core 里是为了让 `Tools/core-check.ts` 能直接断言「弧够淡、点够清晰、线够细、
 * 三层色值/尺寸」——UI 侧只从 `common/Theme.ets` 的 palette / 本类取，全工程唯一来源，
 * 不在绘制代码里散落 hex 或魔法数字。
 *
 * 太阳点改成「清晰点 + 中心高光 + 外圈炫光」三层（不再是从圆心就开始渐变的整团光斑）：
 *   ① 实心核心：半径 [DOT_CORE_RADIUS]，白天 `#B8860B`（对白卡 ≥3:1），夜里 `#E0B84A`；
 *   ② 中心高光：半径 [DOT_HIGHLIGHT_RADIUS]，白天 `#FFF2C8`、夜里 `#FFF8E1`，alpha 1.0；
 *   ③ 外圈柔光：从核心半径到 [DOT_GLOW_RADIUS] 的径向渐变，白天 `#D9A520` 0.45 → 0，
 *      夜里 `#F5D68A` 0.45 → 0（起点就是核心半径，不遮住核心）。
 *  地平线以下不画光斑：只留一圈 1vp 的空心描边。
 *
 * 白天弧 `#E8CFA0`（线宽 1.6vp，只作路径示意）；夜间弧/虚线保持原样（1.5vp、4/4vp）。
 */
export class SunDialColors {
  /** 白天卡片的底色（对比度计算的基准）。 */
  static readonly DAY_CARD: string = '#FFFDFA';
  /** 白天弧：淡金色，仅作路径示意。 */
  static readonly DAY_ARC: string = '#E8CFA0';
  /** 白天太阳点：实心核心（深金，对白卡 ≥3:1）。 */
  static readonly DAY_SUN_DOT_CORE: string = '#B8860B';
  /** 白天太阳点：中心高光（近白暖金，alpha 1.0）。 */
  static readonly DAY_SUN_DOT_HIGHLIGHT: string = '#FFF2C8';
  /** 白天太阳点：外圈柔光。 */
  static readonly DAY_SUN_GLOW: string = '#D9A520';
  /** 夜间弧：保持原来的金色。 */
  static readonly NIGHT_ARC: string = '#F5D68A';
  /** 夜间太阳点：实心核心 / 中心高光 / 外圈柔光。 */
  static readonly NIGHT_SUN_DOT_CORE: string = '#E0B84A';
  static readonly NIGHT_SUN_DOT_HIGHLIGHT: string = '#FFF8E1';
  static readonly NIGHT_SUN_GLOW: string = '#F5D68A';
  /** 夜间虚线（palette.subtle 的夜间值）：中性灰。 */
  static readonly NIGHT_DASH: string = '#9AA7BF';

  /** 白天弧线宽（vp）：细线，只作路径示意。 */
  static readonly DAY_ARC_WIDTH: number = 1.6;
  /** 夜晚虚线线宽（vp）。 */
  static readonly NIGHT_ARC_WIDTH: number = 1.5;
  /** 夜晚虚线间隔（vp）：线宽 1.5 时 4/4 与原来的 6/6 视觉密度相当。 */
  static readonly NIGHT_DASH_LENGTH: number = 4;

  /** 太阳点核心实心半径（vp）：清晰点，不做渐变淡化。 */
  static readonly DOT_CORE_RADIUS: number = 2.4;
  /** 中心高光半径（vp）：“炫”的关键，小、亮、实心。 */
  static readonly DOT_HIGHLIGHT_RADIUS: number = 0.9;
  /** 外圈柔光外沿半径（vp）。 */
  static readonly DOT_GLOW_RADIUS: number = 5.5;
  /** 外圈柔光渐变起点半径（vp）：= 核心半径，柔光不盖住核心。 */
  static readonly DOT_GLOW_START_RADIUS: number = 2.4;
  /** 外圈柔光起点 alpha（向外线性淡出到 0）。 */
  static readonly DOT_GLOW_ALPHA: number = 0.45;
  /** 地平线以下空心点的描边半径（vp）与线宽（vp）。 */
  static readonly DOT_HOLLOW_RADIUS: number = 2.4;
  static readonly DOT_HOLLOW_STROKE_WIDTH: number = 1;
  /** 空心点垫底圆半径（vp）：避免与夜晚虚线糊在一起，不算光斑。 */
  static readonly DOT_HOLLOW_PAD_RADIUS: number = 3.0;
  /** 太阳点硬描边的透明度：已去掉（<0.15 视为没有硬边），保留常量便于断言。 */
  static readonly DOT_RING_ALPHA: number = 0;

  /** `#RRGGBB` / `#AARRGGBB` → `[r, g, b]`（0–255，忽略 alpha）。 */
  static rgb(hex: string): number[] {
    let body: string = hex;
    if (body.length === 9) {
      body = body.substring(3);
    } else if (body.length === 7) {
      body = body.substring(1);
    } else {
      return [0, 0, 0];
    }
    return [
      Number.parseInt(body.substring(0, 2), 16),
      Number.parseInt(body.substring(2, 4), 16),
      Number.parseInt(body.substring(4, 6), 16)
    ];
  }

  /** 相对亮度（WCAG 2.x：sRGB → 线性 → 0.2126R + 0.7152G + 0.0722B）。 */
  static relativeLuminance(hex: string): number {
    const rgb: number[] = SunDialColors.rgb(hex);
    const linear = (channel: number): number => {
      const value: number = channel / 255;
      return value <= 0.03928 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4);
    };
    return 0.2126 * linear(rgb[0]) + 0.7152 * linear(rgb[1]) + 0.0722 * linear(rgb[2]);
  }

  /** 两色的 WCAG 对比度（1–21）。 */
  static contrastRatio(foreground: string, background: string): number {
    const a: number = SunDialColors.relativeLuminance(foreground);
    const b: number = SunDialColors.relativeLuminance(background);
    const hi: number = Math.max(a, b);
    const lo: number = Math.min(a, b);
    return (hi + 0.05) / (lo + 0.05);
  }

  /** 「暖度」：`(R − B) / 255`。暖金为正、中性灰接近 0。 */
  static warmth(hex: string): number {
    const rgb: number[] = SunDialColors.rgb(hex);
    return (rgb[0] - rgb[2]) / 255;
  }

  /** 两色的 RGB 欧氏距离（0–441）。 */
  static rgbDistance(a: string, b: string): number {
    const first: number[] = SunDialColors.rgb(a);
    const second: number[] = SunDialColors.rgb(b);
    const dr: number = first[0] - second[0];
    const dg: number = first[1] - second[1];
    const db: number = first[2] - second[2];
    return Math.sqrt(dr * dr + dg * dg + db * db);
  }
}
