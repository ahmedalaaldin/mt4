//+------------------------------------------------------------------+
//|   Buy & Sell EA v112 - Dual Direction + Risk 5.5%               |
//|   Framework: 4H Direction / 1H Structure / 5M Entry             |
//|   Base: v104/v111 AllBuysRiskFree gate (173.83% proven)         |
//|   Innovation:                                                    |
//|     - SELL side added: symmetric H4/H1/M5 bearish entries       |
//|       H4 close < EMA200 + H1 close < EMA200 + RSI[25,55]       |
//|       M5 BB upper touch + RSI>60 falling + Stoch>75 + bear body|
//|     - AllSellsRiskFree gate: same compound logic for shorts      |
//|     - Risk_Pct = 5.5% (from 4.9%) to target 200%+ return       |
//|     - Max_Buys=2, Max_Sells=2: dual compounding both sides      |
//|   Goal: 200%+ return via dual-direction signals + higher risk    |
//+------------------------------------------------------------------+
#property copyright ""
#property link      ""
#property version   "122.0"
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
input int    H1_RSI_Period      = 14;             //H1 RSI period
input double H1_RSI_Min         = 50.0;           //H1 RSI min for BUY zone
input double H1_RSI_Max         = 75.0;           //H1 RSI max for BUY (not overextended)
input double H1_RSI_Min_Sell    = 25.0;           //H1 RSI min for SELL (not overextended)
input double H1_RSI_Max_Sell    = 50.0;           //H1 RSI max for SELL zone

//--- Bollinger Bands (M5)
input string BB_SET             = "============"; //====== Bollinger Band Settings ======
input int    BB_Period          = 20;             //BB period
input double BB_Dev             = 2.5;            //BB SD
input double TP_Min_ATR         = 0.5;            //Min TP distance as ATR multiple

//--- Entry Signal (M5)
input string ENTRY_SET          = "============"; //====== Entry Settings ======
input int    RSI_Period         = 14;             //M5 RSI period
input double RSI_Buy            = 40.0;           //M5 RSI max for BUY (oversold)
input double RSI_Sell           = 60.0;           //M5 RSI min for SELL (overbought)
input int    Stoch_K            = 5;              //Stochastic K period
input int    Stoch_D            = 3;              //Stochastic D period
input int    Stoch_Slowing      = 3;              //Stochastic slowing
input double Stoch_OS           = 25.0;           //Stochastic oversold level (buy)
input double Stoch_OB           = 75.0;           //Stochastic overbought level (sell)
input double Body_Pct           = 0.2;            //Min body as fraction of candle range
input int    Min_Bar_Gap        = 1;              //Min bars between entries
input double Price_Gap_ATR      = 0.3;            //Min ATR gap between same-dir entries

//--- Exit
input string EXIT_SET           = "============"; //====== Exit Settings ======
input int    ATR_Period         = 14;             //ATR period
input double ATR_SL_Multi       = 1.0;            //SL = ATR x this
input double Trail_ATR_Multi    = 0.3;            //Trail SL offset from BB mid (ATR multiples)
input int    Max_Bars           = 60;             //Force close after N bars

//--- Money Management
input string MONEY_SET          = "============"; //====== Money Management ======
input double Risk_Pct           = 5.5;            //Risk % per trade (raised for 200%+ target)
input double Fixed_Lot          = 0.0;            //Fixed lot (0 = use Risk_Pct)
input int    Max_Buys           = 2;              //Max concurrent BUY positions
input int    Max_Sells          = 2;              //Max concurrent SELL positions

//--- Safety
input string SAFETY_SET         = "============"; //====== Safety Settings ======
input int    MaxSpread          = 35;             //Max spread in points
input int    Slippage           = 30;             //Max slippage in points
input int    Magic_Number       = 1222025;        //Magic Number
input string Order_Comment      = "BSv122";       //Order comment
input double Max_Daily_DD_Pct   = 15.0;           //Daily drawdown guard (% of equity)
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
         if(OrderSymbol() != Symbol() || OrderMagicNumber() != Magic_Number) continue;
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

//--- All open buys have SL >= openPrice (risk-free)
bool AllBuysRiskFree()
{
   for(int i = 0; i < OrdersTotal(); i++)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != Magic_Number) continue;
      if(OrderType() != OP_BUY) continue;
      if(OrderStopLoss() < OrderOpenPrice()) return false;
   }
   return true;
}

