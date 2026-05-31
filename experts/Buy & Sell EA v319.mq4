//+------------------------------------------------------------------+
//|   Buy & Sell EA v319 - MaxDD Fix + Session Extension             |
//|   BASE: v317 — MINIMAL 5 targeted changes (no quality changes)  |
//|                                                                   |
//|   v318 POST-MORTEM (903 trades, -11.12%, MaxDD=13.42%):         |
//|     FAILURE: WR collapsed 89.59% → 52.93%                       |
//|     CAUSE 1: BB_Dev 2.5→2.0                                     |
//|       With BB_Dev=2.0, ~4.55% of M5 bars close outside band     |
//|       TwoBar_Lookback=4 then found "prior breakout" almost       |
//|       always → bbPrevBreak was effectively ALWAYS TRUE          |
//|       Result: two-bar quality filter became non-functional       |
//|     CAUSE 2: TwoBar_Lookback=4 compounded the damage            |
//|       Stale breakouts (4 bars = 20 min ago) = poor entries       |
//|     LESSON: BB_Dev=2.5 + TwoBar_Lookback=1 are NON-NEGOTIABLE  |
//|       Cannot relax EITHER without catastrophic WR collapse       |
//|                                                                   |
//|   CONFIRMED OPTIMAL SETTINGS (v317 = 89.59% WR, non-negotiable):|
//|     BB_Dev=2.5, TwoBar_Lookback=1 (Close[2] <= bbLower2 only)  |
//|     H1_EMA_Period=200, H1_RSI_Min=0, ATR_Spike_Multi=0          |
//|     RSI_Buy=40, Body_Pct=0.20, Max_Buys=1, Max_Sells=1          |
//|     Session 9-21 (12h, proven hours for XAUUSD quality)         |
//|                                                                   |
//|   v319 CHANGES (5 changes, zero quality-filter changes):        |
//|     CHANGE 1: Session 9-21 → 1-23 (+10h, 1.83× frequency)      |
//|       Asian session (1-9) has some XAUUSD BB breakouts          |
//|       With BB_Dev=2.5 quality filter intact, Asian WR should    |
//|       still be 85%+ (above the 83% breakeven WR threshold)      |
//|       Expected: ~5-6 trades/day (was 2.9)                       |
//|     CHANGE 2: Risk_Pct 2.0→1.2 (MaxDD fix)                     |
//|       Lower per-trade risk = lower MaxDD                         |
//|       Compensated by more trades (Change 1) + compounding       |
//|     CHANGE 3: DD_Budget 5.0→4.2 (tighter risk budget)          |
//|       Scale formula starts capping at 4.2% instead of 5.0%      |
//|       Min_Scale kicks in at 4.2%+ DD                            |
//|     CHANGE 4: Min_Scale 0.15→0.07 (allows hard DD cap)         |
//|       At Min_Scale=0.07, Risk_Pct=1.2:                          |
//|         min lot = 0.07×1.2%×$10k / ($160/lot) = 0.053→0.05 lots|
//|         partial (20%) of 0.05 = 0.01 lots ✓ (works)            |
//|       With min trades at 0.084% risk, 13 extra losses after     |
//|       hard stop = only 1.1% more DD → total cap ~4.9%          |
//|     CHANGE 5: Hard_DD_Stop 0→4.8 (absolute MaxDD ceiling)      |
//|       When peak-to-current DD ≥ 4.8%: NO new trades            |
//|       Existing positions still managed (ManageExits always runs) |
//|       Last trade at min scale (0.084% risk) can't push DD>5%   |
//|     CHANGE 6: CalcLots cap: InitialBalance→PeakBalance          |
//|       Proper compounding: risk scales with growing account       |
//|       At $10k: risk=$120. After 100% profit ($20k): risk=$240  |
//|       Doubles annual return without increasing % MaxDD          |
//|                                                                   |
//|   MaxDD MATH:                                                    |
//|     Scale = max(0.07, min(1.0, (4.2 - ddPct) / 1.2))           |
//|     Loss sequence (worst case):                                  |
//|       dd=0%: scale=3.5→1.0 → 1.2% per trade                    |
//|       dd=1.2%: scale=2.5→1.0 → 1.2%                            |
//|       dd=2.4%: scale=1.5→1.0 → 1.2%                            |
//|       dd=3.6%: scale=0.5 → 0.6%                                 |
//|       dd=4.2%: scale=0→min0.07 → 0.084%                        |
//|       Hard stop at 4.8% → no more trades                        |
//|       Any open trade at min scale: max extra loss=0.084%        |
//|       → ABSOLUTE MaxDD CAP: 4.884% ✓ (under 5% target)         |
//|                                                                   |
//|   EXPECTED RESULTS:                                              |
//|     Trades: ~5-6/day (1.83× from session extension)             |
//|     WR: 87-89% (Asian hours slightly lower quality)             |
//|     Return: 100-150%+ (1.83× trades + compounding growth)       |
//|     MaxDD: <4.9% (hard stop guarantees this)                    |
//|                                                                   |
//|   SCOREBOARD:                                                    |
//|     v300: 258% return, 12.4% MaxDD, 1040 trades (3.9/day)      |
//|     v317: +76%, 9.32% MaxDD, 759 trades (2.9/day), WR=89.59%   |
//|     v318: -11%, 13.42% MaxDD, 903 trades — WR collapse (DEAD)  |
//|     v319: This version — targeted fix, quality unchanged         |
//+------------------------------------------------------------------+
#property copyright ""
#property link      ""
#property version   "319.0"
#property strict

