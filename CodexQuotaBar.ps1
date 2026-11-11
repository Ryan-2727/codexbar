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

public static class CodexWindowNative {
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }

    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    public static bool IsForegroundWindow(IntPtr hWnd) {
        return hWnd != IntPtr.Zero && GetForegroundWindow() == hWnd;
    }

    public static bool IsCodexWindow(IntPtr hWnd) {
        if (hWnd == IntPtr.Zero || !IsWindowVisible(hWnd)) return false;

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
            return isCodexProcess || isCodexPackage;
        } catch { return false; }
    }

    public static IntPtr FindForegroundCodexWindow() {
        var hWnd = GetForegroundWindow();
        return IsCodexWindow(hWnd) ? hWnd : IntPtr.Zero;
    }

    public static bool CanKeepOverlayVisible(IntPtr overlayHandle, IntPtr codexHandle) {
        return IsForegroundWindow(overlayHandle)
            && IsCodexWindow(codexHandle)
            && !IsIconic(codexHandle);
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
        $result = Read-RpcResult $reader 2 15000

        $limits = Get-ObjectProperty $result @('rateLimits', 'rate_limits')
        $primaryWindow = Get-ObjectProperty $limits @('primary')
        $secondaryWindow = Get-ObjectProperty $limits @('secondary')
        $primaryDuration = Get-ObjectProperty $primaryWindow @('windowDurationMins', 'window_duration_mins')
        $secondaryDuration = Get-ObjectProperty $secondaryWindow @('windowDurationMins', 'window_duration_mins')

        $fiveHourWindow = if ($primaryDuration -eq 300) { $primaryWindow } elseif ($secondaryDuration -eq 300) { $secondaryWindow } else { $null }
        $weeklyWindow = if ($primaryDuration -eq 10080) { $primaryWindow } elseif ($secondaryDuration -eq 10080) { $secondaryWindow } else { $null }
        if ($null -eq $fiveHourWindow -and $null -eq $primaryDuration) { $fiveHourWindow = $primaryWindow }
        if ($null -eq $weeklyWindow -and $null -eq $secondaryDuration) { $weeklyWindow = $secondaryWindow }
        if ($null -eq $fiveHourWindow -and $null -eq $weeklyWindow) { throw 'Codex did not return a supported usage window.' }

        $fiveHourRemaining = $null
        $fiveHourReset = $null
        if ($null -ne $fiveHourWindow) {
            $fiveHourUsed = Get-ObjectProperty $fiveHourWindow @('usedPercent', 'used_percent')
            if ($null -ne $fiveHourUsed) { $fiveHourRemaining = [Math]::Max(0, [Math]::Min(100, [Math]::Round(100 - [double]$fiveHourUsed))) }
            $fiveHourReset = Convert-ResetTime (Get-ObjectProperty $fiveHourWindow @('resetsAt', 'resets_at'))
        }

        $weeklyRemaining = $null
        $weeklyReset = $null
        if ($null -ne $weeklyWindow) {
            $weeklyUsed = Get-ObjectProperty $weeklyWindow @('usedPercent', 'used_percent')
            if ($null -ne $weeklyUsed) { $weeklyRemaining = [Math]::Max(0, [Math]::Min(100, [Math]::Round(100 - [double]$weeklyUsed))) }
            $weeklyReset = Convert-ResetTime (Get-ObjectProperty $weeklyWindow @('resetsAt', 'resets_at'))
        }

        [pscustomobject]@{
            FiveHourRemaining = $fiveHourRemaining
            FiveHourReset     = $fiveHourReset
            WeeklyRemaining   = $weeklyRemaining
            WeeklyReset       = $weeklyReset
            UpdatedAt       = Get-Date
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
$script:quotaBarHandle = [IntPtr]::Zero
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
$window.Add_SourceInitialized({
    $script:quotaBarHandle = ([System.Windows.Interop.WindowInteropHelper]::new($window)).Handle
})

$outer = [System.Windows.Controls.Border]::new()
$outer.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#DD171B22')
$outer.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#4A677589')
$outer.BorderThickness = '1'
$outer.CornerRadius = '12'
$outer.Padding = '10,6,10,6'
$outer.Cursor = [System.Windows.Input.Cursors]::Hand
$outer.Width = 160
$shadow = [System.Windows.Media.Effects.DropShadowEffect]::new()
$shadow.Color = [System.Windows.Media.Colors]::Black
$shadow.BlurRadius = 24; $shadow.ShadowDepth = 5; $shadow.Opacity = 0.28
$outer.Effect = $shadow
$outer.Add_MouseEnter({
    $outer.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#6688A0B5')
    $outer.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#E21B2028')
})
$outer.Add_MouseLeave({
    $outer.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#4A677589')
    $outer.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#DD171B22')
})
$root = [System.Windows.Controls.StackPanel]::new()
$outer.Child = $root

$bar = [System.Windows.Controls.StackPanel]::new()
$bar.Orientation = 'Horizontal'
$bar.HorizontalAlignment = 'Center'

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

$fiveStack = [System.Windows.Controls.StackPanel]::new(); $fiveStack.Width = 44; $fiveStack.Margin = '0,0,10,0'
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
$divider2.Margin = '0,0,10,0'; $null = $bar.Children.Add($divider2)

$weeklyStack = [System.Windows.Controls.StackPanel]::new(); $weeklyStack.Width = 44
$weeklyTitleRow = [System.Windows.Controls.StackPanel]::new(); $weeklyTitleRow.Orientation = 'Horizontal'
$weeklyStatusDot = [System.Windows.Shapes.Ellipse]::new(); $weeklyStatusDot.Width = 7; $weeklyStatusDot.Height = 7; $weeklyStatusDot.Margin = '0,0,5,0'
$weeklyStatusDot.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#737A85')
$null = $weeklyTitleRow.Children.Add($weeklyStatusDot); $null = $weeklyTitleRow.Children.Add((New-TextBlock '每周' 10 '#C3C9D2'))
$weeklyValue = New-TextBlock '—' 17 '#F4F4F5' 'SemiBold'
$weeklyMeter = New-HairlineMeter
$weeklyMeter.Track.Margin = '0,3,0,0'
$null = $weeklyStack.Children.Add($weeklyTitleRow); $null = $weeklyStack.Children.Add($weeklyValue); $null = $weeklyStack.Children.Add($weeklyMeter.Track); $null = $bar.Children.Add($weeklyStack)

$details = [System.Windows.Controls.Border]::new()
$details.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#B51E252E')
$details.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#44505C68')
$details.BorderThickness = '0,0,0,1'
$details.CornerRadius = '9'
$details.Margin = '0,0,0,10'
$details.Padding = '10,10,10,10'
$details.Visibility = 'Collapsed'
$detailsTranslate = [System.Windows.Media.TranslateTransform]::new(0, 0)
$details.RenderTransform = $detailsTranslate
$detailsStack = [System.Windows.Controls.StackPanel]::new(); $details.Child = $detailsStack
$fiveDetailLabel = New-TextBlock '5 小时' 11 '#C3C9D2' 'SemiBold'
$fiveDetailValue = New-TextBlock '—' 18 '#F3F4F6' 'SemiBold'
$fiveDetailValue.Margin = '0,1,0,5'
$fiveResetLabel = New-TextBlock '下次重置' 9 '#89909B'
$fiveResetValue = New-TextBlock '等待同步' 16 '#F3F4F6' 'SemiBold'
$fiveResetValue.TextWrapping = 'Wrap'
$fiveResetValue.Margin = '0,1,0,10'
$detailDivider = [System.Windows.Controls.Border]::new()
$detailDivider.Height = 1; $detailDivider.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#34414C57')
$detailDivider.Margin = '0,0,0,10'
$weeklyDetailLabel = New-TextBlock '每周' 11 '#C3C9D2' 'SemiBold'
$weeklyDetailValue = New-TextBlock '—' 18 '#F3F4F6' 'SemiBold'
$weeklyDetailValue.Margin = '0,1,0,5'
$weeklyResetLabel = New-TextBlock '下次重置' 9 '#89909B'
$weeklyResetValue = New-TextBlock '等待同步' 16 '#F3F4F6' 'SemiBold'
$weeklyResetValue.TextWrapping = 'Wrap'
$weeklyResetValue.Margin = '0,1,0,10'
$syncFooter = [System.Windows.Controls.DockPanel]::new()
$syncFooter.Margin = '0,2,0,0'
$refreshButton = [System.Windows.Controls.Button]::new()
$refreshButton.ToolTip = '立即同步'
$refreshButton.Foreground = [System.Windows.Media.Brushes]::White
$refreshButton.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#263B4D5E')
$refreshButton.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#4A657A8E')
$refreshButton.BorderThickness = '1'; $refreshButton.Padding = '0'
$refreshButton.Width = 24; $refreshButton.Height = 24
$refreshButton.Cursor = [System.Windows.Input.Cursors]::Hand
$refreshIcon = New-TextBlock '↻' 15 '#FFFFFF' 'SemiBold'
$refreshIcon.FontFamily = 'Segoe UI Symbol'
$refreshIcon.HorizontalAlignment = 'Center'; $refreshIcon.VerticalAlignment = 'Center'
$refreshIcon.RenderTransformOrigin = [System.Windows.Point]::new(0.5, 0.5)
$refreshRotate = [System.Windows.Media.RotateTransform]::new(0)
$refreshIcon.RenderTransform = $refreshRotate
$refreshButton.Content = $refreshIcon
[System.Windows.Controls.DockPanel]::SetDock($refreshButton, 'Right')
$syncText = New-TextBlock '等待同步' 9 '#89909B'
$syncText.Margin = '0,0,6,0'
$null = $syncFooter.Children.Add($refreshButton); $null = $syncFooter.Children.Add($syncText)
$null = $detailsStack.Children.Add($fiveDetailLabel); $null = $detailsStack.Children.Add($fiveDetailValue); $null = $detailsStack.Children.Add($fiveResetLabel); $null = $detailsStack.Children.Add($fiveResetValue); $null = $detailsStack.Children.Add($detailDivider); $null = $detailsStack.Children.Add($weeklyDetailLabel); $null = $detailsStack.Children.Add($weeklyDetailValue); $null = $detailsStack.Children.Add($weeklyResetLabel); $null = $detailsStack.Children.Add($weeklyResetValue); $null = $detailsStack.Children.Add($syncFooter)
$null = $root.Children.Add($details); $null = $root.Children.Add($bar)
$window.Content = $outer

function Format-Reset($Date) {
    if ($null -eq $Date) { return '未知' }
    return $Date.ToString('M月d日 HH:mm')
}

function Set-QuotaView($Remaining, $Reset, $ValueBlock, $Meter, $Dot, $DetailValueBlock, $ResetBlock) {
    if ($null -eq $Remaining) {
        $ValueBlock.Text = '—'
        $ValueBlock.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#F4F4F5')
        $Meter.Fill.Width = 0
        $Dot.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#737A85')
        $DetailValueBlock.Text = '不可用'
        $DetailValueBlock.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#A7ADB7')
        $ResetBlock.Text = '未返回该限额窗口'
        return
    }

    $color = if ($Remaining -lt 20) { '#F36D6D' } elseif ($Remaining -lt 40) { '#F2BA55' } else { '#65D5A4' }
    $ValueBlock.Text = "$Remaining%"
    $ValueBlock.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($color)
    $Meter.Fill.Width = [Math]::Round(44 * $Remaining / 100)
    $Meter.Fill.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString($color)
    $Dot.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString($color)
    $DetailValueBlock.Text = "$Remaining%"
    $DetailValueBlock.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($color)
    $ResetBlock.Text = Format-Reset $Reset
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
        $weeklyStatusDot.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#737A85')
        $fiveDetailValue.Text = '—'; $weeklyDetailValue.Text = '—'
        $fiveResetValue.Text = '等待同步'; $weeklyResetValue.Text = '等待同步'
        $syncText.Text = if ($script:lastError) { '同步失败' } else { '等待同步' }
        return
    }

    Set-QuotaView $script:lastSnapshot.FiveHourRemaining $script:lastSnapshot.FiveHourReset $fiveValue $fiveMeter $fiveStatusDot $fiveDetailValue $fiveResetValue
    Set-QuotaView $script:lastSnapshot.WeeklyRemaining $script:lastSnapshot.WeeklyReset $weeklyValue $weeklyMeter $weeklyStatusDot $weeklyDetailValue $weeklyResetValue
    $syncText.Text = if ($script:lastError) { '数据可能已过期' } else { "上次同步 $($script:lastSnapshot.UpdatedAt.ToString('HH:mm:ss'))" }
}

function Position-Overlay {
    if ($script:codexHandle -eq [IntPtr]::Zero) { return }
    $window.UpdateLayout()
    $workArea = [System.Windows.SystemParameters]::WorkArea
    $window.Left = $workArea.Left + ($workArea.Width * 0.14) + 71
    $window.Top = $workArea.Bottom - $window.ActualHeight - 8
}

function Toggle-Details {
    $script:isDetailsOpen = -not $script:isDetailsOpen
    if ($script:isDetailsOpen) {
        $details.Opacity = 1
        $detailsTranslate.Y = 0
        $details.Visibility = 'Visible'
        Position-Overlay

        $openEase = [System.Windows.Media.Animation.CubicEase]::new()
        $openEase.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut
        $fadeIn = [System.Windows.Media.Animation.DoubleAnimation]::new(0, 1, [TimeSpan]::FromMilliseconds(180))
        $fadeIn.EasingFunction = $openEase
        $fadeIn.FillBehavior = [System.Windows.Media.Animation.FillBehavior]::Stop
        $slideIn = [System.Windows.Media.Animation.DoubleAnimation]::new(6, 0, [TimeSpan]::FromMilliseconds(180))
        $slideIn.EasingFunction = $openEase
        $slideIn.FillBehavior = [System.Windows.Media.Animation.FillBehavior]::Stop
        $details.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $fadeIn)
        $detailsTranslate.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $slideIn)
    }
    else {
        $closeEase = [System.Windows.Media.Animation.CubicEase]::new()
        $closeEase.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseIn
        $fadeOut = [System.Windows.Media.Animation.DoubleAnimation]::new(1, 0, [TimeSpan]::FromMilliseconds(120))
        $fadeOut.EasingFunction = $closeEase
        $slideOut = [System.Windows.Media.Animation.DoubleAnimation]::new(0, 6, [TimeSpan]::FromMilliseconds(120))
        $slideOut.EasingFunction = $closeEase
        $fadeOut.Add_Completed({
            if (-not $script:isDetailsOpen) {
                $details.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $null)
                $detailsTranslate.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $null)
                $details.Opacity = 1
                $detailsTranslate.Y = 0
                $details.Visibility = 'Collapsed'
                Position-Overlay
            }
        })
        $details.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $fadeOut)
        $detailsTranslate.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $slideOut)
    }
}

