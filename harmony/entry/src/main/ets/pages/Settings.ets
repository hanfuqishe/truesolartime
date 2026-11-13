/**
 * 设置页：与 Android 的 SettingsSheet 对应 —— 当前位置、手动坐标、常用城市、提醒开关、关于。
 * 主界面通过「设置」进入，返回后由 Index.onPageShow 重新读取偏好。
 */

import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { router } from '@kit.ArkUI';
import { CityIndex, NearbyCity } from '../core/CityIndex';
import { Place, PlaceSource } from '../core/Place';
import { TakeBand, TakeTimeSchedule } from '../core/TakeTime';
import { TimeFormat } from '../core/TimeFormat';
import { SolarTimeMath } from '../core/SolarTimeMath';
import { AppStore } from '../services/Store';
import { DistrictService } from '../services/DistrictService';
import { KeyTimeService } from '../services/KeyTimeService';
import { LocationService, GeoPoint } from '../services/LocationService';
import { ReminderService } from '../services/ReminderService';

const HERO_COLOR: string = '#F5D68A';
const TEXT_COLOR: string = '#E8EDF7';
const SUBTLE_COLOR: string = '#9AA7BF';
const CARD_COLOR: string = '#16203A';
const PAGE_COLOR: string = '#0B1220';
const CHIP_COLOR: string = '#24304F';

@Entry
@Component
struct Settings {
  @State place: Place = Place.DEFAULT;
  @State placeName: string = '';
  @State presetLabels: string[] = [];
  @State shichenReminders: boolean = false;
  @State keyTimeChime: boolean = false;
  @State locating: boolean = false;
  @State manualLatitude: string = '';
  @State manualLongitude: string = '';
  @State error: string = '';
  @State hint: string = '';
  private context: common.UIAbilityContext | null = null;

  aboutToAppear(): void {
    this.context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    AppStore.init(this.context);
    this.reload();
  }

  private reload(): void {
    this.place = AppStore.place();
    this.placeName = this.labelOf(this.place);
    this.shichenReminders = AppStore.shichenReminders();
    this.keyTimeChime = AppStore.keyTimeChime();
    this.manualLatitude = this.place.latitude.toFixed(4);
    this.manualLongitude = this.place.longitude.toFixed(4);
    const labels: string[] = [];
    for (const preset of Place.PRESETS) {
      labels.push(this.labelOf(preset));
    }
    this.presetLabels = labels;
  }

  private labelOf(place: Place): string {
    const district: string = place.sameLocation(AppStore.place()) ? DistrictService.cachedShortName() : '';
    if (district.length > 0) {
      return district;
    }
    const city: NearbyCity | null = CityIndex.nearest(place.latitude, place.longitude, DistrictService.language());
    if (city !== null) {
      return city.name;
    }
    return TimeFormat.coordinates(place.latitude, place.longitude);
  }

