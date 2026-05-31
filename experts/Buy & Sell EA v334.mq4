//+------------------------------------------------------------------+
//|   Buy & Sell EA v334 - BB_Period=14 faster band test            |
//|   BASE: v328 (best performing) + single change: BB_Period        |
//|                                                                   |
//|   v333 POST-MORTEM (543 trades, +8.08%, MaxDD=4.85%):           |
//|     ACHIEVEMENT: WR=85.45% — above 83% threshold ✓              |
//|     ACHIEVEMENT: MaxDD=4.85% — under 5% limit ✓                 |
//|     FAILURE: Return=+8.08% — far below v328's +16.25% ✗         |
//|     ROOT CAUSE: Wider SL(1.0*ATR) shrinks lots to 80% of v328  |
//|       TP=5*ATR fixed, SL=1.0*ATR → lots=0.8x → wins earn less  |
//|       Despite 543 trades, per-trade profit collapsed             |
//|     LESSON: ATR_SL_Multi=0.80 is the sweet spot for v328        |
//|       Narrower=too tight (v332), Wider=too few lots (v333)       |
//|                                                                   |
//|   TIMEFRAME EXPERIMENTS (v328 parameters on different TF):       |
//|     M1: WR=31.90%, -4.64%, 25% modelling quality — FAIL ✗       |
//|     M5: WR=83.47%, +16.25%, 90% quality — OPTIMAL ✓             |
//|     M15: WR=39.68%, -4.17%, 90% quality — FAIL ✗                |
//|     CONCLUSION: M5 is the ONLY viable timeframe for this pattern |
//|                                                                   |
//|   v334 HYPOTHESIS: Change BB_Period 20 → 14                      |
//|     Rationale: Faster BB (14-period vs 20-period)                |
//|       - BB(14) reacts more quickly to recent price action        |
//|       - Price crosses 2.5σ bands more frequently on BB(14)      |
//|       - Two-bar recovery pattern should occur more often         |
//|       - Hypothesis: +30-50% more signals, same WR quality        |
//|     All other parameters IDENTICAL to v328:                      |
//|       ATR_SL_Multi=0.80 (confirmed optimal)                      |
//|       Risk_Pct=0.85, DD_Budget=3.8 (confirmed optimal)           |
//|       Partial_Pct=0.20 (locked), Trail_ATR_Multi=0.5 (locked)   |
//|                                                                   |
//|   v334 SINGLE CHANGE from v328:                                  |
//|     CHANGE: BB_Period 20 → 14                                    |
//|       Faster Bollinger Band = more breakout/recovery signals     |
//|       All other parameters identical to v328                     |
//|                                                                   |
//|   SUCCESS CRITERIA:                                               |
//|     WR > 80% AND MaxDD < 5% AND Return > 16.25% → IMPROVE       |
//|     Any metric worse than v328 → analyse and move on             |
//|                                                                   |
//|   CONFIRMED NON-NEGOTIABLES:                                      |
//|     BB_Dev=2.5 ← LOCKED (v329 disproved 2.0)                    |
//|     Trail anchor=bbMid ← LOCKED (v330 proved Bid too tight)      |
//|     Trail_ATR_Multi=0.5 ← NON-NEGOTIABLE                        |
//|     Partial_Pct=0.20 ← LOCKED (v331 proved 0.40 hurts WR)       |
//|     ATR_SL_Multi=0.80 ← LOCKED (v332 0.65=fail, v333 1.0=fail)  |
//|     TwoBar_Lookback=1, Session=9-21 (unchanged)                  |
//|     Max_Sells=0, Body_Pct=0.20, Hard_DD_Stop=0.0               |
//|                                                                   |
//|   SCOREBOARD:                                                     |
//|     v328: +16%, 4.99% MaxDD, 380 trades — BEST BASELINE ✓       |
//|     v329: +2%, 6.06% MaxDD — BB_Dev=2.0 fail ✗                  |
//|     v330: +13%, 5.14% MaxDD — exit combo fail ✗                 |
//|     v331: +17%, 5.01% MaxDD, 364 trades — Partial=0.40 fail ✗   |
//|     v332: +10%, 5.45% MaxDD, 331 trades — SL=0.65 fail ✗        |
//|     v333: +8%, 4.85% MaxDD, 543 trades — SL=1.0 fail ✗          |
//|     v334: This version — BB_Period=14, all else=v328            |
//+------------------------------------------------------------------+
#property copyright ""
#property link      ""
#property version   "334.0"
#property strict

