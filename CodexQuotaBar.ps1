param(
    [switch]$CheckRpc,
    [switch]$ValidateOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

Add-Type @'
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

public static class CodexWindowNative {
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }

    private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")] private static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int maxCount);
    [DllImport("user32.dll")] private static extern int GetWindowTextLength(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    public static IntPtr FindCodexWindow() {
        IntPtr found = IntPtr.Zero;
        EnumWindows((hWnd, _) => {
            if (found != IntPtr.Zero || !IsWindowVisible(hWnd)) return true;
            var length = GetWindowTextLength(hWnd);
            if (length == 0) return true;

            var titleBuilder = new StringBuilder(length + 1);
            GetWindowText(hWnd, titleBuilder, titleBuilder.Capacity);
            var title = titleBuilder.ToString();
            uint processId;
            GetWindowThreadProcessId(hWnd, out processId);

            try {
                var process = Process.GetProcessById((int)processId);
                var name = process.ProcessName;
                var isCodexProcess = name.Equals("codex", StringComparison.OrdinalIgnoreCase)
                    || name.Equals("openai.codex", StringComparison.OrdinalIgnoreCase)
                    || name.StartsWith("openai.codex.", StringComparison.OrdinalIgnoreCase);
                var isCodexPackage = false;
                try {
                    var path = process.MainModule.FileName;
                    isCodexPackage = path.IndexOf("OpenAI.Codex_", StringComparison.OrdinalIgnoreCase) >= 0;
                } catch { }
                if (isCodexProcess || isCodexPackage || title.IndexOf("Codex", StringComparison.OrdinalIgnoreCase) >= 0) found = hWnd;
            } catch { }
            return true;
        }, IntPtr.Zero);
        return found;
    }
}
'@

function Get-ObjectProperty {
    param($Object, [string[]]$Names)
    if ($null -eq $Object) { return $null }
    foreach ($name in $Names) {
        $property = $Object.PSObject.Properties[$name]
        if ($null -ne $property) { return $property.Value }
    }
    return $null
}

function Send-RpcMessage {
    param($Writer, $Payload)
    $Writer.WriteLine(($Payload | ConvertTo-Json -Compress -Depth 8))
    $Writer.Flush()
}

function Read-RpcResult {
    param($Reader, [int]$Id, [int]$TimeoutMilliseconds = 3000)
    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMilliseconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        $remaining = [Math]::Max(1, [int]($deadline - [DateTime]::UtcNow).TotalMilliseconds)
        $readTask = $Reader.ReadLineAsync()
        if (-not $readTask.Wait($remaining)) { break }
        $line = $readTask.Result
        if ($null -eq $line) { break }
        try { $message = $line | ConvertFrom-Json -ErrorAction Stop } catch { continue }
        $messageId = Get-ObjectProperty $message @('id')
        if ($messageId -ne $Id) { continue }
        $rpcError = Get-ObjectProperty $message @('error')
        if ($null -ne $rpcError) {
            $messageText = Get-ObjectProperty $rpcError @('message')
            throw "Codex RPC error: $messageText"
        }
        $rpcResult = Get-ObjectProperty $message @('result')
        if ($null -eq $rpcResult) { throw 'Codex RPC response is missing result.' }
        return $rpcResult
    }
    throw "Timed out while waiting for Codex RPC method $Id."
}

function Convert-ResetTime {
    param($UnixSeconds)
    if ($null -eq $UnixSeconds) { return $null }
    try { return [DateTimeOffset]::FromUnixTimeSeconds([Int64]$UnixSeconds).ToLocalTime().DateTime } catch { return $null }
}

