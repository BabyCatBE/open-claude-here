<#
.SYNOPSIS
  Opens a tool's desktop app on a folder. Called by the Explorer context menu.
  What to run for each tool is described in tools.json (next to this script).
.PARAMETER Tool
  Tool id from tools.json (claude, codex, opencode, cursor, ...).
.PARAMETER Path
  Folder to open.
#>
param(
    [Parameter(Mandatory)][string]$Tool,
    [Parameter(Mandatory)][string]$Path
)

$ErrorActionPreference = 'Stop'

# The menu passes "<folder>\." so that quoting never breaks on drive roots like C:\
$full = [IO.Path]::GetFullPath($Path)

$tools = @((Get-Content (Join-Path $PSScriptRoot 'tools.json') -Raw -Encoding UTF8 | ConvertFrom-Json) | ForEach-Object { $_ })
$t = $tools | Where-Object { $_.id -eq $Tool } | Select-Object -First 1
if (-not $t -or -not $t.desktop) { throw "No desktop entry for '$Tool' in tools.json" }
$open = $t.desktop.open

if ($open.uri) {
    # a deep link, e.g. claude://code/new?folder=...
    Start-Process ($open.uri.Replace('{folderEncoded}', [Uri]::EscapeDataString($full)))
}
elseif ($open.run) {
    # a command, e.g. codex app <folder> or cursor <folder>
    $cmd = $open.run[0]
    $rest = @($open.run | Select-Object -Skip 1 | ForEach-Object { $_.Replace('{folder}', $full) })
    Set-Location -LiteralPath $full
    & $cmd @rest
}
elseif ($open.launch) {
    # the app has no way to open a folder from outside: just start it
    Start-Process -FilePath ([Environment]::ExpandEnvironmentVariables($open.launch))
}
else {
    throw "tools.json: '$Tool' desktop.open needs one of uri, run or launch"
}
