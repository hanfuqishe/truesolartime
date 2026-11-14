# Android 版待办：同步鸿蒙版的三个修复 —— **已完成**

> 背景：鸿蒙版（`../harmony`）已修复「太阳卡片用北京时间」「标准时间用北京时间」「夜间不切主题」三个问题。
> Android 版同步完成，并保留了从外部网址获取「关键时间」的功能（Android 不上架，可以发版）。
>
> 本文件保留为改动记录，可随时删除。

---

## 一、三处修复（均已完成）

### ① 太阳卡片（日出 / 上中天 / 日落）改用当地标准时 ✅

| 现在 | 结果 |
|---|---|
| `solar/SolarSnapshot.kt` 的 `localOffsetSeconds` / `sunriseLocal` / `sunsetLocal` / `solarNoonLocal` | 新增，由「UTC 时刻 + 当地时区偏移」换算；北京口径的三个字段保留（`sunriseBeijing` 等），需要「与手机时钟一致」的场合仍可用 |
| `solar/SolarSnapshot.compute(...)` | 增加 `zoneOffsetSeconds` 参数（默认 −1：按坐标兜底，中国境内 +8、境外按经度取整） |
| `ui/MainScreen.kt` 的 `SunCard` | 渲染改用 `*Local` 字段；标题从「太阳位置 · 北京时间」改为「太阳位置 · 当地时间」（三种语言都改了），极昼／极夜提示里的「（北京时间）」改成「（当地时间）」 |

### ② 主界面「标准时间」显示当地标准时 ✅

- 左栏大字 = 当地标准时（`snapshot.localStandardTime`）。
- 标签从「标准时间」改成 `UTC+8` / `UTC-5` 形式：`solar/TimeFormat.kt` 新增 `utcOffsetLabel(offsetSeconds)`，整点省掉分钟、半点／三刻显示 `UTC+5:30` 这样。
- 新增 **`data/ZoneTable.kt`**（国家码 → 标准时区偏移）与 **`data/LocalZone.kt`**（唯一入口）：
  - 中国境内（经度 73–135、纬度 18–54）恒为 +8，不按经度算；
  - 已知国家查表，美国／俄罗斯／加拿大／澳大利亚／巴西／墨西哥／印尼／哈萨克按经度分段；
  - 表里没有的按 `round(经度 / 15)` 取整；不处理夏令时。
- `solar/SolarTimeMath.kt` 新增 `BEIJING_OFFSET_SECONDS`、`isInChinaBbox`、`standardZoneOffsetSeconds`。
- **`data/DistrictResolver.kt`** 的逆地理结果多带一个 `countryCode`（ISO 3166-1 alpha-2）：Nominatim 直接取 `country_code`；高德取 `RegeocodeAddress.countryCode`，只给国家名时按一张小表（中国／美国／俄罗斯等）翻译。缓存 schema 4 → 5，旧缓存自动重查。新增 `cachedCountryCode(context, place)`。
  - **踩到的坑**：国家码是跟着缓存坐标存的，若「跨洲换了地点 + 这次逆地理失败」，缓存里还留着上一个地点的 `cn`，纽约就会被算成 UTC+8。所以只在缓存坐标离当前位置 50 km 内才认这个码（`trustsCountryAt`），更远就退回按经度取整（实测：上海反查留下的 `country=cn` 在纽约确实被丢掉，左栏显示 UTC−5）。
- `MainViewModel` 新增 `zoneOffsetSeconds` 状态（每秒跟着区划缓存重读，换地点当拍更新）。

### ③ 昼夜主题跟随太阳高度角 ✅

- `ui/theme/Theme.kt` 去掉 `isSystemInDarkTheme` 默认值 —— `darkTheme` 参数改成必需，调用方必须显式给，避免忘了传就静默退回跟系统走。
- 实际判定在 `MainScreen`：`TrueSolarTimeTheme(darkTheme = !snapshot.isDay)`，`isDay` = 太阳高度角 > −0.833°。
- 鸿蒙版那个「漏了 `palette = paletteFor(...)` 赋值」的坑在 Compose 里不存在：配色每次重组都由快照现算，没有需要手动刷新的缓存值。实测把地点切到乌鲁木齐（当地高度角 −28.3°）立刻变深色，切回 GPS 立刻变浅色。

