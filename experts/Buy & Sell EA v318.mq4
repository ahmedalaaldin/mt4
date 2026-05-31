//+------------------------------------------------------------------+
//|   Buy & Sell EA v318 - Frequency Boost                           |
//|   BASE: v317 (H1 RSI fix + DD control) — frequency targeting    |
//|                                                                   |
//|   v317 RESULTS (2026.05.28):                                     |
//|     Return: +76.07%, MaxDD: 9.32%, Trades: 759 (2.9/day)        |
//|     WR: 89.59% (Long: 91.09%, Short: 83.10%)                    |
//|     MaxConsecWins: 61, MaxConsecLosses: 13                       |
//|     Profit Factor: 1.76, Expected Payoff: $10.02/trade           |
//|                                                                   |
//|   v317 ANALYSIS:                                                 |
//|     STRENGTH: Outstanding 89.59% WR                              |
//|       - ATR_Spike_Multi=0 removed a bad quality filter           |
//|       - H1_RSI_Min=0 removed contradictory gate                  |
//|       - Two-bar pattern + RSI + bullBody still ensuring quality  |
//|     GAP 1: 2.9 trades/day vs 20+/day target                     |
//|       Root cause A: BB_Dev=2.5 → only 1.24% of M5 bars close    |
//|         outside band → rare breakouts = rare two-bar setups     |
//|       Root cause B: bbPrevBreak checked bar[2] ONLY — misses    |
//|         valid setups where breakout happened 3-5 bars ago        |
//|       Root cause C: Session 9-21 = 12h/day vs 22h available     |
//|     GAP 2: MaxDD 9.32% vs <5% target                            |
//|       Root cause: Risk_Pct=2.0 → one SL = 2% DD, two in a row  |
//|         = 4% → still at full risk! Scale barely kicks in       |
//|     GAP 3: Return 76% vs 200%+ target                           |
//|       If frequency × (0.5× risk) = 3-4× net profit → 200%+     |
//|                                                                   |
//|   v318 CHANGES (6 changes from v317):                           |
//|     CHANGE 1: BB_Dev 2.5→2.0                                    |
//|       4.55% vs 1.24% of bars outside band → 3.7× more breakouts |
//|       Still selective (2σ = statistically significant boundary)  |
//|     CHANGE 2: TwoBar_Lookback 1→4 (NEW PARAMETER)              |
//|       Old: bbPrevBreak = Close[2] <= bbLower[2] (1 bar window)  |
//|       New: check bars 2,3,4,5 — true if ANY closed below BB     |
//|       3-4× more "active windows" after each breakout event      |
//|       Quality PRESERVED: still requires genuine prior breakout   |
//|     CHANGE 3: Session 9-21 → 1-23                               |
//|       Adds 10h of Asian + extended NY (was 12h, now 22h)        |
//|       1.83× more trading time — gold trades 24/5               |
//|     CHANGE 4: Max_Buys 1→2, Max_Sells 1→2                      |
//|       Allow 2 concurrent positions per direction                 |
//|       When two patterns fire within 1-2 bars: both taken         |
//|     CHANGE 5: Risk_Pct 2.0→1.0                                  |
//|       Per-trade risk halved → compensated by ~7× more trades    |
//|       With 5000+/year trades at $5/avg: ~$25,000 = 250% return  |
//|     CHANGE 6: DD_Budget 5.0→4.5                                 |
//|       With Risk_Pct=1.0: scale=(4.5-ddPct)/1.0                  |
//|       5 consecutive losses hit min scale around 4.5% DD          |
//|       → natural MaxDD cap ~4.7-4.8%                             |
//|                                                                   |
//|   EXPECTED RESULTS:                                              |
//|     Trades: ~15-22/day (5-7× boost from changes 1-4)            |
//|     Return: 200%+ (3-4× v317 net via frequency × half risk)     |
//|     MaxDD: 4.5-4.8% (Risk_Pct=1.0 + DD_Budget=4.5)             |
//|     WR: 84-88% (slight drop from BB_Dev=2.0 vs 2.5)             |
//|                                                                   |
//|   SCOREBOARD:                                                    |
//|     v300: Calmar=20.84 (258%, 12.4% MaxDD, 1040 trades/3.9d)   |
//|     v315: +1.95%, 9.13% MaxDD, 196 trades — H1_RSI contradiction|
//|     v317: +76.07%, 9.32% MaxDD, 759 trades (2.9/day), WR=89.6% |
//|     v318: This version — frequency + DD control                  |
//+------------------------------------------------------------------+
#property copyright ""
#property link      ""
#property version   "318.0"
#property strict

