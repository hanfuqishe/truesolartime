/**
 * 时间与文本格式化。语言参数取 'zh...' 开头为中文，其余为英文。
 */

import { SolarTimeMath } from './SolarTimeMath';

const WEEKDAYS_ZH: string[] = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
const WEEKDAYS_EN: string[] = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
const MONTHS_EN: string[] = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

function pad2(value: number): string {
  return value < 10 ? `0${value}` : `${value}`;
}

function isChinese(language: string): boolean {
  return language.startsWith('zh');
}

export class TimeFormat {
  /** 当天秒数 → "HH:mm"；传负数得占位 "--:--"。 */
  static clock(secondsOfDay: number): string {
    if (secondsOfDay < 0) {
      return '--:--';
    }
    const safe: number = Math.floor(((secondsOfDay % 86400) + 86400) % 86400);
    return `${pad2(Math.floor(safe / 3600))}:${pad2(Math.floor((safe % 3600) / 60))}`;
  }

  /** 当天秒数 → "HH:mm:ss"。 */
  static clockWithSeconds(secondsOfDay: number): string {
    const safe: number = Math.floor(((secondsOfDay % 86400) + 86400) % 86400);
    return `${TimeFormat.clock(safe)}:${pad2(Math.floor(safe % 60))}`;
  }

  /** 带正负号的时长，例如 "+14 分 22 秒"、"-2 分 05 秒"。 */
  static signedDuration(seconds: number, language: string): string {
    const sign: string = seconds < 0 ? '-' : '+';
    return sign + TimeFormat.minutesSeconds(seconds, language);
  }

  /** 不带符号的时长，例如 "14 分 22 秒"、"13 小时 0 分"。 */
  static minutesSeconds(seconds: number, language: string): string {
    const total: number = Math.floor(Math.abs(seconds));
    const hours: number = Math.floor(total / 3600);
    const minutes: number = Math.floor((total % 3600) / 60);
    const rest: number = total % 60;
    if (isChinese(language)) {
      if (hours > 0) {
        return `${hours} 小时 ${minutes} 分`;
      }
      if (minutes > 0) {
        return `${minutes} 分 ${pad2(rest)} 秒`;
      }
      return `${rest} 秒`;
    }
    if (hours > 0) {
      return `${hours} h ${minutes} min`;
    }
    if (minutes > 0) {
      return `${minutes} min ${pad2(rest)} s`;
    }
    return `${rest} s`;
  }

  /** 例如 "13 小时 42 分"；传负数得 "--"。 */
  static duration(seconds: number, language: string): string {
    if (seconds < 0) {
      return '--';
    }
    const hours: number = Math.floor(seconds / 3600);
    const minutes: number = Math.floor((seconds % 3600) / 60);
    return isChinese(language) ? `${hours} 小时 ${pad2(minutes)} 分` : `${hours} h ${pad2(minutes)} min`;
  }

  /** 倒计时，例如 "01:23:45"。 */
  static countdown(seconds: number): string {
    const safe: number = Math.max(0, Math.floor(seconds));
    return `${pad2(Math.floor(safe / 3600))}:${pad2(Math.floor((safe % 3600) / 60))}:${pad2(safe % 60)}`;
  }

  /** 北京时间日期 + 星期，例如 "11 月 2 日 · 星期六" / "Nov 2 · Saturday"。 */
  static dateWithWeekday(epochMillis: number, language: string): string {
    const date: Date = new Date(epochMillis + SolarTimeMath.BEIJING_OFFSET_MILLIS);
    const month: number = date.getUTCMonth() + 1;
    const day: number = date.getUTCDate();
    const weekday: number = date.getUTCDay();
    if (isChinese(language)) {
      return `${month} 月 ${day} 日 · ${WEEKDAYS_ZH[(weekday + 6) % 7]}`;
    }
    return `${MONTHS_EN[month - 1]} ${day} · ${WEEKDAYS_EN[weekday]}`;
  }

  /** 紧凑日期 + 星期，例如 "11月13日 周五" / "Nov 13 Fri"，给卡片那行窄字用。 */
  static dateCompact(epochMillis: number, language: string): string {
    const date: Date = new Date(epochMillis + SolarTimeMath.BEIJING_OFFSET_MILLIS);
    const month: number = date.getUTCMonth() + 1;
    const day: number = date.getUTCDate();
    const weekday: number = date.getUTCDay();
    if (isChinese(language)) {
      const name: string = WEEKDAYS_ZH[(weekday + 6) % 7];
      return `${month}月${day}日 周${name.slice(2)}`;
    }
    return `${MONTHS_EN[month - 1]} ${day} ${WEEKDAYS_EN[weekday].slice(0, 3)}`;
  }

  /** 例如 "39.9042°N  116.4074°E"。 */  static coordinates(latitude: number, longitude: number): string {
    const lat: string = `${Math.abs(latitude).toFixed(4)}°${latitude >= 0 ? 'N' : 'S'}`;
    const lon: string = `${Math.abs(longitude).toFixed(4)}°${longitude >= 0 ? 'E' : 'W'}`;
    return `${lat}  ${lon}`;
  }

  /** 「还有 3 分 05 秒」式的剩余时间提示（英文 "in 3 min 05 s"）。 */
  static remaining(seconds: number, language: string): string {
    const text: string = TimeFormat.minutesSeconds(seconds, language);
    return isChinese(language) ? `还有 ${text}` : `in ${text}`;
  }
}
