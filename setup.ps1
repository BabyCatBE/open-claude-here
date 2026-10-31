<#
.SYNOPSIS
  Install, configure or uninstall the "Open AI here" right-click submenu in Windows Explorer
  (Claude Code, Codex, OpenCode - in the terminal or in the desktop app).

  Run it with no arguments: if the menu is not installed it offers to install it; if it is
  installed it offers Configure and Uninstall.
.PARAMETER Action
  install | configure | uninstall. Skips the question.
.PARAMETER Label
  Text of the submenu. Defaults to Portuguese if the system language is pt, otherwise English.
.PARAMETER Tools
  Which tools to add: claude, codex, opencode. Default: every tool found on this machine.
.PARAMETER Modes
  terminal, desktop. Default: both.
.PARAMETER NoPrompt
  Do not ask questions; install everything that was detected (or selected with -Tools/-Modes).
#>
param(
    [ValidateSet('install', 'configure', 'uninstall')][string]$Action,
    [string]$Label,
    [ValidateSet('claude', 'codex', 'opencode')][string[]]$Tools,
    [ValidateSet('terminal', 'desktop')][string[]]$Modes = @('terminal', 'desktop'),
    [switch]$NoPrompt
)

$ErrorActionPreference = 'Stop'
$pt = (Get-UICulture).TwoLetterISOLanguageName -eq 'pt'
$canAsk = -not $NoPrompt -and [Environment]::UserInteractive

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

# --- Keyboard menus ---------------------------------------------------------
# Arrow keys + Space + Enter when a real keyboard/console is attached. When input is piped
# (scripts, tests) the typed-number prompts further down are used instead.
$useKeys = $canAsk -and -not [Console]::IsInputRedirected

# --- Banner (pixel art) -----------------------------------------------------
# Half-block art in true colour: the AI robot plus one logo per tool. Only shown on a real
# console; output stays plain when piped.
function Show-Banner {
    try {
        Add-Type -Namespace Win -Name Con -ErrorAction Stop -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern IntPtr GetStdHandle(int n);
[DllImport("kernel32.dll")] public static extern bool GetConsoleMode(IntPtr h, out uint m);
[DllImport("kernel32.dll")] public static extern bool SetConsoleMode(IntPtr h, uint m);
'@
    } catch { }   # already added in this session
    $h = [Win.Con]::GetStdHandle(-11); $mode = [uint32]0
    [Win.Con]::GetConsoleMode($h, [ref]$mode) | Out-Null
    if (-not [Win.Con]::SetConsoleMode($h, $mode -bor 4)) { return }   # no ANSI colour support: skip the art
    [Console]::OutputEncoding = New-Object Text.UTF8Encoding $false

    $e = [char]27
    # In an art line: ~text~ = white on the art colour (used for ">_"), ^x^ = red on white (eyes)
    $arts = @(
        @{ Label = 'AI here'; Rgb = '80;150;230'; Lines = @(
            '  ▄▄▄▄▄▄▄▄  '
            ' ██████████ '
            ' ██^●^████^●^██ '
            ' ██▄▄▄▄▄▄██ '
            '  ▀▀▀▀▀▀▀▀  ') }
        @{ Label = 'Claude Code'; Rgb = '217;119;87'; Lines = @(
            '            '
            '  ▄██████▄  '
            '▄██ ████ ██▄'
            '████████████'
            '  ▐▌▐▌▐▌▐▌  ') }
        @{ Label = 'Codex'; Rgb = '110;130;255'; Lines = @(
            '   ▄▄██▄▄   '
            '▄██████████▄'
            '████~> _~█████'
            '▀██████████▀'
            '   ▀▀▀▀▀▀   ') }
        @{ Label = 'OpenCode'; Rgb = '210;210;210'; Lines = @(
            '  ▄▄▄▄▄▄▄▄  '
            '  █▀▀▀▀▀▀█  '
            '  █ ████ █  '
            '  █▄▄▄▄▄▄█  '
            '  ▀▀▀▀▀▀▀▀  ') }
    )
    function Paint([string]$line, [string]$rgb) {
        $o = "${e}[38;2;${rgb}m"; $mode = ''
        foreach ($ch in $line.ToCharArray()) {
            if ($ch -eq '~') { if ($mode -eq '~') { $mode = ''; $o += "${e}[0m${e}[38;2;${rgb}m" } else { $mode = '~'; $o += "${e}[48;2;${rgb}m${e}[38;2;255;255;255m" }; continue }
            if ($ch -eq '^') { if ($mode -eq '^') { $mode = ''; $o += "${e}[0m${e}[38;2;${rgb}m" } else { $mode = '^'; $o += "${e}[48;2;255;255;255m${e}[38;2;220;40;40m" }; continue }
            $o += $ch
        }
        return $o + "${e}[0m"
    }
    Write-Host ''
    for ($r = 0; $r -lt 5; $r++) {
        $row = ($arts | ForEach-Object { Paint $_.Lines[$r] $_.Rgb }) -join '  '
        Write-Host ("  " + $row)
    }
    $labels = ($arts | ForEach-Object { $_.Label.PadLeft(6 + [int]($_.Label.Length / 2)).PadRight(12) }) -join '  '
    Write-Host ("  ${e}[90m" + $labels + "${e}[0m")
}
if ($useKeys) { Show-Banner }

