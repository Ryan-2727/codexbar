param([switch]$Remove)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$taskName = 'CodexQuotaBar Watchdog'
$watchdog = Join-Path $PSScriptRoot 'CodexQuotaBar-Watchdog.ps1'
$launcher = Join-Path $PSScriptRoot 'Launch-CodexQuotaBar.vbs'
$stopScript = Join-Path $PSScriptRoot 'Stop-Existing-CodexQuotaBars.ps1'
$shortcutPath = Join-Path ([Environment]::GetFolderPath('Startup')) 'Codex Quota Bar.lnk'

function Remove-LegacyShortcut {
    Remove-Item -LiteralPath $shortcutPath -Force -ErrorAction SilentlyContinue
}

function Remove-WatchdogTask {
    $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existingTask) {
        Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    }
}

if ($Remove) {
    Remove-WatchdogTask
    if (Test-Path -LiteralPath $stopScript) {
        & $stopScript
    }
    Remove-LegacyShortcut
    Write-Host 'Removed ChatGPT/Codex lifecycle autostart.'
    exit 0
}

if (-not (Test-Path -LiteralPath $watchdog)) { throw 'CodexQuotaBar-Watchdog.ps1 was not found.' }
if (-not (Test-Path -LiteralPath $launcher)) { throw 'Launch-CodexQuotaBar.vbs was not found.' }

Remove-WatchdogTask
Remove-LegacyShortcut

$wscriptPath = "$env:SystemRoot\System32\wscript.exe"
$arguments = "`"$launcher`""
$userId = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

$action = New-ScheduledTaskAction -Execute $wscriptPath -Argument $arguments -WorkingDirectory $PSScriptRoot
$logonTrigger = New-ScheduledTaskTrigger -AtLogOn -User $userId
$healthTrigger = New-ScheduledTaskTrigger `
    -Once `
    -At (Get-Date).AddMinutes(1) `
    -RepetitionInterval (New-TimeSpan -Minutes 1) `
    -RepetitionDuration (New-TimeSpan -Days 3650)
$principal = New-ScheduledTaskPrincipal -UserId $userId -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -RestartCount 999 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -MultipleInstances IgnoreNew

$task = New-ScheduledTask -Action $action -Trigger @($logonTrigger, $healthTrigger) -Principal $principal -Settings $settings
Register-ScheduledTask -TaskName $taskName -InputObject $task -Force | Out-Null
Start-ScheduledTask -TaskName $taskName

Write-Host "Installed ChatGPT/Codex lifecycle autostart: $taskName"
