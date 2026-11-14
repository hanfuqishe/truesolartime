# 真太阳时 iOS 版

与 [Android 版](../README.md) 功能对齐的 SwiftUI 实现：真太阳时、十二时辰、太阳位置、位置地图、天气、区划名、关键时间（时间轴 + 报时）、时辰交接提醒。

### 与 Android 版的功能对照

| 功能 | Android | iOS |
| --- | --- | --- |
| 每秒真太阳时 | ✅ | ✅ |
| 首页大卡片（两栏 + UTC 标签 + 区划名） | ✅ | ✅ 1.4.39 同步 |
| 日期 · 天气 · 温度区间（卡片内一行） | ✅ | ✅ 1.4.39 同步 |
| 0–24 时关键时间轴 + 六格逐时 | ✅ | ✅ 1.4.39 同步 |
| 时间字号（秒半高 + 撑满栏宽） | ✅ | ✅ `HeroClockMetrics` 实测字宽反推 |
| 地图视口 | 手机 4:3 / 平板 16:9 | 手机 4:3（无平板版） |
| 区划名（跟随界面语言） | 高德 / OSM 反查 | `CLGeocoder`（系统自带、随系统语言），缓存策略相同（5 km / 30 天 / 语言变化重查） |
| 天气（今日区间 + 未来 5 小时） | Open-Meteo，30 分钟缓存、失败保留旧数据 24 小时、5 分钟重试 | 同接口同策略（1.4.39 同步） |
| 关键时间（服用時間 Take Time） | 抓页面 + 7 天缓存 + 时间轴着色 | 相同（`TakeTimeParsing` 与 Android 解析规则一一对应） |
| 进入关键时间报时 | 500 ms 3200 Hz 蜂鸣 | 本地通知 + `chime500.wav`（同样 3200 Hz / 500 ms） |
| 时辰交接提醒 | 准时 250 ms 蜂鸣 | 本地通知 + `chime250.wav`，准时触发 |
| 屏幕常亮开关 | ✅ | ✅ 1.4.39 同步（`isIdleTimerDisabled`） |
| **时区表（观测地法定时区 + UTC−5 这类标签）** | ✅ | ❌ 仍写死北京时间（UTC+8） |
| 平板两栏布局 | ✅ | ❌ iPhone-only |
| 桌面小组件 | ✅ 5×2 可缩放 | ❌ 见文末说明 |
| 地图底图切换 | 高德/OSM/卫星 | MapKit + 同样的瓦片 |

> iOS 的提醒走系统通知（用户需允许通知），不能像 Android 那样在锁屏下自播蜂鸣。
> **桌面小组件需要 WidgetKit 扩展**：要在 Xcode 里新增 extension target，并共享数据（App Group 需要付费开发者账号），因此单独安排，尚未实现。

## 环境要求

- macOS + **Xcode 15 或更新**（本目录只能在 macOS 上编译，Windows/Linux 无法构建 iOS 应用）
- 可选：`brew install xcodegen`（用于从 `project.yml` 生成工程）

### 没有 Mac，只有 Windows + iPhone，怎么装

**硬约束**：iOS 应用只能用 macOS 上的 Xcode 编译（iOS SDK 只随 Xcode 提供，Apple 许可也要求 Xcode 跑在 Apple 硬件上）。所以「Windows 直接编译 iOS」和「Windows 直接 Xcode 调试」都不成立，但**开发、出包、装到自己的 iPhone 这三件事在 Windows 上都能完成**，只是换条路：

| 路线 | 成本 | 有效期 | 适合 |
| --- | --- | --- | --- |
| **A. GitHub Actions 出未签名 ipa + Sideloadly/AltStore 自签** | 0 元（消耗少量 Actions 分钟） | 免费 Apple ID：**7 天**，到期重签；付费账号：1 年 | 自己用、快速试 |
| **B. 租云端 Mac（MacinCloud / MacStadium / AWS EC2 Mac）** | 约 \$0.5–1/小时或 \$25/月起 | 取决于账号 | 要完整 Xcode 体验、真机 Debug |
| **C. 付费开发者账号 \$99/年 + 云 Mac 或 CI** | ≈¥700/年 | TestFlight 内测 90 天，或直接上架 | 给别人用、长期 |

#### 路线 A 的具体步骤（本仓库已配好 workflow）

