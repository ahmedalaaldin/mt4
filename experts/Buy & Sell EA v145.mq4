//+------------------------------------------------------------------+
//|   Buy & Sell EA v145 - M5 + M15 Dual-Timeframe Signals          |
//|   Framework: H4 Direction / H1 RSI / M5 + M15 BB Entry          |
//|   Base: v144 (207.03% / 43.70% DD / 85.53% WR / 456 trades)    |
//|   Goal: Increase trade frequency by adding M15 BB signals        |
//|   Changes vs v144:                                               |
//|     1. Added M15 timeframe signal block (same BB+RSI formula)    |
//|        - Same BB(20, 2.5) + RSI(14)<40 + bullish body on M15    |
//|        - Same H4/H1 trend filter gate                            |
//|        - M15 ATR for SL/TP sizing (larger SL → smaller lots)    |
//|        - Separate bar-formation tracker (isNewBar_M15)           |
//|        - Separate last-trade timers for M15                      |
//|        - Shares same Max_Buys/Max_Sells limits as M5             |
//|        - Shares same anti-martingale streak                      |
//|     2. Scale_High: 1.85 (same as v144, proven 207% return)      |
//|   Expected: 600-700 trades/year (~1.7/day), WR similar to M5    |
//|   Key insight: M15 BB(2.5) selects stronger reversion points    |
//|   than M5 (wider swing), potentially similar or better WR       |
//|   ManageExits: uses M5 BB midline for all trades (both TFs)     |
//+------------------------------------------------------------------+
#property copyright ""
#property link      ""
#property version   "145.0"
#property strict

#include <stdlib.mqh>

//--- Session
input string SESSION_SET        = "============"; //====== Session Settings ======
input int    Session_Start_Hour = 7;              //Session Start Hour (server time)
input int    Session_End_Hour   = 20;             //Session End Hour (server time)

//--- Trend Filter
input string TREND_SET          = "============"; //====== Trend Filter ======
input int    H4_EMA_Period      = 200;            //H4 EMA period (broad trend)
input int    H1_EMA_Period      = 200;            //H1 EMA period (medium trend)

//--- H1 RSI Gate (proven v139 values)
input string H1RSI_SET          = "============"; //====== H1 RSI Gate ======
input int    H1_RSI_Period      = 14;             //H1 RSI period
input double H1_RSI_Min         = 45.0;           //H1 RSI min for BUY
input double H1_RSI_Max         = 75.0;           //H1 RSI max for BUY
input double H1_RSI_Min_Sell    = 25.0;           //H1 RSI min for SELL
input double H1_RSI_Max_Sell    = 55.0;           //H1 RSI max for SELL

//--- Bollinger Bands
input string BB_SET             = "============"; //====== BB Settings ======
input int    BB_Period          = 20;             //BB period (M5 and M15)
input double BB_Dev             = 2.5;            //BB SD (M5 and M15): proven high WR

//--- Signal: BB Touch (applies to both M5 and M15)
input string S1_SET             = "============"; //====== Signal: BB Touch ======
input int    RSI_Period         = 14;             //RSI period (M5 and M15)
input double RSI_Buy            = 40.0;           //RSI max for BUY (proven)
input double RSI_Sell           = 60.0;           //RSI min for SELL (proven)
input double Body_Pct           = 0.2;            //Min body fraction of candle range
input int    Min_Bar_Gap        = 1;              //Min bars between entries (per TF)

//--- Exit Settings
input string EXIT_SET           = "============"; //====== Exit Settings ======
input int    ATR_Period         = 14;             //ATR period
input double ATR_SL_Multi       = 1.0;            //SL = ATR x this
input double ATR_TP_Multi       = 2.0;            //TP = ATR x this (safety net)
input double Trail_ATR_Multi    = 0.8;            //Trail SL offset
input int    Max_Bars           = 100;            //Force-close after N M5 bars

//--- Money Management
input string MONEY_SET          = "============"; //====== Money Management ======
input double Risk_Pct           = 5.0;            //Base risk % per trade
input double Fixed_Lot          = 0.0;            //Fixed lot (0 = use Risk_Pct)
input int    Max_Buys           = 2;              //Max concurrent BUY positions
input int    Max_Sells          = 2;              //Max concurrent SELL positions

//--- Anti-Martingale (v144 proven values)
input string AM_SET             = "============"; //====== Anti-Martingale Settings ======
input int    WinStreak_Mid      = 2;              //Consec wins for Scale_Mid
input int    WinStreak_High     = 5;              //Consec wins for Scale_High
input double Scale_Mid          = 1.25;           //Scale at mid streak
input double Scale_High         = 1.85;           //Scale at high streak

