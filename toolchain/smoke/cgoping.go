// Package main：E2 最小 CGo 验证目标（hello-world 级）。
//
// 目的：在**不拉 Xray-core** 的前提下，证明三件事：
//  1) OHOS Go fork 的工具链能自举成功；
//  2) GOOS=openharmony + -ftls-model=global-dynamic 能产出可被 OHOS 加载的 c-shared 产物；
//  3) 产物带 PT_TLS + R_AARCH64_TLSDESC，且导出面等于 //export 集合（仅 2 个）。
//
// 与 libXray 的形态刻意保持一致：
//  - 同样 -buildmode=c-shared；
//  - 同样「一个入口 + 一个 free」的导出形状（libXray 是 CGoInvoke / CGoFree）；
//  - 同样由 Go 自动生成的 version script 收敛导出面。
//
// 构建（不要在本目录直接跑，用 toolchain\bootstrap-ohos-go.ps1 -Stage smoke）：
//
//	GOOS=openharmony GOARCH=arm64 CGO_ENABLED=1 \
//	CGO_CFLAGS="-ftls-model=global-dynamic" \
//	go build -trimpath -buildvcs=false -buildmode=c-shared -o libcgoping.so .
//
// 注意：本文件依赖 cgo，因此 CGO_ENABLED 必须为 1；且**不能**加 -tags netgo。
package main

/*
#include <stdlib.h>
#include <string.h>

// 一个纯 C 侧函数：用于验证「C → Go → C」双向调用链都是通的，
// 而不只是 Go 单方向导出。若 C 侧代码没被正确编译进产物，
// 这个符号会在加载期报 undefined symbol，问题会前移到 dlopen 阶段暴露。
static const char* c_side_marker(void) {
	return "cgoping-c-side-ok";
}
*/
import "C"

import (
	"runtime"
	"unsafe"
)

// cgopingVersion 用于在产物里留下可被 strings 检索的标记，
// 便于校验「这个 .so 确实是本次构建出来的」。
const cgopingVersion = "cgoping/0.1 (e2-minimal)"

func main() {}

// CGoPing 是最小入口：返回一段静态 JSON，便于宿主用固定断言校验。
// 返回值由 Go 侧分配（C.CString），**必须**用 CGoFree 释放。
//
//export CGoPing
func CGoPing() *C.char {
	// 刻意在返回体里带上 runtime 信息：一旦宿主拿到的 GOOS 不是 openharmony，
	// 说明工具链/环境变量用错了（这是最常见的失败，且往往静默）。
	payload := `{"success":true,"data":{"marker":"pong","version":"` + cgopingVersion +
		`","goos":"` + runtime.GOOS + `","goarch":"` + runtime.GOARCH +
		`","cside":"` + C.GoString(C.c_side_marker()) + `"}}`
	return C.CString(payload)
}

// CGoFree 释放 CGoPing 返回的字符串。
// 语义与 libXray 的 CGoFree 一致：**只能用这个函数释放，不能用宿主侧 free()**。
//
//export CGoFree
func CGoFree(p *C.char) {
	if p != nil {
		C.free(unsafe.Pointer(p))
	}
}
