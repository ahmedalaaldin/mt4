//+------------------------------------------------------------------+
//|   Buy & Sell EA v81 - Triple TF alignment + M5 RSI bounce       |
//|   Entry: D1 EMA200 + D1 RSI>55 + H4 EMA200 + H1 EMA200         |
//|          + H1 RSI 50-75 + M5 RSI crosses above 40               |
//|   Exit: TP = 0.5xATR, SL = 0.35xATR (1.43:1 R:R)               |
//|   Goal: 5-15 trades/day via triple-TF aligned RSI bounce        |
//|   Hypothesis: 3TF alignment -> 55%+ WR on any RSI dip bounce   |
//+------------------------------------------------------------------+
#property copyright ""
#property link      ""
#property version   "81.0"
#property strict

#include <stdlib.mqh>

//--- Session
input string SESSION_SET        = "============"; //====== Session Settings ======
input int    Session_Start_Hour = 7;              //Session Start Hour (server time)
input int    Session_End_Hour   = 20;             //Session End Hour (server time)

//--- Trend Filter (Triple Timeframe)
input string TREND_SET          = "============"; //====== Trend Filter ======
input int    D1_EMA_Period      = 200;            //D1 EMA period
input double D1_RSI_Min         = 55.0;           //D1 RSI minimum (strong daily uptrend)
input int    H4_EMA_Period      = 200;            //H4 EMA period
input int    H1_EMA_Period      = 200;            //H1 EMA period
input int    H1_RSI_Period      = 14;             //H1 RSI period
input double H1_RSI_Min         = 50.0;           //H1 RSI min
input double H1_RSI_Max         = 75.0;           //H1 RSI max

//--- Entry Signal (M5 RSI bounce)
input string ENTRY_SET          = "============"; //====== Entry Settings ======
input int    RSI_Period         = 14;             //M5 RSI period
input double RSI_Cross_Up       = 40.0;           //RSI cross-above level (was below, now above)
input int    Min_Bar_Gap        = 1;              //Min bars between entries
input double Price_Gap_ATR      = 0.2;            //Min ATR gap between same-dir entries

//--- Exit
input string EXIT_SET           = "============"; //====== Exit Settings ======
input int    ATR_Period         = 14;             //ATR Period
input double ATR_TP_Multi       = 0.5;            //TP = ATR x this
input double ATR_SL_Multi       = 0.35;           //SL = ATR x this
input int    Max_Bars           = 15;             //Force close after N bars (75 minutes)

//--- Money Management
input string MONEY_SET          = "============"; //====== Money Management ======
input double Risk_Pct           = 1.5;            //Risk % per trade (small, high frequency)
input double Fixed_Lot          = 0.0;            //Fixed lot (0 = use Risk_Pct)
input int    Max_Buys           = 10;             //Max concurrent BUY positions

//--- Safety
input string SAFETY_SET         = "============"; //====== Safety Settings ======
input int    MaxSpread          = 35;             //Max spread in points
input int    Slippage           = 30;             //Max slippage in points
input int    Magic_Number       = 812025;         //Magic Number
input string Order_Comment      = "BSv81";        //Order comment
input double Max_Daily_DD_Pct   = 10.0;           //Daily drawdown guard (% of equity)
input int    Max_Trades_Day     = 999;            //Max trades per day

//+------------------------------------------------------------------+
double   g_DayOpenEquity = 0;
bool     g_DailyDDHit    = false;
int      g_TradesToday   = 0;
datetime g_LastDay       = 0;
datetime g_LastBuyTime   = 0;

//+------------------------------------------------------------------+
int OnInit()  { return(INIT_SUCCEEDED); }
void OnDeinit(const int reason) {}

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

   if(!isNewBar) return;

   ManageExits();

   if(dt.hour < Session_Start_Hour || dt.hour >= Session_End_Hour) return;
   if(g_TradesToday >= Max_Trades_Day) return;
   if(MarketInfo(Symbol(), MODE_SPREAD) > MaxSpread) return;

   double atr1 = iATR(NULL, 0, ATR_Period, 1);
   if(atr1 <= 0) return;

   // Triple timeframe trend check
   double d1_ema  = iMA(NULL, PERIOD_D1, D1_EMA_Period, 0, MODE_EMA, PRICE_CLOSE, 0);
   double d1_rsi  = iRSI(NULL, PERIOD_D1, 14, PRICE_CLOSE, 1);
   double h4_ema  = iMA(NULL, PERIOD_H4, H4_EMA_Period, 0, MODE_EMA, PRICE_CLOSE, 0);
   double h1_ema  = iMA(NULL, PERIOD_H1, H1_EMA_Period, 0, MODE_EMA, PRICE_CLOSE, 0);
   double h1_rsi  = iRSI(NULL, PERIOD_H1, H1_RSI_Period, PRICE_CLOSE, 1);

   bool d1Trend = (Close[1] > d1_ema) && (d1_rsi >= D1_RSI_Min);
   bool h4Trend = (Close[1] > h4_ema);
   bool h1Trend = (Close[1] > h1_ema) && (h1_rsi >= H1_RSI_Min) && (h1_rsi <= H1_RSI_Max);

   if(!d1Trend || !h4Trend || !h1Trend) return;

   // M5 RSI crosses above cross level (bounce signal)
   double rsi1 = iRSI(NULL, 0, RSI_Period, PRICE_CLOSE, 1);
   double rsi2 = iRSI(NULL, 0, RSI_Period, PRICE_CLOSE, 2);

   bool rsiCrossUp = (rsi2 < RSI_Cross_Up) && (rsi1 >= RSI_Cross_Up);
   if(!rsiCrossUp) return;

   double slDist = ATR_SL_Multi * atr1;
   double tpDist = ATR_TP_Multi * atr1;
   if(tpDist <= slDist * 0.5) return;

   int openBuys  = CountTrades(OP_BUY);
   int barsSince = (int)((Time[0] - g_LastBuyTime) / PeriodSeconds());
   if(openBuys >= Max_Buys || barsSince < Min_Bar_Gap) return;
   if(openBuys > 0 && !HasEnoughDistance(OP_BUY, atr1)) return;

   double lots = CalcLots(slDist);
   if(lots <= 0) return;

   double entry = NormalizeDouble(Ask, Digits);
   int tkt = OrderSend(Symbol(), OP_BUY, lots, entry, Slippage,
                       NormalizeDouble(entry - slDist, Digits),
                       NormalizeDouble(entry + tpDist, Digits),
                       Order_Comment, Magic_Number, 0, clrGreen);
   if(tkt > 0) { g_TradesToday++; g_LastBuyTime = Time[0]; }
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
bool HasEnoughDistance(int type, double atr)
{
   double minDist  = Price_Gap_ATR * atr;
   double refPrice = (type == OP_BUY) ? Ask : Bid;
   for(int i = 0; i < OrdersTotal(); i++)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != Magic_Number) continue;
      if(OrderType() != type) continue;
      if(MathAbs(refPrice - OrderOpenPrice()) < minDist) return false;
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
