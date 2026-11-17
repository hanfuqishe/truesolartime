/**
 * 太阳卡圆盘的配色、线宽与太阳点渐变参数，以及可测的对比度工具。
 *
 * 这些常量放在 core 里是为了让 `Tools/core-check.ts` 能直接断言「弧够淡、点够亮、线够细、
 * 渐变三档色值」——UI 侧只从 `common/Theme.ets` 的 palette / 本类取，全工程唯一来源，
 * 不在绘制代码里散落 hex 或魔法数字。
 *
 * 白天（白卡 `#FFFDFA`）：
 *   - 白天弧 `#E8CFA0`：淡金色，只作路径示意（对比 ≈1.5，看得见但不抢眼），线宽 1.6vp；
 *   - 太阳点：**柔和边缘的径向渐变**（中心 `#F5C842` → 中段 `#D9A520` → 外沿透明），
 *     核心约 4vp、柔光到 9vp；不再画硬描边（[DOT_RING_ALPHA] = 0）；
 *   - 刻度和地平线/箭头不在这里：它们沿用 accent / subtle。
 * 夜间：弧与太阳点都保持原来的金色 `#F5D68A`，虚线 `#9AA7BF`、线宽 1.5vp、间隔 4/4vp。
 */
export class SunDialColors {
  /** 白天卡片的底色（对比度计算的基准）。 */
  static readonly DAY_CARD: string = '#FFFDFA';
  /** 白天弧：淡金色，仅作路径示意。 */
  static readonly DAY_ARC: string = '#E8CFA0';
  /** 白天太阳点渐变：中心亮金。 */
  static readonly DAY_SUN_DOT_CENTER: string = '#F5C842';
  /** 白天太阳点渐变：中段金（也是核心实心的主色）。 */
  static readonly DAY_SUN_DOT: string = '#D9A520';
  /** 夜间弧：保持原来的金色。 */
  static readonly NIGHT_ARC: string = '#F5D68A';
  /** 夜间太阳点渐变：中心与中段都保持原来的金色。 */
  static readonly NIGHT_SUN_DOT_CENTER: string = '#F5D68A';
  static readonly NIGHT_SUN_DOT: string = '#F5D68A';
  /** 夜间虚线（palette.subtle 的夜间值）：中性灰。 */
  static readonly NIGHT_DASH: string = '#9AA7BF';

  /** 白天弧线宽（vp）：细线，只作路径示意。 */
  static readonly DAY_ARC_WIDTH: number = 1.6;
  /** 夜晚虚线线宽（vp）。 */
  static readonly NIGHT_ARC_WIDTH: number = 1.5;
  /** 夜晚虚线间隔（vp）：线宽 1.5 时 4/4 与原来的 6/6 视觉密度相当。 */
  static readonly NIGHT_DASH_LENGTH: number = 4;
  /** 太阳点核心实心半径（vp）。 */
  static readonly DOT_CORE_RADIUS: number = 4;
  /** 太阳点柔光外沿半径（vp）：核心的 2.25 倍（4 → 9）。 */
  static readonly DOT_GLOW_RADIUS: number = 9;
  /** 渐变的「中段实心」停点：核心 4 / 柔光 9 ≈ 0.44。 */
  static readonly DOT_CORE_STOP: number = 0.44;
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
