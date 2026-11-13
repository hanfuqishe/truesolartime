# 真太阳时 · 鸿蒙版（HarmonyOS NEXT）

纯血鸿蒙（HarmonyOS NEXT / HarmonyOS 5）实现：ArkTS + ArkUI，不含任何 Android 兼容层，
同时提供**系统代理提醒**。功能以 Android 版 1.4.34 为基准。

> **桌面卡片（Form）这一版暂不开放**：鸿蒙的 ArkTS 卡片做不到「分钟级自走」的非本地时间（`TextClock` 忽略 `format`/`timeZoneOffset`、卡片内禁用定时器、`updateDuration` 最小 30 分钟、互动卡片激活态只有 3500 ms），卡片上的真太阳时只能靠推送刷新、最坏滞后 30 分钟，与其给一个会误导人的数字，不如先关掉入口。**代码全部保留**（`entryformability/`、`widget/`、`CardService`），系统能力补齐后把 `module.json5` 里注释掉的那段 `extensionAbilities` 恢复即可重新开放。相关建议已整理成一封反馈信：见 [建议信](./docs/feedback-card-realtime.md)。

## 功能对照

| 功能 | Android | 鸿蒙 | 说明 |
| --- | --- | --- | --- |
| 每秒刷新的真太阳时大时钟 | ✅ | ✅ | 页面内 1 秒定时器（首页大卡片与桌面卡片同款版面，逐秒生效） |
| 时辰（时初／时正、刻数、范围、倒计时） | ✅ | ✅ | 同一套 `Shichen` 逻辑；首页不显示刻数与下个时辰倒计时 |
| 北京时间对照（经度修正 + 均时差） | ✅ | ✅ | 同一套计算；首页不展示总时差与拆解过程 |
| 日出／上中天／日落、白昼时长、高度角、极昼极夜 | ✅ | ✅ | 同一套 NOAA 公式 |
| 天气（气温 + WMO 天气码） | ✅ | ✅ | Open-Meteo，无需 Key；每 30 分钟取数、显示上保留最近 6 小时；主界面另有未来 6 格逐时预报与今日温度区间；换地点后新地点还没取到数时天气位与逐时格显示占位 `--`，不沿用旧地点的读数 |
| 关键时间时间轴（「服用時間 Take Time」） | ✅ | ✅ | 同一套解析与 7 天缓存、01:00–05:00 随机同步；落到时段内时真太阳时数字改用时段配色（同 Android 的 `activeKeyColor`） |
| 区划名（跟随界面语言，5 km / 30 天缓存） | ✅ | ✅ | 逆地理：系统 `geoLocationManager`，非中文界面走 OSM Nominatim；中文显示到「市+区」 |
| 手动坐标 / 常用城市 / 定位 | ✅ | ✅ | 定位只用 `APPROXIMATELY_LOCATION`（±100 m 足够）；点「实时跟随GPS」后进入跟随 GPS 模式，见下 |
| 时辰交接提醒（250 ms） | ✅ | ✅（系统代理提醒） | 见「与 Android 的差异」 |
| 进入关键时间报时（500 ms） | ✅ | ✅（系统代理提醒） | 同上 |
| 桌面卡片：标准时间／真太阳时两栏、日期与气温区间、经纬度、关键时间轴、六格逐时预报 | ⏸ 暂不开放 | ✅ | 版面、配色都已实现（2×4），但鸿蒙卡片无法让真太阳时自己走（只能 30 分钟一次推送），故关闭入口，代码保留 |
| 内嵌地图（高德／OSM 底图，可在设置里切换矢量／卫星） | ✅ | ✅ | 不用 Map Kit，直接按 Web Mercator 拼栅格瓦片：默认境内高德（GCJ-02，标点前做偏移）、境外 OSM；设置页可选 OSM／高德矢量／高德卫星；见下 |
| 桌面卡片点击分区 | ⏸ 暂不开放 | ✅ | 同上，代码保留：左栏→时钟、日期→日历、逐时行→天气、右栏与空白→本应用 |

## 目录结构

