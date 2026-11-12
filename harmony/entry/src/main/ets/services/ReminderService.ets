/**
 * 报时用的代理提醒。
 *
 * HarmonyOS 不允许第三方应用自建精确闹钟，但「代理提醒」（reminderAgentManager）
 * 由系统代发：应用不必常驻，到点由系统弹出通知并响铃。因此
 *   - 时辰交接：提前排好未来 12 个交接时刻；
 *   - 关键时间：提前排好未来 2 天里每段关键时间的起点。
 * 每次重排都会先取消本应用此前发布的同类提醒（按 title 前缀识别）。
 *
 * 与 Android 端的差异：Android 是「只响铃、不发通知」，这里由系统代理，
 * 必然在通知栏留下一条到点通知。
 */

import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { notificationManager } from '@kit.NotificationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ChimeLogic } from '../core/Chime';
import { Place } from '../core/Place';
import { TakeBand } from '../core/TakeTime';
import { TimeFormat } from '../core/TimeFormat';
import { SolarTimeMath } from '../core/SolarTimeMath';
import { AppStore } from './Store';

export const SHICHEN_REMINDER_TITLE: string = 'TrueSolarTime.Shichen';
export const KEY_TIME_REMINDER_TITLE: string = 'TrueSolarTime.KeyTime';

/** 未来 12 个时辰交接 = 24 小时。 */
const SHICHEN_COUNT: number = 12;
/** 关键时间往后排 2 天。 */
const KEY_TIME_DAYS: number = 2;
const NOTIFICATION_ID_SHICHEN: number = 7301;
const NOTIFICATION_ID_KEY_TIME: number = 7401;
const BUNDLE_NAME: string = 'com.realsuntime.solartime';
const ABILITY_NAME: string = 'EntryAbility';

class ReminderTexts {
  shichenTitle: string;
  keyTimeTitle: string;
  takeNow: string;

  constructor(shichenTitle: string, keyTimeTitle: string, takeNow: string) {
    this.shichenTitle = shichenTitle;
    this.keyTimeTitle = keyTimeTitle;
    this.takeNow = takeNow;
  }
}

function textsFor(language: string): ReminderTexts {
  if (language.startsWith('zh')) {
    return new ReminderTexts('时辰交接', '关键时间', '现在可以服用');
  }
  return new ReminderTexts('Shichen boundary', 'Key time', 'Take now');
}

export class ReminderService {
  /** 取消本应用此前发布的全部提醒。 */
  static async cancelAll(): Promise<void> {
    const ids: number[] = AppStore.reminderIds();
    for (const id of ids) {
      try {
        await reminderAgentManager.cancelReminder(id);
      } catch (error) {
        // 已被系统回收的提醒取消会失败，忽略即可。
      }
    }
    AppStore.setReminderIds([]);
  }

  /** 按当前设置与观测点重排所有提醒。 */
  static async reschedule(
    place: Place,
    shichenEnabled: boolean,
    keyTimeEnabled: boolean,
    bands: TakeBand[],
    language: string
  ): Promise<void> {
    await ReminderService.cancelAll();
    if (!shichenEnabled && !keyTimeEnabled) {
      return;
    }
    const texts: ReminderTexts = textsFor(language);
    const now: number = Date.now();
    const published: number[] = [];
    try {
      if (shichenEnabled) {
        const triggers: number[] = ChimeLogic.upcomingShichenTriggers(now, place.longitude, SHICHEN_COUNT);
        let index: number = 0;
        for (const trigger of triggers) {
          const shichenName: string = ReminderService.shichenLabel(trigger, place, language);
          const id: number = await ReminderService.publishCalendar(
            trigger,
            SHICHEN_REMINDER_TITLE,
            `${texts.shichenTitle}: ${shichenName}`,
            NOTIFICATION_ID_SHICHEN + index
          );
          published.push(id);
          index++;
        }
      }
      if (keyTimeEnabled && bands.length > 0) {
        const triggers: number[] = ChimeLogic.upcomingKeyTimeTriggers(now, place.longitude, bands, KEY_TIME_DAYS);
        let index: number = 0;
        for (const trigger of triggers) {
          const id: number = await ReminderService.publishCalendar(
            trigger,
            KEY_TIME_REMINDER_TITLE,
            texts.takeNow,
            NOTIFICATION_ID_KEY_TIME + index
          );
          published.push(id);
          index++;
        }
      }
    } catch (error) {
      const failure: BusinessError = error as BusinessError;
      console.warn(`reschedule failed: ${failure.code} ${failure.message}`);
    } finally {
      AppStore.setReminderIds(published);
    }
  }

  private static shichenLabel(trigger: number, place: Place, language: string): string {
    const snapshot = SolarTimeMath.trueSolarSecondsOfDay(trigger, place.longitude);
    const index: number = Math.floor((((snapshot + 3600) % 86400) + 86400) % 86400 / 7200) % 12;
    const names: string[] = ['子', '丑', '寅', '卯', '辰', '巳', '午', '未', '申', '酉', '戌', '亥'];
    const pinyin: string[] = ['Zi', 'Chou', 'Yin', 'Mao', 'Chen', 'Si', 'Wu', 'Wei', 'Shen', 'You', 'Xu', 'Hai'];
    if (language.startsWith('zh')) {
      return `${names[index]}时 ${TimeFormat.clock(snapshot)}`;
    }
    return `${pinyin[index]} ${TimeFormat.clock(snapshot)}`;
  }

  private static async publishCalendar(
    triggerMillis: number,
    title: string,
    content: string,
    notificationId: number
  ): Promise<number> {
    const date: Date = new Date(triggerMillis);
    const request: reminderAgentManager.ReminderRequestCalendar = {
      reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR,
      dateTime: {
        year: date.getFullYear(),
        month: date.getMonth() + 1,
        day: date.getDate(),
        hour: date.getHours(),
        minute: date.getMinutes(),
        second: date.getSeconds()
      },
      title: title,
      content: content,
      expiredContent: content,
      notificationId: notificationId,
      // 代理提醒里的 wantAgent 是「点通知后打开什么」的简单描述，不是 wantAgent 模块的对象。
      wantAgent: {
        pkgName: BUNDLE_NAME,
        abilityName: ABILITY_NAME
      },
      slotType: notificationManager.SlotType.SERVICE_INFORMATION,
      ringDuration: 2,
      snoozeTimes: 0
    };
    return reminderAgentManager.publishReminder(request);
  }
}
