# OHOS Go å·¥å…·é“¾è‡ªä¸¾ + `cgoping.so` ç¼–è¯‘éªŒè¯ç»“æœ

> ä»»åŠ¡ï¼šE6ï½œæ‰§è¡Œè€…ï¼šsolution-architectï½œæ—¥æœŸï¼š2026-10-18
> ç»“è®ºï¼š**å·¥å…·é“¾è‡ªä¸¾æˆåŠŸï¼Œ`cgoping.so` ç¼–è¯‘æˆåŠŸï¼Œreadelf å››éªŒå…¨éƒ¨é€šè¿‡**ï¼ˆå¯¼å‡ºç¬¦å·éœ€åŠ  version-script æ‰æ»¡è¶³"åªæœ‰ CGoPing/CGoFree"ï¼‰ã€‚
> äº§ç‰©ç›®å½•ï¼š`_toolchain\bootstrap-tmp\`ï¼ˆbootstrapï¼‰ã€`_toolchain\ohos-go-v1.26.5-beta1\`ï¼ˆè‡ªå»ºå·¥å…·é“¾ï¼‰ã€`_toolchain\build\`ï¼ˆso ä¸ mapï¼‰ã€`_toolchain\bootstrap-make.log`ï¼ˆæ„å»ºæ—¥å¿—ï¼‰

---

## Step 1 â€” è§£å‹ bootstrap âœ…

```
PS> Expand-Archive -Path "D:\projects\xray-harmony\_toolchain\downloads\go1.25.14.windows-amd64.zip" -DestinationPath "D:\projects\xray-harmony\_toolchain\bootstrap-tmp" -Force
PS> & "D:\projects\xray-harmony\_toolchain\bootstrap-tmp\go\bin\go.exe" version
go version go1.25.14 windows/amd64
```

è¾“å‡ºä¸æœŸæœ›ä¸€è‡´ï¼ˆ`go1.25.14` â‰¥ fork è¦æ±‚çš„ `minBootstrap=go1.24.6`ï¼‰ã€‚

## Step 2 â€” è‡ªä¸¾ OHOS å·¥å…·é“¾ âœ…ï¼ˆ`make.bat` ç›´æ¥å¯ç”¨ï¼Œ**ä¸éœ€è¦ Git Bash**ï¼‰

```
PS> $env:GOROOT_BOOTSTRAP = "D:\projects\xray-harmony\_toolchain\bootstrap-tmp\go"
PS> cd D:\projects\xray-harmony\_toolchain\ohos-go-v1.26.5-beta1\src
PS> .\make.bat *> D:\projects\xray-harmony\_toolchain\bootstrap-make.log
EXITCODE=0
```

æ—¥å¿—å°¾æ®µï¼ˆçœŸå®è¾“å‡ºï¼‰ï¼š

```
Building Go cmd/dist using D:\projects\xray-harmony\_toolchain\bootstrap-tmp\go. (go1.25.14 windows/amd64)
Building Go toolchain1 using D:\projects\xray-harmony\_toolchain\bootstrap-tmp\go.
Building Go bootstrap cmd/go (go_bootstrap) using Go toolchain1.
Building Go toolchain2 using go_bootstrap and Go toolchain1.
Building Go toolchain3 using go_bootstrap and Go toolchain2.
Building packages and commands for windows/amd64.
---
Installed Go for windows/amd64 in D:\projects\xray-harmony\_toolchain\ohos-go-v1.26.5-beta1
Installed commands in D:\projects\xray-harmony\_toolchain\ohos-go-v1.26.5-beta1\bin
*** You need to add D:\projects\xray-harmony\_toolchain\ohos-go-v1.26.5-beta1\bin to your PATH.
```

> **å¯¹æ—¢æœ‰å‡è®¾çš„ä¿®æ­£**ï¼šä»»åŠ¡å¡é‡Œé¢„åˆ¤"Windows ä¸Š `make.bat` å¯èƒ½éœ€è¦ sh/gcc"ï¼Œå®æµ‹**ä¸éœ€è¦**â€”â€”å®¿ä¸»ä¾§åªç¼– `windows/amd64` çš„ Go å·¥å…·é“¾ï¼Œæœªè§¦åŠ cgo äº¤å‰ç¼–è¯‘å™¨ï¼›Git Bash è·¯å¾„**æ²¡æœ‰ç”¨åˆ°**ã€‚

## Step 3 â€” ä¸‰è¿éªŒè¯ âœ…

```
PS> & $go version
go version go1.26.5 windows/amd64

PS> & $go env GOOS GOARCH GOROOT
windows
amd64
D:\projects\xray-harmony\_toolchain\ohos-go-v1.26.5-beta1

PS> & $go tool dist list | Select-String openharmony