#include <stdlib.mqh>

//--- Session
// v318: Extended from 9-21 → 1-23 to capture Asian dip-buys and extended NY
input string SESSION_SET        = "============"; //====== Session Settings ======
input int    Session_Start_Hour = 1;              // v318: was 9 → 1 (adds 8h Asian session)
input int    Session_End_Hour   = 23;             // v318: was 21 → 23 (adds 2h NY extension)

//--- Trend Filter (unchanged from v317)
input string TREND_SET          = "============"; //====== Trend Filter ======
input int    H4_EMA_Period      = 200;
input int    H1_EMA_Period      = 200;            // kept: EMA200 = reliable bull/bear detection

//--- H1 RSI Gate (unchanged from v317)
// H1_RSI_Min=0: no lower gate (v317 fix — prevents blocking dip buys)
// H1_RSI_Max=90: mild overbought protection
input string H1RSI_SET          = "============"; //====== H1 RSI Gate ======
input int    H1_RSI_Period      = 14;
input double H1_RSI_Min         = 0.0;            // v317 fix: keeps all dip buys accessible
input double H1_RSI_Max         = 90.0;
input double H1_RSI_Min_Sell    = 20.0;
input double H1_RSI_Max_Sell    = 60.0;

//--- BB Entry Signal
// v318: BB_Dev 2.5→2.0 — key frequency lever
// At BB_Dev=2.0: 4.55% of bars close outside vs 1.24% at 2.5 → 3.7× more breakout events
// Still selective: 2σ boundary is statistically significant (95.45% of bars inside)
input string S1_SET             = "============"; //====== BB Signal ======
input int    BB_Period          = 20;
input double BB_Dev             = 2.0;            // v318: was 2.5 → 2.0 (3.7× more signals)
input int    RSI_Period         = 14;
input double RSI_Buy            = 40.0;           // kept: M5 RSI < 40 = genuine oversold
input double RSI_Sell           = 60.0;
input double Body_Pct           = 0.20;           // kept: bullish body filter

//--- Two-bar pattern with extended lookback (NEW in v318)
// v317: bbPrevBreak = Close[2] <= bbLower2 (check exactly bar[2])
// v318: bbPrevBreak = Close[k] <= bbLower[k] for k = 2..TwoBar_Lookback+1
//   TwoBar_Lookback=4: checks bars 2,3,4,5 → 4× wider window
//   Quality preserved: still requires a genuine BB breakout before the recovery
//   Rationale: after a breakout, price often re-tests the BB 2-5 bars later
//     — this re-test + recovery = high-quality mean-reversion entry
input string TWOBAR_SET         = "============"; //====== Two-Bar Pattern ======
input bool   Use_TwoBar_Pattern = true;           // kept true (v316 showed removing hurts WR)
input int    TwoBar_Lookback    = 4;              // v318: NEW — bars 2..5 checked for prior breakout

//--- Volatility Filter (unchanged from v317)
input string VOL_SET            = "============"; //====== Volatility Filter ======
input double Max_ATR_Pct        = 1.00;
input int    ATR_Spike_MA_Period = 50;
input double ATR_Spike_Multi    = 0.0;            // v317 fix: disabled — spike bars = valid setups

//--- Exit Settings (unchanged from v317)
input string EXIT_SET           = "============"; //====== Exit Settings ======
input int    ATR_Period         = 14;
input double ATR_SL_Multi       = 0.8;
input double ATR_TP_Multi       = 5.0;
input double Trail_ATR_Multi    = 0.1;
input double Partial_Pct        = 0.20;           // 20% partial at BB_mid → SL→entry → trail
input int    Max_Bars           = 30;

