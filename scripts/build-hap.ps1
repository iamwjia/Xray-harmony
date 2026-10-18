# Build the PoC HAP for a chosen ABI set (real device vs emulator).
#
# Why this script exists:
#   * The real device is arm64-v8a; the emulator is x86_64.
#   * libxray.so is ~38 MB (stripped). Shipping BOTH ABIs means the real-device
#     package carries ~38 MB that it can never use.
#   => default = arm64-v8a only (release).  Pass -Abi both only when you need the
#      emulator build.
#
# It rewrites entry/build-profile.json5's abiFilters for the duration of the build
# and always restores the arm64-only default afterwards (so a forgotten flag cannot
# silently inflate the release package).
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\scripts\build-hap.ps1                 # arm64 only (release)
#   powershell -ExecutionPolicy Bypass -File .\scripts\build-hap.ps1 -Abi x86_64     # emulator only
#   powershell -ExecutionPolicy Bypass -File .\scripts\build-hap.ps1 -Abi both       # both (debug convenience)

param(
    [ValidateSet('arm64', 'x86_64', 'both')]
    [string]$Abi = 'arm64'
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$dev      = 'C:\Program Files\Huawei\DevEco Studio'
$hvigor   = Join-Path $dev 'tools\hvigor\bin\hvigorw.bat'
$profile  = Join-Path $repoRoot 'entry\build-profile.json5'
$hapOut   = Join-Path $repoRoot 'entry\build\default\outputs\default\entry-default-unsigned.hap'

if (-not (Test-Path $hvigor)) { Write-Host "ERROR: hvigorw not found: $hvigor" -ForegroundColor Red; exit 1 }

switch ($Abi) {
    'arm64'  { $filters = 'arm64-v8a' }
    'x86_64' { $filters = 'x86_64' }
    'both'   { $filters = 'arm64-v8a, x86_64' }
}

$original = Get-Content $profile -Raw -Encoding UTF8

# The default block (kept verbatim in build-profile.json5) — we replace this exact
# text instead of using a regex, because a sloppy regex produced invalid JSON once.
$defaultBlock = @"
      "abiFilters": [
        "arm64-v8a"
      ]
"@
if (-not $original.Contains($defaultBlock)) {
    Write-Host 'ERROR: default abiFilters block not found (expected arm64-v8a only).' -ForegroundColor Red
    Write-Host 'Check entry/build-profile.json5 manually.' -ForegroundColor Red
    exit 1
}

$abiLines = ($filters -split ',\s*' | ForEach-Object { '        "' + $_ + '"' }) -join ",`n"
$newBlock = @"
      "abiFilters": [
$abiLines
      ]
"@
$patched = $original.Replace($defaultBlock, $newBlock)

try {
    [System.IO.File]::WriteAllText($profile, $patched, (New-Object System.Text.UTF8Encoding($false)))

    $env:DEVECO_SDK_HOME = Join-Path $dev 'sdk'
    $env:JAVA_HOME       = Join-Path $dev 'jbr'
    $env:PATH            = (Join-Path $dev 'jbr\bin') + ';' + $env:PATH

    Write-Host "ABI filters: $filters"

    # CMake's EXISTS() checks for per-ABI prebuilt libs are evaluated at configure
    # time. Touch CMakeLists so a newly built <abi>/lib*.so is always picked up
    # (otherwise that ABI silently links without the kernel / cgoping lib).
    $cmakeLists = Join-Path $repoRoot 'entry\src\main\cpp\CMakeLists.txt'
    if (Test-Path $cmakeLists) { (Get-Item $cmakeLists).LastWriteTime = Get-Date }

    $logFile = Join-Path $repoRoot '_toolchain\hvigor-build.log'
    $errFile = Join-Path $repoRoot '_toolchain\hvigor-build.err.log'
    $sw = [Diagnostics.Stopwatch]::StartNew()
    # Start-Process avoids both the cmd quoting traps (paths with spaces) and the
    # "native stderr becomes a terminating PowerShell error" problem.
    $proc = Start-Process -FilePath $hvigor `
        -ArgumentList @('--mode', 'module', '-p', 'product=default', 'assembleHap', '--no-daemon') `
        -WorkingDirectory $repoRoot -NoNewWindow -Wait -PassThru `
        -RedirectStandardOutput $logFile -RedirectStandardError $errFile
    $exit = $proc.ExitCode
    $sw.Stop()
    if ($exit -ne 0) {
        Write-Host 'BUILD FAILED — tail of log:' -ForegroundColor Red
        Get-Content $logFile -Tail 12
        Get-Content $errFile -Tail 12
        exit 1
    }

    if (-not (Test-Path $hapOut)) { Write-Host 'ERROR: HAP not produced' -ForegroundColor Red; exit 1 }
    $hap = Get-Item $hapOut
    Write-Host ("BUILD OK  abi={0}  hap={1:N0} bytes  build={2}s" -f $Abi, $hap.Length, [int]$sw.Elapsed.TotalSeconds) -ForegroundColor Green

    # Per-ABI breakdown straight from the HAP (no estimation).
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($hap.FullName)
    try {
        $rows = $zip.Entries | Where-Object { $_.FullName -match '^libs/' } |
                Sort-Object FullName | Select-Object FullName, Length
        $total = ($rows | Measure-Object -Property Length -Sum).Sum
        Write-Host ''
        Write-Host 'HAP libs/ contents:'
        $rows | ForEach-Object { Write-Host ("  {0,-34} {1,12:N0}" -f $_.FullName, $_.Length) }
        Write-Host ("  {0,-34} {1,12:N0}" -f '(libs total)', $total)
    } finally {
        $zip.Dispose()
    }
} finally {
    # Always restore the arm64-only default.
    [System.IO.File]::WriteAllText($profile, $original, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host ''
    Write-Host 'entry/build-profile.json5 restored to default (arm64-v8a only).'
}
