<#
.SYNOPSIS
  Install, configure or uninstall the "Open AI here" right-click submenu in Windows Explorer.
  Which AI tools it knows about is described in tools.json (Claude Code, Codex, OpenCode, ...).

  Run it with no arguments: if the menu is not installed it offers to install it; if it is
  installed it offers Configure and Uninstall.
.PARAMETER Action
  install | configure | uninstall. Skips the question.
.PARAMETER Label
  Text of the submenu. Defaults to Portuguese if the system language is pt, otherwise English.
.PARAMETER Tools
  Which tools to add (ids from tools.json, e.g. claude,codex). Default: every tool found on this PC.
.PARAMETER Modes
  terminal, desktop. Default: both.
.PARAMETER Entries
  Exact list of entries, e.g. claude-terminal,codex-desktop. Skips every question.
.PARAMETER NoPrompt
  Do not ask questions; install everything that was detected (or selected with -Tools/-Modes).
#>
param(
    [ValidateSet('install', 'configure', 'uninstall')][string]$Action,
    [string]$Label,
    [string[]]$Tools,
    [string[]]$Modes = @('terminal', 'desktop'),
    [string[]]$Entries,
    [switch]$NoPrompt
)

$ErrorActionPreference = 'Stop'

# `powershell -File setup.ps1 -Tools a,b` hands "a,b" over as ONE string: split lists ourselves
function Split-List($value) { @($value | ForEach-Object { $_ -split '[,;\s]+' } | Where-Object { $_ }) }
$Tools = Split-List $Tools
$Entries = Split-List $Entries
$Modes = Split-List $Modes
foreach ($m in $Modes) { if ($m -notin 'terminal', 'desktop') { throw "Unknown mode '$m'. Use terminal and/or desktop." } }

$pt = (Get-UICulture).TwoLetterISOLanguageName -eq 'pt'
$explicit = [bool]($Tools -or $Entries)
$canAsk = -not $NoPrompt -and [Environment]::UserInteractive -and -not $explicit

# --- Locations --------------------------------------------------------------
$classes    = 'HKCU:\Software\Classes'
$menuKey    = "$classes\Directory\ContextMenus\AIHere"
$parentKeys = "$classes\Directory\shell\AIHere", "$classes\Directory\Background\shell\AIHere"
$legacyKeys = "$classes\Directory\shell\ClaudeCode", "$classes\Directory\Background\shell\ClaudeCode"
# Everything is copied to a stable place, so the cloned repo can be deleted afterwards and the
# menu can still be configured or uninstalled (this script also runs from there).
$installDir = Join-Path $env:LOCALAPPDATA 'ClaudeCodeContextMenu'
$configFile = Join-Path $installDir 'config.json'
$programs   = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
$lnkPath    = Join-Path $programs 'Open AI here - Setup.lnk'

function Wait-Close {
    # setup.cmd sets this so a double-clicked window stays open until the user has read it
    if ($env:AIHERE_PAUSE) { Read-Host 'Press Enter to close' | Out-Null }
}

# --- Console look -----------------------------------------------------------
# Arrow keys + Space + Enter on a real console. With piped input (scripts, tests) the typed
# prompts further down are used instead. Colours need ANSI support; without it, plain text.
$useKeys = $canAsk -and -not [Console]::IsInputRedirected
$esc = [char]27

function Enable-Ansi {
    try {
        Add-Type -Namespace Win -Name Con -ErrorAction Stop -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern IntPtr GetStdHandle(int n);
[DllImport("kernel32.dll")] public static extern bool GetConsoleMode(IntPtr h, out uint m);
[DllImport("kernel32.dll")] public static extern bool SetConsoleMode(IntPtr h, uint m);
'@
    } catch { }   # already added in this session
    $h = [Win.Con]::GetStdHandle(-11); $mode = [uint32]0
    if (-not [Win.Con]::GetConsoleMode($h, [ref]$mode)) { return $false }
    return [Win.Con]::SetConsoleMode($h, $mode -bor 4)
}
$ansi = $useKeys -and (Enable-Ansi)

