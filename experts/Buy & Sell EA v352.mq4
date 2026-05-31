//+------------------------------------------------------------------+
//|   Buy & Sell EA v352 - H1_RSI_Max=70 (was 90)                    |
//|   BASE: v343 (M5+M15+M30, WR=85.14%, +30.67%, 814t) BEST ✓      |
//|                                                                   |
//|   SCOREBOARD (all M5 unless noted):                              |
//|     v328: +16.25%, MaxDD=4.99%, WR=83.47%, 380t   BEST M5 ✓    |
//|     v342: M5+M15 → +29.51%, MaxDD=4.74%, WR=86.90%, 756t ✓    |
//|     v343: M5+M15+M30 → +30.67%, MaxDD=4.87%, WR=85.14%, 814t ✓|
//|     v344: TwoBar=false → +9.18%, WR=75.88%        FAIL ✗       |
//|     v345: RSI_Buy=50 → +6.17%, WR=74.87%          FAIL ✗       |
//|     v346: Body_Pct=0.10 → +30.87%, MaxDD=5.37%❌  FAIL ✗       |
//|     v347: Max_Buys=2 → +16.30%, WR=82.40%, 750t   FAIL ✗       |
//|     v348: ATR_TP_Multi=8.0 → IDENTICAL to v343    NO EFFECT ✗  |
//|     v349: Risk_Pct=1.0% → +16.96%, MaxDD=5.01%❌  FAIL ✗       |
//|     v350: H1 signals → +30.42%, MaxDD=5.20%❌      FAIL ✗       |
//|     v351: Max_Bars=50 → +29.91%, MaxDD=4.89%       MARGINAL ✗  |
//|                                                                   |
//|   v352 HYPOTHESIS: H1_RSI_Max=70 (was 90).                      |
//|   When H1 RSI > 70, gold is overbought on the hourly chart.     |
//|   M5/M15/M30 long entries during H1-overbought conditions risk  |
//|   being caught by a larger H1-level correction. Filtering these  |
//|   out should improve WR at the cost of slightly fewer trades.   |
//|   In a bull market, H1 RSI > 70 occurs ~15-20% of session time. |
//|   If those blocked trades have below-average WR, net return     |
//|   should improve despite fewer total trades.                     |
//|                                                                   |
//|   v352 CHANGES from v343:                                        |
//|     H1_RSI_Max: 90.0 → 70.0 (block entries when H1 overbought) |
//|     Max_Bars: kept at 30 (reset from v351's 50, isolate change)  |
//|                                                                   |
//|   NON-NEGOTIABLES (ALL unchanged from v343):                     |
//|     BB_Dev=2.5, BB_Period=20, TwoBar_Lookback=1                  |
//|     Session=9-21, Max_Sells=0, ATR_SL_Multi=0.80                |
//|     Partial_Pct=0.20, Trail_ATR_Multi=0.5, Hard_DD_Stop=0.0     |
//|     RSI_Buy=45.0, RSI_Period=14, Body_Pct=0.20                   |
//|     Risk_Pct=0.85, DD_Budget=3.8                                 |
//+------------------------------------------------------------------+
#property copyright ""
#property link      ""
#property version   "352.0"
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
input double H1_RSI_Max         = 70.0;           // v352: tightened from 90→70 (block H1 overbought)
input double H1_RSI_Min_Sell    = 20.0;
input double H1_RSI_Max_Sell    = 60.0;

//--- BB Entry Signal
input string S1_SET             = "============"; //====== BB Signal ======
input int    BB_Period          = 20;
input double BB_Dev             = 2.5;            // NON-NEGOTIABLE (LOCKED)
input int    RSI_Period         = 14;             // CONFIRMED BEST
input double RSI_Buy            = 45.0;           // NON-NEGOTIABLE
input double RSI_Sell           = 60.0;
input double Body_Pct           = 0.20;           // NON-NEGOTIABLE

//--- Two-bar pattern
input string TWOBAR_SET         = "============"; //====== Two-Bar Pattern ======
input bool   Use_TwoBar_Pattern = true;           // NON-NEGOTIABLE

//--- Multi-Timeframe Settings
input string MTF_SET            = "============"; //====== Multi-TF Settings ======
input bool   Use_M15_Signals    = true;
input bool   Use_M30_Signals    = true;

//--- Volatility Filter
input string VOL_SET            = "============"; //====== Volatility Filter ======
input double Max_ATR_Pct        = 0.0;
input int    ATR_Spike_MA_Period = 50;
input double ATR_Spike_Multi    = 0.0;

