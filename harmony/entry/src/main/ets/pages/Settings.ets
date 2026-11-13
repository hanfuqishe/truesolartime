/**
 * 设置页：与 Android 的 SettingsSheet 对应 —— 当前位置、手动坐标、常用城市、提醒开关、关于。
 * 主界面通过「设置」进入，返回后由 Index.onPageShow 重新读取偏好。
 */

import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { router } from '@kit.ArkUI';
import { notificationManager } from '@kit.NotificationKit';
import { CityIndex, NearbyCity } from '../core/CityIndex';
import { Place, PlaceSource } from '../core/Place';
import { TakeBand, TakeTimeSchedule } from '../core/TakeTime';
import { TimeFormat } from '../core/TimeFormat';
import { SolarTimeMath } from '../core/SolarTimeMath';
import { AppStore } from '../services/Store';
import { AppInfo } from '../services/AppInfo';
import { CardService } from '../services/CardService';
import { DistrictService } from '../services/DistrictService';
import { KeepAwake } from '../services/KeepAwake';
import { KeyTimeService } from '../services/KeyTimeService';
import { LocationService, LocationAttempt } from '../services/LocationService';
import { ReminderService } from '../services/ReminderService';
import { WeatherService } from '../services/WeatherService';
import { AppPalette, paletteFor } from '../common/Theme';

@Entry
@Component
struct Settings {
  @State place: Place = Place.DEFAULT;
  /** 与首页同一套白天／夜间主题。 */
  @State palette: AppPalette = paletteFor(true);
  @State placeName: string = '';
  @State presetLabels: string[] = [];
  @State shichenReminders: boolean = false;
  @State keyTimeChime: boolean = false;
  @State keepScreenOn: boolean = true;
  @State locating: boolean = false;
  @State manualLatitude: string = '';
  @State manualLongitude: string = '';
  @State error: string = '';
  @State hint: string = '';
  /** 通知权限相关的提示，显示在「提醒」卡片里。 */
  @State reminderHint: string = '';
  private context: common.UIAbilityContext | null = null;

  aboutToAppear(): void {
    this.context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    AppStore.init(this.context);
    this.reload();
    // 开关已经打开但用户从没同意过通知（比如旧版本升级上来）：进设置页时补一次请求。
    if (this.shichenReminders || this.keyTimeChime) {
      this.ensureNotifications();
    }
  }

  private reload(): void {
    this.place = AppStore.place();
    this.placeName = this.labelOf(this.place);
    this.shichenReminders = AppStore.shichenReminders();
    this.keyTimeChime = AppStore.keyTimeChime();
    this.keepScreenOn = AppStore.keepScreenOn();
    this.manualLatitude = this.place.latitude.toFixed(4);
    this.manualLongitude = this.place.longitude.toFixed(4);
    const labels: string[] = [];
    for (const preset of Place.PRESETS) {
      labels.push(this.cityLabel(preset));
    }
    this.presetLabels = labels;
    const altitude: number = SolarTimeMath.solarAltitudeDegrees(Date.now(), this.place.latitude, this.place.longitude);
    this.palette = paletteFor(altitude > -0.833);
  }

  private labelOf(place: Place): string {
    const district: string = place.sameLocation(AppStore.place()) ? DistrictService.cachedShortName() : '';
    if (district.length > 0) {
      return district;
    }
    return this.cityLabel(place);
  }

  /** 常用城市按钮上的名字：固定用城市名，不跟随逆地理结果（否则「上海」会变成「黄浦区」）。 */
  private cityLabel(place: Place): string {
    if (place.label.length > 0) {
      return place.label;
    }
    const city: NearbyCity | null = CityIndex.nearest(place.latitude, place.longitude, DistrictService.language());
    if (city !== null) {
      return city.name;
    }
    return TimeFormat.coordinates(place.latitude, place.longitude);
  }

  private applyPlace(place: Place, leave: boolean = false): void {
    AppStore.setPlace(place);
    this.place = place;
    this.placeName = this.labelOf(place);
    this.manualLatitude = place.latitude.toFixed(4);
    this.manualLongitude = place.longitude.toFixed(4);
    this.error = '';
    this.hint = '已保存，返回首页生效';
    this.reschedule();
    // 换了地点，缓存里的天气就属于旧坐标了（显示层按距离判定为无效，立刻只剩占位符）：
    // 不等 30 分钟窗口，马上取一次新地点的天气，并顺手更新区划名。
    WeatherService.refreshIfNeeded(place, true).then((updated: boolean) => {
      if (updated) {
        CardService.refresh().catch((error: BusinessError) => {
          console.warn(`card refresh failed: ${error.code} ${error.message}`);
        });
      }
    }).catch((error: BusinessError) => {
      console.warn(`weather refresh failed: ${error.code} ${error.message}`);
    });
    DistrictService.refreshIfNeeded(place).catch((error: BusinessError) => {
      console.warn(`district refresh failed: ${error.code} ${error.message}`);
    });
    // 常用城市与「实时跟随GPS」都是一步到位的选择，选完直接回首页看结果。
    if (leave) {
      router.back();
    }
  }

