$mainScript = Join-Path $PSScriptRoot 'CodexQuotaBar.ps1'

$processes = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -and $_.CommandLine.IndexOf($mainScript, [StringComparison]::OrdinalIgnoreCase) -ge 0 }

foreach ($process in $processes) {
    Stop-Process -Id $process.ProcessId -Force
}
