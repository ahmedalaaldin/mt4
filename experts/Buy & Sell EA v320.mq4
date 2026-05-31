//+------------------------------------------------------------------+
//|   Buy & Sell EA v320 - Hard_DD_Stop Fix + Sell Session Filter    |
//|   BASE: v319 — Fix Hard_DD_Stop bug, tune risk, filter sells     |
//|                                                                   |
//|   v319 POST-MORTEM (159 trades, +11.85%, MaxDD=5.33%):          |
//|     FAILURE: Only 159 trades (expected 900+)                     |
//|     ROOT CAUSE: Hard_DD_Stop=4.8% triggered after ~40 trades    |
//|       Once triggered, NO new entries allowed                      |
//|       Account can't recover through profitable trades (blocked)  |
//|       EA went silent for remaining ~10 months of the year        |
//|     SECONDARY ISSUE: Short WR = 54.55% (down from 83.10% v317)  |
//|       v317 session 9-21: Short WR = 83.10% (London/NY = good)   |
//|       v319 session 1-23: Short WR = 54.55% (Asian hrs = noisy)  |
//|       Asian hours (01-09) produce low-quality SELL signals       |
//|     MaxDD = 5.33% (exceeded 5% target by 0.33%)                 |
//|                                                                   |
//|   CONFIRMED NON-NEGOTIABLES (from v318 failure + v319 data):    |
//|     BB_Dev=2.5, TwoBar_Lookback=1 (Close[2] only)               |
//|     H1_EMA_Period=200, H1_RSI_Min=0, ATR_Spike_Multi=0          |
//|     RSI_Buy=40, Body_Pct=0.20                                    |
//|                                                                   |
//|   v320 CHANGES (5 changes from v319):                           |
//|     CHANGE 1: Hard_DD_Stop 4.8 → 0 (DISABLED)                  |
//|       Hard_DD_Stop is self-defeating: it prevents recovery       |
//|       Once triggered, profitable trading (which would recover DD)|
//|       is blocked → account stays in drawdown forever             |
//|       Replaced by: DD_Budget scaling alone + tighter Risk_Pct   |
//|     CHANGE 2: Risk_Pct 1.2 → 0.9 (MaxDD control via sizing)    |
//|       Empirical ratio from v317: MaxDD ≈ 4.66 × Risk_Pct       |
//|       At Risk_Pct=0.9: expected MaxDD ≈ 4.19% < 5% ✓           |
//|       Organic control (no hard stop needed)                      |
//|     CHANGE 3: DD_Budget 4.2 → 3.5 (earlier scale ramp)         |
//|       Scale starts cutting at DD > (3.5 - 0.9) = 2.6%          |
//|       vs v319 which only cut at DD > 3.0%                       |
//|       Faster reduction → less DD accumulation in losing runs     |
//|     CHANGE 4: Min_Scale 0.07 → 0.05 (smaller floor)            |
//|       At DD=3.5%: risk = 0.05 × 0.9% = 0.045% per trade        |
//|       Even 20 consecutive min-scale losses = 0.9% more DD       |
//|       Total max DD = 3.5% + 0.9% = 4.4% (theoretical)          |
//|     CHANGE 5: Add Sell_Session filter (9-21 only for sells)     |
//|       Buys: Session 1-23 (extended, Asian longs are fine: 90%+) |
//|       Sells: Session 9-21 (London/NY only, proven: 83%+ WR)     |
//|       Prevents bad Asian-hour sell signals (54.55% WR in v319)  |
//|                                                                   |
//|   MaxDD MATH (no hard stop, organic scaling only):              |
//|     Scale = max(0.05, min(1.0, (3.5 - ddPct) / 0.9))           |
//|     dd=0%:   scale=1.0 → 0.9%/trade                             |
//|     dd=2.6%: scale=1.0 → 0.9%/trade (full risk until here)     |
//|     dd=3.0%: scale=0.56 → 0.5%/trade                           |
//|     dd=3.5%: scale=0 → min0.05 → 0.045%/trade                  |
//|     After that: near-zero risk trades can't move DD much         |
//|     Theoretical max DD ≈ 3.5% + (WCL×0.045%) ≈ 4.0-4.5%       |
//|                                                                   |
//|   EXPECTED RESULTS:                                              |
//|     Trades: ~900-1400/year (1-23 buy session, no hard stop)     |
//|     WR: 87-91% (quality unchanged, bad sells filtered out)      |
//|     Return: ~40-80% (less risk per trade, more trades)          |
//|     MaxDD: ~3.5-4.5% (organic scaling, no hard stop needed)     |
//|                                                                   |
//|   SCOREBOARD:                                                    |
//|     v300: 258% return, 12.4% MaxDD, 1040 trades (3.9/day)      |
//|     v317: +76%, 9.32% MaxDD, 759 trades (2.9/day), WR=89.59%   |
//|     v318: -11%, 13.42% MaxDD, 903 trades — WR collapse (DEAD)  |
//|     v319: +12%, 5.33% MaxDD, 159 trades — Hard_DD_Stop killed  |
//|     v320: This version — Fix Hard_DD_Stop, filter Asian sells    |
//+------------------------------------------------------------------+
#property copyright ""
#property link      ""
#property version   "320.0"
#property strict

