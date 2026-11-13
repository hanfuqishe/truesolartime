/**
 * 真太阳时桌面卡片，版面严格对齐 Android 版小组件（widget_solar_time_compact.xml）：
 *
 *   左栏：标准时间 + 地名 / 大号标准时间 / 日期与今日温度区间
 *   右栏：真太阳时 + 时辰 / 大号真太阳时（带秒）/ 经纬度
 *   中间一条 1vp 竖分隔线；下面 0–24 时时间轴（色条为关键时间，柔化圆点为当前时刻）
 *   底部六格逐时预报（时刻、天气图标、天气名）
 *
 * 点击分区与 Android 一致：左栏→时钟、日期→日历、逐时行→天气、右栏与空白→本应用。
 * 目标应用用 `postCardAction` 的 router 直接拉起（卡片里拿不到 FormExtensionContext.startAbility），
 * 因此写的是华为系统应用的包名 + `<bundle>.MainAbility`；设备上没有对应应用时该区域点击无反应。
 *
 * 尺寸按鸿蒙 2*4 卡片实际可用的约 226×110vp 收：Android 的 4×2 有约 146dp 高，
 * 这里更矮，所以内边距、字号、图标都比 Android 再紧一档，保证六格预报不被裁掉。
 *
 * 与 Android 的两处差异来自卡片能力本身（实测 HarmonyOS 6.0.0 / API 20）：
 *   - 卡片里的 TextClock 只走系统本地时间，`format()` 与 `timeZoneOffset` 都被忽略，
 *     且卡片禁用定时器，所以真太阳时只能用快照文本（HH:mm:ss），随卡片刷新更新；
 *   - 因此左栏标准时间交给 TextClock 自走（分钟精度、跟随系统 12/24 小时制）。
 */

import { weatherIcon } from '../../common/WeatherIcon';

function segmentLength(item: string): number {
  const parts: string[] = item.split(',');
  const length: number = Number.parseFloat(parts[0]);
  return isNaN(length) || length <= 0 ? 1 : length;
}

function isBand(item: string): boolean {
  const parts: string[] = item.split(',');
  return parts.length > 1 && parts[1] !== '-1';
}

const GOLD: string = '#FFC65C';
/** 白天橙底上的真太阳时：淡金，比纯白暖一档，又不至于和底色糊在一起。 */
const DAY_ACCENT: string = '#FFE6B4';
const WHITE: string = '#FFFFFF';
const TEXT_DIM: string = '#B3FFFFFF';
const TEXT_LABEL: string = '#CCFFFFFF';
const DIVIDER: string = '#33FFFFFF';
const AXIS_TRACK: string = '#40FFFFFF';

let storage: LocalStorage = new LocalStorage();

@Entry(storage)
@Component
struct SolarTimeCard {
  @LocalStorageProp('city') city: string = '';
  @LocalStorageProp('shichen') shichen: string = '';
  @LocalStorageProp('dateText') dateText: string = '';
  @LocalStorageProp('temperatureRange') temperatureRange: string = '';
  @LocalStorageProp('weatherSummary') weatherSummary: string = '';
  @LocalStorageProp('solarTime') solarTime: string = '';
  @LocalStorageProp('coords') coords: string = '';
  @LocalStorageProp('segments') segments: string[] = [];
  @LocalStorageProp('nowMinute') nowMinute: number = 0;
  @LocalStorageProp('offsetMinutes') offsetMinutes: number = 480;
  @LocalStorageProp('hourLabels') hourLabels: string[] = [];
  @LocalStorageProp('hourConds') hourConds: string[] = [];
  @LocalStorageProp('hourIcons') hourIcons: string[] = [];
  @LocalStorageProp('temperatureKey') temperatureKey: string = '';
  @LocalStorageProp('inKeyTime') inKeyTime: boolean = false;
  @LocalStorageProp('isDay') isDay: boolean = true;

  private bandColor(): string {
    if (this.temperatureKey === 'cold') {
      return this.isDay ? '#2E7D32' : '#4CAF7D';
    }
    if (this.temperatureKey === 'hot') {
      return this.isDay ? '#B3261E' : '#D9534F';
    }
    return this.solarAccent();
  }

  /** 真太阳时的强调色：白天橙色底上用淡金（比纯白暖一档），夜里用金色。 */
  private solarAccent(): string {
    return this.isDay ? DAY_ACCENT : GOLD;
  }

  /** 真太阳时的字色：落在关键时段里时用色条同色，其余按昼夜取白／金。 */
  private solarColor(): string {
    return this.inKeyTime ? this.bandColor() : this.solarAccent();
  }

  /** 时间轴上代表当前时刻的圆点跟着真太阳时变色；时段外仍是白色。 */
  private dotColor(): string {
    return this.inKeyTime ? this.bandColor() : WHITE;
  }

  /** 日期 + 当日天气与温度区间，例如「11 月 12 日 · 星期四 · 6° 晴 · 2° ~ 12°」。 */
  private dateTail(): string {
    const parts: string[] = [this.dateText];
    if (this.weatherSummary.length > 0) {
      parts.push(this.weatherSummary);
    }
    if (this.temperatureRange.length > 0) {
      parts.push(this.temperatureRange);
    }
    return parts.join(' · ');
  }

  private passedWeight(): number {
    return this.nowMinute > 0 ? this.nowMinute : 0.1;
  }