//--- Safety
input string SAFETY_SET         = "============"; //====== Safety Settings ======
input int    MaxSpread          = 35;             //Max spread in points
input int    Slippage           = 30;             //Max slippage in points
input int    Magic_Number       = 1452025;        //Magic Number
input string Order_Comment      = "BSv145";       //Order comment prefix
input double Max_Daily_DD_Pct   = 15.0;           //Daily DD guard (% of equity)
input int    Max_Trades_Day     = 300;            //Max trades per day cap

//+------------------------------------------------------------------+
double   g_DayOpenEquity   = 0;
bool     g_DailyDDHit      = false;
int      g_TradesToday     = 0;
datetime g_LastDay         = 0;
datetime g_LastBuyTime_M5  = 0;
datetime g_LastSellTime_M5 = 0;
datetime g_LastBuyTime_M15 = 0;
datetime g_LastSellTime_M15= 0;

//+------------------------------------------------------------------+
int OnInit()  { return(INIT_SUCCEEDED); }
void OnDeinit(const int reason) {}

//+------------------------------------------------------------------+
int CountLastStreak()
{
   datetime prevTime = TimeCurrent() + 1;
   int maxLook = 40;
   bool isWin = false;
   bool firstFound = false;
   int count = 0;

   for(int pass = 0; pass < maxLook; pass++)
   {
      datetime bestTime  = 0;
      bool     bestResult = false;
      for(int i = OrdersHistoryTotal() - 1; i >= 0; i--)
      {
         if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
         if(OrderSymbol() != Symbol()) continue;
         if(OrderMagicNumber() != Magic_Number) continue;
         if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;
         if(OrderCloseTime() < prevTime && OrderCloseTime() > bestTime)
         {
            bestTime   = OrderCloseTime();
            bestResult = (OrderProfit() + OrderCommission() + OrderSwap() >= 0);
         }
      }
      if(bestTime == 0) break;

      if(!firstFound)
      {
         isWin      = bestResult;
         firstFound = true;
         count      = 1;
      }
      else
      {
         if(bestResult == isWin) count++;
         else break;
      }
      prevTime = bestTime;
   }

   if(!firstFound) return 0;
   return isWin ? count : -count;
}

//+------------------------------------------------------------------+
double GetRiskScale()
{
   int streak = CountLastStreak();
   if(streak >= WinStreak_High) return Scale_High;
   if(streak >= WinStreak_Mid)  return Scale_Mid;
   if(streak > 0)               return 1.0;
   if(streak == 0)              return 1.0;
   int losses = -streak;
   if(losses == 1) return 0.5;
   if(losses == 2) return 0.25;
   return 0.1;
}

