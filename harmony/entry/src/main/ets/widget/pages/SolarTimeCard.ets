/**
 * 真太阳时桌面卡片，版面严格对齐 Android 版小组件（widget_solar_time_compact.xml）：
 *
 *   左栏：标准时间 + 地名 / 大号标准时间 / 日期与今日温度区间
 *   右栏：真太阳时 + 时辰 / 大号真太阳时（带秒）/ 经纬度
 *   中间一条 1vp 竖分隔线；下面 0–24 时时间轴（色条为关键时间，白条为当前时刻）
 *   底部六格逐时预报（时刻、天气图标、天气名）
 *
 * 尺寸按鸿蒙 2*4 卡片实际可用的约 226×110vp 收：Android 的 4×2 有约 146dp 高，
 * 这里更矮，所以内边距、字号、图标都比 Android 再紧一档，保证六格预报不被裁掉。
 *
 * 与 Android 的两处差异来自卡片能力本身（实测 HarmonyOS 6.0.0 / API 20）：
 *   - 卡片里的 TextClock 只走系统本地时间，`format()` 与 `timeZoneOffset` 都被忽略，
 *     且卡片禁用定时器，所以真太阳时只能用快照文本（HH:mm:ss），随卡片刷新更新；
 *   - 因此左栏标准时间交给 TextClock 自走（分钟精度、跟随系统 12/24 小时制）。
 */

function segmentLength(item: string): number {
  const parts: string[] = item.split(',');
  const length: number = Number.parseFloat(parts[0]);
  return isNaN(length) || length <= 0 ? 1 : length;
}

function isBand(item: string): boolean {
  const parts: string[] = item.split(',');
  return parts.length > 1 && parts[1] !== '-1';
}

function iconOf(name: string): Resource {
  if (name === 'clear_day') {
    return $r('app.media.wx_clear_day');
  }
  if (name === 'clear_night') {
    return $r('app.media.wx_clear_night');
  }
  if (name === 'partly_day') {
    return $r('app.media.wx_partly_day');
  }
  if (name === 'partly_night') {
    return $r('app.media.wx_partly_night');
  }
  if (name === 'overcast') {
    return $r('app.media.wx_overcast');
  }
  if (name === 'fog') {
    return $r('app.media.wx_fog');
  }
  if (name === 'drizzle') {
    return $r('app.media.wx_drizzle');
  }
  if (name === 'rain') {
    return $r('app.media.wx_rain');
  }
  if (name === 'heavy_rain') {
    return $r('app.media.wx_heavy_rain');
  }
  if (name === 'showers') {
    return $r('app.media.wx_showers');
  }
  if (name === 'snow') {
    return $r('app.media.wx_snow');
  }
  if (name === 'heavy_snow') {
    return $r('app.media.wx_heavy_snow');
  }
  if (name === 'thunder') {
    return $r('app.media.wx_thunder');
  }
  return $r('app.media.wx_unknown');
}

const GOLD: string = '#FFC65C';
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
  @LocalStorageProp('solarTime') solarTime: string = '';
  @LocalStorageProp('solarSeconds') solarSeconds: string = '';
  @LocalStorageProp('coords') coords: string = '';
  @LocalStorageProp('segments') segments: string[] = [];
  @LocalStorageProp('nowMinute') nowMinute: number = 0;
  @LocalStorageProp('offsetMinutes') offsetMinutes: number = 480;
  @LocalStorageProp('hourLabels') hourLabels: string[] = [];
  @LocalStorageProp('hourConds') hourConds: string[] = [];
  @LocalStorageProp('hourIcons') hourIcons: string[] = [];
  @LocalStorageProp('temperatureKey') temperatureKey: string = '';

  private bandColor(): string {
    if (this.temperatureKey === 'cold') {
      return '#4CAF7D';
    }
    if (this.temperatureKey === 'hot') {
      return '#D9534F';
    }
    return GOLD;
  }

  private passedWeight(): number {
    return this.nowMinute > 0 ? this.nowMinute : 0.1;
  }

  private remainingWeight(): number {
    const rest: number = 1440 - this.nowMinute;
    return rest > 0 ? rest : 0.1;
  }

  @Builder
  labelRow(label: string, tail: string) {
    Row() {
      Text(label)
        .fontSize(10)
        .fontColor(TEXT_LABEL)
        .maxLines(1)
      Text(tail)
        .fontSize(10)
        .fontColor(TEXT_DIM)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.End)
        .layoutWeight(1)
        .margin({ left: 6 })
    }
    .width('100%')
  }

  @Builder
  hourCell(label: string, icon: string, condition: string) {
    Column() {
      Text(label)
        .fontSize(9)
        .fontColor(TEXT_DIM)
        .maxLines(1)
      Image(iconOf(icon))
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
          this.labelRow('标准时间', this.city)
          TextClock()
            .fontSize(38)
            .fontWeight(FontWeight.Lighter)
            .fontColor(WHITE)
          Row() {
            Text(this.temperatureRange.length > 0 ? `${this.dateText} · ${this.temperatureRange}` : this.dateText)
              .fontSize(8)
              .fontColor(TEXT_DIM)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')
          .margin({ top: 1 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Column()
          .width(1)
          .height(52)
          .backgroundColor(DIVIDER)
          .margin({ left: 10, right: 10 })

        // 右：真太阳时（快照，随卡片刷新更新）
        Column() {
          this.labelRow('真太阳时', this.shichen)
          Row() {
            Text(this.solarTime)
              .fontSize(38)
              .fontWeight(FontWeight.Lighter)
              .fontColor(GOLD)
              .maxLines(1)
            Text(':')
              .fontSize(21)
              .fontWeight(FontWeight.Lighter)
              .fontColor(GOLD)
              .maxLines(1)
              .margin({ bottom: 4 })
            Text(this.solarSeconds)
              .fontSize(21)
              .fontWeight(FontWeight.Lighter)
              .fontColor(GOLD)
              .maxLines(1)
              .margin({ bottom: 4, left: 1 })
          }
          .width('100%')
          .alignItems(VerticalAlign.Bottom)
          .onClick(() => {
            // 卡片上的真太阳时是快照，点一下让应用立刻重算并回推（卡片自身不能用定时器）。
            postCardAction(this, {
              action: 'message',
              params: { msg: 'refresh' }
            });
          })
          Text(this.coords)
            .fontSize(9)
            .fontColor(TEXT_DIM)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 1 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

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
              colors: [[WHITE, 0], [WHITE, 0.45], ['#00FFFFFF', 1]]
            })
          Row().layoutWeight(this.remainingWeight())
        }
        .width('100%')
        .height(11)
      }
      .width('100%')
      .height(11)
      .padding({ left: 6, right: 6 })
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
    }
    .width('100%')
    .height('100%')
    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Start)
    .borderRadius(22)
    .linearGradient({ angle: 315, colors: [['#2A3B5C', 0], ['#151B2E', 1]] })
  }
}
