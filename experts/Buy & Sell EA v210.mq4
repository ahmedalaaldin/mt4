//+------------------------------------------------------------------+
//|   Buy & Sell EA v210 - Wider Take Profit (ATR_TP = 3.0)          |
//|   Framework: H4+H1 Direction / M5 Entry                          |
//|   LESSONS LEARNED:                                                |
//|     v186: 7.0%, Streak=5/10   -> 237.84% ret, 18.87% DD, Cal=12.60|
//|            BEST Calmar so far: ALL M5 parameters proven optimal    |
//|     v192-v197: Exhausted ALL M5 parameter variations              |
//|     v198: M15 timeframe -> catastrophic loss (M15 too slow/noisy) |
//|     v199: BB_Period=14 -> worse (fewer AND lower-quality signals)  |
//|     v200: BB_Period=30 -> worse (DD 31.02%, Calmar 2.89)          |
//|     v201: Session=09:00-17:00 -> worse (fewer trades, DD 30.23%)  |
//|     v202: ATR_Spike_Multi=1.5 -> worse (WR 88.60%, DD 31.18%)    |
//|     v203: Scale_Mid=1.0, Scale_High=1.0 -> +147.99%, Cal 6.89    |
//|       LESSON: Win-streak scaling IMPROVES Calmar. v186 optimal.   |
//|     v204: Max_Daily_DD_Pct=5.0 -> +66.68%, Cal 3.48              |
//|       LESSON: Tight daily DD guard blocks recovery sessions.       |
//|       8% daily guard in v186 is GLOBAL OPTIMUM.                   |
//|     v205: M1 timeframe -> -89.22%, 25% modelling quality (invalid)|
//|       LESSON: M1 data quality too low for valid MT4 backtest.     |
//|       M5 is the ONLY viable timeframe. M1 and M15 both failed.   |
//|     v206: Remove H1 RSI gate -> +324.91%, DD 26.09%, Cal 12.45   |
//|       LESSON: H1 RSI gate removal adds trades (+95) but also DD.  |
//|       Calmar 12.45 vs v186's 12.60 — gate slightly beneficial.    |
//|     v207: Max_Buys=2, Risk_Pct=5% -> +109.83%, DD 16.39%, Cal 6.70|
//|       LESSON: Concurrent positions don't increase trade count.     |
//|       Reducing Risk_Pct kills compounding — both changes failed.  |
//|     v208: Scale_High=1.50 -> +219.35%, DD 23.11%, Cal=9.49       |
//|       LESSON: More aggressive scaling (1.50x) HURTS both return   |
//|       AND drawdown. 1.25x in v186 is GLOBAL OPTIMUM for Scale_High.|
//|     v209: WinStreak_Mid=3, WinStreak_High=8 -> +178.99%, DD 23.96%|
//|       Calmar 7.47. LESSON: Earlier thresholds HURT — more trades  |
//|       execute at elevated risk before streak is truly established. |
//|       v186's 5/10 thresholds are GLOBAL OPTIMUM.                  |
//|   v210 HYPOTHESIS: ATR_TP_Multi = 3.0 (wider take profit)         |
//|     Currently: TP = 2.5 × ATR, TP/SL ratio = 2.5/0.8 = 3.125    |
//|     v210 tries: TP = 3.0 × ATR, TP/SL ratio = 3.0/0.8 = 3.75    |
//|     Rationale: BB mean-reversion entries are high-probability.     |
//|     After touching the 2.5SD band, price often fully reverts to    |
//|     the mean (BB midline) and BEYOND. A wider TP captures that    |
//|     full move. Even if win rate dips slightly (e.g. 87% vs 90%),  |
//|     the EV per trade increases:                                    |
//|       Current: 0.90×2.5 - 0.10×0.8 = 2.17 ATR/trade              |
//|       v210:    0.87×3.0 - 0.13×0.8 = 2.51 ATR/trade (+16%)       |
//|     This should boost total return while DD stays similar.         |
//|     ALL other parameters = v186 GLOBAL OPTIMUM.                   |
//|     Run with PERIOD = M5 in Strategy Tester.                      |
//+------------------------------------------------------------------+
#property copyright ""
#property link      ""
#property version   "210.0"
#property strict

#include <stdlib.mqh>

//--- Session
input string SESSION_SET        = "============"; //====== Session Settings ======
input int    Session_Start_Hour = 9;              //Session Start Hour
input int    Session_End_Hour   = 21;             //Session End Hour

//--- Trend Filter (H4 + H1 — both required, same as v186)
input string TREND_SET          = "============"; //====== Trend Filter ======
input int    H4_EMA_Period      = 200;            //H4 EMA period (macro trend)
input int    H1_EMA_Period      = 200;            //H1 EMA period (intermediate trend)

