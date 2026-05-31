# Investment Castle — Buy & Sell EA

Iterative optimization of a MetaTrader 4 Expert Advisor for **XAUUSD (Gold), M5**.
Mean-reversion (Bollinger Band + RSI + two-bar pattern), buys-only, 9–21 UTC session,
H1/H4 EMA trend filters, multi-timeframe (M5+M15+M30) signals, ATR-based exits.

## Performance goals (a run must hit ALL five)
- Annual return **> 200%**
- Max drawdown **≤ 5%**
- Max consecutive losses **< 3**
- Min consecutive wins **≥ 10**
- Min trades/day **≥ 5**

Standard backtest window: **2025.01.25 → 2026.05.31**, Every Tick, $10,000, M5.

## Repo layout
| Folder | Contents |
|---|---|
| `experts/` | All `Buy & Sell EA vNNN.mq4` source + compiled `.ex4` (v3 → latest) |
| `tools/` | `Run-BacktestLoop.ps1`, `Capture-And-Send.ps1`, `Send-BacktestReport.ps1` |
| `tools/ea-reporter/` | Cloudflare Worker that stores results in KV + emails the report |
| `memory/` | Claude project memory — copy into `~/.claude/.../memory` on the VPS |

## Email/report pipeline
`Capture-And-Send.ps1` screenshots the Strategy Tester graph → `Send-BacktestReport.ps1`
POSTs `{version, screenshot_base64, results}` to `https://www.zargina.com/api/ea-report`.
The `ea-reporter` Worker persists to KV (`ea-backtest-results`, id `beca3fc85b784d3fbd076771bf387a0c`)
and emails an HTML report (inline equity curve + all-time top-5 leaderboard) to the configured inbox.

## VPS setup (Windows)
1. **Node.js** (LTS) — https://nodejs.org  (`node --version` to confirm)
2. **Claude Code** — `npm install -g @anthropic-ai/claude-code`, then run `claude` and authenticate.
3. **MT4** — install IC Markets MT4; copy `experts/*` into
   `%APPDATA%\MetaQuotes\Terminal\<id>\MQL4\Experts\`. Download XAUUSD M5 history (Tools → History Center).
4. **Memory** — copy `memory/*.md` into the Claude project's memory folder so context carries over.
5. **Wrangler** (only if redeploying the Worker from the VPS) — `npm i -g wrangler`, `wrangler login`.

## Compile workflow
Edit a `.mq4`, then:
`metaeditor.exe /compile:"<path to .mq4>" /log:"<log>"` → the `.ex4` appears and shows up in the Strategy Tester EA list.

## Current frontier (as of migration)
- **v411** — DD-safe champion on the standard window: +14.26%, MaxDD 4.43%, WR 74%.
- **v509** — high-return/high-DD (halving mechanism): +76.63% but MaxDD 31.40% (fails the ≤5% cap).
- Open problem: **drawdown control at high base risk** — return potential exists (v509), DD governor does not yet hold near 5%.
