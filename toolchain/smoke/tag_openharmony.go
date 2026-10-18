//go:build openharmony

package main

// buildTagOS proves at runtime that the binary was compiled with the OHOS fork
// targeting GOOS=openharmony. Note: the fork intentionally reports
// runtime.GOOS=="linux" (see internal/goos/gengoos.go: the openharmony target
// generates `const GOOS = "linux"`), so the build tag is the only reliable marker.
func buildTagOS() string {
	return "openharmony"
}
