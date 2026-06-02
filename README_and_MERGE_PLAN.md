# Investment Castle EAs — consolidation + merge plan

## Saved here (verified on this machine)
| EA | Type | Best result (standard window) |
|---|---|---|
| Buy & Sell EA v343 | mean-reversion (legacy) | +30.67% / 4.87% DD / WR 85% (legacy window) |
| Buy & Sell EA v512 | mean-reversion + short side | +19.30% / 4.98% DD / PF 1.37 / WR 74% |
| Buy & Sell EA v513 | v512 + ADX(H1) filter — BEST local | +23.04% / 5.08% DD / PF 1.44 / WR 78% |

## NOT on this machine (need from VPS)
These were built and backtested on the VPS; only the email reports reached this PC. Their
source + .set files are NOT here and NOT in the GitHub repo:
- **Gold Trend EA v600 (H1)** — D10 / SL3 / Trail5 — TREND follower.
  2019.01–2026.05, $10k: realized +392.6% ($49,262), MT4 net +968.96%, **PF 1.41, MaxDD 42.3%, WR 35.8%, 2771 trades.**
  -> This is the HIGH-RETURN engine. Low WR + high DD = classic trend-following signature (few big winners).
- **MeanRev v700 (M30)** — RSI35 / SL4 / BBdev0.5 — MEAN-REVERSION.
  2023: +4.1% / DD 2.4% / **WR 81.6% / PF 1.78 / 103 trades**. On $190 start (auto-scale) -> ~$17,815.
  -> This is the SMOOTH / low-DD engine. High WR, tiny DD, many small winners.

## How to get them here (run on the VPS, in the cloned repo):
```
cd $env:USERPROFILE\mt4
copy "$env:APPDATA\MetaQuotes\Terminal\*\MQL4\Experts\*v600*.*"  experts\   2>$null
copy "$env:APPDATA\MetaQuotes\Terminal\*\MQL4\Experts\*v700*.*"  experts\   2>$null
copy "$env:APPDATA\MetaQuotes\Terminal\*\MQL4\Presets\*.set"     setfiles\  2>$null
git add -A ; git commit -m "add v600 Gold Trend + v700 MeanRev + set files" ; git push
```
Then locally I run `git pull` and I have everything to do the merge.

## The MERGE — why it's the real path to high return at controlled DD
v600 and v700 are **uncorrelated** (trend vs mean-reversion; they profit in opposite regimes).
A blended portfolio captures v600's huge trend return while v700 (and the v513 mean-rev) smooth
the equity curve and cut the aggregate drawdown — the only legitimate way to push return up
without DD exploding (diversification, the same principle that made v512's short side work).

Planned merged EA ("Buy & Sell EA v800 — Hybrid"):
1. Run BOTH engines under one EA, each with its own Magic number (so exits don't collide).
2. Risk-budget each: e.g., v600 trend at reduced risk so its standalone 42% DD scales toward
   ~15-20%, v700/v513 mean-rev adding steady WR. Sweep the risk split to hit the target DD.
3. Optional regime switch: ADX(H1) HIGH -> favor trend (v600); ADX LOW -> favor mean-rev (v700).
   (The ADX work in v513 already proved mean-rev dies in strong trends and trend lives there.)
4. Backtest the blend on 2019–2026 and tune the risk split for the best return at <= target DD.

NOTE: v600's 42% standalone DD must be scaled down in the blend — full v600 alone violates the
5% mandate. The merge's job is to keep most of v600's return while the diversification + risk
split pull the combined DD down to an acceptable band.
