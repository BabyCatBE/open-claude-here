<#
.SYNOPSIS
  Adds an "Open AI here" submenu to the Windows Explorer right-click menu
  (Claude Code, Codex, OpenCode - in the terminal or in the desktop app).
.PARAMETER Label
  Text of the submenu. Defaults to Portuguese if the system language is pt, otherwise English.
.PARAMETER Tools
  Which tools to add: claude, codex, opencode. Default: every tool found on this machine.
.PARAMETER Modes
  terminal, desktop. Default: both (desktop only where the tool supports opening a folder).
.PARAMETER NoPrompt
  Do not ask questions; install everything that was detected (or selected with -Tools/-Modes).
#>
param(
    [string]$Label,
    [ValidateSet('claude', 'codex', 'opencode')][string[]]$Tools,
    [ValidateSet('terminal', 'desktop')][string[]]$Modes = @('terminal', 'desktop'),
    [switch]$NoPrompt
)

$ErrorActionPreference = 'Stop'
$pt = (Get-UICulture).TwoLetterISOLanguageName -eq 'pt'
if (-not $Label) { $Label = if ($pt) { 'Abrir IA aqui' } else { 'Open AI here' } }

# --- Tool table -------------------------------------------------------------
# OpenCode Desktop has no way to open a folder from outside (its opencode:// links only handle
# login), so its desktop entry only launches the app.
$catalog = @(
    @{ Id = 'claude';   Name = 'Claude Code'; Exe = 'claude';   Desktop = $true; DesktopNote = '' }
    @{ Id = 'codex';    Name = 'Codex';       Exe = 'codex';    Desktop = $true; DesktopNote = '' }
    @{ Id = 'opencode'; Name = 'OpenCode';    Exe = 'opencode'; Desktop = $true; DesktopNote = 'no folder' }
)

function Test-DesktopInstalled([string]$id) {
    switch ($id) {
        'claude' { return [bool](Get-AppxPackage -Name 'Claude' -ErrorAction SilentlyContinue) }
        'codex'  { return [bool](Get-AppxPackage -Name 'OpenAI.Codex' -ErrorAction SilentlyContinue) }
        'opencode' { return Test-Path (Join-Path $env:LOCALAPPDATA 'Programs\ai.opencode.desktop\OpenCode.exe') }
        default  { return $false }
    }
}

# --- Detect and choose ------------------------------------------------------
$interactive = -not $NoPrompt -and [Environment]::UserInteractive -and -not $Tools
$entries = @()   # each: @{ Tool; Mode }
foreach ($t in $catalog) {
    if ($Tools -and $Tools -notcontains $t.Id) { continue }
    $cli = [bool](Get-Command $t.Exe -ErrorAction SilentlyContinue)
    $app = $t.Desktop -and (Test-DesktopInstalled $t.Id)
    $found = $Tools -contains $t.Id   # explicit -Tools always installs, even if not detected
    foreach ($mode in 'terminal', 'desktop') {
        if ($Modes -notcontains $mode) { continue }
        $available = if ($mode -eq 'terminal') { $cli } else { $app }
        if (-not $available -and -not ($found -and ($mode -eq 'terminal' -or $t.Desktop))) { continue }
        if ($interactive) {
            $answer = Read-Host "Add '$($t.Name) ($mode)'? [Y/n]"
            if ($answer -match '^(n|no|nao|não)$') { continue }
        }
        $entries += @{ Tool = $t; Mode = $mode }
    }
}

if (-not $entries) { throw 'Nothing to install: no supported tool was found. Install Claude Code, Codex or OpenCode, or pass -Tools.' }

# --- Files ------------------------------------------------------------------
# Copy to a stable location so the repo folder can be deleted afterwards
$installDir = Join-Path $env:LOCALAPPDATA 'ClaudeCodeContextMenu'
New-Item -ItemType Directory -Path $installDir -Force | Out-Null
foreach ($f in 'ai-robot', 'claude-code', 'codex', 'opencode') {
    Copy-Item -Path (Join-Path $PSScriptRoot "assets\$f.ico") -Destination (Join-Path $installDir "$f.ico") -Force
}
$robotIcon = Join-Path $installDir 'ai-robot.ico'
$iconFile = @{ claude = 'claude-code.ico'; codex = 'codex.ico'; opencode = 'opencode.ico' }
$helper = Join-Path $installDir 'open-ai-desktop.ps1'
Copy-Item -Path (Join-Path $PSScriptRoot 'open-ai-desktop.ps1') -Destination $helper -Force

