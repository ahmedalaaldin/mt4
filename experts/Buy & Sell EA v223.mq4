//+------------------------------------------------------------------+
//|   Buy & Sell EA v223 - Dual-Timeframe M5 + M1 Mean-Reversion     |
//|   Framework: H4+H1 Direction / M5+M1 Entry                       |
//|   LESSONS LEARNED:                                                |
//|     v186: Cal=12.60  237.84% ret / 18.87% DD — GLOBAL OPTIMUM    |
//|     v215-v222: ALL modifications worse than v186                  |
//|     v221: Gentler scaling  -> Cal=7.06  (smaller peak = MORE DD%) |
//|     v222: H1 ADX<25 filter -> Cal=2.05  (cuts good setups, WR    |
//|           didn't improve, MaxDD still 19.83%, return crashes 41%) |
//|   v223 HYPOTHESIS: Dual-Timeframe M5 + M1                        |
//|     User request: "use the same strategies on different time       |
//|     frames to increase profits."                                   |
//|     M5 COMPONENT: identical to v186 (7% risk, Magic_M5=2232038)  |
//|     M1 COMPONENT: same BB+RSI+Stoch on M1 bars (4% risk,         |
//|       Magic_M1=2231038). M1 ATR for SL, M1 BB midline for exits. |
//|     Both share H4/H1 EMA + H1 RSI gate + ATR spike filter.       |
//|     Independent anti-martingale scaling per component.            |
//|     Expected: 3-5x more trades, maintained WR, diversified DD.   |
//|   ALL v186 GLOBAL OPTIMA preserved for M5 component.             |
//|   Run with PERIOD = M5 in Strategy Tester.                        |
//+------------------------------------------------------------------+
#property copyright ""
#property link      ""
#property version   "223.0"
#property strict

#include <stdlib.mqh>

//--- Session
input string SESSION_SET        = "============"; //====== Session Settings ======
input int    Session_Start_Hour = 9;              //Session Start Hour
input int    Session_End_Hour   = 21;             //Session End Hour

//--- Trend Filter (shared by M5 and M1)
input string TREND_SET          = "============"; //====== Trend Filter ======
input int    H4_EMA_Period      = 200;            //H4 EMA period (macro trend)
input int    H1_EMA_Period      = 200;            //H1 EMA period (intermediate trend)

//--- H1 RSI Gate (shared)
input string H1RSI_SET          = "============"; //====== H1 RSI Gate ======
input int    H1_RSI_Period      = 14;             //H1 RSI period
input double H1_RSI_Min         = 45.0;           //BUY: H1 RSI minimum (v186 GLOBAL OPTIMUM)
input double H1_RSI_Max         = 75.0;           //BUY: H1 RSI maximum
input double H1_RSI_Min_Sell    = 25.0;           //SELL: H1 RSI minimum
input double H1_RSI_Max_Sell    = 55.0;           //SELL: H1 RSI maximum

//--- Bollinger Bands (shared by M5 and M1)
input string BB_SET             = "============"; //====== BB Settings ======
input int    BB_Period          = 20;             //BB period: 20 (NON-NEGOTIABLE GLOBAL OPTIMUM)
input double BB_Dev             = 2.5;            //BB SD: 2.5 (NON-NEGOTIABLE GLOBAL OPTIMUM)

//--- Signal Parameters (shared by M5 and M1)
input string S1_SET             = "============"; //====== Signal Parameters ======
input int    RSI_Period         = 14;             //RSI period
input double RSI_Buy            = 40.0;           //RSI max for BUY (v186 optimal)
input double RSI_Sell           = 60.0;           //RSI min for SELL (v186 optimal)
input double Body_Pct           = 0.2;            //Min body fraction
input int    Min_Bar_Gap        = 1;              //Min bars between entries

//--- Stochastic Gate (shared)
input string STOCH_SET          = "============"; //====== Stochastic Gate ======
input int    Stoch_K            = 5;              //Stoch K period
input int    Stoch_D            = 3;              //Stoch D smoothing
input int    Stoch_Slow         = 3;              //Stoch slowing
input double Stoch_OS           = 25.0;           //BUY only if K < 25 (GLOBAL OPTIMUM)
input double Stoch_OB           = 75.0;           //SELL only if K > 75 (GLOBAL OPTIMUM)