---

## 二、明确不改的部分（保持原样）

```
✓  data/TakeTimeRepository.kt     继续抓取 https://www.duosuccess.com/tcm/001a01080301b01a.htm
✓  widget/KeyTimeChime.kt         关键时间提醒保留
✓  widget/KeyTimePalette.kt       关键时间配色保留
```

鸿蒙版用 `KEY_TIME_FEATURE_ENABLED = false` 关闭了该功能；**Android 版没有引入这个开关**。

---

## 三、「容易漏的地方」处理结果

1. **桌面小组件口径** ✅
   - `WidgetUpdater.civilZoneOf(place)` → `civilZoneOf(context, place, now)`，改走 `LocalZone.zoneIdFor()`：中国境内钉 `Asia/Shanghai`；境外优先设备时区，设备时区与观测点标准偏移对不上时退到 `GMT±HH:MM`（`TextClock#setTimeZone` 与 `ZoneId.of` 同时认的写法，小时必须补零）。
   - 卡片左栏标签也改成 `UTC+8` 形式（`widget_label_civil` 的文本由刷新时写入），与首页一致。
   - 日期、逐时预报在小组件里本来就是按观测点时区算的，未改。

2. **首页日期与逐时预报的口径**（原待办没写，顺手统一）
   - `ui/HeroExtras.kt` 原来写死北京时间；现在跟左栏时钟同一口径（`LocalZone.zoneOffset`），人在纽约时日期与整点都是纽约的，不会出现「时钟 12:00、日期却是北京的」这种错位。

3. **敏感文件未入库检查** ✅
   - 根 `.gitignore` 已覆盖 `keystore.properties`、`release.jks`、`*.jks`、`*.keystore`、`amap.properties`、`local.properties`、`dist/`、`harmony/.sign/`；仓库里没有 `android/.gitignore`，靠根文件即可。
   - `harmony/.gitignore` 另覆盖 `sign-release.ps1`（含密钥库路径）。

---

## 四、验证

- `./gradlew testDebugUnitTest`：**15 个测试类 / 119 个用例全绿**。新增／扩充：
  - `data/ZoneTableTest`（中国恒 +8、单时区国家、多时区大国分段、未知国家回退、大小写与空白、adcode 不误判）
  - `data/LocalZoneTest`（`GMT±HH:MM` 写法能被 `ZoneId.of` 解析、偏移夹取）
  - `solar/TimeFormatTest`（`utcOffsetLabel` 整点／半点／三刻）
  - `SolarTimeMathTest`（中国 bbox、标准时区偏移）
  - `SolarSnapshotTest`（境内当地时间 = 北京时间；纽约 −5 时左栏与日出日落按当地时间；默认参数走坐标兜底）
  - `data/DistrictResolverTest`（国家码只在缓存坐标附近才算数、国家码规范化、高德只给国家名时的对照表）
- `./gradlew lintDebug`：通过。
- `./gradlew assembleDebug` 并装到平板（华为 MRR-W29 / Android 12）实测：
  - 上海：左栏 `UTC+8`，太阳卡片「太阳位置 · 当地时间」06:21 / 11:38 / 16:56，白天浅色；
  - 切到乌鲁木齐：**仍是 `UTC+8`**（不是按经度算出的 +6），真太阳时 04:31，高度角 −28.3°，**自动转深色**，日出日落按北京时间口径 09:02 / 13:53 / 18:45；
  - 切到纽约（40.7128N / 74.006W）：左栏 **`UTC−5`**、17:30（北京 06:30 当天），真太阳时 17:49，
    太阳卡片 06:41 / 11:40 / 16:39 全是**当地时间**，日期也变成纽约的 11 月 13 日（不是北京的 14 日），
    逐时预报按纽约整点，高度角 −9.9° → 深色；地图自动切到 OpenStreetMap。
    此时 `shared_prefs/district_cache.xml` 里仍存着 `country=cn`（上海那次的），靠 50 km 距离校验丢掉，
    否则这一屏会是 `UTC+8`；
  - 切回 GPS 跟随：恢复上海、浅色。收尾已把输入法从 LatinIME 切回讯飞、地点恢复为跟随 GPS。