//--- Exit Settings
input string EXIT_SET           = "============"; //====== Exit Settings ======
input int    ATR_Period         = 14;
input double ATR_SL_Multi       = 0.8;            // NON-NEGOTIABLE
input double ATR_TP_Multi       = 5.0;            // TP never hit; safety only
input double Trail_ATR_Multi    = 0.5;            // NON-NEGOTIABLE
input double Partial_Pct        = 0.20;           // NON-NEGOTIABLE
input int    Max_Bars           = 30;             // v352: reset to 30 (v343 baseline)

//--- Money Management
input string MONEY_SET          = "============"; //====== Money Management ======
input double Risk_Pct           = 0.85;           // NON-NEGOTIABLE
input double Fixed_Lot          = 0.0;
input int    Max_Buys           = 1;
input int    Max_Sells          = 0;              // NON-NEGOTIABLE (DISABLED)

//--- DD-Budget Scaling
input string DDB_SET            = "============"; //====== DD-Budget Scale ======
input double DD_Budget          = 3.8;
input double Min_Scale          = 0.01;

//--- Safety
input string SAFETY_SET        = "============"; //====== Safety Settings ======
input int    MaxSpread          = 35;
input int    Slippage           = 30;
input int    Magic_Number       = 3522057;        // v352 unique magic
input string Order_Comment      = "BSv352";
input double Max_Daily_DD_Pct   = 8.0;
input int    Max_Trades_Day     = 300;
input double Hard_DD_Stop       = 0.0;            // NON-NEGOTIABLE (DISABLED)

