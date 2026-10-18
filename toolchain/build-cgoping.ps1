# Build the Go c-shared smoke library (libcgoping.so) for HarmonyOS / OpenHarmony.
#
# Purpose: one-command, reproducible build + 4-point ELF validation, for both ABIs.
#   Source   : toolchain/smoke/cgoping.go
#   Exports  : CGoPing / CGoFree  (rest hidden via version-script)
#   Output   : entry/src/main/libs/<abi>/libcgoping.so   (abi: arm64-v8a | x86_64)
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\toolchain\build-cgoping.ps1 -Arch arm64
#   powershell -ExecutionPolicy Bypass -File .\toolchain\build-cgoping.ps1 -Arch x86_64
#   ... -OutDir <dir>      # optional: also/instead copy to a custom dir (e.g. _toolchain/build)
#
# --- Two pitfalls already paid for (do not "simplify" them away) -------------
# 1) The NDK wrapper `aarch64-unknown-linux-ohos-clang` (and its x86_64 twin) is a
#    171-byte `#!/bin/sh` script -- Windows cannot exec it. We must call clang.exe
#    directly with the same flags the wrapper passes:
#        -target <triple>  --sysroot=<ndk>/sysroot  -D__MUSL__
# 2) PowerShell $env: does NOT persist across tool invocations; therefore the
#    environment is set and `go build` is invoked inside THIS single script run.
#
# --- Two artefact rules (paid for the hard way; see toolchain/BOOTSTRAP-RESULT.md) ---
# A) SONAME IS MANDATORY: without `-Wl,-soname,libcgoping.so` the linker writes the
#    build-time ABSOLUTE PATH into the consumer's DT_NEEDED and the app fails to load
#    its NAPI module at startup:
#      "Error loading shared library D:/projects/.../libs/x86_64/libcgoping.so"
# B) NEVER judge "was the OHOS fork used?" by runtime.GOOS: for the `openharmony`
#    target the fork intentionally reports GOOS == "linux"
#    (internal/goos/gengoos.go emits `const GOOS = "linux"`). The only reliable marker
#    is a `//go:build openharmony` tag probe (toolchain/smoke/tag_*.go -> buildtag).

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('arm64', 'x86_64')]
    [string]$Arch,

    [string]$OutDir = ''
)

$ErrorActionPreference = 'Stop'

# --- locate toolchain pieces ------------------------------------------------
$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$go       = Join-Path $repoRoot '_toolchain\ohos-go-v1.26.5-beta1\bin\go.exe'
$srcDir   = Join-Path $repoRoot 'toolchain\smoke'
$srcFile  = 'cgoping.go'

$ndkCandidates = @()
if ($env:DEVECO_SDK_HOME) { $ndkCandidates += (Join-Path $env:DEVECO_SDK_HOME 'default\openharmony\native') }
$ndkCandidates += 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\native'
$native = $ndkCandidates | Where-Object { Test-Path (Join-Path $_ 'llvm\bin\clang.exe') } | Select-Object -First 1
if (-not $native) { Write-Host 'ERROR: NDK not found (set DEVECO_SDK_HOME).' -ForegroundColor Red; exit 1 }

$clang   = Join-Path $native 'llvm\bin\clang.exe'
$readelf = Join-Path $native 'llvm\bin\llvm-readelf.exe'
$sysroot = Join-Path $native 'sysroot'

foreach ($p in @($go, $clang, $readelf)) {
    if (-not (Test-Path $p)) { Write-Host "ERROR: missing $p" -ForegroundColor Red; exit 1 }
}
if (-not (Test-Path (Join-Path $srcDir $srcFile))) {
    Write-Host "ERROR: source not found: $srcDir\$srcFile" -ForegroundColor Red; exit 1
}

# --- per-arch mapping -------------------------------------------------------
switch ($Arch) {
    'arm64'  { $goarch = 'arm64'; $abi = 'arm64-v8a'; $triple = 'aarch64-linux-ohos'; $tlsReloc = 'R_AARCH64_TLSDESC' }
    'x86_64' { $goarch = 'amd64'; $abi = 'x86_64';    $triple = 'x86_64-linux-ohos';  $tlsReloc = 'R_X86_64_TLSDESC' }
}

$outAbiDir = Join-Path $repoRoot "entry\src\main\libs\$abi"
New-Item -ItemType Directory -Force -Path $outAbiDir | Out-Null
$outSo = Join-Path $outAbiDir 'libcgoping.so'

