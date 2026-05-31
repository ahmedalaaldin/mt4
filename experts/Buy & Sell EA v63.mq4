//+------------------------------------------------------------------+
//|   Buy & Sell EA v74 - MACD crossover dual-direction              |
//|   Entry BUY:  H1 EMA200 up + H1 RSI 50-75 + MACD cross up       |
//|               + M5 RSI<55 (not overbought)                       |
//|   Entry SELL: H1 EMA200 dn + H1 RSI 25-50 + MACD cross down     |
//|               + M5 RSI>45 (not oversold)                         |
//|   Exit: TP = 1.2xATR, SL = 0.8xATR                              |
//|   Goal: 2-8 trades/day from MACD crossovers in H1 trend         |
//+------------------------------------------------------------------+
#property copyright ""
#property link      ""
#property version   "74.0"
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
input double H1_RSI_Bull_Min    = 50.0;           //H1 RSI min for uptrend
input double H1_RSI_Bull_Max    = 75.0;           //H1 RSI max for uptrend
input double H1_RSI_Bear_Min    = 25.0;           //H1 RSI min for downtrend
input double H1_RSI_Bear_Max    = 50.0;           //H1 RSI max for downtrend

//--- MACD Signal
input string MACD_SET           = "============"; //====== MACD Settings ======
input int    MACD_Fast          = 12;             //MACD fast EMA
input int    MACD_Slow          = 26;             //MACD slow EMA
input int    MACD_Signal        = 9;              //MACD signal period
input double RSI_Buy_Max        = 55.0;           //M5 RSI must be below this for BUY
input double RSI_Sell_Min       = 45.0;           //M5 RSI must be above this for SELL
input int    RSI_Period         = 14;             //M5 RSI period
input int    Min_Bar_Gap        = 3;              //Min bars between same-dir entries
input double Price_Gap_ATR      = 0.2;            //Min ATR gap between same-dir entries

//--- Exit
input string EXIT_SET           = "============"; //====== Exit Settings ======
input int    ATR_Period         = 14;             //ATR Period
input double ATR_TP_Multi       = 1.2;            //TP = ATR x this
input double ATR_SL_Multi       = 0.8;            //SL = ATR x this
input int    Max_Bars           = 30;             //Force close after N bars (150 min)

//--- Money Management
input string MONEY_SET          = "============"; //====== Money Management ======
input double Risk_Pct           = 3.0;            //Risk % per trade
input double Fixed_Lot          = 0.0;            //Fixed lot (0 = use Risk_Pct)
input int    Max_Buys           = 3;              //Max concurrent BUY positions
input int    Max_Sells          = 3;              //Max concurrent SELL positions

//--- Safety
input string SAFETY_SET         = "============"; //====== Safety Settings ======
input int    MaxSpread          = 35;             //Max spread in points
input int    Slippage           = 30;             //Max slippage in points
input int    Magic_Number       = 742025;         //Magic Number
input string Order_Comment      = "BSv74";        //Order comment
input double Max_Daily_DD_Pct   = 10.0;           //Daily drawdown guard (% of equity)
input int    Max_Trades_Day     = 999;            //Max trades per day