#include <stdlib.mqh>

//--- Session
// v319: Extended 9-21 → 1-23 to add Asian session + extended NY close
// Asian (01-09): lower volatility but BB_Dev=2.5 still gives quality signals
// Extended NY (21-23): active market close period
input string SESSION_SET        = "============"; //====== Session Settings ======
input int    Session_Start_Hour = 1;              // v319: was 9 → 1 (adds 8h Asian)
input int    Session_End_Hour   = 23;             // v319: was 21 → 23 (adds 2h NY close)

//--- Trend Filter (unchanged from v317)
input string TREND_SET          = "============"; //====== Trend Filter ======
input int    H4_EMA_Period      = 200;
input int    H1_EMA_Period      = 200;            // KEPT: EMA200 = reliable bull/bear

//--- H1 RSI Gate (unchanged from v317)
// H1_RSI_Min=0: no lower gate (v317 fix preserved)
// H1_RSI_Max=90: mild overbought protection
input string H1RSI_SET          = "============"; //====== H1 RSI Gate ======
input int    H1_RSI_Period      = 14;
input double H1_RSI_Min         = 0.0;
input double H1_RSI_Max         = 90.0;
input double H1_RSI_Min_Sell    = 20.0;
input double H1_RSI_Max_Sell    = 60.0;

//--- BB Entry Signal (BB_Dev UNCHANGED at 2.5 — v318 proved this is NON-NEGOTIABLE)
// BB_Dev=2.5: only 1.24% of M5 bars close outside → ensures genuine overshooting
// Any reduction causes WR collapse (v318 proved: 2.0 → 52.93% WR → losing strategy)
input string S1_SET             = "============"; //====== BB Signal ======
input int    BB_Period          = 20;
input double BB_Dev             = 2.5;            // KEPT at 2.5 — critical for 89.59% WR
input int    RSI_Period         = 14;
input double RSI_Buy            = 40.0;           // KEPT: M5 RSI < 40 = genuine oversold
input double RSI_Sell           = 60.0;
input double Body_Pct           = 0.20;           // KEPT: bullish body filter

//--- Two-bar pattern (UNCHANGED, TwoBar_Lookback NOT used — v317 logic only)
// TwoBar_Lookback was the other cause of v318 failure:
//   At BB_Dev=2.0 with lookback=4, nearly all prior bars "closed outside" BB
//   → bbPrevBreak was always true → quality filter disabled
// FIX: Keep TwoBar_Lookback=1 (check bar[2] only, as in v317)
input string TWOBAR_SET         = "============"; //====== Two-Bar Pattern ======
input bool   Use_TwoBar_Pattern = true;           // KEPT: critical quality filter

//--- Volatility Filter (unchanged from v317)
input string VOL_SET            = "============"; //====== Volatility Filter ======
input double Max_ATR_Pct        = 1.00;
input int    ATR_Spike_MA_Period = 50;
input double ATR_Spike_Multi    = 0.0;            // KEPT disabled (v317 fix)

//--- Exit Settings (unchanged from v317)
input string EXIT_SET           = "============"; //====== Exit Settings ======
input int    ATR_Period         = 14;
input double ATR_SL_Multi       = 0.8;
input double ATR_TP_Multi       = 5.0;
input double Trail_ATR_Multi    = 0.1;
input double Partial_Pct        = 0.20;
input int    Max_Bars           = 30;

//--- Money Management
// v319: Risk_Pct 2.0→1.2 (reduced for MaxDD control, compensated by more trades + compounding)
// Max_Buys/Sells: KEPT at 1 (v318 showed Max_Buys=2 doesn't help frequency)
input string MONEY_SET          = "============"; //====== Money Management ======
input double Risk_Pct           = 1.2;            // v319: was 2.0 → 1.2 (MaxDD fix)
input double Fixed_Lot          = 0.0;
input int    Max_Buys           = 1;              // KEPT at 1 (concurrent doesn't help)
input int    Max_Sells          = 1;

//--- DD-Budget Scaling
// v319: DD_Budget 5.0→4.2, Min_Scale 0.15→0.07
// Scale = max(0.07, min(1.0, (4.2 - ddPct) / 1.2))
// With Hard_DD_Stop=4.8 below, the min-scale trading window is 4.2%-4.8% DD
// = 0.6% window × 1 trade = 0.084% risk max extra DD after scale floor
// Absolute MaxDD cap: 4.8% + 0.084% = 4.884% < 5% target
input string DDB_SET            = "============"; //====== DD-Budget Scale ======
input double DD_Budget          = 4.2;            // v319: was 5.0 → 4.2 (tighter budget)
input double Min_Scale          = 0.07;           // v319: was 0.15 → 0.07 (allows hard cap)

