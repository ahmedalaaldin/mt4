# ============================================================
# Run-BacktestLoop.ps1
# Automates MT4 Strategy Tester for a list of EA versions:
#   1. Selects each EA in the Strategy Tester
#   2. Clicks Start
#   3. Waits for completion (progress bar = full)
#   4. Reads metrics from the Report tab
#   5. Saves the HTML report
#   6. Calls Capture-And-Send.ps1 (captures graph + emails results)
#   7. Moves to the next version
# ============================================================

param(
    [string[]]$Versions = @("432","433","434","435","436","437","438","439","440"),
    [string]$Symbol     = "XAUUSD",
    [string]$Period     = "M5",
    [string]$FromDate   = "2025.05.24",
    [string]$ToDate     = "2026.05.24"
)

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$SendScript = Join-Path $ScriptDir "Capture-And-Send.ps1"
$ReportDir  = [System.IO.Path]::Combine($env:TEMP, "ea_reports")
New-Item -ItemType Directory -Force -Path $ReportDir | Out-Null

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class Win32 {
    [DllImport("user32.dll")] public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);
    [DllImport("user32.dll")] public static extern IntPtr FindWindowEx(IntPtr hParent, IntPtr hChild, string lpClassName, string lpWindowName);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern int SendMessage(IntPtr hWnd, uint Msg, int wParam, int lParam);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, StringBuilder sb, int nMaxCount);
    [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr hParent, EnumChildProc callback, IntPtr lParam);
    public delegate bool EnumChildProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] public static extern int GetClassName(IntPtr hWnd, StringBuilder sb, int nMaxCount);
    [DllImport("shcore.dll")] public static extern int SetProcessDpiAwareness(int value);
}
"@
[Win32]::SetProcessDpiAwareness(2) | Out-Null

function Get-MT4Window {
    Get-Process -Name "terminal" -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero -and $_.MainWindowTitle -ne "" } |
        Select-Object -First 1
}

function Wait-ForBacktestComplete {
    param([int]$TimeoutMinutes = 90)
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    Write-Host "  Waiting for backtest to complete..." -ForegroundColor Cyan
    Start-Sleep -Seconds 10  # Give it time to start

    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 15
        # Check if 'Start' button is back (means test finished)
        # We detect this by checking if the MT4 CPU usage is low
        $mt4 = Get-MT4Window
        if (-not $mt4) { Write-Warning "MT4 not found!"; return $false }

        # Use UI Automation to find the Start button in the Strategy Tester
        try {
            $rootEl  = [System.Windows.Automation.AutomationElement]::FromHandle($mt4.MainWindowHandle)
            $btnCond = New-Object System.Windows.Automation.PropertyCondition(
                [System.Windows.Automation.AutomationElement]::NameProperty, "Start")
            $startBtn = $rootEl.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $btnCond)
            if ($startBtn -ne $null) {
                Write-Host "  Backtest complete (Start button found)." -ForegroundColor Green
                return $true
            }
        } catch {}

        Write-Host "  Still running... $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor DarkGray
    }
    Write-Warning "Timed out waiting for backtest."
    return $false
}

function Read-BacktestReport {
    param([string]$Version)
    # MT4 saves a report when you right-click → Save as Report in the Report tab.
    # We trigger this via keyboard: click Report tab, Ctrl+S equivalent via context menu.
    # Simpler: read the strategytester HTML template that MT4 populates in memory.
    # Best reliable method: save via MT4 File menu after clicking Report tab.

    $mt4 = Get-MT4Window
    if (-not $mt4) { return $null }

    [Win32]::SetForegroundWindow($mt4.MainWindowHandle) | Out-Null
    Start-Sleep -Milliseconds 800

    # Click the Report tab (5th tab in strategy tester panel at bottom)
    # Use UI Automation to find it
    try {
        $rootEl = [System.Windows.Automation.AutomationElement]::FromHandle($mt4.MainWindowHandle)
        $tabCond = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::NameProperty, "Report")
        $reportTab = $rootEl.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $tabCond)
        if ($reportTab) {
            $inv = $reportTab.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
            $inv.Invoke()
            Start-Sleep -Milliseconds 1000
        }
    } catch {}

    # Save report via right-click context menu → Save as Report
    $reportFile = Join-Path $ReportDir "report_v${Version}.htm"
    # Send Ctrl+S won't work; use File > Save as instead via the report panel
    # Alternative: use SendKeys to trigger context menu
    [System.Windows.Forms.SendKeys]::SendWait("{APPS}")  # Context menu key
    Start-Sleep -Milliseconds 600
    [System.Windows.Forms.SendKeys]::SendWait("s")        # "Save as Report"
    Start-Sleep -Milliseconds 1500

    # A Save dialog should appear — type the path
    [System.Windows.Forms.SendKeys]::SendWait($reportFile)
    Start-Sleep -Milliseconds 400
    [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
    Start-Sleep -Milliseconds 2000

    if (Test-Path $reportFile) {
        return $reportFile
    }
    return $null
}

