# 真太阳时 · 鸿蒙版（HarmonyOS NEXT）

纯血鸿蒙（HarmonyOS NEXT / HarmonyOS 5）实现：ArkTS + ArkUI，不含任何 Android 兼容层，
同时提供**桌面服务卡片**（Form）与**系统代理提醒**。功能以 Android 版 1.4.34 为基准。

## 功能对照

| 功能 | Android | 鸿蒙 | 说明 |
| --- | --- | --- | --- |
| 每秒刷新的真太阳时大时钟 | ✅ | ✅ | 页面内 1 秒定时器（首页大卡片与桌面卡片同款版面，逐秒生效） |
| 时辰（时初／时正、刻数、范围、倒计时） | ✅ | ✅ | 同一套 `Shichen` 逻辑；首页不显示刻数与下个时辰倒计时 |
| 北京时间对照（经度修正 + 均时差） | ✅ | ✅ | 同一套计算；首页不展示总时差与拆解过程 |
| 日出／上中天／日落、白昼时长、高度角、极昼极夜 | ✅ | ✅ | 同一套 NOAA 公式 |
| 天气（气温 + WMO 天气码，30 分钟缓存） | ✅ | ✅ | Open-Meteo，无需 Key；主界面另有未来 5 小时逐时预报与今日温度区间 |
| 关键时间时间轴（「服用時間 Take Time」） | ✅ | ✅ | 同一套解析与 7 天缓存、01:00–05:00 随机同步 |
| 区划名（跟随界面语言，5 km / 30 天缓存） | ✅ | ✅ | 逆地理：系统 `geoLocationManager`，非中文界面走 OSM Nominatim；中文显示到「市+区」 |
| 手动坐标 / 常用城市 / 定位 | ✅ | ✅ | 定位只用 `APPROXIMATELY_LOCATION`（±100 m 足够）；选「使用当前位置」后进入跟随 GPS 模式，见下 |
| 时辰交接提醒（250 ms） | ✅ | ✅（系统代理提醒） | 见「与 Android 的差异」 |
| 进入关键时间报时（500 ms） | ✅ | ✅（系统代理提醒） | 同上 |
| 桌面卡片：标准时间／真太阳时两栏、日期与气温区间、经纬度、关键时间轴、六格逐时预报 | ✅ | ✅ | 2×4，版面与 Android 的 `widget_solar_time_compact.xml` 一致；时间轴为 1vp 细线 + 边缘柔化的圆点 |
| 内嵌地图（高德／OSM 底图） | ✅ | ❌ | 鸿蒙 Map Kit 需要在 AGC 建项目并配置签名与 `client_id`，本仓库不预置；位置信息改由「坐标 + 最近城市」呈现 |
| 桌面卡片点击分区 | ✅ | ✅ | 左栏→时钟、日期→日历、逐时行→天气、右栏与空白→本应用；见下 |

## 目录结构