1. GitHub → **Actions** → 左侧「**iOS 未签名包**」→ **Run workflow**（只在手动触发时跑，平时不消耗 macOS 分钟）；
2. 跑完进入该次 run，下载 artifact **`TrueSolarTime-unsigned-ipa`**（里面的 `TrueSolarTime-unsigned.ipa`）；
3. Windows 上装 **iTunes**（要它带的 Apple 移动设备驱动）+ **Sideloadly**（或 AltStore）；
4. iPhone 用数据线连电脑 → 打开 Sideloadly，把 ipa 拖进去 → 填 **Apple ID**（建议先开双重认证并生成 App 专用密码）→ Start；
5. iPhone 上「设置 → 通用 → VPN 与设备管理」信任你的开发者证书；
6. **7 天后过期**：重跑一次第 2–4 步（用 AltStore 可在 Wi-Fi 下自动续签，但要常驻一个 AltServer）。

> 免费签名的附带限制：同时在装的 App 最多 3 个、Bundle ID 每周上限 10 个；如果以后加了 WidgetKit 小组件扩展，扩展和主 App 会一起被重签，同样 7 天到期。

#### 这个仓库的 iOS 版现状

- 已有：真太阳时、十二时辰、太阳位置、位置地图、时辰交接本地通知（`UNCalendarNotificationTrigger`）。
- **还缺：桌面小组件**。iOS 的小组件是 WidgetKit 扩展，需要在 Xcode 里新建 extension target 并写 `TimelineProvider`（最低刷新间隔受系统预算限制，通常 ≥5 分钟，秒级跳秒要用 iOS 17+ 的 `Text(timerInterval:)`）。这是**代码工作**，跟有没有 Mac 无关 —— 没有 Mac 也一样能写，只是编译验证要靠路线 A/B。

### 在虚拟机里开发

- Apple 的许可条款要求 macOS 跑在 Apple 硬件上；个人自用场景下，虚拟机需开启虚拟化支持（VMware/VirtualBox 要装 Guest Additions / 开启 3D 加速），否则 Xcode 会明显卡顿。
- 先用 **Simulator** 验证功能，再考虑装到真机。

## 生成工程并运行

### 方式一：XcodeGen（推荐）

```bash
cd ios
xcodegen generate          # 由 project.yml 生成 TrueSolarTime.xcodeproj
open TrueSolarTime.xcodeproj
```

装好 Xcode 之后也可以用脚本一键构建：

```bash
bash ios/Scripts/build.sh                                   # 模拟器
bash ios/Scripts/build.sh "platform=iOS Simulator,name=iPhone 16"
```

### 方式二：手动建工程

1. Xcode → File → New → Project → iOS App
2. Product Name 填 `TrueSolarTime`，Interface 选 **SwiftUI**，Language 选 **Swift**
3. 删除模板生成的 `ContentView.swift` 与 `xxxApp.swift`
4. 把 `TrueSolarTime/` 下所有 `.swift` 与 `Assets.xcassets` 拖入工程（勾选 Copy items if needed）
5. 在 Signing & Capabilities 里选择你的 Team
6. 在 Info 里加入键 `NSLocationWhenInUseUsageDescription`，值：
   `用于获取你所在位置的经纬度，以计算当地真太阳时`

### 装到 iPhone

- 免费 Apple ID 也能装，但证书 **7 天过期**，到期需重新用 Xcode 安装（重新选择设备 Run 一次即可）。
- 首次运行需在 iPhone 上「设置 → 通用 → VPN与设备管理」里信任开发者证书。

## 不打开 Xcode 也能验证算法

`Core/` 目录是纯 Foundation 代码，可直接用 `swiftc` 编译运行同一个数值自检（与 Android 版单元测试同源）：

```bash
bash ios/Scripts/verify.sh
```

预期末行为「全部 71 项检查通过」。已在 macOS 15 + Swift 5.10（Command Line Tools）上实测通过，覆盖均时差对照值、北京日出日落、极昼极夜、时辰边界、GCJ-02 偏移与往返精度、成都与北京的正午换算；新增覆盖天气 JSON 解析与小时槽位、关键时间页面解析与跨午夜区间、区划名中英拼法、真太阳时 → 系统时刻的换算。

### 非 UI 层类型检查

`Core/`、`AppSettings`、`WeatherStore`、`KeyTimeStore`、`KeyTimeReminder`、`DistrictStore`、`LocationProvider`、`AppModel` 只依赖 Foundation / Combine / CoreLocation / UserNotifications，装了 Command Line Tools 即可做类型检查（无需 Xcode）：

```bash
cd ios/TrueSolarTime
swiftc -typecheck Core/*.swift AppSettings.swift Services/*.swift \
    LocationProvider.swift AppModel.swift
```

纯 Foundation 的部分（`Core/` + `AppSettings.swift`）在 Windows 的 Swift 工具链上也能直接 `-typecheck`；`Services/` 与 `AppModel` 依赖 CoreLocation/UserNotifications，只能在 macOS 上检查。

注意：macOS 上 `CLAuthorizationStatus.authorizedWhenInUse` 被标记为不可用，这条命令在 macOS 会报一处假错，在 iOS 目标下正常。

