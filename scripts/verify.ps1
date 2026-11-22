# verify.ps1 — 一条命令跑完"能自动化的验证"。
#
# 目的：把这段时间反复手工做的事固化下来。之前的教训是——编译通过、日志正常、
# 功能却是坏的（TextEncoder 返回空数组、Md.update 未 await、ForEach key 不更新、
# 错误打成 [object Object]）。这些都能被"跑一遍"抓住，前提是有人真的跑。
#
# 用法：
#   powershell -ExecutionPolicy Bypass -File .\scripts\verify.ps1              # 纯逻辑 + 编译
#   powershell -ExecutionPolicy Bypass -File .\scripts\verify.ps1 -Emulator    # 额外跑设备冒烟
#
# 退出码：0 全通过；非 0 有失败（可直接用于 CI）。

param(
    [switch]$Emulator
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$node = 'C:\Program Files\Huawei\DevEco Studio\tools\node\node.exe'
if (-not (Test-Path $node)) { $node = 'node' }
$hdc = 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
$hap = Join-Path $repoRoot 'entry\build\default\outputs\default\entry-default-unsigned.hap'

$failures = @()

function Step($name) { Write-Host ''; Write-Host "=== $name ===" -ForegroundColor Cyan }

# 1) 纯逻辑测试：直接从源码抽函数体执行，跑的是真代码而不是副本
Step '1/3 纯逻辑测试（配置生成）'
Push-Location $repoRoot
try {
    & $node 'tests\config-builder.test.js'
    if ($LASTEXITCODE -ne 0) { $failures += 'config-builder.test.js' }
    & $node 'tests\socks-last-endpoint.test.js'
    if ($LASTEXITCODE -ne 0) { $failures += 'socks-last-endpoint.test.js' }
    # 日志脱敏：一条没被掩掉的 UUID/密码等于把用户凭据公开（导出/截图都会带出去）
    & $node 'tests\log-redaction.test.js'
    if ($LASTEXITCODE -ne 0) { $failures += 'log-redaction.test.js' }
    # 订阅条数不能读 AppConfig.subscriptions：该字段从未被填充，会让 3 个订阅显示成未添加
    & $node 'tests\config-subs-source.test.js'
    if ($LASTEXITCODE -ne 0) { $failures += 'config-subs-source.test.js' }
    # 文字层硬闸：可换行的 Text 必须有行高（中文缺行高会整段挤在一起，无法扫读）
    & $node 'scripts\check-text-style.js'
    if ($LASTEXITCODE -ne 0) { $failures += 'check-text-style' }
    # 安全扫描：硬编码凭据 / 明文端点 / 绕过脱敏的日志 / unsafe C 函数
    & $node 'scripts\security-scan.js'
    if ($LASTEXITCODE -ne 0) { $failures += 'security-scan' }
    # 对比度闸门：色标/白字/三级灰必须过 WCAG AA 4.5:1（改一个 hex 就能把字压到读不出）
    & $node 'scripts\check-contrast.js'
    if ($LASTEXITCODE -ne 0) { $failures += 'check-contrast' }
    # 编码闸门：文本文件必须是合法 UTF-8（用 shell here-doc 追加中文会写成 GBK，编译不报错）
    & $node 'scripts\check-encoding.js'
    if ($LASTEXITCODE -ne 0) { $failures += 'check-encoding' }
    # 行尾闸门：跟踪的文本文件必须是 LF（core.autocrlf=true 会把 checkout 改写成 CRLF）
    & $node 'scripts\check-eol.js'
    if ($LASTEXITCODE -ne 0) { $failures += 'check-eol' }
} finally { Pop-Location }

# 2) 编译：arm64 是发布目标，顺带做 ArkTS 全量类型检查
Step '2/3 编译（arm64）'
try {
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'scripts\build-hap.ps1') -Abi arm64 | Out-Null
    if ($LASTEXITCODE -ne 0) { $failures += 'build arm64' }
    else { Write-Host 'BUILD OK' -ForegroundColor Green }
} catch {
    $failures += "build arm64 ($($_.Exception.Message))"
}

# 3) 设备冒烟（可选）：装包 → 启动 → 连接 → 断言内核真的 running
Step '3/3 设备冒烟（可选）'
if (-not $Emulator) {
    Write-Host '跳过（未传 -Emulator）'
} else {
    $targets = & $hdc list targets 2>&1
    if ($targets -notmatch '127\.0\.0\.1:5555|\w{8,}') {
        $failures += 'emulator not connected'
    } else {
        try {
            & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'scripts\build-hap.ps1') -Abi x86_64 | Out-Null
            & $hdc install -r $hap | Out-Null
            & $hdc shell aa force-stop com.tunnelix.app | Out-Null
            Start-Sleep -Seconds 2
            & $hdc shell aa start -a EntryAbility -b com.tunnelix.app | Out-Null
            Start-Sleep -Seconds 8
            & $hdc shell uitest uiInput click 658 912 | Out-Null   # 首页「连接」
            Start-Sleep -Seconds 6
            $log = & $hdc shell "hilog -x | grep 'KernelService' | tail -5" 2>&1
            if ($log -match 'confirmed running=true') {
                Write-Host 'connected: running=true' -ForegroundColor Green
            } else {
                $failures += 'connect did not reach running=true'
                Write-Host $log
            }
        } catch {
            $failures += "emulator smoke ($($_.Exception.Message))"
        }
    }
}

Step '结果'
if ($failures.Count -eq 0) {
    Write-Host 'ALL PASS' -ForegroundColor Green
    exit 0
}
Write-Host ("FAILED: " + ($failures -join '; ')) -ForegroundColor Red
exit 1
