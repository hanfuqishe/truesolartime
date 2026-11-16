/**
 * 行政区划名拼接规则，与 Android 端 DistrictResolver、iOS 的 DistrictNaming 保持一致：
 * 最多保留三级、去掉占位字段、去重；分隔符按名字本身判断 —— 含汉字且没有拉丁字母时
 * 直接相连（「广东省深圳市南山区」「上海市黄浦区」），其余用 ", " 连接
 * （「New York, Manhattan」）。短名取最细一级。
 *
 * 取数（系统逆地理编码 / OSM 兜底）放在 services/DistrictService.ets。
 */

export class DistrictNames {
  /** 完整名，例如 "广东省, 深圳市, 南山区"。 */
  full: string;
  /** 最细一级，例如 "南山区"。 */
  short: string;
  /** ISO 3166-1 alpha-2 国家码（小写），用于查标准时区。 */
  countryCode: string;

  constructor(full: string, short: string, countryCode: string = '') {
    this.countryCode = countryCode;
    this.full = full;
    this.short = short;
  }
}

/** 系统或地图服务用来占位、本身不是地名的上级字段。 */
const PLACEHOLDER_REGIONS: string[] = ['市辖区', '县', '省直辖县级行政区划', '自治区直辖县级行政区划'];

/** 太长的没用：一串行政区划在卡片里会被省略号吃掉，只留最细的三级。 */
const MAX_LEVELS: number = 3;

export class DistrictNameLogic {
  static cleanName(value: string): string {
    const trimmed: string = value.trim();
    if (trimmed.length === 0 || trimmed === '[]') {
      return '';
    }
    return trimmed;
  }

  /**
   * 按「区县、市、省」的顺序传入任意层级，返回拼接后的名字。
   * 全为空或全部是占位字段时返回 null。
   *
   * 分隔符按**名字本身**判断（不是界面语言）：中文名（含汉字、无拉丁字母）从粗到细
   * 直接相连（「广东省深圳市南山区」），其余由细到粗用「, 」连接（「Manhattan, New York」）。
   */
  static composeNames(parts: string[]): DistrictNames | null {
    const levels: string[] = [];
    for (const part of parts) {
      const name: string = DistrictNameLogic.cleanName(part);
      if (name.length === 0) {
        continue;
      }
      if (PLACEHOLDER_REGIONS.indexOf(name) >= 0) {
        continue;
      }
      if (levels.indexOf(name) >= 0) {
        continue;
      }
      if (levels.length >= MAX_LEVELS) {
        break;
      }
      levels.push(name);
    }
    if (levels.length === 0) {
      return null;
    }
    const full: string = DistrictNameLogic.isChineseGrouping(levels)
      ? DistrictNameLogic.joinCoarsestFirst(levels)
      : levels.join(', ');
    return new DistrictNames(full, levels[0]);
  }

  /**
   * 这几级名字能不能按中文习惯直接相连：**至少有一个汉字，且一个拉丁字母都没有**。
   *
   * 「黄浦区」+「上海市」→ true；「Manhattan」+「纽约」→ false（中英混排用逗号，
   * 免得拼出「纽约Manhattan」）。规则与 Android 的 `isChineseGrouping`、
   * iOS 的 `DistrictNaming.isChineseGrouping` 一致。
   */
  static isChineseGrouping(values: string[]): boolean {
    let hasChinese: boolean = false;
    for (const value of values) {
      const name: string = DistrictNameLogic.cleanName(value);
      if (name.length === 0) {
        continue;
      }
      for (let index = 0; index < name.length; index++) {
        const code: number = name.charCodeAt(index);
        if ((code >= 0x4E00 && code <= 0x9FFF) || (code >= 0x3400 && code <= 0x4DBF)) {
          hasChinese = true;
        } else if ((code >= 0x41 && code <= 0x5A) || (code >= 0x61 && code <= 0x7A)) {
          return false;
        }
      }
    }
    return hasChinese;
  }