function Get-CodexRateLimits {
    $configuredPath = $env:CODEX_QUOTA_BAR_CODEX
    $commandArguments = '-s read-only -a untrusted app-server'
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    if ($configuredPath -and (Test-Path -LiteralPath $configuredPath)) {
        $codexPath = (Resolve-Path -LiteralPath $configuredPath).Path
        $psi.FileName = $codexPath
        $psi.Arguments = $commandArguments
    }
    else {
        $npmShim = Get-Command codex.cmd -ErrorAction SilentlyContinue
        if ($npmShim) {
            $psi.FileName = $env:ComSpec
            $psi.Arguments = "/d /s /c `"`"$($npmShim.Source)`" $commandArguments`""
        }
        else {
            $command = Get-Command codex.exe -ErrorAction Stop
            $codexPath = $command.Source
            if ($codexPath -match '\\WindowsApps\\OpenAI\.Codex_') {
                throw '商店版 Codex 内置 CLI 无法独立启动。请安装官方 Codex CLI，或设置 CODEX_QUOTA_BAR_CODEX 为可执行 codex.exe 的完整路径。'
            }
            $psi.FileName = $codexPath
            $psi.Arguments = $commandArguments
        }
    }
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $psi
    if (-not $process.Start()) { throw 'Unable to start codex app-server.' }

    try {
        $writer = $process.StandardInput
        $reader = $process.StandardOutput
        Send-RpcMessage $writer @{ id = 1; method = 'initialize'; params = @{ clientInfo = @{ name = 'codex-quota-bar'; version = '1.0.0' } } }
        [void](Read-RpcResult $reader 1 8000)
        Send-RpcMessage $writer @{ method = 'initialized'; params = @{} }
        Send-RpcMessage $writer @{ id = 2; method = 'account/rateLimits/read'; params = @{} }
        $result = Read-RpcResult $reader 2 3000

        $limits = Get-ObjectProperty $result @('rateLimits', 'rate_limits')
        $primary = Get-ObjectProperty $limits @('primary')
        $secondary = Get-ObjectProperty $limits @('secondary')
        if ($null -eq $primary -or $null -eq $secondary) { throw 'Codex did not return both 5-hour and weekly usage windows.' }

        $primaryUsed = [double](Get-ObjectProperty $primary @('usedPercent', 'used_percent'))
        $secondaryUsed = [double](Get-ObjectProperty $secondary @('usedPercent', 'used_percent'))
        [pscustomobject]@{
            FiveHourRemaining = [Math]::Max(0, [Math]::Min(100, [Math]::Round(100 - $primaryUsed)))
            WeeklyRemaining   = [Math]::Max(0, [Math]::Min(100, [Math]::Round(100 - $secondaryUsed)))
            FiveHourReset     = Convert-ResetTime (Get-ObjectProperty $primary @('resetsAt', 'resets_at'))
            WeeklyReset       = Convert-ResetTime (Get-ObjectProperty $secondary @('resetsAt', 'resets_at'))
            UpdatedAt         = Get-Date
        }
    }
    finally {
        if (-not $process.HasExited) { $process.Kill() }
        $process.Dispose()
    }
}

if ($CheckRpc) {
    Get-CodexRateLimits | ConvertTo-Json -Depth 3
    exit 0
}

$script:lastSnapshot = $null
$script:lastError = '等待同步'
$script:lastRefresh = [DateTime]::MinValue
$script:codexHandle = [IntPtr]::Zero
$script:isDetailsOpen = $false

$window = [System.Windows.Window]::new()
$window.WindowStyle = 'None'
$window.ResizeMode = 'NoResize'
$window.AllowsTransparency = $true
$window.Background = [System.Windows.Media.Brushes]::Transparent
$window.ShowInTaskbar = $false
$window.Topmost = $true
$window.ShowActivated = $false
$window.SizeToContent = 'WidthAndHeight'
$window.Visibility = 'Hidden'

$outer = [System.Windows.Controls.Border]::new()
$outer.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#E6121418')
$outer.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#55606A78')
$outer.BorderThickness = '1'
$outer.CornerRadius = '12'
$outer.Padding = '14,5,14,5'
$outer.Cursor = [System.Windows.Input.Cursors]::Hand
$outer.Width = 272
$shadow = [System.Windows.Media.Effects.DropShadowEffect]::new()
$shadow.Color = [System.Windows.Media.Colors]::Black
$shadow.BlurRadius = 20; $shadow.ShadowDepth = 4; $shadow.Opacity = 0.34
$outer.Effect = $shadow
$root = [System.Windows.Controls.StackPanel]::new()
$outer.Child = $root