//--- H1 RSI Gate (v186 optimal values — confirmed better than removing)
input string H1RSI_SET          = "============"; //====== H1 RSI Gate ======
input int    H1_RSI_Period      = 14;             //H1 RSI period
input double H1_RSI_Min         = 45.0;           //BUY: H1 RSI minimum [45,75]
input double H1_RSI_Max         = 75.0;           //BUY: H1 RSI maximum
input double H1_RSI_Min_Sell    = 25.0;           //SELL: H1 RSI minimum [25,55]
input double H1_RSI_Max_Sell    = 55.0;           //SELL: H1 RSI maximum

//--- Bollinger Bands (M5 entry bar)
input string BB_SET             = "============"; //====== BB Settings ======
input int    BB_Period          = 20;             //BB period: 20 (GLOBAL OPTIMUM — NON-NEGOTIABLE)
input double BB_Dev             = 2.5;            //BB SD: 2.5 (proven 90%+ WR — NON-NEGOTIABLE)

//--- Signal: M5 BB Touch
input string S1_SET             = "============"; //====== Signal: BB Touch ======
input int    RSI_Period         = 14;             //RSI period (M5 bars)
input double RSI_Buy            = 40.0;           //RSI max for BUY (v186 optimal)
input double RSI_Sell           = 60.0;           //RSI min for SELL (v186 optimal)
input double Body_Pct           = 0.2;            //Min body fraction
input int    Min_Bar_Gap        = 1;              //Min bars between entries

//--- Stochastic Gate
input string STOCH_SET          = "============"; //====== Stochastic Gate ======
input int    Stoch_K            = 5;              //Stoch K period
input int    Stoch_D            = 3;              //Stoch D smoothing
input int    Stoch_Slow         = 3;              //Stoch slowing
input double Stoch_OS           = 25.0;           //Stoch oversold: BUY if K < this (v186 optimal)
input double Stoch_OB           = 75.0;           //Stoch overbought: SELL if K > this (v186 optimal)

//--- Volatility Filter
input string VOL_SET            = "============"; //====== Volatility Filter ======
input double Max_ATR_Pct        = 0.60;           //Max ATR as % of price
input int    ATR_Spike_MA_Period = 50;             //Slow ATR for spike detection
input double ATR_Spike_Multi    = 1.8;            //Skip if fast ATR > 1.8 * slow ATR (GLOBAL OPTIMUM)

//--- Exit Settings (v210 CHANGE: ATR_TP_Multi = 3.0)
input string EXIT_SET           = "============"; //====== Exit Settings ======
input int    ATR_Period         = 14;             //ATR period
input double ATR_SL_Multi       = 0.8;            //SL = ATR x 0.8 (v186 optimal)
input double ATR_TP_Multi       = 3.0;            //v210 CHANGE: TP = ATR x 3.0 (was 2.5) — wider profit target
input double Trail_ATR_Multi    = 0.8;            //Trail SL offset: 0.8 (v186 optimal)
input int    Max_Bars           = 100;            //Force-close after N bars

//--- Money Management (v186 optimal values)
input string MONEY_SET          = "============"; //====== Money Management ======
input double Risk_Pct           = 7.0;            //7% — v186 GLOBAL OPTIMUM
input double Fixed_Lot          = 0.0;            //Fixed lot (0 = use Risk_Pct)
input int    Max_Buys           = 1;              //1 concurrent BUY — v186 GLOBAL OPTIMUM
input int    Max_Sells          = 1;              //1 concurrent SELL — v186 GLOBAL OPTIMUM

//--- Anti-Martingale (v186 optimal values — all v208/v209 changes were worse)
input string AM_SET             = "============"; //====== Anti-Martingale ======
input int    WinStreak_Mid      = 5;              //v186 GLOBAL OPTIMUM: 1.10x after 5 wins
input int    WinStreak_High     = 10;             //v186 GLOBAL OPTIMUM: 1.25x after 10 wins
input double Scale_Mid          = 1.10;           //1.10x at WinStreak_Mid+ wins (v186 optimal)
input double Scale_High         = 1.25;           //1.25x at WinStreak_High+ wins (v186 optimal)

//--- Safety
input string SAFETY_SET         = "============"; //====== Safety Settings ======
input int    MaxSpread          = 35;             //Max spread in points
input int    Slippage           = 30;             //Max slippage in points
input int    Magic_Number       = 2102038;        //Magic Number
input string Order_Comment      = "BSv210";       //Order comment
input double Max_Daily_DD_Pct   = 8.0;            //Daily DD guard: 8% (v186 GLOBAL OPTIMUM)
input int    Max_Trades_Day     = 300;            //Max trades per day

