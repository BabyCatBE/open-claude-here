Remove-Item 'HKCU:\Software\Classes\Directory\shell\ClaudeCode' -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item 'HKCU:\Software\Classes\Directory\Background\shell\ClaudeCode' -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $env:LOCALAPPDATA 'ClaudeCodeContextMenu') -Recurse -Force -ErrorAction SilentlyContinue
Write-Output 'Uninstalled.'
