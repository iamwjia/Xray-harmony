//go:build !openharmony

package main

func buildTagOS() string {
	return "not-openharmony"
}
