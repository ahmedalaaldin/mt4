//+------------------------------------------------------------------+
//|   Buy & Sell EA v191 - Balance Peak Guard (no-open-trades fix)   |
//|   Framework: H4 Direction / H1 RSI Structure / M5 Entry         |
//|   LESSONS LEARNED:                                               |
//|     v186: 7.0%, Streak=5/10   -> 90.70% WR, 18.87% DD, Cal=12.60|
//|            BEST: delayed anti-martingale thresholds improve Calmar|
//|     v188: Scale_Mid/High=1.0  -> 90.44% WR, 17.85% DD, Cal=11.00|
//|            FAIL: no win scaling hurts return (-41%) vs DD (-1%)  |
//|     v189: Equity peak guard   -> 89.78% WR, 18.51% DD, Cal=5.05 |
//|            FAIL: guard used AccountEquity() - floatP&L inflates  |
//|            peak, guard fires on normal intraday swings            |
//|     v190: Balance peak guard  -> 90.00% WR, 16.38% DD, Cal=5.46 |
//|            FAIL: partial close (50% @ BBmid) immediately raises  |
//|            AccountBalance(), setting new peaks after every partial|
//|            close. Next SL hit triggers guard from this inflated   |
//|            peak even though no real drawdown occurred.            |
//|   ROOT CAUSE OF v190 BUG: partial close updates AccountBalance() |
//|   FIX v191: Update g_EquityPeak ONLY when openTrades == 0.       |
//|     Peak rises ONLY when a complete trade cycle ends profitably.  |
//|     Partial closes (position still open) cannot set new peaks.    |
//|     Guard fires only on sustained losing periods after COMPLETE   |
//|     trade cycles, not on partial-close-inflated intermediate vals.|
//|   v191 = v190 + no-open-trades peak update + Magic/Comment update|
//|   All other parameters identical to v186/v190:                   |
//|     Risk=7%, Streak=5/10, Scale_Mid=1.10, Scale_High=1.25        |
//|     Guard: Pct=10%, Scale=0.5                                    |
//|   Changes vs v190:                                               |
//|     1. g_EquityPeak only updates when CountTradesByMagic==0      |
//|        for both BUY and SELL (no partial-close peak inflation)    |
//|     2. Magic_Number: 1902025 -> 1912025                          |
//|     3. Order_Comment: BSv190 -> BSv191                           |
//+------------------------------------------------------------------+
#property copyright ""
#property link      ""
#property version   "191.0"
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

//--- Stochastic Gate (v183)
input string STOCH_SET          = "============"; //====== Stochastic Gate (v183) ======
input int    Stoch_K            = 5;              //Stoch K period (fast, responsive)
input int    Stoch_D            = 3;              //Stoch D smoothing
input int    Stoch_Slow         = 3;              //Stoch slowing
input double Stoch_OS           = 25.0;           //Stoch oversold level: BUY if K < this
input double Stoch_OB           = 75.0;           //Stoch overbought level: SELL if K > this

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
input double Risk_Pct           = 7.0;            //Risk%: 7.0 (v186 proven optimal Calmar)
input double Fixed_Lot          = 0.0;            //Fixed lot (0 = use Risk_Pct)
input int    Max_Buys           = 1;              //Max concurrent BUY
input int    Max_Sells          = 1;              //Max concurrent SELL

//--- Anti-Martingale
input string AM_SET             = "============"; //====== Anti-Martingale Settings ======
input int    WinStreak_Mid      = 5;              //Consec wins for Scale_Mid (v186: delayed=5)
input int    WinStreak_High     = 10;             //Consec wins for Scale_High (v186: delayed=10)
input double Scale_Mid          = 1.10;           //Scale_Mid (v186 proven)
input double Scale_High         = 1.25;           //Scale_High (v186 proven)

//--- Balance Peak Guard (v189/v190/v191)
input string EQUITY_GUARD_SET   = "============"; //====== Balance Peak Guard (v191) ======
input double Equity_DD_Guard_Pct   = 10.0;        //Reduce lots if balance drops >X% from peak
input double Equity_DD_Guard_Scale = 0.5;          //Lot scale factor when guard is active (0.5=half)

