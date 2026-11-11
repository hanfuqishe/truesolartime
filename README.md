# 真太阳时

一个显示**真太阳时**（真太阳时 / 视太阳时）的跨平台应用，Android 与 iPhone 双端实现。

真太阳时的定义很简单：**太阳经过观测者所在子午线（正南或正北）的那一刻，记为 12:00**。它与钟表时间（北京时间）的差异来自两项修正：

- **经度修正**：取决于观测者所在经度，与东经 120° 每差 1° 即为 4 分钟。这是主要项，在中国境内可达 ±2 小时（乌鲁木齐约 −129 分钟）。
- **均时差**：取决于太阳的视位置（地球轨道偏心率与黄赤交角），全年在 −14 ~ +16 分钟之间。

所以「你在哪」决定了大头，「太阳在哪」只带来十几分钟的微调，两者合起来才是真太阳时。

## 功能

- **实时真太阳时**：每秒刷新的大字时钟，按当地经度与均时差校正。
- **北京时间对照**：同时显示北京时间，并拆解出「经度修正」与「均时差」两部分。
- **十二时辰**：按真太阳时划分（子时自 23:00 起，每两小时一个时辰），显示时初／时正、刻数以及距下个时辰的倒计时。
- **太阳位置**：日出、正午、日落按**北京时间**显示（与手机时钟一致），并附真太阳时对照；同时给出太阳高度角与日出到日落的位置弧线，极昼／极夜会单独提示。
- **定位方式**：默认持续跟随 GPS，每分钟采样一次；也可手动输入经纬度、从常用城市快速选择。位置会被记住。**跟随 GPS 但还没有拿到有效定位时，界面与小组件都不显示真太阳时**（显示 `--:--` 与「等待 GPS 定位…」，也不显示区县、气温与逐时天气），避免用默认坐标冒充当前位置；一旦拿到定位立即恢复。
- **位置地图**：内嵌地图，标注当前坐标，支持缩放拖动。境内自动使用高德底图（中文地名、路网更细），境外自动使用 OpenStreetMap；三种底图均无需 API Key。
- **时辰交接提醒**：可开关，**进入下一个时辰的那一刻**蜂鸣一声（**250 ms**，比关键时间报时更短，便于区分；开机后自动重新排程）。同样只响提示音、不发通知。
- **桌面小组件**：默认 **5×2** 布局（可双向拖拽缩放），左侧显示所在城市、所在国标准时间、日期与星期，右侧显示当地真太阳时、时辰与经纬度；时间精确到秒、秒数为半高小字，按昼夜切换底色。标准时间的时分秒由布局里的 `TextClock` 自己驱动（宿主进程按整分／整秒走时，与系统时钟同刻进位，不依赖 App 的刷新闹钟），真太阳时含秒级偏移只能每「真太阳时整分」刷新，秒数由 `Chronometer` 自走：刷新时把它的 `base` 设成「当前真太阳时整分的时刻」，它每次走完都会按 `base` 重算到下一整秒的延时，因此永远落在整秒边界上、不会累积漂移（`ViewFlipper` 的 `postDelayed(1000)` 每秒要多花几十毫秒，一分钟能慢近两秒）。`Chronometer` 的文本是 `M:SS`，于是用 `setMaxWidth` 把宽度限成两位数字、配合右对齐，只露出秒数；保留半高小字的样式。这里有两个要点：字体必须是**等宽**的（等宽下 `0:` 与 `00` 同宽，切点才与字体缩放、密度无关），字号也由 App 以 **px** 下发（布局里的 sp 会由宿主按它自己的字体缩放解析，一旦与本进程的度量不一致，裁剪点就会偏，把冒号也露出来——表现成「秒前面两个冒号」）。刷新闹钟会提前醒来、等真正的整分边界再写入，分钟与秒在同一刻进位。字号按栏宽实测换算（填满栏宽而不裁切），高度只用来在「常规」与「紧凑间距」两套布局间切换，极矮时先隐藏逐时行。
- **所在城市／区县**：配置高德 Android 平台 Key 后用 `GeocodeSearch` 反查行政区划（精确到区县）；结果按位置缓存，**新坐标与上次反查坐标相距超过 5 km 才重新查询**，否则一直沿用上次的结果（缓存超过 30 天也会刷新）。未配置 Key、离线或查询失败时回退到内置城市表（省会、常见地级市与各国主要城市取最近）。
- **当前天气**：小组件在日期后显示当天最低/最高气温（例如「11月10日 周二 · 7° ~ 13°」），底部还有一条**未来 5 小时的小时预报**（每格 1 小时，格内为时刻、天气图标与天气名称：晴／多云／阴／雾／小雨／中雨／大雨／阵雨／雪／大雪／雷雨，夜间图标用倾斜的月牙区分晴与多云）；数据来自 Open-Meteo（无需 Key），缓存 30 分钟，位置移动超过 5 km 才重新取数。
- **进入关键时间报时**：可开关，每到一段**关键时间的起点**蜂鸣一次，时长 500 ms（与时辰交接的 250 ms 区分开）、频率 2000 Hz（自己合成正弦波并加 10 ms 淡入淡出，比系统提示音高而清楚；`AudioTrack` 不可用时退回 `ToneGenerator` 的高频 pip）。关键时间按真太阳时计，报时闹钟也按真太阳时刻度对齐后再换算成系统时刻交给 `AlarmManager`（`RTC_WAKEUP` + `setExactAndAllowWhileIdle`，所以**锁屏与休眠时也会准时响**）；接收器用 `goAsync()` 保活到播放结束，避免进程被回收把声音截断。只响提示音，不发通知、不占通知栏；音量跟随**通知音量**，静音或勿扰模式下不会响。没有关键时间数据（从未抓取成功或已超过 7 天）时不报时。
- **小组件点击**：点左侧标准时间打开系统闹钟，点日期打开系统日历（`CATEGORY_APP_CALENDAR` → `content://com.android.calendar/time`），点底部天气打开系统天气（`CATEGORY_APP_WEATHER` → 常见厂商包名 → 浏览器兜底），点右侧真太阳时打开本 App。外部应用的解析结果缓存 10 分钟，且在 Manifest 里用 `<queries>` 声明可见性（Android 11+ 必需）。
- **关键时间时间轴**：天气上方那道横线是真太阳时 **0–24 时**的时间轴，白点（边缘做了柔化）标出当前时刻；轴上按「西格瑪食療」页面（<https://www.duosuccess.com/tcm/001a01080301b01a.htm>）上的「服用時間 Take Time」着色，页面给的时间就当作**关键时间**——**视作真太阳时**，不做时区或经度换算；标注 **Cold or Mild 用绿色**、**Hot or Mild 用红色**，色带与轴线等宽（只换颜色，不抢眼）。页面每天在 **01:00–05:00 之间挑一个随机时刻**同步一次，失败每小时重试；结果连时间戳一起缓存，**7 天内打不开就沿用上次的数据**，超过 7 天或从未成功抓取过则只画轴线、不着色。整条轴在 App 进程里画成位图后用 `setImageViewBitmap` 贴上去（`WidgetAxis`），因为没有能随刷新改变位置的系统控件可用。
- **添加到桌面**：设置面板里的按钮走 `requestPinAppWidget`。Android 没有「新建桌面页」的公开 API（页面归启动器管），桌面已满时启动器只会自己提示一句，App 既收不到失败回调也不能替你建页，因此这里比对「小组件实例数」判断是否真的加上去了，没加上就在按钮下方提示先新建一页或腾出位置。
- **多语言**：跟随系统语言自动切换简体中文、繁体中文或英文（`values-zh` / `values-b+zh+Hant` / `values`）。
- **主题**：跟随系统深色／浅色模式；主卡片另按白天／夜晚切换配色。

