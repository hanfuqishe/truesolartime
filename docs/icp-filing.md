# ICP 备案清单（App 在中国大陆上架的前提）

> 背景：App Store 中国区要求提供 **ICP 备案号**。没有备案号，App 在 App Store Connect 里无法勾选「中国大陆」，
> 国内用户在商店能搜到页面，但点下载会提示「此应用已经不再提供」。
>
> 现状：我们已把「中国大陆」从销售范围里排除，其它地区正常上架。
> 本文件是拿到备案号的完整路径。

---

## 0. 先明确三件事

| 事项 | 说明 |
|---|---|
| **备案主体** | 个人或企业。个人可办，需身份证 + 人脸核验；企业需营业执照（审核稍快，可备案类型更多） |
| **必须有一台大陆服务器** | 阿里云 / 腾讯云 / 华为云的**中国大陆**节点，香港/海外节点不能备案 |
| **必须先有「网站备案」** | App 备案依赖网站备案，两步不能颠倒 |

---

## 1. 材料清单

### 个人主体

| 材料 | 要求 |
|---|---|
| 身份证 | 正反面清晰照片 |
| 手机号 | 本人实名，用于接收验证码 |
| 域名 | 已实名认证（域名注册商处完成） |
| 大陆服务器 | 购买凭证 + IP |
| 真实性核验 | 按云厂商要求拍照/人脸（部分省份需幕布拍照） |
| App 信息 | 名称、包名、平台、隐私政策链接 |

### 企业主体（如有）

营业执照、法人身份证、网站负责人身份证、授权书（非法人办理时）。

---

## 2. 流程（顺序不能变）

```
① 买域名（已实名的 .com / .cn 均可）
        ↓
② 买大陆服务器（最便宜的轻量应用服务器即可，约 100 元/年起）
        ↓
③ 在云厂商备案系统提交「网站备案」
    · 填主体信息、域名、服务器信息
    · 上传身份证、做真实性核验
    · 周期：7~20 个工作日（各省不同）
        ↓
④ 网站备案通过后，提交「App 备案」
    · 同一备案系统里选「App 备案」
    · 填：App 名称 / 包名 / 平台（iOS、Android、HarmonyOS）/ 隐私政策 URL / 功能简介
    · 周期：1~10 个工作日
        ↓
⑤ 拿到 App 备案号（形如「京ICP备XXXXXXXX号-2A」）
        ↓
⑥ 回 App Store Connect：价格与销售范围 → 勾选「中国大陆」
   （可能需要在「App 信息 → 中国区」填备案号）
```

---

## 3. 我们这个 App 要填的具体信息

| 字段 | 值 |
|---|---|
| App 名称 | 真太阳时时钟 |
| iOS Bundle ID | `com.realsuntime.solartime` |
| Android 包名 | `com.realsuntime.solartime` |
| HarmonyOS Bundle | `com.realsuntime.solartime` |
| 平台 | iOS / Android / HarmonyOS |
| 隐私政策 URL | `https://hanfuqishe.github.io/truesolartime/privacy.html`（**备案要求站点在境内**，见下） |
| 功能简介 | 显示当地真太阳时、日出日落、十二时辰与逐时天气的时钟工具 |
| 是否涉及新闻/出版/教育/医疗 | 否 |
| 是否涉及用户发布内容 | 否（无账号、无 UGC） |

### ⚠️ 一个关键限制

**GitHub Pages 是境外托管，不能用于备案。** 备案要求「网站」本身也在境内服务器上。

所以需要：

1. 把隐私政策页（`docs/privacy.html`）**部署到那台大陆服务器**上（Nginx / 静态托管即可）；
2. 备案时填这个境内地址；
3. App Store 里可以继续用 GitHub Pages 的地址（不影响），但**备案材料**里要用境内地址。

> 如果嫌麻烦：备案通过后，也可以把 App 里的隐私政策链接换成境内地址，统一一处。

---

## 4. 几个容易踩的坑

