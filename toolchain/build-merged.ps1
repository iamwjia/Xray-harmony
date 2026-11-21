# Build the merged kernel + forwarding layer as a single OHOS c-shared library.
#
# Why merged: one process can host only one Go runtime, so the kernel and the
# forwarding layer must live in the same .so instead of two.
#
# Source : _toolchain/merged (module "merged", replaces libxray with ../libXray-v26.7.28)
# Exports: Invoke / FreeString / StartTun2Socks
# Output : _toolchain/merged/build-<arch>/libmerg*.so  (not deployed yet)
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\toolchain\build-merged.ps1 -Arch arm64

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('arm64', 'x86_64')]
    [string]$Arch
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$go       = Join-Path $repoRoot '_toolchain\ohos-go-v1.26.5-beta1\bin\go.exe'
$srcDir   = Join-Path $repoRoot '_toolchain\merged'

$ndkCandidates = @()
if ($env:DEVECO_SDK_HOME) { $ndkCandidates += (Join-Path $env:DEVECO_SDK_HOME 'default\openharmony\native') }
$ndkCandidates += 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\native'
$native = $ndkCandidates | Where-Object { Test-Path (Join-Path $_ 'llvm\bin\clang.exe') } | Select-Object -First 1
if (-not $native) { Write-Host 'ERROR: NDK not found (set DEVECO_SDK_HOME).' -ForegroundColor Red; exit 1 }

$clang   = Join-Path $native 'llvm\bin\clang.exe'
$readelf = Join-Path $native 'llvm\bin\llvm-readelf.exe'
$sysroot = Join-Path $native 'sysroot'

switch ($Arch) {
    'arm64'  { $goarch = 'arm64'; $triple = 'aarch64-linux-ohos' }
    'x86_64' { $goarch = 'amd64'; $triple = 'x86_64-linux-ohos' }
}

$outDir = Join-Path $repoRoot "_toolchain\merged\build-$Arch"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$outSo = Join-Path $outDir 'libmerged.so'

$mapFile = Join-Path $outDir 'merged.map'
@"
{
  global:
    Invoke;
    FreeString;
    StartTun2Socks;
  local:
    *;
};
"@ | Set-Content -Path $mapFile -Encoding ascii

$env:GOOS        = 'openharmony'
$env:GOARCH      = $goarch
$env:CGO_ENABLED = '1'
$env:GOROOT      = Join-Path $repoRoot '_toolchain\ohos-go-v1.26.5-beta1'
$env:GOTOOLCHAIN = 'local'
$env:CC          = '"' + $clang + '" -target ' + $triple + ' "--sysroot=' + $sysroot + '" -D__MUSL__'
$env:CGO_CFLAGS  = '-ftls-model=global-dynamic'
# SONAME is mandatory: without it DT_NEEDED records the build-time path and the
# app fails to load at startup.
$env:CGO_LDFLAGS = '-ftls-model=global-dynamic -Wl,-soname,libmerged.so'
if (-not $env:GOPROXY) { $env:GOPROXY = 'https://goproxy.cn,direct' }
if (-not $env:GOSUMDB) { $env:GOSUMDB = 'sum.golang.google.cn' }
$env:GOFLAGS = '-mod=mod'

Write-Host "Arch   : $Arch (GOARCH=$goarch, triple=$triple)"
Write-Host "Source : $srcDir"
Write-Host "Output : $outSo"
Write-Host ''

Push-Location $srcDir
try {
    & $go build -trimpath -buildvcs=false -buildmode=c-shared `
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

$size = (Get-Item $outSo).Length
$exports = @(& $readelf --dyn-syms $outSo | Select-String 'FUNC\s+GLOBAL\s+DEFAULT\s+\d+\s' |
             ForEach-Object { ($_ -split '\s+')[-1] } | Where-Object { $_ -in @('Invoke', 'FreeString', 'StartTun2Socks') })
$soname = (& $readelf -d $outSo | Select-String 'SONAME') -replace '.*\[(.*)\].*', '$1'

Write-Host ("BUILD OK  {0:N0} bytes  soname={1}" -f $size, $soname) -ForegroundColor Green
Write-Host ("exports : " + ($exports -join ', '))
if ($exports.Count -ne 3) {
    Write-Host 'WARN: expected exactly 3 exported symbols' -ForegroundColor Yellow
}