function Show-Banner {
    if (-not $ansi) { return }
    Clear-Host
    # A robot drawn with code characters, with the program name next to it
    $robot = @(
        @{ T = '        _        '; C = '120;200;255' }
        @{ T = '      _(_)_      '; C = '110;190;255' }
        @{ T = '   .-"-----"-.   '; C = '100;175;255' }
        @{ T = '  /  [o] [o]  \  '; C = '90;160;255' }
        @{ T = '  | </_____\> |  '; C = '85;145;250' }
        @{ T = '  \  |_|_|_|  /  '; C = '80;130;245' }
        @{ T = "   '-._____.-'   "; C = '75;115;235' }
    )
    $right = @{
        2 = "${esc}[1;97m</> Open AI here${esc}[0m"
        3 = "${esc}[90mright-click any folder${esc}[0m"
        4 = "${esc}[90mand open an AI right there${esc}[0m"
    }
    Write-Host ''
    for ($i = 0; $i -lt $robot.Count; $i++) {
        $line = "  ${esc}[38;2;$($robot[$i].C)m$($robot[$i].T)${esc}[0m"
        if ($right.ContainsKey($i)) { $line += '  ' + $right[$i] }
        Write-Host $line
    }
    Write-Host ''
}

function Write-MenuLine([string]$text, [bool]$active) {
    $w = [Math]::Max(1, [Console]::WindowWidth - 1)
    $text = $text.PadRight($w).Substring(0, $w)
    if ($active) { Write-Host $text -NoNewline -ForegroundColor Black -BackgroundColor White }
    else { Write-Host $text -NoNewline }
}

# One checklist row: [x] <tool glyph> <terminal/screen glyph> Name   mode
function Write-EntryRow($entry, [bool]$active) {
    $w = [Math]::Max(1, [Console]::WindowWidth - 1)
    $mark = if ($entry.Selected) { 'x' } else { ' ' }
    $modeGlyph = if ($entry.Mode -eq 'terminal') { '[>_]' } else { '[::]' }
    $suffix = $entry.Mode
    if ($entry.Mode -eq 'desktop' -and $entry.Note) { $suffix = "desktop, $($entry.Note)" }
    if (-not $entry.Available) { $suffix += '  (not found on this PC)' }
    $glyph = $entry.Tool.glyph.PadRight(3)
    $pointer = if ($active) { '>' } else { ' ' }
    $plain = "  $pointer [$mark] $glyph $modeGlyph  $($entry.Tool.name)  $suffix"
    if (-not $ansi) { Write-MenuLine $plain $active; return }
    $pad = ' ' * [Math]::Max(0, $w - $plain.Length)
    $base = if ($active) { "${esc}[47m${esc}[30m" } else { "${esc}[0m" }
    $dim = if ($active) { "${esc}[90m" } else { "${esc}[90m" }
    $fg = if ($active) { "${esc}[30m" } else { "${esc}[39m" }
    $line = "${base}  $pointer [$mark] ${esc}[38;2;$($entry.Tool.color)m$glyph${fg} ${dim}$modeGlyph${fg}  $($entry.Tool.name)  ${dim}$suffix${fg}$pad${esc}[0m"
    Write-Host $line -NoNewline
}

# Pick one item. Returns its index, or -1 on Esc.
function Select-Menu([string]$Title, [string[]]$Options, [string]$Hint) {
    Write-Host $Title
    foreach ($o in $Options) { Write-Host '' }
    Write-Host $Hint -ForegroundColor DarkGray
    $top = [Console]::CursorTop - ($Options.Count + 1)
    $sel = 0
    [Console]::CursorVisible = $false
    try {
        while ($true) {
            for ($i = 0; $i -lt $Options.Count; $i++) {
                [Console]::SetCursorPosition(0, $top + $i)
                Write-MenuLine ("  {0} {1}" -f $(if ($i -eq $sel) { '>' } else { ' ' }), $Options[$i]) ($i -eq $sel)
            }
            switch ([Console]::ReadKey($true).Key) {
                'UpArrow'   { $sel = ($sel - 1 + $Options.Count) % $Options.Count }
                'DownArrow' { $sel = ($sel + 1) % $Options.Count }
                'Enter'     { return $sel }
                'Escape'    { return -1 }
            }
        }
    } finally {
        [Console]::CursorVisible = $true
        [Console]::SetCursorPosition(0, $top + $Options.Count + 1)
    }
}

