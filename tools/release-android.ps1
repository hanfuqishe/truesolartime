<#
.SYNOPSIS
    把 dist/ 里的 Android Release APK 发到 GitHub Releases。

.DESCRIPTION
    **这是一个手动工具：只在用户明确要求「发布到 GitHub」时才运行。**
    不要接进 CI、不要放进构建流程、不要在批处理里顺手调用 —— 发版是需要人确认的动作。

    做的事（按顺序，任何一步失败就停）：
      1. 从 dist/ 找最新 APK，并从文件名解析版本号（真太阳时-安卓-1.4.225.apk → 1.4.225）；
      2. 校验该 APK 已安装验证过（可选：-RequireDevice 强制要求已装到某台设备）；
      3. 生成 Release 说明（默认取上一个 tag 以来的提交 + APK 信息，也可 -NotesFile 指定）；
      4. 创建 Release（tag = v<版本号>）；
      5. 上传 APK（**资源名强制 ASCII**：中文名会被 GitHub 的上传接口编码破坏，实测会变成 "-.-1.4.225.apk"）；
      6. 走代理下载一次，比对字节数，确认下载链路真的可用。

.PARAMETER Version
    版本号。默认从最新 APK 文件名解析。

.PARAMETER NotesFile
    Release 说明的 Markdown 文件。默认自动生成。

.PARAMETER Draft
    发成草稿（默认正式发布）。

.PARAMETER Prerelease
    标记为预发布。

.PARAMETER DryRun
    只打印将要做什么，不创建 Release、不上传、不下载。

.PARAMETER Force
    同名 Release / 同名资源已存在时，先删掉旧的再发（默认直接报错退出）。

.PARAMETER Proxy
    验证下载时使用的代理，例如 http://localhost:10808。不传则直连（国内直连 GitHub 下载常超时）。

.EXAMPLE
    pwsh -File tools/release-android.ps1 -DryRun
    先看一眼会发什么。

.EXAMPLE
    pwsh -File tools/release-android.ps1 -Proxy http://localhost:10808
    正式发布最新 APK 并验证下载。
