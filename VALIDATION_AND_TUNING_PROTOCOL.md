# Validation & tuning protocol — v810 Hybrid (turnkey)

Run this the moment an MT4 tester is available (locally once the GUI is back, or on the VPS
which has the 2019-2026 gold history). No guesswork — exact steps + the decision rules.

## 0. Load
- Strategy Tester: Expert = `Buy & Sell EA v810 Hybrid`, Symbol = XAUUSD, Period = M30,
  Model = Every tick, Deposit = $10,000, Spread = 20.
- Load `setfiles\v810_Hybrid_recommended.set` (Expert properties -> Load).

## 1. PRIMARY test — the long window (this is where the trend engine pays off)
- Date range: **2019.01.01 -> 2026.05.31** (if history isn't loaded: Tools -> History Center ->
  XAUUSD -> download M1/M5/M30/H1, or run on the VPS which already has it).
- Run. Record: Net %, MaxDD %, PF, WR, Trades, ConsecW/L.
- TARGET: high return (the engine did +392% standalone) with MaxDD <= ~10-15% after the governor.

## 2. TUNE the risk split to the DD mandate
The trend engine drives drawdown. Sweep in this order, stop when MaxDD <= your cap:
- `T_Risk_Pct`: 0.35 -> 0.25 -> 0.15   (lower = less DD, less return)
- `DD_Budget` : 5.5 -> 4.5 -> 3.5       (lower = harder throttle, tighter DD ceiling)
- `MR_Risk_Pct`: keep ~0.45 (mean-rev DD is small; it's the smoother)
Pick the split with the highest Net % whose MaxDD <= target. Save it as a new .set.

## 3. REGIME-switch A/B (confirm the ADX router helps)
- Run with `Use_ADX_Regime=true` (default) vs `false`. Keep whichever gives better return/DD.
- Optionally sweep `ADX_Split`: 20 / 25 / 30.

## 4. ISOLATE each engine (sanity / attribution)
- `Use_MeanRev=false` -> pure trend (should match v600's profile: high return, low WR, big DD).
- `Use_Trend=false`   -> pure mean-rev (should match v700: high WR, tiny DD, low return).
- Confirms the blend = the sum, and the governor caps the combined DD.

## 5. Report
Run `tools\Capture-And-Send.ps1 -Version "810 <config>" -ReturnPct .. -MaxDD .. -WinRate .. ...`
to email the result + curve, and append to the comparison table.

## Decision rule for "the best EA"
Best = highest Net % among configs with MaxDD <= your drawdown cap. Expectation:
the v810 blend should beat the pure mean-rev line (v513 ~+23%) by a wide margin on the long
window because v600's trend engine compounds through gold's multi-year bull run — the governor
+ risk-split are what keep its drawdown inside the mandate.

## Files (this folder)
- source/  + compiled/ : v343, v512, v513, v600, v700, v800, v810
- setfiles/v810_Hybrid_recommended.set : load-ready preset
- README_and_MERGE_PLAN.md : strategy breakdown + merge rationale