function Write-MenuLine([string]$text, [bool]$active) {
    $text = $text.PadRight([Math]::Max(1, [Console]::WindowWidth - 1)).Substring(0, [Math]::Max(1, [Console]::WindowWidth - 1))
    if ($active) { Write-Host $text -NoNewline -ForegroundColor Black -BackgroundColor White }
    else { Write-Host $text -NoNewline }
}

# Pick one item. Returns its index, or -1 on Esc.
function Select-Menu([string]$Title, [string[]]$Options, [string]$Hint) {
    Write-Host ''
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

# Tick/untick entries. Changes .Selected on the items; returns $false on Esc.
function Select-Entries([string]$Title, $Items) {
    Write-Host ''
    Write-Host $Title
    foreach ($e in $Items) { Write-Host '' }
    Write-Host 'Up/Down move   Space tick/untick   A all   N none   Enter confirm   Esc cancel' -ForegroundColor DarkGray
    $top = [Console]::CursorTop - ($Items.Count + 1)
    $cur = 0
    [Console]::CursorVisible = $false
    try {
        while ($true) {
            for ($i = 0; $i -lt $Items.Count; $i++) {
                $e = $Items[$i]
                $note = if ($e.Available) { '' } else { '   (not found on this PC)' }
                [Console]::SetCursorPosition(0, $top + $i)
                Write-MenuLine ("  {0} [{1}] {2} ({3}){4}" -f $(if ($i -eq $cur) { '>' } else { ' ' }), $(if ($e.Selected) { 'x' } else { ' ' }), $e.Tool.Name, $e.Mode, $note) ($i -eq $cur)
            }
            switch ([Console]::ReadKey($true).Key) {
                'UpArrow'   { $cur = ($cur - 1 + $Items.Count) % $Items.Count }
                'DownArrow' { $cur = ($cur + 1) % $Items.Count }
                'Spacebar'  { $Items[$cur].Selected = -not $Items[$cur].Selected }
                'A'         { $Items | ForEach-Object { $_.Selected = $true } }
                'N'         { $Items | ForEach-Object { $_.Selected = $false } }
                'Enter'     { return $true }
                'Escape'    { return $false }
            }
        }
    } finally {
        [Console]::CursorVisible = $true
        [Console]::SetCursorPosition(0, $top + $Items.Count + 1)
    }
}

# --- What to do -------------------------------------------------------------
$installed = Test-Path $parentKeys[0]

if (-not $Action) {
    if ($useKeys -and -not $Tools) {
        if ($installed) {
            $pick = Select-Menu 'Open AI here is installed.' @('Configure  - choose which entries appear in the menu', 'Uninstall') 'Up/Down move   Enter select   Esc quit'
            $Action = switch ($pick) { 0 { 'configure' } 1 { 'uninstall' } default { exit 0 } }
        } else {
            $pick = Select-Menu 'Open AI here is not installed.' @('Install  - you will pick what appears in the menu next') 'Enter install   Esc quit'
            if ($pick -ne 0) { exit 0 }
            $Action = 'install'
        }
    } elseif ($canAsk -and -not $Tools) {
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

# OpenCode Desktop has no way to open a folder from outside (its opencode:// links only handle
# login), so its desktop entry only launches the app.
$catalog = @(
    @{ Id = 'claude';   Name = 'Claude Code'; Exe = 'claude';   Desktop = $true; DesktopNote = '' }
    @{ Id = 'codex';    Name = 'Codex';       Exe = 'codex';    Desktop = $true; DesktopNote = '' }
    @{ Id = 'opencode'; Name = 'OpenCode';    Exe = 'opencode'; Desktop = $true; DesktopNote = 'no folder' }
)

function Test-DesktopInstalled([string]$id) {
    switch ($id) {
        'claude'   { return [bool](Get-AppxPackage -Name 'Claude' -ErrorAction SilentlyContinue) }
        'codex'    { return [bool](Get-AppxPackage -Name 'OpenAI.Codex' -ErrorAction SilentlyContinue) }
        'opencode' { return Test-Path (Join-Path $env:LOCALAPPDATA 'Programs\ai.opencode.desktop\OpenCode.exe') }
        default    { return $false }
    }
}

# Every possible entry. The recommended selection is "what is installed on this PC".
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

# Configure starts from the previous choice instead of from the recommendation
if ($Action -eq 'configure' -and -not $Tools -and $savedConfig) {
    $saved = @($savedConfig.entries)
    foreach ($e in $all) { $e.Selected = $saved -contains $e.Key }
}

$heading = if ($Action -eq 'configure') { 'Which entries should appear in the menu?' } else { 'Which entries should appear in the menu? (recommended ones are ticked)' }
if ($useKeys -and -not $Tools) {
    if (-not (Select-Entries $heading $all)) { Write-Output 'Cancelled. Nothing was changed.'; Wait-Close; exit 0 }
} elseif ($canAsk -and -not $Tools) {
    while ($true) {
        Write-Output ''
        Write-Output $heading
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

# Remember the choice so Configure starts from it
@{ label = $Label; entries = @($entries | ForEach-Object { $_.Key }) } | ConvertTo-Json | Set-Content -Path $configFile -Encoding UTF8

# --- Files ------------------------------------------------------------------
function Copy-Here([string]$from, [string]$to) {
    # skip when we are already running from the install folder
    if ((Resolve-Path $from).Path -ne [IO.Path]::GetFullPath($to)) { Copy-Item -Path $from -Destination $to -Force }
}
# in the repo the icons are in assets\, in the install folder they sit next to this script
$assetDir = if (Test-Path (Join-Path $PSScriptRoot 'assets')) { Join-Path $PSScriptRoot 'assets' } else { $PSScriptRoot }
foreach ($f in 'ai-robot', 'claude-code', 'codex', 'opencode') {
    Copy-Here (Join-Path $assetDir "$f.ico") (Join-Path $installDir "$f.ico")
}
foreach ($f in 'setup.ps1', 'setup.cmd', 'open-ai-desktop.ps1') {
    Copy-Here (Join-Path $PSScriptRoot $f) (Join-Path $installDir $f)
}
# files from earlier versions
foreach ($f in 'install.ps1', 'uninstall.ps1', 'configure.cmd') { Remove-Item (Join-Path $installDir $f) -Force -ErrorAction SilentlyContinue }
Remove-Item (Join-Path $programs 'Open AI here - Configure.lnk') -Force -ErrorAction SilentlyContinue

$robotIcon = Join-Path $installDir 'ai-robot.ico'
$iconFile = @{ claude = 'claude-code.ico'; codex = 'codex.ico'; opencode = 'opencode.ico' }
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
# Remove previous installs (old single-entry version and earlier runs of this one)
foreach ($old in $parentKeys + $menuKey + $legacyKeys) {
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

foreach ($parent in $parentKeys) {
    New-Item -Path $parent -Force | Out-Null
    Set-ItemProperty -Path $parent -Name 'MUIVerb' -Value $Label
    Set-ItemProperty -Path $parent -Name 'Icon' -Value $robotIcon
    Set-ItemProperty -Path $parent -Name 'ExtendedSubCommandsKey' -Value 'Directory\ContextMenus\AIHere'
}

Write-Output ''
Write-Output "Installed '$Label' with:"
$entries | ForEach-Object { Write-Output ("  - {0} ({1})" -f $_.Tool.Name, $_.Mode) }
Write-Output "On Windows 11 it is under 'Show more options' (Shift+right-click)."
Write-Output "To change this later, open 'Open AI here - Setup' from the Start menu."
Wait-Close
