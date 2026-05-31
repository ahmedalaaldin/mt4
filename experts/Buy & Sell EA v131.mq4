//+------------------------------------------------------------------+
//|   Buy & Sell EA v131 - M5 BB Mean Reversion + M1 RSI Scalp      |
//|   Framework: H4 Direction / H1 Structure / M5+M1 Entry           |
//|   Base: v130                                                     |
//|   Changes vs v130:                                               |
//|     - Signal 1: H1 RSI gate RESTORED to v120 exact values       |
//|       h1Bull requires H1 RSI 45-75, h1Bear requires 25-55        |
//|       This restores v120's 92.94% WR quality filter              |
//|     - Signal 2 (EMA cross): DISABLED - had ~42% WR hurting perf |
//|     - Signal 3 NEW: M1 BB(20,2.0) + RSI(7) scalping            |
//|       Runs on every new M1 bar, 0.5% risk per trade              |
//|       H1 EMA + H1 RSI direction filter (same gate as Signal 1)   |
//|       SL = 1.0x M1 ATR, TP = 1.5x M1 ATR, max hold 60 M1 bars  |
//|       Max 2 concurrent buys, 2 concurrent sells                  |
//|       Min 3 M1 bar gap between same-direction entries            |
//+------------------------------------------------------------------+
#property copyright ""
#property link      ""
#property version   "150.0"
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

//--- H1 RSI Gate (RESTORED from v120)
input string H1RSI_SET          = "============"; //====== H1 RSI Gate (v120 restored) ======
input int    H1_RSI_Period      = 14;             //H1 RSI period
input double H1_RSI_Min         = 45.0;           //H1 RSI min for BUY (bullish momentum zone)
input double H1_RSI_Max         = 75.0;           //H1 RSI max for BUY (not overbought)
input double H1_RSI_Min_Sell    = 25.0;           //H1 RSI min for SELL (not oversold)
input double H1_RSI_Max_Sell    = 55.0;           //H1 RSI max for SELL (bearish momentum zone)

//--- Bollinger Bands (M5) - Signal 1
input string BB_SET             = "============"; //====== BB Touch Signal (Signal 1) ======
input int    BB_Period          = 20;             //BB period
input double BB_Dev             = 2.5;            //BB SD
input double TP_Min_ATR         = 0.5;            //Min TP distance as ATR multiple

//--- Entry Signal 1: BB Touch filters (v120 exact values)
input string ENTRY_SET          = "============"; //====== BB Touch Filters ======
input int    RSI_Period         = 14;             //M5 RSI period
input double RSI_Buy            = 40.0;           //M5 RSI max for BUY (oversold threshold)
input double RSI_Sell           = 60.0;           //M5 RSI min for SELL (overbought threshold)
input int    Stoch_K            = 5;              //Stochastic K period
input int    Stoch_D            = 3;              //Stochastic D period
input int    Stoch_Slowing      = 3;              //Stochastic slowing
input double Stoch_OS           = 25.0;           //Stochastic oversold level (buy)
input double Stoch_OB           = 75.0;           //Stochastic overbought level (sell)
input double Body_Pct           = 0.2;            //Min body as fraction of candle range
input int    Min_Bar_Gap        = 1;              //Min M5 bars between Signal 1 entries

//--- Signal 3: M1 BB + RSI Scalping (NEW)
input string M1_SET             = "============"; //====== M1 Scalp Signal (Signal 3) ======
input bool   Use_M1_Scalp       = true;           //Enable M1 scalping signal
input int    M1_BB_Period       = 20;             //M1 BB period
input double M1_BB_Dev          = 2.0;            //M1 BB standard deviations
input int    M1_RSI_Period      = 7;              //M1 RSI period
input double M1_RSI_Buy         = 30.0;           //M1 RSI oversold threshold (buy)
input double M1_RSI_Sell        = 70.0;           //M1 RSI overbought threshold (sell)
input int    M1_ATR_Period      = 7;              //M1 ATR period
input double M1_SL_Multi        = 1.0;            //M1 SL = ATR x this
input double M1_TP_Multi        = 1.5;            //M1 TP = ATR x this
input double Risk_Pct_M1        = 0.5;            //Risk % per M1 trade
input int    Max_M1_Buys        = 2;              //Max concurrent M1 BUY positions
input int    Max_M1_Sells       = 2;              //Max concurrent M1 SELL positions
input int    Min_M1_Bar_Gap     = 3;              //Min M1 bars between same-direction entries
input int    Max_M1_Bars_Hold   = 60;             //Max M1 bars to hold position (time exit)