//+------------------------------------------------------------------+
double   g_DayOpenEquity = 0;
bool     g_DailyDDHit   = false;
int      g_TradesToday  = 0;
datetime g_LastDay      = 0;
datetime g_LastBuyTime  = 0;
datetime g_LastSellTime = 0;

//+------------------------------------------------------------------+
int OnInit()
{
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
   if(streak >= WinStreak_High) return Scale_High;  // 1.25x at 10+ wins (v186 optimal)
   if(streak >= WinStreak_Mid)  return Scale_Mid;   // 1.10x at 5+ wins (v186 optimal)
   if(streak > 0)               return 1.0;
   if(streak == 0)              return 1.0;
   int losses = -streak;
   if(losses == 1) return 0.5;   // 1 loss: half risk
   if(losses == 2) return 0.25;  // 2 losses: quarter risk
   return 0.1;                   // 3+ losses: minimal risk
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

   // H4 + H1 EMA direction filter + H1 RSI gate (v186 confirmed optimal)
   double h4_ema  = iMA(NULL, PERIOD_H4, H4_EMA_Period, 0, MODE_EMA, PRICE_CLOSE, 0);
   double h1_ema  = iMA(NULL, PERIOD_H1, H1_EMA_Period, 0, MODE_EMA, PRICE_CLOSE, 0);
   double h1_rsi1 = iRSI(NULL, PERIOD_H1, H1_RSI_Period, PRICE_CLOSE, 1);

   bool h4Bull = (iClose(NULL, PERIOD_H4, 1) > h4_ema);
   bool h4Bear = (iClose(NULL, PERIOD_H4, 1) < h4_ema);

   bool h1Bull = (iClose(NULL, PERIOD_H1, 1) > h1_ema)
              && (h1_rsi1 >= H1_RSI_Min) && (h1_rsi1 <= H1_RSI_Max);
   bool h1Bear = (iClose(NULL, PERIOD_H1, 1) < h1_ema)
              && (h1_rsi1 >= H1_RSI_Min_Sell) && (h1_rsi1 <= H1_RSI_Max_Sell);

   double atr1 = iATR(NULL, 0, ATR_Period, 1);
   if(atr1 <= 0) return;

   if(Max_ATR_Pct > 0)
   {
      double price1 = iClose(NULL, 0, 1);
      if(price1 > 0 && (atr1 / price1 * 100.0) > Max_ATR_Pct) return;
   }
   if(ATR_Spike_Multi > 0)
   {
      double atr_slow = iATR(NULL, 0, ATR_Spike_MA_Period, 1);
      if(atr_slow > 0 && atr1 > ATR_Spike_Multi * atr_slow) return;
   }

   double bbLower1 = iBands(NULL, 0, BB_Period, BB_Dev, 0, PRICE_CLOSE, MODE_LOWER, 1);
   double bbUpper1 = iBands(NULL, 0, BB_Period, BB_Dev, 0, PRICE_CLOSE, MODE_UPPER, 1);
   double rsi1     = iRSI(NULL, 0, RSI_Period, PRICE_CLOSE, 1);
   double rsi2     = iRSI(NULL, 0, RSI_Period, PRICE_CLOSE, 2);

   double stoch_k1 = iStochastic(NULL, 0, Stoch_K, Stoch_D, Stoch_Slow, MODE_SMA, 0, MODE_MAIN, 1);
   double stoch_k2 = iStochastic(NULL, 0, Stoch_K, Stoch_D, Stoch_Slow, MODE_SMA, 0, MODE_MAIN, 2);
   bool stochBuy  = (stoch_k1 < Stoch_OS) && (stoch_k1 > stoch_k2);
   bool stochSell = (stoch_k1 > Stoch_OB) && (stoch_k1 < stoch_k2);

   double slDist    = ATR_SL_Multi * atr1;
   double tpDist    = ATR_TP_Multi * atr1;   // v210: 3.0 * ATR (wider TP)
   double riskScale = GetRiskScale();

   double candleRange = High[1] - Low[1];
   double candleBodyB = Close[1] - Open[1];
   double candleBodyS = Open[1] - Close[1];

   //=== Signal BUY: H4 bull + H1 bull(EMA+RSI[45,75]) + BB(20,2.5) + RSI<40 + Stoch<25
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

   //=== Signal SELL: H4 bear + H1 bear(EMA+RSI[25,55]) + BB(20,2.5) + RSI>60 + Stoch>75
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
