//+------------------------------------------------------------------+
//|   Buy & Sell EA v130 - Dual Signal (BB Touch + EMA Cross)        |
//|   Framework: 4H Direction / 1H Structure / 5M Entry             |
//|   Base: v129                                                     |
//|   Changes vs v129:                                               |
//|     - Signal 1: ALL filters reverted to v120 exact values        |
//|       RSI_Buy=40, RSI_Sell=60, Stoch_OS=25, Stoch_OB=75         |
//|       ATR_SL_Multi=1.0, Risk_Pct=5.0                             |
//|     - TARGETED CHANGE: H1 RSI removed from h1Bull/h1Bear         |
//|       Signal 1 now fires whenever H1 price > EMA (no RSI gate)   |
//|       This is the only structural change vs v120 + Signal 2       |
//|     - Signal 2 unchanged (EMA Cross + ATR-based TP from v129)    |
//+------------------------------------------------------------------+
#property copyright ""
#property link      ""
#property version   "140.0"
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

//--- Bollinger Bands (M5) - Signal 1
input string BB_SET             = "============"; //====== BB Touch Signal (Signal 1) ======
input int    BB_Period          = 20;             //BB period
input double BB_Dev             = 2.5;            //BB SD
input double TP_Min_ATR         = 0.5;            //Min TP distance as ATR multiple (Signal 1)

//--- Entry Signal 1: BB Touch confirmation (v120 exact values)
input string ENTRY_SET          = "============"; //====== BB Touch Filters ======
input int    RSI_Period         = 14;             //M5 RSI period
input double RSI_Buy            = 40.0;           //M5 RSI max for BUY oversold
input double RSI_Sell           = 60.0;           //M5 RSI min for SELL overbought
input int    Stoch_K            = 5;              //Stochastic K period
input int    Stoch_D            = 3;              //Stochastic D period
input int    Stoch_Slowing      = 3;              //Stochastic slowing
input double Stoch_OS           = 25.0;           //Stochastic oversold level buy
input double Stoch_OB           = 75.0;           //Stochastic overbought level sell
input double Body_Pct           = 0.2;            //Min body as fraction of candle range
input int    Min_Bar_Gap        = 1;              //Min bars between entries (Signal 1)
input double Price_Gap_ATR      = 0.3;            //Min ATR gap between entries (same dir)

//--- Signal 2: EMA Crossover (independent magic)
input string EMA_SET            = "============"; //====== EMA Cross Signal (Signal 2) ======
input bool   Use_EMA_Cross      = true;           //Enable EMA crossover signal
input int    EMA_Fast_Period    = 9;              //Fast EMA period (M5)
input int    EMA_Slow_Period    = 21;             //Slow EMA period (M5)
input double TP2_ATR_Multi      = 1.5;            //Signal 2 TP = entry +/- this * ATR
input int    Min_Bar_Gap2       = 1;              //Min bars between Signal 2 entries

//--- Exit
input string EXIT_SET           = "============"; //====== Exit Settings ======
input int    ATR_Period         = 14;             //ATR period
input double ATR_SL_Multi       = 1.0;            //SL = ATR x this
input double Trail_ATR_Multi    = 0.8;            //Trail SL offset from BB mid (ATR multiples)
input int    Max_Bars           = 100;            //Force close after N bars

//--- Money Management
input string MONEY_SET          = "============"; //====== Money Management ======
input double Risk_Pct           = 5.0;            //Risk % per trade
input double Fixed_Lot          = 0.0;            //Fixed lot (0 = use Risk_Pct)
input int    Max_Buys           = 1;              //Max concurrent BUY per signal
input int    Max_Sells          = 1;              //Max concurrent SELL per signal

