# App Store 元数据（三语：简体 / 繁體-台灣 / English）

本文件是 **App Store Connect 的可复制文案**：每个字段一段代码块，直接整段复制粘贴，
不要带反引号或 Markdown。三个语言在 App Store Connect 里分别填
「应用信息 → 本地化 → 简体中文 / 繁體中文 / English」。

> 限制（App Store Connect 硬性规定，超了会被拒）：主名称 ≤30、副标题 ≤30、
> 关键词 ≤100（**逗号分隔、逗号后不要空格**）、描述 ≤4000、推广文本 ≤170。
> 每个字段下方括号里是本次文案的实际字符数（按 Unicode 字符数计，中文 1 个汉字算 1）。

| 位置 | 采用 | 填在哪 |
| --- | --- | --- |
| 主名称 | 见下方三语 | App Store Connect → 应用信息 → 名称 |
| 副标题 | 见下方三语 | 版本信息 → 副标题 |
| 关键词 | 见下方三语 | 版本信息 → 关键词 |
| 描述 | 见下方三语 | 版本信息 → 描述 |
| 推广文本 | 见下方三语 | 版本信息 → 推广文本（随时可改，不用重新审核） |
| 图标下显示名称 | 简体「真太阳时时钟」/ 繁體「真太陽時時鐘」/ 英文「True Solar Clock」 | 安装包：`ios/TrueSolarTime/Resources/<lang>.lproj/InfoPlist.strings` 的 `CFBundleDisplayName`；兜底值在 `ios/project.yml` |
| 定位权限说明 | 三语在 `InfoPlist.strings` 的 `NSLocationWhenInUseUsageDescription` | 同上 |

其他固定项：类别 **Utilities**、版权 **© 2026 NowSolar**、
`ITSAppUsesNonExemptEncryption = NO`（只用系统 HTTPS）、支持网址与隐私政策 URL 见文末 TODO。

---

## 简体中文（zh-Hans）

### 主名称（≤30，实际 6）

```
真太阳时时钟
```

### 副标题（≤30，实际 12）

```
实时定位显示当前真太阳时
```

### 关键词（≤100，实际 43）

```
真太阳时,太阳时,真太阳时钟,日出日落,上中天,时辰,十二时辰,天气,定位,占卜,黄历
```

### 描述（≤4000，实际 866）

```
真太阳时时钟：把「太阳走到你头顶」的那一刻算成正午。

【什么是真太阳时】
平常说的「12 点」是所在时区的标准时间，而太阳并不在 12 点整经过你头顶的正南方（北半球）。
真太阳时按太阳的真实位置计时：先按当地经度相对东经 120° 的偏差修正（每差 1° 约 4 分钟），
再叠加因地球轨道偏心率与黄赤交角产生的均时差。所以在成都，真太阳时的正午落在北京时间 12:40 左右；
在乌鲁木齐会差得更多。

【你会看到什么】
· 真太阳时：左栏当地标准时间、右栏真太阳时，秒级刷新，自动跟随系统时区与夏令时。
· 日出 / 上中天 / 日落：按太阳高度角与当地标准时区计算，并给出白昼长度；极昼极夜也会说明。
· 逐时天气：未来几小时的气温与天气图标，数据来自 Open-Meteo（CC BY 4.0）。
· 关键时段：每天同步一次「服用时间」页面上的时段，在 0–24 时轴上用绿色（冻或温）/ 红色（热或温）标出；
  当真正进入某个时段时，真太阳时的数字会跟着变色。
· 十二时辰：以真太阳时划分，子时自 23:00 起，显示时初 / 时正与所属时辰。
· 报时提醒：时辰交接、关键时段起点可各开一个提示音，应用在后台也由系统准点送达。
· 昼夜主题：太阳落山那一刻自动切换到深色界面，不看手机的深色开关。
· 位置：20 个常用城市一键切换，或跟随 GPS，也可手动输入经纬度。

【隐私】
· 位置只在本机用于天文计算，不上传、不保存到任何服务器，也不需要注册账号。
· 只有在需要显示地名时才把经纬度发给 Apple 的逆地理服务，失败时再试 OpenStreetMap；
  查到的地名缓存在本机。
· 无广告、无内购、无第三方统计 SDK、不追踪你。

【关于地名与语言】
界面跟随系统语言：简体中文、繁體中文（台灣）与英文。外国城市的地名会尽量给出区县一级
（例如 Manhattan, New York）；取不到时显示国家名。

如果你只想知道「现在太阳时几点」，打开就能看到；想研究时辰与关键时段，它也在。
```

### 推广文本（≤170，实际 55）