#include <stdlib.mqh>

//--- Session
// v319: Extended buy session to 1-23, v320 adds SELL session filter
// BUY  session 1-23: Asian longs have ~90%+ WR (quality filter intact)
// SELL session 9-21: London/NY only (proven 83%+ sell WR in v317)
input string SESSION_SET           = "============"; //====== Session Settings ======
input int    Session_Start_Hour    = 1;              // BUY start: 1AM (Asian open)
input int    Session_End_Hour      = 23;             // BUY end: 11PM
input int    Sell_Session_Start    = 9;              // v320: SELL restricted to 9AM
input int    Sell_Session_End      = 21;             // v320: SELL restricted to 9PM

//--- Trend Filter (unchanged from v317)
input string TREND_SET             = "============"; //====== Trend Filter ======
input int    H4_EMA_Period         = 200;
input int    H1_EMA_Period         = 200;            // KEPT: EMA200 = reliable

//--- H1 RSI Gate (unchanged from v317)
input string H1RSI_SET             = "============"; //====== H1 RSI Gate ======
input int    H1_RSI_Period         = 14;
input double H1_RSI_Min            = 0.0;            // No lower gate (v317 fix)
input double H1_RSI_Max            = 90.0;
input double H1_RSI_Min_Sell       = 20.0;
input double H1_RSI_Max_Sell       = 60.0;

//--- BB Entry Signal (BB_Dev NON-NEGOTIABLE at 2.5)
input string S1_SET                = "============"; //====== BB Signal ======
input int    BB_Period             = 20;
input double BB_Dev                = 2.5;            // LOCKED — any change = WR collapse
input int    RSI_Period            = 14;
input double RSI_Buy               = 40.0;
input double RSI_Sell              = 60.0;
input double Body_Pct              = 0.20;

//--- Two-bar pattern (unchanged, lookback=1 only)
input string TWOBAR_SET           = "============"; //====== Two-Bar Pattern ======
input bool   Use_TwoBar_Pattern   = true;            // LOCKED — critical quality filter

//--- Volatility Filter (unchanged from v317)
input string VOL_SET              = "============"; //====== Volatility Filter ======
input double Max_ATR_Pct          = 1.00;
input int    ATR_Spike_MA_Period  = 50;
input double ATR_Spike_Multi      = 0.0;             // Disabled (v317 fix)

//--- Exit Settings (unchanged from v317)
input string EXIT_SET             = "============"; //====== Exit Settings ======
input int    ATR_Period           = 14;
input double ATR_SL_Multi         = 0.8;
input double ATR_TP_Multi         = 5.0;
input double Trail_ATR_Multi      = 0.1;
input double Partial_Pct          = 0.20;
input int    Max_Bars             = 30;