openharmony/amd64
openharmony/arm64
```

`openharmony/arm64` å‡ºç°åœ¨ `dist list` â‡’ fork çš„ç›®æ ‡ç«¯å£å·²ç”Ÿæ•ˆï¼ˆè¿™æ˜¯"èƒ½äº¤å‰ç¼–è¯‘åˆ°é¸¿è’™"çš„å‰æï¼‰ã€‚

## Step 4 â€” ç¼–è¯‘ `cgoping.so`ï¼ˆopenharmony/arm64ï¼‰âœ…

### 4.1 å…³é”®å¡ç‚¹ï¼šNDK çš„ `aarch64-unknown-linux-ohos-clang` æ˜¯ **sh è„šæœ¬ï¼Œä¸æ˜¯ exe**

```
æ–‡ä»¶åå­˜åœ¨ä½†æ—  .exeï¼šaarch64-unknown-linux-ohos-clangï¼ˆ171 å­—èŠ‚ï¼‰
å†…å®¹ï¼š#!/bin/sh ... exec $SOURCE/clang -target aarch64-linux-ohos --sysroot=$SOURCE/../../sysroot -D__MUSL__ "$@"
```

Go åœ¨ Windows ä¸Šæ— æ³•ç›´æ¥æ‰§è¡Œè¯¥è„šæœ¬ â‡’ **å¿…é¡»æ”¹ç”¨ `clang.exe` å¹¶æ˜¾å¼ä¼ ç­‰ä»·å‚æ•°**ï¼ˆå†…å®¹ç…§æŠ„è„šæœ¬é‡Œçš„å››ä¸ªå‚æ•°ï¼‰ã€‚

å…ˆç”¨æœ€å° C æ–‡ä»¶éªŒè¯ clang ç›´è¿å¯ç”¨ï¼š

```
& "$ndk\clang.exe" -target aarch64-linux-ohos "--sysroot=$sysroot" -D__MUSL__ -c t.c -o t.o
EXIT=0
llvm-readelf -h t.o â†’ Class: ELF64 / Machine: AArch64
```

### 4.2 å®é™…æ„å»ºå‘½ä»¤ï¼ˆä¸€æ¬¡æˆåŠŸï¼Œ`EXIT=0`ï¼‰

```powershell
$env:GOOS="openharmony"; $env:GOARCH="arm64"; $env:CGO_ENABLED="1"
$env:GOROOT="D:\projects\xray-harmony\_toolchain\ohos-go-v1.26.5-beta1"
$env:CC = '"C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\native\llvm\bin\clang.exe" -target aarch64-linux-ohos "--sysroot=C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\native\sysroot" -D__MUSL__'
$env:CGO_CFLAGS="-ftls-model=global-dynamic"
$env:CGO_LDFLAGS="-ftls-model=global-dynamic"
cd D:\projects\xray-harmony\toolchain\smoke
& $go build -buildmode=c-shared -o "D:\projects\xray-harmony\_toolchain\build\cgoping.so" cgoping.go
```

äº§ç‰©ï¼š`cgoping.so` **2,635,744 å­—èŠ‚**ã€`cgoping.h` 2,397 å­—èŠ‚ã€‚

## Step 5 â€” readelf å››éªŒ

### 5.1 é»˜è®¤æ„å»ºï¼ˆæ—  version-scriptï¼‰ï¼š**ä¸‰é€šè¿‡ã€ä¸€ä¸é€šè¿‡**

| æ£€æŸ¥é¡¹ | ç»“æœ | å®æµ‹ |
|---|---|---|
| â‘  `PT_TLS` å­˜åœ¨ | âœ… | `TLS 0x1203e0 ... R 0x8` |
| â‘¡ `R_AARCH64_TLSDESC` é‡å®šä½å­˜åœ¨ | âœ… | `R_AARCH64_TLSDESC` å…± **1 æ¡** |
| â‘¢ å¯¼å‡ºç¬¦å·**åªæœ‰** `CGoPing`/`CGoFree` | **âŒ** | `GLOBAL DEFAULT` å·²å®šä¹‰å‡½æ•° **48 ä¸ª**ï¼Œå…¶ä¸­ **44 ä¸ªæ˜¯ cgo è¿è¡Œæ—¶ç¬¦å·**ï¼ˆ`_cgo_*`ã€`x_cgo_*`ã€`crosscall2` ç­‰ï¼‰ï¼Œ`CGoPing`/`CGoFree` åªæ˜¯å…¶ä¸­ä¸¤ä¸ª |
| â‘£ `DT_NEEDED` ä»…ç³»ç»Ÿåº“ | âœ… | åªæœ‰ `libc.so`ï¼ˆæ—  glibcã€æ—  `libc++_shared`ï¼‰ |
| é™„ï¼šELF å¤´ | âœ… | `Type: DYN (Shared object file)` / `Machine: AArch64` |

### 5.2 åŠ  version-script åï¼š**å››éªŒå…¨é€šè¿‡** âœ…

æ–°å¢ `_toolchain\build\cgoping.map`ï¼š

```
{
  global:
    CGoPing;
    CGoFree;
  local:
    *;
};
```

é‡å»ºï¼š

```powershell
& $go build -buildmode=c-shared -ldflags "-extldflags=-Wl,--version-script=D:/projects/xray-harmony/_toolchain/build/cgoping.map" -o "...\cgoping-vs.so" cgoping.go
EXIT=0
```

å¤éªŒç»“æœï¼š

```
=== å¯¼å‡ºç¬¦å· ===
  47: 000000000011f014  80 FUNC GLOBAL DEFAULT 13 CGoPing
  48: 000000000011f064  88 FUNC GLOBAL DEFAULT 13 CGoFree
