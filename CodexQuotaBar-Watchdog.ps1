param(
    [int]$PollSeconds = 2,
    [switch]$Once
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$mainScript = Join-Path $PSScriptRoot 'CodexQuotaBar.ps1'
$logPath = Join-Path $PSScriptRoot 'CodexQuotaBar-Watchdog.log'
$archiveLogPath = "$logPath.1"
$maxLogBytes = 256KB

function Write-WatchdogLog {
    param([string]$Message)

    try {
        if ((Test-Path -LiteralPath $logPath) -and (Get-Item -LiteralPath $logPath).Length -ge $maxLogBytes) {
            Remove-Item -LiteralPath $archiveLogPath -Force -ErrorAction SilentlyContinue
            Move-Item -LiteralPath $logPath -Destination $archiveLogPath -Force
        }
        Add-Content -LiteralPath $logPath -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Message" -Encoding UTF8
    }
    catch {
        # Logging must never stop lifecycle monitoring.
    }
}

function Get-CodexProcess {
    Get-CimInstance Win32_Process -Filter "Name='ChatGPT.exe'" -ErrorAction SilentlyContinue |
        Where-Object {
            $_.ExecutablePath -and
            $_.ExecutablePath.IndexOf('OpenAI.Codex_', [StringComparison]::OrdinalIgnoreCase) -ge 0 -and
            $_.CommandLine -notmatch '(?i)(^|\s)--type='
        }
}

function Get-QuotaBarProcess {
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe'" -ErrorAction SilentlyContinue |
        Where-Object {
            $_.CommandLine -and
            $_.CommandLine.IndexOf($mainScript, [StringComparison]::OrdinalIgnoreCase) -ge 0 -and
            $_.CommandLine -notmatch '(?i)-(CheckRpc|ValidateOnly)\b'
        }
}

$lastCodexRunning = $null
Write-WatchdogLog "Watchdog started. PID=$PID"

try {
    do {
        try {
            $codexProcess = Get-CodexProcess | Select-Object -First 1
            $codexRunning = $null -ne $codexProcess
            $barProcesses = @(Get-QuotaBarProcess | Sort-Object ProcessId)

            if ($codexRunning -ne $lastCodexRunning) {
                $state = if ($codexRunning) { "running, PID=$($codexProcess.ProcessId)" } else { 'stopped' }
                Write-WatchdogLog "ChatGPT/Codex is $state."
                $lastCodexRunning = $codexRunning
            }

            if ($codexRunning -and $barProcesses.Count -eq 0) {
                $barProcess = Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -PassThru -ArgumentList @(
                    '-NoProfile',
                    '-ExecutionPolicy', 'Bypass',
                    '-File', "`"$mainScript`""
                )
                Write-WatchdogLog "Quota bar started. PID=$($barProcess.Id)"
            }
            elseif ($codexRunning -and $barProcesses.Count -gt 1) {
                $duplicates = @($barProcesses | Select-Object -Skip 1)
                $duplicates | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
                Write-WatchdogLog "Stopped duplicate quota bars. PIDs=$($duplicates.ProcessId -join ',')"
            }
            elseif (-not $codexRunning -and $barProcesses.Count -gt 0) {
                $barProcesses | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
                Write-WatchdogLog "Quota bar stopped. PIDs=$($barProcesses.ProcessId -join ',')"
            }
        }
        catch {
            Write-WatchdogLog "ERROR $($_.Exception.Message)"
        }

        if (-not $Once) {
            Start-Sleep -Seconds ([Math]::Max(1, $PollSeconds))
        }
    } while (-not $Once)
}
finally {
    Write-WatchdogLog "Watchdog stopped. PID=$PID"
}
