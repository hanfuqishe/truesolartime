# 三语 strings 自检（Windows / PowerShell 版）
#
# 规则与 `Scripts/main.swift` 里的本地化断言一致（两边都在守同一件事）：
#   1. 三份 Localizable.strings 的 key 集合完全一致（缺 key / 多 key 都报错）；
#   2. 每条 value 非空，且不是 key 本身；
#   3. 三语的格式参数（%d / %@ / %.1f …）一致；
#   4. 简体里不出现繁体专用字，繁體里不出现简体专用字；
#   5. 英文里不出现 CJK（汉字 / CJK 标点 / 全角符号）；
#   6. 源码里 `L("…")` / `Lf("…")` 用到的 key 都在表里。
#
# 用法（在仓库任意位置）：
#   pwsh -File ios/Scripts/check-localization.ps1
# 退出码：0 = 全过；1 = 有问题。

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$iosRoot = Split-Path -Parent $scriptDir
$resources = Join-Path $iosRoot 'TrueSolarTime/Resources'
$languages = @('zh-Hans', 'zh-Hant', 'en')

# 与 L10n.swift 的 LocalizationCatalog 保持同一张表。
$traditionalOnly = '設資網預連螢檔軟體訊質時後發開關閉應週點線鐘曆級別選擇確認錯誤載儲讀顯隱數據溫濕風雲陰霧陣陽間標準護'
$simplifiedOnly = '设资网预连萤档软体讯质时后发开关闭应周点线钟历级别选择确认错误载储读显隐数据温湿风云阴雾阵阳间标准护'

function Parse-Strings([string]$path) {
    $text = [System.IO.File]::ReadAllText($path)
    $text = [regex]::Replace($text, '/\*.*?\*/', '', 'Singleline')
    $table = @{}
    foreach ($m in [regex]::Matches($text, '"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;')) {
        $key = $m.Groups[1].Value
        $value = $m.Groups[2].Value
        $table[$key] = $value
    }
    return $table
}

function Get-FormatSignature([string]$value) {
    ($([regex]::Matches($value, "%[0-9.\-+']*[@a-zA-Z]") | ForEach-Object { $_.Value })) -join ','
}

function Test-CJK([string]$value) {
    foreach ($ch in $value.ToCharArray()) {
        $code = [int]$ch
        if (($code -ge 0x4E00 -and $code -le 0x9FFF) -or
            ($code -ge 0x3400 -and $code -le 0x4DBF) -or
            ($code -ge 0x3000 -and $code -le 0x303F) -or
            ($code -ge 0xFF00 -and $code -le 0xFFEF) -or
            ($code -ge 0x2E80 -and $code -le 0x2EFF) -or
            ($code -ge 0xF900 -and $code -le 0xFAFF)) {
            return $ch
        }
    }
    return $null
}

$problems = New-Object System.Collections.ArrayList
$tables = @{}

foreach ($language in $languages) {
    $path = Join-Path $resources "$language.lproj/Localizable.strings"
    if (-not (Test-Path -LiteralPath $path)) {
        [void]$problems.Add("$language：找不到 $path")
        continue
    }
    $tables[$language] = Parse-Strings $path
    if ($tables[$language].Count -eq 0) {
        [void]$problems.Add("$language：解析不到任何 key")
    }
}

