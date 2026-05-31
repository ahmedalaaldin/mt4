//+------------------------------------------------------------------+
//|   Buy & Sell EA v132 - Three M5 Signals, All H1-RSI Gated       |
//|   Framework: H4 Direction / H1 Structure / M5 Entry              |
//|   Base: v131                                                     |
//|   Changes vs v131:                                               |
//|     - Signal 3 (M1 scalp): REMOVED - caused 41% WR & -59% loss  |
//|     - Signal 1: UNCHANGED (v120 exact, 92.94% WR proven)         |
//|     - Signal 2 NEW: M5 RSI(14) oversold recovery cross (>35)     |
//|       H1 RSI gate required + H4 Bull direction                   |
//|       RSI was <35 two bars ago, now crossed above 35             |
//|       Risk 3%, SL=1.5x ATR, TP=BB midline                       |
//|     - Signal 3 NEW: M5 RSI(7) extreme oversold (<22)             |
//|       Requires strong H1 RSI gate (50-80) for high confidence    |
//|       Risk 2%, SL=1.2x ATR, TP=1.0x ATR (tight quick exit)      |
//|     - All signals share H1 RSI gate for WR protection            |
//+------------------------------------------------------------------+
#property copyright ""
#property link      ""
#property version   "132.0"
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

//--- H1 RSI Gate (v120 proven values)
input string H1RSI_SET          = "============"; //====== H1 RSI Gate ======
input int    H1_RSI_Period      = 14;             //H1 RSI period
input double H1_RSI_Min         = 45.0;           //H1 RSI min for BUY (bull zone)
input double H1_RSI_Max         = 75.0;           //H1 RSI max for BUY (not overbought)
input double H1_RSI_Min_Sell    = 25.0;           //H1 RSI min for SELL (not oversold)
input double H1_RSI_Max_Sell    = 55.0;           //H1 RSI max for SELL (bear zone)

//--- H1 RSI Gate for Signal 3 (tighter, higher confidence)
input double H1_RSI_S3_Min      = 50.0;           //H1 RSI min for S3 BUY (strong bull)
input double H1_RSI_S3_Max      = 80.0;           //H1 RSI max for S3 BUY
input double H1_RSI_S3_Min_Sell = 20.0;           //H1 RSI min for S3 SELL
input double H1_RSI_S3_Max_Sell = 50.0;           //H1 RSI max for S3 SELL (strong bear)

//--- Bollinger Bands (M5)
input string BB_SET             = "============"; //====== BB Settings ======
input int    BB_Period          = 20;             //BB period
input double BB_Dev             = 2.5;            //BB standard deviation
input double TP_Min_ATR         = 0.5;            //Min TP as ATR multiple (Signal 1)

//--- Signal 1: M5 BB Touch (v120 exact)
input string S1_SET             = "============"; //====== Signal 1: BB Touch (v120 exact) ======
input int    RSI_Period         = 14;             //M5 RSI period
input double RSI_Buy            = 40.0;           //M5 RSI max for BUY
input double RSI_Sell           = 60.0;           //M5 RSI min for SELL
input int    Stoch_K            = 5;              //Stochastic K period
input int    Stoch_D            = 3;              //Stochastic D period
input int    Stoch_Slowing      = 3;              //Stochastic slowing
input double Stoch_OS           = 25.0;           //Stochastic oversold (buy)
input double Stoch_OB           = 75.0;           //Stochastic overbought (sell)
input double Body_Pct           = 0.2;            //Min body fraction of candle range
input int    Min_Bar_Gap        = 1;              //Min M5 bars between S1 entries

//--- Signal 2: M5 RSI Recovery Cross
input string S2_SET             = "============"; //====== Signal 2: RSI Recovery Cross ======
input bool   Use_S2             = true;           //Enable Signal 2
input double S2_RSI_Level       = 35.0;           //RSI cross-up level (was below, now above)
input double S2_RSI_Sell_Level  = 65.0;           //RSI cross-down level for SELL
input double S2_Risk_Pct        = 3.0;            //Risk % per S2 trade
input int    S2_Magic           = 1402026;        //Magic Number Signal 2
input int    S2_Min_Bar_Gap     = 2;              //Min M5 bars between S2 entries