//+------------------------------------------------------------------+
double   g_DayOpenEquity  = 0;
bool     g_DailyDDHit     = false;
int      g_TradesToday    = 0;
datetime g_LastDay        = 0;
double   g_InitialBalance = 0;
double   g_PeakBalance    = 0;
datetime g_LastM15Bar     = 0;
datetime g_LastM30Bar     = 0;

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

   datetime m15BarTime = iTime(NULL, PERIOD_M15, 0);
   bool isNewM15Bar = (m15BarTime != g_LastM15Bar);
   if(isNewM15Bar) g_LastM15Bar = m15BarTime;

   datetime m30BarTime = iTime(NULL, PERIOD_M30, 0);
   bool isNewM30Bar = (m30BarTime != g_LastM30Bar);
   if(isNewM30Bar) g_LastM30Bar = m30BarTime;

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

   // h1Bull: price above H1-200EMA AND H1 RSI not overbought (≤70)
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

   //=== M5 BUY ===
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

   //=== M15 BUY ===
   if(Use_M15_Signals && isNewM15Bar && h1Bull)
   {
      double m15_bbLower1 = iBands(NULL, PERIOD_M15, BB_Period, BB_Dev, 0, PRICE_CLOSE, MODE_LOWER, 1);
      double m15_bbLower2 = iBands(NULL, PERIOD_M15, BB_Period, BB_Dev, 0, PRICE_CLOSE, MODE_LOWER, 2);
      double m15_rsi1     = iRSI(NULL, PERIOD_M15, RSI_Period, PRICE_CLOSE, 1);
      double m15_rsi2     = iRSI(NULL, PERIOD_M15, RSI_Period, PRICE_CLOSE, 2);

      double m15_high1  = iHigh(NULL, PERIOD_M15, 1);
      double m15_low1   = iLow(NULL, PERIOD_M15, 1);
      double m15_close1 = iClose(NULL, PERIOD_M15, 1);
      double m15_open1  = iOpen(NULL, PERIOD_M15, 1);
      double m15_close2 = iClose(NULL, PERIOD_M15, 2);

      double m15_range = m15_high1 - m15_low1;
      double m15_bodyB = m15_close1 - m15_open1;

      bool m15_bbTouch     = (m15_low1 <= m15_bbLower1) && (m15_close1 > m15_bbLower1);
      bool m15_rsiOS       = (m15_rsi1 < RSI_Buy);
      bool m15_rsiRising   = (m15_rsi1 > m15_rsi2);
      bool m15_bullBody    = (m15_bodyB > 0) && (m15_range > 0)
                          && (m15_bodyB >= Body_Pct * m15_range);
      bool m15_bbPrevBreak = (!Use_TwoBar_Pattern) || (m15_close2 <= m15_bbLower2);

      if(m15_bbTouch && m15_rsiOS && m15_rsiRising && m15_bullBody && m15_bbPrevBreak)
      {
         if(CountTradesByMagic(OP_BUY, Magic_Number) < Max_Buys)
         {
            double m15_atr = iATR(NULL, PERIOD_M15, ATR_Period, 1);
            if(m15_atr > 0)
            {
               double m15_slDist = ATR_SL_Multi * m15_atr;
               double m15_tpDist = ATR_TP_Multi * m15_atr;
               double m15_lots   = CalcLots(m15_slDist, riskScale);
               double entry      = NormalizeDouble(Ask, Digits);
               double sl         = NormalizeDouble(entry - m15_slDist, Digits);
               double tp         = NormalizeDouble(entry + m15_tpDist, Digits);
               if(m15_lots > 0)
               {
                  int tkt = OrderSend(Symbol(), OP_BUY, m15_lots, entry, Slippage,
                                      sl, tp, Order_Comment, Magic_Number, 0, clrLime);
                  if(tkt > 0) g_TradesToday++;
               }
            }
         }
      }
   }

   //=== M30 BUY ===
   if(Use_M30_Signals && isNewM30Bar && h1Bull)
   {
      double m30_bbLower1 = iBands(NULL, PERIOD_M30, BB_Period, BB_Dev, 0, PRICE_CLOSE, MODE_LOWER, 1);
      double m30_bbLower2 = iBands(NULL, PERIOD_M30, BB_Period, BB_Dev, 0, PRICE_CLOSE, MODE_LOWER, 2);
      double m30_rsi1     = iRSI(NULL, PERIOD_M30, RSI_Period, PRICE_CLOSE, 1);
      double m30_rsi2     = iRSI(NULL, PERIOD_M30, RSI_Period, PRICE_CLOSE, 2);

      double m30_high1  = iHigh(NULL, PERIOD_M30, 1);
      double m30_low1   = iLow(NULL, PERIOD_M30, 1);
      double m30_close1 = iClose(NULL, PERIOD_M30, 1);
      double m30_open1  = iOpen(NULL, PERIOD_M30, 1);
      double m30_close2 = iClose(NULL, PERIOD_M30, 2);

      double m30_range = m30_high1 - m30_low1;
      double m30_bodyB = m30_close1 - m30_open1;

      bool m30_bbTouch     = (m30_low1 <= m30_bbLower1) && (m30_close1 > m30_bbLower1);
      bool m30_rsiOS       = (m30_rsi1 < RSI_Buy);
      bool m30_rsiRising   = (m30_rsi1 > m30_rsi2);
      bool m30_bullBody    = (m30_bodyB > 0) && (m30_range > 0)
                          && (m30_bodyB >= Body_Pct * m30_range);
      bool m30_bbPrevBreak = (!Use_TwoBar_Pattern) || (m30_close2 <= m30_bbLower2);

      if(m30_bbTouch && m30_rsiOS && m30_rsiRising && m30_bullBody && m30_bbPrevBreak)
      {
         if(CountTradesByMagic(OP_BUY, Magic_Number) < Max_Buys)
         {
            double m30_atr = iATR(NULL, PERIOD_M30, ATR_Period, 1);
            if(m30_atr > 0)
            {
               double m30_slDist = ATR_SL_Multi * m30_atr;
               double m30_tpDist = ATR_TP_Multi * m30_atr;
               double m30_lots   = CalcLots(m30_slDist, riskScale);
               double entry      = NormalizeDouble(Ask, Digits);
               double sl         = NormalizeDouble(entry - m30_slDist, Digits);
               double tp         = NormalizeDouble(entry + m30_tpDist, Digits);
               if(m30_lots > 0)
               {
                  int tkt = OrderSend(Symbol(), OP_BUY, m30_lots, entry, Slippage,
                                      sl, tp, Order_Comment, Magic_Number, 0, clrAqua);
                  if(tkt > 0) g_TradesToday++;
               }
            }
         }
      }
   }

   //=== SELL (DISABLED - Max_Sells=0 NON-NEGOTIABLE) ===
   if(Max_Sells > 0 && h1Bear)
   {
      double bbUpper1s = iBands(NULL, 0, BB_Period, BB_Dev, 0, PRICE_CLOSE, MODE_UPPER, 1);
      double bbUpper2s = iBands(NULL, 0, BB_Period, BB_Dev, 0, PRICE_CLOSE, MODE_UPPER, 2);
      bool bbTouchUp   = (High[1] >= bbUpper1s) && (Close[1] < bbUpper1s);
      bool rsiOB       = (rsi1 > RSI_Sell);
      bool rsiFalling  = (rsi1 < rsi2);
      bool bearBody    = (candleBodyS > 0) && (candleRange > 0)
                      && (candleBodyS >= Body_Pct * candleRange);
      bool bbPrevBreakS = (!Use_TwoBar_Pattern) || (Close[2] >= bbUpper2s);

      if(bbTouchUp && rsiOB && rsiFalling && bearBody && bbPrevBreakS)
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