```
harmony/
├── AppScope/                     应用级配置（bundleName、图标）
├── entry/
│   ├── src/main/
│   │   ├── module.json5          入口 Ability、FormExtensionAbility、权限
│   │   ├── ets/
│   │   │   ├── common/           白天／夜间两套主题（Theme.ets）与天气图标映射
│   │   │   ├── core/             纯逻辑（不带系统 API，可用 tsc 编译验证）
│   │   │   │   ├── SolarTimeMath.ets   均时差、赤纬、真太阳时、日出日落、高度角
│   │   │   │   ├── MapTiles.ets        位置地图：GCJ-02 偏移、Web Mercator 瓦片拼接
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
   它会把材料写到 `~/.ohos/config/`，并把签名配置存到本工程的 **`.sign/sign-config.json5`**。
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

签名配置放在 `.sign/sign-config.json5`（**已在 `.gitignore` 里，不入库**：里面是 .p12 路径与口令），
`build-profile.json5` 里只写名字引用它：

```json5
"products": [{ "name": "default", "signingConfig": "default", /* … */ }]
```

hvigor 的 `SignHap` 任务会自己去读这个文件，签出 `entry-default-signed.hap`；
`node Tools/package-hap.js` 会优先取签名产物，输出 `dist/真太阳时-鸿蒙-<版本号>.hap`。
没有 `.sign/` 时 `assembleHap` 仍然能过，只是提示 `Will skip sign`、产物是未签名的
`entry-default-unsigned.hap`（模拟器才接受未签名包）。

### 交给别人做真机测试前要准备什么

1. **必须先签名，且要用对方的设备**：仓库里不含签名材料（`.sign/` 不入库），未配置签名时产物是
   未签名的 `entry-default-unsigned.hap`，真机装不进去。两条可行路线：
   - **调试证书**（推荐给内部测试）：DevEco Studio → `File → Project Structure → Signing Configs`
     → 勾选 *Automatically generate signature*（需登录华为开发者账号）。它生成的调试 profile
     **只对 AGC「调试设备」列表里的 UDID 有效**，所以要让测试者先把设备 UDID 报给你（一个 profile
     最多 100 台/年），加进 AppGallery Connect 的调试设备列表后重新生成 profile 再打包。
   - **邀请测试**：AGC 建应用 → 用发布证书打 release 包上传 → 开「邀请测试」，测试者从应用市场安装，
     不需要 UDID。适合发给不大方便配合抓 UDID 的人。
2. **系统版本**：`compatibleSdkVersion` 是 `5.0.0(12)`，即 **HarmonyOS NEXT 5.0 及以上**。
   HarmonyOS 4.x（Android 内核那一代）和平板/手表等非手机设备装不了。
3. **本机连真机**：手机打开「设置 → 系统和更新 → 开发者选项 → **USB 调试**」，插上数据线后在手机上
   点「允许调试」，电脑上 `hdc list targets` 要能看到设备（只有 `COM*` 说明手机还停在 MTP 模式，
   `hdc` 看不见它，包也装不进去）。确认设备在线后再核对 UDID 是否在调试 profile 里：
   `hdc shell bm get -u`，结果必须出现在 `.sign/sign-config.json5` 指向的 `.p7b` 的
   `debug-info.device-ids` 里，否则安装会报「设备不在 profile 中」。
4. **测试者要在设备上放行的几件事**：
   - **通知**：报时靠系统「代理提醒」，第一次进设置页（或打开报时开关）会弹「允许发送通知」，
     选了「不允许」就到点只响铃、通知栏不显示；之后要到「设置 → 通知」里手动打开。
   - **定位**：点「实时跟随GPS」时授权；若系统「位置」总开关没开，应用会直接提示去控制中心打开。
   - **桌面卡片这一版没有**：入口已关闭（原因见文首说明），长按应用图标只会看到「卸载」。
4. **已知的差异与限制**（不是 bug，别当问题报）：
   - 鸿蒙版**不提供桌面卡片**（Android 版有）。原因不是没做，而是鸿蒙卡片没法让真太阳时自己走，
     只能 30 分钟推送一次，做出来会显示一个滞后的时间。
   - 卡片里点「日期/逐时行」等区域会跳华为系统应用（时钟/日历/天气），非华为机型可能没有对应应用，
     点了没反应属正常（这一条只在恢复卡片入口后才适用）。
   - 境内区划名偶尔会退回「最近的城市名」（Nominatim 在国内不稳），天气用的是 Open-Meteo。

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
node verify-core.js  # 185 项断言，期望值与 Android 单测、iOS Scripts/main.swift 一致
node parse-ets.js    # 用 TypeScript 解析器检查 core/services/Ability 的语法（22 个文件）
python check-ets.py  # 26 个 ArkTS 文件的导入导出一致性、括号平衡、禁用特性
```