//--- Volatility Filter (shared)
input string VOL_SET            = "============"; //====== Volatility Filter ======
input double Max_ATR_Pct        = 0.60;           //Max ATR as % of price
input int    ATR_Spike_MA_Period = 50;             //Slow ATR period for spike detection
input double ATR_Spike_Multi    = 1.8;            //Skip if fast ATR > 1.8 * slow (GLOBAL OPTIMUM)

//--- Exit Settings (v186 GLOBAL OPTIMA)
input string EXIT_SET           = "============"; //====== Exit Settings ======
input int    ATR_Period         = 14;             //ATR period
input double ATR_SL_Multi       = 0.8;            //SL = ATR x 0.8 (v186 GLOBAL OPTIMUM)
input double ATR_TP_Multi       = 2.5;            //TP multiplier (trail exits first)
input double Trail_ATR_Multi    = 0.8;            //Trail offset: 0.8 ATR (v186 optimal)
input double Partial_Pct        = 0.50;           //50% partial at BB midline (v186 optimum)
input int    Max_Bars_M5        = 100;            //M5: force-close after N M5 bars
input int    Max_Bars_M1        = 100;            //M1: force-close after N M1 bars

//--- M5 Component (v186 GLOBAL OPTIMA)
input string M5_SET             = "============"; //====== M5 Component (v186 Optimal) ======
input double Risk_Pct_M5        = 7.0;            //M5 risk per trade: 7% (v186 GLOBAL OPTIMUM)
input int    Max_Buys_M5        = 1;              //Max concurrent M5 BUYs (v186 GLOBAL OPTIMUM)
input int    Max_Sells_M5       = 1;              //Max concurrent M5 SELLs (v186 GLOBAL OPTIMUM)
input int    Magic_Number_M5    = 2232038;        //M5 Magic Number
input string Comment_M5         = "BSv223M5";     //M5 order comment
input int    WinStreak_Mid_M5   = 5;              //M5 upscale at 5 wins (v186 GLOBAL OPTIMUM)
input int    WinStreak_High_M5  = 10;             //M5 upscale at 10 wins (v186 GLOBAL OPTIMUM)
input double Scale_Mid_M5       = 1.10;           //M5: 1.10x after 5 wins (v186 GLOBAL OPTIMUM)
input double Scale_High_M5      = 1.25;           //M5: 1.25x after 10 wins (v186 GLOBAL OPTIMUM)

//--- M1 Component (NEW — same logic, M1 bars)
input string M1_SET             = "============"; //====== M1 Component (v223 NEW) ======
input double Risk_Pct_M1        = 4.0;            //M1 risk per trade: 4% (lower, M1 noisier)
input int    Max_Buys_M1        = 1;              //Max concurrent M1 BUYs
input int    Max_Sells_M1       = 1;              //Max concurrent M1 SELLs
input int    Magic_Number_M1    = 2231038;        //M1 Magic Number
input string Comment_M1         = "BSv223M1";     //M1 order comment
input int    WinStreak_Mid_M1   = 5;              //M1 upscale at 5 wins
input int    WinStreak_High_M1  = 10;             //M1 upscale at 10 wins
input double Scale_Mid_M1       = 1.10;           //M1: 1.10x after 5 wins
input double Scale_High_M1      = 1.25;           //M1: 1.25x after 10 wins

//--- Safety (shared)
input string SAFETY_SET         = "============"; //====== Safety Settings ======
input int    MaxSpread          = 35;             //Max spread in points
input int    Slippage           = 30;             //Max slippage in points
input double Max_Daily_DD_Pct   = 8.0;            //Daily DD guard: 8% (v186 GLOBAL OPTIMUM)
input int    Max_Trades_Day     = 300;            //Max total trades per day

//+------------------------------------------------------------------+
double   g_DayOpenEquity = 0;
bool     g_DailyDDHit   = false;
int      g_TradesToday  = 0;
datetime g_LastDay      = 0;

datetime g_LastBuyTimeM5  = 0;
datetime g_LastSellTimeM5 = 0;
datetime g_LastBuyTimeM1  = 0;
datetime g_LastSellTimeM1 = 0;

//+------------------------------------------------------------------+
int OnInit() { return(INIT_SUCCEEDED); }
void OnDeinit(const int reason) {}

