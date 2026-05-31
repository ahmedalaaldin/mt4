//+------------------------------------------------------------------+
//|   Buy & Sell EA v316 - High-Frequency BB Mean-Reversion          |
//|   BASE: v315 + fundamental overhaul to reach 20+ trades/day      |
//|   ROOT CAUSE ANALYSIS (v315: +1.95% return, 9.13% MaxDD, 196 t) |
//|     1) H1_RSI_Min=40 BLOCKS dip buys: when M5 oversold,          |
//|        H1 RSI is ALSO falling <40 → h1Bull = false at exactly    |
//|        the best dip-buy moments. Classic "wrong filter" problem.  |
//|     2) ATR_Spike_Multi=1.8 still blocking volatile sessions        |
//|     3) Two-bar pattern + BB_Dev=2.5 + rsiOS + bullBody together  |
//|        are ALL required → their joint probability is near zero    |
//|     4) Risk_Pct=4.5% too high: one SL = 4.5% DD = 90% of budget |
//|   v316 CHANGES:                                                   |
//|     FIX 1: Remove H1 RSI gate from h1Bull — just use EMA trend   |
//|             h1Bull = H1 close > H1 EMA50 (no RSI gate)            |
//|             h1Bear = H1 close < H1 EMA50 (no RSI gate)            |
//|     FIX 2: Remove Max_ATR_Pct and ATR_Spike_Multi filters        |
//|     FIX 3: Remove two-bar pattern (Use_TwoBar_Pattern=false)     |
//|             Remove bullBody/bearBody requirements                  |
//|             Remove rsiOS/rsiOB (too restrictive + redundant with  |
//|             BBTouch which already confirms oversold/overbought)    |
//|     FIX 4: Risk_Pct = 2.0% (was 4.5%)                           |
//|             Min_Scale = 0.15 (was 0.01) — no more scale crash     |
//|     FIX 5: BB_Dev 2.5→2.0 (more frequent BB touches)             |
//|     FIX 6: Session 7-22 (was 9-21, +5 more trading hours)        |
//|     FIX 7: Max_Buys=2, Max_Sells=2 (was 1,1) — 2x capacity       |
//|     FIX 8: H1_EMA_Period 200→50 (more sell opportunities via      |
//|             shorter EMA that oscillates, enabling h1Bear in bulls) |
//|   EXPECTED: ~2000-4000 trades/year (8-16/day), Return>200%       |
//|             MaxDD<5% via 2.0% Risk_Pct + halt at 1.5x budget     |
//|   SCOREBOARD:                                                     |
//|     v300: Calmar=20.84 (M5 baseline, 1040 trades, 258% return)   |
//|     v315: Return=+1.95%, MaxDD=9.13%, 196 trades (dead end)      |
//|     v316: This version — MAJOR overhaul                           |
//+------------------------------------------------------------------+
#property copyright ""
#property link      ""
#property version   "316.0"
#property strict

#include <stdlib.mqh>

//--- Session
input string SESSION_SET        = "============"; //====== Session Settings ======
input int    Session_Start_Hour = 7;              // v316: 9→7 (+2 hours pre-London)
input int    Session_End_Hour   = 22;             // v316: 21→22 (+1 hour post-NY)

//--- Trend Filter
// v316: H1_EMA_Period 200→50 so h1Bear fires during H1 corrections
// With EMA200, in a year-long gold bull run h1Bear was almost never true → no sells
// With EMA50, short-term corrections bring H1 close below EMA50 regularly → sells fire
input string TREND_SET          = "============"; //====== Trend Filter ======
input int    H1_EMA_Period      = 50;             // v316: was 200 → more sell signals

//--- BB Entry Signal
// v316: BB_Dev 2.5→2.0 (more frequent touches), body/RSI conditions removed
input string S1_SET             = "============"; //====== BB Signal ======
input int    BB_Period          = 20;
input double BB_Dev             = 2.0;            // v316: was 2.5 → more signal frequency
input int    RSI_Period         = 14;