# --- Commands ---------------------------------------------------------------
$hasWt = [bool](Get-Command wt.exe -ErrorAction SilentlyContinue)

function Get-TerminalCommand($t) {
    # npm-installed CLIs are .cmd/.ps1 shims, which need cmd.exe to run
    $src = (Get-Command $t.Exe -ErrorAction SilentlyContinue).Source
    $run = if ($src -and $src -like '*.exe') { $t.Exe } else { "cmd.exe /c $($t.Exe)" }
    # %V works for folders and for the folder background. "<dir>\." keeps the closing quote
    # safe when the path ends in a backslash (drive root).
    if ($hasWt) { return "wt.exe -d `"%V\.`" $run" }
    return "cmd.exe /k cd /d `"%V`" && $($t.Exe)"
}

function Get-DesktopCommand($t) {
    "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$helper`" -Tool $($t.Id) -Path `"%V\.`""
}

# --- Registry ---------------------------------------------------------------
$classes = 'HKCU:\Software\Classes'
$menuKey = "$classes\Directory\ContextMenus\AIHere"

# Remove previous installs (old single-entry version and earlier runs of this one)
foreach ($old in "$classes\Directory\shell\ClaudeCode", "$classes\Directory\Background\shell\ClaudeCode",
                 "$classes\Directory\shell\AIHere", "$classes\Directory\Background\shell\AIHere", $menuKey) {
    Remove-Item -Path $old -Recurse -Force -ErrorAction SilentlyContinue
}

# The submenu items, shared by "right-click a folder" and "right-click inside a folder"
New-Item -Path "$menuKey\shell" -Force | Out-Null
$i = 0
$lastTool = $null
foreach ($e in $entries) {
    $i++
    $item = "$menuKey\shell\{0:D2}_{1}_{2}" -f $i, $e.Tool.Id, $e.Mode
    New-Item -Path $item -Force | Out-Null
    $suffix = if ($e.Mode -eq 'desktop' -and $e.Tool.DesktopNote) { "desktop, $($e.Tool.DesktopNote)" } else { $e.Mode }
    Set-ItemProperty -Path $item -Name 'MUIVerb' -Value ("{0} ({1})" -f $e.Tool.Name, $suffix)
    Set-ItemProperty -Path $item -Name 'Icon' -Value (Join-Path $installDir $iconFile[$e.Tool.Id])
    if ($lastTool -and $lastTool -ne $e.Tool.Id) { Set-ItemProperty -Path $item -Name 'CommandFlags' -Value 0x20 -Type DWord }  # separator before
    $lastTool = $e.Tool.Id
    New-Item -Path "$item\command" -Force | Out-Null
    $cmd = if ($e.Mode -eq 'terminal') { Get-TerminalCommand $e.Tool } else { Get-DesktopCommand $e.Tool }
    Set-ItemProperty -Path "$item\command" -Name '(Default)' -Value $cmd
}

foreach ($parent in "$classes\Directory\shell\AIHere", "$classes\Directory\Background\shell\AIHere") {
    New-Item -Path $parent -Force | Out-Null
    Set-ItemProperty -Path $parent -Name 'MUIVerb' -Value $Label
    Set-ItemProperty -Path $parent -Name 'Icon' -Value $robotIcon
    Set-ItemProperty -Path $parent -Name 'ExtendedSubCommandsKey' -Value 'Directory\ContextMenus\AIHere'
}

Write-Output "Installed '$Label' with:"
$entries | ForEach-Object { Write-Output ("  - {0} ({1})" -f $_.Tool.Name, $_.Mode) }
Write-Output "On Windows 11 it is under 'Show more options' (Shift+right-click)."