=== TLSDESC æ¡æ•° === 1
=== PT_TLS === TLS 0x11f8a0 ... R 0x8
=== NEEDED === Shared library: [libc.so]
```

â‡’ å››é¡¹å…¨è¿‡ï¼Œ**`cgoping-vs.so` ä¸ºæœ¬æ­¥çš„æ­£å¼éªŒæ”¶äº§ç‰©**ã€‚

---

## ç»“è®ºä¸è¦ç‚¹

1. **å·¥å…·é“¾å¯ç”¨**ï¼š`make.bat` åœ¨ Windows åŸç”Ÿè‡ªä¸¾æˆåŠŸï¼ˆ18 åˆ†é’Ÿå†…ï¼‰ï¼Œå®¿ä¸» `go1.26.5 windows/amd64`ï¼Œ`dist list` å« `openharmony/arm64`ã€‚
2. **äº¤å‰ç¼–è¯‘å¯ç”¨**ï¼š`GOOS=openharmony GOARCH=arm64 CGO_ENABLED=1` + NDK `clang.exe`ï¼ˆæ˜¾å¼ `-target`/`--sysroot`/`-D__MUSL__`ï¼‰+ `-ftls-model=global-dynamic` ä¸€æ¬¡äº§å‡º `DYN`/`AArch64` å…±äº«åº“ã€‚
3. **TLS é“¾è·¯å·²éªŒè¯**ï¼š`PT_TLS` æ®µ + `R_AARCH64_TLSDESC` é‡å®šä½åŒæ—¶å­˜åœ¨ï¼Œè¿™æ­£æ˜¯ç»•è¿‡ musl IE-TLS é™åˆ¶çš„å…³é”®è¯æ®ã€‚
4. **ä¾èµ–å¹²å‡€**ï¼š`DT_NEEDED` ä»… `libc.so`ï¼Œæ²¡æœ‰æŠŠå®¿ä¸»åº“æˆ– glibc å¸¦è¿›äº§ç‰©ã€‚
5. **å¯¼å‡ºç¬¦å·é»˜è®¤è¿‡å®½ï¼ˆé‡è¦ï¼‰**ï¼šä¸åŠ çº¦æŸæ—¶ 44 ä¸ª cgo è¿è¡Œæ—¶ç¬¦å·å¯¹å¤–å¯è§ã€‚**ç»“è®ºï¼šæ­£å¼äº§ç‰©å¿…é¡»åŠ  version-script**ï¼ˆä¸ libXray çš„ `global: CGoInvoke; CGoFree; local: *;` åšæ³•ä¸€è‡´ï¼‰ï¼Œå¦åˆ™ç¬¦å·é¢è¿‡å¤§ã€ä¸”å¯èƒ½ä¸å®¿ä¸»ç¬¦å·å†²çªã€‚

## å¡ç‚¹ä¸è§„é¿ï¼ˆå†™è¿›åç»­è„šæœ¬ï¼‰

| å¡ç‚¹ | ç°è±¡ | è§„é¿ |
|---|---|---|
| **NDK wrapper æ˜¯ sh è„šæœ¬** | ç›´æ¥æŠŠå®ƒå½“ `CC` ä¼šåœ¨ Windows ä¸Šå¤±è´¥ï¼ˆæ— æ³•æ‰§è¡Œ shï¼‰ | ç”¨ `clang.exe` + æ˜¾å¼ `-target aarch64-linux-ohos --sysroot=<ndk>/sysroot -D__MUSL__`ï¼ˆå››ä¸ªå‚æ•°ç…§æŠ„è„šæœ¬ï¼‰ |
| **PowerShell ç¯å¢ƒå˜é‡ä¸è·¨è°ƒç”¨ä¿ç•™** | å•ç‹¬ä¸€æ¬¡ `go build` æŠ¥ `go: no Go source files` | ç¯å¢ƒå˜é‡ä¸ `go build` **å¿…é¡»åœ¨åŒä¸€æ¬¡è°ƒç”¨å†…**è®¾ç½®å¹¶æ‰§è¡Œï¼ˆå·²å†™è¿›å»ºè®®è„šæœ¬ï¼‰ |
| **é»˜è®¤å¯¼å‡º 44 ä¸ª cgo ç¬¦å·** | å››éªŒç¬¬ 3 é¡¹ä¸é€šè¿‡ | åŠ  `-ldflags "-extldflags=-Wl,--version-script=<map>"` |

## ä¸‹ä¸€æ­¥

1. æŠŠ Step 4/5 çš„å‘½ä»¤å›ºåŒ–è¿› `toolchain\build-cgoping.ps1`ï¼ˆå« version-scriptã€ç¯å¢ƒå˜é‡ä¸€æ¬¡æ€§è®¾ç½®ï¼‰ï¼Œé¿å…é‡å¤æ‰‹å·¥æ“ä½œã€‚
2. çœŸæœºä¾§æœªåšï¼ˆæœ¬æ­¥ä¸æ¶‰åŠï¼‰ï¼š`hdc file send cgoping-vs.so` + NAPI åŠ è½½ + è°ƒ `CGoPing` å±åç»­ `P-03` èŒƒå›´ã€‚
3. ä¸‹ä¸€æ­¥çœŸæ­£çš„æ„å»ºç›®æ ‡æ˜¯ **libXrayï¼ˆ`v26.7.28`ï¼Œç¦æ­¢ mainï¼‰**ï¼šæœ¬æ­¥å·²éªŒè¯çš„ `CC`/`-ftls-model`/version-script ä¸‰ä»¶å¥—å¯ç›´æ¥å¤ç”¨ï¼Œä½†éœ€é¢å¤–å¤„ç†ï¼ˆaï¼‰Xray JSON é…ç½®è§£æä¾èµ–çš„åŒ…ä½“ç§¯ã€ï¼ˆbï¼‰`readelf` æ ¡éªŒ `DT_NEEDED` ä¸å¾—å¼•å…¥ `libc++_shared` ä¹‹å¤–çš„éç³»ç»Ÿåº“ã€‚
4. æ— ã€éœ€äººå·¥ã€‘é¡¹ï¼šæœ¬æ­¥æ‰€æœ‰é˜»å¡ç‚¹å‡å·²è‡ªè¡Œè§£å†³ã€‚

## äº§ç‰©æ¸…å•

| æ–‡ä»¶ | è¯´æ˜ |
|---|---|
| `_toolchain\ohos-go-v1.26.5-beta1\bin\go.exe` | è‡ªå»º OHOS Go å·¥å…·é“¾ï¼ˆgo1.26.5ï¼‰ |
| `_toolchain\bootstrap-make.log` | è‡ªä¸¾å®Œæ•´æ—¥å¿— |
| `_toolchain\build\cgoping.so` / `.h` | é»˜è®¤æ„å»ºäº§ç‰©ï¼ˆç¬¦å·é¢è¿‡å®½ï¼Œä½œå¯¹ç…§ï¼‰ |
| `_toolchain\build\cgoping-vs.so` | **åŠ  version-script çš„æ­£å¼éªŒæ”¶äº§ç‰©** |
| `_toolchain\build\cgoping.map` | å¯¼å‡ºç¬¦å·çº¦æŸè„šæœ¬ |

---

## M5£ºGo `.so` ÔÚ OHOS ½ø³ÌÄÚÊµ²â£¨E7£©

> Ä¿±ê£ºÖ¤Ã÷ **Go runtime ÄÜÔÚ OHOS Ó¦ÓÃ½ø³ÌÄÚ³õÊ¼»¯²¢Ö´ĞĞ cgo µ÷ÓÃ**£¨`P-03` ºËĞÄ¼ÙÉè£©£¬ÓÃ x86_64 Ä£ÄâÆ÷¼´¿É£¬ÎŞĞèÕæ»ú¡£
> ½áÂÛ£º**âœ…\ ³ÉÁ¢**£¨`buildtag=openharmony` + `cside=cgoping-c-side-ok`£©£¬²¢Ë³´ø²È³öÁ½Ìõ»á¿ÓËÀºóÀ´ÕßµÄÓ²¹æÔò¡£

### 1. ¹¹½¨£¨`toolchain/build-cgoping.ps1 -Arch x86_64`£©

```
Arch   : x86_64  (GOARCH=amd64, ABI=x86_64, triple=x86_64-linux-ohos)
Validation (llvm-readelf):
  [PASS] ELF type / machine           Type=DYN (Shared object file) Machine=Advanced Micro Devices X86-64
  [PASS] PT_TLS present               TLS segment found
  [PASS] R_X86_64_TLSDESC count       1
  [PASS] exported == 2                CGoPing,CGoFree
  [PASS] NEEDED only libc.so          libc.so
