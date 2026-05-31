//+------------------------------------------------------------------+
//|   Buy & Sell EA v181 - Restore Return + Single Concurrent Pos    |
//|   Framework: H4 Direction / H1 RSI Structure / M5 Entry         |
//|   LESSONS LEARNED:                                               |
//|     v178: Risk=4.0%, no spike filter -> 229% ret, 24.35% DD, Cal=9.42 |
//|     v179: Risk=4.0%, SL=0.6        -> 244% ret, 26.43% DD, Cal=9.25  |
//|            FAIL: tighter SL kills WR                             |
//|     v180: Risk=4.0%, spike filter  -> 161% ret, 15.55% DD, Cal=10.37 |
//|            SUCCESS: DD halved! But return below 200% target      |
//|            ATR spike filter is proven: skip if ATR > 1.8*slow    |
//|            WR improved: 84.56% -> 85.12% (filter removes losers) |
//|   ROOT CAUSE OF LOW RETURN v180: spike filter + session 9-21     |
//|    removes too many good trades. Need larger position size.       |
//|   APPROACH v181:                                                  |
//|     Risk_Pct: 4.0% -> 5.0% (restore 200%+ return target)        |
//|     Expected: return ~200%, DD ~19%, Calmar ~10.5                |
//|     Max_Buys=1, Max_Sells=1 (no concurrent same-direction trades) |
//|       Eliminates compounded concurrent losses during choppy periods|
//|       Small trade count reduction (~5%) but significant DD improvement|
//|     Keep all v180 improvements:                                   |
//|       ATR spike filter (atr_fast > 1.8 * atr_slow -> skip)       |
//|       Session 09:00-21:00, Daily DD 8%                           |
//|       SL=0.8 (proven optimal), TP=2.5                            |
//|   Changes vs v180:                                                |
//|     1. Risk_Pct: 4.0 -> 5.0                                      |
//|     2. Max_Buys: 2 -> 1 (no concurrent BUYs)                     |
//|     3. Max_Sells: 2 -> 1 (no concurrent SELLs)                   |
//|     4. Magic_Number: 1802025 -> 1812025                           |
//|     5. Order_Comment: BSv180 -> BSv181                            |
//+------------------------------------------------------------------+
#property copyright ""
#property link      ""
#property version   "181.0"
#property strict

#include <stdlib.mqh>

//--- Session
input string SESSION_SET        = "============"; //====== Session Settings ======
input int    Session_Start_Hour = 9;              //Session Start Hour (skip thin Asian pre-session)
input int    Session_End_Hour   = 21;             //Session End Hour (cover London+NY)

//--- Trend Filter
input string TREND_SET          = "============"; //====== Trend Filter ======
input int    H4_EMA_Period      = 200;            //H4 EMA period (broad trend)
input int    H1_EMA_Period      = 200;            //H1 EMA period (medium trend)

//--- H1 RSI Gate
input string H1RSI_SET          = "============"; //====== H1 RSI Gate ======
input int    H1_RSI_Period      = 14;             //H1 RSI period
input double H1_RSI_Min         = 45.0;           //H1 RSI min for BUY
input double H1_RSI_Max         = 75.0;           //H1 RSI max for BUY
input double H1_RSI_Min_Sell    = 25.0;           //H1 RSI min for SELL
input double H1_RSI_Max_Sell    = 55.0;           //H1 RSI max for SELL

//--- Bollinger Bands (M5)
input string BB_SET             = "============"; //====== BB Settings ======
input int    BB_Period          = 20;             //BB period
input double BB_Dev             = 2.5;            //BB SD: 2.5 (proven 81%+ WR)

//--- Signal: M5 BB Touch
input string S1_SET             = "============"; //====== Signal: BB Touch ======
input int    RSI_Period         = 14;             //M5 RSI period
input double RSI_Buy            = 40.0;           //M5 RSI max for BUY: 40 (proven quality)
input double RSI_Sell           = 60.0;           //M5 RSI min for SELL: 60 (proven quality)
input double Body_Pct           = 0.2;            //Min body fraction
input int    Min_Bar_Gap        = 1;              //Min bars between entries

//--- Volatility Filter
input string VOL_SET            = "============"; //====== Volatility Filter ======
input double Max_ATR_Pct        = 0.60;           //Max ATR as % of price (absolute ceiling)
input int    ATR_Spike_MA_Period = 50;             //Slow ATR period for spike detection
input double ATR_Spike_Multi    = 1.8;            //Skip if fast ATR > spike_multi * slow ATR (v180 proven)

//--- Exit Settings
input string EXIT_SET           = "============"; //====== Exit Settings ======
input int    ATR_Period         = 14;             //ATR period
input double ATR_SL_Multi       = 0.8;            //SL = ATR x 0.8 (proven optimal)
input double ATR_TP_Multi       = 2.5;            //TP = ATR x 2.5
input double Trail_ATR_Multi    = 0.8;            //Trail SL offset
input int    Max_Bars           = 100;            //Force-close after N bars