#include <stdlib.mqh>

//--- Session (LOCKED at 9-21)
input string SESSION_SET        = "============"; //====== Session Settings ======
input int    Session_Start_Hour = 9;
input int    Session_End_Hour   = 21;

//--- Trend Filter
input string TREND_SET          = "============"; //====== Trend Filter ======
input int    H4_EMA_Period      = 200;
input int    H1_EMA_Period      = 200;

//--- H1 RSI Gate
input string H1RSI_SET          = "============"; //====== H1 RSI Gate ======
input int    H1_RSI_Period      = 14;
input double H1_RSI_Min         = 0.0;
input double H1_RSI_Max         = 90.0;
input double H1_RSI_Min_Sell    = 20.0;
input double H1_RSI_Max_Sell    = 60.0;

//--- BB Entry Signal
// v334 SINGLE CHANGE: BB_Period 20 → 14
// Rationale: Faster BB reacts quicker → more 2.5σ breakout/recovery signals
// BB_Dev stays at 2.5 (NON-NEGOTIABLE), all other BB params unchanged
input string S1_SET             = "============"; //====== BB Signal ======
input int    BB_Period          = 14;             // v334: 20 → 14 (SINGLE CHANGE)
input double BB_Dev             = 2.5;            // NON-NEGOTIABLE
input int    RSI_Period         = 14;
input double RSI_Buy            = 45.0;
input double RSI_Sell           = 60.0;
input double Body_Pct           = 0.20;

//--- Two-bar pattern
input string TWOBAR_SET         = "============"; //====== Two-Bar Pattern ======
input bool   Use_TwoBar_Pattern = true;

//--- Volatility Filter
input string VOL_SET            = "============"; //====== Volatility Filter ======
input double Max_ATR_Pct        = 0.0;
input int    ATR_Spike_MA_Period = 50;
input double ATR_Spike_Multi    = 0.0;

//--- Exit Settings (identical to v328 — ATR_SL_Multi restored to 0.80)
input string EXIT_SET           = "============"; //====== Exit Settings ======
input int    ATR_Period         = 14;
input double ATR_SL_Multi       = 0.80;           // v328 value (restored from v333's 1.0)
input double ATR_TP_Multi       = 5.0;
input double Trail_ATR_Multi    = 0.5;            // NON-NEGOTIABLE
input double Partial_Pct        = 0.20;           // LOCKED: v328 value
input int    Max_Bars           = 30;

//--- Money Management (identical to v328)
input string MONEY_SET          = "============"; //====== Money Management ======
input double Risk_Pct           = 0.85;
input double Fixed_Lot          = 0.0;
input int    Max_Buys           = 1;
input int    Max_Sells          = 0;              // DISABLED (Max_Sells=0 NON-NEGOTIABLE)

//--- DD-Budget Scaling (identical to v328)
input string DDB_SET            = "============"; //====== DD-Budget Scale ======
input double DD_Budget          = 3.8;
input double Min_Scale          = 0.01;

//--- Safety
input string SAFETY_SET        = "============"; //====== Safety Settings ======
input int    MaxSpread          = 35;
input int    Slippage           = 30;
input int    Magic_Number       = 3342057;
input string Order_Comment      = "BSv334";
input double Max_Daily_DD_Pct   = 8.0;
input int    Max_Trades_Day     = 300;
input double Hard_DD_Stop       = 0.0;            // PERMANENTLY DISABLED

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
            // BB_mid-based trail — NON-NEGOTIABLE (identical to v328)
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

   //=== SELL (DISABLED) ===
   if(Max_Sells > 0 && h1Bear)
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