- 待办：桌面小组件的实际添加没有在平板上手工验证（华为启动器的添加流程没法用 adb 点），逻辑与首页共用 `LocalZone`，并有单元测试覆盖。

---

## 六、桌面小组件高度（1.4.36）

平板上一加进来就是 5×2，卡片 395×286dp，内容只有 140dp，上下各留 73dp 空白——看着像「内容缩在一个大橙块里」。

- 先试过「让内容撑满单元格」（内容列 match_parent + 弹簧控件），**被否掉**：屏幕空间还是那么多，只是把空白挪到了中间，反而更浪费。改动已整体回退。
- 第二步试过只改 `targetCellHeight` 2 → 1，**没用**：Pixel 桌面与华为桌面都是按 `minWidth/minHeight` 除以 70dp 算格数（Pixel 实测 `getMinMaxSizes: Rect(350, 116 - 693, 220)`），`targetCellHeight` 只是提示、不参与分配。
- **最终做法：把 `minHeight` 从 110dp 降到 40dp**（`targetCellHeight="1"` 一起留着）。于是 `(40 + 30) / 70 = 1`，两种桌面都给 1 行：
  - 平板一格 = **143dp**：紧凑间距 + 整张卡（时钟 / 日期 / 时间轴 / 逐时行，内容约 140dp）。
  - 手机一格 = **107dp**：常规间距 + 只留两栏时钟与日期，时间轴与逐时行整条收掉（否则日期行会被切掉一半、时间轴露不出来——这是 5×1 在模拟器上第一版的真实表现）。
  - 两行及以上：与原来一致，按折算高度在常规／紧凑之间切。
- 判据在 `WidgetUpdater.buildViews`：`singleRow = effectiveHeight < 145dp`、`large = smallestScreenWidthDp ≥ 600`，两者组合出 `compact` / `showAxis` / `showHourly`（注释里写了每档的理由）。桌面回报的口径与真实值的差距：手机 2 行报 116dp（实际约 223dp）、平板 2 行报 132dp（实际 286dp），一律按 70dp 一格。
- 排查用的日志保留在 `WidgetUpdater`：`options(id) min=.. max=..` 与 `build(id) reported=..x..dp effectiveHeight=.. singleRow=.. large=.. compact=.. axis=.. hourly=..`，换机型时一眼能看出桌面报的是名义尺寸还是实际尺寸。
- **口径修正（重要）**：`HEIGHT_SCALE` 原来是 1.25（早先在另一台机器上量的），实测三组后发现真实系数约 **2.0**：
  | 设备 | 回报 | 实际卡片高 |
  |---|---|---|
  | Pixel 4 模拟器 1 格 | 52dp | 107dp |
  | Pixel 4 模拟器 2 格 | 116dp | 223dp |
  | 华为 MRR-W29 2 格 | 132dp | 266~288dp |
  改 2.0 之后，平板上那张 2 格卡片不再被误判成"165dp 的小卡"而套用紧凑版面（内容缩成一团），改用常规间距、内容从 140dp 长到约 180dp。
