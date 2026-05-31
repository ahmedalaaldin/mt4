//+------------------------------------------------------------------+
//|   Buy & Sell EA v44 - v35 Signal + BUY STOP Breakout Entry     |
//|   Entry: H1 EMA200 + H1 RSI 50-75 + BB 2.5SD lower touch      |
//|          + M5 RSI<40 + Stoch K&D<25                             |
//|          → BUY STOP at bar[1].High (breakout confirmation)      |
//|   Exit: TP = BB mid, SL below bar[1].Low                       |
//|   Goal: Better WR via confirmed breakout, no bullish close req  |
//+------------------------------------------------------------------+
#property copyright ""
#property link      ""
#property version   "44.0"
#property strict

#include <stdlib.mqh>

//--- Session
input string SESSION_SET        = "============"; //====== Session Settings ======
input int    Session_Start_Hour = 7;              //Session Start Hour (server time)
input int    Session_End_Hour   = 20;             //Session End Hour (server time)

//--- Trend Filter
input string TREND_SET          = "============"; //====== Trend Filter ======
input int    H1_EMA_Period      = 200;            //H1 EMA period
input int    H1_RSI_Period      = 14;             //H1 RSI period
input double H1_RSI_Min         = 50.0;           //H1 RSI min
input double H1_RSI_Max         = 75.0;           //H1 RSI max

//--- Bollinger Bands
input string BB_SET             = "============"; //====== Bollinger Band Settings ======
input int    BB_Period          = 20;             //BB period
input double BB_Dev             = 2.5;            //BB standard deviations (optimal)
input double TP_Min_ATR         = 0.5;            //Min TP as ATR multiple

//--- Entry Signal
input string ENTRY_SET          = "============"; //====== Entry Settings ======
input int    RSI_Period         = 14;             //M5 RSI period
input double RSI_Buy            = 40.0;           //M5 RSI must be below this
input int    Stoch_K            = 5;              //Stochastic K period
input int    Stoch_D            = 3;              //Stochastic D period
input int    Stoch_Slowing      = 3;              //Stochastic slowing
input double Stoch_OB           = 25.0;           //Stochastic oversold level
input double Stop_Buffer        = 0.1;            //BUY STOP buffer above bar[1].High (x ATR)
input int    Pending_Expiry     = 6;              //Pending order expiry in bars
input int    Min_Bar_Gap        = 2;              //Min bars between new signal entries
input double Price_Gap_ATR      = 0.3;            //Min ATR gap between same-dir entries

//--- Exit
input string EXIT_SET           = "============"; //====== Exit Settings ======
input int    ATR_Period         = 14;             //ATR Period
input double ATR_SL_Multi       = 1.0;            //SL below bar[1].Low (x ATR)
input int    Max_Bars           = 40;             //Force close after N bars

//--- Money Management
input string MONEY_SET          = "============"; //====== Money Management ======
input double Risk_Pct           = 2.0;            //Risk % per trade
input double Fixed_Lot          = 0.0;            //Fixed lot (0 = use Risk_Pct)
input int    Max_Buys           = 3;              //Max concurrent BUY/pending positions

//--- Safety
input string SAFETY_SET         = "============"; //====== Safety Settings ======
input int    MaxSpread          = 35;             //Max spread in points
input int    Slippage           = 30;             //Max slippage in points
input int    Magic_Number       = 442025;         //Magic Number
input string Order_Comment      = "BSv44";        //Order comment
input double Max_Daily_DD_Pct   = 4.0;            //Daily drawdown guard (% of equity)
input int    Max_Trades_Day     = 80;             //Max trades per day

//+------------------------------------------------------------------+
double   g_DayOpenEquity = 0;
bool     g_DailyDDHit    = false;
int      g_TradesToday   = 0;
datetime g_LastDay       = 0;
datetime g_LastSignalBar = 0;