//--- Two-bar pattern: DISABLED in v316
// v315 with two-bar + BB_Dev=2.5 + rsiOS + bullBody = near-zero joint probability
// → 196 trades/year. Removing two-bar recovers v300-level trade count.
input string TWOBAR_SET         = "============"; //====== Two-Bar Pattern ======
input bool   Use_TwoBar_Pattern = false;          // v316: was true → DISABLED

//--- Volatility Filter: DISABLED in v316
// ATR_Spike_Multi=1.8 was blocking volatile gold sessions
// Max_ATR_Pct removed in v315 but ATR_Spike_Multi was still active
input string VOL_SET            = "============"; //====== Volatility Filter ======
input int    ATR_Spike_MA_Period = 50;
input double ATR_Spike_Multi    = 0.0;            // v316: was 1.8 → DISABLED (set 0)

//--- Exit Settings (identical to v300/v315)
input string EXIT_SET           = "============"; //====== Exit Settings ======
input int    ATR_Period         = 14;
input double ATR_SL_Multi       = 0.8;
input double ATR_TP_Multi       = 5.0;
input double Trail_ATR_Multi    = 0.1;
input double Partial_Pct        = 0.20;
input int    Max_Bars           = 30;

//--- Money Management
// v316: Risk_Pct 4.5→2.0 (critical fix: one SL was 4.5% DD ≈ entire budget)
// With 2.0%: first loss = 2.0% DD → scale = (5-2)/2 = 1.5 → capped to 1.0 still full risk
// Second loss: balance down 2%+2%=4% → scale = (5-4)/2 = 0.5 → 50% risk
// Third loss: balance down 2%+2%+1%=5% → scale = (5-5)/2 = 0 → Min_Scale=0.15 → 0.3% risk/trade
// Recovery from Min_Scale is much faster with 0.15 vs 0.01
input string MONEY_SET          = "============"; //====== Money Management ======
input double Risk_Pct           = 2.0;            // v316: was 4.5 → safer per-trade DD
input double Fixed_Lot          = 0.0;
input int    Max_Buys           = 2;              // v316: was 1 → double capacity
input int    Max_Sells          = 2;              // v316: was 1 → double capacity

//--- DD-Budget Scaling
input string DDB_SET            = "============"; //====== DD-Budget Scale ======
input double DD_Budget          = 5.0;            // % DD budget (balance basis)
input double Min_Scale          = 0.15;           // v316: was 0.01 → never crash scale
// Emergency halt: if DD exceeds 1.5x budget, close all trades and halt for the day
input double DD_Emergency_Mult  = 1.5;            // v316: new — halt at 7.5% DD