- **默认尺寸最后回到 5×2**（`minHeight=110dp`、`targetCellHeight=2`）：把 `minHeight` 降到 40dp 试过一轮，手机确实变成 1 格，但 1 格只有 107dp，逐时天气那排只能砍掉——而 5×2 + 天气本来是对的，所以回退。现在"1 格"那套版面只在**桌面真的只给 1 格**时兜底（用户手动拖矮、或某些桌面按 minHeight 算得小）。
- **手机 / 平板分档放内容**（1.4.36 最终形态）：默认仍是 5×2（`minHeight=110dp`）。桌面上报的尺寸按「一格 70dp」折算、真实高度约为其 2 倍，所以按折算值分档：
  - 高度 ≥ **240dp** → 加一行「日出 / 正午 / 日落」（新增 `widget_sun_row`，时间按观测点标准时）；
  - 高度 ≥ **255dp 且宽度 ≥ 260dp** → 再加**第二排逐时天气**（新增 `widget_hour_row2`，接在第一排后 6 小时）；
  - **但这两项都只对平板生效**（`isLargeScreen`）：真机 P40 Pro 的 5×2 卡片折算 262dp，按高度门槛会被判成"够高"，结果日出日落 + 两排天气全出来、显得太满，用户要求手机上不要。现在手机恒为 6 格逐时、无日出日落行。（早先按「宽度 ≥ 420dp」判断过一轮，实测平板默认宽度也放得下两排，改成以高度为主、宽度只作最小可读性门槛。）
  - 只剩 1 格（被拖矮）→ 只留两栏时钟与日期，时间轴与逐时行让位；
  - 其余情况与原来一致（常规 / 紧凑间距按折算高度切）。
- 踩坑记录：**不能用 PowerShell 的 `Get-Content/Set-Content` 改这些资源文件** —— PS 5.1 默认按 ANSI 读写，会把 UTF-8 的中文注释整块写坏、aapt2 直接报「3 字节的 UTF-8 序列的字节 3 无效」。改资源文件要用 `[System.IO.File]::ReadAllText/WriteAllText` 配 `UTF8Encoding($false)`，或者直接用编辑工具。
- **小组件不再跟系统「字体大小」缩放**（someone 把系统字号调大后整块走样的那个问题）：布局与样式里的 `textSize` 全部由 **sp 改成 dp**（`widget_solar_time*.xml`、`widget_preview.xml`、`styles.xml` 里 12 处），`WidgetUpdater` 里的 `spToPx` 改成 `dpToPx`（`COMPLEX_UNIT_DIP`），常量 `*_SP` 一并改名 `*_DP`。原来的毛病是：字号被放大后逐时行的天气名换行、时钟秒数被 `setMaxWidth` 裁掉。实测 Pixel 4 模拟器 `font_scale` 1.0 / 1.6 / 2.0 三档渲染**逐像素一致**。
  - 注意 `styles.xml` 用的是 `<item name="android:textSize">10sp</item>` 这种**元素写法**，按 `textSize="..."` 属性写法写的正则匹配不到，第一次改漏了——已按 `textSize">` 重跑。
- **时间轴两端与文字对齐**：`WidgetAxis.render` 原来把轴线与色带画在 `[dotRadius, width - dotRadius]`（约内缩 5.7dp，为的是圆点在 0:00／24:00 不出界），看着比上下文字短一截。现在轴线与色带铺满整条位图（`0 .. widthPx`），刻度也按整宽映射；只有圆点在两端时会被位图边缘裁掉一半，与首页 Compose 版（圆点中心夹到 `0..width`）表现一致。实测平板像素：日期行文字 92..1004、轴线 89..1006（差 ≤1dp，是字形边距）。
- **圆点被拉成椭圆**：轴的位图是按**桌面回报的宽度**画的，桌面再用 `fitXY` 横向拉到真实卡片宽度；华为平板回报 304dp 而实际卡片约 396dp，横向拉伸约 1.3 倍，正圆就成了椭圆（截图实测宽高比 1.29）。修法：把圆点（连同径向渐变，用 `Shader.setLocalMatrix` 一起压）预先横向压扁，`WidgetUpdater.dotXCompensation()` 按屏幕档位给系数：
  - **手机 = 1.0（完全不动）**——Pixel 桌面回报的宽度与真实卡片基本一致，圆点本来就是正圆（用户实测确认）；
  - **平板 = 1.30**——拉伸后回到正圆，实测亮核 17×17。
  没做成"按真实宽度算补偿"：桌面上报的尺寸只有名义值，真实卡片宽度拿不到（`OPTION_APPWIDGET_MIN/MAX_WIDTH` 都是名义值）。
