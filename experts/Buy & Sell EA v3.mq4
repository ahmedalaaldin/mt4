//+------------------------------------------------------------------+
//|   Buy & Sell EA v14 - XAUUSD M5 EMA200 + ADX Trend Filter      |
//|   Strategy: H1 EMA200 Trend + ADX + EMA Cross/RSI Bounce       |
//|   Fixed 1.5:1 RR — best result from parameter sweeps            |
//+------------------------------------------------------------------+
#property copyright ""
#property link      ""
#property version   "14.0"
#property strict

#include <stdlib.mqh>

//--- Session
input string SESSION_SET         = "============"; //====== Session Settings ======
input int    Session_Start_Hour  = 7;              //Session Start Hour (server time)
input int    Session_End_Hour    = 20;             //Session End Hour (server time)

//--- Trend Filter
input string TREND_SET           = "============"; //====== Trend Filter ======
input int    H1_EMA_Period        = 200;           //H1 EMA period (macro uptrend)
input int    EMA_Fast             = 8;             //Fast EMA M5
input int    EMA_Slow             = 21;            //Slow EMA M5
input int    ADX_Period           = 14;            //ADX Period
input double ADX_Min              = 20.0;          //Min ADX to enter (trending market)

//--- Entry
input string ENTRY_SET           = "============"; //====== Entry Settings ======
input int    RSI_Period           = 14;            //RSI period
input double RSI_OS               = 45.0;          //RSI oversold bounce level
input double RSI_OB               = 70.0;          //Skip entry if RSI above this
input int    Min_Bar_Gap          = 3;             //Min bars between entries
input double Price_Gap_ATR        = 0.3;           //Min ATR gap between same-dir entries

//--- Exit / Trailing
input string EXIT_SET            = "============"; //====== Exit Settings ======
input int    ATR_Period           = 14;            //ATR Period
input double ATR_SL_Multi         = 1.0;           //Initial Stop Loss = ATR x this
input double Trail_Start_Multi    = 100.0;         //Start trailing when profit >= ATR x this (100=disabled)
input double Trail_Step_Multi     = 0.5;           //Trail step size = ATR x this
input double ATR_TP_Multi         = 1.5;           //Take Profit = ATR x this
input int    Max_Bars             = 80;            //Force close after N bars if no trail triggered

//--- Money Management
input string MONEY_SET           = "============"; //====== Money Management ======
input double Risk_Pct             = 1.5;           //Risk per trade (% of equity)
input double Fixed_Lot            = 0.0;           //Fixed lot (0 = use Risk_Pct)
input int    Max_Trades           = 3;             //Max concurrent buy positions

//--- Safety
input string SAFETY_SET          = "============"; //====== Safety Settings ======
input int    MaxSpread            = 35;            //Max spread in points
input int    Slippage             = 30;            //Max slippage in points
input int    Magic_Number         = 142025;        //Magic Number
input string Order_Comment        = "BSv14";       //Order comment
input double Max_Daily_DD_Pct     = 3.5;           //Daily drawdown guard (% of equity)
input int    Max_Trades_Day       = 60;            //Max trades per day

