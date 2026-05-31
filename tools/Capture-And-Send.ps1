param(
    [Parameter(Mandatory=$true)]
    [string]$Version,

    [string]$WinRate         = "",
    [string]$ReturnPct       = "",
    [string]$ReturnAmt       = "",
    [string]$MaxDD           = "",
    [string]$MaxDDAmt        = "",
    [string]$TotalTrades     = "",
    [string]$MaxConsecWins      = "",
    [string]$MaxConsecWinsAmt   = "",
    [string]$MaxConsecLosses    = "",
    [string]$MaxConsecLossesAmt = ""
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinAPI {
    // DPI awareness: must call before any coordinate API so we get physical pixels.
    // Physical screen = 2880x1800; logical (DPI-unaware) = 1440x900.
    // Without this, GetWindowRect returns logical coords and PrintWindow captures wrong region.
    [DllImport("shcore.dll")] public static extern int SetProcessDpiAwareness(int value);

    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, int dwExtraInfo);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdcBlt, uint nFlags);
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }
}
"@

# Make this process DPI-aware so all coordinates are physical pixels (2x).
# PROCESS_PER_MONITOR_DPI_AWARE = 2
[WinAPI]::SetProcessDpiAwareness(2) | Out-Null

# Find MT4 terminal process
$mt4 = Get-Process -Name "terminal" -ErrorAction SilentlyContinue |
       Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero -and $_.MainWindowTitle -ne "" } |
       Select-Object -First 1

$bitmap = $null

if ($mt4) {
    $rect = New-Object WinAPI+RECT
    [WinAPI]::GetWindowRect($mt4.MainWindowHandle, [ref]$rect) | Out-Null

    $ww = $rect.Right  - $rect.Left   # physical pixels (e.g. 2906)
    $wh = $rect.Bottom - $rect.Top    # physical pixels (e.g. 1730)

    # Bring MT4 to front and click the Graph tab
    [WinAPI]::SetForegroundWindow($mt4.MainWindowHandle) | Out-Null
    Start-Sleep -Milliseconds 600

    # Graph tab at physical screen coordinates:
    #   X = 29.5% from window left (Graph tab center at ~29.5% in both logical and physical)
    #   Y = 86px above window bottom in physical (= 43px logical x2)
    $tabRowY   = $rect.Bottom - 86
    $graphTabX = $rect.Left + [int]($ww * 0.295)

    [WinAPI]::SetCursorPos($graphTabX, $tabRowY) | Out-Null
    Start-Sleep -Milliseconds 150
    [WinAPI]::mouse_event(0x0002, 0, 0, 0, 0) | Out-Null   # MOUSEEVENTF_LEFTDOWN
    Start-Sleep -Milliseconds 80
    [WinAPI]::mouse_event(0x0004, 0, 0, 0, 0) | Out-Null   # MOUSEEVENTF_LEFTUP
    Start-Sleep -Milliseconds 2000   # Wait for equity curve to render

    # Capture MT4 window content via PrintWindow at full physical resolution.
    # PrintWindow bypasses any overlapping windows on screen.
    # Physical window: ww=2906, wh=1730. Strategy Tester starts at 49.6% (window_y=858).
    $fullBmp = New-Object System.Drawing.Bitmap($ww, $wh)
    $g       = [System.Drawing.Graphics]::FromImage($fullBmp)
    $hdc     = $g.GetHdc()
    [WinAPI]::PrintWindow($mt4.MainWindowHandle, $hdc, 2) | Out-Null  # PW_RENDERFULLCONTENT=2
    $g.ReleaseHdc($hdc)
    $g.Dispose()

    # Crop to Strategy Tester Graph panel (physical window pixel coordinates):
    #   Top  = 49.6% of physical window height  (= Strategy Tester top)
    #   End  = 94.5% of physical window height  (= just before the tab row)
    #   Left = 32px physical (skip invisible border + small margin)
    #   Right = ww - 36px physical
    $cropX = 32
    $cropY = [int]($wh * 0.496)
    $cropW = $ww - 36
    $cropH = [int]($wh * 0.945) - [int]($wh * 0.496)

    $bitmap = New-Object System.Drawing.Bitmap($cropW, $cropH)
    $gc     = [System.Drawing.Graphics]::FromImage($bitmap)
    $src    = New-Object System.Drawing.Rectangle($cropX, $cropY, $cropW, $cropH)
    $dst    = New-Object System.Drawing.Rectangle(0, 0, $cropW, $cropH)
    $gc.DrawImage($fullBmp, $dst, $src, [System.Drawing.GraphicsUnit]::Pixel)
    $gc.Dispose()
    $fullBmp.Dispose()
} else {
    # Fallback: capture lower 50% of primary screen
    $sw = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width
    $sh = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Height
    $bitmap   = New-Object System.Drawing.Bitmap($sw, [int]($sh * 0.50))
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.CopyFromScreen(0, [int]($sh * 0.47), 0, 0, (New-Object System.Drawing.Size($sw, [int]($sh * 0.50))))
    $graphics.Dispose()
}

$timestamp      = Get-Date -Format "yyyyMMdd-HHmmss"
$screenshotPath = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "ea-backtest-${Version}-${timestamp}.png")
$bitmap.Save($screenshotPath, [System.Drawing.Imaging.ImageFormat]::Png)
$bitmap.Dispose()

Write-Host "Screenshot saved: $screenshotPath"

$sendScript = Join-Path $ScriptDir "Send-BacktestReport.ps1"

& $sendScript `
    -Version         $Version `
    -ScreenshotPath  $screenshotPath `
    -WinRate         $WinRate `
    -ReturnPct       $ReturnPct `
    -ReturnAmt       $ReturnAmt `
    -MaxDD           $MaxDD `
    -MaxDDAmt        $MaxDDAmt `
    -TotalTrades     $TotalTrades `
    -MaxConsecWins      $MaxConsecWins `
    -MaxConsecWinsAmt   $MaxConsecWinsAmt `
    -MaxConsecLosses    $MaxConsecLosses `
    -MaxConsecLossesAmt $MaxConsecLossesAmt

Remove-Item $screenshotPath -Force -ErrorAction SilentlyContinue