### 构建 App 需要 Xcode

SwiftUI / MapKit / UIKit 层必须用 **iOS SDK** 编译，只有安装 Xcode 后才能在模拟器或真机上运行 —— Command Line Tools 不含 iOS SDK。

## 已验证

在 macOS 15.0.1（VMware 虚机）+ **Xcode 16.2** + **iOS 18.3 模拟器**上实测：
- `bash ios/Scripts/build.sh "platform=iOS Simulator,name=iPhone 16"` → **BUILD SUCCEEDED**，17 个 Swift 文件全部编译通过
- App 成功安装并启动，界面完整渲染：主卡片、北京时间对照、太阳弧线、地图卡片
- 系统定位授权弹窗正确显示中文说明（来自 `NSLocationWhenInUseUsageDescription`）
- 自适应图标在桌面正常显示
- 数值与 Android 端一致：上海 正午 11:37、真太阳时比北京时间快 22 分 16 秒

**向 Android 看齐这一版（天气 / 区划名 / 关键时间 / 报时）的验证**：
- 纯逻辑自检：`bash ios/Scripts/verify.sh` → **全部 71 项通过**（含天气解析、关键时间页面解析、区划名拼法、真太阳时 → 系统时刻换算）；
- 完整编译：GitHub Actions「iOS 未签名包」[run #43160384757](https://github.com/hanfuqishe/truesolartime/actions/runs/43160384757) → **全部步骤成功**，并在 macOS runner 上用 Xcode 构建出 `TrueSolarTime-unsigned.ipa`（约 900 KB）。这条流水线同时也是「没有 Mac」时的编译验证手段。

### 虚机渲染注意

若 macOS 跑在没有 GPU 加速的虚拟机里（如 VMware SVGA，`Metal` 不可用），模拟器会退回软件渲染，**`LinearGradient` 的颜色会出现通道串色（橙色偏土黄）**，而纯色与透明度合成仍然精确。这是虚拟显卡的限制，真机与有 GPU 的 Mac 上不会出现。


## 与 Android 实现的差异

| 方面 | Android | iOS |
| --- | --- | --- |
| 定位 | `LocationManager` 每分钟采样 | `CLLocationManager.requestLocation()` 每分钟采样（避免后台持续定位耗电） |
| 地图 | osmdroid + 高德/OSM 瓦片 | MapKit + `MKTileOverlay` 加载同样的瓦片 |
| 时辰提醒 | `AlarmManager` 精确闹钟 | `UNCalendarNotificationTrigger`，每次滚动排 5 天（系统上限 64 条） |
| 坐标 | 数据层 WGS-84，仅绘图时转 GCJ-02 | 相同 |

两者共享同一套公式与常量，`Scripts/main.swift` 中的期望值可直接交叉核对。

## 结构

```
ios/
├── project.yml                     XcodeGen 工程定义
├── Scripts/
│   ├── main.swift                  数值自检（无需 Xcode）
│   └── verify.sh                   编译并运行自检
└── TrueSolarTime/
    ├── TrueSolarTimeApp.swift      入口
    ├── AppModel.swift              时钟、定位状态、位置与提醒
    ├── AppSettings.swift           UserDefaults 封装
    ├── LocationProvider.swift      CoreLocation 每分钟采样
    ├── Services/
    │   ├── WeatherStore.swift      Open-Meteo 天气与 30 分钟缓存
    │   ├── KeyTimeStore.swift      关键时间抓取与 7 天缓存
    │   ├── DistrictStore.swift     CLGeocoder 区划反查与缓存
    │   └── KeyTimeReminder.swift   关键时间报时 + 时辰交接提醒（本地通知）
    ├── Resources/
    │   ├── chime500.wav            3200 Hz / 500 ms（进入关键时间）
    │   └── chime250.wav            3200 Hz / 250 ms（时辰交接）
    ├── Core/                       纯 Foundation，可脱离 UI 单测
    │   ├── SolarTimeMath.swift     均时差、赤纬、真太阳时、日出日落、高度角
    │   ├── Shichen.swift           十二时辰
    │   ├── SolarSnapshot.swift     供 UI 消费的聚合快照
    │   ├── TimeFormat.swift        时间／时长格式化
    │   ├── Weather.swift           天气模型、Open-Meteo 解析、小时槽位
    │   ├── KeyTime.swift           关键时间模型、页面解析、区间判定
    │   ├── DistrictName.swift      区划名拼接、距离与缓存判定
    │   ├── Place.swift             位置模型与常用城市
    │   └── MapStyle.swift          WGS-84 ↔ GCJ-02、底图选择
    ├── UI/                         SwiftUI 界面
    └── Assets.xcassets             图标与强调色
```