//--- Exit (Signal 1)
input string EXIT_SET           = "============"; //====== Exit Settings ======
input int    ATR_Period         = 14;             //ATR period (M5)
input double ATR_SL_Multi       = 1.0;            //Signal 1 SL = M5 ATR x this
input double Trail_ATR_Multi    = 0.8;            //Trail SL offset from BB mid
input int    Max_Bars           = 100;            //Force-close after N M5 bars (Signal 1)

//--- Money Management
input string MONEY_SET          = "============"; //====== Money Management ======
input double Risk_Pct           = 5.0;            //Risk % per Signal 1 trade
input double Fixed_Lot          = 0.0;            //Fixed lot size (0 = use Risk_Pct)
input int    Max_Buys           = 1;              //Max concurrent Signal 1 BUY
input int    Max_Sells          = 1;              //Max concurrent Signal 1 SELL

//--- Safety
input string SAFETY_SET         = "============"; //====== Safety Settings ======
input int    MaxSpread          = 35;             //Max spread in points
input int    Slippage           = 30;             //Max slippage in points
input int    Magic_Number       = 1402025;        //Magic Number (Signal 1)
input int    Magic_M1           = 1402027;        //Magic Number (Signal 3 M1)
input string Order_Comment      = "BSv150";       //Order comment
input double Max_Daily_DD_Pct   = 15.0;           //Daily drawdown guard (% of equity)
input int    Max_Trades_Day     = 300;            //Max trades per day

//+------------------------------------------------------------------+
double   g_DayOpenEquity   = 0;
bool     g_DailyDDHit      = false;
int      g_TradesToday     = 0;
datetime g_LastDay         = 0;

// Signal 1 trackers
datetime g_LastBuyTime1    = 0;
datetime g_LastSellTime1   = 0;

// Signal 3 (M1) trackers
datetime g_LastM1BuyTime   = 0;
datetime g_LastM1SellTime  = 0;

//+------------------------------------------------------------------+
int OnInit()  { return(INIT_SUCCEEDED); }
void OnDeinit(const int reason) {}

//+------------------------------------------------------------------+
int CountConsecLosses()
{
   int count = 0;
   datetime prevTime = TimeCurrent() + 1;

   for(int pass = 0; pass < 6; pass++)
   {
      datetime bestTime = 0;
      bool     bestLoss = false;

      for(int i = OrdersHistoryTotal() - 1; i >= 0; i--)
      {
         if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
         if(OrderSymbol() != Symbol()) continue;
         if(OrderMagicNumber() != Magic_Number) continue;
         if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;
         if(OrderCloseTime() < prevTime && OrderCloseTime() > bestTime)
         {
            bestTime = OrderCloseTime();
            bestLoss = (OrderProfit() + OrderCommission() + OrderSwap() < 0);
         }
      }

      if(bestTime == 0) break;
      if(!bestLoss)     break;
      count++;
      prevTime = bestTime;
   }
   return count;
}

//+------------------------------------------------------------------+
double GetRiskScale()
{
   int streak = CountConsecLosses();
   if(streak == 0) return 1.0;
   if(streak == 1) return 0.5;
   if(streak == 2) return 0.25;
   return 0.1;
}