# Tick/untick entries. Shows what is available on this PC; M reveals the rest.
# Changes .Selected on the items; returns $false on Esc.
function Select-Entries([string]$Title, $Items) {
    $showAll = $false
    $base = @($Items | Where-Object { $_.Available -or $_.Selected })
    if (-not $base) { $showAll = $true }
    Write-Host $Title
    $rows = [Math]::Min($Items.Count, [Math]::Max(3, [Console]::WindowHeight - [Console]::CursorTop - 4))
    1..$rows | ForEach-Object { Write-Host '' }
    Write-Host ''   # status line
    Write-Host 'Up/Down move   Space tick   A all   N none   M other tools   Enter confirm   Esc cancel' -ForegroundColor DarkGray
    $top = [Console]::CursorTop - ($rows + 2)
    $cur = 0; $off = 0
    $w = [Math]::Max(1, [Console]::WindowWidth - 1)
    [Console]::CursorVisible = $false
    try {
        while ($true) {
            $vis = @(if ($showAll) { $Items } else { $base })
            if ($cur -ge $vis.Count) { $cur = $vis.Count - 1 }
            if ($cur -lt 0) { $cur = 0 }
            if ($cur -lt $off) { $off = $cur }
            if ($cur -ge $off + $rows) { $off = $cur - $rows + 1 }
            for ($r = 0; $r -lt $rows; $r++) {
                [Console]::SetCursorPosition(0, $top + $r)
                $i = $off + $r
                if ($i -lt $vis.Count) { Write-EntryRow $vis[$i] ($i -eq $cur) } else { Write-Host (' ' * $w) -NoNewline }
            }
            [Console]::SetCursorPosition(0, $top + $rows)
            $status = if ($showAll) { 'showing every tool the menu knows (M to show only what is on this PC)' } else { 'showing tools found on this PC (M to see the others)' }
            Write-Host ($status.PadRight($w).Substring(0, $w)) -NoNewline -ForegroundColor DarkGray
            switch ([Console]::ReadKey($true).Key) {
                'UpArrow'   { $cur = ($cur - 1 + $vis.Count) % $vis.Count }
                'DownArrow' { $cur = ($cur + 1) % $vis.Count }
                'Spacebar'  { $vis[$cur].Selected = -not $vis[$cur].Selected }
                'A'         { $vis | ForEach-Object { $_.Selected = $true } }
                'N'         { $vis | ForEach-Object { $_.Selected = $false } }
                'M'         { $showAll = -not $showAll; $cur = 0; $off = 0 }
                'Enter'     { return $true }
                'Escape'    { return $false }
            }
        }
    } finally {
        [Console]::CursorVisible = $true
        [Console]::SetCursorPosition(0, $top + $rows + 2)
    }
}

# --- What to do -------------------------------------------------------------
$installed = Test-Path $parentKeys[0]
if ($useKeys) { Show-Banner }

if (-not $Action) {
    if ($useKeys) {
        if ($installed) {
            $pick = Select-Menu 'Open AI here is installed.' @('Configure  - choose which entries appear in the menu', 'Uninstall') 'Up/Down move   Enter select   Esc quit'
            $Action = switch ($pick) { 0 { 'configure' } 1 { 'uninstall' } default { exit 0 } }
        } else {
            $pick = Select-Menu 'Open AI here is not installed.' @('Install  - you will pick what appears in the menu next') 'Enter install   Esc quit'
            if ($pick -ne 0) { exit 0 }
            $Action = 'install'
        }
    } elseif ($canAsk) {
        Write-Output ''
        if ($installed) {
            Write-Output 'Open AI here is installed.'
            Write-Output '  [1] Configure  - choose which entries appear in the menu'
            Write-Output '  [2] Uninstall'
            Write-Output '  [Q] Quit'
            switch -Regex ((Read-Host 'Choose').Trim()) {
                '^1$'   { $Action = 'configure' }
                '^2$'   { $Action = 'uninstall' }
                default { exit 0 }
            }
        } else {
            Write-Output 'Open AI here is not installed.'
            $answer = Read-Host 'Press Enter to install (Q to quit)'
            if ($answer -match '^[qQ]') { exit 0 }
            $Action = 'install'
        }
    } else {
        $Action = 'install'
    }
}
# nothing to configure yet: configuring a missing install is just installing
if ($Action -eq 'configure' -and -not $installed) { $Action = 'install' }

