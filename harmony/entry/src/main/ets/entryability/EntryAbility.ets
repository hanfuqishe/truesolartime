import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { TakeBand, TakeTimeSchedule } from '../core/TakeTime';
import { AppStore } from '../services/Store';
import { CardService } from '../services/CardService';
import { DistrictService } from '../services/DistrictService';
import { KeyTimeService } from '../services/KeyTimeService';
import { ReminderService } from '../services/ReminderService';

/** 前台每分钟刷一次卡片并重排提醒；秒级显示由页面自己的定时器负责。 */
const REFRESH_INTERVAL_MILLIS: number = 60 * 1000;

export default class EntryAbility extends UIAbility {
  private refreshTimer: number = -1;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    AppStore.init(this.context);
    AppStorage.setOrCreate<string>('language', DistrictService.language());
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (error: BusinessError) => {
      if (error.code) {
        console.error(`loadContent failed: ${error.code} ${error.message}`);
      }
    });
  }

  onForeground(): void {
    this.refreshNow();
    if (this.refreshTimer < 0) {
      this.refreshTimer = setInterval(() => {
        this.refreshNow();
      }, REFRESH_INTERVAL_MILLIS);
    }
  }

  onBackground(): void {
    if (this.refreshTimer >= 0) {
      clearInterval(this.refreshTimer);
      this.refreshTimer = -1;
    }
    // 进入后台前把提醒排好：代理提醒由系统代发，不需要应用常驻。
    this.reschedule();
  }

  onDestroy(): void {
    if (this.refreshTimer >= 0) {
      clearInterval(this.refreshTimer);
      this.refreshTimer = -1;
    }
  }

  private refreshNow(): void {
    CardService.refresh().catch((error: BusinessError) => {
      console.warn(`card refresh failed: ${error.code} ${error.message}`);
    });
    this.reschedule();
  }

  private reschedule(): void {
    const place = AppStore.place();
    const schedule: TakeTimeSchedule | null = KeyTimeService.schedule();
    const bands: TakeBand[] = schedule === null ? [] : schedule.bands;
    ReminderService.reschedule(
      place,
      AppStore.shichenReminders(),
      AppStore.keyTimeChime(),
      bands,
      DistrictService.language()
    ).catch((error: BusinessError) => {
      console.warn(`reminder reschedule failed: ${error.code} ${error.message}`);
    });
  }
}