- **圆点在真机上变成竖椭圆**（P40 Pro：亮核 20×21，模拟器上是正圆）：轴线 `ImageView` 的高度写在布局里是 `13dp`，由**宿主**按它自己的密度换算成像素，而我们画位图用的是**本进程**的 density——两边不一致时竖直方向就被缩放（这台机器系统显示大小 450dpi、物理 530dpi）。修法：API 31+ 用 `RemoteViews.setViewLayoutHeight(id, heightPx, COMPLEX_UNIT_PX)` 把视图高度钉成位图的像素高度，纵向缩放恒为 1:1；旧版本退回布局里的 dp。修完三台实测：模拟器 18×18、真机 19×18、平板 18×16（平板仍有 1.30 的横向预补偿）。
- **英文界面下主页显示「巳时」、桌面卡片显示「Si hour」**：主页大卡片直接用了 `snapshot.shichenName`，而它是 `Shichen.name()` 拼的**固定中文名**（`NAMES[index] + "时"`）；桌面卡片走的是 `TimeText.shichenName()` → `R.array.shichen_names` + `shichen_name_format`，英文本地化成 `Zi/Chou/…` + `%1$s hour`。修法：主页也改用 `TimeText.shichenName(context, snapshot.shichenIndex)`，两边共用一套本地化。
- **地址长时主页标题被挤成一字一行**：`Header` 里右侧地名是不定宽 `Text`（只有 `maxLines=1`，没有权重），Compose 会先量它、按内容取满整行，左边的标题列（`weight(1f)`）就只剩几个像素，于是「True Solar Time」竖排成 `Tru / e / Sol / ar / …`，副标题也被挤成窄条。修法：标题列 `weight(1.5f)`、地名 `weight(1f)` + `textAlign = End` + 省略号，两者都吃掉剩余空间，齿轮仍在最右、地名靠右。
- **主页有内容、桌面卡片却全是占位符**：两边的「跟随 GPS」判定不一致。App 启动时是 `hasPermission() && place.source != MANUAL` 才开跟踪、才进「等待定位」；而 `WidgetUpdater.resolveLocation()` 早先只判断 `source != MANUAL` 就当成跟随 GPS，于是**没给定位权限**的机器上，App 拿默认坐标照常显示（还有天气），小组件却走 `hasValidFix(followingGps = true, hadFix = false)` → `hasFix=false` → 全是 `--`。修法：`resolveLocation` 也要求 `LocationTracker(context).hasPermission()`，与 App 同一套条件；顺带把「无 fix」时的天气位改成占位符（见下条）。
- **没定位时小组件整块塌成两个时钟**：早先 `bindHourly(show = … && hasFix)` 会把逐时行隐藏、`dateText` 只留日期、城市名也隐藏，于是一张 5×2 的卡片只剩两个时钟 + 一大片空白（用户看到时报「按说天气要显示占位符」）。现在无定位时：真太阳时 `--:--`、经纬度位显示「等待 GPS 定位…」、日期行 `… · --`、逐时格子 `?` + `--`（`bindHourly` 新增 `hasFix` 参数，无定位时把所有格子强制成 `unknown`，免得把兜底城市（内置默认坐标）的天气挂上去）；日出日落行仍然隐藏（没有位置算不出来）。已用「清 App 数据 + 关定位」在模拟器上复现验证。
- **设置里加「添加到桌面」按钮**（1.4.36 后期）：`FilledTonalButton` → `AppWidgetManager.requestPinAppWidget()`。
  - 关键坑一：**桌面添加成功后会直接切到桌面前台**，我们的界面进后台，所以当场等结果（哪怕轮询 12 秒）拿不到，界面上只会显示"失败"。改成「记账 + 回前台结算」：请求前把当前实例数与时间戳写进 `widget_pin` SharedPreferences，`SettingsSheet` 用 `LifecycleEventObserver` 监听 `ON_RESUME`，回来时才比对实例数并落成"已添加 / 没加上"（请求发出 3 秒内不判定，免得用户还在确认框上）。
  - 关键坑二：华为桌面这一屏满了只 toast 一句「当前屏幕已经没有空间」，API 照样返回 true，所以文案不能写死"不支持直接添加"，改成"桌面可能满了，或该桌面不支持应用内添加；腾出一格再试，或长按桌面 → 窗口小工具"。
  - 三语言文案：`section_widget` / `widget_add_action` / `widget_add_desc` / `widget_add_waiting` / `widget_add_done` / `widget_add_manual`。英文串里**不能直接写撇号**（`Couldn't` 会让 aapt2 报错，要写 `Could not` 或转义成 `\'`）。
  - 实测：Pixel 模拟器（Android 14）点按钮 → 系统确认框 → 添加成功，回 App 显示「已添加到桌面。」，实例数 3→4；华为 P40 Pro 能弹同样的确认框，但当前桌面已满 → 正确显示"桌面可能已经满了"的提示。
