# Open Claude Here

Right-click any folder in Windows Explorer → **Open AI here** → pick a tool and where to run it. No more `cd C:\Users\...` before starting a session.

Clique com o botão direito em qualquer pasta → **Abrir IA aqui** → escolha a ferramenta e onde abrir. Sem precisar digitar `cd` antes.

```
Open AI here ▸  Claude Code (terminal)
                Claude Code (desktop)
                ─────────────
                Codex (terminal)
                Codex (desktop)
                ─────────────
                OpenCode (terminal)
                OpenCode (desktop, no folder)
```

The installer detects what you have and only adds those entries. It works in two places:

- Right-click **on a folder**
- Right-click the **background inside a folder** (works in empty folders too)

## What opens what

| Entry | What it does | Notes |
|---|---|---|
| Claude Code (terminal) | `wt.exe -d <folder> claude` | falls back to `cmd.exe` without Windows Terminal |
| Claude Code (desktop) | opens `claude://code/new?folder=<folder>` | Claude Desktop asks you to confirm the folder. If the app is already open, the folder may be added to the current window. |
| Codex (terminal) | runs `codex` in the folder | |
| Codex (desktop) | `codex app <folder>` | |
| OpenCode (terminal) | runs `opencode` in the folder | |
| OpenCode (desktop, no folder) | opens the app | OpenCode Desktop has no way to open a folder from outside (its `opencode://` links only handle login), so pick the project inside the app. |

## Requirements

- Windows 10/11
- At least one of: [Claude Code](https://claude.com/claude-code), [Codex](https://developers.openai.com/codex), [OpenCode](https://opencode.ai) (CLI in your PATH, and/or the desktop app)
- [Windows Terminal](https://aka.ms/terminal) (recommended; falls back to `cmd.exe` if missing)

## Install

```powershell
git clone https://github.com/BabyCatBE/open-claude-here.git
cd open-claude-here
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

The installer lists what it found and asks `[Y/n]` for each entry. No admin rights needed: everything is written under `HKCU` (your user only), plus files copied to `%LOCALAPPDATA%\ClaudeCodeContextMenu`.

Options:

```powershell
# no questions, install everything detected
.\install.ps1 -NoPrompt

# choose tools and/or modes yourself
.\install.ps1 -Tools claude,codex -Modes terminal

# custom submenu text
.\install.ps1 -Label "AI here"
```

Re-running the installer replaces the previous menu (including the old single "Open Claude Code here" entry).

## Windows 11 note

Windows 11's new context menu hides classic entries. Use **Show more options** (or **Shift + right-click**) to see it. Showing it in the new menu requires a signed shell extension package, which is out of scope here.

## Uninstall

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
```

## How it works

A submenu defined once under `HKCU\Software\Classes\Directory\ContextMenus\AIHere`, referenced by two parent entries:

| Key | Triggered by |
|---|---|
| `Directory\shell\AIHere` | right-click on a folder |
| `Directory\Background\shell\AIHere` | right-click inside a folder |

Each item uses `%V` (the folder) as its working directory. Terminal items call `wt.exe` directly; desktop items go through `open-ai-desktop.ps1`.

## Icons

- Submenu robot: [Twemoji](https://github.com/jdecked/twemoji) 🤖 (© Twitter, Inc. and contributors, [CC-BY 4.0](https://creativecommons.org/licenses/by/4.0/))
- Claude Code: pixel-art robot made for this project
- Codex: the Codex logo from [LobeHub Icons](https://github.com/lobehub/lobe-icons) (MIT), rendered as `.ico`
- OpenCode: the icon embedded in the OpenCode desktop app
- The Codex and OpenCode logos belong to OpenAI and the OpenCode project respectively, and are used only to identify each tool in the menu.

## License

MIT