# version-script: export exactly CGoPing / CGoFree
$mapFile = Join-Path $repoRoot "_toolchain\cgoping.map"
New-Item -ItemType Directory -Force -Path (Split-Path $mapFile) | Out-Null
@"
{
  global:
    CGoPing;
    CGoFree;
  local:
    *;
};
"@ | Set-Content -Path $mapFile -Encoding ascii

# --- environment (same script run as the build, see pitfall 2) --------------
$env:GOOS       = 'openharmony'
$env:GOARCH     = $goarch
$env:CGO_ENABLED = '1'
$env:GOROOT     = Join-Path $repoRoot '_toolchain\ohos-go-v1.26.5-beta1'
$env:CC         = '"' + $clang + '" -target ' + $triple + ' "--sysroot=' + $sysroot + '" -D__MUSL__'
$env:CGO_CFLAGS  = '-ftls-model=global-dynamic'
$env:CGO_LDFLAGS = '-ftls-model=global-dynamic -Wl,-soname,libcgoping.so'

Write-Host "Arch   : $Arch  (GOARCH=$goarch, ABI=$abi, triple=$triple)"
Write-Host "Go     : $go"
Write-Host "Clang  : $clang"
Write-Host "Output : $outSo"
Write-Host ''

Push-Location $srcDir
try {
    # SONAME is mandatory: without it the linker records the *build-time absolute path*
    # in DT_NEEDED of the consumer (libentry.so), and the library fails to load after
    # install ("Error loading shared library D:/.../libs/x86_64/libcgoping.so").
    # It is passed through CGO_LDFLAGS (see above) so that the quoting stays simple.
    & $go build -buildmode=c-shared `
        -ldflags "-extldflags=-Wl,--version-script=$($mapFile -replace '\\','/')" `
        -o $outSo .
    $buildExit = $LASTEXITCODE
} finally {
    Pop-Location
}

if ($buildExit -ne 0 -or -not (Test-Path $outSo)) {
    Write-Host "FAILED: go build exit=$buildExit" -ForegroundColor Red
    exit 1
}

if ($OutDir -ne '') {
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    Copy-Item -Force $outSo (Join-Path $OutDir 'libcgoping.so')
    Copy-Item -Force (Join-Path $outAbiDir 'libcgoping.h') (Join-Path $OutDir 'libcgoping.h') -ErrorAction SilentlyContinue
    Write-Host "Copied to: $OutDir"
}

# --- 4-point validation -----------------------------------------------------
$hdr      = & $readelf -h $outSo
$type     = ($hdr | Select-String 'Type:')     -replace '.*Type:\s*', ''
$machine  = ($hdr | Select-String 'Machine:')  -replace '.*Machine:\s*', ''
$ptTls    = (& $readelf -l $outSo | Select-String '^\s*TLS\s') | Select-Object -First 1
$tlsCount = (& $readelf -r $outSo | Select-String $tlsReloc).Count
$exports  = @(& $readelf --dyn-syms $outSo | Select-String 'FUNC\s+GLOBAL\s+DEFAULT\s+\d+\s' |
              ForEach-Object { ($_ -split '\s+')[-1] })
$needed   = @(& $readelf -d $outSo | Select-String 'NEEDED' |
              ForEach-Object { if ($_ -match '\[(.*)\]') { $matches[1] } })

$ok = $true
function Check($name, $pass, $detail) {
    if ($pass) { Write-Host ("  [PASS] {0,-28} {1}" -f $name, $detail) -ForegroundColor Green }
    else       { Write-Host ("  [FAIL] {0,-28} {1}" -f $name, $detail) -ForegroundColor Red; $script:ok = $false }
}

Write-Host ''
Write-Host "Validation (llvm-readelf):"
Check 'ELF type / machine'  (($type.Trim() -eq 'DYN (Shared object file)') -or ($type.Trim() -eq 'DYN'))  "Type=$( $type.Trim() ) Machine=$( $machine.Trim() )"
Check 'PT_TLS present'      ($null -ne $ptTls)                                                          $(if ($ptTls) { 'TLS segment found' } else { 'no TLS segment' })
Check "$tlsReloc count"     ($tlsCount -ge 1)                                                           "$tlsCount"
Check 'exported == 2'       (($exports.Count -eq 2) -and ($exports -contains 'CGoPing') -and ($exports -contains 'CGoFree'))  ($exports -join ',')
Check 'NEEDED only libc.so' (($needed.Count -eq 1) -and ($needed[0] -eq 'libc.so'))                      ($needed -join ',')

Write-Host ''
if (-not $ok) { Write-Host 'VALIDATION FAILED' -ForegroundColor Red; exit 1 }
Write-Host ("OK  {0} -> {1}  ({2} bytes)" -f $Arch, $outSo, (Get-Item $outSo).Length) -ForegroundColor Green
