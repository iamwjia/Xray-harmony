# Build libXray (real Xray kernel) as an OHOS c-shared library.
#
# Source   : _toolchain/libXray-v26.7.28 (pinned tag v26.7.28; NOT tracked by git)
# Exports  : CGoInvoke / CGoFree  (everything else hidden via version-script)
# Output   : entry/src/main/libs/<abi>/libxray.so   (abi: arm64-v8a | x86_64)
#            _toolchain/build-<arch>/libxray.so     (unstripped copy for inspection)
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\toolchain\build-libxray.ps1 -Arch arm64
#   powershell -ExecutionPolicy Bypass -File .\toolchain\build-libxray.ps1 -Arch x86_64
#
# Prerequisites (already verified in BOOTSTRAP-RESULT.md):
#   * OHOS Go fork bootstrap done (_toolchain/ohos-go-v1.26.5-beta1/bin/go.exe)
#   * module deps downloaded with a reachable GOPROXY. proxy.golang.org is NOT
#     reachable here; use:  GOPROXY=https://goproxy.cn,direct  GOSUMDB=sum.golang.google.cn
#
# Artefact rules (paid for the hard way):
#   A) SONAME is mandatory, otherwise DT_NEEDED of libentry.so records the
#      build-time absolute path and the app fails to load at startup.
#   B) runtime.GOOS is "linux" even on the openharmony target -> never use it to
#      tell whether the fork was used; use a //go:build openharmony probe.

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('arm64', 'x86_64')]
    [string]$Arch
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$go       = Join-Path $repoRoot '_toolchain\ohos-go-v1.26.5-beta1\bin\go.exe'
$srcDir   = Join-Path $repoRoot '_toolchain\libXray-v26.7.28'

$ndkCandidates = @()
if ($env:DEVECO_SDK_HOME) { $ndkCandidates += (Join-Path $env:DEVECO_SDK_HOME 'default\openharmony\native') }
$ndkCandidates += 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\native'
$native = $ndkCandidates | Where-Object { Test-Path (Join-Path $_ 'llvm\bin\clang.exe') } | Select-Object -First 1
if (-not $native) { Write-Host 'ERROR: NDK not found (set DEVECO_SDK_HOME).' -ForegroundColor Red; exit 1 }

$clang   = Join-Path $native 'llvm\bin\clang.exe'
$readelf = Join-Path $native 'llvm\bin\llvm-readelf.exe'
$sysroot = Join-Path $native 'sysroot'

if (-not (Test-Path (Join-Path $srcDir 'go.mod'))) {
    Write-Host "ERROR: libXray source not found at $srcDir (git clone --branch v26.7.28)" -ForegroundColor Red
    exit 1
}

switch ($Arch) {
    'arm64'  { $goarch = 'arm64'; $abi = 'arm64-v8a'; $triple = 'aarch64-linux-ohos'; $tlsReloc = 'R_AARCH64_TLSDESC' }
    'x86_64' { $goarch = 'amd64'; $abi = 'x86_64';    $triple = 'x86_64-linux-ohos';  $tlsReloc = 'R_X86_64_TLSDESC' }
}

$outAbiDir = Join-Path $repoRoot "entry\src\main\libs\$abi"
$outKeep   = Join-Path $repoRoot "_toolchain\build-$Arch"
New-Item -ItemType Directory -Force -Path $outAbiDir, $outKeep | Out-Null
$outSo = Join-Path $outAbiDir 'libxray.so'

# version-script: export exactly CGoInvoke / CGoFree
$mapFile = Join-Path $repoRoot '_toolchain\libxray.map'
@"
{
  global:
    CGoInvoke;
    CGoFree;
  local:
    *;
};
"@ | Set-Content -Path $mapFile -Encoding ascii