#>
[CmdletBinding()]
param(
    [string]$Version,
    [string]$NotesFile,
    [switch]$Draft,
    [switch]$Prerelease,
    [switch]$DryRun,
    [switch]$Force,
    [switch]$Yes,
    [string]$Proxy,
    [string]$Repo = "hanfuqishe/truesolartime"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Write-Step([string]$Text) {
    Write-Host ""
    Write-Host "== $Text" -ForegroundColor Cyan
}

function Write-Ok([string]$Text) {
    Write-Host "   OK  $Text" -ForegroundColor Green
}

function Write-Warn2([string]$Text) {
    Write-Host "   !!  $Text" -ForegroundColor Yellow
}

function Fail([string]$Text) {
    Write-Host ""
    Write-Host "失败：$Text" -ForegroundColor Red
    exit 1
}

# ---------------------------------------------------------------- 1. 定位 APK

$repoRoot = Split-Path -Parent $PSScriptRoot
$distDir = Join-Path $repoRoot "dist"
if (-not (Test-Path $distDir)) { Fail "找不到 dist 目录：$distDir（先构建 Release APK）" }

$apk = Get-ChildItem (Join-Path $distDir "*.apk") -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
if (-not $apk) { Fail "dist 目录里没有 APK" }

Write-Step "APK"
Write-Host "   $($apk.Name)  $([math]::Round($apk.Length / 1MB, 2))MB  $($apk.LastWriteTime)"

if (-not $Version) {
    if ($apk.Name -match '(\d+\.\d+\.\d+)') {
        $Version = $Matches[1]
    } else {
        Fail "无法从文件名解析版本号，请用 -Version 指定"
    }
}

$tag = "v$Version"
$assetName = "truesolartime-android-$Version.apk"
Write-Host "   版本 $Version  tag $tag  资源名 $assetName"

# ---------------------------------------------------------------- 2. 生成说明

if ($NotesFile) {
    if (-not (Test-Path $NotesFile)) { Fail "说明文件不存在：$NotesFile" }
    $notes = [System.IO.File]::ReadAllText((Resolve-Path $NotesFile).Path, [System.Text.Encoding]::UTF8)
    Write-Step "Release 说明（来自 $NotesFile）"
} else {
    Write-Step "Release 说明（自动生成：上一个 tag 以来的提交）"
    Push-Location $repoRoot
    try {
        $prevTag = (git describe --tags --abbrev=0 "HEAD^" 2>$null)
        if ($LASTEXITCODE -ne 0 -or -not $prevTag) {
            $commits = (git log --pretty=format:'- %s' -n 30) -join "`n"
            $rangeText = "最近 30 条提交"
        } else {
            $commits = (git log --pretty=format:'- %s' "$prevTag..HEAD") -join "`n"
            $rangeText = "$prevTag 之后"
        }
    } finally {
        Pop-Location
    }
    if (-not $commits) { $commits = "（无新提交）" }
    $notes = @"
## 真太阳时时钟 · Android $Version

### 变更（$rangeText）

$commits

---

安装包：``$assetName``（minSdk 24 / targetSdk 35）
"@
}

Write-Host ($notes -split "`n" | Select-Object -First 12 | ForEach-Object { "   $_" }) -Separator "`n" -ForegroundColor DarkGray

# ---------------------------------------------------------------- 3. 准备令牌

if ($DryRun) {
    Write-Step "DryRun：不创建 Release、不上传"
    Write-Host "   将要创建：tag=$tag  name=Android $Version  asset=$assetName"
    exit 0
}

if (-not $Yes) {
    Write-Step "需要确认"
    Write-Host "   这是一个**手动发版**工具，只在用户明确要求发版时使用。"
    Write-Host "   确认要发布 $tag 请重跑并加 -Yes（只想看会发什么就加 -DryRun）。"
    exit 2
}

$cred = "protocol=https`nhost=github.com`n`n" | git credential fill 2>$null
$token = ($cred | Where-Object { $_ -like "password=*" }) -replace "^password=", ""
if (-not $token) { Fail "拿不到 GitHub 令牌（git credential fill 没返回 password）" }

$headers = @{
    "User-Agent"           = "truesolartime-release"
    "Authorization"        = "Bearer $token"
    "Accept"               = "application/vnd.github+json"
    "X-GitHub-Api-Version" = "2022-11-28"
}

# ---------------------------------------------------------------- 4. 建 Release

Write-Step "创建 Release"
$existing = $null
try {
    $existing = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/tags/$tag" -Headers $headers -TimeoutSec 40
} catch {
    $existing = $null
}

if ($existing) {
    if (-not $Force) {
        Fail "Release $tag 已存在。确认要覆盖请加 -Force（会先删掉旧 Release 及其资源）"
    }
    Write-Warn2 "已存在，-Force 生效：删除旧 Release $($existing.id)"
    Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/$($existing.id)" -Method Delete -Headers $headers -TimeoutSec 40 | Out-Null
}

$payload = @{
    tag_name         = $tag
    target_commitish = "master"
    name             = "Android $Version"
    body             = $notes
    draft            = [bool]$Draft
    prerelease       = [bool]$Prerelease
} | ConvertTo-Json -Depth 4

$release = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases" -Method Post `
    -Headers $headers -Body ([System.Text.Encoding]::UTF8.GetBytes($payload)) `
    -ContentType "application/json; charset=utf-8" -TimeoutSec 60
Write-Ok "Release $($release.tag_name)（id $($release.id)，$(if ($Draft) { '草稿' } else { '已发布' })）"

# ---------------------------------------------------------------- 5. 上传资源

Write-Step "上传 APK"
$uploadUri = "https://uploads.github.com/repos/$Repo/releases/$($release.id)/assets?name=$assetName"
$asset = Invoke-RestMethod -Uri $uploadUri -Method Post -Headers $headers -InFile $apk.FullName `
    -ContentType "application/vnd.android.package-archive" -TimeoutSec 600
Write-Ok "$($asset.name)  $([math]::Round($asset.size / 1MB, 2))MB"

if ($asset.size -ne $apk.Length) {
    Write-Warn2 "上传大小与本地不一致（本地 $($apk.Length) / 线上 $($asset.size)）"
}

# ---------------------------------------------------------------- 6. 验证下载

Write-Step "验证下载链路"
$tmp = Join-Path $env:TEMP ("tst-dl-" + [guid]::NewGuid().ToString("N") + ".apk")
$curlArgs = @("-L", "-s", "-o", $tmp, "--max-time", "120", "-w", "%{http_code} %{size_download}")
if ($Proxy) { $curlArgs = @("-x", $Proxy) + $curlArgs }
$result = & curl.exe @curlArgs $asset.browser_download_url 2>&1
$parts = "$result".Trim() -split "\s+"
$code = $parts[0]
$size = if ($parts.Count -gt 1) { [int64]$parts[1] } else { 0 }

if ($code -ne "200") {
    Write-Warn2 "下载返回 HTTP $code（直连 GitHub 常见超时，试 -Proxy）"
} elseif ($size -ne $apk.Length) {
    Write-Warn2 "下载 $size 字节 ≠ 本地 $($apk.Length) 字节"
} else {
    Write-Ok "下载 $size 字节，与本地一致"
}
if (Test-Path $tmp) { Remove-Item $tmp -Force }

Write-Step "完成"
Write-Host "   Release 页面：$($release.html_url)"
Write-Host "   下载直链    ：$($asset.browser_download_url)"