# 0) 打包前提：三个 .lproj 目录必须存在，且各有 Localizable.strings + InfoPlist.strings。
#    XcodeGen 会把 .lproj 识别成本地化 variant group，Xcode 再拷进 .app；
#    目录缺失时系统只会退到英文（界面看不到中文）。
foreach ($language in $languages) {
    $dir = Join-Path $resources "$language.lproj"
    if (-not (Test-Path -LiteralPath $dir)) {
        [void]$problems.Add("$language：缺少 .lproj 目录（$dir）")
        continue
    }
    foreach ($name in @('Localizable.strings', 'InfoPlist.strings')) {
        $file = Join-Path $dir $name
        if (-not (Test-Path -LiteralPath $file)) {
            [void]$problems.Add("$language：缺少 $name")
        } elseif ((Get-Item -LiteralPath $file).Length -eq 0) {
            [void]$problems.Add("$language：$name 是空文件")
        }
    }
}
if ($tables.Count -eq $languages.Count) {
    $union = New-Object System.Collections.Generic.HashSet[string]
    foreach ($language in $languages) { foreach ($k in $tables[$language].Keys) { [void]$union.Add($k) } }

    foreach ($language in $languages) {
        $keys = $tables[$language].Keys
        $missing = @($union | Where-Object { -not $keys.Contains($_) } | Sort-Object)
        $extra = @($keys | Where-Object { -not $union.Contains($_) } | Sort-Object)
        if ($missing.Count -gt 0) { [void]$problems.Add("$language：缺少 $($missing.Count) 个 key —— $($missing -join ', ')") }
        if ($extra.Count -gt 0) { [void]$problems.Add("$language：多出 $($extra.Count) 个 key —— $($extra -join ', ')") }
    }

    foreach ($key in ($union | Sort-Object)) {
        $signatures = @()
        foreach ($language in $languages) {
            $value = $tables[$language][$key]
            if ([string]::IsNullOrWhiteSpace($value)) {
                [void]$problems.Add("$language：「$key」的文案为空")
            } elseif ($value -eq $key) {
                [void]$problems.Add("$language：「$key」的文案还是 key 本身（没翻译）")
            }
            $signatures += (Get-FormatSignature $value)
        }
        if (($signatures | Select-Object -Unique).Count -gt 1) {
            $detail = for ($i = 0; $i -lt $languages.Count; $i++) { "$($languages[$i]): $($signatures[$i])" }
            [void]$problems.Add("「$key」的格式参数不一致 —— $($detail -join ' / ')")
        }
    }

    foreach ($language in @('zh-Hans', 'zh-Hant')) {
        $forbidden = if ($language -eq 'zh-Hans') { $traditionalOnly } else { $simplifiedOnly }
        $label = if ($language -eq 'zh-Hans') { '繁体专用字' } else { '简体专用字' }
        foreach ($key in ($tables[$language].Keys | Sort-Object)) {
            $found = @()
            foreach ($ch in $tables[$language][$key].ToCharArray()) {
                if ($forbidden.Contains($ch) -and ($found -notcontains $ch)) { $found += $ch }
            }
            if ($found.Count -gt 0) {
                [void]$problems.Add("$language：「$key」里出现$label「$($found -join '、')」")
            }
        }
    }

    foreach ($key in ($tables['en'].Keys | Sort-Object)) {
        $bad = Test-CJK $tables['en'][$key]
        if ($bad) { [void]$problems.Add("en：「$key」里出现 CJK 字符「$bad」") }
    }

    # 源码里用到的 key 必须都在表里
    $used = New-Object System.Collections.Generic.HashSet[string]
    $swiftFiles = Get-ChildItem (Join-Path $iosRoot 'TrueSolarTime') -Recurse -Filter *.swift
    foreach ($file in $swiftFiles) {
        $text = [System.IO.File]::ReadAllText($file.FullName)
        foreach ($m in [regex]::Matches($text, '\b(?:L|Lf|L10n\.t|L10n\.f)\(\s*"([^"]+)"')) {
            [void]$used.Add($m.Groups[1].Value)
        }
    }
    $undefined = @($used | Where-Object { -not $union.Contains($_) } | Sort-Object)
    if ($undefined.Count -gt 0) {
        [void]$problems.Add("源码里用了未定义的 key —— $($undefined -join ', ')")
    }

    Write-Output ("key 数量：zh-Hans={0}  zh-Hant={1}  en={2}（源码引用 {3} 个）" -f `
        $tables['zh-Hans'].Count, $tables['zh-Hant'].Count, $tables['en'].Count, $used.Count)
}

if ($problems.Count -gt 0) {
    Write-Output ""
    Write-Output "发现 $($problems.Count) 个问题："
    foreach ($problem in $problems) { Write-Output "  ERROR $problem" }
    exit 1
}

Write-Output ""
Write-Output "三语 strings 检查通过（key 一致、无空值、格式参数一致、简繁互斥、英文无 CJK、源码 key 齐全）。"
exit 0