//--- All open sells have SL <= openPrice (risk-free for shorts)
bool AllSellsRiskFree()
{
   for(int i = 0; i < OrdersTotal(); i++)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != Magic_Number) continue;
      if(OrderType() != OP_SELL) continue;
      if(OrderStopLoss() > OrderOpenPrice()) return false;
   }
   return true;
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

   double h4_ema = iMA(NULL, PERIOD_H4, H4_EMA_Period, 0, MODE_EMA, PRICE_CLOSE, 0);
   double h1_ema = iMA(NULL, PERIOD_H1, H1_EMA_Period, 0, MODE_EMA, PRICE_CLOSE, 0);
   double h1_rsi1 = iRSI(NULL, PERIOD_H1, H1_RSI_Period, PRICE_CLOSE, 1);

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

   //--- BUY logic
   bool h4Bull = (iClose(NULL, PERIOD_H4, 0) > h4_ema);
   bool h1Bull = (iClose(NULL, PERIOD_H1, 1) > h1_ema)
               && (h1_rsi1 >= H1_RSI_Min) && (h1_rsi1 <= H1_RSI_Max);

   if(h4Bull && h1Bull)
   {
      bool bbTouch  = (Low[1] <= bbLower1) && (Close[1] > bbLower1);
      bool rsiOS    = (rsi1 < RSI_Buy);
      bool rsiRising= (rsi1 > rsi2);
      bool stochOS  = (stochK1 < Stoch_OS) && (stochD1 < Stoch_OS);
      bool bullBody = (candleBody > 0) && (candleRange > 0) && (candleBody >= Body_Pct * candleRange);

      if(bbTouch && rsiOS && rsiRising && stochOS && bullBody)
      {
         double entry  = NormalizeDouble(Ask, Digits);
         double tpDist = bbMid0 - entry;
         if(tpDist >= minTP)
         {
            int openBuys  = CountTrades(OP_BUY);
            int barsSince = (int)((Time[0] - g_LastBuyTime) / PeriodSeconds());
            bool canOpen  = (openBuys == 0) || (openBuys < Max_Buys && AllBuysRiskFree());

            if(canOpen && barsSince >= Min_Bar_Gap)
            {
               if(openBuys == 0 || HasEnoughDistance(OP_BUY, atr1))
               {
                  double lots = CalcLots(slDist, riskScale);
                  if(lots > 0)
                  {
                     int tkt = OrderSend(Symbol(), OP_BUY, lots, entry, Slippage,
                                         NormalizeDouble(entry - slDist, Digits),
                                         0, Order_Comment, Magic_Number, 0, clrGreen);
                     if(tkt > 0) { g_TradesToday++; g_LastBuyTime = Time[0]; }
                  }
               }
            }
         }
      }
   }

   //--- SELL logic (mirror: H4 bearish, H1 bearish, M5 upper BB rejection)
   bool h4Bear = (iClose(NULL, PERIOD_H4, 0) < h4_ema);
   bool h1Bear = (iClose(NULL, PERIOD_H1, 1) < h1_ema)
               && (h1_rsi1 >= H1_RSI_Min_Sell) && (h1_rsi1 <= H1_RSI_Max_Sell);

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
            int openSells = CountTrades(OP_SELL);
            int barsSince = (int)((Time[0] - g_LastSellTime) / PeriodSeconds());
            bool canOpen  = (openSells == 0) || (openSells < Max_Sells && AllSellsRiskFree());

            if(canOpen && barsSince >= Min_Bar_Gap)
            {
               if(openSells == 0 || HasEnoughDistance(OP_SELL, atr1))
               {
                  double lots = CalcLots(slDist, riskScale);
                  if(lots > 0)
                  {
                     int tkt = OrderSend(Symbol(), OP_SELL, lots, entry, Slippage,
                                         NormalizeDouble(entry + slDist, Digits),
                                         0, Order_Comment, Magic_Number, 0, clrRed);
                     if(tkt > 0) { g_TradesToday++; g_LastSellTime = Time[0]; }
                  }
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
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != Magic_Number) continue;

      int    tkt       = OrderTicket();
      double openPrice = OrderOpenPrice();
      double currentSL = OrderStopLoss();
      int    type      = OrderType();

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
               double beSL = NormalizeDouble(openPrice, Digits);
               if(currentSL < openPrice)
                  OrderModify(tkt, openPrice, beSL, 0, 0, clrBlue);
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
         // partialDone for sell: SL has been moved to or below openPrice (at BE)
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
               double beSL = NormalizeDouble(openPrice, Digits);
               if(currentSL > openPrice)
                  OrderModify(tkt, openPrice, beSL, 0, 0, clrBlue);
            }
            continue;
         }

         if(partialDone)
         {
            // Trail: SL moves DOWN toward profit as price falls
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
