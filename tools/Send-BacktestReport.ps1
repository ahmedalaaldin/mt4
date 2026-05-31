param(
    [Parameter(Mandatory=$true)]
    [string]$Version,

    [Parameter(Mandatory=$false)]
    [string]$ScreenshotPath = "",

    [string]$WinRate         = "",
    [string]$ReturnPct       = "",
    [string]$ReturnAmt       = "",   # Net profit in dollars e.g. "18746"
    [string]$MaxDD           = "",
    [string]$MaxDDAmt        = "",   # Max drawdown in dollars e.g. "6379"
    [string]$TotalTrades     = "",
    [string]$MaxConsecWins      = "",
    [string]$MaxConsecWinsAmt   = "",
    [string]$MaxConsecLosses    = "",
    [string]$MaxConsecLossesAmt = ""
)

$EndpointUrl = "https://www.zargina.com/api/ea-report"

$screenshotBase64 = ""
if ($ScreenshotPath -ne "" -and (Test-Path $ScreenshotPath)) {
    $bytes = [System.IO.File]::ReadAllBytes($ScreenshotPath)
    $screenshotBase64 = [Convert]::ToBase64String($bytes)
    $sizeKB = [Math]::Round($bytes.Length / 1KB, 1)
    Write-Host "Screenshot loaded: $ScreenshotPath ($sizeKB KB)"
} elseif ($ScreenshotPath -ne "") {
    Write-Warning "Screenshot file not found: $ScreenshotPath - sending without screenshot."
}

$results = [ordered]@{}
if ($WinRate -ne "") { $results["Win Rate"] = "${WinRate}%" }
if ($ReturnPct -ne "") {
    $returnStr = "${ReturnPct}%"
    if ($ReturnAmt -ne "") { $returnStr += "  (+`$$ReturnAmt on `$10,000)" }
    $results["Total Return"] = $returnStr
}
if ($MaxDD -ne "") {
    $ddStr = "${MaxDD}%"
    if ($MaxDDAmt -ne "") { $ddStr += "  (`$$MaxDDAmt peak-to-trough)" }
    $results["Max Drawdown"] = $ddStr
}
if ($TotalTrades     -ne "") { $results["Total Trades"]           = "${TotalTrades} trades" }
if ($MaxConsecWins -ne "") {
    $winsStr = "${MaxConsecWins} in a row"
    if ($MaxConsecWinsAmt -ne "") { $winsStr += "  (`$$MaxConsecWinsAmt)" }
    $results["Max Consecutive Wins"] = $winsStr
}
if ($MaxConsecLosses -ne "") {
    $lossStr = "${MaxConsecLosses} in a row"
    if ($MaxConsecLossesAmt -ne "") { $lossStr += "  (-`$$MaxConsecLossesAmt)" }
    $results["Max Consecutive Losses"] = $lossStr
}

$payload = [ordered]@{
    version           = $Version
    screenshot_base64 = $screenshotBase64
    results           = $results
}

$json = $payload | ConvertTo-Json -Depth 5

Write-Host "Sending backtest report for EA $Version to ahmed@zargina.com..."

try {
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $response = Invoke-RestMethod `
        -Uri $EndpointUrl `
        -Method Post `
        -ContentType "application/json; charset=utf-8" `
        -Body $bodyBytes `
        -ErrorAction Stop

    if ($response.ok -eq $true) {
        Write-Host "Email sent. ID: $($response.id)" -ForegroundColor Green
    } else {
        Write-Warning "Worker error: $($response.error)"
    }
} catch {
    $msg = $_.ToString()
    Write-Error "Failed: $msg"
}
