# 真太阳时 iOS 版

与 [Android 版](../README.md) 功能一致的 SwiftUI 实现：真太阳时、十二时辰、太阳位置、位置地图、时辰交接提醒。

## 环境要求

- macOS + **Xcode 15 或更新**（本目录只能在 macOS 上编译，Windows/Linux 无法构建 iOS 应用）
- 可选：`brew install xcodegen`（用于从 `project.yml` 生成工程）

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

预期末行为「全部 37 项检查通过」。已在 macOS 15 + Swift 5.10（Command Line Tools）上实测通过，覆盖均时差对照值、北京日出日落、极昼极夜、时辰边界、GCJ-02 偏移与往返精度、成都与北京的正午换算。

### 非 UI 层类型检查

`Core/`、`AppSettings`、`LocationProvider`、`ShichenReminder`、`AppModel` 只依赖 Foundation / Combine / CoreLocation / UserNotifications，装了 Command Line Tools 即可做类型检查（无需 Xcode）：

```bash
cd ios/TrueSolarTime
swiftc -typecheck Core/*.swift AppSettings.swift LocationProvider.swift ShichenReminder.swift AppModel.swift
```

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
    ├── ShichenReminder.swift       时辰交接通知
    ├── Core/                       纯 Foundation，可脱离 UI 单测
    │   ├── SolarTimeMath.swift     均时差、赤纬、真太阳时、日出日落、高度角
    │   ├── Shichen.swift           十二时辰
    │   ├── SolarSnapshot.swift     供 UI 消费的聚合快照
    │   ├── TimeFormat.swift        时间／时长格式化
    │   ├── Place.swift             位置模型与常用城市
    │   └── MapStyle.swift          WGS-84 ↔ GCJ-02、底图选择
    ├── UI/                         SwiftUI 界面
    └── Assets.xcassets             图标与强调色
```