$script:isRefreshing = $false
$outer.Add_MouseLeftButtonUp({ if (-not $refreshButton.IsMouseOver) { Toggle-Details } })
$refreshButton.Add_Click({
    if ($script:isRefreshing) { return }
    $script:isRefreshing = $true
    $refreshButton.IsEnabled = $false

    $spinEase = [System.Windows.Media.Animation.QuadraticEase]::new()
    $spinEase.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseInOut
    $spin = [System.Windows.Media.Animation.DoubleAnimation]::new(0, 360, [TimeSpan]::FromMilliseconds(400))
    $spin.EasingFunction = $spinEase
    $spin.FillBehavior = [System.Windows.Media.Animation.FillBehavior]::Stop
    $spin.Add_Completed({
        try {
            Update-Overlay
            Position-Overlay
        }
        finally {
            $refreshRotate.BeginAnimation([System.Windows.Media.RotateTransform]::AngleProperty, $null)
            $refreshRotate.Angle = 0
            $refreshButton.IsEnabled = $true
            $script:isRefreshing = $false
        }
    })
    $refreshRotate.BeginAnimation([System.Windows.Media.RotateTransform]::AngleProperty, $spin)
})
$window.Add_Deactivated({
    if ($script:isDetailsOpen) {
        $script:isDetailsOpen = $false
        $details.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $null)
        $detailsTranslate.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $null)
        $details.Opacity = 1
        $detailsTranslate.Y = 0
        $details.Visibility = 'Collapsed'
        Position-Overlay
    }
})

if ($ValidateOnly) {
    'WPF overlay validation: OK'
    exit 0
}

$timer = [System.Windows.Threading.DispatcherTimer]::new()
$timer.Interval = [TimeSpan]::FromMilliseconds(250)
$timer.Add_Tick({
    try {
        $handle = [CodexWindowNative]::FindForegroundCodexWindow()
        if ($handle -eq [IntPtr]::Zero) {
            if ([CodexWindowNative]::CanKeepOverlayVisible($script:quotaBarHandle, $script:codexHandle)) { return }

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
    }
    catch {
        $script:lastError = "Window detection: $($_.Exception.Message)"
    }
})

$window.Add_Closed({ $timer.Stop() })
$timer.Start()
[System.Windows.Threading.Dispatcher]::Run()