//--- Money Management
input string MONEY_SET          = "============"; //====== Money Management ======
input double Risk_Pct           = 5.0;            //Risk%: 5.0 (increased from 4.0 to restore 200%+ return)
input double Fixed_Lot          = 0.0;            //Fixed lot (0 = use Risk_Pct)
input int    Max_Buys           = 1;              //Max concurrent BUY: 1 (no compounded concurrent losses)
input int    Max_Sells          = 1;              //Max concurrent SELL: 1

//--- Anti-Martingale
input string AM_SET             = "============"; //====== Anti-Martingale Settings ======
input int    WinStreak_Mid      = 1;              //Consec wins for Scale_Mid
input int    WinStreak_High     = 1;              //Consec wins for Scale_High
input double Scale_Mid          = 1.10;           //Scale_Mid
input double Scale_High         = 1.25;           //Scale_High

//--- Safety
input string SAFETY_SET         = "============"; //====== Safety Settings ======
input int    MaxSpread          = 35;             //Max spread in points
input int    Slippage           = 30;             //Max slippage in points
input int    Magic_Number       = 1812025;        //Magic Number
input string Order_Comment      = "BSv181";       //Order comment
input double Max_Daily_DD_Pct   = 8.0;            //Daily DD guard: 8%
input int    Max_Trades_Day     = 300;            //Max trades per day

//+------------------------------------------------------------------+
double   g_DayOpenEquity = 0;
bool     g_DailyDDHit   = false;
int      g_TradesToday  = 0;
datetime g_LastDay      = 0;
datetime g_LastBuyTime  = 0;
datetime g_LastSellTime = 0;

//+------------------------------------------------------------------+
int OnInit()  { return(INIT_SUCCEEDED); }
void OnDeinit(const int reason) {}

//+------------------------------------------------------------------+
int CountLastStreak()
{
   datetime prevTime = TimeCurrent() + 1;
   int maxLook = 40;
   bool isWin = false;
   bool firstFound = false;
   int count = 0;
   for(int pass = 0; pass < maxLook; pass++)
   {
      datetime bestTime  = 0;
      bool     bestResult = false;
      for(int i = OrdersHistoryTotal() - 1; i >= 0; i--)
      {
         if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
         if(OrderSymbol() != Symbol()) continue;
         if(OrderMagicNumber() != Magic_Number) continue;
         if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;
         if(OrderCloseTime() < prevTime && OrderCloseTime() > bestTime)
         {
            bestTime   = OrderCloseTime();
            bestResult = (OrderProfit() + OrderCommission() + OrderSwap() >= 0);
         }
      }
      if(bestTime == 0) break;
      if(!firstFound) { isWin = bestResult; firstFound = true; count = 1; }
      else { if(bestResult == isWin) count++; else break; }
      prevTime = bestTime;
   }
   if(!firstFound) return 0;
   return isWin ? count : -count;
}