```
harmony/
├── AppScope/                     应用级配置（bundleName、图标）
├── entry/
│   ├── src/main/
│   │   ├── module.json5          入口 Ability、FormExtensionAbility、权限
│   │   ├── ets/
│   │   │   ├── core/             纯逻辑（不带系统 API，可用 tsc 编译验证）
│   │   │   │   ├── SolarTimeMath.ets   均时差、赤纬、真太阳时、日出日落、高度角
│   │   │   │   ├── Shichen.ets         十二时辰
│   │   │   │   ├── SolarSnapshot.ets   供界面消费的聚合快照
│   │   │   │   ├── TimeFormat.ets      时间／时长格式化（中英）
│   │   │   │   ├── CityIndex.ets       250 个城市的离线表（中英双语）
│   │   │   │   ├── TakeTime.ets        关键时间解析、缓存策略、时间轴分段
│   │   │   │   ├── Weather.ets         天气码解析与分类
│   │   │   │   ├── DistrictName.ets    区划名拼接规则
│   │   │   │   ├── Chime.ets           报时窗口与下次交接时刻
│   │   │   │   └── Place.ets           观测点模型与常用城市
│   │   │   ├── services/         系统能力封装
│   │   │   │   ├── Store.ets           preferences（同步读，卡片进程也能用）
│   │   │   │   ├── HttpUtil.ets        HTTP GET
│   │   │   │   ├── LocationService.ets 定位与权限
│   │   │   │   ├── DistrictService.ets 逆地理编码 + OSM 兜底
│   │   │   │   ├── WeatherService.ets  天气取数与缓存
│   │   │   │   ├── KeyTimeService.ets  关键时间抓取与缓存
│   │   │   │   ├── ReminderService.ets 代理提醒发布／取消
│   │   │   │   ├── ChimePlayer.ets     前台报时音（AVPlayer + rawfile）
│   │   │   │   └── CardService.ets     卡片数据组装与推送
│   │   │   ├── entryability/     UIAbility
│   │   │   ├── entryformability/ FormExtensionAbility
│   │   │   ├── pages/Index.ets   主界面
│   │   │   └── widget/pages/SolarTimeCard.ets  桌面卡片
│   │   └── resources/           字符串（中／英）、颜色、图标、form_config.json、报时音
│   └── build-profile.json5
├── Tools/                        本地校验脚本（不需要 DevEco Studio）
│   ├── verify-core.js            把 core/*.ets 当 TypeScript 编译并跑 159 项数值自检
│   ├── core-check.ts             自检用例（期望值与 Android 单测一致）
│   ├── check-ets.py              导入／导出、括号、ArkTS 禁用特性静态检查
│   ├── gen-city-index.py         从 Android 城市表同步 CityIndex.ets
│   └── gen-icons.py              把 design/icon-512.png（与 Android 同一张图）同步成 app_icon.png
└── build-profile.json5
```

## 构建

装 **DevEco Studio**（Windows / macOS 都有），不支持 Android Studio。版本关系：

| 工具链 | HarmonyOS SDK | 说明 |
| --- | --- | --- |
| DevEco Studio 5.0.3+ | API 12（5.0.0） | 本工程最低要求，也是 `compatibleSdkVersion` 的取值 |
| DevEco Studio 5.1.x / 6.x 及更新版本 | API 更高 | **可以直接打开本工程**，详见下节 |

### 首次构建

1. 用 DevEco Studio 打开本目录（`harmony/`），等待 `Sync` 完成。
2. `File → Project Structure → Signing Configs` 勾选 **Automatically generate signature**（需登录华为开发者账号；真机调试用调试证书即可）。
3. 运行 `entry` 到真机或模拟器；或命令行：

```bash
cd harmony
./hvigorw --mode module -p product=default -p module=entry@default assembleHap
# 产物：entry/build/default/outputs/default/entry-default-signed.hap
hdc install entry/build/default/outputs/default/entry-default-signed.hap
```

在 DevEco Studio 里构建时 IDE 会自己注入 SDK 路径；**脱离 IDE 直接跑 `hvigorw` 必须先给 `DEVECO_SDK_HOME`**，
否则报 `00303217 Configuration Error: Invalid value of 'DEVECO_SDK_HOME'`：

```powershell
$env:DEVECO_SDK_HOME = 'D:\DevEco Studio\sdk'   # DevEco 安装目录下的 sdk
```

没有签名时 `assembleHap` 也能过，只是产物未签名、无法安装（`entry-default-unsigned.hap`）。

### 用更高版本的 DevEco Studio 打开

不需要为此去找 5.0.3，装最新的就行。首次 `Sync` 时 IDE 会提示工程/hvigor 插件版本较旧，按提示升级即可：

1. 弹出的 **「工程升级 / Migrate」** 提示点确认 —— 它会把 `hvigorfile.ts` 依赖、`hvigor/hvigor-config.json5` 与
   `oh-package.json5` 里的 `modelVersion` 一起抬到当前 IDE 的版本，源码不用改。