- **小字全部统一成 11dp + `#CCFFFFFF`**（与左上角 `UTC+8` 一致）：日期行、经纬度、逐时时刻与天气名、日出/正午/日落、城市名与时辰，都跟标签同一把尺子；原来这些分散在 10/11/12dp 与 `#B3`/`#D9`/`#CC` 三种色阶上，同一块卡片里看着参差。日期与经纬度仍保留"按可用宽度一起缩"的兜底（下限 0.85）。
- **日期那行小字偏小（比同标称 11dp 的标签小一圈）**：根因和圆点同一个——**桌面进程用物理密度**（P40 Pro 530dpi → 3.3125），而 App 拿到的是系统「显示大小」覆写后的密度（450dpi → 2.8125）。布局里的 `11dp` 由桌面换算（≈36px），而 `applyClockSizing` 用 `COMPLEX_UNIT_PX` 显式下发日期字号（11 × 2.8125 ≈ 31px），于是同一行字比旁边标签小 ~15%。修法：**小字一律按 `COMPLEX_UNIT_DIP` 下发**，交给桌面用它自己的密度换算，与布局里其它小字同一把尺子。日志：`SolarWidget: smallText date=..dp coord=..dp scale=.. dateW=.. coordW=.. avail=..`。
- 华为桌面给不了 1 格**：平板上的小组件即使 `minHeight=40dp`（`dumpsys` 确认 provider 已更新为 320×40dp），华为仍按 **2 格（288dp）** 投放并上报 132dp，`targetCellHeight=1` 也不生效。也就是说这块 288dp 的卡片是桌面决定的，App 只能选择"把内容填满"或"接受留白"；合成手势（swipe / motionevent / draganddrop）都没法抓住编辑模式下的缩放手柄，只能靠手指拖。Pixel 桌面则按 minHeight 给 1 格。
- 顺带发现：`android.widget.Space` **不在 RemoteViews 白名单里**，用它做弹簧会让宿主抛 `Class not allowed to be inflated android.widget.Space`，小组件直接变「加载失败」。要占位只能用 `TextView` 之类的白名单控件。
- 版本号抬到 1.4.36（versionCode 43），`dist/真太阳时-安卓-1.4.36.apk` 已出；平板与 Pixel 4 模拟器（Android 14）装的是同一个包，两边都实测过（`min=(320dp x 40dp)`）。平板上因为换签名重装过，应用数据与小组件都被清掉，需要重新添加一次小组件。

---

## 五、鸿蒙版对应实现（移植参考，保留原样）

| 鸿蒙 | Android |
|---|---|
| `entry/src/main/ets/core/ZoneTable.ets` | `data/ZoneTable.kt` |
| `core/SolarTimeMath.ets` → `standardZoneOffsetSeconds` / `isInChinaBbox` | `solar/SolarTimeMath.kt` |
| `core/SolarSnapshot.ets` → `localOffsetSeconds` / `*LocalSeconds` | `solar/SolarSnapshot.kt` |
| `core/TimeFormat.ets` → `utcOffsetLabel` | `solar/TimeFormat.kt` |
| `pages/Index.ets` → `standardSecond` / `palette` | `ui/MainScreen.kt` / `MainViewModel.kt` |
| `services/Store.ets` → `CachedDistrict.countryCode` | `data/DistrictResolver.kt` |