| 坑 | 说明 |
|---|---|
| **服务器选成香港节点** | 不能备案，必须大陆 |
| **备案期间关服务器** | 会被驳回，保持运行 |
| **域名未实名** | 先在注册商完成实名，否则备案系统拒收 |
| **网站备案和 App 备案想同时做** | 不行，必须先网站后 App |
| **备案号填错位置** | App Store Connect 里在「App 信息 → 中国区」填写，不是「销售范围」 |
| **备案信息与实际不符** | 网站内容要真实（至少能打开、有基本介绍 + 隐私政策） |
| **备案后长期不更新** | 每年需年检（部分省份），App 信息变更要重新备案 |

---

## 5. 时间与成本估算

| 项 | 时间 | 必须花 | 可选花 |
|---|---|---|---|
| 域名 | 即时 | 30~60 元/年 | — |
| 大陆服务器 / 可备案主机 | 即时 | 100~200 元/年（促销可低至 9.9~40 元首年） | — |
| **网站备案** | **7~20 个工作日** | **0（工信部免费）** | — |
| **App 备案** | **1~10 个工作日** | **0** | — |
| 签名证书 | 即时（AGC 自动签名） | **0** | — |
| 软件著作权登记 | 1~3 个月 | **0（2017 年起官费已停征）** | 代理 300~800 元 / 加急 300~600 元 |
| **合计** | 备案 2~4 周，软著才是长板 | **约 150~260 元/年** | 想快就再加 300~800 元 |

> 一句话：**备案本身不收费**，那“1000 元”上限几乎全是“软著代理/加急”的可选项。自己申请软著、用促销主机，现金成本不到 300 元/年，主要成本是等软著的时间。

---

## 6. 现在的处境与选择

| 选择 | 说明 |
|---|---|
| **A. 只上非中国区**（现状） | 立刻可用；国内用户装不了（除非用 TestFlight） |
| **B. 走备案**（本文件） | 2~4 周后国内可下载 |
| **C. 先用 TestFlight 给国内用户** | 已可用：内部 100 人 / 外部 10000 人（需 Beta 审核），90 天有效 |

**推荐**：A 保持现状（已上架）+ 并行启动 B（备案）+ C 给急需的用户。

---

## 7. 下一步动作（今天就能做）

1. 决定主体（个人 or 企业）
2. 买域名（如果还没有）
3. 买一台大陆轻量服务器
4. 把 `docs/privacy.html` 传上去，确认能公网访问
5. 在云厂商备案系统提交「网站备案」

---

## 8. 鸿蒙（华为应用市场）的额外要求

> 与 App Store 不同，华为这边是**两道独立的门**：工信部 App 备案 + 华为审核材料。缺任何一项都上不了架。

### 8.1 备案必填的「App 特征信息」——我们现在缺签名

