<#
.SYNOPSIS
  Opens a desktop AI app (Claude Desktop, Codex) on a folder. Called by the Explorer context menu.
.PARAMETER Tool
  claude | codex | opencode
.PARAMETER Path
  Folder to open.
#>
param(
    [Parameter(Mandatory)][ValidateSet('claude', 'codex', 'opencode')][string]$Tool,
    [Parameter(Mandatory)][string]$Path
)

$ErrorActionPreference = 'Stop'

# The menu passes "<folder>\." so that quoting never breaks on drive roots like C:\
$full = [IO.Path]::GetFullPath($Path)

switch ($Tool) {
    'claude' {
        # Documented deep link: Claude Desktop asks the user to confirm the folder.
        Start-Process ('claude://code/new?folder=' + [Uri]::EscapeDataString($full))
    }
    'opencode' {
        # OpenCode Desktop cannot open a folder from outside, so this only launches the app.
        $exe = Join-Path $env:LOCALAPPDATA 'Programs\ai.opencode.desktop\OpenCode.exe'
        Start-Process -FilePath $exe
    }
    'codex' {
        # "codex app [PATH]" opens the folder as a workspace in the Codex desktop app.
        Set-Location -LiteralPath $full
        & codex app $full
    }
}