覆盖范围：均时差与 NOAA 公布值、真太阳时与经度修正的等价性、北京 6/21 与 12/21 的日出日落与年鉴值、
上中天等于真太阳时 12:00、极昼极夜、太阳高度角、十二时辰的边界与刻数、关键时间解析（含跨午夜、
被标签拆开的时间段、温度标记）、时间轴分段、天气 JSON 解析与小时槽位、区划名拼接、报时窗口与
「时辰交接让位给关键时间」规则、城市索引、地图瓦片（GCJ-02 偏移与边界、瓦片编号与反算、视口覆盖）。

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
- **已做**：模拟器（HarmonyOS 6.0.0 / API 20，`HRM6`）跑通；真机签名链路已打通——
  签名材料在 `~/.ohos/config/`（DevEco 自动签名生成），配置存 `.sign/sign-config.json5`（不入库），
  `build-profile.json5` 的 product 用 `"signingConfig": "default"` 引用，`assembleHap` 直接产出
  `entry-default-signed.hap`（`hap-sign-tool verify-app` 校验通过，profile 为 debug、含 1 个 UDID）
- **未做**：真机实跑。手机插上后若 `hdc list targets` 只有 `COM*`，说明还没开 USB 调试（见
  「交给别人做真机测试前要准备什么」第 3 条）

## 页面结构

- **首页**：顶部标题 + 地名 + 「设置」按钮；下面是
  1. 大卡片（与桌面卡片同款版面，逐秒刷新，含时间轴与六格逐时预报；底色按昼夜切换：白天暖橙 + 白字、夜里深蓝 + 金字；真太阳时白天用淡金 `#FFE6B4`、夜里用金 `#F5D68A`，与安卓一致；落在关键时段里时改成同时段配色——白天数字用淡绿 `#BCF5CA`／淡红 `#FFC4C9`（与淡金同浓度），时间轴色段与圆点仍用深一档的 `#2E7D32`／`#B3261E`，夜里两者同用亮一档的 `#4CAF7D`／`#D9534F`）；
     整个页面也是两套主题（`common/Theme.ets`）：白天米白纸面 + 白卡片 + 深字，夜里 #0B1220 底 + #16203A 卡片 + 浅字；
  2. 太阳卡：虚线弧 + 地平线 + 柔光圆点标出当前太阳位置（对齐 Android 的 `SunArc`；虚线间隔、线宽与圆点半径沿用 Android 的像素值，按屏幕密度换算成 vp，两边看起来同一套虚线），
     底下是日出/上中天/日落与白昼时长；
  3. 位置地图卡：坐标 + 瓦片地图 + 底图来源（对齐 Android 的 `MapCard`，可双指/双击缩放）；
  4. 页脚（版本与数据来源）。
- **设置页**（`pages/Settings.ets`）：当前位置与「实时跟随GPS」按钮、手动坐标、常用城市、地图底图
  （自动／OpenStreetMap／高德矢量／高德卫星，与 Android 同一组选项）、两项提醒开关、屏幕常亮开关、关于。
  返回首页时由 `Index.onPageShow` 重新读取偏好。
  应用只跑竖屏（`module.json5` 里 `EntryAbility` 的 `"orientation": "portrait"`）；「屏幕常亮」默认打开，
  由 `services/KeepAwake.ets` 调 `window.setWindowKeepScreenOn`，只在前台生效（退到后台系统照旧按休眠时间熄屏）。
  「常用城市」和「实时跟随GPS」都是一步到位的选择——**点完立即返回首页**（手动坐标仍停在设置页，
  并提示「已保存，返回首页生效」）。换地点后缓存里的天气属于旧坐标，显示层立刻把它判为无效
  （天气位与逐时格退回 `--`），同时强制取一次新地点的天气，数据一到就显示（
  `WeatherService.revision` / `DistrictService.revision` 让首页不等 30 秒的节流就重算）。

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

   > **卡片里别用 `@Builder` 按值传参渲染会变的数据。** `@Builder labelRow(label, tail)` 的两个
   > 参数在首次构建时就被复制下来，那时卡片刚创建、LocalStorage 还是空的，之后推过来的地名与
   > 时辰不会刷新 —— 表现就是「标准时间」「真太阳时」右侧一直空白（天气、日期、逐时那些直接
   > 写在 `build()` 里、绑 `this.xxx` 的反而正常）。改法：在 `build()` 里直接写
   > `Text(this.city)` / `Text(this.shichen)`，让 `@LocalStorageProp` 的更新能落到这两个 Text 上。