//--- Safety
input string SAFETY_SET         = "============"; //====== Safety Settings ======
input int    MaxSpread          = 35;             //Max spread in points
input int    Slippage           = 30;             //Max slippage in points
input int    Magic_Number       = 1912025;        //Magic Number
input string Order_Comment      = "BSv191";       //Order comment
input double Max_Daily_DD_Pct   = 8.0;            //Daily DD guard: 8%
input int    Max_Trades_Day     = 300;            //Max trades per day

//+------------------------------------------------------------------+
double   g_DayOpenEquity = 0;
bool     g_DailyDDHit   = false;
int      g_TradesToday  = 0;
datetime g_LastDay      = 0;
datetime g_LastBuyTime  = 0;
datetime g_LastSellTime = 0;
double   g_EquityPeak   = 0;   // Balance peak: only updated when NO open trades

//+------------------------------------------------------------------+
int OnInit()
{
   g_EquityPeak = AccountBalance();  // seed with current balance at EA start
   return(INIT_SUCCEEDED);
}
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

   // === v191 FIX: Update balance peak ONLY when no open trades ===
   // Partial closes immediately raise AccountBalance(), creating new peaks
   // mid-trade. This caused the guard to fire prematurely in v190 because
   // when the remaining half of a partially-closed trade then hits SL,
   // balance drops from the partial-close-inflated peak.
   // Fix: Only update the peak when all positions are fully closed
   // (openTrades == 0). Peak rises only on complete profitable trade cycles.
   double curEquity  = AccountEquity();   // used for daily DD guard + lots
   double curBalance = AccountBalance();  // used for peak guard (closed trades)

   int openBuysNow  = CountTradesByMagic(OP_BUY,  Magic_Number);
   int openSellsNow = CountTradesByMagic(OP_SELL, Magic_Number);
   int openTrades   = openBuysNow + openSellsNow;

   // Only update peak when position is flat (all trades closed)
   if(openTrades == 0 && curBalance > g_EquityPeak)
      g_EquityPeak = curBalance;

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
   if(ATR_Spike_Multi > 0)
   {
      double atr_slow = iATR(NULL, 0, ATR_Spike_MA_Period, 1);
      if(atr_slow > 0 && atr1 > ATR_Spike_Multi * atr_slow) return;
   }

   double bbLower1 = iBands(NULL, 0, BB_Period, BB_Dev, 0, PRICE_CLOSE, MODE_LOWER, 1);
   double bbUpper1 = iBands(NULL, 0, BB_Period, BB_Dev, 0, PRICE_CLOSE, MODE_UPPER, 1);
   double rsi1     = iRSI(NULL, 0, RSI_Period, PRICE_CLOSE, 1);
   double rsi2     = iRSI(NULL, 0, RSI_Period, PRICE_CLOSE, 2);

   // === STOCHASTIC GATE (v183) ===
   double stoch_k1 = iStochastic(NULL, 0, Stoch_K, Stoch_D, Stoch_Slow, MODE_SMA, 0, MODE_MAIN, 1);
   double stoch_k2 = iStochastic(NULL, 0, Stoch_K, Stoch_D, Stoch_Slow, MODE_SMA, 0, MODE_MAIN, 2);
   bool stochBuy  = (stoch_k1 < Stoch_OS) && (stoch_k1 > stoch_k2);
   bool stochSell = (stoch_k1 > Stoch_OB) && (stoch_k1 < stoch_k2);

   double slDist    = ATR_SL_Multi * atr1;
   double tpDist    = ATR_TP_Multi * atr1;
   double riskScale = GetRiskScale();

   // === v191: Balance Peak Guard (no-open-trades fix) ===
   // Peak is g_EquityPeak which only updates when openTrades==0.
   // Guard fires only when realized balance (after complete trade cycles)
   // drops >X% below the last fully-flat balance high.
   if(Equity_DD_Guard_Pct > 0 && g_EquityPeak > 0)
   {
      double ddFromPeak = (g_EquityPeak - curBalance) / g_EquityPeak * 100.0;
      if(ddFromPeak >= Equity_DD_Guard_Pct)
         riskScale *= Equity_DD_Guard_Scale;
   }

   double candleRange = High[1] - Low[1];
   double candleBodyB = Close[1] - Open[1];
   double candleBodyS = Open[1] - Close[1];

   //=== Signal BUY ===
   if(h4Bull && h1Bull && stochBuy)
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
   if(h4Bear && h1Bear && stochSell)
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