//--- Money Management
// v320: Risk_Pct 1.2→0.9 (organic MaxDD control via sizing, no hard stop needed)
// Empirical: MaxDD ≈ 4.66 × Risk_Pct → 0.9% × 4.66 = 4.19% expected MaxDD
input string MONEY_SET            = "============"; //====== Money Management ======
input double Risk_Pct             = 0.9;             // v320: 1.2→0.9 (MaxDD fix)
input double Fixed_Lot            = 0.0;
input int    Max_Buys             = 1;
input int    Max_Sells            = 1;

//--- DD-Budget Scaling
// v320: DD_Budget 4.2→3.5, Min_Scale 0.07→0.05
// Scale ramp starts earlier (at DD > 2.6% vs v319's 3.0%)
// Faster risk reduction in losing runs → less DD accumulation
input string DDB_SET              = "============"; //====== DD-Budget Scale ======
input double DD_Budget            = 3.5;             // v320: 4.2→3.5 (earlier ramp)
input double Min_Scale            = 0.05;            // v320: 0.07→0.05 (smaller floor)

//--- Safety
// v320: Hard_DD_Stop DISABLED (0) — was self-defeating in v319
// Organic scaling (DD_Budget + Risk_Pct) provides sufficient protection
input string SAFETY_SET           = "============"; //====== Safety Settings ======
input int    MaxSpread             = 35;
input int    Slippage              = 30;
input int    Magic_Number          = 3202057;
input string Order_Comment         = "BSv320";
input double Max_Daily_DD_Pct      = 8.0;
input int    Max_Trades_Day        = 300;
input double Hard_DD_Stop          = 0.0;            // v320: DISABLED (was 4.8, killed trades)

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
// DD-Budget scaling: organic MaxDD control without hard stop
// Scale starts reducing when DD > DD_Budget - Risk_Pct = 2.6%
// Reaches Min_Scale at DD = DD_Budget = 3.5%
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
// Peak-balance compounding: risk scales with growing account
// Enables geometric growth while maintaining % drawdown protection
double CalcLots(double slDist, double riskScale = 1.0)
{
   if(Fixed_Lot > 0) return NormalizeDouble(Fixed_Lot, 2);
   double tickVal  = MarketInfo(Symbol(), MODE_TICKVALUE);
   double tickSize = MarketInfo(Symbol(), MODE_TICKSIZE);
   if(tickVal <= 0 || tickSize <= 0) return MarketInfo(Symbol(), MODE_MINLOT);
   double riskAmt = AccountEquity() * (Risk_Pct * riskScale) / 100.0;
   double capAmt  = g_PeakBalance * (Risk_Pct * riskScale) / 100.0;
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

   // v320: Hard_DD_Stop disabled (set to 0) — was self-defeating in v319
   // MaxDD controlled organically through DD_Budget scaling + reduced Risk_Pct
   if(Hard_DD_Stop > 0.0 && g_PeakBalance > 0)
   {
      double globalDD = (g_PeakBalance - curBalance) / g_PeakBalance * 100.0;
      if(globalDD >= Hard_DD_Stop) return;
   }

   bool inBuySession  = (dt.hour >= Session_Start_Hour  && dt.hour < Session_End_Hour);
   bool inSellSession = (dt.hour >= Sell_Session_Start   && dt.hour < Sell_Session_End);

   if(!inBuySession && !inSellSession) return;
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

   //=== BUY === (session 1-23, Asian + London + NY)
   // Quality filters IDENTICAL to v317 (non-negotiable)
   if(inBuySession && h1Bull)
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

   //=== SELL === (session 9-21 only — v320: filtered to London/NY proven hours)
   // Asian hours (1-9) produced 54.55% WR in v319 — below 83% threshold
   // v317 (9-21 only): Short WR = 83.10% — above threshold, profitable
   if(inSellSession && h1Bear)
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