```
太阳走到你头顶的那一刻，才是真正的正午。真太阳时时钟按太阳的真实位置计时：秒级刷新，附带日出日落、时辰与天气。
```

### 审核备注（Review notes，仅提交时填）

```
定位仅用于在本机计算真太阳时与日出日落；坐标只在显示地名时发给 Apple 的地理编码服务
（失败时用 OpenStreetMap），不保存到我们自己的服务器。应用无账号体系。
```

---

## 繁體中文（台灣，zh-Hant）

### 主名稱（≤30，實際 6）

```
真太陽時時鐘
```

### 副標題（≤30，實際 12）

```
即時定位顯示目前真太陽時
```

### 關鍵字（≤100，實際 44）

```
真太陽時,太陽時,真太陽時鐘,日出日落,上中天,時辰,十二時辰,天氣,定位,占卜,農民曆
```

### 描述（≤4000，實際 881）

```
真太陽時時鐘：把「太陽走到你頭頂」的那一刻算成正午。

【什麼是真太陽時】
平常說的「12 點」是所在時區的標準時間，但太陽並不會在 12 點整經過你頭頂的正南方（北半球）。
真太陽時依太陽的實際位置計時：先按當地經度相對東經 120° 的偏差修正（每差 1° 約 4 分鐘），
再疊加因地球軌道偏心率與黃赤交角產生的均時差。所以在台北，真太陽時的正午會落在標準時間 12:00 前後幾分鐘；
愈往西邊的城市差得愈多。

【你會看到什麼】
· 真太陽時：左欄當地標準時間、右欄真太陽時，秒級更新，自動跟隨系統時區與日光節約時間。
· 日出 / 上中天 / 日落：依太陽高度角與當地標準時區計算，並顯示白晝長度；極晝極夜也會說明。
· 逐時天氣：未來幾小時的氣溫與天氣圖示，資料來自 Open-Meteo（CC BY 4.0）。
· 關鍵時段：每天同步一次「服用時間」頁面上的時段，在 0–24 時軸上用綠色（凍或溫）／紅色（熱或溫）標出；
  真正進入某個時段時，真太陽時的數字會跟著變色。
· 十二時辰：依真太陽時劃分，子時自 23:00 起，顯示時初／時正與所屬時辰。
· 報時提醒：時辰交接、關鍵時段起點可各開一個提示音，應用程式在背景也由系統準時送達。
· 晝夜主題：太陽落山那一刻自動切換到深色介面，不看手機的深色模式開關。
· 位置：20 個常用城市一鍵切換，或跟隨 GPS，也可手動輸入經緯度。

【隱私】
· 位置只在本機用於天文計算，不上傳、不儲存到任何伺服器，也不需要註冊帳號。
· 只有在需要顯示地名時才把經緯度傳給 Apple 的逆地理服務，失敗時再試 OpenStreetMap；
  查到的地名快取在本機。
· 無廣告、無 App 內購買、無第三方統計 SDK、不追蹤你。

【關於地名與語言】
介面跟隨系統語言：簡體中文、繁體中文（台灣）與英文。外國城市的地名會盡量給到行政區一級
（例如 Manhattan, New York）；取不到時顯示國名。

如果你只想知道「現在太陽時幾點」，打開就能看到；想研究時辰與關鍵時段，它也在。
```

### 推廣文字（≤170，實際 54）

```
太陽走到你頭頂的那一刻，才是真正的正午。真太陽時時鐘依太陽的實際位置計時：秒級更新，附日出日落、時辰與天氣。
```

### 審核備註（Review notes）

```
定位僅用於在本機計算真太陽時與日出日落；座標只在顯示地名時傳給 Apple 的地理編碼服務
（失敗時用 OpenStreetMap），不會儲存到我們自己的伺服器。應用程式沒有帳號系統。
```

---

## English (en)

### Name (≤30, actual 26)

```
NowSolar: True Solar Clock
```

### Subtitle (≤30, actual 27)

```
Live solar time by location
```

### Keywords (≤100, actual 96)

```
solar time,true solar time,sun clock,sunrise,sunset,solar noon,shichen,chinese hours,weather,GPS
```

### Description (≤4000, actual 2542)

