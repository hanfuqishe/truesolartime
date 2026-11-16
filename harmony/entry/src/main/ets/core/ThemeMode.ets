/**
 * 界面与桌面卡片的配色模式：自动 / 强制亮色 / 强制暗色（与 Android 的 `ThemeMode` 一致）。
 *
 * 「自动」是**默认值，也是 1.4.x 之前的唯一行为**：白天（太阳在地平线上）用亮色、夜里用暗色，
 * 不看系统的深色开关 —— 太阳落山的那一刻整个界面一起换色。
 * 强制模式只是忽略日出日落，其余渲染逻辑（关键时间配色、时间轴、卡片渐变、太阳弧）完全一样：
 * 太阳弧上的圆点位置永远按真实太阳高度角算，不受这里影响。
 *
 * 这里只有纯逻辑（值 = 偏好里存的字符串），读写偏好放在 services/Store.ets。
 */

export class ThemeMode {
  /** 按日出日落自动切换（默认）。 */
  static readonly AUTO: string = 'AUTO';
  /** 永远亮色。 */
  static readonly LIGHT: string = 'LIGHT';
  /** 永远暗色。 */
  static readonly DARK: string = 'DARK';
  /** 设置页里的三个选项（顺序即界面顺序）。 */
  static readonly OPTIONS: string[] = ['AUTO', 'LIGHT', 'DARK'];

  /**
   * 存储里的名字 → 规范化后的模式。
   *
   * 认不出来（旧版本没有这个键、值被人为改坏、大小写不对）一律回「自动」——
   * 宁可退回旧行为，也不要因为一个坏字符串让界面永远停在暗色。
   */
  static fromName(name: string): string {
    if (name === ThemeMode.LIGHT) {
      return ThemeMode.LIGHT;
    }
    if (name === ThemeMode.DARK) {
      return ThemeMode.DARK;
    }
    return ThemeMode.AUTO;
  }

  /**
   * 当前该不该用暗色。
   *
   * @param mode 规范化后的模式（未经 [fromName] 的字符串也安全：非法值当自动）。
   * @param sunIsUp 太阳是否在地平线之上（页面用 `snapshot.isDay()`，设置页用太阳高度角 > -0.833°）。
   *   [AUTO] 用它，[LIGHT]/[DARK] 直接忽略它。
   */
  static isDark(mode: string, sunIsUp: boolean): boolean {
    const normalized: string = ThemeMode.fromName(mode);
    if (normalized === ThemeMode.LIGHT) {
      return false;
    }
    if (normalized === ThemeMode.DARK) {
      return true;
    }
    return !sunIsUp;
  }

  /** 该不该用亮色（页面配色开关统一用它取反，免得两处各写一遍）。 */
  static isLight(mode: string, sunIsUp: boolean): boolean {
    return !ThemeMode.isDark(mode, sunIsUp);
  }

  /** 设置页里的选项文案（鸿蒙端目前只有中文界面）。 */
  static label(mode: string): string {
    const normalized: string = ThemeMode.fromName(mode);
    if (normalized === ThemeMode.LIGHT) {
      return '亮色';
    }
    if (normalized === ThemeMode.DARK) {
      return '暗色';
    }
    return '自动';
  }

  /** 设置页里的说明文字：让用户知道「自动」到底是按什么切的。 */
  static description(mode: string): string {
    const normalized: string = ThemeMode.fromName(mode);
    if (normalized === ThemeMode.LIGHT) {
      return '始终浅色纸面，不看日出日落';
    }
    if (normalized === ThemeMode.DARK) {
      return '始终深蓝夜色，不看日出日落';
    }
    return '白天亮色、夜晚暗色（按日出日落，与旧版本一致）';
  }
}
