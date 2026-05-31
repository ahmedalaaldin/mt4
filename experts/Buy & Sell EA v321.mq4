//+------------------------------------------------------------------+
//|   Buy & Sell EA v321 - Session Correction + Organic MaxDD Fix    |
//|   BASE: v317 + v319 improvements — clean version, no hard stop   |
//|                                                                   |
//|   v320 POST-MORTEM (447 trades, +20.00%, MaxDD=5.27%):          |
//|     FAILURE: Long WR collapsed 91.09% → 75.00%                  |
//|     ROOT CAUSE: Asian session (01-09) buys have poor quality     |
//|       XAUUSD 01-09: low volatility, choppy, mean-reversion fails |
//|       BB_Dev=2.5 touches are less reliable in low-volume hours   |
//|       Result: 392 longs at 75% WR vs v317's 91% WR              |
//|     SECONDARY ISSUE: MaxDD = 5.27% (still above 5% target)      |
//|     Also: Short WR still 56.36% (unchanged — sell logic OK in    |
//|       9-21 window, bad shorts are rare in that window)           |
//|                                                                   |
//|   CONFIRMED SESSION DATA:                                        |
//|     v317 (9-21 London/NY): Long WR=91.09%, Short WR=83.10%      |
//|     v319 (1-23, but Hard_DD killed early): Long WR=90.51%        |
//|     v320 (1-23 buys, 9-21 sells): Long WR=75.00% ← CONFIRMED BAD|
//|     CONCLUSION: Session 9-21 is the ONLY proven window          |
//|                                                                   |
//|   CONFIRMED NON-NEGOTIABLES (locked from v317+v318 analysis):   |
//|     BB_Dev=2.5, TwoBar_Lookback=1 (Close[2] only)               |
//|     Session=9-21 (proven London/NY quality)                      |
//|     H1_EMA_Period=200, H1_RSI_Min=0, ATR_Spike_Multi=0          |
//|     RSI_Buy=40, Body_Pct=0.20                                    |
//|                                                                   |
//|   v321 CHANGES from v317 (3 changes):                           |
//|     CHANGE 1: Risk_Pct 2.0 → 1.0 (MaxDD control, organic)       |
//|       Empirical ratio: MaxDD ≈ 4.66 × Risk_Pct (v317 data)     |
//|       At 1.0%: expected MaxDD ≈ 4.66% (under 5% target)         |
//|       Return trade-off: ~38% vs v317's 76% (half the risk)      |
//|       Compensated by peak-balance compounding (Change 3)         |
//|     CHANGE 2: DD_Budget 5.0 → 3.8, Min_Scale 0.15 → 0.04       |
//|       Scale starts cutting at DD > 2.8% (not v317's 3.0%)       |
//|       Faster risk reduction when losing → less DD accumulation   |
//|       No Hard_DD_Stop needed — organic scaling is sufficient     |
//|       Worst case: 3.8% + (5 × 0.04%) = 4.0% theoretical max    |
//|     CHANGE 3: CalcLots cap: InitialBalance → PeakBalance        |
//|       Peak-balance compounding from v319                         |
//|       Returns compound geometrically as account grows            |
//|                                                                   |
//|   MaxDD MATH (no hard stop, organic scaling):                   |
//|     Scale = max(0.04, min(1.0, (3.8 - ddPct) / 1.0))           |
//|     dd=0%:   scale=1.0 → 1.0%/trade                             |
//|     dd=2.8%: scale=1.0 → 1.0%/trade (full until here)          |
//|     dd=3.0%: scale=0.80 → 0.80%/trade                          |
//|     dd=3.5%: scale=0.30 → 0.30%/trade                          |
//|     dd=3.8%: scale=0 → min=0.04 → 0.04%/trade                  |
//|     Max extra DD after scaling: near-zero                        |
//|     Expected MaxDD: ~4.0-4.8% (safely under 5% target)          |
//|                                                                   |
//|   EXPECTED RESULTS:                                              |
//|     Trades: ~700-800/year (proven 9-21 session)                 |
//|     WR: 87-91% (quality unchanged, proven session)              |
//|     Return: ~35-45%+ (1.0% risk + peak compounding)             |
//|     MaxDD: <5% (organic scaling)                                 |
//|                                                                   |
//|   SCOREBOARD:                                                    |
//|     v300: 258% return, 12.4% MaxDD, 1040 trades (3.9/day)      |
//|     v317: +76%, 9.32% MaxDD, 759 trades (2.9/day), WR=89.59%   |
//|     v318: -11%, 13.42% MaxDD, 903 trades — WR collapse (DEAD)  |
//|     v319: +12%, 5.33% MaxDD, 159 trades — Hard_DD_Stop killed  |
//|     v320: +20%, 5.27% MaxDD, 447 trades — Asian session killed  |
//|     v321: This version — Clean fix, proven session, no hard stop |
//+------------------------------------------------------------------+
#property copyright ""
#property link      ""
#property version   "321.0"
#property strict

