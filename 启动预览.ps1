param([switch]$Rebuild)
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
$flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
$flutterPath = if ($flutterCommand) { $flutterCommand.Source } elseif (Test-Path -LiteralPath 'D:\tools\flutter\bin\flutter.bat') { 'D:\tools\flutter\bin\flutter.bat' } else { $null }
if (-not (Get-Command node -ErrorAction SilentlyContinue)) { throw '请先安装 Node.js 22 或更新版本。' }
if ($Rebuild -or -not (Test-Path -LiteralPath '.\build\web\index.html')) {
    if (-not $flutterPath) { throw '未找到 Flutter。请安装 SDK 并加入 PATH 后重试。' }
    & $flutterPath pub get
    if ($LASTEXITCODE -ne 0) { throw 'Flutter 依赖安装失败。' }
    npm ci --ignore-scripts
    if ($LASTEXITCODE -ne 0) { throw '预览依赖安装失败。' }
    node tools/prepare-web.mjs
    if ($LASTEXITCODE -ne 0) { throw 'PDF 组件准备失败。' }
    node tools/plugin-sdk.mjs build
    if ($LASTEXITCODE -ne 0) { throw '插件目录生成失败。' }
    & $flutterPath build web --wasm --no-web-resources-cdn
    if ($LASTEXITCODE -ne 0) { throw 'Flutter Web 编译失败。' }
    node tools/offline-shell.mjs
}
Write-Host '打开 http://127.0.0.1:4173 即可预览。按 Ctrl+C 停止。'
node tools/preview.mjs
