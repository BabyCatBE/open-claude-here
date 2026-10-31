<#
.SYNOPSIS
  Adds "Open Claude Code here" to the Windows Explorer right-click menu.
.PARAMETER Label
  Text shown in the menu. Defaults to Portuguese if the system language is pt, otherwise English.
#>
param(
    [string]$Label
)

$ErrorActionPreference = 'Stop'

if (-not $Label) {
    if ((Get-UICulture).TwoLetterISOLanguageName -eq 'pt') { $Label = 'Abrir sessão Claude Code aqui' }
    else { $Label = 'Open Claude Code here' }
}

# Warn (but do not fail) if claude is not installed yet
if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Write-Warning "'claude' was not found in PATH. Install Claude Code first: https://claude.com/claude-code"
}

# Copy the icon to a stable location so the repo folder can be deleted afterwards
$installDir = Join-Path $env:LOCALAPPDATA 'ClaudeCodeContextMenu'
New-Item -ItemType Directory -Path $installDir -Force | Out-Null
$icon = Join-Path $installDir 'claude-code.ico'
Copy-Item -Path (Join-Path $PSScriptRoot 'assets\claude-code.ico') -Destination $icon -Force

# Prefer Windows Terminal, fall back to cmd.exe
if (Get-Command wt.exe -ErrorAction SilentlyContinue) {
    $cmdFolder     = 'wt.exe -d "%1" claude'
    $cmdBackground = 'wt.exe -d "%V" claude'
} else {
    $cmdFolder     = 'cmd.exe /k cd /d "%1" && claude'
    $cmdBackground = 'cmd.exe /k cd /d "%V" && claude'
}

$targets = @{
    'HKCU:\Software\Classes\Directory\shell\ClaudeCode'            = $cmdFolder
    'HKCU:\Software\Classes\Directory\Background\shell\ClaudeCode' = $cmdBackground
}

foreach ($key in $targets.Keys) {
    New-Item -Path $key -Force | Out-Null
    Set-ItemProperty -Path $key -Name '(Default)' -Value $Label
    Set-ItemProperty -Path $key -Name 'Icon' -Value $icon
    New-Item -Path "$key\command" -Force | Out-Null
    Set-ItemProperty -Path "$key\command" -Name '(Default)' -Value $targets[$key]
}

Write-Output "Installed: '$Label'. On Windows 11 it is under 'Show more options' (Shift+right-click)."