$bar = [System.Windows.Controls.StackPanel]::new()
$bar.Orientation = 'Horizontal'

function New-TextBlock([string]$Text, [double]$Size, [string]$Color, [string]$Weight = 'Medium') {
    $block = [System.Windows.Controls.TextBlock]::new()
    $block.Text = $Text
    $block.FontFamily = 'Segoe UI'
    $block.FontSize = $Size
    $block.FontWeight = $Weight
    $block.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Color)
    $block.VerticalAlignment = 'Center'
    $block.SetValue([System.Windows.Media.TextOptions]::TextFormattingModeProperty, [System.Windows.Media.TextFormattingMode]::Display)
    $block.SetValue([System.Windows.Media.TextOptions]::TextRenderingModeProperty, [System.Windows.Media.TextRenderingMode]::Grayscale)
    return $block
}

function New-HairlineMeter {
    $track = [System.Windows.Controls.Border]::new()
    $track.Width = 44; $track.Height = 2; $track.CornerRadius = '2'
    $track.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#38404A')
    $fill = [System.Windows.Controls.Border]::new()
    $fill.Width = 0; $fill.Height = 2; $fill.CornerRadius = '2'
    $fill.HorizontalAlignment = 'Left'
    $fill.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#65D5A4')
    $track.Child = $fill
    return [pscustomobject]@{ Track = $track; Fill = $fill }
}

$brand = New-TextBlock 'Codex 配额' 11 '#E8E8EB' 'SemiBold'
$brand.Margin = '0,0,12,0'
$null = $bar.Children.Add($brand)
$divider1 = [System.Windows.Controls.Border]::new()
$divider1.Width = 1; $divider1.Height = 28; $divider1.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#32353C')
$divider1.Margin = '0,0,12,0'; $null = $bar.Children.Add($divider1)

$fiveStack = [System.Windows.Controls.StackPanel]::new(); $fiveStack.Margin = '0,0,12,0'
$fiveTitleRow = [System.Windows.Controls.StackPanel]::new(); $fiveTitleRow.Orientation = 'Horizontal'
$fiveStatusDot = [System.Windows.Shapes.Ellipse]::new(); $fiveStatusDot.Width = 7; $fiveStatusDot.Height = 7; $fiveStatusDot.Margin = '0,0,5,0'
$fiveStatusDot.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#737A85')
$null = $fiveTitleRow.Children.Add($fiveStatusDot); $null = $fiveTitleRow.Children.Add((New-TextBlock '5 小时' 10 '#C3C9D2'))
$fiveValue = New-TextBlock '—' 17 '#F4F4F5' 'SemiBold'
$fiveMeter = New-HairlineMeter
$fiveMeter.Track.Margin = '0,3,0,0'
$null = $fiveStack.Children.Add($fiveTitleRow); $null = $fiveStack.Children.Add($fiveValue); $null = $fiveStack.Children.Add($fiveMeter.Track); $null = $bar.Children.Add($fiveStack)

$divider2 = [System.Windows.Controls.Border]::new()
$divider2.Width = 1; $divider2.Height = 28; $divider2.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#32353C')
$divider2.Margin = '0,0,12,0'; $null = $bar.Children.Add($divider2)

