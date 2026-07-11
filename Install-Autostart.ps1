param([switch]$Remove)

$launcher = Join-Path $PSScriptRoot 'Start-CodexQuotaBar.cmd'
$shortcutPath = Join-Path ([Environment]::GetFolderPath('Startup')) 'Codex Quota Bar.lnk'

if ($Remove) {
    Remove-Item -LiteralPath $shortcutPath -Force -ErrorAction SilentlyContinue
    Write-Host '已移除开机启动项。'
    exit 0
}

if (-not (Test-Path -LiteralPath $launcher)) { throw '找不到 Start-CodexQuotaBar.cmd。' }

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = "$env:SystemRoot\System32\cmd.exe"
$shortcut.Arguments = "/c `"$launcher`""
$shortcut.WorkingDirectory = $PSScriptRoot
$shortcut.WindowStyle = 7
$shortcut.Save()
Write-Host "已创建开机启动项：$shortcutPath"