function Parse-ReportMetrics {
    param([string]$HtmlPath)
    if (-not (Test-Path $HtmlPath)) { return @{} }
    $html = Get-Content $HtmlPath -Raw -Encoding UTF8

    function ExtractValue($pattern) {
        if ($html -match $pattern) { return $Matches[1].Trim() }
        return ""
    }

    $m = @{}
    # MT4 report HTML patterns
    if ($html -match 'Total net profit[^<]*<[^>]+>\s*<[^>]+>([\d.\-]+)') { $m.NetProfit = $Matches[1] }
    if ($html -match 'Profit factor[^<]*<[^>]+>\s*<[^>]+>([\d.]+)')       { $m.ProfitFactor = $Matches[1] }
    if ($html -match 'Expected payoff[^<]*<[^>]+>\s*<[^>]+>([\d.\-]+)')   { $m.ExpectedPayoff = $Matches[1] }
    if ($html -match 'Absolute drawdown[^<]*<[^>]+>\s*<[^>]+>([\d.]+)')   { $m.AbsDD = $Matches[1] }
    if ($html -match 'Maximal drawdown[^<]*<[^>]+>\s*<[^>]+>([\d.]+)\s*\(([\d.]+)%\)') {
        $m.MaxDDAmt = $Matches[1]; $m.MaxDDPct = $Matches[2]
    }
    if ($html -match 'Relative drawdown[^<]*<[^>]+>\s*<[^>]+>([\d.]+)%') { $m.RelDD = $Matches[1] }
    if ($html -match 'Total trades[^<]*<[^>]+>\s*<[^>]+>(\d+)')           { $m.TotalTrades = $Matches[1] }
    if ($html -match 'Win trades[^<]*<[^>]+>\s*<[^>]+>(\d+).*?\(([\d.]+)%\)') {
        $m.WinTrades = $Matches[1]; $m.WinRate = $Matches[2]
    }
    if ($html -match 'Maximum consecutive wins[^<]*<[^>]+>\s*<[^>]+>(\d+)\s*\(([\d.]+)\)') {
        $m.MaxConsecWins = $Matches[1]; $m.MaxConsecWinsAmt = $Matches[2]
    }
    if ($html -match 'Maximum consecutive losses[^<]*<[^>]+>\s*<[^>]+>(\d+)\s*\(([\d.]+)\)') {
        $m.MaxConsecLosses = $Matches[1]; $m.MaxConsecLossesAmt = $Matches[2]
    }
    if ($html -match 'Initial deposit[^<]*<[^>]+>\s*<[^>]+>([\d.]+)')     { $m.InitDeposit = $Matches[1] }
    return $m
}

function Set-StrategyTesterEA {
    param([string]$Version)
    $mt4 = Get-MT4Window
    if (-not $mt4) { return $false }

    [Win32]::SetForegroundWindow($mt4.MainWindowHandle) | Out-Null
    Start-Sleep -Milliseconds 800

    # Use UI Automation to find the EA ComboBox and select the version
    try {
        $rootEl = [System.Windows.Automation.AutomationElement]::FromHandle($mt4.MainWindowHandle)
        # Find combobox named "Expert Advisor" or the one containing EA names
        $cond = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::ComboBox)
        $combos = $rootEl.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)
        foreach ($cb in $combos) {
            $name = $cb.Current.Name
            if ($name -match "Expert|EA|Buy") {
                # Try to expand and select
                try {
                    $expPat = $cb.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern)
                    $expPat.Expand()
                    Start-Sleep -Milliseconds 500
                    # Find the list item matching our version
                    $itemCond = New-Object System.Windows.Automation.PropertyCondition(
                        [System.Windows.Automation.AutomationElement]::NameProperty,
                        "Buy & Sell EA v${Version}.ex4")
                    $item = $cb.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $itemCond)
                    if ($item) {
                        $selPat = $item.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
                        $selPat.Select()
                        Start-Sleep -Milliseconds 500
                        $expPat.Collapse()
                        Write-Host "  Selected EA v$Version" -ForegroundColor Green
                        return $true
                    }
                    $expPat.Collapse()
                } catch {}
            }
        }
    } catch { Write-Warning "UI Automation error: $_" }
    return $false
}