$weeklyStack = [System.Windows.Controls.StackPanel]::new()
$weeklyTitleRow = [System.Windows.Controls.StackPanel]::new(); $weeklyTitleRow.Orientation = 'Horizontal'
$statusDot = [System.Windows.Shapes.Ellipse]::new(); $statusDot.Width = 7; $statusDot.Height = 7; $statusDot.Margin = '0,0,5,0'
$statusDot.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#737A85')
$null = $weeklyTitleRow.Children.Add($statusDot); $null = $weeklyTitleRow.Children.Add((New-TextBlock '每周' 10 '#C3C9D2'))
$weeklyValue = New-TextBlock '—' 17 '#F4F4F5' 'SemiBold'
$weeklyMeter = New-HairlineMeter
$weeklyMeter.Track.Margin = '0,3,0,0'
$null = $weeklyStack.Children.Add($weeklyTitleRow); $null = $weeklyStack.Children.Add($weeklyValue); $null = $weeklyStack.Children.Add($weeklyMeter.Track); $null = $bar.Children.Add($weeklyStack)

$details = [System.Windows.Controls.Border]::new()
$details.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#44505C68')
$details.BorderThickness = '0,0,0,1'
$details.Margin = '0,0,0,9'
$details.Padding = '0,0,0,10'
$details.Visibility = 'Collapsed'
$detailsStack = [System.Windows.Controls.StackPanel]::new(); $details.Child = $detailsStack
$detailsHeader = [System.Windows.Controls.DockPanel]::new(); $detailsHeader.Margin = '0,0,0,10'
$detailsTitle = New-TextBlock 'Codex 配额' 13 '#F3F4F6' 'SemiBold'
$syncBadge = New-TextBlock '等待同步' 10 '#A7ADB7'
[System.Windows.Controls.DockPanel]::SetDock($syncBadge, 'Right')
$null = $detailsHeader.Children.Add($syncBadge); $null = $detailsHeader.Children.Add($detailsTitle)
$fiveDetailText = New-TextBlock '5 小时   等待同步' 11 '#D8DCE2'
$fiveDetailText.Margin = '0,0,0,6'
$weeklyDetailText = New-TextBlock '每周     等待同步' 11 '#D8DCE2'
$weeklyDetailText.Margin = '0,0,0,10'
$syncText = New-TextBlock '上次同步：等待同步' 10 '#89909B'
$syncText.Margin = '0,0,0,8'
$null = $detailsStack.Children.Add($detailsHeader); $null = $detailsStack.Children.Add($fiveDetailText); $null = $detailsStack.Children.Add($weeklyDetailText); $null = $detailsStack.Children.Add($syncText)
$refreshButton = [System.Windows.Controls.Button]::new()
$refreshButton.Content = '立即同步'
$refreshButton.FontFamily = 'Segoe UI'; $refreshButton.FontSize = 11
$refreshButton.Foreground = [System.Windows.Media.Brushes]::White
$refreshButton.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#2F6EA8')
$refreshButton.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#4E8BC2')
$refreshButton.BorderThickness = '1'; $refreshButton.Padding = '10,5,10,5'
$refreshButton.HorizontalAlignment = 'Left'
$null = $detailsStack.Children.Add($refreshButton)
$null = $root.Children.Add($details); $null = $root.Children.Add($bar)
$window.Content = $outer

function Format-Reset($Date) {
    if ($null -eq $Date) { return '未知' }
    return $Date.ToString('M月d日 HH:mm')
}