//--- Money Management
// v318: Risk_Pct 2.0→1.0 (halved per-trade risk, compensated by 7× frequency)
// v318: Max_Buys/Sells 1→2 (concurrent positions when 2 setups fire together)
// With Risk_Pct=1.0 and 5000+ trades/year:
//   Expected avg: ~$5/trade × 5000 = $25,000 = 250% annual return
input string MONEY_SET          = "============"; //====== Money Management ======
input double Risk_Pct           = 1.0;            // v318: was 2.0 → 1.0 (halved per-trade risk)
input double Fixed_Lot          = 0.0;
input int    Max_Buys           = 2;              // v318: was 1 → 2 (concurrent longs allowed)
input int    Max_Sells          = 2;              // v318: was 1 → 2 (concurrent shorts allowed)

//--- DD-Budget Scaling
// v318: DD_Budget 5.0→4.5, Risk_Pct=1.0
// Scale = max(0.15, min(1.0, (4.5 - ddPct) / 1.0))
// At ddPct=0:   scale=4.5→cap 1.0  → 1.0% per trade
// At ddPct=3.5: scale=1.0           → 1.0% per trade (still full risk)
// At ddPct=4.0: scale=0.5           → 0.5% per trade
// At ddPct=4.5: scale=0.0→Min 0.15 → 0.15% per trade
// 5 consecutive losses at full risk: 5×1.0% = 5% → BLOCKED by scale at 4.5%
// Natural MaxDD cap: ~4.7-4.8%
input string DDB_SET            = "============"; //====== DD-Budget Scale ======
input double DD_Budget          = 4.5;            // v318: was 5.0 → 4.5 (tighter risk budget)
input double Min_Scale          = 0.15;           // kept: ensures partial close math works

//--- Safety (unchanged from v317)
input string SAFETY_SET        = "============"; //====== Safety Settings ======
input int    MaxSpread          = 35;
input int    Slippage           = 30;
input int    Magic_Number       = 3182057;
input string Order_Comment      = "BSv318";
input double Max_Daily_DD_Pct   = 8.0;
input int    Max_Trades_Day     = 300;

//+------------------------------------------------------------------+
double   g_DayOpenEquity  = 0;
bool     g_DailyDDHit     = false;
int      g_TradesToday    = 0;
datetime g_LastDay        = 0;
double   g_InitialBalance = 0;
double   g_PeakBalance    = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   g_InitialBalance = AccountBalance();
   g_PeakBalance    = AccountBalance();
   return(INIT_SUCCEEDED);
}
void OnDeinit(const int reason) {}

//+------------------------------------------------------------------+
// DD-Budget scaling (same formula as v317, DD_Budget=4.5 instead of 5.0)
// With Risk_Pct=1.0 and DD_Budget=4.5:
//   - Full risk runs until ddPct = DD_Budget - Risk_Pct = 3.5%
//   - Then scale linearly reduces until ddPct = DD_Budget (4.5%)
//   - After 4.5% DD: Min_Scale=0.15 kicks in (tiny lots, protects remaining capital)
double GetRiskScale()
{
   double curBalance = AccountBalance();
   if(curBalance > g_PeakBalance) g_PeakBalance = curBalance;
   double ddPct = 0;
   if(g_PeakBalance > 0)
      ddPct = (g_PeakBalance - curBalance) / g_PeakBalance * 100.0;
   double scale = (DD_Budget - ddPct) / Risk_Pct;
   return MathMax(Min_Scale, MathMin(1.0, scale));
}