## 计算原理

```
真太阳时 = 北京时间 + (当地经度 − 120°) × 4 分钟 + 均时差
```

- **经度修正**：经度每偏离东经 120°（东八区中央经线）1°，时间相差 4 分钟。
- **均时差**：地球轨道偏心率与黄赤交角造成的日差，全年在约 −14 分到 +16 分之间变化，采用 NOAA Solar Calculator 的算法，误差约 ±0.5 分钟。
- **日出日落**：按天顶角 90.833°（含大气折射与太阳视半径）求解时角。

以北京（东经 116.4074°）11 月 2 日为例：经度修正 −14 分 22 秒，均时差 +16 分 29 秒，真太阳时比北京时间快约 2 分 06 秒。

## 构建

仓库按目标平台分目录，Android 部分在 `android/`：

```
android/   Android 工程（Kotlin + Compose，Gradle 根目录）
ios/       iPhone 工程（SwiftUI），见 ios/README.md
```

Android 侧需要 JDK 17+ 与 Android SDK（compileSdk 35、build-tools 35.0.0）。

```bash
cd android
./gradlew assembleDebug        # 产出 android/app/build/outputs/apk/debug/app-debug.apk
./gradlew testDebugUnitTest    # 太阳时／时辰计算单元测试
./gradlew lintDebug
./gradlew assembleRelease      # 产出 android/app/build/outputs/apk/release/app-release.apk
```

`assembleRelease` 结束后会自动把产物另存为 `android/dist/真太阳时-<版本号>.apk`（如 `真太阳时-1.4.5.apk`），
可直接分发；`dist/` 不参与版本控制，也不受 `clean` 影响。

发行版签名读取 `android/keystore.properties`（**不入库**），格式：

```properties
storeFile=release.jks
storePassword=***
keyAlias=solartime
keyPassword=***
```

缺少该文件时 `assembleRelease` 会产出未签名 APK。

可选：`android/amap.properties`（同样**不入库**）配置高德 **Android 平台 Key**，用于小组件显示区县名：