//+------------------------------------------------------------------+
void OnTick()
{
   // M5 bar tracker
   static datetime s_LastBar   = 0;
   bool isNewBar = (Time[0] != s_LastBar);
   if(isNewBar) s_LastBar = Time[0];

   // M1 bar tracker
   static datetime s_LastM1Bar = 0;
   datetime m1_bar0 = iTime(NULL, PERIOD_M1, 0);
   bool isNewM1Bar  = (m1_bar0 != s_LastM1Bar);
   if(isNewM1Bar) s_LastM1Bar = m1_bar0;

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

   // Daily DD guard
   if(!g_DailyDDHit && g_DayOpenEquity > 0)
   {
      double ddPct = (g_DayOpenEquity - AccountEquity()) / g_DayOpenEquity * 100.0;
      if(ddPct >= Max_Daily_DD_Pct) { CloseAllTrades(); g_DailyDDHit = true; return; }
   }
   if(g_DailyDDHit) return;

   ManageExits();

   // Session and spread checks
   bool inSession = (dt.hour >= Session_Start_Hour && dt.hour < Session_End_Hour);
   bool spreadOK  = (MarketInfo(Symbol(), MODE_SPREAD) <= MaxSpread);

   // H1/H4 trend indicators — computed once per tick, shared by all signals
   double h4_ema  = iMA(NULL, PERIOD_H4, H4_EMA_Period, 0, MODE_EMA, PRICE_CLOSE, 0);
   double h1_ema  = iMA(NULL, PERIOD_H1, H1_EMA_Period, 0, MODE_EMA, PRICE_CLOSE, 0);
   double h1_rsi1 = iRSI(NULL, PERIOD_H1, H1_RSI_Period, PRICE_CLOSE, 1);

   bool h4Bull = (iClose(NULL, PERIOD_H4, 0) > h4_ema);
   bool h4Bear = (iClose(NULL, PERIOD_H4, 0) < h4_ema);

   // H1 condition: price vs EMA + RSI gate (RESTORED from v120)
   bool h1Bull = (iClose(NULL, PERIOD_H1, 1) > h1_ema)
              && (h1_rsi1 >= H1_RSI_Min) && (h1_rsi1 <= H1_RSI_Max);
   bool h1Bear = (iClose(NULL, PERIOD_H1, 1) < h1_ema)
              && (h1_rsi1 >= H1_RSI_Min_Sell) && (h1_rsi1 <= H1_RSI_Max_Sell);

   //=== Signal 3: M1 BB + RSI Scalping ===
   if(Use_M1_Scalp && isNewM1Bar && inSession && spreadOK && g_TradesToday < Max_Trades_Day)
   {
      double m1_atr1 = iATR(NULL, PERIOD_M1, M1_ATR_Period, 1);
      if(m1_atr1 > 0)
      {
         double m1_bb_lower = iBands(NULL, PERIOD_M1, M1_BB_Period, M1_BB_Dev, 0, PRICE_CLOSE, MODE_LOWER, 1);
         double m1_bb_upper = iBands(NULL, PERIOD_M1, M1_BB_Period, M1_BB_Dev, 0, PRICE_CLOSE, MODE_UPPER, 1);
         double m1_rsi1     = iRSI(NULL, PERIOD_M1, M1_RSI_Period, PRICE_CLOSE, 1);
         double m1_low1     = iLow(NULL,  PERIOD_M1, 1);
         double m1_high1    = iHigh(NULL, PERIOD_M1, 1);
         double m1_close1   = iClose(NULL, PERIOD_M1, 1);

         // M1 BUY: BB lower touch + RSI oversold + H1 bullish (uses same H1 gate as Signal 1)
         if(h1Bull && m1_low1 <= m1_bb_lower && m1_close1 > m1_bb_lower && m1_rsi1 < M1_RSI_Buy)
         {
            int m1Buys    = CountTradesByMagic(OP_BUY, Magic_M1);
            int barsSince = (int)((m1_bar0 - g_LastM1BuyTime) / 60);

            if(m1Buys < Max_M1_Buys && barsSince >= Min_M1_Bar_Gap)
            {
               double entry = NormalizeDouble(Ask, Digits);
               double sl3   = NormalizeDouble(entry - M1_SL_Multi * m1_atr1, Digits);
               double tp3   = NormalizeDouble(entry + M1_TP_Multi * m1_atr1, Digits);
               double lots3 = CalcLotsM1(m1_atr1 * M1_SL_Multi);
               if(lots3 > 0)
               {
                  int tkt = OrderSend(Symbol(), OP_BUY, lots3, entry, Slippage,
                                      sl3, tp3, Order_Comment, Magic_M1, 0, clrAqua);
                  if(tkt > 0) { g_TradesToday++; g_LastM1BuyTime = m1_bar0; }
               }
            }
         }

         // M1 SELL: BB upper touch + RSI overbought + H1 bearish
         if(h1Bear && m1_high1 >= m1_bb_upper && m1_close1 < m1_bb_upper && m1_rsi1 > M1_RSI_Sell)
         {
            int m1Sells   = CountTradesByMagic(OP_SELL, Magic_M1);
            int barsSince = (int)((m1_bar0 - g_LastM1SellTime) / 60);

            if(m1Sells < Max_M1_Sells && barsSince >= Min_M1_Bar_Gap)
            {
               double entry = NormalizeDouble(Bid, Digits);
               double sl3   = NormalizeDouble(entry + M1_SL_Multi * m1_atr1, Digits);
               double tp3   = NormalizeDouble(entry - M1_TP_Multi * m1_atr1, Digits);
               double lots3 = CalcLotsM1(m1_atr1 * M1_SL_Multi);
               if(lots3 > 0)
               {
                  int tkt = OrderSend(Symbol(), OP_SELL, lots3, entry, Slippage,
                                      sl3, tp3, Order_Comment, Magic_M1, 0, clrMagenta);
                  if(tkt > 0) { g_TradesToday++; g_LastM1SellTime = m1_bar0; }
               }
            }
         }
      }
   }

   //=== M5 signals: only fire on new M5 bars ===
   if(!isNewBar) return;
   if(!inSession) return;
   if(g_TradesToday >= Max_Trades_Day) return;
   if(!spreadOK) return;

   double atr1 = iATR(NULL, 0, ATR_Period, 1);
   if(atr1 <= 0) return;

   double bbMid0   = iBands(NULL, 0, BB_Period, BB_Dev, 0, PRICE_CLOSE, MODE_MAIN,  0);
   double bbLower1 = iBands(NULL, 0, BB_Period, BB_Dev, 0, PRICE_CLOSE, MODE_LOWER, 1);
   double bbUpper1 = iBands(NULL, 0, BB_Period, BB_Dev, 0, PRICE_CLOSE, MODE_UPPER, 1);
   double rsi1     = iRSI(NULL, 0, RSI_Period, PRICE_CLOSE, 1);
   double rsi2     = iRSI(NULL, 0, RSI_Period, PRICE_CLOSE, 2);
   double stochK1  = iStochastic(NULL, 0, Stoch_K, Stoch_D, Stoch_Slowing, MODE_SMA, 0, MODE_MAIN,   1);
   double stochD1  = iStochastic(NULL, 0, Stoch_K, Stoch_D, Stoch_Slowing, MODE_SMA, 0, MODE_SIGNAL, 1);

   double slDist      = ATR_SL_Multi * atr1;
   double minTP       = TP_Min_ATR * atr1;
   double candleRange = High[1] - Low[1];
   double candleBody  = Close[1] - Open[1];
   double riskScale   = GetRiskScale();

   //=== Signal 1: M5 BB Touch (v120 exact quality, H1 RSI gate restored) ===
   if(h4Bull && h1Bull)
   {
      bool bbTouch   = (Low[1] <= bbLower1) && (Close[1] > bbLower1);
      bool rsiOS     = (rsi1 < RSI_Buy);
      bool rsiRising = (rsi1 > rsi2);
      bool stochOS   = (stochK1 < Stoch_OS) && (stochD1 < Stoch_OS);
      bool bullBody  = (candleBody > 0) && (candleRange > 0) && (candleBody >= Body_Pct * candleRange);

      if(bbTouch && rsiOS && rsiRising && stochOS && bullBody)
      {
         double tpDist = bbMid0 - Ask;
         if(tpDist >= minTP)
         {
            int openBuys  = CountTradesByMagic(OP_BUY, Magic_Number);
            int barsSince = (int)((Time[0] - g_LastBuyTime1) / PeriodSeconds());

            if(openBuys < Max_Buys && barsSince >= Min_Bar_Gap)
            {
               double entry = NormalizeDouble(Ask, Digits);
               double lots  = CalcLots(slDist, riskScale);
               if(lots > 0)
               {
                  int tkt = OrderSend(Symbol(), OP_BUY, lots, entry, Slippage,
                                      NormalizeDouble(entry - slDist, Digits),
                                      0, Order_Comment, Magic_Number, 0, clrGreen);
                  if(tkt > 0) { g_TradesToday++; g_LastBuyTime1 = Time[0]; }
               }
            }
         }
      }
   }

   if(h4Bear && h1Bear)
   {
      bool bbTouchUp  = (High[1] >= bbUpper1) && (Close[1] < bbUpper1);
      bool rsiOB      = (rsi1 > RSI_Sell);
      bool rsiFalling = (rsi1 < rsi2);
      bool stochOB    = (stochK1 > Stoch_OB) && (stochD1 > Stoch_OB);
      bool bearBody   = (candleBody < 0) && (candleRange > 0) && (MathAbs(candleBody) >= Body_Pct * candleRange);

      if(bbTouchUp && rsiOB && rsiFalling && stochOB && bearBody)
      {
         double tpDist = Bid - bbMid0;
         if(tpDist >= minTP)
         {
            int openSells = CountTradesByMagic(OP_SELL, Magic_Number);
            int barsSince = (int)((Time[0] - g_LastSellTime1) / PeriodSeconds());

            if(openSells < Max_Sells && barsSince >= Min_Bar_Gap)
            {
               double entry = NormalizeDouble(Bid, Digits);
               double lots  = CalcLots(slDist, riskScale);
               if(lots > 0)
               {
                  int tkt = OrderSend(Symbol(), OP_SELL, lots, entry, Slippage,
                                      NormalizeDouble(entry + slDist, Digits),
                                      0, Order_Comment, Magic_Number, 0, clrRed);
                  if(tkt > 0) { g_TradesToday++; g_LastSellTime1 = Time[0]; }
               }
            }
         }
      }
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
      if(OrderSymbol() != Symbol()) continue;
      if(OrderMagicNumber() != Magic_Number && OrderMagicNumber() != Magic_M1) continue;

      int    tkt       = OrderTicket();
      double openPrice = OrderOpenPrice();
      double currentSL = OrderStopLoss();
      int    type      = OrderType();

      // Signal 3 (M1): TP already set in OrderSend, apply time-based exit only
      if(OrderMagicNumber() == Magic_M1)
      {
         int m1Bars = iBarShift(NULL, PERIOD_M1, OrderOpenTime(), false);
         if(m1Bars >= Max_M1_Bars_Hold)
         {
            if(type == OP_BUY)  OrderClose(tkt, OrderLots(), Bid, Slippage, clrYellow);
            if(type == OP_SELL) OrderClose(tkt, OrderLots(), Ask, Slippage, clrYellow);
         }
         continue;
      }

      // Signal 1: BB mid partial close + trailing stop
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

         if(iBarShift(NULL, 0, OrderOpenTime(), false) >= Max_Bars)
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

         if(iBarShift(NULL, 0, OrderOpenTime(), false) >= Max_Bars)
            OrderClose(tkt, OrderLots(), Ask, Slippage, clrYellow);
      }
   }
}

