# 从鸿蒙签名证书（.cer，PEM 或含证书链）里提取备案要的两项：
#   · 签名证书的 MD5 指纹
#   · 证书公钥（base64 编码的 DER SubjectPublicKeyInfo）
#
# 用法：
#   powershell -File tools/harmony-cert-info.ps1 -CertPath "C:\Users\me\.ohos\config\xxx.cer"
#   powershell -File tools/harmony-cert-info.ps1 -CertPath xxx.cer -LeafIndex 2
#
# 说明：
#   * DevEco / AGC 导出的 .cer 常常是**证书链**（根 → 中间 → 应用证书）。
#     备案要的是最后那张「应用证书」，脚本默认取链尾；不确定时用 -List 先看每张的主题。
#   * 备案必须用**发布证书**（CN 里不带 Development）；调试证书的指纹与上架包对不上。
#   * 依赖 openssl 在 PATH 里（DevEco 自带、msys2 也有）。

param(
    [Parameter(Mandatory = $true)][string]$CertPath,
    [int]$LeafIndex = -1,
    [switch]$List
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $CertPath)) { throw "找不到证书：$CertPath" }

$openssl = (Get-Command openssl -ErrorAction SilentlyContinue)
if (-not $openssl) { throw "PATH 里没有 openssl（DevEco 自带的那份也可以，把它加到 PATH）" }

$work = Join-Path $env:TEMP ("certinfo_" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
try {
    # 统一拆成单张：.cer 可能是单证书，也可能是链
    $chainPem = Join-Path $work 'chain.pem'
    $raw = [System.IO.File]::ReadAllText($CertPath)
    if ($raw -match '-----BEGIN CERTIFICATE-----') {
        Copy-Item $CertPath $chainPem
    } else {
        # DER 输入：转成 PEM
        & $openssl x509 -inform DER -in $CertPath -out $chainPem 2>$null
    }

    $text = [System.IO.File]::ReadAllText($chainPem)
    $blocks = [regex]::Matches($text, '-----BEGIN CERTIFICATE-----[\s\S]*?-----END CERTIFICATE-----')
    if ($blocks.Count -eq 0) { throw "证书里没解析出任何 CERTIFICATE 段" }

    $certs = @()
    for ($i = 0; $i -lt $blocks.Count; $i++) {
        $f = Join-Path $work "cert$i.pem"
        [System.IO.File]::WriteAllText($f, $blocks[$i].Value + "`n")
        $subject = ((& $openssl x509 -in $f -noout -subject 2>$null) -join ' ').Trim()
        $md5 = ((& $openssl x509 -in $f -noout -fingerprint -md5 2>$null) -join ' ').Trim()
        $certs += [pscustomobject]@{ Index = $i; Path = $f; Subject = $subject; Md5 = ($md5 -replace '^.*Fingerprint=', '') }
    }

    if ($List) {
        "共 $($certs.Count) 张证书："
        foreach ($c in $certs) {
            "  [$($c.Index)] $($c.Subject)"
            "       MD5 = $($c.Md5)"
        }
        return
    }

    $leaf = if ($LeafIndex -ge 0) { $certs | Where-Object { $_.Index -eq $LeafIndex } } else { $certs[-1] }
    if (-not $leaf) { throw "没有索引为 $LeafIndex 的证书（共 $($certs.Count) 张）" }

    # 公钥：先导出 PEM 公钥，再转 DER 字节，最后 base64（不要走文本管道，会乱码）
    $pubPem = Join-Path $work 'pub.pem'
    $pubDer = Join-Path $work 'pub.der'
    & $openssl x509 -in $leaf.Path -pubkey -noout -out $pubPem 2>$null
    & $openssl pkey -pubin -in $pubPem -outform DER -out $pubDer 2>$null
    $pubBase64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($pubDer))

    "证书主题 : $($leaf.Subject)"
    "MD5 指纹 : $($leaf.Md5)"
    "公钥(b64) : $pubBase64"
    ""
    if ($leaf.Subject -match 'Development') {
        "⚠️ 这是**调试证书**（主题里带 Development）。备案要用发布证书（Release），"
        "   否则指纹与 AppGallery 上的包对不上。"
    }
} finally {
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
}