//--- Signal 3: M5 Fast RSI Extreme
input string S3_SET             = "============"; //====== Signal 3: Fast RSI Extreme ======
input bool   Use_S3             = true;           //Enable Signal 3
input int    S3_RSI_Period      = 7;              //M5 RSI(7) period
input double S3_RSI_Buy         = 22.0;           //RSI(7) extreme oversold (buy)
input double S3_RSI_Sell        = 78.0;           //RSI(7) extreme overbought (sell)
input double S3_Risk_Pct        = 2.0;            //Risk % per S3 trade
input double S3_SL_Multi        = 1.2;            //SL = ATR x this (Signal 3)
input double S3_TP_Multi        = 1.0;            //TP = ATR x this (Signal 3)
input int    S3_Magic           = 1402028;        //Magic Number Signal 3
input int    S3_Min_Bar_Gap     = 1;              //Min M5 bars between S3 entries

//--- Exit Settings
input string EXIT_SET           = "============"; //====== Exit Settings ======
input int    ATR_Period         = 14;             //ATR period (M5)
input double ATR_SL_Multi       = 1.0;            //S1 SL = ATR x this
input double S2_SL_Multi        = 1.5;            //S2 SL = ATR x this
input double Trail_ATR_Multi    = 0.8;            //Trail SL offset (ATR units below BB mid)
input int    Max_Bars           = 100;            //Force-close after N M5 bars (S1 & S2)
input int    S3_Max_Bars        = 30;             //Force-close after N M5 bars (S3)

//--- Money Management
input string MONEY_SET          = "============"; //====== Money Management ======
input double Risk_Pct           = 5.0;            //Risk % per S1 trade
input double Fixed_Lot          = 0.0;            //Fixed lot (0 = use Risk_Pct)
input int    Max_Buys           = 1;              //Max concurrent S1 BUY positions
input int    Max_Sells          = 1;              //Max concurrent S1 SELL positions
input int    S2_Max_Buys        = 2;              //Max concurrent S2 BUY positions
input int    S2_Max_Sells       = 2;              //Max concurrent S2 SELL positions
input int    S3_Max_Buys        = 2;              //Max concurrent S3 BUY positions
input int    S3_Max_Sells       = 2;              //Max concurrent S3 SELL positions

//--- Safety
input string SAFETY_SET         = "============"; //====== Safety Settings ======
input int    MaxSpread          = 35;             //Max spread in points
input int    Slippage           = 30;             //Max slippage in points
input int    Magic_Number       = 1402025;        //Magic Number Signal 1
input string Order_Comment      = "BSv132";       //Order comment
input double Max_Daily_DD_Pct   = 15.0;           //Daily DD guard (% of equity)
input int    Max_Trades_Day     = 300;            //Max trades per day cap

//+------------------------------------------------------------------+
double   g_DayOpenEquity = 0;
bool     g_DailyDDHit   = false;
int      g_TradesToday  = 0;
datetime g_LastDay      = 0;

// Signal 1 trackers
datetime g_LastBuyTime1  = 0;
datetime g_LastSellTime1 = 0;
// Signal 2 trackers
datetime g_LastBuyTime2  = 0;
datetime g_LastSellTime2 = 0;
// Signal 3 trackers
datetime g_LastBuyTime3  = 0;
datetime g_LastSellTime3 = 0;

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
double CalcLots(double slDist, double riskPct, double riskScale = 1.0)
{
   if(Fixed_Lot > 0) return NormalizeDouble(Fixed_Lot, 2);
   double tickVal  = MarketInfo(Symbol(), MODE_TICKVALUE);
   double tickSize = MarketInfo(Symbol(), MODE_TICKSIZE);
   if(tickVal <= 0 || tickSize <= 0) return MarketInfo(Symbol(), MODE_MINLOT);
   double riskAmt  = AccountEquity() * (riskPct * riskScale) / 100.0;
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
      if(OrderSymbol() != Symbol()) continue;
      int mg = OrderMagicNumber();
      if(mg != Magic_Number && mg != S2_Magic && mg != S3_Magic) continue;
      if(OrderType() == OP_BUY)
         OrderClose(OrderTicket(), OrderLots(), Bid, Slippage, clrOrange);
      else if(OrderType() == OP_SELL)
         OrderClose(OrderTicket(), OrderLots(), Ask, Slippage, clrOrange);
   }
}

