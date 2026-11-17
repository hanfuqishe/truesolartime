/**
 * 太阳卡圆盘的固定配色与其可测的对比度工具。
 *
 * 颜色放在 core 里是为了让 `Tools/core-check.ts` 能直接断言「白天弧够轻、太阳点够明显、
 * 与夜晚虚线的色相区分」——UI 侧只从 `common/Theme.ets` 的 palette 取，palette 又引用这里，
 * 全工程唯一来源，不在绘制代码里散落 hex。
 *
 * 白天（白卡 `#FFFDFA`）：
 *   - 白天弧 `#E8CFA0`：淡金色，只作路径示意（对比 ≈1.5，看得见但不抢眼）；
 *   - 太阳点 `#D9A520`：亮金色实心（与弧对比 ≈1.48，靠一圈深金细描边把它从弧上「抠」出来）；
 *   - 太阳点描边 `#8A6508`：0.5 不透明度、1vp（与弧对比 ≈3.5）；
 *   - 刻度和地平线/箭头不在这里：它们沿用 accent / subtle。
 * 夜间：弧与太阳点都保持原来的金色 `#F5D68A`（描边透明），夜晚虚线是中性灰 `#9AA7BF`。
 */
export class SunDialColors {
  /** 白天卡片的底色（对比度计算的基准）。 */
  static readonly DAY_CARD: string = '#FFFDFA';
  /** 白天弧：淡金色，仅作路径示意。 */
  static readonly DAY_ARC: string = '#E8CFA0';
  /** 白天太阳点：亮金色实心。 */
  static readonly DAY_SUN_DOT: string = '#D9A520';
  /** 白天太阳点描边：深金色，绘制时叠 0.5 不透明度、1vp。 */
  static readonly DAY_SUN_DOT_RING: string = '#8A6508';
  /** 夜间弧：保持原来的金色。 */
  static readonly NIGHT_ARC: string = '#F5D68A';
  /** 夜间太阳点：保持原来的金色（与 accent 相同）。 */
  static readonly NIGHT_SUN_DOT: string = '#F5D68A';
  /** 夜间太阳点描边：全透明（画了也看不见，夜间视觉与改版前一致）。 */
  static readonly NIGHT_SUN_DOT_RING: string = '#00F5D68A';
  /** 夜间虚线（palette.subtle 的夜间值）：中性灰。 */
  static readonly NIGHT_DASH: string = '#9AA7BF';

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
