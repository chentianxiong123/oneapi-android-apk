//go:build no_web

package main

import "embed"

var buildFS embed.FS
var indexPage []byte
var classicBuildFS embed.FS
var classicIndexPage []byte
