/**
 * 行政区划名拼接规则，与 Android 端 DistrictResolver 保持一致：
 * 最多保留三级、去掉占位字段、去重，完整名用 ", " 连接，短名取最细一级。
 *
 * 取数（系统逆地理编码 / OSM 兜底）放在 services/DistrictService.ets。
 */

export class DistrictNames {
  /** 完整名，例如 "广东省, 深圳市, 南山区"。 */
  full: string;
  /** 最细一级，例如 "南山区"。 */
  short: string;

  constructor(full: string, short: string) {
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
    return new DistrictNames(levels.join(', '), levels[0]);
  }

  /** 区县缺失时退回市或省，避免只显示一个空名字。 */
  static pickNames(district: string, city: string, province: string): DistrictNames | null {
    const county: string = DistrictNameLogic.cleanName(district);
    const town: string = PLACEHOLDER_REGIONS.indexOf(DistrictNameLogic.cleanName(city)) >= 0 ? '' : DistrictNameLogic.cleanName(city);
    const region: string = PLACEHOLDER_REGIONS.indexOf(DistrictNameLogic.cleanName(province)) >= 0 ? '' : DistrictNameLogic.cleanName(province);
    if (county.length === 0) {
      const only: string = town.length > 0 ? town : region;
      if (only.length === 0) {
        return null;
      }
      if (only === region && town.length === 0 && region.length > 0) {
        return new DistrictNames(region, region);
      }
      return new DistrictNames(only, only);
    }
    return DistrictNameLogic.composeNames([county, town, region]);
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