```properties
apiKey=你的高德Android平台Key
```

申请时填写的应用信息：

| 项 | 值 |
| --- | --- |
| PackageName | `com.realsuntime.solartime` |
| 发布版安全码 SHA1 | 见 `keytool -list -v -keystore android/release.jks -alias solartime` |
| 调试版安全码 SHA1 | 见 `keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android` |

Key 会作为 `com.amap.api.v2.apikey` 元数据打进 Manifest，只在逆地理编码时使用；不配置时小组件用内置城市表。配置后，只有新坐标与上次反查坐标相距 **超过 5 km**（或缓存超过 30 天）时才查询一次高德——市中心日常移动基本不会触发，配额压力极小（Android 平台 Key 与包名、签名绑定，他人反编译也无法使用）。

## 项目结构

```
android/                          Android（Kotlin + Compose，Gradle 根目录）
├── app/                          应用模块
├── gradle/  gradlew  *.gradle.kts
└── keystore.properties  local.properties     本地配置，不入库

ios/                              iPhone（SwiftUI），构建说明见 ios/README.md
├── TrueSolarTime/                源码（Core / UI / 平台层）
├── Scripts/                      数值自检与构建脚本
└── project.yml                   XcodeGen 工程定义
```

Android 源码结构：

```
android/app/src/main/java/com/realsuntime/solartime/
├── MainActivity.kt              入口
├── MainViewModel.kt             每秒时钟、定位状态、位置与提醒设置
├── solar/                       纯 Kotlin 天文与时辰计算（可单测）
│   ├── SolarTimeMath.kt         均时差、赤纬、真太阳时、日出日落、高度角
│   ├── Shichen.kt               十二时辰划分与交接时刻
│   ├── SolarSnapshot.kt         供 UI 消费的聚合快照
│   └── TimeFormat.kt            时间／时长格式化
├── map/                         WGS-84 ↔ GCJ-02、底图选择
├── data/                        位置模型、SharedPreferences、LocationManager 封装、地图配置、离线城市索引
├── notify/                      时辰交接提醒（AlarmManager + 蜂鸣）
├── widget/                      桌面小组件、时间轴、进入关键时间报时
└── ui/                          Compose 界面、地图卡片与主题
```

## 图标

图标是一只**倾斜 45° 的椭圆表盘**（圆盘按 41° 视角投影），指针枢轴位于椭圆偏下方的焦点处，刻度沿盘缘排布且每一根都指向枢轴。表圈、指针、中心轴帽均为解析式 3D 着色（Lambert + Blinn-Phong 高光、接触阴影、指针棱线）。

图标由脚本生成，不要手改 PNG：

```bash
python design/render_icon.py all       # 生成全部尺寸（Android mipmap/自适应图层、商店图标、iOS AppIcon）
python design/render_icon.py preview   # 生成 design/drafts/ 下的草稿便于调参
```

- `design/render_icon.py`：渲染器，参数集中在 `DEFAULTS`（倾角 `tilt_deg`、枢轴位置 `pivot_frac`、指针角度等）
- `design/icon-1024.png`、`design/icon-512.png`：母版与商店上传图
- 自适应图标：`mipmap-anydpi-v26/ic_launcher.xml` 引用 `ic_launcher_background.png` + `ic_launcher_foreground.png`（前景按 66dp 安全区缩放）
- 主题图标（Android 13+ 单色）：`drawable/ic_launcher_monochrome.xml`

## 多语言

| 语言 | 资源目录 |
| --- | --- |
| 英文（默认／兜底） | `res/values/` |
| 简体中文 | `res/values-zh/` |
| 繁体中文 | `res/values-b+zh+Hant/` |

系统语言为 `zh-Hans-*` 时取简体，`zh-Hant-*`（含 zh-TW / zh-HK）取繁体，其余语言取英文。所有界面文案、通知、小组件与时间单位均通过资源输出；代码中的 `TimeText` / `MapText` 负责格式化与地图底图名称。

## 权限

| 权限 | 用途 |
| --- | --- |
| `ACCESS_COARSE_LOCATION` / `ACCESS_FINE_LOCATION` | GPS 自动定位（可选，拒绝后仍可手动输入） |
| `SCHEDULE_EXACT_ALARM` | 让提醒准时触发（未授权时退化为可延迟闹钟） |
| `RECEIVE_BOOT_COMPLETED` | 重启后重新排程提醒 |
| `INTERNET` / `ACCESS_NETWORK_STATE` | 加载 OpenStreetMap 地图瓦片 |

## 第三方资源

地图瓦片来自 OpenStreetMap（© OpenStreetMap contributors，ODbL 协议），由 [osmdroid](https://github.com/osmdroid/osmdroid) 渲染。

天气数据来自 [Open-Meteo](https://open-meteo.com/)（© Open-Meteo.com，CC BY 4.0），无需 API Key。