$env:GOOS        = 'openharmony'
$env:GOARCH      = $goarch
$env:CGO_ENABLED = '1'
$env:GOROOT      = Join-Path $repoRoot '_toolchain\ohos-go-v1.26.5-beta1'
$env:CC          = '"' + $clang + '" -target ' + $triple + ' "--sysroot=' + $sysroot + '" -D__MUSL__'
$env:CGO_CFLAGS  = '-ftls-model=global-dynamic'
$env:CGO_LDFLAGS = '-ftls-model=global-dynamic -Wl,-soname,libxray.so'
if (-not $env:GOPROXY) { $env:GOPROXY = 'https://goproxy.cn,direct' }
if (-not $env:GOSUMDB) { $env:GOSUMDB = 'sum.golang.google.cn' }
$env:GOFLAGS = '-mod=mod'

Write-Host "Arch   : $Arch  (GOARCH=$goarch, ABI=$abi, triple=$triple)"
Write-Host "Source : $srcDir"
Write-Host "Output : $outSo"
Write-Host ''

Push-Location $srcDir
try {
    & $go build -trimpath -buildvcs=false -buildmode=c-shared `
        -ldflags "-extldflags=-Wl,--version-script=$($mapFile -replace '\\','/')" `
        -o $outSo ./cgo_bridge
    $buildExit = $LASTEXITCODE
} finally {
    Pop-Location
}

if ($buildExit -ne 0 -or -not (Test-Path $outSo)) {
    Write-Host "FAILED: go build exit=$buildExit" -ForegroundColor Red
    exit 1
}
Copy-Item -Force $outSo (Join-Path $outKeep 'libxray.so')

# --- validation -------------------------------------------------------------
$hdr      = & $readelf -h $outSo
$type     = ($hdr | Select-String 'Type:')    -replace '.*Type:\s*', ''
$machine  = ($hdr | Select-String 'Machine:') -replace '.*Machine:\s*', ''
$ptTls    = (& $readelf -l $outSo | Select-String '^\s*TLS\s') | Select-Object -First 1
$tlsCount = (& $readelf -r $outSo | Select-String $tlsReloc).Count
$exports  = @(& $readelf --dyn-syms $outSo | Select-String 'FUNC\s+GLOBAL\s+DEFAULT\s+\d+\s' |
              ForEach-Object { ($_ -split '\s+')[-1] })
$needed   = @(& $readelf -d $outSo | Select-String 'NEEDED' | ForEach-Object { if ($_ -match '\[(.*)\]') { $matches[1] } })
$soname   = (& $readelf -d $outSo | Select-String 'SONAME') -replace '.*\[(.*)\].*', '$1'

$ok = $true
function Check($name, $pass, $detail) {
    if ($pass) { Write-Host ("  [PASS] {0,-26} {1}" -f $name, $detail) -ForegroundColor Green }
    else       { Write-Host ("  [FAIL] {0,-26} {1}" -f $name, $detail) -ForegroundColor Red; $script:ok = $false }
}

Write-Host ''
Write-Host 'Validation (llvm-readelf):'
Check 'ELF type / machine'  (($type.Trim() -eq 'DYN (Shared object file)') -or ($type.Trim() -eq 'DYN')) "Type=$($type.Trim()) Machine=$($machine.Trim())"
Check 'PT_TLS present'      ($null -ne $ptTls) $(if ($ptTls) { 'TLS segment found' } else { 'no TLS segment' })
Check "$tlsReloc count"     ($tlsCount -ge 1) "$tlsCount"
Check 'exported == 2'       (($exports.Count -eq 2) -and ($exports -contains 'CGoInvoke') -and ($exports -contains 'CGoFree')) ($exports -join ',')
Check 'NEEDED only libc.so' (($needed.Count -eq 1) -and ($needed[0] -eq 'libc.so')) ($needed -join ',')
Check 'SONAME'              ($soname.Trim() -eq 'libxray.so') $soname.Trim()

Write-Host ''
if (-not $ok) { Write-Host 'VALIDATION FAILED' -ForegroundColor Red; exit 1 }
Write-Host ("OK  {0} -> {1}  ({2} bytes)" -f $Arch, $outSo, (Get-Item $outSo).Length) -ForegroundColor Green