//+------------------------------------------------------------------+
double GetRiskScale()
{
   int streak = CountLastStreak();
   if(streak >= WinStreak_High) return Scale_High;
   if(streak >= WinStreak_Mid)  return Scale_Mid;
   if(streak > 0)               return 1.0;
   if(streak == 0)              return 1.0;
   int losses = -streak;
   if(losses == 1) return 0.5;
   if(losses == 2) return 0.25;
   return 0.1;
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
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != Magic_Number) continue;
      if(OrderType() == OP_BUY)
         OrderClose(OrderTicket(), OrderLots(), Bid, Slippage, clrOrange);
      else if(OrderType() == OP_SELL)
         OrderClose(OrderTicket(), OrderLots(), Ask, Slippage, clrOrange);
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
      int    bars      = iBarShift(NULL, 0, OrderOpenTime(), false);
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
                  if(OrderSelect(tkt, SELECT_BY_TICKET, MODE_TRADES))
                     OrderModify(tkt, openPrice, NormalizeDouble(openPrice, Digits), 0, 0, clrBlue);
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
         if(bars >= Max_Bars) OrderClose(tkt, OrderLots(), Bid, Slippage, clrYellow);
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
                  if(OrderSelect(tkt, SELECT_BY_TICKET, MODE_TRADES))
                     OrderModify(tkt, openPrice, NormalizeDouble(openPrice, Digits), 0, 0, clrBlue);
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
         if(bars >= Max_Bars) OrderClose(tkt, OrderLots(), Ask, Slippage, clrYellow);
      }
   }
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

   bool inSession = (dt.hour >= Session_Start_Hour && dt.hour < Session_End_Hour);
   if(!inSession) return;
   if(MarketInfo(Symbol(), MODE_SPREAD) > MaxSpread) return;
   if(g_TradesToday >= Max_Trades_Day) return;

   double h4_ema  = iMA(NULL, PERIOD_H4, H4_EMA_Period, 0, MODE_EMA, PRICE_CLOSE, 0);
   double h1_ema  = iMA(NULL, PERIOD_H1, H1_EMA_Period, 0, MODE_EMA, PRICE_CLOSE, 0);
   double h1_rsi1 = iRSI(NULL, PERIOD_H1, H1_RSI_Period, PRICE_CLOSE, 1);

   bool h4Bull = (iClose(NULL, PERIOD_H4, 0) > h4_ema);
   bool h4Bear = (iClose(NULL, PERIOD_H4, 0) < h4_ema);

   bool h1Bull = (iClose(NULL, PERIOD_H1, 1) > h1_ema)
              && (h1_rsi1 >= H1_RSI_Min) && (h1_rsi1 <= H1_RSI_Max);
   bool h1Bear = (iClose(NULL, PERIOD_H1, 1) < h1_ema)
              && (h1_rsi1 >= H1_RSI_Min_Sell) && (h1_rsi1 <= H1_RSI_Max_Sell);

   double atr1 = iATR(NULL, 0, ATR_Period, 1);
   if(atr1 <= 0) return;

   // === Absolute ATR% Volatility Ceiling ===
   if(Max_ATR_Pct > 0)
   {
      double price1 = iClose(NULL, 0, 1);
      if(price1 > 0 && (atr1 / price1 * 100.0) > Max_ATR_Pct) return;
   }

   // === ATR SPIKE FILTER (proven in v180) ===
   // Skip if fast ATR > 1.8 * slow ATR (news/volatility spike detection)
   if(ATR_Spike_Multi > 0)
   {
      double atr_slow = iATR(NULL, 0, ATR_Spike_MA_Period, 1);
      if(atr_slow > 0 && atr1 > ATR_Spike_Multi * atr_slow) return;
   }

   double bbLower1 = iBands(NULL, 0, BB_Period, BB_Dev, 0, PRICE_CLOSE, MODE_LOWER, 1);
   double bbUpper1 = iBands(NULL, 0, BB_Period, BB_Dev, 0, PRICE_CLOSE, MODE_UPPER, 1);
   double rsi1     = iRSI(NULL, 0, RSI_Period, PRICE_CLOSE, 1);
   double rsi2     = iRSI(NULL, 0, RSI_Period, PRICE_CLOSE, 2);

   double slDist    = ATR_SL_Multi * atr1;
   double tpDist    = ATR_TP_Multi * atr1;
   double riskScale = GetRiskScale();

   double candleRange = High[1] - Low[1];
   double candleBodyB = Close[1] - Open[1];
   double candleBodyS = Open[1] - Close[1];

   //=== Signal BUY ===
   if(h4Bull && h1Bull)
   {
      bool bbTouch   = (Low[1] <= bbLower1) && (Close[1] > bbLower1);
      bool rsiOS     = (rsi1 < RSI_Buy);
      bool rsiRising = (rsi1 > rsi2);
      bool bullBody  = (candleBodyB > 0) && (candleRange > 0)
                    && (candleBodyB >= Body_Pct * candleRange);

      if(bbTouch && rsiOS && rsiRising && bullBody)
      {
         int openBuys  = CountTradesByMagic(OP_BUY, Magic_Number);
         int barsSince = (int)((Time[0] - g_LastBuyTime) / PeriodSeconds());
         if(openBuys < Max_Buys && barsSince >= Min_Bar_Gap)
         {
            double entry = NormalizeDouble(Ask, Digits);
            double sl    = NormalizeDouble(entry - slDist, Digits);
            double tp    = NormalizeDouble(entry + tpDist, Digits);
            double lots  = CalcLots(slDist, riskScale);
            if(lots > 0)
            {
               int tkt = OrderSend(Symbol(), OP_BUY, lots, entry, Slippage,
                                   sl, tp, Order_Comment, Magic_Number, 0, clrGreen);
               if(tkt > 0) { g_TradesToday++; g_LastBuyTime = Time[0]; }
            }
         }
      }
   }

   //=== Signal SELL ===
   if(h4Bear && h1Bear)
   {
      bool bbTouchUp  = (High[1] >= bbUpper1) && (Close[1] < bbUpper1);
      bool rsiOB      = (rsi1 > RSI_Sell);
      bool rsiFalling = (rsi1 < rsi2);
      bool bearBody   = (candleBodyS > 0) && (candleRange > 0)
                     && (candleBodyS >= Body_Pct * candleRange);

      if(bbTouchUp && rsiOB && rsiFalling && bearBody)
      {
         int openSells = CountTradesByMagic(OP_SELL, Magic_Number);
         int barsSince = (int)((Time[0] - g_LastSellTime) / PeriodSeconds());
         if(openSells < Max_Sells && barsSince >= Min_Bar_Gap)
         {
            double entry = NormalizeDouble(Bid, Digits);
            double sl    = NormalizeDouble(entry + slDist, Digits);
            double tp    = NormalizeDouble(entry - tpDist, Digits);
            double lots  = CalcLots(slDist, riskScale);
            if(lots > 0)
            {
               int tkt = OrderSend(Symbol(), OP_SELL, lots, entry, Slippage,
                                   sl, tp, Order_Comment, Magic_Number, 0, clrRed);
               if(tkt > 0) { g_TradesToday++; g_LastSellTime = Time[0]; }
            }
         }
      }
   }
}
//+------------------------------------------------------------------+