//+------------------------------------------------------------------+
void CloseAllTrades()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol()) continue;
      if(OrderMagicNumber() != Magic_Number && OrderMagicNumber() != Magic_M1) continue;
      if(OrderType() == OP_BUY)
         OrderClose(OrderTicket(), OrderLots(), Bid, Slippage, clrOrange);
      else if(OrderType() == OP_SELL)
         OrderClose(OrderTicket(), OrderLots(), Ask, Slippage, clrOrange);
   }
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
// Signal 1 lot calculator (uses Risk_Pct with risk scaling)
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
// Signal 3 lot calculator (uses Risk_Pct_M1, no scaling for speed)
double CalcLotsM1(double slDist)
{
   double tickVal  = MarketInfo(Symbol(), MODE_TICKVALUE);
   double tickSize = MarketInfo(Symbol(), MODE_TICKSIZE);
   if(tickVal <= 0 || tickSize <= 0) return MarketInfo(Symbol(), MODE_MINLOT);
   double riskAmt  = AccountEquity() * Risk_Pct_M1 / 100.0;
   double slTicks  = slDist / tickSize;
   double lots     = riskAmt / (slTicks * tickVal);
   double stepLot  = MarketInfo(Symbol(), MODE_LOTSTEP);
   double minLot   = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot   = MarketInfo(Symbol(), MODE_MAXLOT);
   lots = MathFloor(lots / stepLot) * stepLot;
   return NormalizeDouble(MathMax(minLot, MathMin(maxLot, lots)), 2);
}
//+------------------------------------------------------------------+