  /** 代理提醒以通知的形式出现：打开开关时顺带要一次通知权限，否则到点时只会静默。 */
  private ensureNotifications(): void {
    const context: common.UIAbilityContext | null = this.context;
    if (context === null) {
      return;
    }
    notificationManager.isNotificationEnabled().then((enabled: boolean) => {
      if (enabled) {
        this.reminderHint = '';
        return;
      }
      notificationManager.requestEnableNotification(context).then(() => {
        this.reminderHint = '';
      }).catch(() => {
        this.reminderHint = '未允许通知：到点仍会响铃，但通知栏里看不到提醒。可到「设置 → 通知」里为本应用打开。';
      });
    }).catch(() => {
      // 查询失败就跳过，发布提醒时系统还会再问一次。
    });
  }

  private reschedule(): void {
    const place: Place = AppStore.place();
    const schedule: TakeTimeSchedule | null = KeyTimeService.schedule();
    const bands: TakeBand[] = schedule === null ? [] : schedule.bands;
    ReminderService.reschedule(
      place,
      AppStore.shichenReminders(),
      AppStore.keyTimeChime(),
      bands,
      DistrictService.language()
    ).catch((error: BusinessError) => {
      console.warn(`reschedule failed: ${error.code} ${error.message}`);
    });
  }

  private async locate(): Promise<void> {
    const context: common.UIAbilityContext | null = this.context;
    if (context === null || this.locating) {
      return;
    }
    this.locating = true;
    try {
      const granted: boolean = await LocationService.ensurePermission(context);
      AppStore.setLocationAsked(true);
      if (!granted) {
        this.hint = '未授予定位权限，可手动输入坐标';
        return;
      }
      const attempt: LocationAttempt = await LocationService.attempt();
      if (attempt.point === null) {
        // 最常见的失败不是超时，而是系统「位置」总开关没开（下拉控制中心里那个磁贴），
        // 这种提示必须能直接告诉用户去哪儿打开，否则只能干等到超时后重试。
        this.hint = LocationService.isSwitchOff(attempt.code)
          ? '系统「位置」开关未打开：从屏幕顶部下拉控制中心打开「位置」后重试，或手动输入坐标'
          : '暂时取不到位置，请稍后再试，也可手动输入坐标';
        return;
      }
      this.applyPlace(new Place(attempt.point.latitude, attempt.point.longitude, PlaceSource.GPS, '', ''), true);
    } finally {
      this.locating = false;
    }
  }

  private applyManual(): void {
    const latitude: number = Number.parseFloat(this.manualLatitude);
    const longitude: number = Number.parseFloat(this.manualLongitude);
    if (!Place.isValidLatitude(latitude)) {
      this.error = '纬度需在 -90 到 90 之间';
      return;
    }
    if (!Place.isValidLongitude(longitude)) {
      this.error = '经度需在 -180 到 180 之间';
      return;
    }
    this.applyPlace(new Place(latitude, longitude, PlaceSource.MANUAL, '', ''));
  }

  @Styles
  cardStyle() {
    .width('100%')
    .borderRadius(18)
    .padding(16)
  }

  @Builder
  sectionTitle(title: string) {
    Text(title)
      .fontSize(13)
      .fontColor(this.palette.accent)
      .width('100%')
  }

