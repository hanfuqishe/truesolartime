# 真太阳时

一个显示**真太阳时**（真太阳时 / 视太阳时）的 Android 应用。

真太阳时的定义很简单：**太阳经过观测者所在子午线（正南或正北）的那一刻，记为 12:00**。它与钟表时间（北京时间）的差异来自两项修正：

- **经度修正**：取决于观测者所在经度，与东经 120° 每差 1° 即为 4 分钟。这是主要项，在中国境内可达 ±2 小时（乌鲁木齐约 −129 分钟）。
- **均时差**：取决于太阳的视位置（地球轨道偏心率与黄赤交角），全年在 −14 ~ +16 分钟之间。

所以「你在哪」决定了大头，「太阳在哪」只带来十几分钟的微调，两者合起来才是真太阳时。

## 功能

- **实时真太阳时**：每秒刷新的大字时钟，按当地经度与均时差校正。
- **北京时间对照**：同时显示北京时间，并拆解出「经度修正」与「均时差」两部分。
- **十二时辰**：按真太阳时划分（子时自 23:00 起，每两小时一个时辰），显示时初／时正、刻数以及距下个时辰的倒计时。
- **太阳位置**：日出、正午、日落按**北京时间**显示（与手机时钟一致），并附真太阳时对照；同时给出太阳高度角与日出到日落的位置弧线，极昼／极夜会单独提示。
- **定位方式**：默认持续跟随 GPS，每分钟采样一次；也可手动输入经纬度、从常用城市快速选择。位置会被记住。
- **位置地图**：内嵌地图，标注当前坐标，支持缩放拖动。境内自动使用高德底图（中文地名、路网更细），境外自动使用 OpenStreetMap；三种底图均无需 API Key。
- **时辰交接提醒**：可开启通知，在进入下一个时辰前 5 分钟提醒（开机后自动重新排程）。
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

需要 JDK 17+ 与 Android SDK（compileSdk 35、build-tools 35.0.0）。

```bash
./gradlew assembleDebug        # 产出 app/build/outputs/apk/debug/app-debug.apk
./gradlew testDebugUnitTest    # 太阳时／时辰计算单元测试
./gradlew lintDebug
./gradlew assembleRelease      # 产出签名发行版 app/build/outputs/apk/release/app-release.apk
```

发行版签名读取仓库根目录的 `keystore.properties`（**不入库**），格式：

```properties
storeFile=release.jks
storePassword=***
keyAlias=solartime
keyPassword=***
```

缺少该文件时 `assembleRelease` 会产出未签名 APK。

## 项目结构

```
app/src/main/java/com/realsuntime/solartime/
├── MainActivity.kt              入口
├── MainViewModel.kt             每秒时钟、定位状态、位置与提醒设置
├── solar/                       纯 Kotlin 天文与时辰计算（可单测）
│   ├── SolarTimeMath.kt         均时差、赤纬、真太阳时、日出日落、高度角
│   ├── Shichen.kt               十二时辰划分与交接时刻
│   ├── SolarSnapshot.kt         供 UI 消费的聚合快照
│   └── TimeFormat.kt            时间／时长格式化
├── data/                        位置模型、SharedPreferences、LocationManager 封装、地图配置
├── notify/                      时辰交接提醒（AlarmManager + 通知）
└── ui/                          Compose 界面、地图卡片与主题
```

## 图标

自适应图标为「太阳 + 倾斜椭圆轨道 + 12 个时间刻度」，矢量绘制于 `res/drawable/ic_launcher_foreground.xml`。

## 权限

| 权限 | 用途 |
| --- | --- |
| `ACCESS_COARSE_LOCATION` / `ACCESS_FINE_LOCATION` | GPS 自动定位（可选，拒绝后仍可手动输入） |
| `POST_NOTIFICATIONS` | 时辰交接提醒（Android 13+） |
| `SCHEDULE_EXACT_ALARM` | 让提醒准时触发（未授权时退化为可延迟闹钟） |
| `RECEIVE_BOOT_COMPLETED` | 重启后重新排程提醒 |
| `INTERNET` / `ACCESS_NETWORK_STATE` | 加载 OpenStreetMap 地图瓦片 |

## 第三方资源

地图瓦片来自 OpenStreetMap（© OpenStreetMap contributors，ODbL 协议），由 [osmdroid](https://github.com/osmdroid/osmdroid) 渲染。
