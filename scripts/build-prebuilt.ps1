# Rebuild the prebuilt shared library (libprebuilt.so) for both ABIs.
#
# Purpose: keep the checked-in binaries auditable/reproducible.
#   Source : entry/src/main/cpp/prebuilt/prebuilt.c
#   Output : entry/src/main/libs/<abi>/libprebuilt.so
#
# This is NOT a mandatory build step (the .so files are committed),
# it exists so that anyone can verify the committed binaries match the source.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\scripts\build-prebuilt.ps1

$ErrorActionPreference = 'Stop'

# --- locate NDK clang -------------------------------------------------------
$candidates = @()

if ($env:DEVECO_SDK_HOME) {
    $candidates += (Join-Path $env:DEVECO_SDK_HOME 'default\openharmony\native')
}
$candidates += 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\native'

$native = $candidates | Where-Object { Test-Path (Join-Path $_ 'llvm\bin\clang.exe') } | Select-Object -First 1
if (-not $native) {
    Write-Host "ERROR: NDK not found. Set DEVECO_SDK_HOME to your DevEco 'sdk' directory." -ForegroundColor Red
    exit 1
}

$clang   = Join-Path $native 'llvm\bin\clang.exe'
$readelf = Join-Path $native 'llvm\bin\llvm-readelf.exe'
$sysroot = Join-Path $native 'sysroot'

$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$src = Join-Path $repoRoot 'entry\src\main\cpp\prebuilt\prebuilt.c'

if (-not (Test-Path $src)) {
    Write-Host "ERROR: source not found: $src" -ForegroundColor Red
    exit 1
}

Write-Host "NDK    : $native"
Write-Host "Source : $src"
Write-Host ""

# --- build matrix -----------------------------------------------------------
$targets = @(
    @{ Abi = 'arm64-v8a'; Triple = 'aarch64-linux-ohos' },
    @{ Abi = 'x86_64';    Triple = 'x86_64-linux-ohos'  }
)

$failed = $false
foreach ($t in $targets) {
    $abi    = $t.Abi
    $triple = $t.Triple
    $outDir = Join-Path $repoRoot "entry\src\main\libs\$abi"
    $outSo  = Join-Path $outDir 'libprebuilt.so'
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null

    $args = @(
        "--target=$triple",
        "--sysroot=$sysroot",
        '-shared', '-fPIC', '-O2',
        '-Wl,-soname,libprebuilt.so',
        '-o', $outSo,
        $src
    )
    & $clang @args
    if ($LASTEXITCODE -ne 0) {
        Write-Host "FAILED: $abi (clang exit $LASTEXITCODE)" -ForegroundColor Red
        $failed = $true
        continue
    }

    $size = (Get-Item $outSo).Length
    $machine = (& $readelf -h $outSo | Select-String 'Machine') -replace '.*Machine:\s*', ''
    $soname  = (& $readelf -d $outSo | Select-String 'SONAME') -replace '.*\[(.*)\].*', '$1'

    Write-Host ("OK  {0,-10} Machine={1,-36} SONAME={2,-18} size={3} B" -f $abi, $machine.Trim(), $soname.Trim(), $size)
}

Write-Host ""
if ($failed) {
    Write-Host "One or more ABIs failed." -ForegroundColor Red
    exit 1
}
Write-Host "All ABIs rebuilt. Verify the committed binaries are unchanged with: git status" -ForegroundColor Green
