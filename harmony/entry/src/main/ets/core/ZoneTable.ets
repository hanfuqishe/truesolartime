/**
 * 国家/地区 → 标准时区偏移。
 *
 * 用于「日出 / 上中天 / 日落」按当地标准时展示。优先级：
 *   1. 已知国家（单时区国家直接查表）；
 *   2. 多时区大国按经度分段（美国、加拿大、俄罗斯、澳大利亚、巴西、墨西哥、印尼、哈萨克）；
 *   3. 表里没有的，退回按经度每 15° 取整的近似（SolarTimeMath.standardZoneOffsetSeconds）。
 *
 * 中国全境（含港澳台）恒为 +8，不按经度算 —— 否则乌鲁木齐 87°E 会被算成 +6。
 */

export class ZoneTable {
  private static readonly MINUTES: Map<string, number> = ZoneTable.buildTable();

  private static buildTable(): Map<string, number> {
    const map: Map<string, number> = new Map<string, number>();
    // 东亚 / 东南亚
    map.set('cn', 480); map.set('hk', 480); map.set('mo', 480); map.set('tw', 480);
    map.set('jp', 540); map.set('kr', 540); map.set('kp', 540);
    map.set('sg', 480); map.set('my', 480); map.set('ph', 480); map.set('bn', 480);
    map.set('th', 420); map.set('vn', 420); map.set('la', 420); map.set('kh', 420);
    map.set('mm', 390); map.set('tl', 540); map.set('mn', 480);
    // 南亚 / 中亚 / 西亚
    map.set('bd', 360); map.set('in', 330); map.set('lk', 330); map.set('np', 345);
    map.set('pk', 300); map.set('af', 270); map.set('ir', 210);
    map.set('iq', 180); map.set('sa', 180); map.set('ae', 240); map.set('om', 240);
    map.set('qa', 180); map.set('kw', 180); map.set('bh', 180); map.set('ye', 180);
    map.set('jo', 180); map.set('il', 120); map.set('lb', 120); map.set('sy', 180);
    map.set('tr', 180); map.set('ge', 240); map.set('am', 240); map.set('az', 240);
    map.set('uz', 300); map.set('tm', 300); map.set('kg', 360); map.set('tj', 300);
    // 欧洲
    map.set('gb', 0); map.set('ie', 0); map.set('pt', 0); map.set('is', 0);
    map.set('fr', 60); map.set('de', 60); map.set('it', 60); map.set('es', 60);
    map.set('nl', 60); map.set('be', 60); map.set('ch', 60); map.set('at', 60);
    map.set('se', 60); map.set('no', 60); map.set('dk', 60); map.set('pl', 60);
    map.set('cz', 60); map.set('sk', 60); map.set('hu', 60); map.set('hr', 60);
    map.set('si', 60); map.set('rs', 60); map.set('ba', 60); map.set('me', 60);
    map.set('mk', 60); map.set('al', 60); map.set('lu', 60); map.set('mt', 60);
    map.set('li', 60); map.set('ad', 60); map.set('mc', 60); map.set('sm', 60);
    map.set('va', 60); map.set('gi', 60);
    map.set('gr', 120); map.set('bg', 120); map.set('ro', 120); map.set('md', 120);
    map.set('ua', 120); map.set('fi', 120); map.set('ee', 120); map.set('lv', 120);
    map.set('lt', 120); map.set('cy', 120); map.set('by', 180);
    // 非洲
    map.set('eg', 120); map.set('ly', 120); map.set('sd', 120); map.set('ss', 120);
    map.set('tn', 60); map.set('dz', 60); map.set('ma', 60); map.set('ne', 60);
    map.set('td', 60); map.set('cm', 60); map.set('cf', 60); map.set('ga', 60);
    map.set('cg', 60); map.set('ao', 60); map.set('ng', 60); map.set('gh', 0);
    map.set('ci', 0); map.set('sn', 0); map.set('ml', 0); map.set('bf', 0);
    map.set('gm', 0); map.set('gn', 0); map.set('sl', 0); map.set('lr', 0);
    map.set('tg', 0); map.set('bj', 60); map.set('gq', 60); map.set('mr', 0);
    map.set('et', 180); map.set('ke', 180); map.set('tz', 180); map.set('ug', 180);
    map.set('so', 180); map.set('dj', 180); map.set('er', 180); map.set('mg', 180);
    map.set('cd', 120); map.set('zm', 120); map.set('zw', 120); map.set('mz', 120);
    map.set('za', 120); map.set('na', 120); map.set('bw', 120); map.set('mw', 120);
    map.set('rw', 120); map.set('bi', 120); map.set('mu', 240); map.set('sc', 240);
    // 美洲
    map.set('ar', -180); map.set('cl', -240); map.set('pe', -300); map.set('co', -300);
    map.set('ve', -240); map.set('ec', -300); map.set('bo', -240); map.set('py', -240);
    map.set('uy', -180); map.set('gy', -240); map.set('sr', -180); map.set('gf', -180);
    map.set('cu', -300); map.set('do', -240); map.set('ht', -300); map.set('jm', -300);
    map.set('pr', -240); map.set('tt', -240); map.set('pa', -300); map.set('cr', -360);
    map.set('ni', -360); map.set('hn', -360); map.set('sv', -360); map.set('gt', -360);
    map.set('bz', -360); map.set('gl', -180);
    // 大洋洲
    map.set('nz', 720); map.set('fj', 720); map.set('pg', 600); map.set('nc', 660);
    map.set('sb', 660); map.set('vu', 660); map.set('pf', -600);
    return map;
  }