SONAME: [libcgoping.so]
```

½Å±¾ÒÑÄÚÖÃ£º`-Arch arm64|x86_64`¡¢version-script¡¢SONAME¡¢ËÄÑé£¨°´¼Ü¹¹Ñ¡ `R_AARCH64_TLSDESC` / `R_X86_64_TLSDESC`£©¡£

### 2. ×°½øÓ¦ÓÃ²¢ÕæÊµµã»÷£¨Ä£ÄâÆ÷ `127.0.0.1:5555`£¬API 26£©

HAP ÄÚÈ·ÈÏ£º`libs/x86_64/libcgoping.so`£¨1,379,976 B£¬strip ºó£©+ `libentry.so` µÄ `DT_NEEDED` Îª `libcgoping.so`£¨**²»ÊÇ¾ø¶ÔÂ·¾¶**£©¡£

`uitest dumpLayout` ¡ú `M5: call Go CGoPing() :: [116,1159][1200,1299]` ¡ú `uitest uiInput click 658 1229`£º

```
10-18 12:54:18.371 20363 20363 I A00001/XVPN_POC: M5 clicked
10-18 12:54:18.371 20363 20363 I A00001/XVPN_POC: M5 result={"success":true,"data":{
  "marker":"pong","version":"cgoping/0.1 (e2-minimal)","goos":"linux","goarch":"amd64",
  "buildtag":"openharmony","cside":"cgoping-c-side-ok"}}
```

½ø³Ì´æ»î£¨`ps` ÓĞ PID 20363£©£¬**ÎŞ SIGSEGV**¡£

### 3. ÅĞ¶¨

| ¼ì²é | ½áÂÛ |
|---|---|
| `dlopen("libcgoping.so")` ³É¹¦ | âœ…£¨ÈÕÖ¾ÎŞ\ dlopen Ê§°Ü·ÖÖ§£© |
| `dlsym("CGoPing")` / `dlsym("CGoFree")` | âœ…£¨µ÷ÓÃ³É¹¦¡¢·µ»ØÖµ±»\ `CGoFree` ÊÍ·ÅºóÈÔÕıÈ·£© |
| Go runtime ÔÚ OHOS ½ø³ÌÄÚ³õÊ¼»¯ | âœ…£¨ÄÜ·µ»Ø\ `runtime.GOARCH=amd64` µÈÔËĞĞÊ±ĞÅÏ¢£© |
| È·ÊµÓÃ OHOS fork ±àÒë | âœ…\ `buildtag=openharmony`£¨`//go:build openharmony` Ì½Õë£© |
| C¡úGo¡úC Ë«Ïòµ÷ÓÃÁ´ | âœ…\ `cside=cgoping-c-side-ok`£¨Go ²àµ÷ÓÃ C ²à `c_side_marker()`£© |
| ±ÀÀ£ | âŒ\ ÎŞ |