//--- Safety
input string SAFETY_SET        = "============"; //====== Safety Settings ======
input int    MaxSpread          = 35;
input int    Slippage           = 30;
input int    Magic_Number       = 3162057;
input string Order_Comment      = "BSv316";
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
// Balance-based DD scaling (v315 fix preserved)
// v316: Min_Scale raised 0.01→0.15 so partial-close math still works
//   at minimum scale. Previously 0.01 scale → near-zero lots → partial
//   close rounded to 0 → WR collapsed to 46% (v314/v315 pattern).
// v316: 0.15 scale → 15% of full lots → partial close still viable.
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

   // Daily DD check (uses balance to avoid equity-inflate false trigger)
   if(!g_DailyDDHit && g_DayOpenEquity > 0)
   {
      double ddPct = (g_DayOpenEquity - curBalance) / g_DayOpenEquity * 100.0;
      if(ddPct >= Max_Daily_DD_Pct) { CloseAllTrades(); g_DailyDDHit = true; return; }
   }
   if(g_DailyDDHit) return;

   // v316 Emergency halt: if balance DD from peak > DD_Budget * Emergency_Mult
   // (e.g., >7.5% at default 5.0×1.5), close all and halt for today
   if(DD_Emergency_Mult > 0 && g_PeakBalance > 0)
   {
      double emergDD = (g_PeakBalance - curBalance) / g_PeakBalance * 100.0;
      if(emergDD >= DD_Budget * DD_Emergency_Mult)
      {
         CloseAllTrades();
         g_DailyDDHit = true;
         return;
      }
   }

   ManageExits();
   if(!isNewBar) return;

   bool inSession = (dt.hour >= Session_Start_Hour && dt.hour < Session_End_Hour);
   if(!inSession) return;
   if(MarketInfo(Symbol(), MODE_SPREAD) > MaxSpread) return;
   if(g_TradesToday >= Max_Trades_Day) return;

   // v316: H1 trend filter uses EMA50 only — NO RSI gate
   // EMA50 oscillates more than EMA200, enabling h1Bear during H1 corrections
   // even in a year-long gold bull run → more sell entries
   double h1_ema  = iMA(NULL, PERIOD_H1, H1_EMA_Period, 0, MODE_EMA, PRICE_CLOSE, 0);

   // v316: No H1 RSI gate for buys or sells — just trend direction
   bool h1Bull = (iClose(NULL, PERIOD_H1, 1) > h1_ema);
   bool h1Bear = (iClose(NULL, PERIOD_H1, 1) < h1_ema);

   double atr1 = iATR(NULL, 0, ATR_Period, 1);
   if(atr1 <= 0) return;

   // v316: ATR_Spike_Multi=0 → disabled (was 1.8, blocked volatile gold sessions)
   if(ATR_Spike_Multi > 0)
   {
      double atr_slow = iATR(NULL, 0, ATR_Spike_MA_Period, 1);
      if(atr_slow > 0 && atr1 > ATR_Spike_Multi * atr_slow) return;
   }

   // BB values (uses BB_Dev=2.0 vs v315's 2.5 → more frequent touches)
   double bbUpper1 = iBands(NULL, 0, BB_Period, BB_Dev, 0, PRICE_CLOSE, MODE_UPPER, 1);
   double bbLower1 = iBands(NULL, 0, BB_Period, BB_Dev, 0, PRICE_CLOSE, MODE_LOWER, 1);
   double bbUpper2 = iBands(NULL, 0, BB_Period, BB_Dev, 0, PRICE_CLOSE, MODE_UPPER, 2);
   double bbLower2 = iBands(NULL, 0, BB_Period, BB_Dev, 0, PRICE_CLOSE, MODE_LOWER, 2);

   double rsi1 = iRSI(NULL, 0, RSI_Period, PRICE_CLOSE, 1);
   double rsi2 = iRSI(NULL, 0, RSI_Period, PRICE_CLOSE, 2);

   double slDist    = ATR_SL_Multi * atr1;
   double tpDist    = ATR_TP_Multi * atr1;
   double riskScale = GetRiskScale();

   //=== BUY ===
   // v316: Simplified entry — removed rsiOS, bullBody (too selective, reduced WR via over-filter)
   // Keep: h1Bull (H1 uptrend) + bbTouch (price at/below lower BB then recovered inside)
   //       + rsiRising (momentum recovery confirmation)
   //       + bbPrevBreak if Use_TwoBar_Pattern=true (disabled by default in v316)
   if(h1Bull)
   {
      bool bbTouch     = (Low[1] <= bbLower1) && (Close[1] > bbLower1);
      bool rsiRising   = (rsi1 > rsi2);
      bool bbPrevBreak = (!Use_TwoBar_Pattern) || (Close[2] <= bbLower2);

      if(bbTouch && rsiRising && bbPrevBreak)
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
   // v316: Simplified entry — removed rsiOB, bearBody
   // Keep: h1Bear (H1 downtrend/correction) + bbTouchUp (price at/above upper BB then recovered)
   //       + rsiFalling (momentum reversal confirmation)
   //       + bbPrevBreak if Use_TwoBar_Pattern=true (disabled by default)
   if(h1Bear)
   {
      bool bbTouchUp   = (High[1] >= bbUpper1) && (Close[1] < bbUpper1);
      bool rsiFalling  = (rsi1 < rsi2);
      bool bbPrevBreak = (!Use_TwoBar_Pattern) || (Close[2] >= bbUpper2);

      if(bbTouchUp && rsiFalling && bbPrevBreak)
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