2. 若提示 `compatibleSdkVersion` 对应的 SDK 未安装，二选一：
   - 在 SDK Manager 里补装 **API 12**（保持向下兼容，装到 HarmonyOS 5.x 真机也能跑）；
   - 或者把 `build-profile.json5` 的 `compatibleSdkVersion` 改成当前 IDE 的版本（例如 `5.0.5(17)`、`6.0.0(20)`）——
     本工程只用到 API 12 的能力（`TextClock.timeZoneOffset`、`reminderAgentManager`、
     `getAddressesFromLocation`、`preferences.getPreferencesSync`），向上编译没有兼容问题，代价是装不到更旧的系统上。
3. 如果 IDE 提示迁移到 **ArkTS 1.2 / 静态化**（HarmonyOS 6 起的新语法版本），选择**保持 ArkTS 1.1**：
   本工程用的是 1.1 的装饰器写法（`@Entry` / `@Component` / `@Builder` / `@State`）。
4. 升级后先跑一次 `Sync`，再看 `Build → Build Hap(s)` 是否通过。

## 本地校验（不需要鸿蒙 SDK）

核心逻辑刻意与系统 API 完全解耦，因此可以当 TypeScript 编译并用 Node 跑数值自检：

```bash
cd harmony/Tools
npm install          # typescript + @types/node
node verify-core.js  # 159 项断言，期望值与 Android 单测、iOS Scripts/main.swift 一致
node parse-ets.js    # 用 TypeScript 解析器检查 core/services/Ability 的语法（21 个文件）
python check-ets.py  # 23 个 ArkTS 文件的导入导出一致性、括号平衡、禁用特性
```

覆盖范围：均时差与 NOAA 公布值、真太阳时与经度修正的等价性、北京 6/21 与 12/21 的日出日落与年鉴值、
上中天等于真太阳时 12:00、极昼极夜、太阳高度角、十二时辰的边界与刻数、关键时间解析（含跨午夜、
被标签拆开的时间段、温度标记）、时间轴分段、天气 JSON 解析与小时槽位、区划名拼接、报时窗口与
「时辰交接让位给关键时间」规则、城市索引。

ArkUI 声明式界面无法脱离鸿蒙 SDK 编译，`pages/`、`widget/`、`*Ability.ets` 只能靠 DevEco Studio
构建与真机验证。核心逻辑刻意不 import 任何 `@kit.*`，就是为了让上面这套检查能在没有鸿蒙 SDK 的
机器上跑起来。

## 实测编译结果

在本机 **DevEco Studio 26.0.1.290**（HarmonyOS SDK API 26.0.1.120 Beta1、hvigor 6.26.20）上用命令行
`hvigorw assembleHap` 试过：

```
> hvigor BUILD SUCCESSFUL in 13 s 965 ms
33 tasks in total: 18 executed, 15 up-to-date
```

- **0 error、0 warning**（首次编译的 46 个 error + 65 个 warning 已全部修掉，主要是偏好设置字段与方法同名、
  `ReminderRequest.wantAgent` 的结构、`GeoAddress` 的可选字段、卡片里 `TextClock` 不支持 `textAlign`
  等；`getContext` / `showToast` 的弃用警告改用 `getUIContext()`）
- 产物 `entry/build/default/outputs/default/entry-default-unsigned.hap`，489 KB
- 包内结构已验证：`ets/widgets.abc`（25 KB，卡片已编译进去）、`resources/base/profile/form_config.json`、
  `resources/rawfile/chime500.wav` 与 `chime250.wav`、`module.json` 里 5 项权限齐全，
  `minAPIVersion = 50000012` —— `compatibleSdkVersion` 仍是 `5.0.0(12)`，用 API 26 SDK 编译但向下兼容 API 12
- **未做**：真机/模拟器运行。本机没有调试证书（签名需登录华为账号，DevEco 里 `Project Structure → Signing Configs`
  勾自动签名即可），模拟器镜像也没下载（`Device Manager` 里下 `HarmonyOS 7.0.1 B1` 镜像后即可启动 `Mate 90 Pro`）

## 页面结构

- **首页**：顶部标题 + 地名 + 「设置」按钮；下面是
  1. 大卡片（与桌面卡片同款版面，逐秒刷新，含时间轴与六格逐时预报）；
  2. 太阳卡：虚线弧 + 地平线 + 柔光圆点标出当前太阳位置（对齐 Android 的 `SunArc`），
     底下是日出/上中天/日落与白昼时长；
  3. 页脚（版本与数据来源）。