â‡’\ **`P-03` Ç°°ë£¨so ¼ÓÔØ + Go runtime ³õÊ¼»¯ + cgo µ÷ÓÃ£©ÔÚ OHOS ÉÏ³ÉÁ¢¡£**

---

## âš \ï¸\ M5 ²È³öÀ´µÄÁ½ÌõÓ²¹æÔò£¨±È"ÄÜ±à³ö so"¸üÈİÒ×¿ÓÈË£©

### ¹æÔò A£º`runtime.GOOS` **²»ÄÜ**ÓÃÀ´ÅĞ¶ÏÊÇ·ñÓÃÁË OHOS fork
¸Ã fork ¶Ô `openharmony` Ä¿±ê**ºã¶¨ÉÏ±¨** `GOOS == "linux"`£º

```go
// src/internal/goos/gengoos.go
if target == "openharmony" {
    fmt.Fprintf(&buf, "const GOOS = `linux`\n\n")   // ¡û ¿ÌÒâÈç´Ë
}

// src/internal/goos/zgoos_openharmony.go
const GOOS = `linux`
const IsOpenharmony = 1
```

â‡’\ ¿´µ½ `goos=linux` **²»´ú±í¹¤¾ßÁ´ÓÃ´í**¡£Î¨Ò»¿É¿¿ÅĞ¾İÊÇ `//go:build openharmony` ±àÒë±êÇ©Ì½Õë£¨`toolchain/smoke/tag_openharmony.go` ¡ú ·µ»ØÖµ `buildtag` ×Ö¶Î£©¡£
**ÕâÌõÈô²»Ğ´Çå£¬»á°ÑÕıÈ·¹¹½¨ÎóÅĞÎª´íÎó£¬È»ºóÈÃÈËÈ¥»»¹¤¾ßÁ´°×ÕÛÌÚ¡£**

### ¹æÔò B£ºÔ¤¹¹½¨ `.so` ±ØĞëÉè SONAME£¬ÇÒ±ØĞë·ÅÔÚ `libs/<abi>/`
Êµ²âÁ½´ÎÊ§°Ü£¬¸÷×ÔÏÖÏó²»Í¬£º

1. **²»Éè SONAME**£ºÁ´½ÓÆ÷°Ñ**¹¹½¨ÆÚ¾ø¶ÔÂ·¾¶**Ğ´½ø `libentry.so` µÄ `DT_NEEDED`£¬°²×°ºóÆô¶¯¼´Ê§°Ü£º
   ```
   W MMG: key:default/entry First: failed Error loading shared library
   D:/projects/xray-harmony/entry/src/main/cpp/../libs/x86_64/libcgoping.so:
   (needed by /data/storage/el1/bundle/libs/x86_64/libentry.so)
   ```
   â‡’\ ¼Ó `CGO_LDFLAGS=... -Wl,-soname,libcgoping.so` ºóÕı³££¨`DT_NEEDED` ±äÎª `libcgoping.so`£©¡£
2. **ÊÔÍ¼´ÓÓ¦ÓÃË½ÓĞÄ¿Â¼ `dlopen` ¾ø¶ÔÂ·¾¶**£¨ÏÈ°Ñ so ·Å rawfile ÔÙÊÍ·Åµ½ `files/native/`£©£º
   ```
   M5 dlopen FAILED: [arg:/data/storage/el2/base/haps/entry/files/native/libcgoping.so]
   Error loading shared library ...: No error information
   ```
   â‡’\ **É³Ïä/¹ÒÔØÏŞÖÆ£ºÓ¦ÓÃ files Ä¿Â¼ÏÂµÄ .so ²»¿É dlopen**£¨`No error information` ÊÇµäĞÍµÄÎŞÖ´ĞĞÈ¨ÏŞ/±»¾Ü±íÏÖ£©¡£
   â‡’\ Î¨Ò»¿ÉĞĞÎ»ÖÃÊÇËæ°ü·Ö·¢µÄ `libs/<abi>/`£¨`/data/storage/el1/bundle/libs/<abi>/`£©¡£

> ¸½´ø½áÂÛ£º**hvigor Ö»´ò°ü²ÎÓë CMake Á´½ÓÍ¼µÄ .so**¡£Î´Á´½ÓµÄÔ¤¹¹½¨¿â¼´Ê¹·ÅÔÚ `libs/<abi>/` Ò²²»»á½ø HAP£¨Êµ²â HAP ÄÚÖ»ÓĞ `libc++_shared.so`/`libentry.so`/`libprebuilt.so`£©¡£ÒªÈÃËü½ø°ü£¬±ØĞë `add_library(... SHARED IMPORTED)` + `target_link_libraries`£¨±¾ÏîÄ¿µÄ `prebuilt` Óë `cgoping` ¾ùÈç´Ë£©¡£ÔËĞĞÊ±ÈÔ¿ÉÓÃ `dlopen`+`dlsym` µ÷ÓÃ£¬Ö¤¾İÓïÒå²»ÊÜÓ°Ïì¡£

## M5 ²ú³öÇåµ¥

