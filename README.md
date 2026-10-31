# Open Claude Here

Right-click any folder in Windows Explorer → **Open Claude Code here**, with a little pixel-art Claude robot as the icon. It opens a terminal already inside that folder, running `claude`.

Clique com o botão direito em qualquer pasta → **Abrir sessão Claude Code aqui**. Abre o terminal já dentro da pasta, rodando o `claude`.

Works in two places:

- Right-click **on a folder**
- Right-click the **background inside a folder** (works in empty folders too)

## Requirements

- Windows 10/11
- [Claude Code](https://claude.com/claude-code) installed (`claude` available in your PATH)
- [Windows Terminal](https://aka.ms/terminal) (recommended; falls back to `cmd.exe` if missing)

## Install

```powershell
git clone https://github.com/BabyCatBE/open-claude-here.git
cd open-claude-here
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

No admin rights needed. Everything is written under `HKCU` (your user only) plus an icon copied to `%LOCALAPPDATA%\ClaudeCodeContextMenu`.

Custom menu text:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Label "Claude here"
```

## Windows 11 note

Windows 11's new context menu hides classic entries. Use **Show more options** (or **Shift + right-click**) to see it. Showing it in the new menu requires a signed shell extension package, which is out of scope here.

## Uninstall

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
```

## How it works

Two registry keys under `HKCU\Software\Classes\Directory`:

| Key | Triggered by | Command |
|---|---|---|
| `shell\ClaudeCode` | right-click on a folder | `wt.exe -d "%1" claude` |
| `Background\shell\ClaudeCode` | right-click inside a folder | `wt.exe -d "%V" claude` |

## License

MIT
