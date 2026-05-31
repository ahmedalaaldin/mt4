---
name: project-investment-castle-ea
description: "Buy & Sell EA iterative optimization project — MT4 Expert Advisor for XAUUSD, 497+ versions deep"
metadata: 
  node_type: memory
  type: project
  originSessionId: 5e0e6362-8e67-41a6-9748-b2b6a12ae1db
---

# Investment Castle — Buy & Sell EA

**IMPORTANT — file locations:**
- **MT4 Experts path (LIVE + SOURCE for v100+):** `C:\Users\ahmed\AppData\Roaming\MetaQuotes\Terminal\5D49F47D1EA1ECFC0DDC965B6D100AC5\MQL4\Experts\`
- **OneDrive source path (older versions only, v1-v99):** `C:\Users\ahmed\OneDrive\Investment Castle\FX\Source\MT4\EAs\Buy & Sell\`
- **Always search MT4 Experts folder for true latest version (.mq4 AND .ex4 files)**
- **Current version: v509** (as of 2026-05-31). ALWAYS `Get-ChildItem` the Experts folder to
  confirm the true latest version before creating a new one — memory can lag the user's own runs.
- v500-v509 are a CONTINUATION OF THE v499 LINE (corrupted header, H4_Fast=500), made by the
  user earlier 2026-05-31 (12-3PM). Lineage of changes:
    v500: Risk_Pct 1.5->3.0 (recover return)        [I overwrote this; reconstructed from v499]
    v501: removed fixed TP, tp=0 dynamic-close in ManageExits  [overwrote; reconstructed from v502]
    v503: RSI_Buy 45->30, disable TwoBar (first-touch hypothesis)
    v507: Risk_Pct=2.5 base + HALVING after each consecutive loss; DD_Budget DISABLED (=100)
    v508: Max_Buys=1, halving capped ~5% MaxDD
    v509: latest (halving-mechanism line)
- INCIDENT: my tonight v500/v501 (v411-based MM experiments, Risk 0.95 / DD_Budget 4.2) used the
  500/501 names and overwrote the user's originals via Copy-Item -Force. No shadow/history/recycle
  recovery possible; RECONSTRUCTED both (v500=v499+Risk3.0 exact; v501=from v502, logic preserved).
  KV ea:result:500/501 now hold MY metrics (12.05%/13.12%), not the user's morning numbers.
  LESSON: check directory for true latest before Copy-Item -Force onto version filenames.
- NOTE: my "MM saturated" finding was vs the OLD DD_Budget design; v507+ uses a NEWER halving
  mechanism (DD_Budget disabled).

## v509 BACKTEST (standard window, 2026-05-31) — PIVOTAL FINDING
- v509 (halving mechanism, Risk_Pct=2.5 base, Max_Buys=1, DD_Budget=100/disabled):
  +76.63% ($7662.82), Maximal DD **31.40%** ($3272.68), WR 48.11%, 291 trades,
  6 consec wins, 7 consec losses, PF 1.36.
- HUGE return (5.4x v411's 14.26%) BUT catastrophic DD (31.40% — 6x over the 5% cap).
  v508's header claim "halving capped at ~5% MaxDD" is FALSE on this window. The
  risk-halving-after-loss does NOT control drawdown when base risk is 2.5.
- REFRAME: two distinct regimes now proven on the SAME window:
    v411 = LOW risk: +14.26% @ 4.43% DD, WR 74% (DD-safe, return too low)
    v509 = HIGH risk: +76.63% @ 31.40% DD, WR 48% (return closer, DD blown)
  The project's real unsolved problem = DD CONTROL at high base risk. Return potential
  clearly exists (76%); need a sizing/stop mechanism that actually caps DD near 5% while
  keeping high base exposure. The halving as implemented doesn't do it.
- Leaderboard: v509 now tops KV by return (76.63%) but its 31.40% DD column flags it as
  non-viable under the ≤5% mandate.
- Compile workflow: edit .mq4 → `metaeditor.exe /compile:"<path>" /log:"<log>"` → .ex4 auto-appears
  in tester combobox. v411-line warnings (return value of OrderClose/Modify not checked) are benign.

## Goals (unmet targets)
- >200% return per year
- Max Drawdown ≤ 5%
- Max Consecutive Losers < 3
- Min Consecutive Winners ≥ 10
- Min Trades per Day ≥ 5

## v497 Backtest (2025.01.25–2026.05.31, XAUUSD M5, Every Tick, $10k)
- Return: +4.88% (~3.7%/yr) ❌
- Max DD: 6.00% ❌ (just over 5% target)
- Win Rate: 62.44% ✓
- Total Trades: 418 (~0.86/day) ❌
- Consec. Losses: 12 ❌
- Consec. Wins: 57 ✅
- Profit Factor: 1.21
- Avg Win: $10.90, Avg Loss: -$15.01 ← core problem: avg loss > avg win

**Root cause of poor performance:** Partial_Pct=0.05 + Trail_ATR_Multi=0.40 is closing
partial positions too early for tiny profits while full SL is large. Result: avg win ($10.90)
much smaller than avg loss ($15.01) even at 62% WR → near-zero net profit.

## v497 Key Parameters
- Risk_Pct=1.50, Trail_ATR_Multi=0.40, Partial_Pct=0.05
- Max_Bars=22, ATR_Spike_Multi=2.2, H4_EMA_Fast_Period=60
- Session: 9-21, Max_Buys=1, Max_Sells=0
- BB_Dev=2.5, BB_Period=20, RSI_Buy=45.0, Body_Pct=0.20
- DD_Budget=3.8, ATR_SL_Multi=0.80, H1_EMA_Period=200
- Use_M15_Signals=true, Use_M30_Signals=true, Use_TwoBar_Pattern=true
- H1_RSI_Min=0.0, H1_RSI_Max=90.0 (effectively disabled)

## KEY FINDING — Risk_Pct is neutralized by DD_Budget scaling (v500, 2026-05-31)
- v500 = v411 + Risk_Pct 0.85→0.95 (single var). Result: +12.05% ($1205), MaxDD 4.45%,
  WR 73.44%, 576 trades, 41 cons W, 7 cons L. WORSE than v411 (+14.26%) — REFUTED.
- Why: DD_Budget=3.8 scaling shrinks lot size as drawdown grows, holding MaxDD ~constant
  (4.45% vs v411's 4.43% — barely moved despite +11.8% base risk). Higher base risk just
  trips the throttle + Max_Daily_DD_Pct(8%) earlier → fewer trades (576<606) → less return.
- IMPLICATION: cannot buy return by raising Risk_Pct alone — DD-budget mechanism cancels it.

## v501: DD_Budget 3.8->4.2 also REFUTED (2026-05-31)
- v501 = v411 + DD_Budget 3.8->4.2 (Risk back to 0.85). Result: +13.12% ($1311.90),
  Maximal DD 4.81% (relative DD 5.20%), WR 74.96%, 619 trades, 42 cons W, 7 cons L.
- Raising DD_Budget INCREASED drawdown (4.43%->4.81%) but DECREASED return (14.26%->13.12%).
  Path-dependence: bigger size during drawdowns → deeper dips → throttle sells size low →
  misses recovery. Worse risk-adjusted. Relative DD breached 5% (5.20%).

## STRATEGIC CONCLUSION — money management is SATURATED
- v411 (Risk=0.85, DD_Budget=3.8) is a local optimum. BOTH MM levers fail to beat it:
  Risk_Pct up (v500) and DD_Budget up (v501) each reduce return. Cannot extract more return
  from position sizing — it's path-dependent and self-defeating with the DD-budget throttle.
- THE BINDING CONSTRAINT IS THE EDGE ITSELF: trade frequency (~1.7/day vs ≥5 goal) and the
  small avg-win/avg-loss ratio (~12.8 / -29). Next versions must improve SIGNAL QUALITY or
  QUANTITY (entry logic, more TFs, better filters), or the avg-win:avg-loss (exit logic) —
  NOT money management. v411 remains the champion to beat.

## Architecture (locked NON-NEGOTIABLES)
- BB_Dev=2.5, BB_Period=20, TwoBar_Lookback=1
- Session=9-21 UTC, Max_Sells=0 (buys only)
- ATR_SL_Multi=0.80, RSI_Buy=45.0, RSI_Period=14, Body_Pct=0.20
- H1_EMA_Period=200, Use_TwoBar_Pattern=true

## Historical scoreboard (from v497 header)
- v342: M5+M15 → +29.51%, MaxDD=4.74%, WR=86.90%, 756 trades
- v343: M5+M15+M30 → +30.67%, MaxDD=4.87%, WR=85.14%, 814 trades
- v354: M5+M15+M30, ATR_Spike=2.0 → +30.33%, MaxDD=4.65%
- v355: ATR_Spike=1.5 → +0.73%, WR=70.16%, 305 trades FAIL
- v411: ALL-TIME BEST ratio=9.50, MaxDD=4.32%

## Workflow
After each iteration: copy vN, increment version, update header hypothesis, update Magic_Number.
After successful backtest (passes goals): run `Capture-And-Send.ps1` from `C:\Users\ahmed\OneDrive\Investment Castle\FX\Tools\`

## Email pipeline
- `Capture-And-Send.ps1` → `Send-BacktestReport.ps1` → POST `https://www.zargina.com/api/ea-report`
- **Cloudflare Worker:** `ea-reporter` (source at `C:\Users\ahmed\OneDrive\Investment Castle\FX\Tools\ea-reporter\`)
- **KV namespace:** `ea-backtest-results` (id: beca3fc85b784d3fbd076771bf387a0c)
- **Email TO:** worker + wrangler.toml hardcode `ahmed.alaaeldin@icloud.com` (same Apple mailbox as @me.com)
- **wrangler is v4.x → defaults to LOCAL mode. ALWAYS pass `--remote` for real KV reads/writes.**
- **Never write KV string values with `Set-Content -Encoding utf8` (PS 5.1 adds a UTF-8 BOM).**
  Use `[System.IO.File]::WriteAllText($p,$s,(New-Object System.Text.UTF8Encoding $false))`.
  A BOM in `ea:all_versions` broke the worker's `JSON.parse` → ok:false → no email.

## 2026-05-31 session fixes
- Email MIME fix (ver 690b82a3): HTML body part was declared `quoted-printable` but sent
  raw → Apple Mail/iCloud mangled markup and the inline equity-curve `<img>` didn't render
  in the body. Switched HTML part to `Content-Transfer-Encoding: base64` (added toBase64Utf8
  helper, UTF-8 safe for the 🥇🥈🥉 medals) + multipart/related type="text/html". Re-sent
  v411 + v354 with curves embedded. Capture-And-Send.ps1 deletes its temp PNG, so re-sending
  with an image requires the tester to still show that run's Graph (re-run if overwritten).
- Worker hardened: `parseJsonSafe()` strips BOM + tolerates corrupt JSON; KV/leaderboard
  step wrapped in try/catch so EMAIL ALWAYS SENDS even if KV fails. Deployed (ver 9c6c66b8).
- `Run-BacktestLoop.ps1`: replaced PS7-only `??` operators with PS 5.1-safe `Nz()` helper
  (the `??` was a parse error under Windows PowerShell 5.1, killing the loop before sending).
  Loop already sends on EVERY run (no goal gate in the script).
- Cleaned junk KV keys (`v_test_ping`, `test:wrangler_write`); confirmed live email delivery.

## Leaderboard reality (answer to "are the top 5 the absolute best v1→latest?")
- NO. KV holds only 8 recorded versions: 342,343,354,370,411,492,432,493. The other ~491
  were never POSTed. Ranking by returnPct: 370(33.64) > 343(30.67) > 354(30.33) > 342(29.51) > 492/432(12.83).
- 2026-05-31: RE-RAN v411 and v354 in Strategy Tester on the CURRENT standard window
  (2025.01.25–2026.05.31, Every Tick, $10k, M5) to capture real full metrics:
    v411: +14.26% ($1425.75), MaxDD 4.43%, WR 74.42%, 606 trades, 41 cons wins, 7 cons losses, PF 1.34
    v354: +4.93%  ($492.73),  MaxDD 4.85%, WR 69.57%, 539 trades, 39 cons wins, 12 cons losses, PF 1.13
  Both emailed + KV updated. v411 no longer shows 0%; v354 no longer has blank fields.
- REMAINING WINDOW MISMATCH: 370/343/342 records still hold LEGACY-window numbers (~30%)
  from an unknown older test window — NOT comparable to the current-window entries
  (411/432/492/354/493). New leaderboard top 5 by return: 370(33.64,legacy) > 343(30.67,legacy)
  > 342(29.51,legacy) > 411(14.26,real) > 432(12.83,real). To make the board fully
  apples-to-apples, re-run 342/343/370 on the current window too.