  private remainingWeight(): number {
    const rest: number = 1440 - this.nowMinute;
    return rest > 0 ? rest : 0.1;
  }

  @Builder
  hourCell(label: string, icon: string, condition: string) {
    Column() {
      Text(label)
        .fontSize(9)
        .fontColor(TEXT_DIM)
        .maxLines(1)
      Image(weatherIcon(icon))
        .width(15)
        .height(15)
        .objectFit(ImageFit.Contain)
        .margin({ top: 1 })
      Text(condition)
        .fontSize(9)
        .fontColor(TEXT_DIM)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 1 })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
  }

  build() {
    Column() {
      Row() {
        // 左：标准时间（交给 TextClock 自走）
        Column() {
          Row() {
            Text('标准时间')
              .fontSize(10)
              .fontColor(TEXT_LABEL)
              .maxLines(1)
            Text(this.city)
              .fontSize(10)
              .fontColor(TEXT_DIM)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .textAlign(TextAlign.End)
              .layoutWeight(1)
              .margin({ left: 6 })
          }
          .width('100%')
          TextClock()
            .fontSize(38)
            .fontWeight(FontWeight.Medium)
            .fontColor(WHITE)
          Row() {
            Text(this.dateTail())
              .fontSize(8)
              .fontColor(TEXT_DIM)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')
          .margin({ top: 1 })
          .onClick(() => {
            // 日期 → 日历（Android 的 widget_civil_date 指向日历，解析不到时冒泡到左栏的闹钟）
            postCardAction(this, {
              action: 'router',
              bundleName: 'com.huawei.hmos.calendar',
              abilityName: 'com.huawei.hmos.calendar.MainAbility'
            });
          })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .onClick(() => {
          // 左栏（标准时间）→ 时钟（闹钟），与 Android 的左栏一致
          postCardAction(this, {
            action: 'router',
            bundleName: 'com.huawei.hmos.clock',
            abilityName: 'com.huawei.hmos.clock.MainAbility'
          });
        })

        Column()
          .width(1)
          .height(42)
          .backgroundColor(DIVIDER)
          .margin({ left: 10, right: 10, top: 4 })

        // 右：真太阳时（快照，随卡片刷新更新；卡片里秒走不起来，所以只显示到分钟）
        Column() {
          Row() {
            Text('真太阳时')
              .fontSize(10)
              .fontColor(TEXT_LABEL)
              .maxLines(1)
            Text(this.shichen)
              .fontSize(10)
              .fontColor(TEXT_DIM)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .textAlign(TextAlign.End)
              .layoutWeight(1)
              .margin({ left: 6 })
          }
          .width('100%')
          Text(this.solarTime)
            .fontSize(38)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.solarColor())
            .maxLines(1)
            .width('100%')
          Text(this.coords)
            .fontSize(9)
            .fontColor(TEXT_DIM)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .textAlign(TextAlign.End)
            .margin({ top: 1 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .onClick(() => {
          // 右栏（真太阳时）→ 打开本应用
          postCardAction(this, {
            action: 'router',
            bundleName: 'com.realsuntime.solartime',
            abilityName: 'EntryAbility'
          });
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      // 0–24 时时间轴：与 Android 的 WidgetAxis 同款——1vp 细线 + 边缘柔化的圆点
      Stack() {
        Row() {
          ForEach(this.segments, (item: string) => {
            if (isBand(item)) {
              Row()
                .height(1)
                .backgroundColor(this.bandColor())
                .layoutWeight(segmentLength(item))
            } else {
              Row()
                .height(1)
                .layoutWeight(segmentLength(item))
            }
          }, (item: string, index: number) => `${index}-${item}`)
        }
        .width('100%')
        .height(1)
        .backgroundColor(AXIS_TRACK)

        Row() {
          Row().layoutWeight(this.passedWeight())
          Column()
            .width(11)
            .height(11)
            .borderRadius(5.5)
            .radialGradient({
              center: ['50%', '50%'],
              radius: 5.5,
              colors: [[this.dotColor(), 0], [this.dotColor(), 0.45], [`#00${this.dotColor().substring(1)}`, 1]]
            })
          Row().layoutWeight(this.remainingWeight())
        }
        .width('100%')
        .height(11)
      }
      .width('100%')
      .height(11)
      .margin({ top: 2 })

      Row() {
        ForEach(this.hourLabels, (label: string, index: number) => {
          this.hourCell(
            label,
            index < this.hourIcons.length ? this.hourIcons[index] : 'unknown',
            index < this.hourConds.length ? this.hourConds[index] : ''
          )
        }, (label: string, index: number) => `${index}-${label}`)
      }
      .width('100%')
      .margin({ top: 3 })
      .onClick(() => {
        // 逐时预报 → 天气应用，与 Android 的 widget_hour_row 一致
        postCardAction(this, {
          action: 'router',
          bundleName: 'com.huawei.hmos.weather',
          abilityName: 'com.huawei.hmos.weather.MainAbility'
        });
      })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Start)
    .borderRadius(22)
    .linearGradient({
      angle: 315,
      colors: this.isDay
        ? [['#F7A64B', 0], ['#EA7A2C', 1]]
        : [['#2A3B5C', 0], ['#151B2E', 1]]
    })
    .onClick(() => {
      // 空白处 / 时间轴 → 打开本应用
      postCardAction(this, {
        action: 'router',
        bundleName: 'com.realsuntime.solartime',
        abilityName: 'EntryAbility'
      });
    })
  }
}