| ÎÄ¼ş | ËµÃ÷ |
|---|---|
| `toolchain/build-cgoping.ps1` | Ò»¼ü¹¹½¨ + ËÄÑé£¨º¬ SONAME¡¢version-script¡¢Á½¿Ó×¢ÊÍ£© |
| `toolchain/smoke/go.mod` / `tag_openharmony.go` / `tag_default.go` | fork ÅĞ±ğÌ½Õë£¨build tag£© |
| `entry/src/main/libs/x86_64/libcgoping.so` | x86_64 ²úÎï£¨SONAME ÒÑÉè£© |
| `entry/src/main/cpp/cgo_bridge.cpp` | NAPI °ó¶¨£ºdlopen + dlsym + µ÷ÓÃ + `CGoFree` |
| `entry/src/main/cpp/napi_init.cpp` / `CMakeLists.txt` | ×¢²á `m5CGoPing`¡¢¹ÒÔØ `cgoping` ²ÎÓë´ò°ü |
| `entry/src/main/ets/pages/Index.ets` | µÚ 4 ¸ö°´Å¥ `M5: call Go CGoPing()` |

---

## ½áÂÛ±ß½ç£¨±Ø¶Á£¬·ÀÖ¹°Ñ½áÂÛËµ¹ıÍ·£©

- M5 µÄÖ¤¾İÀ´×Ô **x86_64 Ä£ÄâÆ÷£¨API 26£©**£¬¾İ´Ë¿ÉÈ·ÈÏ£º**Go runtime ÄÜÔÚ OHOS Ó¦ÓÃ½ø³ÌÄÚ³õÊ¼»¯²¢Íê³É cgo µ÷ÓÃ**£¨º¬ C¡úGo¡úC Ë«Ïò£©¡£
- **arm64 Õæ»úÈÔÎ´ÑéÖ¤**£º`P-03` Ö»Ëã**¾Ö²¿Ö¤Êµ**¡£Õæ»úĞèÖØÅÜÍ¬Ò»Á´Â·£¨arm64 `libcgoping.so` + Í¬Ò»µã»÷¶¯×÷£©£¬²¢¶îÍâ¹Ø×¢ fork µÄ TLSDESC/ĞÅºÅ´¦ÀíÔÚÕæÊµ ABI ÏÂµÄ±íÏÖ¡£
- Òò´Ë±¾½áÂÛ**²»ÄÜ**ÍâÍÆÎª¡¸Xray-core ÔÚ OHOS Õæ»ú¿ÉÓÃ¡¹¡ª¡ªÄÇĞèÒª `P-02`£¨±à libXray£©+ Õæ»ú¼ÓÔØµ÷ÓÃ²ÅÄÜ¶¨ÂÛ¡£

## ¸½£ºÈıÌõ¹¤¾ß²ã×¢ÒâÊÂÏî

1. **²»ÄÜÓÃ `runtime.GOOS` ÅĞ¶ÏÊÇ·ñÓÃÁË OHOS fork**£¨fork ¶Ô openharmony Ä¿±êºãÎª `linux`£©¡ª¡ªÖ»ÄÜÓÃ `//go:build openharmony` ±àÒë±êÇ©Ì½Õë¡£
2. **NDK µÄ `aarch64-unknown-linux-ohos-clang` / `x86_64-unknown-linux-ohos-clang` ÊÇ 171 ×Ö½ÚµÄ `#!/bin/sh` ½Å±¾**£¬Windows ²»ÄÜÖ´ĞĞ£»±ØĞë¸ÄÓÃ `clang.exe` + `-target <triple> --sysroot=<ndk>/sysroot -D__MUSL__`¡£
3. **`hdc hilog` ÊÇÁ÷Ê½µÄ**£¨»áÒ»Ö±¸ú×ÅÉè±¸ÈÕÖ¾Ë¢£©£¬Òª¿´ÒÑ²úÉúµÄ»º³åÓÃ `hdc shell hilog -x`£¨»òÏÈ `hilog -r` Çå¿ÕÔÙ¸´ÏÖ£©¡£

---

## P-02ï¼šlibXray åœ¨ OHOS è¿›ç¨‹å†…åŠ è½½ä¸å“åº”ï¼ˆE9ï¼‰

> ç›®æ ‡ï¼šæŠŠå·²éªŒè¯çš„ã€ŒGo â†’ OHOS `.so`ã€é“¾è·¯ç”¨åœ¨**çœŸå†…æ ¸**ä¸Šâ€”â€”ç¼– `libXray v26.7.28`ï¼ˆå« xray-core `v1.260327.1`ï¼‰ï¼Œamd64 åœ¨æ¨¡æ‹Ÿå™¨åŠ è½½å¹¶éªŒè¯ `CGoInvoke` æœ‰å“åº”ã€‚
> ç»“è®ºï¼š**âœ… æˆç«‹**â€”â€”`CGoInvoke` è¿”å›åˆæ³• JSONï¼ˆ`{"success":false,"data":null,"error":"unknown method"}`ï¼‰ï¼Œè¯æ˜å†…æ ¸å¯è¢«åŠ è½½ã€Go runtime å®Œæˆåˆå§‹åŒ–ã€xray-core çš„è°ƒç”¨åˆ†å‘å™¨è¢«æ‰§è¡Œã€‚

### 1. æºç ä¸é’‰ç‰ˆ

```
repo   : https://github.com/XTLS/libXray.git
tag    : v26.7.28  (åŒæ—¶å¸¦ tag v1.260728.0)
commit : 80263da83e96b2972455b0a94b13ee1a10e51391
go.mod : go 1.26.3 ; require github.com/xtls/xray-core v1.260327.1-0.20260728075948-5ca6f4b7d4dc
æœ¬åœ°è·¯å¾„: _toolchain/libXray-v26.7.28ï¼ˆä¸å…¥åº“ï¼‰
```

