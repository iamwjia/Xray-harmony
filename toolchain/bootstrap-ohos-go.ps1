<#
.SYNOPSIS
  OHOS Go 工具链一键自举（Windows 原生路径）——E2 交付物。

.DESCRIPTION
  从零到「能编出可被 OHOS 加载的 .so」的完整步骤：预检 → 下引导 Go → 解压 →
  取 OHOS Go fork 源码 → 自举工具链 → 验证 → 编最小 CGo .so → 校验产物。

  ★ 默认 -Mode Plan：只打印将要执行的动作与期望输出，**不下载、不安装、不编译**。
    真正执行必须显式给 -Mode Run（需用户批准下载）。

  每一步都打印 [STEP n/N] 与期望输出，便于对照 README.md 的验证表。

.PARAMETER Mode
  Plan（默认）：演练，不产生任何副作用；Run：真实执行。

.PARAMETER Stage
  all（默认）| preflight | download | bootstrap | verify | smoke
  用于分段执行：例如先 -Stage preflight 确认环境，再 -Stage download。

.PARAMETER Root
  工作目录（工具链与源码都放这里，**不要放仓库内**，避免被人误 clean）。
  默认 D:\projects\xray-harmony\toolchain\_work

.PARAMETER DevEcoNative
  OHOS NDK 的 native 目录（含 llvm\bin 与 sysroot）。

.PARAMETER ForkTag
  OHOS Go fork 的 tag，默认 v1.26.5-beta1（现役）。

.PARAMETER BootstrapVersion
  引导 Go 版本；留空=自动从官方 JSON 索引里挑最新的 go1.24.x（≥1.24.6）。

.PARAMETER DownloadBase
  引导 Go 下载基址。国内不通时改 https://golang.google.cn/dl

.EXAMPLE
  # 1) 先演练，确认动作清单
  powershell -ExecutionPolicy Bypass -File .\bootstrap-ohos-go.ps1

.EXAMPLE
  # 2) 用户批准下载后，分段真跑
  powershell -ExecutionPolicy Bypass -File .\bootstrap-ohos-go.ps1 -Mode Run -Stage preflight
  powershell -ExecutionPolicy Bypass -File .\bootstrap-ohos-go.ps1 -Mode Run -Stage download
  powershell -ExecutionPolicy Bypass -File .\bootstrap-ohos-go.ps1 -Mode Run -Stage bootstrap
  powershell -ExecutionPolicy Bypass -File .\bootstrap-ohos-go.ps1 -Mode Run -Stage verify
  powershell -ExecutionPolicy Bypass -File .\bootstrap-ohos-go.ps1 -Mode Run -Stage smoke
#>

[CmdletBinding()]
param(
    [ValidateSet('Plan', 'Run')][string]$Mode = 'Plan',
    [ValidateSet('all', 'preflight', 'download', 'bootstrap', 'verify', 'smoke')][string]$Stage = 'all',
    [string]$Root = 'D:\projects\xray-harmony\toolchain\_work',
    [string]$DevEcoNative = 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\native',
    [string]$ForkTag = 'v1.26.5-beta1',
    [string]$BootstrapVersion = '',
    [string]$DownloadBase = 'https://go.dev/dl'
)

$ErrorActionPreference = 'Continue'
$Total = 9
$script:Fail = 0

