/**
 * 首页标题行（齿轮图标左边）的位置徽标规则，与 Android 的 `ui/HeaderBadge.kt` 一致。
 *
 * 只有**跟随 GPS** 时才显示 `GPS` 小徽标：它提示的是「这个位置来自定位」，不是地名。
 * 选了预设城市、或手动输入经纬度时什么都不显示 —— 地名已经在下方大卡片里，
 * 标题行再放一份只会挤掉标题（长地址还会被截成「New …」）。
 */

import { PlaceSource } from './Place';

export class PlaceBadgeLogic {
  /** 徽标文案：跟随 GPS 时显示这个固定的短名。 */
  static readonly GPS_TEXT: string = 'GPS';

  /**
   * 该来源要不要显示 `GPS` 徽标。
   *
   * 只有 `PlaceSource.GPS` 为 true；预设城市（`MANUAL`）、手动坐标、首启动的
   * `DEFAULT` 一律 false，调用处整块条件渲染，不占位、不留空白间距。
   */
  static showsGps(source: PlaceSource): boolean {
    return source === PlaceSource.GPS;
  }
}