- **设置页**（`pages/Settings.ets`）：当前位置与「使用当前位置」、手动坐标、常用城市、
  两项提醒开关、关于。返回首页时由 `Index.onPageShow` 重新读取偏好。

关键时间不再单独占一张卡：它的色带只在两处时间轴（桌面卡片 / 首页大卡片）上呈现，
区间文字与报时开关分别在首页时间轴与设置页。

## 图标

应用图标不再单独设计，直接沿用 Android 版：`Tools/gen-icons.py` 把 `design/icon-512.png`
（与 Android `ic_launcher` 同一张图）复制到 `AppScope/resources/base/media/app_icon.png`
与 `entry/src/main/resources/base/media/app_icon.png`。换图标只需替换 `design/icon-512.png`
后重跑脚本。

## 与 Android 的差异

1. **卡片上的真太阳时是快照，不能逐秒自走**（实测 HarmonyOS 6.0.0 / API 20 模拟器）：

   | 尝试 | 结果 |
   | --- | --- |
   | `TextClock().format('HH:mm:ss')` / `format('ss')` | **被忽略**，始终按系统格式显示到分钟 |
   | `TextClock({ timeZoneOffset: 482 })`（含范围内 420 的对照实验） | **被忽略**，始终是系统本地时间 |
   | 把 `compatibleSdkVersion` 从 `5.0.0(12)` 提到 `6.0.0(20)` 再测 | 仍然忽略，与目标 API 无关 |
   | 解包 `ets/widgets.abc` 查字符串 | `HH:mm:ss` / `timeZoneOffset` / `format` **都在**，是运行时（卡片渲染侧）丢弃，不是编译期裁剪 |
   | 卡片内 `setInterval` / `setTimeout` | 编译期报错 `11706006 can't support form application` |

   **所以桌面卡片只能到分钟级；需要逐秒的真太阳时，看应用首页** —— 首页大卡片是同款版面，
   但跑在页面里，1 秒定时器与任意格式都可用，右栏真太阳时是活的。
   也就是说卡片能力本身的边界，不是实现偷懒。

   也就是说卡片只能显示本机时间，无法把「经度 × 4 + 均时差」的偏移交给它。因此卡片改为：
   左栏「标准时间」用 `TextClock` 自走（分钟精度、跟随系统 12/24 小时制），右栏「真太阳时」用
   快照文本（只有 `HH:mm`，**不再显示秒** —— 卡片上秒走不起来，显示不动的秒只会误导），
   由以下时机刷新：系统定时刷新（`updateDuration: 1`，即 30 分钟）、
   打开应用（`EntryAbility.onForeground` 里推一次）。
   代价：不打开应用时，右栏最多滞后 30 分钟。这是卡片能力本身的边界，不是实现偷懒。
2. **报时用系统代理提醒**：鸿蒙不允许第三方应用自建精确闹钟。这里用 `reminderAgentManager`
   提前发布未来 12 个时辰交接（24 小时）与未来 2 天关键时间起点的提醒，由系统代发通知并响铃 ——
   应用不必常驻，代价是**通知栏会留下一条到点通知**（Android 端是只响铃不通知）。
   应用在前台时改为自己用 `AVPlayer` 播放 `rawfile` 里的 3200 Hz 蜂鸣，与 Android 听感一致。
3. **区划名取数**：Android 用高德 SDK（中文）+ Nominatim（其他语言）。鸿蒙优先用系统逆地理编码
   （`geoLocationManager.getAddressesFromLocation`，中文界面），非中文界面直接走 Nominatim，
   因为系统逆地理的返回语言不由界面语言决定。中文写法是「上级+区县」直接相连（如「上海市黄浦区」），
   其他语言由细到粗用逗号连接（如「Huangpu District, Shanghai」），与 Android 相同。
   缓存策略（5 km / 30 天 / 语言变化重查）与 Android 相同。