时区表口径（两版一致）：

- **中国境内（经度 73–135、纬度 18–54）恒为 UTC+8**，不按经度算
- 其余：已知国家查表；美国、俄罗斯、加拿大、澳大利亚、巴西、墨西哥、印尼、哈萨克按经度分段
- 表里没有的：按 `round(经度 / 15)` 取整，限制 UTC−12…+12
- 不处理夏令时（存的是标准时）

---

## 交付版 1.4.37

- 版本抬到 `versionCode 44 / versionName 1.4.37`；鸿蒙侧 `harmony/AppScope/app.json5`（`1043700 / 1.4.37`）与 `harmony/entry/oh-package.json5`（`1.4.37`）同步改了版本号，但**没有重新打 HAP**（构建里 `SignHap` 目前失败，签名材料在 `harmony/.sign/release/`）。
- 产物：`dist/真太阳时-安卓-1.4.37.apk`（1.98 MB，release 签名，SHA-256 `ac41c07995e6…`；clean assembleRelease 两次构建哈希一致）+ 给测试者的 `dist/真太阳时-1.4.37-测试说明.md`。
- 交付前核对：apt2 dump badging → ersionCode='44' versionName='1.4.37'、minSdk 24 / targetSdk 35；pksigner verify → CN=True Solar Time（与 1.4.35/1.4.36 同证书，可覆盖安装）；真机、平板、模拟器三台装的是同一份哈希。
## 交付版 1.4.38

- 版本抬到 `versionCode 45 / versionName 1.4.38`；鸿蒙侧 `harmony/AppScope/app.json5`（`1043800 / 1.4.38`）同步，两平台版本号仍然一致。
- **平板宽屏两栏**：内容区 ≥ 560dp 时「首页大卡片」与「太阳位置」按 **1:1 并排、等高**（`Row(IntrinsicSize.Max)` + `fillMaxHeight`），并排时把太阳弧线压到 74dp，让行高由橙色大卡片决定、卡片里不留空白。
- **卡片内容按卡宽自适应缩放**：`LocalDensity` 覆盖，卡片逻辑宽度恒等于手机卡的 334dp（夹在 0.8～1.6），所以 640dp 的小平板也不会出现「时钟被截断」（固定 1.35 倍时实测把 `10:46` 截成 `10:4`）。
- **时间字号的硬规则**：秒恒为主字号的 **1/2**，且「时:分:秒」**正好撑满该栏**（`rememberTextMeasurer` 按 100sp 量样本宽度反推，留 3% 余量）。实测手机主字 159px／秒 80px（50.3%）、填充 96%；平板 231/232px + 64px、填充 97%。中途修掉两个坑：`BoxWithConstraints` 是 SubcomposeLayout，外层 `IntrinsicSize.Max` 会向它要固有尺寸直接崩；`toSp()` 二次除密度导致字号被压小。
- **桌面小组件同样按两条规则**：秒与冒号不再是固定的 23dp，而是与主字号一起解 `主字号·R主 + (主字号/2)·(R秒+R冒) + 间隙 = 栏宽`；主字号上限 48 → 56dp（48 时算出来要 52dp 才撑满）。实测桌面截图主字 104px／秒 51px = 49%。为让标准时间那栏的冒号也能缩放，两个布局补齐 `@+id/widget_civil_colon`。
- **地图视口按比例**：手机 **4:3**、平板 **16:9**（`Modifier.aspectRatio`，不再写死 190/340dp）。实测手机 1088×816、平板 1400×788。
- 产物：`dist/真太阳时-安卓-1.4.38.apk`（1.98 MB，sha256 `d9276213c615131de652791edff7fb32e27f78f49caea246b4e690d011f46669`，release 签名 `CN=True Solar Time`）；手机（ELS-AN00）、平板（MRR-W29）均已装载验证。