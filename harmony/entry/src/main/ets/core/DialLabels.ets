/**
 * 太阳圆盘上的三段时间标签：「说明 + 半角空格 + 时间」。
 *
 * 文案跟随界面语言：简体/繁体都用中文（日出/日落/上中天），英文用
 * Sunrise / Sunset / Solar noon；极昼/极夜仍只有「极昼」「极夜」两个词。
 */
export class DialLabels {
  static sunrise(language: string, clock: string): string {
    return `${DialLabels.isEnglish(language) ? 'Sunrise' : '日出'} ${clock}`;
  }

  static sunset(language: string, clock: string): string {
    return `${DialLabels.isEnglish(language) ? 'Sunset' : '日落'} ${clock}`;
  }

  static noon(language: string, clock: string): string {
    return `${DialLabels.isEnglish(language) ? 'Solar noon' : '上中天'} ${clock}`;
  }

  static polar(midnightSun: boolean, language: string): string {
    if (DialLabels.isEnglish(language)) {
      return midnightSun ? 'Midnight sun' : 'Polar night';
    }
    return midnightSun ? '极昼' : '极夜';
  }

  private static isEnglish(language: string): boolean {
    return language.startsWith('en');
  }
}
