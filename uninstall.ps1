$classes = 'HKCU:\Software\Classes'
foreach ($key in
    "$classes\Directory\shell\AIHere",
    "$classes\Directory\Background\shell\AIHere",
    "$classes\Directory\ContextMenus\AIHere",
    # previous single-entry version
    "$classes\Directory\shell\ClaudeCode",
    "$classes\Directory\Background\shell\ClaudeCode") {
    Remove-Item $key -Recurse -Force -ErrorAction SilentlyContinue
}
Remove-Item (Join-Path $env:LOCALAPPDATA 'ClaudeCodeContextMenu') -Recurse -Force -ErrorAction SilentlyContinue
Write-Output 'Uninstalled.'