4. **没有地图**：鸿蒙地图组件属于 Map Kit，需要在 AGC 创建项目、配置 `client_id` 与签名后才能显示。
   本仓库不预置商业服务凭据，位置信息以「精确坐标 + 最近城市」呈现。
5. **字面差异**：卡片与界面的少量辅助文案目前只有中文（英文界面下仍显示中文提示），
   与 Android 的 `values-en` 相比还有差距，见「待办」。

### 卡片下方那行应用名

桌面上卡片底下会显示一行「真太阳时」。那是**桌面**按应用名画的（节点 id 形如
`AppName_text_<bundleName>_<label>`），不是卡片自身的内容，卡片区域也不受它影响。
实测把 `form_label`（改成测试值）与 `form_display_name`（置空）都无效 —— 它取的是
`AppScope/app.json5` 的 `label`，改它等于给应用改名，因此没有提供隐藏开关。

### 卡片点击分区

与 Android 的 `bindClicks` 一一对应：

| 区域 | 目标 |
| --- | --- |
| 左栏（标准时间） | 时钟 `com.huawei.hmos.clock` / `com.huawei.hmos.clock.MainAbility` |
| 日期那一行 | 日历 `com.huawei.hmos.calendar` / `com.huawei.hmos.calendar.MainAbility` |
| 底部逐时预报 | 天气 `com.huawei.hmos.weather` / `com.huawei.hmos.weather.MainAbility` |
| 右栏（真太阳时）、时间轴、空白 | 本应用 `EntryAbility` |

实现方式是卡片里的 `postCardAction({ action: 'router', bundleName, abilityName })`：卡片/FormExtension
侧拿不到 `startAbility`（`FormExtensionContext` 只有 `connect`），只能由桌面代拉。因此
**目标应用的包名与 ability 名是写死的**，取的是华为系统应用的命名惯例（本机 `com.huawei.hmos.settings`
的入口就是 `com.huawei.hmos.settings.MainAbility`）。设备上没有这些应用时，对应区域点击不会有反应 ——
模拟器镜像里就没装时钟/日历/天气，所以这三块只能在真机上验证。

### 跟随 GPS
点「使用当前位置」后，位置来源记为 `PlaceSource.GPS`，之后不再是一次性快照：

- 应用每次打开（`Index.aboutToAppear`）静默重取一次定位，不再弹权限框；
- 卡片每次刷新（`CardService.refresh`，含系统 30 分钟定时与打开应用触发的推送）在组装数据前
  重新取一次定位，坐标变化才写回偏好并顺带刷新天气、区划名。

这条与 Android 卡片每次 `buildViews` 都调 `LocationTracker.lastKnownLocation()` 的行为一致。
取不到定位（没授权、无信号）时保留上一次的坐标，不会把位置清空。

## 权限

| 权限 | 用途 |
| --- | --- |
| `ohos.permission.INTERNET` | 天气（Open-Meteo）、关键时间页面、Nominatim |
| `ohos.permission.GET_NETWORK_INFO` | 区分「没网」与「取数失败」 |
| `ohos.permission.APPROXIMATELY_LOCATION` / `LOCATION` | 定位求经度、逆地理编码 |
| `ohos.permission.PUBLISH_AGENT_REMINDER` | 发布时辰交接与关键时间的代理提醒 |

不申请后台常驻、不申请精确定时：卡片的标准时间由 `TextClock` 承担，真太阳时随卡片刷新更新，提醒由系统代发。

## 待办

- 界面与卡片的英文文案（`values-en` 风格，与 Android/iOS 对齐）。
- 若要做全景地图，接入 Map Kit（需 AGC 项目）。
- 卡片尺寸 4×4 的专门布局（当前 4×4 复用 2×4 的内容，留白较多）。

## 数据来源

- 天气：Open-Meteo（CC BY 4.0）
- 逆地理（非中文界面）：OpenStreetMap Nominatim（ODbL）
- 关键时间：「西格瑪食療」<https://www.duosuccess.com/tcm/001a01080301b01a.htm> 的「服用時間 Take Time」