```
NowSolar: True Solar Clock shows the moment the sun actually crosses your meridian — the real noon where you are.

WHAT TRUE SOLAR TIME IS
"12:00" on a clock is the standard time of your time zone, but the sun does not cross due south at 12:00 (north of the equator). True solar time follows the sun's real position: first the clock is corrected for the longitude offset from 120°E (about 4 minutes per degree), then the equation of time is added, which comes from Earth's orbital eccentricity and axial tilt. That is why true solar noon in Chengdu falls around 12:40 Beijing time, and why cities far west of their zone's meridian differ even more.

WHAT YOU GET
· True solar time: local standard time on the left, true solar time on the right, ticking every second and following the system time zone and daylight saving.
· Sunrise, solar noon and sunset, computed from the sun's altitude and your local zone, plus the length of daylight — with a note for midnight sun and polar night.
· Hourly weather for the next hours, with data from Open-Meteo (CC BY 4.0).
· Key time periods: the app syncs a public "take time" page once a day and marks those periods on a 0–24 hour axis in green (cold or mild) or red (hot or mild). While you are inside a period, the true solar time digits change colour too.
· The twelve shichen: derived from true solar time, Zi starting at 23:00, showing early/late half and the current shichen.
· Chime reminders: one sound when the next shichen begins, another at the start of a key time period — delivered on time by the system even when the app is in the background.
· Day and night theme: the interface switches to a dark palette the moment the sun sets, following the sun rather than the system setting.
· Location: 20 preset cities, GPS tracking, or manual coordinates.

PRIVACY
· Your location is used only on the device for astronomical math. Nothing is uploaded, nothing is stored on a server, and there is no account.
· Coordinates are sent to Apple's reverse geocoding service only when a place name is needed; if that fails, OpenStreetMap is tried. Results are cached on the device.
· No ads, no in-app purchases, no third-party analytics SDK, no tracking.

LANGUAGES
The interface follows your system language: Simplified Chinese, Traditional Chinese (Taiwan) and English. District-level place names are shown when available (for example Manhattan, New York); otherwise the country is shown.

Open it when you just want to know what the sun says the time is — or dig into shichen and key time periods.
```

### Promotional text (≤170, actual 164)

```
True noon is the moment the sun crosses your meridian, not 12:00 on the wall clock. NowSolar ticks with the real sun, and adds sunrise, sunset, shichen and weather.
```

### Review notes

```
Location is used only on-device to compute true solar time and sunrise/sunset. Coordinates are sent to Apple's geocoding service only to display a place name (OpenStreetMap is tried if that fails) and are never stored on our servers. The app has no accounts.
```

---

## 字符数总表

| 字段 | 简体（zh-Hans） | 繁體（zh-Hant） | English | 上限 |
| --- | --- | --- | --- | --- |
| 主名称 | 真太阳时时钟（6） | 真太陽時時鐘（6） | NowSolar: True Solar Clock（26） | 30 |
| 副标题 | 实时定位显示当前真太阳时（12） | 即時定位顯示目前真太陽時（12） | Live solar time by location（27） | 30 |
| 关键词 | 43 | 44 | 96 | 100 |
| 描述 | 866 | 881 | 2542 | 4000 |
| 推广文本 | 55 | 54 | 164 | 170 |

> 关键词务必**逗号分隔、逗号后不留空格**；不要重复主名称里已有的词（Apple 会自己组合名称与关键词）。

## 台灣用語自查（繁体这一份特意这么写，不是无脑简繁转换）

| 繁體（台灣）用詞 | 大陸簡體寫法 | 出現位置 |
| --- | --- | --- |
| 設定 | 设置 | 應用程式內「設定」頁（strings: `common.settings`）、本文件 |
| 網路 | 网络 | 錯誤提示（`diag.networkError`） |
| 伺服器 | 服务器 | 連線失敗提示（`diag.cannotConnect`） |
| 預設 | 默认 | 常用城市說明（`city.*` 一組 key 的上下文） |
| 支援 | 支持 | 商店頁／文案 |
| 使用者 | 用户 | 隱私說明 |
| 螢幕 | 屏幕 | 螢幕恆亮（`settings.keepScreenOn`） |
| 連線 | 连接 | 裝置未連線（`diag.offline`） |
| 資料 | 数据 | 地圖資料（`map.attributionOsm`）、Open-Meteo 資料 |
| 座標 | 坐标 | 套用座標（`settings.applyCoordinates`） |
| 檔案 | 文件 | 文案中的「檔案」 |
| 快取 | 缓存 | 地名快取 |
| 農民曆 | 黄历 | 關鍵字 |
| 日光節約時間 | 夏令时 | 描述（繁中） |

## 上架时还要准备（与本表无关）

- 隐私政策 URL：仓库 `docs/privacy.html`（可用 GitHub Pages 托管）——`TODO(owner)` 填真实地址
- 支持网址：`TODO(owner)`
- 截图：6.9"/6.7" 竖屏各 3 张起（用真机或模拟器出图），三种语言各一套（至少英文一套 + 中文一套）
- 中国大陆区上架需要工信部 **App 备案号**；没有的话只能上架非中国区
- 版本号由 CI 统一 bump（本文件不含版本号）