//+------------------------------------------------------------------+
void ManageExitForOrder(int tkt, int type, int magic,
                        double openPrice, double currentSL,
                        double atr, double bbMid, int maxBars)
{
   // S3: fixed TP set on OrderSend, only time-based exit here
   if(magic == S3_Magic)
   {
      if(iBarShift(NULL, 0, OrderOpenTime(), false) >= maxBars)
      {
         if(type == OP_BUY)  OrderClose(tkt, OrderLots(), Bid, Slippage, clrYellow);
         if(type == OP_SELL) OrderClose(tkt, OrderLots(), Ask, Slippage, clrYellow);
      }
      return;
   }

   // S1 & S2: partial close at BB mid + trailing stop
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
         return;
      }

      if(partialDone)
      {
         double trailSL = NormalizeDouble(bbMid - Trail_ATR_Multi * atr, Digits);
         if(trailSL > currentSL)
            OrderModify(tkt, openPrice, trailSL, 0, 0, clrBlue);
      }

      if(iBarShift(NULL, 0, OrderOpenTime(), false) >= maxBars)
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
         return;
      }

      if(partialDone)
      {
         double trailSL = NormalizeDouble(bbMid + Trail_ATR_Multi * atr, Digits);
         if(trailSL < currentSL)
            OrderModify(tkt, openPrice, trailSL, 0, 0, clrBlue);
      }

      if(iBarShift(NULL, 0, OrderOpenTime(), false) >= maxBars)
         OrderClose(tkt, OrderLots(), Ask, Slippage, clrYellow);
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
      int mg = OrderMagicNumber();
      if(mg != Magic_Number && mg != S2_Magic && mg != S3_Magic) continue;

      int maxBars = (mg == S3_Magic) ? S3_Max_Bars : Max_Bars;
      ManageExitForOrder(OrderTicket(), OrderType(), mg,
                         OrderOpenPrice(), OrderStopLoss(),
                         atr, bbMid, maxBars);
   }
}

