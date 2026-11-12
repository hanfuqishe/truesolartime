/**
 * 真太阳时桌面卡片。
 *
 * 受卡片能力限制（只有 ArkUI 组件子集、不能自定义绘制），布局刻意保持简单：
 *   区县 · 时辰 / 真太阳时（TextClock 自走，秒是系统在跳）/ 时辰范围 · 时差
 *   关键时间轴 / 天气与关键时间文字
 *
 * 时间轴上每一段的宽度用 layoutWeight 按分钟数分配，数据来自卡片绑定的 segments。
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

let storage: LocalStorage = new LocalStorage();

@Entry(storage)
@Component
struct SolarTimeCard {
  @LocalStorageProp('district') district: string = '';
  @LocalStorageProp('shichen') shichen: string = '';
  @LocalStorageProp('shichenRange') shichenRange: string = '';
  @LocalStorageProp('beijing') beijing: string = '';
  @LocalStorageProp('offsetMinutes') offsetMinutes: number = 480;
  @LocalStorageProp('offsetText') offsetText: string = '';
  @LocalStorageProp('temperature') temperature: string = '--';
  @LocalStorageProp('weather') weather: string = '';
  @LocalStorageProp('keyTime') keyTime: string = '';
  @LocalStorageProp('segments') segments: string[] = [];
  @LocalStorageProp('temperatureKey') temperatureKey: string = '';

  private bandColor(): string {
    if (this.temperatureKey === 'cold') {
      return '#4CAF7D';
    }
    if (this.temperatureKey === 'hot') {
      return '#D9534F';
    }
    return '#F5D68A';
  }

  build() {
    Column() {
      Row() {
        Text(this.district.length > 0 ? this.district : '—')
          .fontSize(13)
          .fontColor('#E8EDF7')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text(this.shichen)
          .fontSize(13)
          .fontColor('#F5D68A')
          .maxLines(1)
      }
      .width('100%')

      TextClock({ timeZoneOffset: this.offsetMinutes })
        .format('HH:mm:ss')
        .fontSize(40)
        .fontWeight(FontWeight.Bold)
        .fontColor('#F5D68A')
        .width('100%')
        .textAlign(TextAlign.Center)

      Row() {
        Text(this.shichenRange)
          .fontSize(10)
          .fontColor('#9AA7BF')
          .layoutWeight(1)
        Text(this.offsetText)
          .fontSize(10)
          .fontColor('#9AA7BF')
      }
      .width('100%')

      Row() {
        ForEach(this.segments, (item: string) => {
          if (isBand(item)) {
            Row()
              .height(6)
              .borderRadius(3)
              .backgroundColor(this.bandColor())
              .layoutWeight(segmentLength(item))
          } else {
            Row()
              .height(6)
              .layoutWeight(segmentLength(item))
          }
        }, (item: string, index: number) => `${index}-${item}`)
      }
      .width('100%')
      .height(6)
      .borderRadius(3)
      .backgroundColor('#24304F')
      .margin({ top: 6 })

      Row() {
        Text(this.temperature)
          .fontSize(13)
          .fontColor('#E8EDF7')
        Text(this.weather)
          .fontSize(11)
          .fontColor('#9AA7BF')
          .margin({ left: 4 })
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .margin({ top: 4 })

      Text(this.keyTime.length > 0 ? this.keyTime : '')
        .fontSize(10)
        .fontColor(this.bandColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .margin({ top: 2 })
    }
    .width('100%')
    .height('100%')
    .padding(12)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor('#16203A')
  }
}
