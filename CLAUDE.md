# Investment Castle — Buy & Sell EA (project context for Claude)

This file loads automatically when Claude Code runs in this repo. It carries the
project's context over from the original machine. (Detailed history is in `memory/`;
note that absolute paths in those notes refer to the OLD machine — on this VPS the
project lives at the repo clone location and MT4 is under `%APPDATA%\MetaQuotes\...`.)

## What this project is
Iterative optimization of an MT4 Expert Advisor for **XAUUSD (Gold), M5**.
Strategy (LOCKED): Bollinger Band mean-reversion (BB_Period=20, BB_Dev=2.5) + RSI
confirmation (RSI_Buy=45) + two-bar pattern; **buys-only** (Max_Sells=0); 9–21 UTC
session; H1 EMA(200) + H4 EMA trend filters; multi-timeframe M5+M15+M30 signals;
ATR-based SL (ATR_SL_Multi=0.8), partial close, ATR trailing stop.

## Goals (a run must hit ALL five)
- Annual return **> 200%** · Max drawdown **≤ 5%** · Max consecutive losses **< 3**
- Min consecutive wins **≥ 10** · Min trades/day **≥ 5**

Standard backtest window: **2025.01.25 → 2026.05.31**, Every Tick, $10,000, M5, spread 20.

## Iteration workflow
Copy latest `.mq4` → bump version + unique Magic_Number + header hypothesis →
compile (`metaeditor.exe /compile:"<file>"`) → backtest in Strategy Tester →
if it runs, `tools/Capture-And-Send.ps1 -Version N ...` screenshots the equity curve and
emails a report (stores results in the Cloudflare KV `ea-backtest-results`).
ALWAYS check the Experts folder for the true latest version before creating a new one.

## Current frontier (established on the standard window)
- **v411** — DD-safe champion: **+14.26%, MaxDD 4.43%, WR 74.4%, 606 trades**.
- **v509** — halving mechanism (Risk_Pct=2.5 base, DD_Budget disabled): **+76.63% but MaxDD 31.40%**
  (fails the ≤5% cap; the "halving caps DD at ~5%" claim is false on this window).

## Key findings
- **Money management is saturated around v411.** Raising Risk_Pct (v500) or DD_Budget (v501)
  both REDUCE return — the sizing formula `effRisk = Risk_Pct*(DD_Budget-ddPct)/Risk_Pct`
  cancels Risk_Pct during drawdowns, so size depends only on DD_Budget there.
- **The unsolved problem is drawdown control at high base risk.** Return potential clearly
  exists (v509 hit 77%); a sizing/stop governor that holds DD near 5% does not yet exist.
- To raise return: improve the EDGE (signal quality/frequency ~1.7/day vs ≥5 goal, or the
  avg-win:avg-loss ratio ~$12.8 win vs ~$29 loss), NOT money management.

## Email/report pipeline
`tools/Send-BacktestReport.ps1` POSTs to `https://www.zargina.com/api/ea-report`.
Worker `ea-reporter` (in `tools/ea-reporter/`) persists to KV and emails an HTML report
with inline equity curve + all-time top-5 leaderboard. Reports go to the user's iCloud inbox.
- wrangler 4.x defaults to LOCAL — always pass `--remote` for real KV reads/writes.
- Never write KV string values with PowerShell `Set-Content -Encoding utf8` (adds a BOM that
  breaks the worker's JSON.parse). Use `[IO.File]::WriteAllText($p,$s,(New-Object Text.UTF8Encoding $false))`.

## User
Algorithmic trader; comfortable reading MQL4. Does not need basic syntax explained.