//+------------------------------------------------------------------+
void OnTick()
{
   // M5 bar tracker
   static datetime s_LastBar = 0;
   bool isNewBar = (Time[0] != s_LastBar);
   if(isNewBar) s_LastBar = Time[0];

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

   // Only fire new entries on a new M5 bar
   if(!isNewBar) return;

   // Session and spread checks
   bool inSession = (dt.hour >= Session_Start_Hour && dt.hour < Session_End_Hour);
   if(!inSession) return;
   bool spreadOK = (MarketInfo(Symbol(), MODE_SPREAD) <= MaxSpread);
   if(!spreadOK) return;
   if(g_TradesToday >= Max_Trades_Day) return;

   // Shared indicators (computed once per new bar)
   double h4_ema  = iMA(NULL, PERIOD_H4, H4_EMA_Period, 0, MODE_EMA, PRICE_CLOSE, 0);
   double h1_ema  = iMA(NULL, PERIOD_H1, H1_EMA_Period, 0, MODE_EMA, PRICE_CLOSE, 0);
   double h1_rsi1 = iRSI(NULL, PERIOD_H1, H1_RSI_Period, PRICE_CLOSE, 1);

   bool h4Bull = (iClose(NULL, PERIOD_H4, 0) > h4_ema);
   bool h4Bear = (iClose(NULL, PERIOD_H4, 0) < h4_ema);

   // Standard H1 gate (for S1 and S2)
   bool h1Bull = (iClose(NULL, PERIOD_H1, 1) > h1_ema)
              && (h1_rsi1 >= H1_RSI_Min) && (h1_rsi1 <= H1_RSI_Max);
   bool h1Bear = (iClose(NULL, PERIOD_H1, 1) < h1_ema)
              && (h1_rsi1 >= H1_RSI_Min_Sell) && (h1_rsi1 <= H1_RSI_Max_Sell);

   // Tight H1 gate for S3 (requires stronger momentum)
   bool h1BullS3 = (iClose(NULL, PERIOD_H1, 1) > h1_ema)
                && (h1_rsi1 >= H1_RSI_S3_Min) && (h1_rsi1 <= H1_RSI_S3_Max);
   bool h1BearS3 = (iClose(NULL, PERIOD_H1, 1) < h1_ema)
                && (h1_rsi1 >= H1_RSI_S3_Min_Sell) && (h1_rsi1 <= H1_RSI_S3_Max_Sell);

   double atr1    = iATR(NULL, 0, ATR_Period, 1);
   if(atr1 <= 0) return;

   double bbMid0   = iBands(NULL, 0, BB_Period, BB_Dev, 0, PRICE_CLOSE, MODE_MAIN,  0);
   double bbLower1 = iBands(NULL, 0, BB_Period, BB_Dev, 0, PRICE_CLOSE, MODE_LOWER, 1);
   double bbUpper1 = iBands(NULL, 0, BB_Period, BB_Dev, 0, PRICE_CLOSE, MODE_UPPER, 1);

   double rsi1     = iRSI(NULL, 0, RSI_Period, PRICE_CLOSE, 1);
   double rsi2     = iRSI(NULL, 0, RSI_Period, PRICE_CLOSE, 2);
   double stochK1  = iStochastic(NULL, 0, Stoch_K, Stoch_D, Stoch_Slowing, MODE_SMA, 0, MODE_MAIN,   1);
   double stochD1  = iStochastic(NULL, 0, Stoch_K, Stoch_D, Stoch_Slowing, MODE_SMA, 0, MODE_SIGNAL, 1);

   // RSI(7) for Signal 3
   double rsi7_1 = iRSI(NULL, 0, S3_RSI_Period, PRICE_CLOSE, 1);

   double riskScale = GetRiskScale();

   //=== Signal 1: M5 BB Touch (v120 exact, 92.94% WR) ===
   if(h4Bull && h1Bull)
   {
      bool bbTouch   = (Low[1] <= bbLower1) && (Close[1] > bbLower1);
      bool rsiOS     = (rsi1 < RSI_Buy);
      bool rsiRising = (rsi1 > rsi2);
      bool stochOS   = (stochK1 < Stoch_OS) && (stochD1 < Stoch_OS);
      double candleRange = High[1] - Low[1];
      double candleBody  = Close[1] - Open[1];
      bool bullBody  = (candleBody > 0) && (candleRange > 0) && (candleBody >= Body_Pct * candleRange);

      if(bbTouch && rsiOS && rsiRising && stochOS && bullBody)
      {
         double slDist  = ATR_SL_Multi * atr1;
         double tpDist  = bbMid0 - Ask;
         double minTP   = TP_Min_ATR * atr1;

         if(tpDist >= minTP)
         {
            int openBuys  = CountTradesByMagic(OP_BUY, Magic_Number);
            int barsSince = (int)((Time[0] - g_LastBuyTime1) / PeriodSeconds());

            if(openBuys < Max_Buys && barsSince >= Min_Bar_Gap)
            {
               double entry = NormalizeDouble(Ask, Digits);
               double lots  = CalcLots(slDist, Risk_Pct, riskScale);
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
      double candleRange = High[1] - Low[1];
      double candleBody  = Close[1] - Open[1];
      bool bearBody   = (candleBody < 0) && (candleRange > 0) && (MathAbs(candleBody) >= Body_Pct * candleRange);

      if(bbTouchUp && rsiOB && rsiFalling && stochOB && bearBody)
      {
         double slDist  = ATR_SL_Multi * atr1;
         double tpDist  = Bid - bbMid0;
         double minTP   = TP_Min_ATR * atr1;

         if(tpDist >= minTP)
         {
            int openSells = CountTradesByMagic(OP_SELL, Magic_Number);
            int barsSince = (int)((Time[0] - g_LastSellTime1) / PeriodSeconds());

            if(openSells < Max_Sells && barsSince >= Min_Bar_Gap)
            {
               double entry = NormalizeDouble(Bid, Digits);
               double lots  = CalcLots(slDist, Risk_Pct, riskScale);
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

   //=== Signal 2: M5 RSI Recovery Cross (was below level, now above) ===
   if(Use_S2)
   {
      // BUY: H1 Bull + RSI crossed up through S2_RSI_Level
      if(h4Bull && h1Bull)
      {
         bool rsiCrossUp = (rsi2 < S2_RSI_Level) && (rsi1 >= S2_RSI_Level);

         if(rsiCrossUp)
         {
            int openBuys  = CountTradesByMagic(OP_BUY, S2_Magic);
            int barsSince = (int)((Time[0] - g_LastBuyTime2) / PeriodSeconds());

            if(openBuys < S2_Max_Buys && barsSince >= S2_Min_Bar_Gap)
            {
               double slDist = S2_SL_Multi * atr1;
               double entry  = NormalizeDouble(Ask, Digits);
               double lots   = CalcLots(slDist, S2_Risk_Pct, 1.0);
               if(lots > 0)
               {
                  int tkt = OrderSend(Symbol(), OP_BUY, lots, entry, Slippage,
                                      NormalizeDouble(entry - slDist, Digits),
                                      0, Order_Comment, S2_Magic, 0, clrLime);
                  if(tkt > 0) { g_TradesToday++; g_LastBuyTime2 = Time[0]; }
               }
            }
         }
      }

      // SELL: H1 Bear + RSI crossed down through S2_RSI_Sell_Level
      if(h4Bear && h1Bear)
      {
         bool rsiCrossDown = (rsi2 > S2_RSI_Sell_Level) && (rsi1 <= S2_RSI_Sell_Level);

         if(rsiCrossDown)
         {
            int openSells = CountTradesByMagic(OP_SELL, S2_Magic);
            int barsSince = (int)((Time[0] - g_LastSellTime2) / PeriodSeconds());

            if(openSells < S2_Max_Sells && barsSince >= S2_Min_Bar_Gap)
            {
               double slDist = S2_SL_Multi * atr1;
               double entry  = NormalizeDouble(Bid, Digits);
               double lots   = CalcLots(slDist, S2_Risk_Pct, 1.0);
               if(lots > 0)
               {
                  int tkt = OrderSend(Symbol(), OP_SELL, lots, entry, Slippage,
                                      NormalizeDouble(entry + slDist, Digits),
                                      0, Order_Comment, S2_Magic, 0, clrTomato);
                  if(tkt > 0) { g_TradesToday++; g_LastSellTime2 = Time[0]; }
               }
            }
         }
      }
   }

   //=== Signal 3: M5 RSI(7) Extreme with Tight H1 Gate ===
   if(Use_S3)
   {
      double slDist3 = S3_SL_Multi * atr1;
      double tpDist3 = S3_TP_Multi * atr1;

      // BUY: Strong H1 Bull (RSI 50-80) + M5 RSI(7) very oversold (<22)
      if(h4Bull && h1BullS3 && rsi7_1 < S3_RSI_Buy)
      {
         int openBuys  = CountTradesByMagic(OP_BUY, S3_Magic);
         int barsSince = (int)((Time[0] - g_LastBuyTime3) / PeriodSeconds());

         if(openBuys < S3_Max_Buys && barsSince >= S3_Min_Bar_Gap)
         {
            double entry = NormalizeDouble(Ask, Digits);
            double sl3   = NormalizeDouble(entry - slDist3, Digits);
            double tp3   = NormalizeDouble(entry + tpDist3, Digits);
            double lots  = CalcLots(slDist3, S3_Risk_Pct, 1.0);
            if(lots > 0)
            {
               int tkt = OrderSend(Symbol(), OP_BUY, lots, entry, Slippage,
                                   sl3, tp3, Order_Comment, S3_Magic, 0, clrAqua);
               if(tkt > 0) { g_TradesToday++; g_LastBuyTime3 = Time[0]; }
            }
         }
      }

      // SELL: Strong H1 Bear (RSI 20-50) + M5 RSI(7) very overbought (>78)
      if(h4Bear && h1BearS3 && rsi7_1 > S3_RSI_Sell)
      {
         int openSells = CountTradesByMagic(OP_SELL, S3_Magic);
         int barsSince = (int)((Time[0] - g_LastSellTime3) / PeriodSeconds());

         if(openSells < S3_Max_Sells && barsSince >= S3_Min_Bar_Gap)
         {
            double entry = NormalizeDouble(Bid, Digits);
            double sl3   = NormalizeDouble(entry + slDist3, Digits);
            double tp3   = NormalizeDouble(entry - tpDist3, Digits);
            double lots  = CalcLots(slDist3, S3_Risk_Pct, 1.0);
            if(lots > 0)
            {
               int tkt = OrderSend(Symbol(), OP_SELL, lots, entry, Slippage,
                                   sl3, tp3, Order_Comment, S3_Magic, 0, clrOrchid);
               if(tkt > 0) { g_TradesToday++; g_LastSellTime3 = Time[0]; }
            }
         }
      }
   }
}
//+------------------------------------------------------------------+