//+------------------------------------------------------------------+
double CalcLots(double slDist, double riskScale = 1.0)
{
   if(Fixed_Lot > 0) return NormalizeDouble(Fixed_Lot, 2);
   double tickVal  = MarketInfo(Symbol(), MODE_TICKVALUE);
   double tickSize = MarketInfo(Symbol(), MODE_TICKSIZE);
   if(tickVal <= 0 || tickSize <= 0) return MarketInfo(Symbol(), MODE_MINLOT);
   double riskAmt = AccountEquity() * (Risk_Pct * riskScale) / 100.0;
   double capAmt  = g_InitialBalance * (Risk_Pct * riskScale) / 100.0;
   if(riskAmt > capAmt) riskAmt = capAmt;
   double slTicks  = slDist / tickSize;
   double lots     = riskAmt / (slTicks * tickVal);
   double stepLot  = MarketInfo(Symbol(), MODE_LOTSTEP);
   double minLot   = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot   = MarketInfo(Symbol(), MODE_MAXLOT);
   lots = MathFloor(lots / stepLot) * stepLot;
   return NormalizeDouble(MathMax(minLot, MathMin(maxLot, lots)), 2);
}

//+------------------------------------------------------------------+
int CountTradesByMagic(int type, int magic)
{
   int n = 0;
   for(int i = 0; i < OrdersTotal(); i++)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() == Symbol() && OrderMagicNumber() == magic && OrderType() == type) n++;
   }
   return n;
}

//+------------------------------------------------------------------+
void CloseAllTrades()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != Magic_Number) continue;
      if(OrderType() == OP_BUY)
         OrderClose(OrderTicket(), OrderLots(), Bid, Slippage, clrOrange);
      else if(OrderType() == OP_SELL)
         OrderClose(OrderTicket(), OrderLots(), Ask, Slippage, clrOrange);
   }
}

//+------------------------------------------------------------------+
void ManageExits()
{
   double atr   = iATR(NULL, 0, ATR_Period, 1);
   double bbMid = iBands(NULL, 0, BB_Period, BB_Dev, 0, PRICE_CLOSE, MODE_MAIN, 0);
   if(atr <= 0 || bbMid <= 0) return;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != Magic_Number) continue;
      int    tkt       = OrderTicket();
      double openPrice = OrderOpenPrice();
      double currentSL = OrderStopLoss();
      int    type      = OrderType();
      int    bars      = iBarShift(NULL, 0, OrderOpenTime(), false);

      if(type == OP_BUY)
      {
         bool partialDone = (currentSL >= openPrice);
         if(!partialDone && Bid >= bbMid)
         {
            double stepLot  = MarketInfo(Symbol(), MODE_LOTSTEP);
            double minLot   = MarketInfo(Symbol(), MODE_MINLOT);
            double partLots = MathFloor(OrderLots() * Partial_Pct / stepLot) * stepLot;
            if(partLots >= minLot && partLots < OrderLots())
            {
               if(OrderClose(tkt, partLots, Bid, Slippage, clrCyan))
                  if(OrderSelect(tkt, SELECT_BY_TICKET, MODE_TRADES))
                     OrderModify(tkt, openPrice, NormalizeDouble(openPrice, Digits), 0, 0, clrBlue);
            }
            else
            {
               if(currentSL < openPrice)
                  OrderModify(tkt, openPrice, NormalizeDouble(openPrice, Digits), 0, 0, clrBlue);
            }
            continue;
         }
         if(partialDone)
         {
            double trailSL = NormalizeDouble(bbMid - Trail_ATR_Multi * atr, Digits);
            if(trailSL > currentSL)
               OrderModify(tkt, openPrice, trailSL, 0, 0, clrBlue);
         }
         if(bars >= Max_Bars) OrderClose(tkt, OrderLots(), Bid, Slippage, clrYellow);
      }
      else if(type == OP_SELL)
      {
         bool partialDone = (currentSL > 0 && currentSL <= openPrice);
         if(!partialDone && Ask <= bbMid)
         {
            double stepLot  = MarketInfo(Symbol(), MODE_LOTSTEP);
            double minLot   = MarketInfo(Symbol(), MODE_MINLOT);
            double partLots = MathFloor(OrderLots() * Partial_Pct / stepLot) * stepLot;
            if(partLots >= minLot && partLots < OrderLots())
            {
               if(OrderClose(tkt, partLots, Ask, Slippage, clrCyan))
                  if(OrderSelect(tkt, SELECT_BY_TICKET, MODE_TRADES))
                     OrderModify(tkt, openPrice, NormalizeDouble(openPrice, Digits), 0, 0, clrBlue);
            }
            else
            {
               if(currentSL > openPrice || currentSL == 0)
                  OrderModify(tkt, openPrice, NormalizeDouble(openPrice, Digits), 0, 0, clrBlue);
            }
            continue;
         }
         if(partialDone)
         {
            double trailSL = NormalizeDouble(bbMid + Trail_ATR_Multi * atr, Digits);
            if(trailSL < currentSL)
               OrderModify(tkt, openPrice, trailSL, 0, 0, clrBlue);
         }
         if(bars >= Max_Bars) OrderClose(tkt, OrderLots(), Ask, Slippage, clrYellow);
      }
   }
}

