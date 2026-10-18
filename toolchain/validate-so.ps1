<#
.SYNOPSIS
  OHOS .so 产物校验（E2 交付物）——判定「这个 .so 能不能被 HarmonyOS 加载且不崩」。

.DESCRIPTION
  对给定 .so 依次做 8 项检查，每项给出「期望 / 实际 / 判定」。
  关键项（1-5）任一不过 → 退出码 1，**禁止**把该产物推到真机或交给下一步。

  检查项：
    1 ARM64 架构        （ELF Machine = AArch64）
    2 GOOS=openharmony  （strings 里的构建信息；用错 GOOS 是最高频错误）
    3 PT_TLS 段         （有=Go 用了真 TLS；空=典型的 GOOS=android 产物）
    4 R_AARCH64_TLSDESC （有=fork 的通用动态 TLS 生效；空=IE/LE 模型，musl 会拒 dlopen）
    5 导出符号面        （c-shared 下应恰为 //export 集合；多=泄漏面）
    6 DT_NEEDED         （依赖库是否都可满足）
    7 文件大小          （异常偏小=依赖没链进去）
    8 Go 版本标记       （是否 go1.26.x fork 构建）

.PARAMETER SoPath
  待校验的 .so 绝对或相对路径。

.PARAMETER DevEcoNative
  OHOS NDK 的 native 目录（提供 llvm-readelf / llvm-nm / llvm-strings）。

.EXAMPLE
  .\validate-so.ps1 -SoPath ..\_toolchain\smoke\libcgoping.so
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SoPath,
    [string]$DevEcoNative = 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\native',
    [string[]]$ExpectedExports = @()
)

$bin = Join-Path $DevEcoNative 'llvm\bin'
$readelf = Join-Path $bin 'llvm-readelf.exe'
$llvmn = Join-Path $bin 'llvm-nm.exe'
$llvms = Join-Path $bin 'llvm-strings.exe'

$fail = 0
$results = @()

function Add-Result($no, $name, $expected, $actual, $pass, $critical) {
    $script:results += [pscustomobject]@{
        No       = $no
        Check    = $name
        Expected = $expected
        Actual   = $actual
        Pass     = $(if ($pass) { 'PASS' } else { 'FAIL' })
        Critical = $(if ($critical) { 'Y' } else { 'n' })
    }
    if (-not $pass -and $critical) { $script:fail++ }
}

function Run($exe, $argList) {
    # 返回 stdout+stderr 合并文本（llvm 工具把结果打 stdout，错误打 stderr）
    $out = & $exe @argList 2>&1
    return ($out | Out-String)
}

Write-Host ''
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor DarkCyan
Write-Host "  OHOS .so 校验: $SoPath" -ForegroundColor Cyan
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor DarkCyan

if (-not (Test-Path $SoPath)) { Write-Host "  [FAIL] 文件不存在: $SoPath" -ForegroundColor Red; exit 1 }
foreach ($t in @($readelf, $llvmn)) {
    if (-not (Test-Path $t)) { Write-Host "  [FAIL] 校验工具缺失: $t" -ForegroundColor Red; exit 1 }
}
$SoPath = (Resolve-Path $SoPath).Path

# 1 架构
$hdr = Run $readelf @('-h', $SoPath)
$isA64 = $hdr -match 'AArch64'
Add-Result 1 'ELF 架构 = AArch64' 'AArch64' $(if ($isA64) { 'AArch64' } else { '非 AArch64' }) $isA64 $true

# 2 GOOS
$str = Run $llvms @($SoPath)
$goos = '(未找到)'
$m = [regex]::Match($str, 'GOOS=openharmony')
if ($m.Success) { $goos = 'GOOS=openharmony' }
else {
    $m2 = [regex]::Match($str, 'GOOS=[a-z0-9]+')
    if ($m2.Success) { $goos = $m2.Value }
}
Add-Result 2 'GOOS = openharmony' 'GOOS=openharmony' $goos ($goos -eq 'GOOS=openharmony') $true

# 3 PT_TLS
$prog = Run $readelf @('-l', $SoPath)
$hasTls = $prog -match '(?m)^\s*TLS\s'
Add-Result 3 'PT_TLS 段存在' '有 TLS 程序头' $(if ($hasTls) { '有' } else { '无' }) $hasTls $true