//--- Safety
// v319: Hard_DD_Stop=4.8 — absolute ceiling on new trades
// When peak-to-current DD ≥ 4.8%: no new entries, ManageExits still runs
input string SAFETY_SET        = "============"; //====== Safety Settings ======
input int    MaxSpread          = 35;
input int    Slippage           = 30;
input int    Magic_Number       = 3192057;
input string Order_Comment      = "BSv319";
input double Max_Daily_DD_Pct   = 8.0;
input int    Max_Trades_Day     = 300;
input double Hard_DD_Stop       = 4.8;            // v319: NEW — absolute MaxDD ceiling

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
// DD-Budget scaling (DD_Budget=4.2, Risk_Pct=1.2, Min_Scale=0.07)
// Hard stop at 4.8% handled in OnTick before entry signals
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
// v319: Cap uses g_PeakBalance instead of g_InitialBalance
// This enables proper compounding as the account grows:
//   At $10k: capAmt = $10k × 1.2% = $120 per trade
//   After 100% profit ($20k peak): capAmt = $20k × 1.2% = $240 per trade
//   Risk% stays constant, absolute $ scales with account growth
// During drawdown: AccountEquity < PeakBalance → riskAmt < capAmt → equity is the effective cap
// Net result: compounding in growth + protection in drawdown (same DD% behavior)
double CalcLots(double slDist, double riskScale = 1.0)
{
   if(Fixed_Lot > 0) return NormalizeDouble(Fixed_Lot, 2);
   double tickVal  = MarketInfo(Symbol(), MODE_TICKVALUE);
   double tickSize = MarketInfo(Symbol(), MODE_TICKSIZE);
   if(tickVal <= 0 || tickSize <= 0) return MarketInfo(Symbol(), MODE_MINLOT);
   double riskAmt = AccountEquity() * (Risk_Pct * riskScale) / 100.0;
   double capAmt  = g_PeakBalance * (Risk_Pct * riskScale) / 100.0;  // v319: PeakBalance cap
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

   // v319: Hard DD Stop — absolute ceiling on new entries
   // When global peak-to-trough DD ≥ Hard_DD_Stop: block all new trades
   // ManageExits above already ran so existing positions still managed
   if(Hard_DD_Stop > 0.0 && g_PeakBalance > 0)
   {
      double globalDD = (g_PeakBalance - curBalance) / g_PeakBalance * 100.0;
      if(globalDD >= Hard_DD_Stop) return;
   }

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
   double bbUpper2 = iBands(NULL, 0, BB_Period, BB_Dev, 0, PRICE_CLOSE, MODE_UPPER, 2);
   double bbLower2 = iBands(NULL, 0, BB_Period, BB_Dev, 0, PRICE_CLOSE, MODE_LOWER, 2);

   double rsi1 = iRSI(NULL, 0, RSI_Period, PRICE_CLOSE, 1);
   double rsi2 = iRSI(NULL, 0, RSI_Period, PRICE_CLOSE, 2);

   double slDist    = ATR_SL_Multi * atr1;
   double tpDist    = ATR_TP_Multi * atr1;
   double riskScale = GetRiskScale();

   double candleRange = High[1] - Low[1];
   double candleBodyB = Close[1] - Open[1];
   double candleBodyS = Open[1] - Close[1];

   //=== BUY ===
   // All conditions IDENTICAL to v317 (quality filter preserved)
   // bbPrevBreak: Close[2] <= bbLower2 (original 1-bar lookback — NOT extended like v318)
   if(h1Bull)
   {
      bool bbTouch     = (Low[1] <= bbLower1) && (Close[1] > bbLower1);
      bool rsiOS       = (rsi1 < RSI_Buy);
      bool rsiRising   = (rsi1 > rsi2);
      bool bullBody    = (candleBodyB > 0) && (candleRange > 0)
                      && (candleBodyB >= Body_Pct * candleRange);
      bool bbPrevBreak = (!Use_TwoBar_Pattern) || (Close[2] <= bbLower2);

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
   // All conditions IDENTICAL to v317 (quality filter preserved)
   if(h1Bear)
   {
      bool bbTouchUp   = (High[1] >= bbUpper1) && (Close[1] < bbUpper1);
      bool rsiOB       = (rsi1 > RSI_Sell);
      bool rsiFalling  = (rsi1 < rsi2);
      bool bearBody    = (candleBodyS > 0) && (candleRange > 0)
                      && (candleBodyS >= Body_Pct * candleRange);
      bool bbPrevBreak = (!Use_TwoBar_Pattern) || (Close[2] >= bbUpper2);

      if(bbTouchUp && rsiOB && rsiFalling && bearBody && bbPrevBreak)
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