//+------------------------------------------------------------------+
double   g_DayOpenEquity = 0;
bool     g_DailyDDHit    = false;
int      g_TradesToday   = 0;
datetime g_LastDay       = 0;
datetime g_LastEntryTime = 0;

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
      if(ddPct >= Max_Daily_DD_Pct)
      {
         CloseAllTrades();
         g_DailyDDHit = true;
         return;
      }
   }
   if(g_DailyDDHit) return;

   //--- Update trailing stops on every tick
   ManageTrailing();

   if(!isNewBar) return;

   //--- Bar-open logic below
   ManageExits();

   if(dt.hour < Session_Start_Hour || dt.hour >= Session_End_Hour) return;
   if(g_TradesToday >= Max_Trades_Day) return;
   if(MarketInfo(Symbol(), MODE_SPREAD) > MaxSpread) return;

   int openBuys = CountTrades(OP_BUY);
   if(openBuys >= Max_Trades) return;

   int barsSince = (int)((Time[0] - g_LastEntryTime) / PeriodSeconds());
   if(barsSince < Min_Bar_Gap) return;

   double atr1 = iATR(NULL, 0, ATR_Period, 1);
   if(atr1 <= 0) return;

   //--- H1 macro uptrend filter (EMA200)
   double h1_ema = iMA(NULL, PERIOD_H1, H1_EMA_Period, 0, MODE_EMA, PRICE_CLOSE, 0);
   if(Close[1] <= h1_ema) return;

   //--- ADX trend strength filter
   double adx1 = iADX(NULL, 0, ADX_Period, PRICE_CLOSE, MODE_MAIN, 1);
   if(adx1 < ADX_Min) return;

   //--- M5 EMAs
   double ema_f1 = iMA(NULL, 0, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE, 1);
   double ema_f2 = iMA(NULL, 0, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE, 2);
   double ema_s1 = iMA(NULL, 0, EMA_Slow, 0, MODE_EMA, PRICE_CLOSE, 1);
   double ema_s2 = iMA(NULL, 0, EMA_Slow, 0, MODE_EMA, PRICE_CLOSE, 2);

   //--- RSI
   double rsi1 = iRSI(NULL, 0, RSI_Period, PRICE_CLOSE, 1);
   double rsi2 = iRSI(NULL, 0, RSI_Period, PRICE_CLOSE, 2);

   bool bullBar = (Close[1] > Open[1]);
   bool rsiOK   = (rsi1 < RSI_OB);

   //--- Signal A: EMA8 fresh cross above EMA21
   bool sigEMACross = (ema_f2 <= ema_s2) && (ema_f1 > ema_s1) && bullBar && rsiOK;

   //--- Signal B: RSI oversold bounce while EMA8 > EMA21
   bool sigRSIBounce = (ema_f1 > ema_s1) && (rsi2 < RSI_OS) && (rsi1 >= RSI_OS) && bullBar && rsiOK;

   if(!sigEMACross && !sigRSIBounce) return;

   if(openBuys > 0 && !HasEnoughDistance(OP_BUY, atr1)) return;

   double slDist = ATR_SL_Multi * atr1;
   double tpDist = ATR_TP_Multi * atr1;
   double lots   = CalcLots(slDist);
   if(lots <= 0) return;

   double entry = NormalizeDouble(Ask, Digits);
   double sl    = NormalizeDouble(entry - slDist, Digits);
   double tp    = NormalizeDouble(entry + tpDist, Digits);

   int tkt = OrderSend(Symbol(), OP_BUY, lots, entry, Slippage, sl, tp, Order_Comment, Magic_Number, 0, clrGreen);
   if(tkt > 0) { g_TradesToday++; g_LastEntryTime = Time[0]; }
}

//+------------------------------------------------------------------+
void ManageTrailing()
{
   double atrCurrent = iATR(NULL, 0, ATR_Period, 0);
   if(atrCurrent <= 0) return;

   double trailStart = Trail_Start_Multi * atrCurrent;
   double trailStep  = Trail_Step_Multi  * atrCurrent;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != Magic_Number) continue;
      if(OrderType() != OP_BUY) continue;

      double profit = Bid - OrderOpenPrice();

      if(profit >= trailStart)
      {
         double newSL = NormalizeDouble(Bid - trailStep, Digits);
         if(newSL > OrderStopLoss() + Point)
            OrderModify(OrderTicket(), OrderOpenPrice(), newSL, OrderTakeProfit(), 0, clrBlue);
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
      if(OrderType() != OP_BUY) continue;
      if(OrderStopLoss() <= OrderOpenPrice() - ATR_SL_Multi * iATR(NULL, 0, ATR_Period, 1) * 0.5)
      {
         if(iBarShift(NULL, 0, OrderOpenTime(), false) >= Max_Bars)
            OrderClose(OrderTicket(), OrderLots(), Bid, Slippage, clrYellow);
      }
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