function Click-StartButton {
    $mt4 = Get-MT4Window
    if (-not $mt4) { return }
    [Win32]::SetForegroundWindow($mt4.MainWindowHandle) | Out-Null
    Start-Sleep -Milliseconds 500

    try {
        $rootEl = [System.Windows.Automation.AutomationElement]::FromHandle($mt4.MainWindowHandle)
        $btnCond = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::NameProperty, "Start")
        $startBtn = $rootEl.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $btnCond)
        if ($startBtn) {
            $inv = $startBtn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
            $inv.Invoke()
            Write-Host "  Clicked Start" -ForegroundColor Green
        } else {
            Write-Warning "Start button not found"
        }
    } catch { Write-Warning "Error clicking Start: $_" }
}

# ── Main loop ─────────────────────────────────────────────────────────────────
Write-Host "=== EA Backtest Automation ===" -ForegroundColor Yellow
Write-Host "Versions to test: $($Versions -join ', ')" -ForegroundColor Yellow
Write-Host ""

foreach ($ver in $Versions) {
    Write-Host "[$ver] Starting backtest..." -ForegroundColor Cyan

    # If this isn't the first version, select it (first one already selected)
    if ($ver -ne $Versions[0]) {
        $ok = Set-StrategyTesterEA -Version $ver
        if (-not $ok) {
            Write-Warning "[$ver] Could not select EA — skipping"
            continue
        }
        Start-Sleep -Milliseconds 1000
        Click-StartButton
    }

    # Wait for completion
    $done = Wait-ForBacktestComplete -TimeoutMinutes 90
    if (-not $done) {
        Write-Warning "[$ver] Timed out — skipping"
        continue
    }

    Start-Sleep -Seconds 3

    # Save report and parse
    $reportPath = Read-BacktestReport -Version $ver
    $metrics    = if ($reportPath) { Parse-ReportMetrics -HtmlPath $reportPath } else { @{} }

    Write-Host "[$ver] Metrics: WinRate=$($metrics.WinRate)% Return=$($metrics.NetProfit) MaxDD=$($metrics.MaxDDPct)% Trades=$($metrics.TotalTrades)" -ForegroundColor Green

    # Calculate return %
    $returnPct = ""
    $returnAmt = ""
    if ($metrics.NetProfit -and $metrics.InitDeposit) {
        $rp = [math]::Round(([double]$metrics.NetProfit / [double]$metrics.InitDeposit) * 100, 2)
        $returnPct = "$rp"
        $returnAmt = [math]::Round([double]$metrics.NetProfit).ToString()
    }

    # Capture graph and send email
    # NOTE: ALWAYS sends, every run (pass or fail) — no goal gate here.
    Write-Host "[$ver] Sending email report..." -ForegroundColor Cyan
    # PS 5.1-safe null fallback (the ?? operator is PowerShell 7+ only and
    # would make this whole script fail to parse under Windows PowerShell 5.1).
    function Nz($v) { if ($null -eq $v) { "" } else { "$v" } }
    $params = @(
        "-Version",           $ver
        "-WinRate",           (Nz $metrics.WinRate)
        "-ReturnPct",         $returnPct
        "-ReturnAmt",         $returnAmt
        "-MaxDD",             (Nz $metrics.MaxDDPct)
        "-MaxDDAmt",          (Nz $metrics.MaxDDAmt)
        "-TotalTrades",       (Nz $metrics.TotalTrades)
        "-MaxConsecWins",     (Nz $metrics.MaxConsecWins)
        "-MaxConsecWinsAmt",  (Nz $metrics.MaxConsecWinsAmt)
        "-MaxConsecLosses",   (Nz $metrics.MaxConsecLosses)
        "-MaxConsecLossesAmt",(Nz $metrics.MaxConsecLossesAmt)
    )
    & $SendScript @params

    Write-Host "[$ver] Done." -ForegroundColor Green
    Write-Host ""
    Start-Sleep -Seconds 5
}

Write-Host "=== All backtests complete ===" -ForegroundColor Yellow