# --- Uninstall --------------------------------------------------------------
if ($Action -eq 'uninstall') {
    foreach ($key in $parentKeys + $menuKey + $legacyKeys) {
        Remove-Item $key -Recurse -Force -ErrorAction SilentlyContinue
    }
    Remove-Item $lnkPath -Force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $programs 'Open AI here - Configure.lnk') -Force -ErrorAction SilentlyContinue
    if ($PSScriptRoot -eq $installDir) {
        # we are running from the folder we want to delete: remove it once this script has exited
        Start-Process cmd.exe -WindowStyle Hidden -ArgumentList "/c ping -n 4 127.0.0.1 >nul & rmdir /s /q `"$installDir`""
    } else {
        Remove-Item $installDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Output 'Uninstalled.'
    Wait-Close
    exit 0
}

# --- Install / Configure ----------------------------------------------------
New-Item -ItemType Directory -Path $installDir -Force | Out-Null
$savedConfig = if (Test-Path $configFile) { Get-Content $configFile -Raw | ConvertFrom-Json } else { $null }

# Menu text: -Label, else the one saved last time, else a default for the system language
if (-not $Label) {
    $Label = if ($savedConfig.label) { $savedConfig.label } elseif ($pt) { 'Abrir IA aqui' } else { 'Open AI here' }
}

# The list of tools lives in tools.json: add a tool there and it shows up here.
# (Windows PowerShell 5.1 returns the JSON array as one object, so flatten it)
$catalog = @((Get-Content (Join-Path $PSScriptRoot 'tools.json') -Raw -Encoding UTF8 | ConvertFrom-Json) | ForEach-Object { $_ })
foreach ($id in $Tools) {
    if ($catalog.id -notcontains $id) { throw "Unknown tool '$id'. Known tools: $($catalog.id -join ', ')" }
}

function Test-Detect($detect) {
    if (-not $detect) { return $false }
    if ($detect.appx) { return [bool](Get-AppxPackage -Name $detect.appx -ErrorAction SilentlyContinue) }
    if ($detect.path) { return Test-Path ([Environment]::ExpandEnvironmentVariables($detect.path)) }
    if ($detect.exe)  { return [bool](Get-Command $detect.exe -ErrorAction SilentlyContinue) }
    return $false
}

# Every possible entry. The recommended selection is "what is installed on this PC".
$all = @()
foreach ($t in $catalog) {
    foreach ($mode in 'terminal', 'desktop') {
        $def = $t.$mode
        if (-not $def) { continue }
        $available = if ($mode -eq 'terminal') { [bool](Get-Command $def.exe -ErrorAction SilentlyContinue) } else { Test-Detect $def.detect }
        $key = "$($t.id)-$mode"
        $selected = if ($Entries) { $Entries -contains $key }
                    else { ($Modes -contains $mode) -and $(if ($Tools) { $Tools -contains $t.id } else { $available }) }
        $note = if ($mode -eq 'desktop') { $def.note } else { '' }
        $all += [pscustomobject]@{ Key = $key; Tool = $t; Mode = $mode; Available = $available; Selected = $selected; Note = $note }
    }
}

# Configure starts from the previous choice instead of from the recommendation
if ($Action -eq 'configure' -and -not $explicit -and $savedConfig) {
    $saved = @($savedConfig.entries)
    foreach ($e in $all) { $e.Selected = $saved -contains $e.Key }
}

$heading = if ($Action -eq 'configure') { 'Which entries should appear in the menu?' } else { 'Which entries should appear in the menu? (the ones found on this PC are ticked)' }
if ($useKeys) {
    Show-Banner   # clears the Configure/Uninstall question, keeps the robot on top
    if (-not (Select-Entries $heading $all)) { Write-Output 'Cancelled. Nothing was changed.'; Wait-Close; exit 0 }
} elseif ($canAsk) {
    while ($true) {
        Write-Output ''
        Write-Output $heading
        for ($i = 0; $i -lt $all.Count; $i++) {
            $e = $all[$i]
            $mark = if ($e.Selected) { 'x' } else { ' ' }
            $note = if ($e.Available) { '' } else { '   (not found on this PC)' }
            Write-Output ('  [{0}] {1}  {2} ({3}){4}' -f $mark, ($i + 1), $e.Tool.name, $e.Mode, $note)
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

$chosen = @($all | Where-Object Selected)
if (-not $chosen) { throw 'No entries selected: nothing to install. Run again and select at least one (or install one of the supported tools).' }

# Remember the choice so Configure starts from it
@{ label = $Label; entries = @($chosen | ForEach-Object { $_.Key }) } | ConvertTo-Json | Set-Content -Path $configFile -Encoding UTF8

# --- Files ------------------------------------------------------------------
function Copy-Here([string]$from, [string]$to) {
    # skip when we are already running from the install folder
    if (-not (Test-Path $from)) { return }
    if ((Resolve-Path $from).Path -ne [IO.Path]::GetFullPath($to)) { Copy-Item -Path $from -Destination $to -Force }
}
# in the repo the icons are in assets\, in the install folder they sit next to this script
$assetDir = if (Test-Path (Join-Path $PSScriptRoot 'assets')) { Join-Path $PSScriptRoot 'assets' } else { $PSScriptRoot }
foreach ($f in @('ai-robot.ico') + @($catalog | ForEach-Object { $_.icon })) {
    Copy-Here (Join-Path $assetDir $f) (Join-Path $installDir $f)
}
foreach ($f in 'setup.ps1', 'setup.cmd', 'open-ai-desktop.ps1', 'tools.json') {
    Copy-Here (Join-Path $PSScriptRoot $f) (Join-Path $installDir $f)
}
# files from earlier versions
foreach ($f in 'install.ps1', 'uninstall.ps1', 'configure.cmd') { Remove-Item (Join-Path $installDir $f) -Force -ErrorAction SilentlyContinue }
Remove-Item (Join-Path $programs 'Open AI here - Configure.lnk') -Force -ErrorAction SilentlyContinue

$robotIcon = Join-Path $installDir 'ai-robot.ico'
$helper = Join-Path $installDir 'open-ai-desktop.ps1'

# Start menu shortcut to this same setup (works without the repo)
$lnk = (New-Object -ComObject WScript.Shell).CreateShortcut($lnkPath)
$lnk.TargetPath = Join-Path $installDir 'setup.cmd'
$lnk.WorkingDirectory = $installDir
$lnk.IconLocation = $robotIcon
$lnk.Save()

# --- Commands ---------------------------------------------------------------
$hasWt = [bool](Get-Command wt.exe -ErrorAction SilentlyContinue)

function Get-TerminalCommand($t) {
    $command = if ($t.terminal.command) { $t.terminal.command } else { $t.terminal.exe }
    # npm-installed CLIs are .cmd/.ps1 shims, which need cmd.exe to run
    $src = (Get-Command $t.terminal.exe -ErrorAction SilentlyContinue | Select-Object -First 1).Source
    $run = if ($src -and $src -like '*.exe') { $command } else { "cmd.exe /c $command" }
    # %V works for folders and for the folder background. "<dir>\." keeps the closing quote
    # safe when the path ends in a backslash (drive root).
    if ($hasWt) { return "wt.exe -d `"%V\.`" $run" }
    return "cmd.exe /k cd /d `"%V`" && $command"
}

function Get-DesktopCommand($t) {
    "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$helper`" -Tool $($t.id) -Path `"%V\.`""
}

# --- Registry ---------------------------------------------------------------
# Remove previous installs (old single-entry version and earlier runs of this one)
foreach ($old in $parentKeys + $menuKey + $legacyKeys) {
    Remove-Item -Path $old -Recurse -Force -ErrorAction SilentlyContinue
}

# The submenu items, shared by "right-click a folder" and "right-click inside a folder"
New-Item -Path "$menuKey\shell" -Force | Out-Null
$i = 0
$lastTool = $null
foreach ($e in $chosen) {
    $i++
    $item = "$menuKey\shell\{0:D2}_{1}_{2}" -f $i, $e.Tool.id, $e.Mode
    New-Item -Path $item -Force | Out-Null
    $suffix = if ($e.Note) { "$($e.Mode), $($e.Note)" } else { $e.Mode }
    Set-ItemProperty -Path $item -Name 'MUIVerb' -Value ("{0} ({1})" -f $e.Tool.name, $suffix)
    $toolIcon = Join-Path $installDir $e.Tool.icon
    Set-ItemProperty -Path $item -Name 'Icon' -Value $(if (Test-Path $toolIcon) { $toolIcon } else { $robotIcon })
    if ($lastTool -and $lastTool -ne $e.Tool.id) { Set-ItemProperty -Path $item -Name 'CommandFlags' -Value 0x20 -Type DWord }  # separator before
    $lastTool = $e.Tool.id
    New-Item -Path "$item\command" -Force | Out-Null
    $cmd = if ($e.Mode -eq 'terminal') { Get-TerminalCommand $e.Tool } else { Get-DesktopCommand $e.Tool }
    Set-ItemProperty -Path "$item\command" -Name '(Default)' -Value $cmd
}

foreach ($parent in $parentKeys) {
    New-Item -Path $parent -Force | Out-Null
    Set-ItemProperty -Path $parent -Name 'MUIVerb' -Value $Label
    Set-ItemProperty -Path $parent -Name 'Icon' -Value $robotIcon
    Set-ItemProperty -Path $parent -Name 'ExtendedSubCommandsKey' -Value 'Directory\ContextMenus\AIHere'
}

Write-Output ''
Write-Output "Installed '$Label' with:"
$chosen | ForEach-Object { Write-Output ("  - {0} ({1})" -f $_.Tool.name, $_.Mode) }
Write-Output "On Windows 11 it is under 'Show more options' (Shift+right-click)."
Write-Output "To change this later, open 'Open AI here - Setup' from the Start menu."
Wait-Close
