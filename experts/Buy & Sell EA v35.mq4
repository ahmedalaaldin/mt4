//+------------------------------------------------------------------+
//|   Buy & Sell EA v46 - Dual Direction Mean Reversion             |
//|   BUY:  Close > H1_EMA + H1_RSI 50-75 + BB lower touch        |
//|         + M5 RSI<40 + Stoch K&D<25 + bullish close             |
//|   SELL: Close < H1_EMA + H1_RSI 25-50 + BB upper touch        |
//|         + M5 RSI>60 + Stoch K&D>75 + bearish close            |
//|   Exit: TP = BB mid, SL = 1xATR                               |
//|   Goal: Double trade frequency via symmetric mean reversion     |
//+------------------------------------------------------------------+
#property copyright ""
#property link      ""
#property version   "46.0"
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
input double H1_RSI_Bull_Min    = 50.0;           //H1 RSI min for BUY
input double H1_RSI_Bull_Max    = 75.0;           //H1 RSI max for BUY
input double H1_RSI_Bear_Min    = 25.0;           //H1 RSI min for SELL
input double H1_RSI_Bear_Max    = 50.0;           //H1 RSI max for SELL

//--- Bollinger Bands
input string BB_SET             = "============"; //====== Bollinger Band Settings ======
input int    BB_Period          = 20;             //BB period
input double BB_Dev             = 2.5;            //BB standard deviations
input double TP_Min_ATR         = 0.5;            //Min TP distance as ATR multiple

//--- Entry Signal
input string ENTRY_SET          = "============"; //====== Entry Settings ======
input int    RSI_Period         = 14;             //M5 RSI period
input double RSI_Buy            = 40.0;           //M5 RSI oversold level (for BUY)
input double RSI_Sell           = 60.0;           //M5 RSI overbought level (for SELL)
input int    Stoch_K            = 5;              //Stochastic K period
input int    Stoch_D            = 3;              //Stochastic D period
input int    Stoch_Slowing      = 3;              //Stochastic slowing
input double Stoch_OS           = 25.0;           //Stochastic oversold level (for BUY)
input double Stoch_OB           = 75.0;           //Stochastic overbought level (for SELL)
input int    Min_Bar_Gap        = 2;              //Min bars between entries (same direction)
input double Price_Gap_ATR      = 0.3;            //Min ATR gap between same-dir entries

//--- Exit
input string EXIT_SET           = "============"; //====== Exit Settings ======
input int    ATR_Period         = 14;             //ATR Period
input double ATR_SL_Multi       = 1.0;            //Stop Loss = ATR x this
input int    Max_Bars           = 40;             //Force close after N bars

//--- Money Management
input string MONEY_SET          = "============"; //====== Money Management ======
input double Risk_Pct           = 2.0;            //Risk % per trade
input double Fixed_Lot          = 0.0;            //Fixed lot (0 = use Risk_Pct)
input int    Max_Buys           = 3;              //Max concurrent BUY positions
input int    Max_Sells          = 3;              //Max concurrent SELL positions

//--- Safety
input string SAFETY_SET         = "============"; //====== Safety Settings ======
input int    MaxSpread          = 35;             //Max spread in points
input int    Slippage           = 30;             //Max slippage in points
input int    Magic_Number       = 462025;         //Magic Number
input string Order_Comment      = "BSv46";        //Order comment
input double Max_Daily_DD_Pct   = 4.0;            //Daily drawdown guard (% of equity)
input int    Max_Trades_Day     = 80;             //Max trades per day

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

   double bbMid0   = iBands(NULL, 0, BB_Period, BB_Dev, 0, PRICE_CLOSE, MODE_MAIN,  0);
   double bbUpper1 = iBands(NULL, 0, BB_Period, BB_Dev, 0, PRICE_CLOSE, MODE_UPPER, 1);
   double bbLower1 = iBands(NULL, 0, BB_Period, BB_Dev, 0, PRICE_CLOSE, MODE_LOWER, 1);
   double rsi1     = iRSI(NULL, 0, RSI_Period, PRICE_CLOSE, 1);
   double stochK1  = iStochastic(NULL, 0, Stoch_K, Stoch_D, Stoch_Slowing, MODE_SMA, 0, MODE_MAIN,   1);
   double stochD1  = iStochastic(NULL, 0, Stoch_K, Stoch_D, Stoch_Slowing, MODE_SMA, 0, MODE_SIGNAL, 1);

   double slDist = ATR_SL_Multi * atr1;
   double minTP  = TP_Min_ATR * atr1;

   // --- BUY Signal (identical to proven v24/BSv35) ---
   bool h1Bull      = (Close[1] > h1_ema) && (h1_rsi >= H1_RSI_Bull_Min) && (h1_rsi <= H1_RSI_Bull_Max);
   bool bbTouchLow  = (Low[1] <= bbLower1) && (Close[1] > bbLower1);
   bool rsiOS       = (rsi1 < RSI_Buy);
   bool stochOS     = (stochK1 < Stoch_OS) && (stochD1 < Stoch_OS);
   bool bullClose   = (Close[1] > Open[1]);

   if(h1Bull && bbTouchLow && rsiOS && stochOS && bullClose)
   {
      double entry  = NormalizeDouble(Ask, Digits);
      double tpDist = bbMid0 - entry;

      if(tpDist >= minTP)
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
                  int tkt = OrderSend(Symbol(), OP_BUY, lots, entry, Slippage,
                                      NormalizeDouble(entry - slDist, Digits),
                                      NormalizeDouble(bbMid0, Digits),
                                      Order_Comment, Magic_Number, 0, clrGreen);
                  if(tkt > 0) { g_TradesToday++; g_LastBuyTime = Time[0]; }
               }
            }
         }
      }
   }

   // --- SELL Signal (symmetric: downtrend + BB upper touch + overbought oscillators) ---
   bool h1Bear      = (Close[1] < h1_ema) && (h1_rsi >= H1_RSI_Bear_Min) && (h1_rsi <= H1_RSI_Bear_Max);
   bool bbTouchHigh = (High[1] >= bbUpper1) && (Close[1] < bbUpper1);
   bool rsiOB       = (rsi1 > RSI_Sell);
   bool stochOB     = (stochK1 > Stoch_OB) && (stochD1 > Stoch_OB);
   bool bearClose   = (Close[1] < Open[1]);

   if(h1Bear && bbTouchHigh && rsiOB && stochOB && bearClose)
   {
      double entry  = NormalizeDouble(Bid, Digits);
      double tpDist = entry - bbMid0;

      if(tpDist >= minTP)
      {
         int openSells = CountTrades(OP_SELL);
         int barsSince = (int)((Time[0] - g_LastSellTime) / PeriodSeconds());
         if(openSells < Max_Sells && barsSince >= Min_Bar_Gap)
         {
            if(openSells == 0 || HasEnoughDistance(OP_SELL, atr1))
            {
               double lots = CalcLots(slDist);
               if(lots > 0)
               {
                  int tkt = OrderSend(Symbol(), OP_SELL, lots, entry, Slippage,
                                      NormalizeDouble(entry + slDist, Digits),
                                      NormalizeDouble(bbMid0, Digits),
                                      Order_Comment, Magic_Number, 0, clrRed);
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
      if(OrderType() == OP_BUY)
         OrderClose(OrderTicket(), OrderLots(), Bid, Slippage, clrOrange);
      else if(OrderType() == OP_SELL)
         OrderClose(OrderTicket(), OrderLots(), Ask, Slippage, clrOrange);
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