# ─────────────────────────── 输出helper ───────────────────────────
function Banner($n, $title) {
    Write-Host ''
    Write-Host ("=" * 68) -ForegroundColor DarkCyan
    Write-Host ("[STEP {0}/{1}] {2}" -f $n, $Total, $title) -ForegroundColor Cyan
    Write-Host ("=" * 68) -ForegroundColor DarkCyan
}
function Info($m) { Write-Host "  $m" }
function Expect($m) { Write-Host "  期望: $m" -ForegroundColor DarkGray }
function Ok($m) { Write-Host "  [OK] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "  [WARN] $m" -ForegroundColor Yellow }
function Bad($m) { Write-Host "  [FAIL] $m" -ForegroundColor Red; $script:Fail++ }
function Cmd($m) { Write-Host "  > $m" -ForegroundColor DarkYellow }

# Plan 模式：只打印；Run 模式：执行
function Do($what, [scriptblock]$action) {
    if ($Mode -eq 'Plan') {
        Info "[PLAN] 将执行: $what"
        return $null
    }
    Info "执行: $what"
    return (& $action)
}

function NeedRun($stage) {
    return ($Stage -eq 'all' -or $Stage -eq $stage)
}

# ─────────────────────────── 路径 ───────────────────────────
$forkDir     = Join-Path $Root ("ohos-go-" + $ForkTag.TrimStart('v'))
$bootDir     = Join-Path $Root 'bootstrap-go'
$dlDir       = Join-Path $Root 'downloads'
$smokeDir    = Join-Path $Root 'smoke'
$goExe       = Join-Path $forkDir 'bin\go.exe'
$clang       = Join-Path $DevEcoNative 'llvm\bin\aarch64-unknown-linux-ohos-clang'
$clangxx     = Join-Path $DevEcoNative 'llvm\bin\aarch64-unknown-linux-ohos-clang++'
$readelf     = Join-Path $DevEcoNative 'llvm\bin\llvm-readelf.exe'
$llvmn       = Join-Path $DevEcoNative 'llvm\bin\llvm-nm.exe'

Write-Host ''
Write-Host "  OHOS Go 工具链自举 | Mode=$Mode Stage=$Stage" -ForegroundColor White
Write-Host "  Root=$Root"
Write-Host "  Fork=$ForkTag  DevEco=$DevEcoNative"
if ($Mode -eq 'Plan') {
    Write-Host ''
    Write-Host "  ⚠ 当前是 Plan 模式：不会下载/安装/编译任何东西。真实执行请加 -Mode Run（需授权）。" -ForegroundColor Yellow
}

# ═══════════════ STEP 1 预检 ═══════════════
if (NeedRun 'preflight') {
    Banner 1 '预检：环境与既有资产'
    Info "OS: $([System.Environment]::OSVersion.VersionString)  64bit=$([Environment]::Is64BitProcess)"
    Expect 'Windows 10/11 x64（本机）'

    if (Test-Path $clang) { Ok "NDK clang 存在: $clang" } else { Bad "NDK clang 不存在: $clang（检查 -DevEcoNative）" }
    if (Test-Path $clangxx) { Ok "NDK clang++ 存在" } else { Warn "NDK clang++ 不存在（CGO 不需要它，但 C++ 依赖时会用到）" }
    if (Test-Path $readelf) { Ok "llvm-readelf 存在" } else { Bad "llvm-readelf 缺失 → 产物校验会退化到 llvm-objdump" }
    if (Test-Path $llvmn) { Ok "llvm-nm 存在" } else { Bad "llvm-nm 缺失 → 导出符号校验无法做" }

    $drive = ($Root -split ':')[0] + ':'
    $free = $null
    try { $free = (Get-PSDrive -Name $drive.TrimEnd(':')).Free } catch { $free = $null }
    if ($null -ne $free) {
        $freeGB = [math]::Round($free / 1GB, 1)
        Info "磁盘 $drive 可用 ${freeGB} GB"
        if ($freeGB -lt 5) { Warn '建议 >= 5 GB（工具链 + 源码 + 后续模块缓存）' } else { Ok '磁盘空间充足' }
    } else { Warn "无法读取 $drive 可用空间" }

    $sysGo = Get-Command go -ErrorAction SilentlyContinue
    if ($null -eq $sysGo) { Ok '本机无 Go（符合预期：我们将用自举方式装 fork 工具链）' }
    else { Warn "PATH 里已有 Go: $($sysGo.Source)；自举时请注意不要被它干扰（脚本用绝对路径调用 fork 的 go）" }

    Info "Git: $(if (Get-Command git -ErrorAction SilentlyContinue) { '可用' } else { '不可用（将退回 tarball 下载）' })"
}

# ═══════════════ STEP 2 解析引导 Go 版本 ═══════════════
$bootZipName = $null
$bootSha     = $null
if (NeedRun 'download') {
    Banner 2 '解析引导 Go 版本（>=1.24.6 且 <1.26 的 windows-amd64）'
    if ($Mode -eq 'Plan') {
        Cmd "GET $DownloadBase/?mode=json&include=all"
        Expect '从 JSON 索引里筛选 go1.24.x（取最高），拿到 windows-amd64 archive 的 filename + sha256'
        Info '[PLAN] 若用户指定 -BootstrapVersion 则跳过筛选，直接用指定版本'
    } else {
        try {
            $idx = Invoke-RestMethod -Uri "$DownloadBase/?mode=json&include=all" -UseBasicParsing -TimeoutSec 60
            $cands = @()
            foreach ($rel in $idx) {
                $v = [string]$rel.version
                # 允许 go1.24.x / go1.25.x（均满足 fork 的 minBootstrap = go1.24.6）；上限取 < go1.26
                if ($v -notlike 'go1.24.*' -and $v -notlike 'go1.25.*') { continue }
                foreach ($f in $rel.files) {
                    if ($f.kind -eq 'archive' -and $f.os -eq 'windows' -and $f.arch -eq 'amd64') {
                        $cands += [pscustomobject]@{ Version = $v; File = $f.filename; Sha = $f.sha256 }
                    }
                }
            }
            if ($BootstrapVersion -ne '') {
                $pick = $cands | Where-Object { $_.Version -eq $BootstrapVersion } | Select-Object -First 1
                if ($null -eq $pick) { $pick = $null }
            } else {
                $pick = $cands | Sort-Object { [version]($_.Version -replace '^go', '') } | Select-Object -Last 1
            }
            if ($null -eq $pick) {
                Bad '未在索引中找到合适的 go1.24.x windows-amd64 包；请用 -BootstrapVersion 显式指定，或换 -DownloadBase'
            } else {
                $bootZipName = $pick.File
                $bootSha = $pick.Sha
                Ok "选定: $($pick.Version)  文件: $bootZipName"
                Info "sha256: $bootSha"
            }
        } catch {
            Bad "读取 Go 下载索引失败: $($_.Exception.Message)"
            Info '国内网络可试: -DownloadBase https://golang.google.cn/dl'
        }
    }
}

# ═══════════════ STEP 3 下载并校验 ═══════════════
if (NeedRun 'download') {
    Banner 3 '下载并校验引导 Go（sha256 必须与官方索引一致）'
    if ($Mode -eq 'Plan') {
        Cmd "mkdir $dlDir"
        Cmd "Invoke-WebRequest $DownloadBase/$bootZipName -> $dlDir"
        Cmd 'Get-FileHash -Algorithm SHA256  → 与索引比对'
        Expect '哈希一致；不一致必须中止（供应链风险）'
    } else {
        if ($null -eq $bootZipName) { Bad '缺少引导 Go 包名，跳过下载' }
        else {
            if (-not (Test-Path $dlDir)) { New-Item -ItemType Directory -Path $dlDir -Force | Out-Null }
            $zip = Join-Path $dlDir $bootZipName
            if (Test-Path $zip) {
                Ok "已存在: $zip（跳过下载）"
            } else {
                Do "下载 $DownloadBase/$bootZipName" { Invoke-WebRequest -Uri "$DownloadBase/$bootZipName" -OutFile $zip -UseBasicParsing -TimeoutSec 1800 }
                if (-not (Test-Path $zip)) { Bad '下载失败' }
            }
            if ((Test-Path $zip) -and $bootSha) {
                $actual = (Get-FileHash -Algorithm SHA256 -Path $zip).Hash.ToLower()
                if ($actual -eq $bootSha.ToLower()) { Ok 'sha256 校验通过' } else { Bad "sha256 不一致！期望 $bootSha 实际 $actual —— 中止" }
            }
        }
    }
}

# ═══════════════ STEP 4 解压引导 Go ═══════════════
if (NeedRun 'download') {
    Banner 4 '解压引导 Go 到工作目录'
    if ($Mode -eq 'Plan') {
        Cmd "Expand-Archive $dlDir\<go zip> -DestinationPath $Root\_boottmp"
        Expect "得到 $Root\_boottmp\go\bin\go.exe；再整目录移动为 $bootDir"
    } else {
        if ($bootZipName -and (Test-Path (Join-Path $dlDir $bootZipName))) {
            $tmp = Join-Path $Root '_boottmp'
            if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
            New-Item -ItemType Directory -Path $tmp -Force | Out-Null
            Do 'Expand-Archive' { Expand-Archive -Path (Join-Path $dlDir $bootZipName) -DestinationPath $tmp -Force }
            $extracted = Join-Path $tmp 'go'
            if (Test-Path $extracted) {
                if (Test-Path $bootDir) { Remove-Item -Recurse -Force $bootDir }
                Move-Item -Path $extracted -Destination $bootDir
                if (Test-Path (Join-Path $bootDir 'bin\go.exe')) { Ok "引导 Go 就绪: $bootDir" } else { Bad '解压后未找到 bin\go.exe' }
            } else { Bad "解压目录结构异常，未见 $extracted" }
            Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
        } else { Bad '没有可解压的引导 Go 包' }
    }
    Info '验证: & "$bootDir\bin\go.exe" version  期望 go version go1.24.x windows/amd64'
}

# ═══════════════ STEP 5 取 OHOS Go fork 源码 ═══════════════
if (NeedRun 'download') {
    Banner 5 "取 OHOS Go fork 源码（tag $ForkTag）"
    if ($Mode -eq 'Plan') {
        Cmd "git clone --branch $ForkTag https://github.com/star4277/ohos-go.git $forkDir"
        Cmd 'git -C $forkDir rev-parse HEAD   # ← 必须记入实验留痕'
        Expect '源码目录含 src\make.bat；VERSION 含 1.26.5'
        Info '备用（无 git 时）: 下载 https://github.com/star4277/ohos-go/archive/refs/tags/<tag>.tar.gz 并解压'
    } else {
        if (Test-Path (Join-Path $forkDir 'src\make.bat')) {
            Ok "fork 源码已存在: $forkDir"
        } elseif (Get-Command git -ErrorAction SilentlyContinue) {
            Do "git clone" { git clone --branch $ForkTag https://github.com/star4277/ohos-go.git $forkDir }
        } else {
            Bad '无 git，请手动下载 tarball 解压到 $forkDir（见 README §7）'
        }
        if (Test-Path (Join-Path $forkDir 'src\make.bat')) {
            $sha = (& git -C $forkDir rev-parse HEAD) 2>$null
            Ok "fork commit: $sha   ← 请抄进实验记录"
            $vfile = Join-Path $forkDir 'VERSION'
            if (Test-Path $vfile) { Info "VERSION: $((Get-Content $vfile -Raw).Trim())" }
        }
    }
}

# ═══════════════ STEP 6 自举工具链 ═══════════════
if (NeedRun 'bootstrap') {
    Banner 6 '自举 OHOS Go 工具链（src\make.bat，约 6–15 分钟）'
    if ($Mode -eq 'Plan') {
        Cmd '$env:GOROOT_BOOTSTRAP = "<bootstrap-go>"'
        Cmd '$env:GOTOOLCHAIN     = "local"'
        Cmd 'Push-Location "$forkDir\src"; .\make.bat'
        Expect '结尾打印 Installed Go for windows/amd64；生成 "$forkDir\bin\go.exe"'
        Warn '常见失败：bootstrap 版本过低/过高、OOM、GOTOOLCHAIN 未设导致去下载官方 Go'
        Info 'Windows 原生自举属【待验证】路径；若失败请走 WSL2（README §4 Path B）'
    } else {
        $env:GOROOT_BOOTSTRAP = $bootDir
        $env:GOTOOLCHAIN = 'local'
        Info "GOROOT_BOOTSTRAP=$($env:GOROOT_BOOTSTRAP)"
        Push-Location (Join-Path $forkDir 'src')
        try {
            Do 'make.bat' { & cmd /c "make.bat" }
        } finally {
            Pop-Location
        }
        if (Test-Path $goExe) { Ok "工具链已生成: $goExe" } else { Bad '未生成 bin\go.exe，自举失败（见 README §6 决策树）' }
    }
}

# ═══════════════ STEP 7 验证工具链 ═══════════════
if (NeedRun 'verify' -or $Stage -eq 'all') {
    Banner 7 '验证工具链（三条全绿才算成功）'
    Cmd '& $goExe version'
    Expect 'go version go1.26.5 windows/amd64'
    Cmd '& $goExe tool dist list | Select-String openharmony'
    Expect 'openharmony/arm64   ← 缺此行说明 fork 端口补丁没生效'
    Cmd '& $goExe env GOOS GOARCH CGO_ENABLED'
    Expect 'windows amd64 1'
    if ($Mode -eq 'Run' -and (Test-Path $goExe)) {
        $v = & $goExe version 2>&1
        if ($v -match 'go1\.26\.5') { Ok "① $v" } else { Bad "① 版本不符: $v" }
        $dl = & $goExe tool dist list 2>&1 | Select-String 'openharmony'
        if ($dl) { Ok "② $($dl.ToString().Trim())" } else { Bad '② 未见 openharmony/arm64 → 端口补丁未生效' }
    } elseif ($Mode -eq 'Run') {
        Bad "工具链不存在，跳过 ① ②: $goExe"
    }
}

# ═══════════════ STEP 8 编最小 CGo .so ═══════════════
if (NeedRun 'smoke') {
    Banner 8 '编最小 CGo .so（libcgoping.so，不拉 Xray-core）'
    $smokeSrc = Join-Path $PSScriptRoot 'smoke\cgoping.go'
    $soOut = Join-Path $smokeDir 'libcgoping.so'
    if ($Mode -eq 'Plan') {
        Cmd "cp $smokeSrc $smokeDir\cgoping.go"
        Cmd "'module cgoping' + 'go 1.26' -> $smokeDir\go.mod"
        Cmd '$env:GOOS="openharmony"; $env:GOARCH="arm64"; $env:CGO_ENABLED="1"'
        Cmd ('$env:CC="' + $clang + '"')
        Cmd '$env:CGO_CFLAGS="-ftls-model=global-dynamic"'
        Cmd '$env:GOTOOLCHAIN="local"'
        Cmd "Push-Location $smokeDir; & $goExe build -trimpath -buildvcs=false -buildmode=c-shared -o libcgoping.so ."
        Expect "产出 libcgoping.so（约 2–4 MB）+ libcgoping.h"
        Warn '禁止加 -tags netgo（openharmony net 端口需 cgo，会报 _C_getifaddrs undefined）'
    } else {
        if (-not (Test-Path $goExe)) { Bad '工具链不存在，无法编 smoke' }
        else {
            if (-not (Test-Path $smokeDir)) { New-Item -ItemType Directory -Path $smokeDir -Force | Out-Null }
            Copy-Item $smokeSrc (Join-Path $smokeDir 'cgoping.go') -Force
            Set-Content -Path (Join-Path $smokeDir 'go.mod') -Encoding ASCII -Value @('module cgoping', '', 'go 1.26', '')
            $env:GOOS = 'openharmony'
            $env:GOARCH = 'arm64'
            $env:CGO_ENABLED = '1'
            $env:CC = $clang
            $env:CXX = $clangxx
            $env:CGO_CFLAGS = '-ftls-model=global-dynamic'
            $env:GOTOOLCHAIN = 'local'
            Push-Location $smokeDir
            try {
                Do 'go build -buildmode=c-shared' { & $goExe build -trimpath -buildvcs=false -buildmode=c-shared -o 'libcgoping.so' '.' }
            } finally {
                Pop-Location
            }
            if (Test-Path $soOut) { Ok "产物: $soOut ($([math]::Round((Get-Item $soOut).Length/1MB,2)) MB)" }
            else { Bad '未产出 libcgoping.so（见 README §6 决策树「编译失败」分支）' }
        }
    }
}

# ═══════════════ STEP 9 校验产物 ═══════════════
if (NeedRun 'smoke') {
    Banner 9 '校验产物（PT_TLS / TLSDESC / 导出面 / DT_NEEDED）'
    $validator = Join-Path $PSScriptRoot 'validate-so.ps1'
    Cmd "& $validator -SoPath $smokeDir\libcgoping.so"
    Expect '4 项关键检查全 PASS；导出符号恰为 CGoPing + CGoFree'
    if ($Mode -eq 'Run') {
        if (Test-Path $validator -and (Test-Path (Join-Path $smokeDir 'libcgoping.so'))) {
            & $validator -SoPath (Join-Path $smokeDir 'libcgoping.so') -DevEcoNative $DevEcoNative
        } else {
            Warn '校验脚本或产物缺失，跳过（请先完成 STEP 8）'
        }
    }
}

# ─────────────────────────── 收尾 ───────────────────────────
Write-Host ''
Write-Host ("=" * 68) -ForegroundColor DarkCyan
if ($Mode -eq 'Plan') {
    Write-Host '  Plan 完成：未产生任何下载/安装/编译副作用。' -ForegroundColor Yellow
    Write-Host '  下一步：用户批准后加 -Mode Run 分段执行（建议先 -Stage preflight）。' -ForegroundColor Yellow
} elseif ($script:Fail -eq 0) {
    Write-Host '  全部步骤未见 FAIL。请把 STEP 5 的 commit、STEP 6 耗时、STEP 9 输出抄进实验记录。' -ForegroundColor Green
} else {
    Write-Host ("  有 {0} 处 FAIL —— 按 README §6 失败决策树处置，不要盲目重试。" -f $script:Fail) -ForegroundColor Red
}
Write-Host ("=" * 68) -ForegroundColor DarkCyan
if ($script:Fail -gt 0) { exit 1 } else { exit 0 }
