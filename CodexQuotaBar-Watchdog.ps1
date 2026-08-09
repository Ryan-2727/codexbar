param(
    [int]$PollSeconds = 2,
    [switch]$Once
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$mainScript = Join-Path $PSScriptRoot 'CodexQuotaBar.ps1'

function Get-CodexProcess {
    Get-CimInstance Win32_Process -Filter "Name='ChatGPT.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.ExecutablePath -and $_.ExecutablePath.IndexOf('OpenAI.Codex_', [StringComparison]::OrdinalIgnoreCase) -ge 0 }
}

function Get-QuotaBarProcess {
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -and $_.CommandLine.IndexOf($mainScript, [StringComparison]::OrdinalIgnoreCase) -ge 0 }
}

do {
    try {
        $codexRunning = $null -ne (Get-CodexProcess | Select-Object -First 1)
        $barProcesses = @(Get-QuotaBarProcess)

        if ($codexRunning -and $barProcesses.Count -eq 0) {
            Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList @(
                '-NoProfile',
                '-ExecutionPolicy', 'Bypass',
                '-File', "`"$mainScript`""
            )
        }
        elseif (-not $codexRunning -and $barProcesses.Count -gt 0) {
            $barProcesses | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
        }
    }
    catch {
        # Keep supervising after transient WMI or process-enumeration failures.
    }

    if (-not $Once) {
        Start-Sleep -Seconds ([Math]::Max(1, $PollSeconds))
    }
} while (-not $Once)