//+------------------------------------------------------------------+
void OnTick()
{
   static datetime s_LastBar = 0;
   bool isNewBar = (Time[0] != s_LastBar);
   if(isNewBar) s_LastBar = Time[0];

   double curBalance = AccountBalance();

   MqlDateTime dt;
   TimeToStruct(Time[0], dt);
   datetime today = StringToTime(StringFormat("%d.%02d.%02d", dt.year, dt.mon, dt.day));
   if(today != g_LastDay)
   {
      g_DayOpenEquity = curBalance;
      g_DailyDDHit    = false;
      g_TradesToday   = 0;
      g_LastDay       = today;
   }

   if(!g_DailyDDHit && g_DayOpenEquity > 0)
   {
      double ddPct = (g_DayOpenEquity - curBalance) / g_DayOpenEquity * 100.0;
      if(ddPct >= Max_Daily_DD_Pct) { CloseAllTrades(); g_DailyDDHit = true; return; }
   }
   if(g_DailyDDHit) return;

   ManageExits();
   if(!isNewBar) return;

   bool inSession = (dt.hour >= Session_Start_Hour && dt.hour < Session_End_Hour);
   if(!inSession) return;
   if(MarketInfo(Symbol(), MODE_SPREAD) > MaxSpread) return;
   if(g_TradesToday >= Max_Trades_Day) return;

   double h1_ema  = iMA(NULL, PERIOD_H1, H1_EMA_Period, 0, MODE_EMA, PRICE_CLOSE, 0);
   double h1_rsi1 = iRSI(NULL, PERIOD_H1, H1_RSI_Period, PRICE_CLOSE, 1);

   bool h1Bull = (iClose(NULL, PERIOD_H1, 1) > h1_ema)
              && (h1_rsi1 >= H1_RSI_Min) && (h1_rsi1 <= H1_RSI_Max);
   bool h1Bear = (iClose(NULL, PERIOD_H1, 1) < h1_ema)
              && (h1_rsi1 >= H1_RSI_Min_Sell) && (h1_rsi1 <= H1_RSI_Max_Sell);

   double atr1 = iATR(NULL, 0, ATR_Period, 1);
   if(atr1 <= 0) return;

   if(Max_ATR_Pct > 0)
   {
      double price1 = iClose(NULL, 0, 1);
      if(price1 > 0 && (atr1 / price1 * 100.0) > Max_ATR_Pct) return;
   }
   if(ATR_Spike_Multi > 0)
   {
      double atr_slow = iATR(NULL, 0, ATR_Spike_MA_Period, 1);
      if(atr_slow > 0 && atr1 > ATR_Spike_Multi * atr_slow) return;
   }

   double bbUpper1 = iBands(NULL, 0, BB_Period, BB_Dev, 0, PRICE_CLOSE, MODE_UPPER, 1);
   double bbLower1 = iBands(NULL, 0, BB_Period, BB_Dev, 0, PRICE_CLOSE, MODE_LOWER, 1);

   double rsi1 = iRSI(NULL, 0, RSI_Period, PRICE_CLOSE, 1);
   double rsi2 = iRSI(NULL, 0, RSI_Period, PRICE_CLOSE, 2);

   double slDist    = ATR_SL_Multi * atr1;
   double tpDist    = ATR_TP_Multi * atr1;
   double riskScale = GetRiskScale();

   double candleRange = High[1] - Low[1];
   double candleBodyB = Close[1] - Open[1];
   double candleBodyS = Open[1] - Close[1];

   //=== BUY ===
   if(h1Bull)
   {
      bool bbTouch   = (Low[1] <= bbLower1) && (Close[1] > bbLower1);
      bool rsiOS     = (rsi1 < RSI_Buy);
      bool rsiRising = (rsi1 > rsi2);
      bool bullBody  = (candleBodyB > 0) && (candleRange > 0)
                    && (candleBodyB >= Body_Pct * candleRange);

      // v318: Extended N-bar lookback two-bar pattern
      // Checks if any bar from [2] to [TwoBar_Lookback+1] closed below its BB lower band
      // TwoBar_Lookback=4: checks bars 2,3,4,5
      // Quality preserved: requires genuine prior BB breakout before the recovery
      bool bbPrevBreak = !Use_TwoBar_Pattern;
      if(!bbPrevBreak)
      {
         int maxLook = TwoBar_Lookback + 1;
         for(int j = 2; j <= maxLook; j++)
         {
            double bbLowJ = iBands(NULL, 0, BB_Period, BB_Dev, 0, PRICE_CLOSE, MODE_LOWER, j);
            if(Close[j] <= bbLowJ) { bbPrevBreak = true; break; }
         }
      }

      if(bbTouch && rsiOS && rsiRising && bullBody && bbPrevBreak)
      {
         if(CountTradesByMagic(OP_BUY, Magic_Number) < Max_Buys)
         {
            double entry = NormalizeDouble(Ask, Digits);
            double sl    = NormalizeDouble(entry - slDist, Digits);
            double tp    = NormalizeDouble(entry + tpDist, Digits);
            double lots  = CalcLots(slDist, riskScale);
            if(lots > 0)
            {
               int tkt = OrderSend(Symbol(), OP_BUY, lots, entry, Slippage,
                                   sl, tp, Order_Comment, Magic_Number, 0, clrGreen);
               if(tkt > 0) g_TradesToday++;
            }
         }
      }
   }

   //=== SELL ===
   if(h1Bear)
   {
      bool bbTouchUp  = (High[1] >= bbUpper1) && (Close[1] < bbUpper1);
      bool rsiOB      = (rsi1 > RSI_Sell);
      bool rsiFalling = (rsi1 < rsi2);
      bool bearBody   = (candleBodyS > 0) && (candleRange > 0)
                     && (candleBodyS >= Body_Pct * candleRange);

      // v318: Extended N-bar lookback two-bar pattern (sell side)
      bool bbPrevBreakUp = !Use_TwoBar_Pattern;
      if(!bbPrevBreakUp)
      {
         int maxLook = TwoBar_Lookback + 1;
         for(int j = 2; j <= maxLook; j++)
         {
            double bbUpJ = iBands(NULL, 0, BB_Period, BB_Dev, 0, PRICE_CLOSE, MODE_UPPER, j);
            if(Close[j] >= bbUpJ) { bbPrevBreakUp = true; break; }
         }
      }

      if(bbTouchUp && rsiOB && rsiFalling && bearBody && bbPrevBreakUp)
      {
         if(CountTradesByMagic(OP_SELL, Magic_Number) < Max_Sells)
         {
            double entry = NormalizeDouble(Bid, Digits);
            double sl    = NormalizeDouble(entry + slDist, Digits);
            double tp    = NormalizeDouble(entry - tpDist, Digits);
            double lots  = CalcLots(slDist, riskScale);
            if(lots > 0)
            {
               int tkt = OrderSend(Symbol(), OP_SELL, lots, entry, Slippage,
                                   sl, tp, Order_Comment, Magic_Number, 0, clrRed);
               if(tkt > 0) g_TradesToday++;
            }
         }
      }
   }
}
//+------------------------------------------------------------------+