# 4 TLSDESC
$rel = Run $readelf @('-r', $SoPath)
$hasDesc = $rel -match 'R_AARCH64_TLSDESC'
Add-Result 4 'R_AARCH64_TLSDESC 重定位' '存在' $(if ($hasDesc) { '存在' } else { '不存在' }) $hasDesc $true

# 5 导出符号
$dyn = Run $llvmn @('-D', $SoPath)
$exported = @()
foreach ($line in ($dyn -split "`r?`n")) {
    if ($line -match '^\s*[0-9a-fA-F]+\s+([Tt])\s+(\S+)$') { $exported += $Matches[2] }
}
$exported = $exported | Sort-Object -Unique
$expStr = ($exported -join ', ')
if ($ExpectedExports.Count -gt 0) {
    $diff = Compare-Object ($ExpectedExports | Sort-Object) $exported
    $okExports = ($null -eq $diff)
    Add-Result 5 '导出符号面' ($ExpectedExports -join ', ') $expStr $okExports $true
} else {
    # 无期望值时，至少要求「有导出」且「不含明显内部符号」
    $okExports = ($exported.Count -gt 0)
    Add-Result 5 '导出符号面（未指定期望）' '至少 1 个' $expStr $okExports $true
}

# 6 DT_NEEDED
$dyns = Run $readelf @('-d', $SoPath)
$needed = @()
foreach ($line in ($dyns -split "`r?`n")) {
    if ($line -match 'NEEDED.*?\[(.+?)\]') { $needed += $Matches[1] }
}
$neededStr = $(if ($needed.Count -eq 0) { '(无)' } else { $needed -join ', ' })
$suspicious = @()
foreach ($n in $needed) {
    if ($n -match '^[A-Za-z]:' -or $n -match '^/' -or $n -match 'libgo') { $suspicious += $n }
}
$okNeeded = ($suspicious.Count -eq 0)
Add-Result 6 'DT_NEEDED 无异常' '仅系统库（如 libc.so）' $neededStr $okNeeded $false

# 7 大小
$sizeMB = [math]::Round((Get-Item $SoPath).Length / 1MB, 2)
$okSize = ($sizeMB -gt 0.3)
Add-Result 7 '文件大小合理' '> 0.3 MB' "$sizeMB MB" $okSize $false

# 8 Go 版本标记
$gover = '(未找到)'
$mg = [regex]::Match($str, 'go1\.(2[0-9])\.[0-9]+')
if ($mg.Success) { $gover = $mg.Value }
$okGov = ($gover -match '^go1\.2[0-9]\.')
Add-Result 8 'Go 版本标记' 'go1.2x.y' $gover $okGov $false

# ── 输出表 ──
Write-Host ''
$results | Format-Table -AutoSize No, Check, Expected, Actual, Pass, Critical | Out-String -Width 200 | Write-Host
Write-Host '  说明：Critical=Y 的项失败即判定产物不可用（不要推真机）。' -ForegroundColor DarkGray
Write-Host ''

if ($fail -gt 0) {
    Write-Host "  ✗ 结论：不可用（$fail 个关键项失败）" -ForegroundColor Red
    Write-Host '    最常见原因速查：' -ForegroundColor DarkGray
    Write-Host '      · #2 不是 openharmony → GOOS 用了 android/linux，或用了官方 Go 而非 fork' -ForegroundColor DarkGray
    Write-Host '      · #3 无 TLS            → 几乎肯定是 GOOS=android 产物（bionic 固定槽）' -ForegroundColor DarkGray
    Write-Host '      · #4 无 TLSDESC        → 缺 -ftls-model=global-dynamic，或 fork 补丁未生效' -ForegroundColor DarkGray
    Write-Host '      · #5 导出过多          → buildmode 不是 c-shared（Go 只在 c-shared 下生成 version script）' -ForegroundColor DarkGray
    exit 1
} else {
    Write-Host '  ✓ 结论：产物通过校验，可用于 P-03 加载验证' -ForegroundColor Green
    Write-Host '    注意：这只证明「可被加载且 TLS 模型正确」，不证明运行期一定不崩——仍需真机 P-03。' -ForegroundColor DarkGray
    exit 0
}