2. **报时用系统代理提醒**：鸿蒙不允许第三方应用自建精确闹钟。这里用 `reminderAgentManager`
   提前发布未来 12 个时辰交接（24 小时）与未来 2 天关键时间起点的提醒，由系统代发通知并响铃 ——
   应用不必常驻，代价是**通知栏会留下一条到点通知**（Android 端是只响铃不通知）。
   应用在前台时改为自己用 `AVPlayer` 播放 `rawfile` 里的 3200 Hz 蜂鸣，与 Android 听感一致。
3. **区划名取数**：Android 用高德 SDK（中文）+ Nominatim（其他语言）。鸿蒙优先用系统逆地理编码
   （`geoLocationManager.getAddressesFromLocation`，中文界面），非中文界面直接走 Nominatim，
   因为系统逆地理的返回语言不由界面语言决定。中文写法是「上级+区县」直接相连（如「上海市黄浦区」），
   其他语言由细到粗用逗号连接（如「Huangpu District, Shanghai」），与 Android 相同。
   缓存策略（5 km / 30 天 / 语言变化重查）与 Android 相同。
4. **地图不用 Map Kit**：鸿蒙的地图组件属于 Map Kit，需要在 AGC 建项目、配置 `client_id` 与签名，
   本仓库不预置商业凭据。首页的「位置地图」改为直接拼栅格瓦片（`core/MapTiles.ets` + ArkUI `Image`）：
   按 Web Mercator 算出视口内的瓦片编号与像素偏移，境内取高德（`webrd0x.is.autonavi.com`，
   GCJ-02，标点前用 `toGcj02` 偏移）、境外取 OpenStreetMap；支持双指缩放与双击放大。
   底图可在设置页里指定（自动／OpenStreetMap／高德矢量／高德卫星），卫星图取
   `webst0x.is.autonavi.com/appmaptile?style=6`，标识存在偏好的 `map_style` 里。
   因为页面本身要上下滚动，地图不做拖动平移，标点始终在视口正中。
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
点「实时跟随GPS」后，位置来源记为 `PlaceSource.GPS`，之后不再是一次性快照：

- **应用打开期间每分钟取一次**（`Index.tick` 里按 60 秒节流，静默取、不弹权限框）；
- **桌面卡片每 5 分钟取一次**（`CardService.syncGpsPlace` 用偏好里的时间戳节流；卡片本身受
  系统 30 分钟定时与前台推送驱动，5 分钟只是上限），坐标变化才写回偏好并顺带刷新天气、区划名。

处于该模式时，首页右上角（设置按钮左侧）显示「GPS」而不是地名，提示坐标是自动跟随的。

这条与 Android 卡片每次 `buildViews` 都调 `LocationTracker.lastKnownLocation()` 的行为一致。
取不到定位（没授权、无信号）时保留上一次的坐标，不会把位置清空。

**定位失败最常见的原因是系统「位置」总开关没打开**：此时 `getCurrentLocation` 返回
`3301100 The location switch is off`，设置页会直接提示「系统「位置」开关未打开：从屏幕顶部
下拉控制中心打开「位置」后重试」。注意它**不在**系统设置里 —— 这批模拟器镜像的设置首页没有
「隐私/位置服务」入口，只能从控制中心那个「位置」磁贴开。开关打开后，模拟器里
`-gps -latitude/-longitude` 注入的坐标与系统逆地理（区划名）都能正常工作。

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
