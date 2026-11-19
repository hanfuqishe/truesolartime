/**
 * 设置页：与 Android 的 SettingsSheet 对应 —— 当前位置、手动坐标、常用城市、提醒开关、关于。
 * 主界面通过「设置」进入，返回后由 Index.onPageShow 重新读取偏好。
 */

import { common, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { promptAction, router } from '@kit.ArkUI';
import { formInfo, formProvider } from '@kit.FormKit';
import { notificationManager } from '@kit.NotificationKit';
import { CityIndex, NearbyCity } from '../core/CityIndex';
import { DistrictNameLogic, DistrictNames } from '../core/DistrictName';
import { MAP_STYLE_OPTIONS, MapStyleOption, MapTilesLogic } from '../core/MapTiles';
import { Place, PlaceSource } from '../core/Place';
import { TakeBand, TakeTimeSchedule } from '../core/TakeTime';
import { TimeFormat } from '../core/TimeFormat';
import { SolarTimeMath } from '../core/SolarTimeMath';
import { ThemeMode } from '../core/ThemeMode';
import { WeatherSource, WeatherLogic } from '../core/Weather';
import { AppStore, WeatherDiag } from '../services/Store';
import { AppInfo } from '../services/AppInfo';
import { CardService, CARD_ENTRY_ENABLED } from '../services/CardService';
import { DistrictService } from '../services/DistrictService';
import { MapTileService } from '../services/MapTileService';
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
  /** 配色模式：AUTO（默认，按日出日落）/ LIGHT / DARK，见 core/ThemeMode.ets。 */
  @State themeMode: string = ThemeMode.AUTO;
  /** 诊断：天气源、逐时步长、上次取数尝试、下次重试倒计时与最近失败原因。 */
  @State weatherSource: string = WeatherSource.OPEN_METEO;
  @State weatherStep: number = 1;
  @State weatherStatus: string = '';
  @State weatherResult: string = '';
  @State weatherFailure: string = '';
  /** 上次取数尝试的时间文案，例如「08:41（3 分钟前）」；从未试过时是「暂无」。 */
  @State weatherAttempt: string = '暂无';
  /** 下次自动取数的倒计时，例如「57 秒后（主源轮询）」。 */
  @State weatherRetry: string = '—';
  /** 地图底图诊断：实际源 / 样式 / 首选 / 缩放与降级 / 瓦片状态 / OSM 失败 / 空白判定 / 下次探测。 */
  @State mapDiagLines: string[] = [];
  /** 地图底图标识（见 core/MapTiles 的 MAP_STYLE_OPTIONS）。 */
  @State mapStyleKey: string = 'auto';
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
    this.mapStyleKey = AppStore.mapStyle();
    this.themeMode = AppStore.themeMode();
    this.manualLatitude = this.place.latitude.toFixed(4);
    this.manualLongitude = this.place.longitude.toFixed(4);
    const labels: string[] = [];
    for (const preset of Place.PRESETS) {
      labels.push(this.cityLabel(preset));
    }
    this.presetLabels = labels;
    this.applyPalette();
    this.reloadDiagnostics();
  }

  /**
   * 页面配色：与首页同一套判定 —— 「自动」看太阳高度角（> -0.833° 为白天），
   * 亮色/暗色直接强制。太阳弧之类的真实太阳量不受影响。
   */
  private applyPalette(): void {
    const altitude: number = SolarTimeMath.solarAltitudeDegrees(Date.now(), this.place.latitude, this.place.longitude);
    this.palette = paletteFor(ThemeMode.isLight(this.themeMode, altitude > -0.833));
  }

  /**
   * 诊断数据（设置页底部「诊断」）：天气源 / 逐时步长 / 数据过期分钟数 / 最近失败原因。
   *
   * 键名与 Android 的 DiagReport 一致（`weather_source` / `weather_step` / `weather_age_minutes`），
   * 用户截图时两边能直接对上。
   */
  private reloadDiagnostics(): void {
    this.weatherSource = WeatherService.source();
    this.weatherStep = WeatherService.stepHours();
    const ageMinutes: number = WeatherService.ageMinutes();
    // 低精度（7Timer! 3 小时）前台按 60/120/300 秒退避重试主源（后台 10 分钟），成功立刻切回 1 小时源。
    const lowPrecision: string = WeatherLogic.isLowPrecision(this.weatherSource, this.weatherStep)
      ? '（低精度 3 小时数据：前台按 60/120/300 秒退避重试主源，后台 10 分钟）'
      : '';
    // 缓存按地点区分（≤5 km）：有缓存但它属于上一个城市时，界面显示的是占位符。
    const belongs: boolean = WeatherService.cached(this.place) !== null;
    if (ageMinutes < 0) {
      this.weatherStatus = '当前地点没有缓存（显示占位符）';
    } else if (!belongs) {
      this.weatherStatus = `当前地点没有缓存：旧缓存属于其他地点（显示占位符），数据已放置 ${ageMinutes} 分钟`;
    } else if (ageMinutes <= 30) {
      this.weatherStatus = `数据有效（${ageMinutes} 分钟前更新）${lowPrecision}`;
    } else {
      this.weatherStatus = `数据过期 ${ageMinutes} 分钟${lowPrecision}`;
    }
    const diag: WeatherDiag = AppStore.weatherDiag();
    this.weatherResult = diag.result.length > 0 ? diag.result : '暂无记录';
    this.weatherFailure = diag.failure;

    // 上次取数尝试（每次取数都会先记一拍，所以它也是「上次主源尝试」）与下次重试倒计时。
    const attemptMillis: number = WeatherService.lastAttemptMillis();
    if (attemptMillis > 0) {
      const agoMinutes: number = Math.max(0, Math.floor((Date.now() - attemptMillis) / 60000));
      this.weatherAttempt = `${this.clockLabel(attemptMillis)}（${agoMinutes} 分钟前）`;
    } else {
      this.weatherAttempt = '暂无';
    }
    const retrySeconds: number = WeatherService.nextRetrySeconds();
    const retryReason: string = WeatherLogic.isLowPrecision(this.weatherSource, this.weatherStep)
      ? `主源轮询，已连续失败 ${AppStore.weatherPrimaryFailures()} 次`
      : (ageMinutes > 30 ? '过期重试' : '缓存过期');
    this.weatherRetry = retrySeconds <= 0
      ? '即将重试'
      : `${retrySeconds} 秒后（${retryReason}）`;
    this.mapDiagLines = MapTileService.diagnostics();
  }

  /** 毫秒时间戳 → 「HH:mm」（本地时区），诊断里显示取数时刻。 */
  private clockLabel(millis: number): string {
    const date: Date = new Date(millis);
    const hour: number = date.getHours();
    const minute: number = date.getMinutes();
    return `${hour < 10 ? '0' : ''}${hour}:${minute < 10 ? '0' : ''}${minute}`;
  }

  /**
   * 当前位置的名字，三段式（与首页卡片、Android `MainScreen.cityText` 一致）：
   * ① 反查到的区划名（必须经 `cachedNamesFor(place)` 按坐标过滤，≤ 5 km）；
   * ② 反查未回/失败时只有预设城市才回退到城市名；③ 都没有就显示半角减号。
   */
  private labelOf(place: Place): string {
    const district: DistrictNames | null = place.sameLocation(AppStore.place())
      ? DistrictService.cachedNamesFor(place)
      : null;
    return DistrictNameLogic.labelFor(district, this.cityLabel(place));
  }

  /**
   * 常用城市按钮上的名字：固定用城市名，不跟随逆地理结果（否则「上海」会变成「黄浦区」）。
   *
   * 非预设点（手工坐标 / GPS）没有名字可用，返回空串 —— 由 `DistrictNameLogic.labelFor` 统一落成 `-`。
   */
  private cityLabel(place: Place): string {
    const preset: Place | null = Place.presetOf(place);
    if (preset === null) {
      return '';
    }
    return this.cityNameOf(preset);
  }

  /** 预设城市的名字：内置城市先看 label，境外城市按坐标查离线城市表（随界面语言变化）。 */
  private cityNameOf(place: Place): string {
    if (place.label.length > 0) {
      return place.label;
    }
    const city: NearbyCity | null = CityIndex.nearest(place.latitude, place.longitude, DistrictService.language());
    return city === null ? '' : city.name;
  }

  /** 设置页也按「跟随意图 + 还没有 GPS fix」判断未知态，坐标统一显示 `--`。 */
  private isUnknownLocation(): boolean {
    return AppStore.gpsIntent() && this.place.source !== PlaceSource.GPS;
  }

  /** 常用城市按 4 个一行切分的行号（最后一行不满 4 个也保留空位）。 */
  private presetRowIndexes(): number[] {
    const rows: number[] = [];
    const count: number = Math.ceil(Place.PRESETS.length / 4);
    for (let index: number = 0; index < count; index++) {
      rows.push(index);
    }
    return rows;
  }

  private applyPlace(place: Place, leave: boolean = false): void {
    // 换地点（含手动坐标）：先把旧区划名清掉，反查回来前显示 `-`，绝不残留上一个城市。
    if (!place.sameLocation(this.place)) {
      DistrictService.clearCached();
    }
    AppStore.setPlace(place);
    // 选城市 / 输坐标 = 退出「跟随 GPS」意图；只有 GPS 定位重新打开意图。
    AppStore.setGpsIntent(place.source === PlaceSource.GPS);
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

  /**
   * 「添加到桌面」：打开系统的卡片页（`formProvider.openFormManager`，API 18+）。
   *
   * HarmonyOS 没有「应用内把卡片直接钉到桌面」的能力（Android 的 `requestPinAppWidget`
   * 在鸿蒙没有对应物），能做的只是把用户送到卡片页，由用户点「添加」。低版本系统上
   * 该接口不存在，会抛错，这时退回提示「长按桌面空白处 → 卡片」。
   */
  private addCardToDesktop(): void {
    const params: Record<string, Object> = {};
    params['ohos.extra.param.key.form_dimension'] = formInfo.FormDimension.Dimension_2_4;
    params['ohos.extra.param.key.form_name'] = 'solar_time_card';
    params['ohos.extra.param.key.module_name'] = 'entry';
    const want: Want = {
      bundleName: 'com.realsuntime.solartime',
      abilityName: 'SolarTimeFormAbility',
      parameters: params
    };
    try {
      formProvider.openFormManager(want);
      console.info('[card] openFormManager dispatched');
      // 系统卡片页能否真的打开取决于桌面实现；无论成功与否都给一句反馈，
      // 免得用户点了没反应（模拟器上实测：接口不抛错，但界面无变化）。
      promptAction.showToast({ message: '已请求打开卡片页：选中「真太阳时」再点添加；打不开就长按桌面空白处 → 卡片' });
    } catch (error) {
      const err = error as BusinessError;
      console.error(`[card] openFormManager failed: ${err.code} ${err.message}`);
      promptAction.showToast({
        message: `打不开卡片页（${err.code}）：请长按桌面空白处 → 卡片 → 真太阳时`
      });
    }
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
    // 用户明确要求「跟随 GPS」：**先把意图落地，再看权限**。
    // 无权限时也必须留下意图，首页才能据此进入「定位不可用」未知态，而不是继续显示旧地点。
    AppStore.setGpsIntent(true);
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
    // 手动坐标：立刻清掉上一个城市的区划名，反查成功才显示结果，失败保持 `-`。
    DistrictService.clearCached();
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
          // 长地名只允许占右侧 55%，永不压到左边的「设置」标题。
          .constraintSize({ maxWidth: '55%' })
          .margin({ left: 8 })
          .textAlign(TextAlign.End)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })

      Scroll() {
        Column({ space: 12 }) {
          // 当前位置
          Column() {
            this.sectionTitle('当前位置')
            Text(`${this.isUnknownLocation() ? '定位不可用' : this.placeName}　${
              TimeFormat.coordinates(this.place.latitude, this.place.longitude, this.isUnknownLocation())}`)
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
            // 手工分行：每行固定 4 格，每格 layoutWeight(1)，等宽由结构保证。
            ForEach(this.presetRowIndexes(), (row: number) => {
              Row({ space: 8 }) {
                ForEach([0, 1, 2, 3], (column: number) => {
                  if (row * 4 + column < Place.PRESETS.length) {
                    Row() {
                      Text(row * 4 + column < this.presetLabels.length
                        ? this.presetLabels[row * 4 + column]
                        : TimeFormat.coordinates(Place.PRESETS[row * 4 + column].latitude,
                          Place.PRESETS[row * 4 + column].longitude))
                        .fontSize(12)
                        .fontColor(this.palette.text)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .textAlign(TextAlign.Center)
                        .width('100%')
                        .padding({ left: 4, right: 4 })
                    }
                    .layoutWeight(1)
                    .height(32)
                    .justifyContent(FlexAlign.Center)
                    .backgroundColor(this.palette.chip)
                    .borderRadius(14)
                    .onClick(() => {
                      this.applyPlace(Place.PRESETS[row * 4 + column], true);
                    })
                  } else {
                    // 空位也占 1/4，最后一行左对齐、右侧留空。
                    Row()
                      .layoutWeight(1)
                      .height(32)
                  }
                }, (column: number) => `${row}-${column}`)
              }
              .width('100%')
              .margin({ top: 8 })
            }, (row: number) => `${row}`)
          }
          .cardStyle()
    .backgroundColor(this.palette.card)

          // 地图底图：与 Android 设置面板同一组选项
          Column() {
            this.sectionTitle('地图底图')
            Text(MapTilesLogic.autoHint(DistrictService.language()))
              .fontSize(10)
              .fontColor(this.palette.subtle)
              .margin({ top: 4 })
              .width('100%')
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(MAP_STYLE_OPTIONS, (option: MapStyleOption) => {
                Text(MapTilesLogic.optionLabel(option, DistrictService.language()))
                  .fontSize(12)
                  .fontColor(option.key === this.mapStyleKey ? this.palette.onAccent : this.palette.text)
                  .backgroundColor(option.key === this.mapStyleKey ? this.palette.accent : this.palette.chip)
                  .borderRadius(14)
                  .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                  .margin({ right: 8, top: 8 })
                  .onClick(() => {
                    this.mapStyleKey = option.key;
                    AppStore.setMapStyle(option.key);
                    // 换底图 = 重新开始：清掉上一次会话的回退/降级记忆。
                    MapTileService.reset();
                  })
              }, (option: MapStyleOption) => option.key)
            }
            .width('100%')
            .margin({ top: 4 })
            Text('选中后返回首页生效')
              .fontSize(10)
              .fontColor(this.palette.subtle)
              .margin({ top: 4 })
              .width('100%')
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

          // 屏幕：常亮开关 + 主题三选（与 Android 的 SettingsSheet 同一片区、同一组语义）
          Column() {
            this.sectionTitle('屏幕')
            this.switchRow('屏幕常亮', '应用打开期间不自动熄屏（会更耗电）', this.keepScreenOn,
              (value: boolean) => {
                this.keepScreenOn = value;
                AppStore.setKeepScreenOn(value);
                KeepAwake.apply(this.context);
              })
            Text('主题')
              .fontSize(14)
              .fontColor(this.palette.text)
              .margin({ top: 14 })
              .width('100%')
            Text(ThemeMode.description(this.themeMode))
              .fontSize(10)
              .fontColor(this.palette.subtle)
              .margin({ top: 2 })
              .width('100%')
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(ThemeMode.OPTIONS, (mode: string) => {
                Text(ThemeMode.label(mode))
                  .fontSize(12)
                  .fontColor(mode === this.themeMode ? this.palette.onAccent : this.palette.text)
                  .backgroundColor(mode === this.themeMode ? this.palette.accent : this.palette.chip)
                  .borderRadius(14)
                  .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                  .margin({ right: 8, top: 8 })
                  .onClick(() => {
                    this.themeMode = ThemeMode.fromName(mode);
                    AppStore.setThemeMode(this.themeMode);
                    // 当场换色：用户不用返回首页就能看到效果（返回后由 Index.onPageShow 重新读取）。
                    this.applyPalette();
                  })
              }, (mode: string) => mode)
            }
            .width('100%')
            .margin({ top: 4 })
            Text('光照与真太阳时的计算不受影响；太阳弧上的圆点永远按真实太阳高度角摆放。')
              .fontSize(10)
              .fontColor(this.palette.subtle)
              .margin({ top: 6 })
              .width('100%')
          }
          .cardStyle()
    .backgroundColor(this.palette.card)

          // 桌面卡片：挪到页面下方、「诊断」正上方（与 Android 设置页同一顺序：
          // 提醒 → 屏幕/主题 → 添加到桌面 → 诊断 → 关于）。1.4.37 起开放。
          // 注意鸿蒙的 ArkTS 卡片做不到「非本地时间的分钟级自走」，卡片上的真太阳时最多
          // 滞后约 30 分钟，所以说明里必须写清，别让用户当成秒表。
          if (CARD_ENTRY_ENABLED) {
            Column() {
              this.sectionTitle('桌面卡片')
              Text('把 2×4 的真太阳时卡片放到桌面：点下面按钮打开卡片页，选中「真太阳时」再点添加。')
                .fontSize(10)
                .fontColor(this.palette.subtle)
                .margin({ top: 4 })
                .width('100%')
              Button('添加到桌面')
                .fontSize(13)
                .backgroundColor(this.palette.accent)
                .fontColor(this.palette.onAccent)
                .width('100%')
                .height(38)
                .margin({ top: 10 })
                .onClick(() => {
                  this.addCardToDesktop();
                })
              Text('注意：系统限制卡片内的时钟不能自走，卡片上的真太阳时最多滞后约 30 分钟；要看准点请打开应用。')
                .fontSize(10)
                .fontColor(this.palette.subtle)
                .margin({ top: 8 })
                .width('100%')
            }
            .cardStyle()
            .backgroundColor(this.palette.card)
          }

          // 诊断：天气源 / 逐时步长 / 数据过期分钟数 / 最近失败原因
          Column() {
            this.sectionTitle('诊断')
            Text(`天气源：${WeatherSource.displayName(this.weatherSource)}`)
              .fontSize(11)
              .fontColor(this.palette.text)
              .margin({ top: 8 })
              .width('100%')
            Text(`逐时步长：${this.weatherStep} 小时（6 格共 ${this.weatherStep * 6} 小时）`)
              .fontSize(11)
              .fontColor(this.palette.text)
              .margin({ top: 4 })
              .width('100%')
            Text(`数据状态：${this.weatherStatus}`)
              .fontSize(11)
              .fontColor(this.palette.text)
              .margin({ top: 4 })
              .width('100%')
            Text(`上次取数尝试：${this.weatherAttempt}`)
              .fontSize(11)
              .fontColor(this.palette.text)
              .margin({ top: 4 })
              .width('100%')
            Text(`下次重试：${this.weatherRetry}`)
              .fontSize(11)
              .fontColor(this.palette.text)
              .margin({ top: 4 })
              .width('100%')
            Text(`最近一次取数：${this.weatherResult}`)
              .fontSize(11)
              .fontColor(this.palette.text)
              .margin({ top: 4 })
              .width('100%')
            if (this.weatherFailure.length > 0) {
              Text(`最近失败原因：${this.weatherFailure}`)
                .fontSize(11)
                .fontColor('#D9534F')
                .margin({ top: 4 })
                .width('100%')
            }
            Text('天气缓存按地点区分：换了城市后，新地点没有缓存就显示占位符，不会沿用旧城市的读数。')
              .fontSize(10)
              .fontColor(this.palette.subtle)
              .margin({ top: 8 })
              .width('100%')
            ForEach(this.mapDiagLines, (line: string) => {
              Text(line)
                .fontSize(11)
                .fontColor(this.palette.text)
                .margin({ top: 4 })
                .width('100%')
            }, (line: string, index: number) => `${index}-${line}`)
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
            Text(`数据来源：天气 ${WeatherSource.attribution(this.weatherSource)}；区划名：系统逆地理编码 / OSM Nominatim。`)
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
