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
.PARAMETER Configure
  Reopen the checklist to change which entries appear, starting from your previous choice.
#>
param(
    [string]$Label,
    [ValidateSet('claude', 'codex', 'opencode')][string[]]$Tools,
    [ValidateSet('terminal', 'desktop')][string[]]$Modes = @('terminal', 'desktop'),
    [switch]$NoPrompt,
    [switch]$Configure
)

$ErrorActionPreference = 'Stop'
$pt = (Get-UICulture).TwoLetterISOLanguageName -eq 'pt'

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

# Everything is copied to a stable location, so the cloned repo can be deleted afterwards
# and the menu can still be reconfigured (this script also runs from there).
$installDir = Join-Path $env:LOCALAPPDATA 'ClaudeCodeContextMenu'
New-Item -ItemType Directory -Path $installDir -Force | Out-Null
$configFile = Join-Path $installDir 'config.json'
$savedConfig = if (Test-Path $configFile) { Get-Content $configFile -Raw | ConvertFrom-Json } else { $null }

# Menu text: -Label, else the one saved last time, else a default for the system language
if (-not $Label) {
    $Label = if ($savedConfig.label) { $savedConfig.label } elseif ($pt) { 'Abrir IA aqui' } else { 'Open AI here' }
}

# --- Detect and choose ------------------------------------------------------
# Every possible entry, with whether it is available on this machine
$all = @()
foreach ($t in $catalog) {
    $cli = [bool](Get-Command $t.Exe -ErrorAction SilentlyContinue)
    $app = $t.Desktop -and (Test-DesktopInstalled $t.Id)
    foreach ($mode in 'terminal', 'desktop') {
        if ($mode -eq 'desktop' -and -not $t.Desktop) { continue }
        $available = if ($mode -eq 'terminal') { $cli } else { $app }
        $selected = ($Modes -contains $mode) -and $(if ($Tools) { $Tools -contains $t.Id } else { $available })
        $all += [pscustomobject]@{ Key = "$($t.Id)-$mode"; Tool = $t; Mode = $mode; Available = $available; Selected = $selected }
    }
}

# -Configure starts from the previous choice instead of from what was detected
if ($Configure -and -not $Tools -and $savedConfig) {
    $saved = @($savedConfig.entries)
    foreach ($e in $all) { $e.Selected = $saved -contains $e.Key }
}

$interactive = -not $NoPrompt -and [Environment]::UserInteractive -and -not $Tools
if ($interactive) {
    while ($true) {
        Write-Output ''
        Write-Output 'Which entries should appear in the menu?'
        for ($i = 0; $i -lt $all.Count; $i++) {
            $e = $all[$i]
            $mark = if ($e.Selected) { 'x' } else { ' ' }
            $note = if ($e.Available) { '' } else { '   (not found on this PC)' }
            Write-Output ('  [{0}] {1}  {2} ({3}){4}' -f $mark, ($i + 1), $e.Tool.Name, $e.Mode, $note)
        }
        $answer = Read-Host 'Type numbers to toggle (e.g. 2 4), A = all, N = none, Enter = confirm'
        if (-not $answer) { break }
        switch -Regex ($answer.Trim()) {
            '^[aA]$' { $all | ForEach-Object { $_.Selected = $true }; continue }
            '^[nN]$' { $all | ForEach-Object { $_.Selected = $false }; continue }
            default {
                foreach ($n in ($answer -split '[\s,]+' | Where-Object { $_ -match '^\d+$' })) {
                    $idx = [int]$n - 1
                    if ($idx -ge 0 -and $idx -lt $all.Count) { $all[$idx].Selected = -not $all[$idx].Selected }
                }
            }
        }
    }
}

$entries = @($all | Where-Object Selected | ForEach-Object { @{ Tool = $_.Tool; Mode = $_.Mode; Key = $_.Key } })
if (-not $entries) { throw 'No entries selected: nothing to install. Run again and select at least one (or install Claude Code, Codex or OpenCode).' }

# Remember the choice so -Configure and future installs start from it
@{ label = $Label; entries = @($entries | ForEach-Object { $_.Key }) } | ConvertTo-Json | Set-Content -Path $configFile -Encoding UTF8

# --- Files ------------------------------------------------------------------
function Copy-Here([string]$from, [string]$to) {
    # skip when the installer is already running from the install folder
    if ((Resolve-Path $from).Path -ne [IO.Path]::GetFullPath($to)) {
        Copy-Item -Path $from -Destination $to -Force
    }
}
# in the repo the icons are in assets\, in the install folder they sit next to this script
$assetDir = if (Test-Path (Join-Path $PSScriptRoot 'assets')) { Join-Path $PSScriptRoot 'assets' } else { $PSScriptRoot }
foreach ($f in 'ai-robot', 'claude-code', 'codex', 'opencode') {
    Copy-Here (Join-Path $assetDir "$f.ico") (Join-Path $installDir "$f.ico")
}
foreach ($f in 'install.ps1', 'uninstall.ps1', 'open-ai-desktop.ps1') {
    Copy-Here (Join-Path $PSScriptRoot $f) (Join-Path $installDir $f)
}
$robotIcon = Join-Path $installDir 'ai-robot.ico'
$iconFile = @{ claude = 'claude-code.ico'; codex = 'codex.ico'; opencode = 'opencode.ico' }
$helper = Join-Path $installDir 'open-ai-desktop.ps1'

# Double-clickable reconfigure (works without the repo) + Start menu shortcut
Set-Content -Path (Join-Path $installDir 'configure.cmd') -Encoding ASCII -Value @(
    '@echo off',
    'powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" -Configure',
    'pause'
)
$lnkPath = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Open AI here - Configure.lnk'
$lnk = (New-Object -ComObject WScript.Shell).CreateShortcut($lnkPath)
$lnk.TargetPath = Join-Path $installDir 'configure.cmd'
$lnk.WorkingDirectory = $installDir
$lnk.IconLocation = $robotIcon
$lnk.Save()

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