> **è¸©å‘ï¼šé»˜è®¤ `GOPROXY=https://proxy.golang.org` åœ¨æœ¬æœºä¸å¯è¾¾**ï¼Œ`go mod download` æŠ¥
> `dial tcp 142.250.73.81:443: connectex: A connection attempt failed ...`ï¼ˆè¿æ¥è¶…æ—¶ï¼‰ã€‚
> è§£å†³ï¼š`GOPROXY=https://goproxy.cn,direct` + `GOSUMDB=sum.golang.google.cn` + `GOFLAGS=-mod=mod`ï¼Œä¹‹å `go mod download` é€€å‡ºç  0ã€‚

### 2. ç¼–è¯‘ï¼ˆ`-buildmode=c-shared`ï¼Œå¸¦ version-script + SONAMEï¼‰

```powershell
$env:GOOS="openharmony"; $env:GOARCH="amd64"; $env:CGO_ENABLED="1"
$env:CC='"...\clang.exe" -target x86_64-linux-ohos "--sysroot=...\sysroot" -D__MUSL__'
$env:CGO_CFLAGS ='-ftls-model=global-dynamic'
$env:CGO_LDFLAGS='-ftls-model=global-dynamic -Wl,-soname,libxray.so'
go build -trimpath -buildvcs=false -buildmode=c-shared `
  -ldflags "-extldflags=-Wl,--version-script=<...>/libxray.map" `
  -o ...\libxray.so ./cgo_bridge
```

`libxray.map`ï¼š`global: CGoInvoke; CGoFree; local: *;`

é¦–æ¬¡ç¼–è¯‘ï¼ˆ`EXIT=0`ï¼‰äº§ç‰©ï¼š`libxray.so` **71,317,112 B**ï¼ˆæœª stripï¼Œå«ç¬¦å·ä¸ DWARFï¼‰ã€‚

### 3. å››éªŒï¼ˆ`llvm-readelf`ï¼‰

| æ£€æŸ¥ | ç»“æœ |
|---|---|
| ELF å¤´ | âœ… `Type: DYN (Shared object file)` / `Machine: Advanced Micro Devices X86-64` |
| `PT_TLS` | âœ… `TLS 0x1f506c0 ... R 0x8` |
| `R_X86_64_TLSDESC` | âœ… 1 æ¡ |
| å¯¼å‡ºç¬¦å· | âœ… **ä»… `CGoInvoke` + `CGoFree`**ï¼ˆversion-script ç”Ÿæ•ˆï¼‰ |
| `DT_NEEDED` | âœ… ä»… `libc.so`ï¼›`SONAME: libxray.so` |

### 4. æ¥å…¥åº”ç”¨

- `entry/src/main/libs/x86_64/libxray.so` â† æ„å»ºäº§ç‰©ï¼›
- `CMakeLists.txt`ï¼š`add_library(xraycore SHARED IMPORTED)` + `target_link_libraries(entry PUBLIC xraycore)`ï¼ˆåŒ M5 è§„åˆ™ï¼š**ä¸å‚ä¸é“¾æ¥å›¾çš„ .so ä¸ä¼šè¿› HAP**ï¼‰ï¼›
- `cgo_bridge.cpp` æ–°å¢ `M6CGoInvoke`ï¼š`dlopen("libxray.so")` â†’ `dlsym("CGoInvoke")` â†’ ç”¨**æ•…æ„éæ³•**çš„ä¿¡å°è°ƒç”¨ï¼ˆ`{"apiVersion":1,"method":"__p02_probe__","payload":{}}`ï¼‰â†’ `CGoFree` é‡Šæ”¾ï¼›
- `Index.ets` ç¬¬ 5 ä¸ªæŒ‰é’® **`M6: load libxray + CGoInvoke`**ã€‚

HAP å†…ç¡®è®¤ï¼š`libs/x86_64/libxray.so` **38,069,288 B**ï¼ˆstrip åï¼‰ï¼›HAP æ€»å¤§å° **42,421,112 B**ã€‚

### 5. å®è·‘ï¼ˆæ¨¡æ‹Ÿå™¨ 127.0.0.1:5555ï¼ŒAPI 26ï¼‰

```
I A00001/XVPN_POC: M6 clicked
I A00001/XVPN_POC: M6 result=[elapsed_ms=0] {"success":false,"data":null,"error":"unknown method"}
```

è¿›ç¨‹å­˜æ´»ï¼ˆPID 26110ï¼‰ï¼Œ**æ—  SIGSEGV**ã€‚

åˆ¤å®šï¼šè¿”å›**åˆæ³• JSON**ï¼ˆ`success:false` + ç»“æ„åŒ– `error`ï¼‰â‡’ **Xray å†…æ ¸åœ¨ OHOS è¿›ç¨‹å†…å¯åŠ è½½å¹¶å“åº”è°ƒç”¨**ï¼Œ`P-02` æ ¸å¿ƒè¯æ®æˆç«‹ã€‚
**æ³¨æ„**ï¼šè¿™ä¸æ˜¯ã€Œèƒ½ä»£ç†ä¸Šç½‘ã€â€”â€”æ— èŠ‚ç‚¹ã€æ— å‡ºç«™è¿æ¥ï¼ŒåªéªŒè¯ã€ŒåŠ è½½ + åˆ†å‘å™¨æ‰§è¡Œã€ã€‚

