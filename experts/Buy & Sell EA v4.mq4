//+------------------------------------------------------------------+
//|   Buy & Sell EA v15 - Bidirectional XAUUSD M5                   |
//|   BUY above H1 EMA200 / SELL below H1 EMA200                   |
//|   Signals: EMA8/21 cross + RSI bounce (both directions)         |
//|   ADX removed — confirmed counter-productive in sweeps          |
//+------------------------------------------------------------------+
#property copyright ""
#property link      ""
#property version   "15.0"
#property strict

#include <stdlib.mqh>

//--- Session
input string SESSION_SET         = "============"; //====== Session Settings ======
input int    Session_Start_Hour  = 7;              //Session Start Hour (server time)
input int    Session_End_Hour    = 20;             //Session End Hour (server time)

//--- Trend Filter
input string TREND_SET           = "============"; //====== Trend Filter ======
input int    H1_EMA_Period        = 200;           //H1 EMA period (macro trend)
input int    EMA_Fast             = 8;             //Fast EMA M5
input int    EMA_Slow             = 21;            //Slow EMA M5

//--- Entry
input string ENTRY_SET           = "============"; //====== Entry Settings ======
input int    RSI_Period           = 14;            //RSI period
input double RSI_OS               = 45.0;          //RSI oversold level  (buy signal)
input double RSI_OB               = 55.0;          //RSI overbought level (sell signal)
input double RSI_Skip_OB          = 70.0;          //Skip BUY if RSI above this
input double RSI_Skip_OS          = 30.0;          //Skip SELL if RSI below this
input int    Min_Bar_Gap          = 2;             //Min bars between entries (per direction)
input double Price_Gap_ATR        = 0.3;           //Min ATR gap between same-dir entries

//--- Exit
input string EXIT_SET            = "============"; //====== Exit Settings ======
input int    ATR_Period           = 14;            //ATR Period
input double ATR_SL_Multi         = 1.0;           //Stop Loss = ATR x this
input double ATR_TP_Multi         = 1.5;           //Take Profit = ATR x this
input int    Max_Bars             = 80;            //Force close after N bars

//--- Money Management
input string MONEY_SET           = "============"; //====== Money Management ======
input double Risk_Pct             = 1.5;           //Risk per trade (% of equity)
input double Fixed_Lot            = 0.0;           //Fixed lot (0 = use Risk_Pct)
input int    Max_Buys             = 3;             //Max concurrent BUY positions
input int    Max_Sells            = 3;             //Max concurrent SELL positions

//--- Safety
input string SAFETY_SET          = "============"; //====== Safety Settings ======
input int    MaxSpread            = 35;            //Max spread in points
input int    Slippage             = 30;            //Max slippage in points
input int    Magic_Number         = 152025;        //Magic Number
input string Order_Comment        = "BSv15";       //Order comment
input double Max_Daily_DD_Pct     = 3.5;           //Daily drawdown guard (% of equity)
input int    Max_Trades_Day       = 60;            //Max trades per day

//+------------------------------------------------------------------+
double   g_DayOpenEquity  = 0;
bool     g_DailyDDHit     = false;
int      g_TradesToday    = 0;
datetime g_LastDay        = 0;
datetime g_LastBuyTime    = 0;
datetime g_LastSellTime   = 0;

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

   double ema_f1 = iMA(NULL, 0, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE, 1);
   double ema_f2 = iMA(NULL, 0, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE, 2);
   double ema_s1 = iMA(NULL, 0, EMA_Slow, 0, MODE_EMA, PRICE_CLOSE, 1);
   double ema_s2 = iMA(NULL, 0, EMA_Slow, 0, MODE_EMA, PRICE_CLOSE, 2);

   double rsi1 = iRSI(NULL, 0, RSI_Period, PRICE_CLOSE, 1);
   double rsi2 = iRSI(NULL, 0, RSI_Period, PRICE_CLOSE, 2);

   bool bullBar = (Close[1] > Open[1]);
   bool bearBar = (Close[1] < Open[1]);

   //--- BUY logic: price above H1 EMA200
   if(Close[1] > h1_ema)
   {
      int openBuys = CountTrades(OP_BUY);
      if(openBuys < Max_Buys)
      {
         int barsSince = (int)((Time[0] - g_LastBuyTime) / PeriodSeconds());
         if(barsSince >= Min_Bar_Gap)
         {
            bool sigBuyCross   = (ema_f2 <= ema_s2) && (ema_f1 > ema_s1) && bullBar && (rsi1 < RSI_Skip_OB);
            bool sigBuyBounce  = (ema_f1 > ema_s1) && (rsi2 < RSI_OS) && (rsi1 >= RSI_OS) && bullBar && (rsi1 < RSI_Skip_OB);

            if((sigBuyCross || sigBuyBounce) && (openBuys == 0 || HasEnoughDistance(OP_BUY, atr1)))
            {
               double slDist = ATR_SL_Multi * atr1;
               double tpDist = ATR_TP_Multi * atr1;
               double lots   = CalcLots(slDist);
               if(lots > 0)
               {
                  double entry = NormalizeDouble(Ask, Digits);
                  double sl    = NormalizeDouble(entry - slDist, Digits);
                  double tp    = NormalizeDouble(entry + tpDist, Digits);
                  int tkt = OrderSend(Symbol(), OP_BUY, lots, entry, Slippage, sl, tp, Order_Comment, Magic_Number, 0, clrGreen);
                  if(tkt > 0) { g_TradesToday++; g_LastBuyTime = Time[0]; }
               }
            }
         }
      }
   }

   //--- SELL logic: price below H1 EMA200
   if(Close[1] < h1_ema)
   {
      int openSells = CountTrades(OP_SELL);
      if(openSells < Max_Sells)
      {
         int barsSince = (int)((Time[0] - g_LastSellTime) / PeriodSeconds());
         if(barsSince >= Min_Bar_Gap)
         {
            bool sigSellCross  = (ema_f2 >= ema_s2) && (ema_f1 < ema_s1) && bearBar && (rsi1 > RSI_Skip_OS);
            bool sigSellBounce = (ema_f1 < ema_s1) && (rsi2 > RSI_OB) && (rsi1 <= RSI_OB) && bearBar && (rsi1 > RSI_Skip_OS);

            if((sigSellCross || sigSellBounce) && (openSells == 0 || HasEnoughDistance(OP_SELL, atr1)))
            {
               double slDist = ATR_SL_Multi * atr1;
               double tpDist = ATR_TP_Multi * atr1;
               double lots   = CalcLots(slDist);
               if(lots > 0)
               {
                  double entry = NormalizeDouble(Bid, Digits);
                  double sl    = NormalizeDouble(entry + slDist, Digits);
                  double tp    = NormalizeDouble(entry - tpDist, Digits);
                  int tkt = OrderSend(Symbol(), OP_SELL, lots, entry, Slippage, sl, tp, Order_Comment, Magic_Number, 0, clrRed);
                  if(tkt > 0) { g_TradesToday++; g_LastSellTime = Time[0]; }
               }
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
      if(iBarShift(NULL, 0, OrderOpenTime(), false) < Max_Bars) continue;

      double price = (OrderType() == OP_BUY) ? Bid : Ask;
      OrderClose(OrderTicket(), OrderLots(), price, Slippage, clrYellow);
   }
}

//+------------------------------------------------------------------+
void CloseAllTrades()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != Magic_Number) continue;
      double price = (OrderType() == OP_BUY) ? Bid : Ask;
      OrderClose(OrderTicket(), OrderLots(), price, Slippage, clrOrange);
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
