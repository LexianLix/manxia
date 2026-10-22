param()
$ErrorActionPreference = 'Stop'
$workspace = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$startup = Join-Path $workspace 'WORK_START.md'
if (-not (Test-Path -LiteralPath $startup)) {
    Write-Output '没有待消费的启动文档；请查看 docs/DEVELOPMENT_PLAN.md。'
    exit 0
}
$content = [IO.File]::ReadAllText($startup)
if ([string]::IsNullOrWhiteSpace($content)) { throw '启动文档为空，保留文件供检查。' }
Write-Output $content
# Only delete the exact one-time document after successfully reading/outputting it.
Remove-Item -LiteralPath $startup