华为云备案系统对每个平台单独采集特征信息（来源：[App备案前准备及注意事项](https://support.huaweicloud.com/prepare-icp/icp_02_0049.html)）：

| 字段 | 含义 | 我们的情况 |
|---|---|---|
| 平台 | 安卓 / iOS / **鸿蒙** …可一次备多平台 | 勾「鸿蒙」 |
| 鸿蒙包名 | `bundleName` | `com.realsuntime.solartime` |
| **公钥** | 签名证书里的公钥 | ⚠️ **需要签名证书** |
| **签名 MD5** | 证书的数字指纹 | ⚠️ **需要签名证书** |

**问题**：`assembleHap` 目前产出的是 `entry-default-unsigned.hap`，没有签名 → 上面两项填不出来，且 AppGallery 也不接受未签名包。

**解决**：在 AppGallery Connect 给应用配置签名（「自动签名」最省事，需要登录 AGC 与本地 DevEco 关联）。
配置后证书落在 `~/.ohos/config/`（p12 + cer + p7b），取指纹：

```powershell
# MD5 / SHA 指纹（备案要的「签名 MD5」）
keytool -printcert -file <证书>.cer

# 公钥（base64，备案表单里的「公钥」）
openssl x509 -inform DER -in <证书>.cer -pubkey -noout |
  openssl pkey -pubin -outform DER | openssl base64 -A
```

### 8.2 华为审核还要「软件著作权」

除备案号外，AppGallery 上架**通常要求《计算机软件著作权登记证书》**（或电子版权认证）。
这是独立流程：正常 1~3 个月，加急可缩短。

> **关键路径是软著，不是备案** —— 备案 2~4 周就够，软著可能要几个月。要上架就该最先启动软著。

### 8.3 备案表单里其它字段怎么填

| 字段 | 值 |
|---|---|
| App 名称 | 真太阳时时钟（安装后图标下的名字，需与 HAP 里 `label` 一致） |
| App 图标 | 现有图标，**≤100KB** |
| App 服务内容 | 选「生活服务 / 工具」类，备注写「显示当地真太阳时、日出日落、时辰与逐时天气的时钟工具」 |
| 域名 / IP | 那台大陆备案服务器（隐私政策页部署在上面） |
| 是否提供 SDK 服务 | 否 |
| 是否应用 SDK 服务 | 否（未接入支付/登录/统计类 SDK） |
| 前置审批 | 不涉及 |

### 8.4 上架时备案号填在哪

AppGallery Connect → 我的应用 → 上架 → 应用信息里填 **APP 备案号**（形如「京ICP备XXXXXXXX号-2A」）。
没有它，审核会直接驳回「未备案」。

### 8.5 鸿蒙侧的时间线建议

```
第 0 天   → 启动软著申请（最慢，1~3 个月）
第 0 天   → 买域名 + 大陆轻量服务器；把 docs/privacy.html 部署上去
第 1~20 天→ 网站备案
第 20 天  → App 备案（勾鸿蒙平台，填包名 + 公钥 + MD5）
第 25 天  → 拿到备案号
软著到手 + 备案号到手 → AGC 提审
```

---

## 9. 域名与「可备案主机」的选购要点（阿里云 / 华为云通用）

### 9.1 备案服务码：备案的真正入口

```
阿里云/华为云备案 → 必须先有「备案服务码」
        ↓
服务码只能由「内地地域」的云资源签发（ECS / 轻量应用服务器 / 虚拟主机）
        ↓
只买域名、不买内地主机 → 没有服务码 → 备不了案
```

要点：

| 项 | 要求 |
|---|---|
| 地域 | **必须内地**（香港 / 海外节点一律不行） |
| 剩余时长 | 通常要求 **≥ 3 个月**，否则签不出服务码 |
| 数量 | 1 个服务码对应 1 个网站备案；我们只需要 1 个 |
| 主体 | 下单账号、域名实名、备案主体 **必须一致**（个人就对个人） |

> 2026-11 实测：阿里云「域名下单页」有 **9.9 元加购「AI 建站」**，权益写的是
> 「再送 1 年 .CN + **备案服务码** + 云资源 + 证书 + 解析」——
> 也就是 **约 40 元**就能拿到「域名 + 可备案主机 + 服务码」，比单买轻量（100~200 元/年）更低。
> 下单前只需确认三件事：服务码 ≥1 个、资源时长 ≥3 个月、续费价能接受。

### 9.2 两个容易吃暗亏的地方

**① 首年促销 ≠ 长期成本**

```
9.9 / 30 元 是首年价
        ↓
主机到期不续 → 资源释放 → 备案会被核查、可能注销
        ↓
真正要看的是「第二年续费价」（可能是 200+/年）
```

**②「送 1 年 .CN」有两种含义**

| 说法 | 含义 |
|---|---|
| 「本域名续费 1 年」 | 第二年年费免了，最实惠 |
| 「另送一个新 .cn」 | 多一个域名，需单独实名，且与备案主体保持一致 |

下单前点开细则看清楚是哪一种。

### 9.3 下单清单（照着勾就行）

- [ ] 域名：实名认证完成（1~2 天），与备案主体一致
- [ ] 主机：**内地地域**，剩余时长 ≥3 个月
- [ ] 备案服务码：数量 ≥1（加购套餐里含的话，下单后去控制台领）
- [ ] 解析：把 `solartime.cn`（或所选域名）解析到这台主机
- [ ] 站点：把 `docs/privacy.html` 与 `docs/index.html` 传上去，确认 `http(s)://域名/privacy.html` 能打开
- [ ] 关闭/开启自动续费：自己决定，但**别让它过期**
- [ ] 记住续费价：第二年是否还愿意付

### 9.4 备案时填的域名

备案里填的「网站域名」就是这台主机上跑的那个域名；
**App 备案**里填的「App 关联域名」用同一个即可（隐私政策页也在这个域名下）。

---

## 10. 三端签名证书信息（已实测填写成功 · 2026-11-22）

**这份是备案表单直接可粘的值。** 三个平台一次备案，包名/Bundle ID 完全相同。

### 10.1 汇总

| 平台 | 包名 / Bundle ID | 指纹类型 | 指纹值 |
|---|---|---|---|
| **Android** | `com.realsuntime.solartime` | MD5 | `c277440bcbb87c40ed265d74e079ce12` |
| **鸿蒙** | `com.realsuntime.solartime` | MD5 | `81299D91B2562A4F920D94303E30BDE7` |
| **iOS** | `com.realsuntime.solartime` | **SHA-1** | `F85921F195BBABA4FDAF986B7614EA8D1CBD7814` |

> **指纹类型不一样**：安卓/鸿蒙要 MD5，iOS 要 SHA-1。填错类型会报「格式错误」，
> 但如果**带了冒号**（`81:29:9D:…`）则一定报错 —— 表单要的是 32/40 位**连续十六进制**。

### 10.2 Android

```
包名    com.realsuntime.solartime
MD5     c277440bcbb87c40ed265d74e079ce12
SHA-1   0A7E8B55BB69601A692095FE25B3B26648DF22A0
SHA-256 4399B84C5597B67784F9D664F83FEA5595CEF2CD9C7A31C36AC4AC93085C8954
```

公钥（RSA 2048，hex 为 DER SubjectPublicKeyInfo）：

```
30820122300d06092a864886f70d01010105000382010f003082010a02820101009709d5fe868b9997a6278f61cd2c7b24478027757d3d7d1ecda9ffc0ba5a8a52cebbb9b123964c2fe3bbbd3513f9576cf2b12cb3f5dcd9f46cbad4958bea3afd607abfeff26347240d07fd2da5950bb207a56d7dd6a8d0a473b36d37f5195c8df0b90fa4779117dcfbc8672b9b5416456e0d0ecf449a7f3ffa245827b1296fc5b4f1e0ab03caed835c969b4ed4cb4611817fc96aa9e3247ed8126d0fec4a333f75d4aeb2d372afc8bc4d4c6d6334774d2bf46eb2adac673c43bc5a01e5ff72ddc31a30e4f7293cc573fa38b9c48de1891ba1c2d4fd17cd5c27708d4f5f1cd24e242b18415a2dfadd854635ab52746c455b3c1c6bb79f96ff826b810787136c650203010001
```

公钥（base64，同一把 key 的另一种编码）：

```
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAlwnV/oaLmZemJ49hzSx7JEeAJ3V9PX0ezan/wLpailLOu7mxI5ZML+O7vTUT+Vds8rEss/Xc2fRsutSVi+o6/WB6v+/yY0ckDQf9LaWVC7IHpW191qjQpHOzbTf1GVyN8LkPpHeRF9z7yGcrm1QWRW4NDs9Emn8/+iRYJ7Epb8W08eCrA8rtg1yWm07Uy0YRgX/JaqnjJH7YEm0P7EozP3XUrrLTcq/IvE1MbWM0d00r9G6yraxnPEO8WgHl/3Ldwxow5PcpPMVz+ji5xI3hiRuhwtT9F81cJ3CNT18c0k4kKxhBWi363YVGNatSdGxFWzwca7eflv+Ca4EHhxNsZQIDAQAB
```

证书身份：`CN=True Solar Time, OU=Personal, O=realsuntime, L=Shanghai, ST=Shanghai, C=CN`，
自签名，有效期 2026-11-03 ~ **2054-03-21**（安卓自签名可长期使用，不需要每年换）。

**取法**（两处独立来源，值必须一致，否则说明包与 keystore 不匹配）：

```powershell
# ① 直接读上架 APK 的签名证书（最权威）
apksigner verify --print-certs dist/真太阳时-安卓-x.y.z.apk

# ② 读 keystore（需要 android/keystore.properties 里的密码）
keytool -exportcert -alias solartime -keystore android/release.jks -storepass <密码> -file cert.cer
openssl x509 -inform DER -in cert.cer -noout -fingerprint -md5
openssl x509 -inform DER -in cert.cer -pubkey -noout |
  openssl pkey -pubin -outform DER -out pub.der   # 再对 pub.der 做 base64/hex
```

### 10.3 鸿蒙

```
包名    com.realsuntime.solartime
MD5     81299D91B2562A4F920D94303E30BDE7
```

公钥（**EC 原始点**，130 位 hex，`04` 开头，与 AGC 证书详情页显示的一致）：

```
0453864b0c5ea9ebdf1a721b932a0cb38ae3eacc444dfd3c7ce82c350c3c1b9d1fe6368d46898c707aed5726214bfd675419d96e4f5c88c97ae731bf353cb1a9d6
```

公钥（base64 的 DER SubjectPublicKeyInfo）：

```
MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEU4ZLDF6p698achuTKgyziuPqzERN/Tx86Cw1DDwbnR/mNo1GiYxweu1XJiFL/WdUGdluT1yIyXrnMb81PLGp1g==
```

证书身份：`CN=李实(2082780383715276225),Release`（AGC 里的发布证书「真太阳时」）。

**取法**：用 `tools/harmony-cert-info.ps1`（默认取链尾那张，即应用证书）：

```powershell
# 先看链里有几张（AGC 导出的 .cer 通常是 根 → 中间 → 应用证书）
powershell -File tools\harmony-cert-info.ps1 -CertPath 认证.cer -List

# 再取 MD5 + 公钥
powershell -File tools\harmony-cert-info.ps1 -CertPath 认证.cer
```

> **两个坑**：
> 1. `.cer` 是**证书链**时，`keytool -printcert` 会给**根证书**的指纹（`7D:0C:4B:…`），是错的，
>    必须取链尾那张；
> 2. 脚本必须存成 **UTF-8 with BOM**，否则 PowerShell 5.1 按 GB2312 解码中文注释会直接语法报错。

### 10.4 iOS

```
Bundle ID  com.realsuntime.solartime
SHA-1      F85921F195BBABA4FDAF986B7614EA8D1CBD7814
```

公钥（RSA 2048，base64 的 DER SubjectPublicKeyInfo）：

```
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAo/WXtRWPdV75+vGiaqcKEga6CPfF8SmWHitJ3WWqI19QE5H6Bm00ed/HvVfrTSztLmMxA4Z2bn4R9O98JSEfvv6xnaVpcwhai/MrJqzYdgdzpZwGH/rD9QGK1puYSO5cOnfq2zCkVs8Be8NCojwrtTBDgBCmASqQYLhp6b7hX7TS1i74hraBZymWuB98OSilofMOuCoKJH/URR0/rxwGnkjH2VOsmfP1lfQ3rPhN8rTcqH3n7ugdbvjE3W31E8WK/iVgjYBlMzY/Z9bbt9gZ/LVhbvhwIOOdKsrArrFEZT2tKbJhTOvo4z2075v1yNRHFshJARYS6eEgxyA/viJQewIDAQAB
```

公钥（hex，与上面同一把 key）：

```
30820122300d06092a864886f70d01010105000382010f003082010a0282010100a3f597b5158f755ef9faf1a26aa70a1206ba08f7c5f129961e2b49dd65aa235f501391fa066d3479dfc7bd57eb4d2ced2e63310386766e7e11f4ef7c25211fbefeb19da56973085a8bf32b26acd8760773a59c061ffac3f5018ad69b9848ee5c3a77eadb30a456cf017bc342a23c2bb530438010a6012a9060b869e9bee15fb4d2d62ef886b681672996b81f7c3928a5a1f30eb82a0a247fd4451d3faf1c069e48c7d953ac99f3f595f437acf84df2b4dca87de7eee81d6ef8c4dd6df513c58afe25608d806533363f67d6dbb7d819fcb5616ef87020e39d2acac0aeb144653dad29b2614cebe8e33db4ef9bf5c8d44716c849011612e9e120c7203fbe22507b0203010001
```

证书身份：`CN=Apple Distribution: shi li (747U98AXHA)`，Team `747U98AXHA`，
有效期 2026-11-22 ~ **2027-11-22**（苹果分发证书一年一换，**到期前要重新备案**）。

**取法**（Windows 上没有苹果证书，从签名包里反解——拿到的一定是上架签名用的那张）：

```powershell
# ① 从 TestFlight / App Store 的分发 ipa 里取描述文件
#    解压 ipa → Payload/TrueSolarTime.app/embedded.mobileprovision
# ② 解开 CMS 签名包
openssl smime -inform DER -verify -noverify -in embedded.mobileprovision -out prov.plist
# ③ 取 DeveloperCertificates（plist 里的 base64 数组）→ DER → 证书
# ④ 算指纹与公钥
openssl x509 -in dev.pem -noout -fingerprint -sha1
openssl x509 -in dev.pem -pubkey -noout | openssl pkey -pubin -outform DER -out pub.der
```

> 描述文件里另有 3 张**苹果自己的**证书（Profile Signing CA / Root CA 等），
> 它们的指纹不是我们要的 —— 要的是 plist 里 `DeveloperCertificates` 那一条。

### 10.5 「App 全部后台服务域名」填不进去的 .org

备案系统会按**工信部支持的后缀**校验，`.org` 直接报「不支持备案」。我们实际访问的三个 `.org` 都填不进去：

| 域名 | 用途 | 处理 |
|---|---|---|
| `tile.openstreetmap.org` | OSM 瓦片兜底 | 删掉不填 |
| `nominatim.openstreetmap.org` | 境外地名反查 | 删掉不填 |
| `www.openstreetmap.org` | 署名链接（不请求数据）| 删掉不填 |

**能填的清单**（这套提交成功）：

```
api.open-meteo.com          天气主源
7timer.info                 天气备用
is.autonavi.com             高德瓦片（境内）
server.arcgisonline.com     Esri 底图（境外）
duosuccess.com              关键时间数据
amap.com                    高德 SDK 自有服务端（覆盖 *.amap.com）
```

不要填 `weatherkit.apple.com` —— 它只是 Apple 天气的**署名链接**，WeatherKit 数据走 Apple 内部通道，不经过该域名。

### 10.6 三端必填字段对照（照抄即可）

| 字段 | Android | 鸿蒙 | iOS |
|---|---|---|---|
| 平台 | 安卓 | 鸿蒙 | iOS |
| 包名 | `com.realsuntime.solartime` | `com.realsuntime.solartime` | `com.realsuntime.solartime` |
| 公钥 | RSA hex（10.2）| EC 原始点 hex（10.3）| RSA hex 或 base64（10.4）|
| 指纹 | **MD5**（32 位无冒号）| **MD5**（32 位无冒号）| **SHA-1**（40 位无冒号）|
| 是否提供 SDK 服务 | 否 | 否 | 否 |

> 鸿蒙版**没有任何第三方 SDK**（`oh-package.json5` 的 `dependencies` 为空），只引用华为系统 Kit；
> 安卓版用了**高德地图 SDK**（`DistrictResolver` 的反地理编码），备案里如需列 SDK 服务商，只有这一项。