//--- Safety
input string SAFETY_SET         = "============"; //====== Safety Settings ======
input int    MaxSpread          = 35;             //Max spread in points
input int    Slippage           = 30;             //Max slippage in points
input int    Magic_Number       = 1402025;        //Magic Number (Signal 1)
input string Order_Comment      = "BSv140";       //Order comment
input double Max_Daily_DD_Pct   = 15.0;           //Daily drawdown guard (% of equity)
input int    Max_Trades_Day     = 80;             //Max trades per day

//+------------------------------------------------------------------+
double   g_DayOpenEquity  = 0;
bool     g_DailyDDHit     = false;
int      g_TradesToday    = 0;
datetime g_LastDay        = 0;

// Signal 1 trackers
datetime g_LastBuyTime1   = 0;
datetime g_LastSellTime1  = 0;

// Signal 2 trackers (independent)
datetime g_LastBuyTime2   = 0;
datetime g_LastSellTime2  = 0;

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
         if(OrderMagicNumber() != Magic_Number && OrderMagicNumber() != Magic_Number + 1) continue;
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
   static datetime s_LastBar = 0;
   bool isNewBar = (Time[0] != s_LastBar);
   if(isNewBar) s_LastBar = Time[0];

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

   if(!isNewBar) return;

   if(dt.hour < Session_Start_Hour || dt.hour >= Session_End_Hour) return;
   if(g_TradesToday >= Max_Trades_Day) return;
   if(MarketInfo(Symbol(), MODE_SPREAD) > MaxSpread) return;

   double atr1 = iATR(NULL, 0, ATR_Period, 1);
   if(atr1 <= 0) return;

   double h4_ema  = iMA(NULL, PERIOD_H4, H4_EMA_Period, 0, MODE_EMA, PRICE_CLOSE, 0);
   double h1_ema  = iMA(NULL, PERIOD_H1, H1_EMA_Period, 0, MODE_EMA, PRICE_CLOSE, 0);

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

   bool h4Bull = (iClose(NULL, PERIOD_H4, 0) > h4_ema);
   bool h4Bear = (iClose(NULL, PERIOD_H4, 0) < h4_ema);

   // H1 condition: price vs EMA only (RSI gate removed — the single structural change vs v120)
   bool h1Bull = (iClose(NULL, PERIOD_H1, 1) > h1_ema);
   bool h1Bear = (iClose(NULL, PERIOD_H1, 1) < h1_ema);

   //=== Signal 1: BB Touch (mean-reversion, v120 exact quality filters) ===
   if(h4Bull && h1Bull)
   {
      bool bbTouch   = (Low[1] <= bbLower1) && (Close[1] > bbLower1);
      bool rsiOS     = (rsi1 < RSI_Buy);
      bool rsiRising = (rsi1 > rsi2);
      bool stochOS   = (stochK1 < Stoch_OS) && (stochD1 < Stoch_OS);
      bool bullBody  = (candleBody > 0) && (candleRange > 0) && (candleBody >= Body_Pct * candleRange);

      if(bbTouch && rsiOS && rsiRising && stochOS && bullBody)
      {
         double entry  = NormalizeDouble(Ask, Digits);
         double tpDist = bbMid0 - entry;
         if(tpDist >= minTP)
         {
            int openBuys  = CountTradesByMagic(OP_BUY, Magic_Number);
            int barsSince = (int)((Time[0] - g_LastBuyTime1) / PeriodSeconds());

            if(openBuys < Max_Buys && barsSince >= Min_Bar_Gap)
            {
               double lots = CalcLots(slDist, riskScale);
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
         double entry  = NormalizeDouble(Bid, Digits);
         double tpDist = entry - bbMid0;
         if(tpDist >= minTP)
         {
            int openSells = CountTradesByMagic(OP_SELL, Magic_Number);
            int barsSince = (int)((Time[0] - g_LastSellTime1) / PeriodSeconds());

            if(openSells < Max_Sells && barsSince >= Min_Bar_Gap)
            {
               double lots = CalcLots(slDist, riskScale);
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

   //=== Signal 2: EMA Crossover (Magic_Number+1, ATR-based TP) ===
   if(Use_EMA_Cross)
   {
      int magic2 = Magic_Number + 1;

      double ema_fast1 = iMA(NULL, 0, EMA_Fast_Period, 0, MODE_EMA, PRICE_CLOSE, 1);
      double ema_fast2 = iMA(NULL, 0, EMA_Fast_Period, 0, MODE_EMA, PRICE_CLOSE, 2);
      double ema_slow1 = iMA(NULL, 0, EMA_Slow_Period, 0, MODE_EMA, PRICE_CLOSE, 1);
      double ema_slow2 = iMA(NULL, 0, EMA_Slow_Period, 0, MODE_EMA, PRICE_CLOSE, 2);

      bool emaBullCross = (ema_fast1 > ema_slow1) && (ema_fast2 <= ema_slow2);
      bool emaBearCross = (ema_fast1 < ema_slow1) && (ema_fast2 >= ema_slow2);

      bool h1AboveEMA = (iClose(NULL, PERIOD_H1, 1) > h1_ema);
      bool h1BelowEMA = (iClose(NULL, PERIOD_H1, 1) < h1_ema);

      if(emaBullCross && h4Bull && h1AboveEMA)
      {
         int openBuys  = CountTradesByMagic(OP_BUY, magic2);
         int barsSince = (int)((Time[0] - g_LastBuyTime2) / PeriodSeconds());

         if(openBuys < Max_Buys && barsSince >= Min_Bar_Gap2)
         {
            double entry = NormalizeDouble(Ask, Digits);
            double sl2   = NormalizeDouble(entry - slDist, Digits);
            double tp2   = NormalizeDouble(entry + TP2_ATR_Multi * atr1, Digits);
            double lots  = CalcLots(slDist, riskScale);
            if(lots > 0)
            {
               int tkt = OrderSend(Symbol(), OP_BUY, lots, entry, Slippage,
                                   sl2, tp2, Order_Comment, magic2, 0, clrLime);
               if(tkt > 0) { g_TradesToday++; g_LastBuyTime2 = Time[0]; }
            }
         }
      }

      if(emaBearCross && h4Bear && h1BelowEMA)
      {
         int openSells = CountTradesByMagic(OP_SELL, magic2);
         int barsSince = (int)((Time[0] - g_LastSellTime2) / PeriodSeconds());

         if(openSells < Max_Sells && barsSince >= Min_Bar_Gap2)
         {
            double entry = NormalizeDouble(Bid, Digits);
            double sl2   = NormalizeDouble(entry + slDist, Digits);
            double tp2   = NormalizeDouble(entry - TP2_ATR_Multi * atr1, Digits);
            double lots  = CalcLots(slDist, riskScale);
            if(lots > 0)
            {
               int tkt = OrderSend(Symbol(), OP_SELL, lots, entry, Slippage,
                                   sl2, tp2, Order_Comment, magic2, 0, clrOrangeRed);
               if(tkt > 0) { g_TradesToday++; g_LastSellTime2 = Time[0]; }
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
      if(OrderMagicNumber() != Magic_Number && OrderMagicNumber() != Magic_Number + 1) continue;

      int    tkt       = OrderTicket();
      double openPrice = OrderOpenPrice();
      double currentSL = OrderStopLoss();
      int    type      = OrderType();

      // Signal 2: TP set in OrderSend, only apply time-based exit
      if(OrderMagicNumber() == Magic_Number + 1)
      {
         if(iBarShift(NULL, 0, OrderOpenTime(), false) >= Max_Bars)
         {
            if(type == OP_BUY)  OrderClose(tkt, OrderLots(), Bid, Slippage, clrYellow);
            if(type == OP_SELL) OrderClose(tkt, OrderLots(), Ask, Slippage, clrYellow);
         }
         continue;
      }

      // Signal 1 exit logic (BB mid partial close + trail)
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
      if(OrderMagicNumber() != Magic_Number && OrderMagicNumber() != Magic_Number + 1) continue;
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