//+------------------------------------------------------------------+
int CountLastStreak(int magic)
{
   datetime prevTime  = TimeCurrent() + 1;
   int      maxLook   = 40;
   bool     isWin     = false;
   bool     firstFound = false;
   int      count     = 0;
   for(int pass = 0; pass < maxLook; pass++)
   {
      datetime bestTime   = 0;
      bool     bestResult = false;
      for(int i = OrdersHistoryTotal() - 1; i >= 0; i--)
      {
         if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
         if(OrderSymbol() != Symbol()) continue;
         if(OrderMagicNumber() != magic) continue;
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
double GetRiskScale(int magic, int streakMid, int streakHigh,
                    double scaleMid, double scaleHigh)
{
   int streak = CountLastStreak(magic);
   if(streak >= streakHigh) return scaleHigh;
   if(streak >= streakMid)  return scaleMid;
   if(streak > 0)           return 1.0;
   if(streak == 0)          return 1.0;
   int losses = -streak;
   if(losses == 1) return 0.5;
   if(losses == 2) return 0.25;
   return 0.1;
}

//+------------------------------------------------------------------+
double CalcLots(double slDist, double riskPct, double riskScale)
{
   double tickVal  = MarketInfo(Symbol(), MODE_TICKVALUE);
   double tickSize = MarketInfo(Symbol(), MODE_TICKSIZE);
   if(tickVal <= 0 || tickSize <= 0) return MarketInfo(Symbol(), MODE_MINLOT);
   double riskAmt  = AccountEquity() * (riskPct * riskScale) / 100.0;
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
      if(OrderSymbol() != Symbol()) continue;
      int mag = OrderMagicNumber();
      if(mag != Magic_Number_M5 && mag != Magic_Number_M1) continue;
      if(OrderType() == OP_BUY)
         OrderClose(OrderTicket(), OrderLots(), Bid, Slippage, clrOrange);
      else if(OrderType() == OP_SELL)
         OrderClose(OrderTicket(), OrderLots(), Ask, Slippage, clrOrange);
   }
}

//+------------------------------------------------------------------+
// tf=0 for M5 component, tf=PERIOD_M1 for M1 component
void ManageExits(int magic, int tf, int maxBars)
{
   double atr   = iATR(NULL, tf, ATR_Period, 1);
   double bbMid = iBands(NULL, tf, BB_Period, BB_Dev, 0, PRICE_CLOSE, MODE_MAIN, 0);
   if(atr <= 0 || bbMid <= 0) return;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != magic) continue;

      int    tkt       = OrderTicket();
      double openPrice = OrderOpenPrice();
      double currentSL = OrderStopLoss();
      int    type      = OrderType();
      int    bars      = (int)MathRound((TimeCurrent() - OrderOpenTime())
                          / (PeriodSeconds(tf > 0 ? tf : Period())));

      if(type == OP_BUY)
      {
         bool partialDone = (currentSL >= openPrice);
         if(!partialDone && Bid >= bbMid)
         {
            double stepLot  = MarketInfo(Symbol(), MODE_LOTSTEP);
            double minLot   = MarketInfo(Symbol(), MODE_MINLOT);
            double partLots = MathFloor(OrderLots() * Partial_Pct / stepLot) * stepLot;
            if(partLots >= minLot && partLots < OrderLots())
            {
               if(OrderClose(tkt, partLots, Bid, Slippage, clrCyan))
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
         if(bars >= maxBars) OrderClose(tkt, OrderLots(), Bid, Slippage, clrYellow);
      }
      else if(type == OP_SELL)
      {
         bool partialDone = (currentSL > 0 && currentSL <= openPrice);
         if(!partialDone && Ask <= bbMid)
         {
            double stepLot  = MarketInfo(Symbol(), MODE_LOTSTEP);
            double minLot   = MarketInfo(Symbol(), MODE_MINLOT);
            double partLots = MathFloor(OrderLots() * Partial_Pct / stepLot) * stepLot;
            if(partLots >= minLot && partLots < OrderLots())
            {
               if(OrderClose(tkt, partLots, Ask, Slippage, clrCyan))
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
         if(bars >= maxBars) OrderClose(tkt, OrderLots(), Ask, Slippage, clrYellow);
      }
   }
}

//+------------------------------------------------------------------+
// Shared entry logic for both timeframes
// tf=0 means current chart (M5); tf=PERIOD_M1 means M1 bars
void TryEntry(int tf, int magic, string cmt, double riskPct,
              int maxBuys, int maxSells,
              int streakMid, int streakHigh, double scaleMid, double scaleHigh,
              datetime &lastBuyTime, datetime &lastSellTime)
{
   double atr1 = iATR(NULL, tf, ATR_Period, 1);
   if(atr1 <= 0) return;

   // ATR percent filter (use raw price for reference)
   if(Max_ATR_Pct > 0)
   {
      double price1 = iClose(NULL, tf, 1);
      if(price1 > 0 && (atr1 / price1 * 100.0) > Max_ATR_Pct) return;
   }
   // ATR spike filter
   if(ATR_Spike_Multi > 0)
   {
      double atrSlow = iATR(NULL, tf, ATR_Spike_MA_Period, 1);
      if(atrSlow > 0 && atr1 > ATR_Spike_Multi * atrSlow) return;
   }

   double bbLower1 = iBands(NULL, tf, BB_Period, BB_Dev, 0, PRICE_CLOSE, MODE_LOWER, 1);
   double bbUpper1 = iBands(NULL, tf, BB_Period, BB_Dev, 0, PRICE_CLOSE, MODE_UPPER, 1);
   double rsi1     = iRSI(NULL, tf, RSI_Period, PRICE_CLOSE, 1);
   double rsi2     = iRSI(NULL, tf, RSI_Period, PRICE_CLOSE, 2);

   double stoch_k1 = iStochastic(NULL, tf, Stoch_K, Stoch_D, Stoch_Slow, MODE_SMA, 0, MODE_MAIN, 1);
   double stoch_k2 = iStochastic(NULL, tf, Stoch_K, Stoch_D, Stoch_Slow, MODE_SMA, 0, MODE_MAIN, 2);
   bool stochBuy   = (stoch_k1 < Stoch_OS) && (stoch_k1 > stoch_k2);
   bool stochSell  = (stoch_k1 > Stoch_OB) && (stoch_k1 < stoch_k2);

   double cHigh  = iHigh(NULL, tf, 1);
   double cLow   = iLow(NULL, tf, 1);
   double cClose = iClose(NULL, tf, 1);
   double cOpen  = iOpen(NULL, tf, 1);

   double candleRange = cHigh - cLow;
   double candleBodyB = cClose - cOpen;
   double candleBodyS = cOpen  - cClose;

   double slDist    = ATR_SL_Multi * atr1;
   double tpDist    = ATR_TP_Multi * atr1;
   double riskScale = GetRiskScale(magic, streakMid, streakHigh, scaleMid, scaleHigh);

   // Shared H4/H1 direction + RSI gate
   double h4_ema  = iMA(NULL, PERIOD_H4, H4_EMA_Period, 0, MODE_EMA, PRICE_CLOSE, 0);
   double h1_ema  = iMA(NULL, PERIOD_H1, H1_EMA_Period, 0, MODE_EMA, PRICE_CLOSE, 0);
   double h1_rsi1 = iRSI(NULL, PERIOD_H1, H1_RSI_Period, PRICE_CLOSE, 1);

   bool h4Bull = (iClose(NULL, PERIOD_H4, 1) > h4_ema);
   bool h4Bear = (iClose(NULL, PERIOD_H4, 1) < h4_ema);
   bool h1Bull = (iClose(NULL, PERIOD_H1, 1) > h1_ema)
              && (h1_rsi1 >= H1_RSI_Min) && (h1_rsi1 <= H1_RSI_Max);
   bool h1Bear = (iClose(NULL, PERIOD_H1, 1) < h1_ema)
              && (h1_rsi1 >= H1_RSI_Min_Sell) && (h1_rsi1 <= H1_RSI_Max_Sell);

   int tfSecs = PeriodSeconds(tf > 0 ? tf : Period());

   //=== Signal BUY
   if(h4Bull && h1Bull && stochBuy)
   {
      bool bbTouch   = (cLow <= bbLower1) && (cClose > bbLower1);
      bool rsiOS     = (rsi1 < RSI_Buy);
      bool rsiRising = (rsi1 > rsi2);
      bool bullBody  = (candleBodyB > 0) && (candleRange > 0)
                    && (candleBodyB >= Body_Pct * candleRange);

      if(bbTouch && rsiOS && rsiRising && bullBody)
      {
         int openBuys  = CountTradesByMagic(OP_BUY, magic);
         int barsSince = (int)((TimeCurrent() - lastBuyTime) / tfSecs);
         if(openBuys < maxBuys && barsSince >= Min_Bar_Gap)
         {
            double entry = NormalizeDouble(Ask, Digits);
            double sl    = NormalizeDouble(entry - slDist, Digits);
            double tp    = NormalizeDouble(entry + tpDist, Digits);
            double lots  = CalcLots(slDist, riskPct, riskScale);
            if(lots > 0)
            {
               int tkt = OrderSend(Symbol(), OP_BUY, lots, entry, Slippage,
                                   sl, tp, cmt, magic, 0, clrGreen);
               if(tkt > 0) { g_TradesToday++; lastBuyTime = TimeCurrent(); }
            }
         }
      }
   }

   //=== Signal SELL
   if(h4Bear && h1Bear && stochSell)
   {
      bool bbTouchUp  = (cHigh >= bbUpper1) && (cClose < bbUpper1);
      bool rsiOB      = (rsi1 > RSI_Sell);
      bool rsiFalling = (rsi1 < rsi2);
      bool bearBody   = (candleBodyS > 0) && (candleRange > 0)
                     && (candleBodyS >= Body_Pct * candleRange);

      if(bbTouchUp && rsiOB && rsiFalling && bearBody)
      {
         int openSells = CountTradesByMagic(OP_SELL, magic);
         int barsSince = (int)((TimeCurrent() - lastSellTime) / tfSecs);
         if(openSells < maxSells && barsSince >= Min_Bar_Gap)
         {
            double entry = NormalizeDouble(Bid, Digits);
            double sl    = NormalizeDouble(entry + slDist, Digits);
            double tp    = NormalizeDouble(entry - tpDist, Digits);
            double lots  = CalcLots(slDist, riskPct, riskScale);
            if(lots > 0)
            {
               int tkt = OrderSend(Symbol(), OP_SELL, lots, entry, Slippage,
                                   sl, tp, cmt, magic, 0, clrRed);
               if(tkt > 0) { g_TradesToday++; lastSellTime = TimeCurrent(); }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
void OnTick()
{
   static datetime s_LastM5Bar = 0;
   static datetime s_LastM1Bar = 0;

   bool isNewM5Bar = (Time[0] != s_LastM5Bar);
   bool isNewM1Bar = (iTime(NULL, PERIOD_M1, 0) != s_LastM1Bar);
   if(isNewM5Bar) s_LastM5Bar = Time[0];
   if(isNewM1Bar) s_LastM1Bar = iTime(NULL, PERIOD_M1, 0);

   // Daily reset
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

   // Daily DD guard
   if(!g_DailyDDHit && g_DayOpenEquity > 0)
   {
      double ddPct = (g_DayOpenEquity - AccountEquity()) / g_DayOpenEquity * 100.0;
      if(ddPct >= Max_Daily_DD_Pct) { CloseAllTrades(); g_DailyDDHit = true; return; }
   }
   if(g_DailyDDHit) return;

   // Manage exits for both components on every tick
   ManageExits(Magic_Number_M5, 0,           Max_Bars_M5);
   ManageExits(Magic_Number_M1, PERIOD_M1,   Max_Bars_M1);

   // Check session + spread + daily trade limit
   bool inSession = (dt.hour >= Session_Start_Hour && dt.hour < Session_End_Hour);
   if(!inSession) return;
   if(MarketInfo(Symbol(), MODE_SPREAD) > MaxSpread) return;
   if(g_TradesToday >= Max_Trades_Day) return;

   // M5 entries on new M5 bar
   if(isNewM5Bar)
   {
      TryEntry(0, Magic_Number_M5, Comment_M5, Risk_Pct_M5,
               Max_Buys_M5, Max_Sells_M5,
               WinStreak_Mid_M5, WinStreak_High_M5, Scale_Mid_M5, Scale_High_M5,
               g_LastBuyTimeM5, g_LastSellTimeM5);
   }

   // M1 entries on new M1 bar
   if(isNewM1Bar)
   {
      TryEntry(PERIOD_M1, Magic_Number_M1, Comment_M1, Risk_Pct_M1,
               Max_Buys_M1, Max_Sells_M1,
               WinStreak_Mid_M1, WinStreak_High_M1, Scale_Mid_M1, Scale_High_M1,
               g_LastBuyTimeM1, g_LastSellTimeM1);
   }
}
//+------------------------------------------------------------------+