//+------------------------------------------------------------------+
double CalcLots(double slDist, double riskScale = 1.0)
{
   if(Fixed_Lot > 0) return NormalizeDouble(Fixed_Lot, 2);
   double tickVal  = MarketInfo(Symbol(), MODE_TICKVALUE);
   double tickSize = MarketInfo(Symbol(), MODE_TICKSIZE);
   if(tickVal <= 0 || tickSize <= 0) return MarketInfo(Symbol(), MODE_MINLOT);
   double riskAmt  = AccountEquity() * (Risk_Pct * riskScale) / 100.0;
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
   // Use M5 ATR and BB mid for all exit management
   double atr   = iATR(NULL, PERIOD_M5, ATR_Period, 1);
   double bbMid = iBands(NULL, PERIOD_M5, BB_Period, BB_Dev, 0, PRICE_CLOSE, MODE_MAIN, 0);
   if(atr <= 0 || bbMid <= 0) return;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != Magic_Number) continue;

      int    tkt       = OrderTicket();
      double openPrice = OrderOpenPrice();
      double currentSL = OrderStopLoss();
      int    type      = OrderType();
      int    bars      = iBarShift(NULL, PERIOD_M5, OrderOpenTime(), false);

      if(type == OP_BUY)
      {
         bool partialDone = (currentSL >= openPrice);
         if(!partialDone && Bid >= bbMid)
         {
            double stepLot  = MarketInfo(Symbol(), MODE_LOTSTEP);
            double minLot   = MarketInfo(Symbol(), MODE_MINLOT);
            double halfLots = MathFloor(OrderLots() * 0.5 / stepLot) * stepLot;
            if(halfLots >= minLot && halfLots < OrderLots())
            {
               if(OrderClose(tkt, halfLots, Bid, Slippage, clrCyan))
               {
                  if(OrderSelect(tkt, SELECT_BY_TICKET, MODE_TRADES))
                     OrderModify(tkt, openPrice, NormalizeDouble(openPrice, Digits), 0, 0, clrBlue);
               }
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
         if(bars >= Max_Bars)
            OrderClose(tkt, OrderLots(), Bid, Slippage, clrYellow);
      }
      else if(type == OP_SELL)
      {
         bool partialDone = (currentSL > 0 && currentSL <= openPrice);
         if(!partialDone && Ask <= bbMid)
         {
            double stepLot  = MarketInfo(Symbol(), MODE_LOTSTEP);
            double minLot   = MarketInfo(Symbol(), MODE_MINLOT);
            double halfLots = MathFloor(OrderLots() * 0.5 / stepLot) * stepLot;
            if(halfLots >= minLot && halfLots < OrderLots())
            {
               if(OrderClose(tkt, halfLots, Ask, Slippage, clrCyan))
               {
                  if(OrderSelect(tkt, SELECT_BY_TICKET, MODE_TRADES))
                     OrderModify(tkt, openPrice, NormalizeDouble(openPrice, Digits), 0, 0, clrBlue);
               }
            }
            else
            {
               if(currentSL > openPrice)
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
         if(bars >= Max_Bars)
            OrderClose(tkt, OrderLots(), Ask, Slippage, clrYellow);
      }
   }
}

//+------------------------------------------------------------------+
void OnTick()
{
   // Track M5 and M15 bar formations
   static datetime s_LastBar_M5  = 0;
   static datetime s_LastBar_M15 = 0;

   bool isNewBar_M5  = (Time[0] != s_LastBar_M5);
   bool isNewBar_M15 = (iTime(NULL, PERIOD_M15, 0) != s_LastBar_M15);

   if(isNewBar_M5)  s_LastBar_M5  = Time[0];
   if(isNewBar_M15) s_LastBar_M15 = iTime(NULL, PERIOD_M15, 0);

   // Daily reset
   MqlDateTime dt;
   TimeToStruct(Time[0], dt);
   datetime today = StringToTime(StringFormat("%d.%02d.%02d", dt.year, dt.mon, dt.day));
   if(today != g_LastDay)
   {
      g_DayOpenEquity = AccountEquity();
      g_DailyDDHit    = false;
      g_TradesToday   = 0;
      g_LastDay       = today;
   }

   if(!g_DailyDDHit && g_DayOpenEquity > 0)
   {
      double ddPct = (g_DayOpenEquity - AccountEquity()) / g_DayOpenEquity * 100.0;
      if(ddPct >= Max_Daily_DD_Pct) { CloseAllTrades(); g_DailyDDHit = true; return; }
   }
   if(g_DailyDDHit) return;

   ManageExits();

   // Only process new entries on new bars
   if(!isNewBar_M5 && !isNewBar_M15) return;

   bool inSession = (dt.hour >= Session_Start_Hour && dt.hour < Session_End_Hour);
   if(!inSession) return;
   if(MarketInfo(Symbol(), MODE_SPREAD) > MaxSpread) return;
   if(g_TradesToday >= Max_Trades_Day) return;

   // Shared higher-timeframe filters
   double h4_ema  = iMA(NULL, PERIOD_H4, H4_EMA_Period, 0, MODE_EMA, PRICE_CLOSE, 0);
   double h1_ema  = iMA(NULL, PERIOD_H1, H1_EMA_Period, 0, MODE_EMA, PRICE_CLOSE, 0);
   double h1_rsi1 = iRSI(NULL, PERIOD_H1, H1_RSI_Period, PRICE_CLOSE, 1);

   bool h4Bull = (iClose(NULL, PERIOD_H4, 0) > h4_ema);
   bool h4Bear = (iClose(NULL, PERIOD_H4, 0) < h4_ema);

   bool h1Bull = (iClose(NULL, PERIOD_H1, 1) > h1_ema)
              && (h1_rsi1 >= H1_RSI_Min) && (h1_rsi1 <= H1_RSI_Max);
   bool h1Bear = (iClose(NULL, PERIOD_H1, 1) < h1_ema)
              && (h1_rsi1 >= H1_RSI_Min_Sell) && (h1_rsi1 <= H1_RSI_Max_Sell);

   double riskScale = GetRiskScale();

   //=======================================================================
   //  M5 SIGNALS (same as v144)
   //=======================================================================
   if(isNewBar_M5)
   {
      double m5_atr1     = iATR(NULL, PERIOD_M5, ATR_Period, 1);
      double m5_bbLower1 = iBands(NULL, PERIOD_M5, BB_Period, BB_Dev, 0, PRICE_CLOSE, MODE_LOWER, 1);
      double m5_bbUpper1 = iBands(NULL, PERIOD_M5, BB_Period, BB_Dev, 0, PRICE_CLOSE, MODE_UPPER, 1);
      double m5_rsi1     = iRSI(NULL, PERIOD_M5, RSI_Period, PRICE_CLOSE, 1);
      double m5_rsi2     = iRSI(NULL, PERIOD_M5, RSI_Period, PRICE_CLOSE, 2);

      if(m5_atr1 > 0)
      {
         double m5_slDist    = ATR_SL_Multi * m5_atr1;
         double m5_tpDist    = ATR_TP_Multi * m5_atr1;
         double m5_range     = High[1] - Low[1];
         double m5_bodyB     = Close[1] - Open[1];
         double m5_bodyS     = Open[1] - Close[1];

         // M5 BUY
         if(h4Bull && h1Bull)
         {
            bool bbTouch   = (Low[1] <= m5_bbLower1) && (Close[1] > m5_bbLower1);
            bool rsiOS     = (m5_rsi1 < RSI_Buy);
            bool rsiRising = (m5_rsi1 > m5_rsi2);
            bool bullBody  = (m5_bodyB > 0) && (m5_range > 0) && (m5_bodyB >= Body_Pct * m5_range);

            if(bbTouch && rsiOS && rsiRising && bullBody)
            {
               int openBuys  = CountTradesByMagic(OP_BUY, Magic_Number);
               int barsSince = (int)((Time[0] - g_LastBuyTime_M5) / PeriodSeconds());
               if(openBuys < Max_Buys && barsSince >= Min_Bar_Gap)
               {
                  double entry = NormalizeDouble(Ask, Digits);
                  double sl    = NormalizeDouble(entry - m5_slDist, Digits);
                  double tp    = NormalizeDouble(entry + m5_tpDist, Digits);
                  double lots  = CalcLots(m5_slDist, riskScale);
                  if(lots > 0)
                  {
                     int tkt = OrderSend(Symbol(), OP_BUY, lots, entry, Slippage,
                                         sl, tp, Order_Comment + "-M5", Magic_Number, 0, clrGreen);
                     if(tkt > 0) { g_TradesToday++; g_LastBuyTime_M5 = Time[0]; }
                  }
               }
            }
         }

         // M5 SELL
         if(h4Bear && h1Bear)
         {
            bool bbTouchUp  = (High[1] >= m5_bbUpper1) && (Close[1] < m5_bbUpper1);
            bool rsiOB      = (m5_rsi1 > RSI_Sell);
            bool rsiFalling = (m5_rsi1 < m5_rsi2);
            bool bearBody   = (m5_bodyS > 0) && (m5_range > 0) && (m5_bodyS >= Body_Pct * m5_range);

            if(bbTouchUp && rsiOB && rsiFalling && bearBody)
            {
               int openSells = CountTradesByMagic(OP_SELL, Magic_Number);
               int barsSince = (int)((Time[0] - g_LastSellTime_M5) / PeriodSeconds());
               if(openSells < Max_Sells && barsSince >= Min_Bar_Gap)
               {
                  double entry = NormalizeDouble(Bid, Digits);
                  double sl    = NormalizeDouble(entry + m5_slDist, Digits);
                  double tp    = NormalizeDouble(entry - m5_tpDist, Digits);
                  double lots  = CalcLots(m5_slDist, riskScale);
                  if(lots > 0)
                  {
                     int tkt = OrderSend(Symbol(), OP_SELL, lots, entry, Slippage,
                                         sl, tp, Order_Comment + "-M5", Magic_Number, 0, clrRed);
                     if(tkt > 0) { g_TradesToday++; g_LastSellTime_M5 = Time[0]; }
                  }
               }
            }
         }
      }
   }

   //=======================================================================
   //  M15 SIGNALS (same formula, M15 ATR + M15 BB + M15 RSI)
   //=======================================================================
   if(isNewBar_M15)
   {
      double m15_atr1     = iATR(NULL, PERIOD_M15, ATR_Period, 1);
      double m15_bbLower1 = iBands(NULL, PERIOD_M15, BB_Period, BB_Dev, 0, PRICE_CLOSE, MODE_LOWER, 1);
      double m15_bbUpper1 = iBands(NULL, PERIOD_M15, BB_Period, BB_Dev, 0, PRICE_CLOSE, MODE_UPPER, 1);
      double m15_rsi1     = iRSI(NULL, PERIOD_M15, RSI_Period, PRICE_CLOSE, 1);
      double m15_rsi2     = iRSI(NULL, PERIOD_M15, RSI_Period, PRICE_CLOSE, 2);

      double m15_Low1   = iLow(NULL,  PERIOD_M15, 1);
      double m15_High1  = iHigh(NULL, PERIOD_M15, 1);
      double m15_Close1 = iClose(NULL, PERIOD_M15, 1);
      double m15_Open1  = iOpen(NULL,  PERIOD_M15, 1);

      if(m15_atr1 > 0)
      {
         double m15_slDist = ATR_SL_Multi * m15_atr1;
         double m15_tpDist = ATR_TP_Multi * m15_atr1;
         double m15_range  = m15_High1 - m15_Low1;
         double m15_bodyB  = m15_Close1 - m15_Open1;
         double m15_bodyS  = m15_Open1  - m15_Close1;
         int    m15_period_sec = PERIOD_M15 * 60;

         // M15 BUY
         if(h4Bull && h1Bull)
         {
            bool bbTouch   = (m15_Low1 <= m15_bbLower1) && (m15_Close1 > m15_bbLower1);
            bool rsiOS     = (m15_rsi1 < RSI_Buy);
            bool rsiRising = (m15_rsi1 > m15_rsi2);
            bool bullBody  = (m15_bodyB > 0) && (m15_range > 0) && (m15_bodyB >= Body_Pct * m15_range);

            if(bbTouch && rsiOS && rsiRising && bullBody)
            {
               int openBuys  = CountTradesByMagic(OP_BUY, Magic_Number);
               int barsSince = (int)((iTime(NULL, PERIOD_M15, 0) - g_LastBuyTime_M15) / m15_period_sec);
               if(openBuys < Max_Buys && barsSince >= Min_Bar_Gap)
               {
                  double entry = NormalizeDouble(Ask, Digits);
                  double sl    = NormalizeDouble(entry - m15_slDist, Digits);
                  double tp    = NormalizeDouble(entry + m15_tpDist, Digits);
                  double lots  = CalcLots(m15_slDist, riskScale);
                  if(lots > 0)
                  {
                     int tkt = OrderSend(Symbol(), OP_BUY, lots, entry, Slippage,
                                         sl, tp, Order_Comment + "-15", Magic_Number, 0, clrLime);
                     if(tkt > 0) { g_TradesToday++; g_LastBuyTime_M15 = iTime(NULL, PERIOD_M15, 0); }
                  }
               }
            }
         }

         // M15 SELL
         if(h4Bear && h1Bear)
         {
            bool bbTouchUp  = (m15_High1 >= m15_bbUpper1) && (m15_Close1 < m15_bbUpper1);
            bool rsiOB      = (m15_rsi1 > RSI_Sell);
            bool rsiFalling = (m15_rsi1 < m15_rsi2);
            bool bearBody   = (m15_bodyS > 0) && (m15_range > 0) && (m15_bodyS >= Body_Pct * m15_range);

            if(bbTouchUp && rsiOB && rsiFalling && bearBody)
            {
               int openSells = CountTradesByMagic(OP_SELL, Magic_Number);
               int barsSince = (int)((iTime(NULL, PERIOD_M15, 0) - g_LastSellTime_M15) / m15_period_sec);
               if(openSells < Max_Sells && barsSince >= Min_Bar_Gap)
               {
                  double entry = NormalizeDouble(Bid, Digits);
                  double sl    = NormalizeDouble(entry + m15_slDist, Digits);
                  double tp    = NormalizeDouble(entry - m15_tpDist, Digits);
                  double lots  = CalcLots(m15_slDist, riskScale);
                  if(lots > 0)
                  {
                     int tkt = OrderSend(Symbol(), OP_SELL, lots, entry, Slippage,
                                         sl, tp, Order_Comment + "-15", Magic_Number, 0, clrTomato);
                     if(tkt > 0) { g_TradesToday++; g_LastSellTime_M15 = iTime(NULL, PERIOD_M15, 0); }
                  }
               }
            }
         }
      }
   }
}
//+------------------------------------------------------------------+
