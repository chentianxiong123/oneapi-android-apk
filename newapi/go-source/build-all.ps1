<#
.SYNOPSIS
    NewAPI MIPS (mipsel) 交叉编译脚本
    编译全部版本：MySQL/SQLite × 有前端/无前端
.DESCRIPTION
    需要:
    - Go 1.22+
    - musl.cc mipsel-linux-muslsf-cross 工具链 (仅 CGo SQLite 版本需要)
    - WSL 或 Linux 环境 (仅 CGo SQLite 版本需要)
    输出目录: bin\release\
#>

param(
    [switch]$OnlyMySQL,
    [switch]$OnlySQLite,
    [switch]$NoWeb,
    [switch]$WithWeb
)

$ErrorActionPreference = "Stop"
$ROOT = Split-Path -Parent $PSScriptRoot
$OUT = "$ROOT\bin\release"
New-Item -ItemType Directory -Path $OUT -Force | Out-Null

# 检测 UPX
$UPX = Get-Command "upx.exe" -ErrorAction SilentlyContinue
if (-not $UPX) {
    $UPXPath = "C:\Users\a1\AppData\Local\Temp\upx\upx-4.2.4-win64\upx.exe"
    if (Test-Path $UPXPath) { $UPX = $UPXPath }
}

# 默认：全编
if (-not ($OnlyMySQL -or $OnlySQLite -or $NoWeb -or $WithWeb)) {
    $OnlyMySQL = $true; $OnlySQLite = $true; $NoWeb = $true; $WithWeb = $true
}

function Build-MySQL {
    param([string]$Suffix, [string]$Tags)
    Write-Host "=== 编译 MySQL 版 ($Suffix) ===" -ForegroundColor Cyan

    Push-Location $ROOT
    # 确保 go.mod replace
    $gomod = Get-Content "go.mod" -Raw
    if ($gomod -notmatch "replace github.com/glebarez/sqlite => \./sqlite-stub") {
        $gomod = $gomod -replace "(go \d+\.\d+\n)", "`$1`nreplace github.com/glebarez/sqlite => ./sqlite-stub`n"
        Set-Content "go.mod" -Value $gomod
    }
    # 确保 sqlite-stub 存在
    if (-not (Test-Path "sqlite-stub")) {
        New-Item -ItemType Directory -Path "sqlite-stub" -Force | Out-Null
        @"
module github.com/glebarez/sqlite
go 1.25.1
require gorm.io/gorm v1.25.12
"@ | Set-Content "sqlite-stub\go.mod"
        @"
package sqlite
import (
    "gorm.io/gorm"
    "gorm.io/gorm/clause"
    "gorm.io/gorm/migrator"
    "gorm.io/gorm/schema"
)
type Dialector struct{ DSN string }
func Open(dsn string) Dialector { return Dialector{DSN: dsn} }
func (Dialector) Name() string { return "sqlite" }
func (Dialector) Initialize(*gorm.DB) error { return gorm.ErrInvalidDB }
func (Dialector) Migrator(*gorm.DB) gorm.Migrator { return &migrator.Migrator{} }
func (Dialector) DataTypeOf(*schema.Field) string { return "" }
func (Dialector) DefaultValueOf(*schema.Field) clause.Expression { return nil }
func (Dialector) BindVarTo(writer clause.Writer, stmt *gorm.Statement, v interface{}) { writer.WriteString("?") }
func (Dialector) QuoteTo(writer clause.Writer, s string) { writer.WriteString(s) }
func (Dialector) Explain(sql string, vars ...interface{}) string { return sql }
"@ | Set-Content "sqlite-stub\sqlite.go"
    }
    Pop-Location

    $env:GOOS = "linux"; $env:GOARCH = "mipsle"; $env:GOMIPS = "softfloat"
    $outfile = "$OUT\newapi-mipsle-mysql$Suffix"
    go build -tags "$Tags" -ldflags="-s -w" -o $outfile .
    Write-Host "  → $outfile ($((Get-Item $outfile).Length/1MB, 'F2') MB)" -ForegroundColor Green

    if ($UPX) {
        $upxfile = "$OUT\newapi-mipsle-mysql${Suffix}-upx"
        & $UPX --best --lzma -o $upxfile $outfile
        Write-Host "  → $upxfile ($((Get-Item $upxfile).Length/1MB, 'F2') MB) [UPX]" -ForegroundColor Green
    }
}

function Build-SQLite {
    param([string]$Suffix, [string]$Tags)
    Write-Host "=== 编译 SQLite 静态版 ($Suffix) ===" -ForegroundColor Cyan

    # 需要 WSL + musl 工具链
    $CC = "wsl -e /opt/mipsel-tc/bin/mipsel-linux-muslsf-gcc"
    if (-not (Get-Command "wsl" -ErrorAction SilentlyContinue)) {
        Write-Host "  ❌ 需要 WSL" -ForegroundColor Red; return
    }

    Push-Location $ROOT
    $gomod = Get-Content "go.mod" -Raw
    if ($gomod -notmatch "replace github.com/glebarez/sqlite => \./sqlite-cgo") {
        $gomod = $gomod -replace "replace github.com/glebarez/sqlite => \./sqlite-stub", "replace github.com/glebarez/sqlite => ./sqlite-cgo"
        Set-Content "go.mod" -Value $gomod
    }
    Pop-Location

    $outfile = "$OUT\newapi-mipsle-sqlite$Suffix"
    wsl bash -c @"
export PATH=/usr/local/go/bin:/opt/mipsel-tc/bin:`$PATH
export CGO_ENABLED=1
export CC=mipsel-linux-muslsf-gcc
export GOOS=linux GOARCH=mipsle GOMIPS=softfloat
cd /mnt/c/Users/a1/Desktop/new-api-src
go build -tags $Tags -ldflags='-s -w -linkmode=external -extldflags=-static' -o `$(wslpath '$outfile') .
"@
    Write-Host "  → $outfile ($((Get-Item $outfile).Length/1MB, 'F2') MB)" -ForegroundColor Green

    if ($UPX) {
        $upxfile = "$OUT\newapi-mipsle-sqlite${Suffix}-upx"
        & $UPX --best --lzma -o $upxfile $outfile
        Write-Host "  → $upxfile ($((Get-Item $upxfile).Length/1MB, 'F2') MB) [UPX]" -ForegroundColor Green
    }
}

# ===== 主流程 =====

# 无前端版本
if ($NoWeb) {
    if ($OnlyMySQL) { Build-MySQL -Suffix "" -Tags "no_web" }
    if ($OnlySQLite) { Build-SQLite -Suffix "" -Tags "no_web" }
}

# 有前端版本
if ($WithWeb) {
    # 检查前端 dist 是否存在
    $hasDefault = Test-Path "$ROOT\web\default\dist\index.html"
    $hasClassic = Test-Path "$ROOT\web\classic\dist\index.html"
    if (-not ($hasDefault -and $hasClassic)) {
        Write-Host "  ⚠️ 前端 dist 缺失，跳过有前端版本" -ForegroundColor Yellow
    } else {
        if ($OnlyMySQL) { Build-MySQL -Suffix "-web" -Tags "" }
        if ($OnlySQLite) { Build-SQLite -Suffix "-web" -Tags "" }
    }
}

Write-Host "=== 完成 ===" -ForegroundColor Cyan
Write-Host "输出目录: $OUT"
Get-ChildItem $OUT | Select Length, Name