  private applyPlace(place: Place): void {
    AppStore.setPlace(place);
    this.place = place;
    this.placeName = this.labelOf(place);
    this.manualLatitude = place.latitude.toFixed(4);
    this.manualLongitude = place.longitude.toFixed(4);
    this.error = '';
    this.hint = '已保存，返回首页生效';
    this.reschedule();
    DistrictService.refreshIfNeeded(place).catch((error: BusinessError) => {
      console.warn(`district refresh failed: ${error.code} ${error.message}`);
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
      const point: GeoPoint | null = await LocationService.current();
      if (point === null) {
        this.hint = '暂时取不到位置，请稍后再试';
        return;
      }
      this.applyPlace(new Place(point.latitude, point.longitude, PlaceSource.GPS, '', ''));
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
    .backgroundColor(CARD_COLOR)
    .borderRadius(18)
    .padding(16)
  }

  @Builder
  sectionTitle(title: string) {
    Text(title)
      .fontSize(13)
      .fontColor(HERO_COLOR)
      .width('100%')
  }

  @Builder
  switchRow(title: string, desc: string, isOn: boolean, onToggle: (value: boolean) => void) {
    Row() {
      Column() {
        Text(title)
          .fontSize(14)
          .fontColor(TEXT_COLOR)
        Text(desc)
          .fontSize(10)
          .fontColor(SUBTLE_COLOR)
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
          .fontColor(TEXT_COLOR)
          .width(40)
          .onClick(() => {
            router.back();
          })
        Text('设置')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_COLOR)
          .layoutWeight(1)
        Text(this.placeName)
          .fontSize(12)
          .fontColor(HERO_COLOR)
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
              .fontColor(TEXT_COLOR)
              .margin({ top: 8 })
              .width('100%')
            Button(this.locating ? '定位中…' : '实时跟随GPS')
              .fontSize(13)
              .backgroundColor(CHIP_COLOR)
              .fontColor(TEXT_COLOR)
              .width('100%')
              .height(38)
              .margin({ top: 12 })
              .onClick(() => {
                this.locate();
              })
            if (this.hint.length > 0) {
              Text(this.hint)
                .fontSize(10)
                .fontColor(SUBTLE_COLOR)
                .margin({ top: 8 })
                .width('100%')
            }
          }
          .cardStyle()

          // 手动坐标
          Column() {
            this.sectionTitle('手动坐标')
            Row() {
              TextInput({ text: this.manualLatitude, placeholder: '纬度' })
                .type(InputType.NUMBER_DECIMAL)
                .backgroundColor('#0F1830')
                .fontColor(TEXT_COLOR)
                .layoutWeight(1)
                .onChange((value: string) => {
                  this.manualLatitude = value;
                  this.error = '';
                })
              TextInput({ text: this.manualLongitude, placeholder: '经度' })
                .type(InputType.NUMBER_DECIMAL)
                .backgroundColor('#0F1830')
                .fontColor(TEXT_COLOR)
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
              .backgroundColor(HERO_COLOR)
              .fontColor(PAGE_COLOR)
              .width('100%')
              .height(38)
              .margin({ top: 10 })
              .onClick(() => {
                this.applyManual();
              })
          }
          .cardStyle()

          // 常用城市
          Column() {
            this.sectionTitle('常用城市')
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(Place.PRESETS, (preset: Place, index: number) => {
                Text(index < this.presetLabels.length
                  ? this.presetLabels[index]
                  : TimeFormat.coordinates(preset.latitude, preset.longitude))
                  .fontSize(12)
                  .fontColor(this.place.sameLocation(preset) ? PAGE_COLOR : TEXT_COLOR)
                  .backgroundColor(this.place.sameLocation(preset) ? HERO_COLOR : CHIP_COLOR)
                  .borderRadius(14)
                  .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                  .margin({ right: 8, top: 8 })
                  .onClick(() => {
                    this.applyPlace(preset);
                  })
              }, (preset: Place) => `${preset.latitude}-${preset.longitude}`)
            }
            .width('100%')
            .margin({ top: 4 })
          }
          .cardStyle()

          // 提醒
          Column() {
            this.sectionTitle('提醒')
            this.switchRow('时辰交接提醒', '进入下一个时辰时响一声（250 ms）', this.shichenReminders,
              (value: boolean) => {
                this.shichenReminders = value;
                AppStore.setShichenReminders(value);
                this.reschedule();
              })
            this.switchRow('关键时间报时', '每进入一段关键时间响一次（500 ms）', this.keyTimeChime,
              (value: boolean) => {
                this.keyTimeChime = value;
                AppStore.setKeyTimeChime(value);
                this.reschedule();
              })
            Text('提醒由系统代理发出：应用不在前台也会到点通知；打开应用时只响铃、不留通知。')
              .fontSize(10)
              .fontColor('#5A6885')
              .margin({ top: 12 })
              .width('100%')
          }
          .cardStyle()

          // 关于
          Column() {
            this.sectionTitle('关于')
            Text('真太阳时 v1.0.0')
              .fontSize(12)
              .fontColor(TEXT_COLOR)
              .margin({ top: 8 })
              .width('100%')
            Text('左侧是当地标准时间（跟随系统 12/24 小时制），右侧是以太阳为准的真太阳时：' +
              '经度每差 1° 相当于 4 分钟，再叠加均时差。')
              .fontSize(10)
              .fontColor(SUBTLE_COLOR)
              .margin({ top: 6 })
              .width('100%')
            Text('数据来源：天气 Open-Meteo（CC BY 4.0）；区划名：系统逆地理编码 / OSM Nominatim。')
              .fontSize(10)
              .fontColor(SUBTLE_COLOR)
              .margin({ top: 6 })
              .width('100%')
            Text(`北京时区偏移 ${SolarTimeMath.BEIJING_OFFSET_MILLIS / 3600000} 小时`)
              .fontSize(10)
              .fontColor('#5A6885')
              .margin({ top: 6 })
              .width('100%')
          }
          .cardStyle()
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
    .backgroundColor(PAGE_COLOR)
  }
}