  /**
   * 中文名从粗到细直接相连（入参是最细→最粗的顺序）。
   *
   * 上级已经包含在下一级开头时只留更长的那一份：「上海市」+「上海市黄浦区」→
   * 「上海市黄浦区」，不会写成「上海市上海市黄浦区」。
   */
  private static joinCoarsestFirst(levels: string[]): string {
    let joined: string = '';
    for (let index = levels.length - 1; index >= 0; index--) {
      const name: string = levels[index];
      if (joined.length === 0) {
        joined = name;
      } else if (name.startsWith(joined)) {
        joined = name;
      } else if (!joined.endsWith(name)) {
        joined = joined + name;
      }
    }
    return joined;
  }

  /**
   * 从 OSM 的 display_name 里挑出「区/县/旗」一级的名字，例如
   * "均乐社区, 南京东路街道, 上海市, 黄浦区, 上海市, 中国" → "黄浦区"。
   * OSM 常把城市的「区」只写进 display_name，address 字段里没有，只能这样补。
   */
  static pickDistrictFromDisplay(display: string, city: string): string {
    if (display.length === 0) {
      return '';
    }
    for (const raw of display.split(',')) {
      const name: string = raw.trim();
      if (name.length === 0 || name === city) {
        continue;
      }
      if (DistrictNameLogic.isPoiArea(name)) {
        continue;
      }
      if (name.endsWith('区') || name.endsWith('县') || name.endsWith('旗')) {
        return name;
      }
    }
    return '';
  }

  /** 「XX社区 / XX园区」这类是点位而不是行政区，别当成区县。 */
  private static isPoiArea(name: string): boolean {
    const suffixes: string[] = ['社区', '小区', '园区', '街区', '校区', '景区', '厂区', '营区'];
    for (const suffix of suffixes) {
      if (name.endsWith(suffix)) {
        return true;
      }
    }
    return false;
  }

  /**
   * 「区县 + 上级」的写法：中文名直接相连（如「上海市黄浦区」「广东省深圳市南山区」），
   * 拉丁字母等非中文名用「, 」连接（如「New York, Manhattan」）—— 否则境外城市会被拼成
   * 「New YorkManhattan」这种粘在一起的怪串。与 Android 端 `pickNames`、
   * iOS 的 `DistrictNaming.joinChinese`/逗号写法一致。
   * 上级名本身已含该前缀时不再重复；没有区县时退回市，再退回省。
   */
  static pickNames(district: string, city: string, province: string): DistrictNames | null {
    const county: string = DistrictNameLogic.cleanName(district);
    const town: string = PLACEHOLDER_REGIONS.indexOf(DistrictNameLogic.cleanName(city)) >= 0 ? '' : DistrictNameLogic.cleanName(city);
    const region: string = PLACEHOLDER_REGIONS.indexOf(DistrictNameLogic.cleanName(province)) >= 0 ? '' : DistrictNameLogic.cleanName(province);
    if (county.length === 0) {
      const only: string = town.length > 0 ? town : region;
      if (only.length === 0) {
        return null;
      }
      return new DistrictNames(only, only);
    }
    const parents: string[] = [];
    if (town.length > 0) {
      parents.push(town);
    }
    if (region.length > 0) {
      parents.push(region);
    }
    let parent: string = '';
    for (const name of parents) {
      if (name !== county) {
        parent = name;
        break;
      }
    }
    let full: string = county;
    if (parent.length > 0 && !county.startsWith(parent)) {
      full = DistrictNameLogic.isChineseGrouping([parent, county]) ? parent + county : `${parent}, ${county}`;
    }
    // 短名只留区县；若区县就是全部（如县级市），短名与全名相同。
    return new DistrictNames(full, county);
  }

  /** 缓存是否该重查：没有名字、坐标移动超过 5 km、缓存过期或界面语言变了。 */
  static needsRefresh(
    hasCache: boolean,
    cachedLanguage: string,
    language: string,
    ageMillis: number,
    movedKm: number
  ): boolean {
    if (!hasCache) {
      return true;
    }
    if (cachedLanguage !== language) {
      return true;
    }
    if (!(ageMillis >= 0 && ageMillis <= 30 * 24 * 60 * 60 * 1000)) {
      return true;
    }
    return movedKm > 5.0;
  }
}