  @Builder
  switchRow(title: string, desc: string, isOn: boolean, onToggle: (value: boolean) => void) {
    Row() {
      Column() {
        Text(title)
          .fontSize(14)
          .fontColor(this.palette.text)
        Text(desc)
          .fontSize(10)
          .fontColor(this.palette.subtle)
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: isOn })
        .onChange((value: boolean) => {
          onToggle(value);
        })
    }
    .width('100%')
    .margin({ top: 12 })
  }

  build() {
    Column() {
      Row() {
        Text('‹')
          .fontSize(26)
          .fontColor(this.palette.text)
          .width(40)
          .onClick(() => {
            router.back();
          })
        Text('设置')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette.text)
          .layoutWeight(1)
        Text(this.placeName)
          .fontSize(12)
          .fontColor(this.palette.accent)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })

      Scroll() {
        Column({ space: 12 }) {
          // 当前位置
          Column() {
            this.sectionTitle('当前位置')
            Text(`${this.placeName}　${TimeFormat.coordinates(this.place.latitude, this.place.longitude)}`)
              .fontSize(12)
              .fontColor(this.palette.text)
              .margin({ top: 8 })
              .width('100%')
            Button(this.locating ? '定位中…' : '实时跟随GPS')
              .fontSize(13)
              .backgroundColor(this.palette.chip)
              .fontColor(this.palette.text)
              .width('100%')
              .height(38)
              .margin({ top: 12 })
              .onClick(() => {
                this.locate();
              })
            if (this.hint.length > 0) {
              Text(this.hint)
                .fontSize(10)
                .fontColor(this.palette.subtle)
                .margin({ top: 8 })
                .width('100%')
            }
          }
          .cardStyle()
    .backgroundColor(this.palette.card)

          // 手动坐标
          Column() {
            this.sectionTitle('手动坐标')
            Row() {
              TextInput({ text: this.manualLatitude, placeholder: '纬度' })
                .type(InputType.NUMBER_DECIMAL)
                .backgroundColor(this.palette.chip)
                .fontColor(this.palette.text)
                .layoutWeight(1)
                .onChange((value: string) => {
                  this.manualLatitude = value;
                  this.error = '';
                })
              TextInput({ text: this.manualLongitude, placeholder: '经度' })
                .type(InputType.NUMBER_DECIMAL)
                .backgroundColor(this.palette.chip)
                .fontColor(this.palette.text)
                .layoutWeight(1)
                .margin({ left: 8 })
                .onChange((value: string) => {
                  this.manualLongitude = value;
                  this.error = '';
                })
            }
            .width('100%')
            .margin({ top: 10 })
            if (this.error.length > 0) {
              Text(this.error)
                .fontSize(10)
                .fontColor('#D9534F')
                .margin({ top: 6 })
                .width('100%')
            }
            Button('应用')
              .fontSize(13)
              .backgroundColor(this.palette.accent)
              .fontColor(this.palette.onAccent)
              .width('100%')
              .height(38)
              .margin({ top: 10 })
              .onClick(() => {
                this.applyManual();
              })
          }
          .cardStyle()
    .backgroundColor(this.palette.card)

          // 常用城市：只是快捷定位入口，不按当前坐标高亮（当前坐标未必落在这些点上）
          Column() {
            this.sectionTitle('常用城市')
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(Place.PRESETS, (preset: Place, index: number) => {
                Text(index < this.presetLabels.length
                  ? this.presetLabels[index]
                  : TimeFormat.coordinates(preset.latitude, preset.longitude))
                  .fontSize(12)
                  .fontColor(this.palette.text)
                  .backgroundColor(this.palette.chip)
                  .borderRadius(14)
                  .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                  .margin({ right: 8, top: 8 })
                  .onClick(() => {
                    this.applyPlace(preset, true);
                  })
              }, (preset: Place) => `${preset.latitude}-${preset.longitude}`)
            }
            .width('100%')
            .margin({ top: 4 })
          }
          .cardStyle()
    .backgroundColor(this.palette.card)

          // 提醒
          Column() {
            this.sectionTitle('提醒')
            this.switchRow('时辰交接提醒', '进入下一个时辰时响一声（250 ms）', this.shichenReminders,
              (value: boolean) => {
                this.shichenReminders = value;
                AppStore.setShichenReminders(value);
                if (value) {
                  this.ensureNotifications();
                }
                this.reschedule();
              })
            this.switchRow('关键时间报时', '每进入一段关键时间响一次（500 ms）', this.keyTimeChime,
              (value: boolean) => {
                this.keyTimeChime = value;
                AppStore.setKeyTimeChime(value);
                if (value) {
                  this.ensureNotifications();
                }
                this.reschedule();
              })
            Text('提醒由系统代理发出：应用不在前台也会到点通知；打开应用时只响铃、不留通知。')
              .fontSize(10)
              .fontColor('#5A6885')
              .margin({ top: 12 })
              .width('100%')
            if (this.reminderHint.length > 0) {
              Text(this.reminderHint)
                .fontSize(10)
                .fontColor('#D9534F')
                .margin({ top: 8 })
                .width('100%')
            }
          }
          .cardStyle()
    .backgroundColor(this.palette.card)

          // 屏幕
          Column() {
            this.sectionTitle('屏幕')
            this.switchRow('屏幕常亮', '应用打开期间不自动熄屏（会更耗电）', this.keepScreenOn,
              (value: boolean) => {
                this.keepScreenOn = value;
                AppStore.setKeepScreenOn(value);
                KeepAwake.apply(this.context);
              })
          }
          .cardStyle()
    .backgroundColor(this.palette.card)

          // 关于
          Column() {
            this.sectionTitle('关于')
            Text(`真太阳时 v${AppInfo.versionName()}`)
              .fontSize(12)
              .fontColor(this.palette.text)
              .margin({ top: 8 })
              .width('100%')
            Text('左侧是当地标准时间（跟随系统 12/24 小时制），右侧是以太阳为准的真太阳时：' +
              '经度每差 1° 相当于 4 分钟，再叠加均时差。')
              .fontSize(10)
              .fontColor(this.palette.subtle)
              .margin({ top: 6 })
              .width('100%')
            Text('数据来源：天气 Open-Meteo（CC BY 4.0）；区划名：系统逆地理编码 / OSM Nominatim。')
              .fontSize(10)
              .fontColor(this.palette.subtle)
              .margin({ top: 6 })
              .width('100%')
            Text(`北京时区偏移 ${SolarTimeMath.BEIJING_OFFSET_MILLIS / 3600000} 小时`)
              .fontSize(10)
              .fontColor('#5A6885')
              .margin({ top: 6 })
              .width('100%')
          }
          .cardStyle()
    .backgroundColor(this.palette.card)
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 24 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.palette.page)
  }
}