  /** 多时区大国按经度分段，单位分钟。 */
  private static multiZoneMinutes(country: string, longitude: number): number {
    if (country === 'us') {
      if (longitude < -155) return -600;      // 夏威夷
      if (longitude < -130) return -540;      // 阿拉斯加
      if (longitude < -114) return -480;      // 太平洋
      if (longitude < -101) return -420;      // 山地
      if (longitude < -86) return -360;       // 中部
      return -300;                            // 东部
    }
    if (country === 'ca') {
      if (longitude < -120) return -480;
      if (longitude < -95) return -420;
      return -300;
    }
    if (country === 'mx') {
      return longitude < -105 ? -420 : -360;
    }
    if (country === 'br') {
      if (longitude < -60) return -300;
      if (longitude < -45) return -240;
      return -180;
    }
    if (country === 'ru') {
      if (longitude < 40) return 180;
      if (longitude < 52) return 240;
      if (longitude < 65) return 300;
      if (longitude < 85) return 420;
      if (longitude < 105) return 480;
      if (longitude < 125) return 540;
      if (longitude < 145) return 600;
      return 660;
    }
    if (country === 'au') {
      if (longitude < 129) return 480;
      if (longitude < 138) return 570;
      return 600;
    }
    if (country === 'id') {
      if (longitude < 115) return 420;
      if (longitude < 127) return 480;
      return 540;
    }
    if (country === 'kz') {
      return longitude < 65 ? 300 : 360;
    }
    return Number.MIN_SAFE_INTEGER;   // 不是多时区国家
  }

  private static isMultiZone(country: string): boolean {
    return country === 'us' || country === 'ca' || country === 'mx' || country === 'br' ||
      country === 'ru' || country === 'au' || country === 'id' || country === 'kz';
  }

  /**
   * 观测点的标准时区偏移（秒）。
   * @param countryCode 逆地理编码得到的 ISO 3166-1 alpha-2（大小写不敏感），未知传空串。
   * @param fallbackSeconds 表里查不到时的兜底值（通常是按经度取整）。
   */
  static offsetSeconds(countryCode: string, longitude: number, fallbackSeconds: number): number {
    const code: string = countryCode !== undefined && countryCode !== null ? countryCode.trim().toLowerCase() : '';
    if (code.length === 0) {
      return fallbackSeconds;
    }
    if (ZoneTable.isMultiZone(code)) {
      const minutes: number = ZoneTable.multiZoneMinutes(code, longitude);
      if (minutes !== Number.MIN_SAFE_INTEGER) {
        return minutes * 60;
      }
    }
    const minutes: number | undefined = ZoneTable.MINUTES.get(code);
    if (minutes === undefined) {
      return fallbackSeconds;
    }
    return minutes * 60;
  }
}