### 6. é‡‡é›†åˆ°çš„æ•°å­—ï¼ˆæœªé‡‡é›†é¡¹å¦‚å®æ ‡æ³¨ï¼‰

| æŒ‡æ ‡ | å€¼ | è¯´æ˜ |
|---|---|---|
| `libxray.so`ï¼ˆæ„å»ºäº§ç‰©ï¼Œæœª stripï¼‰ | **71,317,112 B** | â€” |
| `libxray.so`ï¼ˆHAP å†…ï¼Œstrip åï¼‰ | **38,069,288 B** | hvigor è‡ªåŠ¨ strip |
| HAP æ€»å¤§å° | **42,421,112 B** | å« libentry/libprebuilt/libcgoping/libc++_shared |
| å®‰è£…è€—æ—¶ï¼ˆ`hdc install -r`ï¼‰ | **2 s** | æ¨¡æ‹Ÿå™¨ï¼ŒéçœŸæœº |
| å†·å¯åŠ¨åˆ° UI å¯ç”¨ï¼ˆä»£ç†æŒ‡æ ‡ï¼‰ | **â‰ˆ1.28 s** | `aa start` â†’ `uitest dumpLayout` æˆåŠŸï¼›å« dumpLayout è‡ªèº«å¼€é”€ï¼Œ**éä¸¥æ ¼é¦–å¸§** |
| è¿›ç¨‹å†…å­˜ï¼ˆ`VmRSS` / `VmHWM`ï¼‰ | **173,200 kB / 174,044 kB**ï¼ˆâ‰ˆ169/170 MBï¼‰ | æ•´ä¸ªåº”ç”¨è¿›ç¨‹ï¼Œå« 38 MB æ˜ å°„çš„ `libxray.so` + Go runtime + ArkTS |
| `CGoInvoke` å•æ¬¡è°ƒç”¨è€—æ—¶ | **< 1 ms**ï¼ˆ`elapsed_ms=0`ï¼‰ | è§ä¸‹æ–¹è§‚å¯Ÿ 1 |

### 7. ä¸¤æ¡å¿…é¡»è®°å½•çš„è§‚å¯Ÿ

1. **æœ¬æ¶æ„ä¸‹æ²¡æœ‰ç‹¬ç«‹çš„ã€Œdlopen è€—æ—¶ã€**ï¼š`.so` å¿…é¡»å‚ä¸é“¾æ¥å›¾æ‰èƒ½è¿› HAPï¼Œå› æ­¤å®ƒåŒæ—¶æ˜¯ `libentry.so` çš„ `DT_NEEDED`ï¼Œ**åœ¨åº”ç”¨å¯åŠ¨æ—¶å³è¢«åŠ è½½**ï¼›è¿è¡ŒæœŸ `dlopen("libxray.so")` åªæ˜¯å–å·²åŠ è½½å¥æŸ„ã€‚â‡’ **å†…æ ¸çœŸå®åŠ è½½æˆæœ¬åœ¨å†·å¯åŠ¨ï¼Œä¸åœ¨ç‚¹å‡»æŒ‰é’®æ—¶**ï¼›1.28 s å†·å¯åŠ¨ä¸­è¯¥éƒ¨åˆ†æœªæ‹†åˆ†ï¼ˆã€æœªé‡‡é›†ã€‘ç»†åˆ†ï¼‰ã€‚
2. **Native ä¾§ `OH_LOG_INFO` æœªå‡ºç°åœ¨ `hilog -x` ä¸­**ï¼ˆåªçœ‹åˆ° ArkTS çš„ `XVPN_POC` è¡Œï¼ŒM5 æ—¶äº¦ç„¶ï¼‰ã€‚â‡’ é˜¶æ®µå½’å› ï¼ˆdlopen/dlsym/callï¼‰**ä¸èƒ½ä¾èµ– native æ—¥å¿—**ï¼›æœ¬æ¬¡æ”¹ä¸ºæŠŠ `elapsed_ms` æ‹¼è¿›è¿”å›å€¼æ‰æ‹¿åˆ°è€—æ—¶ã€‚**åç»­ PoC éœ€é˜¶æ®µå½’å› æ—¶ï¼Œåº”æŠŠçŠ¶æ€å†™è¿›è¿”å›å€¼æˆ–æ”¹ç”¨å¯è¾¾çš„æ—¥å¿—é€šé“ã€‚**

### 8. ç»“è®ºè¾¹ç•Œ

- æœ¬æ¬¡è¯æ®æ¥è‡ª **x86_64 æ¨¡æ‹Ÿå™¨**ï¼šè¯æ˜ã€Œ**Xray å†…æ ¸å¯è¢« OHOS åº”ç”¨åŠ è½½å¹¶å“åº” `CGoInvoke`**ã€ã€‚
- **ä»æœªéªŒè¯**ï¼šarm64 çœŸæœºåŠ è½½ã€çœŸå®èŠ‚ç‚¹å‡ºç«™ã€tun æ•°æ®é¢ï¼ˆå± `J-01` èŒƒå›´ï¼‰ã€‚
- æ•… `P-02` è®°ä¸º**æ ¸å¿ƒè¯æ®æˆç«‹ã€çœŸæœºéƒ¨åˆ†å¾…éªŒ**ï¼›**ä¸èƒ½**æ®æ­¤å®£å¸ƒã€Œå¯ä»¥ä»£ç†ä¸Šç½‘ã€ã€‚