function Update-Overlay {
    try {
        $snapshot = Get-CodexRateLimits
        $script:lastSnapshot = $snapshot
        $script:lastError = $null
        $script:lastRefresh = Get-Date
    }
    catch {
        $script:lastError = $_.Exception.Message
        $script:lastRefresh = Get-Date
    }

    if ($null -eq $script:lastSnapshot) {
        $fiveValue.Text = '—'; $weeklyValue.Text = '—'
        $fiveMeter.Fill.Width = 0; $weeklyMeter.Fill.Width = 0
        $fiveStatusDot.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#737A85')
        $statusDot.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#737A85')
        $fiveDetailText.Text = '5 小时   等待同步'
        $weeklyDetailText.Text = '每周     等待同步'
        $syncBadge.Text = '等待同步'
        $syncText.Text = "上次同步：$script:lastError"
        return
    }

    $five = $script:lastSnapshot.FiveHourRemaining
    $weekly = $script:lastSnapshot.WeeklyRemaining
    $minimum = [Math]::Min($five, $weekly)
    $color = if ($minimum -lt 10) { '#F36D6D' } elseif ($minimum -lt 20) { '#F2BA55' } else { '#65D5A4' }
    $fiveColor = if ($five -lt 10) { '#F36D6D' } elseif ($five -lt 20) { '#F2BA55' } else { '#65D5A4' }
    $weeklyColor = if ($weekly -lt 10) { '#F36D6D' } elseif ($weekly -lt 20) { '#F2BA55' } else { '#65D5A4' }
    $fiveValue.Text = "$five%"; $weeklyValue.Text = "$weekly%"
    $fiveValue.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($fiveColor)
    $weeklyValue.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($weeklyColor)
    $fiveMeter.Fill.Width = [Math]::Round(44 * $five / 100)
    $weeklyMeter.Fill.Width = [Math]::Round(44 * $weekly / 100)
    $fiveMeter.Fill.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString($fiveColor)
    $weeklyMeter.Fill.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString($weeklyColor)
    $fiveStatusDot.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString($fiveColor)
    $statusDot.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString($weeklyColor)
    $fiveDetailText.Text = "5 小时   $five%   ·   $(Format-Reset $script:lastSnapshot.FiveHourReset) 重置"
    $weeklyDetailText.Text = "每周     $weekly%   ·   $(Format-Reset $script:lastSnapshot.WeeklyReset) 重置"
    $syncBadge.Text = if ($script:lastError) { '数据待同步' } else { '已同步' }
    $syncText.Text = if ($script:lastError) { "上次同步：数据可能已过期 — $script:lastError" } else { "上次同步：$($script:lastSnapshot.UpdatedAt.ToString('HH:mm:ss'))" }
}

function Position-Overlay {
    if ($script:codexHandle -eq [IntPtr]::Zero) { return }
    $window.UpdateLayout()
    $workArea = [System.Windows.SystemParameters]::WorkArea
    $window.Left = $workArea.Left + ($workArea.Width * 0.14) + ($window.ActualWidth / 8)
    $window.Top = $workArea.Bottom - $window.ActualHeight - 8
}

function Toggle-Details {
    $script:isDetailsOpen = -not $script:isDetailsOpen
    if ($script:isDetailsOpen) {
        $details.Opacity = 0
        $details.Visibility = 'Visible'
        $fadeIn = [System.Windows.Media.Animation.DoubleAnimation]::new(0, 1, [TimeSpan]::FromMilliseconds(160))
        $details.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $fadeIn)
    }
    else {
        $details.Visibility = 'Collapsed'
    }
    Position-Overlay
}

$outer.Add_MouseLeftButtonUp({ Toggle-Details })
$refreshButton.Add_Click({ Update-Overlay; Position-Overlay })
$window.Add_Deactivated({
    if ($script:isDetailsOpen) {
        $script:isDetailsOpen = $false
        $details.Visibility = 'Collapsed'
        Position-Overlay
    }
})

if ($ValidateOnly) {
    'WPF overlay validation: OK'
    exit 0
}

$timer = [System.Windows.Threading.DispatcherTimer]::new()
$timer.Interval = [TimeSpan]::FromSeconds(2)
$timer.Add_Tick({
    $handle = [CodexWindowNative]::FindCodexWindow()
    if ($handle -eq [IntPtr]::Zero) {
        $script:codexHandle = [IntPtr]::Zero
        if ($window.Visibility -eq 'Visible') { $window.Hide() }
        return
    }

    $script:codexHandle = $handle
    if ([CodexWindowNative]::IsIconic($handle)) {
        if ($window.Visibility -eq 'Visible') { $window.Hide() }
        return
    }

    if ($window.Visibility -ne 'Visible') { $window.Show() }
    Position-Overlay
    if (((Get-Date) - $script:lastRefresh).TotalSeconds -ge 60) { Update-Overlay; Position-Overlay }
})

$window.Add_Closed({ $timer.Stop() })
$timer.Start()
[System.Windows.Threading.Dispatcher]::Run()
