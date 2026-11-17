/**
 * 太阳卡圆盘的配色、线宽与太阳点（= 时间轴「现在」圆点）的参数，以及可测的对比度工具。
 *
 * 这些常量放在 core 里是为了让 `Tools/core-check.ts` 能直接断言「弧够淡、线够细、
 * 太阳点与时间轴圆点逐项一致」——UI 侧只从 `common/Theme.ets` 的 palette / 本类取，
 * 全工程唯一来源，不在绘制代码里散落 hex 或魔法数字。
 *
 * **太阳点不再自创画法**：逐项照搬首页 0–24 时时间轴「现在」圆点——
 * 单个径向渐变圆、半径 [DOT_RADIUS]（5.5vp）、色标 [DOT_STOPS]（0 / 0.45 / 1）、
 * alpha [DOT_ALPHAS]（1 / 0.45 / 0，即中间就开始软化，边缘完全透明），渐变**从圆心 0 开始**。
 * 只有颜色不同：白天 `#D9A520`、夜间 `#F5D68A`。
 * 地平线以下用同尺寸、同渐变结构的柔化点（透明度减半），不画硬边描边圈。
 *
 * 白天弧 `#E8CFA0`（线宽 1.6vp，只作路径示意）；夜间弧/虚线保持原样（1.5vp、4/4vp）。
 */
export class SunDialColors {
  /** 白天卡片的底色（对比度计算的基准）。 */
  static readonly DAY_CARD: string = '#FFFDFA';
  /** 白天弧：淡金色，仅作路径示意。 */
  static readonly DAY_ARC: string = '#E8CFA0';
  /** 白天太阳点：金色（与时间轴圆点同结构、同尺寸）。 */
  static readonly DAY_SUN_DOT: string = '#D9A520';
  /** 夜间弧：保持原来的金色。 */
  static readonly NIGHT_ARC: string = '#F5D68A';
  /** 夜间太阳点：保持原来的金色。 */
  static readonly NIGHT_SUN_DOT: string = '#F5D68A';
  /** 夜间虚线（palette.subtle 的夜间值）：中性灰。 */
  static readonly NIGHT_DASH: string = '#9AA7BF';

  /** 白天弧线宽（vp）：细线，只作路径示意。 */
  static readonly DAY_ARC_WIDTH: number = 1.6;
  /** 夜晚虚线线宽（vp）。 */
  static readonly NIGHT_ARC_WIDTH: number = 1.5;
  /** 夜晚虚线间隔（vp）：线宽 1.5 时 4/4 与原来的 6/6 视觉密度相当。 */
  static readonly NIGHT_DASH_LENGTH: number = 4;

  /**
   * 太阳点 / 时间轴圆点的渐变半径（vp）。
   *
   * 时间轴那颗点就是 11×11vp 的盒子 + `radialGradient(radius: 5.5)`；太阳点照搬。
   */
  static readonly DOT_RADIUS: number = 5.5;
  /** 渐变色标位置（与时间轴圆点一致）：0 / 0.45 / 1。 */
  static readonly DOT_STOPS: number[] = [0, 0.45, 1];
  /** 渐变色标 alpha（与时间轴圆点一致）：1 / 0.45 / 0 —— 从圆心开始柔和过渡。 */
  static readonly DOT_ALPHAS: number[] = [1, 0.45, 0];
  /** 地平线以下柔化点的 alpha 缩放（同尺寸同画法，只是更淡）。 */
  static readonly DOT_BELOW_HORIZON_SCALE: number = 0.5;

  /** 给 `#RRGGBB` 叠一层 alpha（`#AARRGGBB`）：渐变与 Canvas 都只吃字符串颜色。 */
  static withAlpha(hex: string, alpha: number): string {
    if (hex.length !== 7) {
      return hex;
    }
    const value: number = Math.max(0, Math.min(255, Math.round(alpha * 255)));
    const body: string = value < 16 ? `0${value.toString(16)}` : value.toString(16);
    return `#${body}${hex.substring(1)}`.toUpperCase();
  }

  /**
   * 按时间轴圆点的 alpha 序列生成三档颜色（0 / 0.45 / 1）。
   *
   * @param base 基础色（白天 `#D9A520` / 夜间 `#F5D68A`）
   * @param alphaScale 整体透明度缩放：1 = 地平线以上；0.5 = 地平线以下的柔化点。
   */
  static dotGradientColors(base: string, alphaScale: number = 1): string[] {
    const colors: string[] = [];
    for (const alpha of SunDialColors.DOT_ALPHAS) {
      colors.push(SunDialColors.withAlpha(base, alpha * alphaScale));
    }
    return colors;
  }

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