#include <stdlib.mqh>

//--- Session (LOCKED at 9-21 — proven London/NY quality)
// v317 confirmed: 9-21 gives Long WR=91%, Short WR=83%
// v320 proved: extending to 1-23 drops Long WR to 75% (Asian noise)
// SESSION IS NON-NEGOTIABLE — do not extend to Asian hours
input string SESSION_SET        = "============"; //====== Session Settings ======
input int    Session_Start_Hour = 9;              // LOCKED: London open
input int    Session_End_Hour   = 21;             // LOCKED: NY close

//--- Trend Filter (unchanged from v317)
input string TREND_SET          = "============"; //====== Trend Filter ======
input int    H4_EMA_Period      = 200;
input int    H1_EMA_Period      = 200;

//--- H1 RSI Gate (unchanged from v317)
input string H1RSI_SET          = "============"; //====== H1 RSI Gate ======
input int    H1_RSI_Period      = 14;
input double H1_RSI_Min         = 0.0;
input double H1_RSI_Max         = 90.0;
input double H1_RSI_Min_Sell    = 20.0;
input double H1_RSI_Max_Sell    = 60.0;

//--- BB Entry Signal (BB_Dev LOCKED at 2.5)
input string S1_SET             = "============"; //====== BB Signal ======
input int    BB_Period          = 20;
input double BB_Dev             = 2.5;            // LOCKED — critical for WR
input int    RSI_Period         = 14;
input double RSI_Buy            = 40.0;
input double RSI_Sell           = 60.0;
input double Body_Pct           = 0.20;

//--- Two-bar pattern (LOCKED at lookback=1)
input string TWOBAR_SET         = "============"; //====== Two-Bar Pattern ======
input bool   Use_TwoBar_Pattern = true;

//--- Volatility Filter (unchanged from v317)
input string VOL_SET            = "============"; //====== Volatility Filter ======
input double Max_ATR_Pct        = 1.00;
input int    ATR_Spike_MA_Period = 50;
input double ATR_Spike_Multi    = 0.0;

//--- Exit Settings (unchanged from v317)
input string EXIT_SET           = "============"; //====== Exit Settings ======
input int    ATR_Period         = 14;
input double ATR_SL_Multi       = 0.8;
input double ATR_TP_Multi       = 5.0;
input double Trail_ATR_Multi    = 0.1;
input double Partial_Pct        = 0.20;
input int    Max_Bars           = 30;

//--- Money Management
// v321: Risk_Pct 2.0→1.0 (organic MaxDD control)
// Empirical: MaxDD ≈ 4.66 × Risk_Pct → 1.0% × 4.66 = 4.66% expected
input string MONEY_SET          = "============"; //====== Money Management ======
input double Risk_Pct           = 1.0;            // v321: 2.0→1.0 (MaxDD control)
input double Fixed_Lot          = 0.0;
input int    Max_Buys           = 1;
input int    Max_Sells          = 1;

//--- DD-Budget Scaling
// v321: DD_Budget 5.0→3.8, Min_Scale 0.15→0.04
// Scale starts cutting at DD > 2.8% (DD_Budget - Risk_Pct = 3.8-1.0 = 2.8%)
// Reaches Min_Scale at DD = 3.8%
// Near-zero risk at DD ≥ 3.8% → theoretical max DD ≈ 4.0%
input string DDB_SET            = "============"; //====== DD-Budget Scale ======
input double DD_Budget          = 3.8;            // v321: 5.0→3.8
input double Min_Scale          = 0.04;           // v321: 0.15→0.04

//--- Safety (Hard_DD_Stop DISABLED — organic scaling is sufficient)
input string SAFETY_SET        = "============"; //====== Safety Settings ======
input int    MaxSpread          = 35;
input int    Slippage           = 30;
input int    Magic_Number       = 3212057;
input string Order_Comment      = "BSv321";
input double Max_Daily_DD_Pct   = 8.0;
input int    Max_Trades_Day     = 300;
input double Hard_DD_Stop       = 0.0;            // DISABLED — organic scaling sufficient

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
// Organic DD control: scale ramps from 1.0→0.04 as DD goes 2.8%→3.8%
// No hard stop needed — very small trades near and above 3.8% DD
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
// Peak-balance compounding: geometric growth as account grows
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

   // Hard_DD_Stop check (disabled at 0.0 — organic scaling handles MaxDD)
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