//+------------------------------------------------------------------+
int OnInit()  { return(INIT_SUCCEEDED); }
void OnDeinit(const int reason) { CancelPendingOrders(); }

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
      if(ddPct >= Max_Daily_DD_Pct) { CloseAllTrades(); CancelPendingOrders(); g_DailyDDHit = true; return; }
   }
   if(g_DailyDDHit) return;

   if(!isNewBar) return;

   ManageExits();
   CleanInvalidPending();

   if(dt.hour < Session_Start_Hour || dt.hour >= Session_End_Hour) return;
   if(g_TradesToday >= Max_Trades_Day) return;
   if(MarketInfo(Symbol(), MODE_SPREAD) > MaxSpread) return;

   double atr1 = iATR(NULL, 0, ATR_Period, 1);
   if(atr1 <= 0) return;

   // Avoid duplicate signals on same bar
   if(Time[1] == g_LastSignalBar) return;

   double h1_ema   = iMA(NULL, PERIOD_H1, H1_EMA_Period, 0, MODE_EMA, PRICE_CLOSE, 0);
   double h1_rsi   = iRSI(NULL, PERIOD_H1, H1_RSI_Period, PRICE_CLOSE, 1);
   bool h1Trend    = (Close[1] > h1_ema) && (h1_rsi >= H1_RSI_Min) && (h1_rsi <= H1_RSI_Max);
   if(!h1Trend) return;

   double bbMid0   = iBands(NULL, 0, BB_Period, BB_Dev, 0, PRICE_CLOSE, MODE_MAIN,  0);
   double bbLower1 = iBands(NULL, 0, BB_Period, BB_Dev, 0, PRICE_CLOSE, MODE_LOWER, 1);
   double rsi1     = iRSI(NULL, 0, RSI_Period, PRICE_CLOSE, 1);
   double stochK1  = iStochastic(NULL, 0, Stoch_K, Stoch_D, Stoch_Slowing, MODE_SMA, 0, MODE_MAIN,   1);
   double stochD1  = iStochastic(NULL, 0, Stoch_K, Stoch_D, Stoch_Slowing, MODE_SMA, 0, MODE_SIGNAL, 1);

   bool bbTouch = (Low[1] <= bbLower1) && (Close[1] > bbLower1);
   bool rsiOS   = (rsi1 < RSI_Buy);
   bool stochOS = (stochK1 < Stoch_OB) && (stochD1 < Stoch_OB);

   if(bbTouch && rsiOS && stochOS)
   {
      // BUY STOP price: just above bar[1].High
      double stopEntry = NormalizeDouble(High[1] + Stop_Buffer * atr1, Digits);
      double stopLoss  = NormalizeDouble(Low[1]  - ATR_SL_Multi * atr1, Digits);
      double slDist    = stopEntry - stopLoss;
      double tpPrice   = NormalizeDouble(bbMid0, Digits);
      double tpDist    = tpPrice - stopEntry;

      // Validate: stop must be above current Ask, TP must be above stop
      double minStopLevel = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
      if(stopEntry <= Ask + minStopLevel) return;
      if(tpDist < TP_Min_ATR * atr1) return;
      if(slDist <= 0) return;

      int totalPositions = CountTrades(OP_BUY) + CountPending(OP_BUYSTOP);
      int barsSince      = (int)((Time[0] - g_LastSignalBar) / PeriodSeconds());

      if(totalPositions < Max_Buys && barsSince >= Min_Bar_Gap)
      {
         if(totalPositions == 0 || HasEnoughDistance(stopEntry, atr1))
         {
            double lots    = CalcLots(slDist);
            datetime expiry = Time[0] + Pending_Expiry * PeriodSeconds();
            if(lots > 0)
            {
               int tkt = OrderSend(Symbol(), OP_BUYSTOP, lots, stopEntry, Slippage,
                                   stopLoss, tpPrice,
                                   Order_Comment, Magic_Number, expiry, clrGreen);
               if(tkt > 0) { g_TradesToday++; g_LastSignalBar = Time[1]; }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
void CleanInvalidPending()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != Magic_Number) continue;
      if(OrderType() != OP_BUYSTOP) continue;
      // Cancel if TP is now below Ask (signal direction invalidated, or price ran past TP without filling)
      if(OrderTakeProfit() > 0 && Ask > OrderTakeProfit())
         OrderDelete(OrderTicket(), clrRed);
   }
}

//+------------------------------------------------------------------+
void ManageExits()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != Magic_Number) continue;
      if(OrderType() != OP_BUY) continue;
      if(iBarShift(NULL, 0, OrderOpenTime(), false) < Max_Bars) continue;
      OrderClose(OrderTicket(), OrderLots(), Bid, Slippage, clrYellow);
   }
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
   }
}

//+------------------------------------------------------------------+
void CancelPendingOrders()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != Magic_Number) continue;
      if(OrderType() == OP_BUYSTOP || OrderType() == OP_BUYLIMIT)
         OrderDelete(OrderTicket(), clrOrange);
   }
}

//+------------------------------------------------------------------+
int CountTrades(int type)
{
   int n = 0;
   for(int i = 0; i < OrdersTotal(); i++)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() == Symbol() && OrderMagicNumber() == Magic_Number && OrderType() == type) n++;
   }
   return n;
}

//+------------------------------------------------------------------+
int CountPending(int type)
{
   int n = 0;
   for(int i = 0; i < OrdersTotal(); i++)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() == Symbol() && OrderMagicNumber() == Magic_Number && OrderType() == type) n++;
   }
   return n;
}

//+------------------------------------------------------------------+
bool HasEnoughDistance(double newPrice, double atr)
{
   double minDist = Price_Gap_ATR * atr;
   for(int i = 0; i < OrdersTotal(); i++)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != Magic_Number) continue;
      if(OrderType() != OP_BUY && OrderType() != OP_BUYSTOP) continue;
      double refPrice = (OrderType() == OP_BUY) ? OrderOpenPrice() : OrderOpenPrice();
      if(MathAbs(newPrice - refPrice) < minDist) return false;
   }
   return true;
}

//+------------------------------------------------------------------+
double CalcLots(double slDist)
{
   if(Fixed_Lot > 0) return NormalizeDouble(Fixed_Lot, 2);
   double tickVal  = MarketInfo(Symbol(), MODE_TICKVALUE);
   double tickSize = MarketInfo(Symbol(), MODE_TICKSIZE);
   if(tickVal <= 0 || tickSize <= 0) return MarketInfo(Symbol(), MODE_MINLOT);
   double riskAmt  = AccountEquity() * Risk_Pct / 100.0;
   double slTicks  = slDist / tickSize;
   double lots     = riskAmt / (slTicks * tickVal);
   double stepLot  = MarketInfo(Symbol(), MODE_LOTSTEP);
   double minLot   = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot   = MarketInfo(Symbol(), MODE_MAXLOT);
   lots = MathFloor(lots / stepLot) * stepLot;
   return NormalizeDouble(MathMax(minLot, MathMin(maxLot, lots)), 2);
}
//+------------------------------------------------------------------+