//+------------------------------------------------------------------+
double   g_DayOpenEquity = 0;
bool     g_DailyDDHit    = false;
int      g_TradesToday   = 0;
datetime g_LastDay       = 0;
datetime g_LastBuyTime   = 0;
datetime g_LastSellTime  = 0;

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

   double h1_ema = iMA(NULL, PERIOD_H1, H1_EMA_Period, 0, MODE_EMA, PRICE_CLOSE, 0);
   double h1_rsi = iRSI(NULL, PERIOD_H1, H1_RSI_Period, PRICE_CLOSE, 1);

   double macdMain1   = iMACD(NULL, 0, MACD_Fast, MACD_Slow, MACD_Signal, PRICE_CLOSE, MODE_MAIN,   1);
   double macdMain2   = iMACD(NULL, 0, MACD_Fast, MACD_Slow, MACD_Signal, PRICE_CLOSE, MODE_MAIN,   2);
   double macdSignal1 = iMACD(NULL, 0, MACD_Fast, MACD_Slow, MACD_Signal, PRICE_CLOSE, MODE_SIGNAL, 1);
   double macdSignal2 = iMACD(NULL, 0, MACD_Fast, MACD_Slow, MACD_Signal, PRICE_CLOSE, MODE_SIGNAL, 2);

   double rsi1 = iRSI(NULL, 0, RSI_Period, PRICE_CLOSE, 1);

   double slDist = ATR_SL_Multi * atr1;
   double tpDist = ATR_TP_Multi * atr1;
   if(tpDist <= slDist * 0.5) return;

   // BUY signal: uptrend + MACD crosses above signal
   bool h1Bull = (Close[1] > h1_ema) && (h1_rsi >= H1_RSI_Bull_Min) && (h1_rsi <= H1_RSI_Bull_Max);
   bool macdCrossUp = (macdMain2 < macdSignal2) && (macdMain1 >= macdSignal1);
   bool rsiNotOB = (rsi1 < RSI_Buy_Max);

   if(h1Bull && macdCrossUp && rsiNotOB)
   {
      int openBuys  = CountTrades(OP_BUY);
      int barsSince = (int)((Time[0] - g_LastBuyTime) / PeriodSeconds());
      if(openBuys < Max_Buys && barsSince >= Min_Bar_Gap)
      {
         if(openBuys == 0 || HasEnoughDistance(OP_BUY, atr1))
         {
            double lots = CalcLots(slDist);
            if(lots > 0)
            {
               double entry = NormalizeDouble(Ask, Digits);
               int tkt = OrderSend(Symbol(), OP_BUY, lots, entry, Slippage,
                                   NormalizeDouble(entry - slDist, Digits),
                                   NormalizeDouble(entry + tpDist, Digits),
                                   Order_Comment, Magic_Number, 0, clrGreen);
               if(tkt > 0) { g_TradesToday++; g_LastBuyTime = Time[0]; }
            }
         }
      }
   }

   // SELL signal: downtrend + MACD crosses below signal
   bool h1Bear = (Close[1] < h1_ema) && (h1_rsi >= H1_RSI_Bear_Min) && (h1_rsi <= H1_RSI_Bear_Max);
   bool macdCrossDown = (macdMain2 > macdSignal2) && (macdMain1 <= macdSignal1);
   bool rsiNotOS = (rsi1 > RSI_Sell_Min);

   if(h1Bear && macdCrossDown && rsiNotOS)
   {
      int openSells  = CountTrades(OP_SELL);
      int barsSince  = (int)((Time[0] - g_LastSellTime) / PeriodSeconds());
      if(openSells < Max_Sells && barsSince >= Min_Bar_Gap)
      {
         if(openSells == 0 || HasEnoughDistance(OP_SELL, atr1))
         {
            double lots = CalcLots(slDist);
            if(lots > 0)
            {
               double entry = NormalizeDouble(Bid, Digits);
               int tkt = OrderSend(Symbol(), OP_SELL, lots, entry, Slippage,
                                   NormalizeDouble(entry + slDist, Digits),
                                   NormalizeDouble(entry - tpDist, Digits),
                                   Order_Comment, Magic_Number, 0, clrRed);
               if(tkt > 0) { g_TradesToday++; g_LastSellTime = Time[0]; }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
void ManageExits()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != Magic_Number) continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;
      if(iBarShift(NULL, 0, OrderOpenTime(), false) < Max_Bars) continue;
      double closePrice = (OrderType() == OP_BUY) ? Bid : Ask;
      OrderClose(OrderTicket(), OrderLots(), closePrice, Slippage, clrYellow);
   }
}

//+------------------------------------------------------------------+
void CloseAllTrades()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != Magic_Number) continue;
      double closePrice = (OrderType() == OP_BUY) ? Bid : Ask;
      if(OrderType() == OP_BUY || OrderType() == OP_SELL)
         OrderClose(OrderTicket(), OrderLots(), closePrice, Slippage, clrOrange);
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
