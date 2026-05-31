//+------------------------------------------------------------------+
//|   Buy & Sell EA v250 - Flat Win Scaling (No Upscale on Wins)     |
//|   Framework: H4+H1 Direction / M5 Entry (v186 CONFIRMED BEST)   |
//|   LESSONS LEARNED:                                               |
//|     v186: BB+RSI+Stoch(25/75)+H4+H1 -> Cal=12.60  *** BEST ***  |
//|       Risk=7%, Scale_Mid=1.10, Scale_High=1.25                   |
//|     v243: Dollar cap FAILED — MaxDD 19.35%, Calmar=10.36         |
//|     v244: NO STOCH = CATASTROPHIC                                |
//|     v245: BB_Dev=2.0 FAILED (24× worse Calmar)                   |
//|     v246: M1 TIMEFRAME FAILED                                    |
//|     v247: EQUITY GUARD FAILED — Return=23.73%, MaxDD=8.69%       |
//|       Calmar=2.73 (5× WORSE than v186)                           |
//|       LESSON: Equity guard fires on floating losses → kills gains |
//|     v248: NO EQUITY GUARD — Return=166.21%, MaxDD=23.18%         |
//|       Calmar=7.17, 255 trades, Win=89.41%, MaxConsecWins=57      |
//|       PROBLEM: Anti-martingale 7%×1.25×$32k=$2,800 per trade    |
//|     v249: INITIAL BALANCE CAP — Return=119.29%, MaxDD=16.12%     |
//|       Calmar=7.40, 236 trades, Win=88.56%, MaxConsecWins=51      |
//|       Max loss=$914.94, Profit Factor=1.89                       |
//|       PROBLEM: Scale_High=1.25×$10k=$875 → 5.8% of $15k peak   |
//|         Win-streak upscaling adds $175 extra to first loss        |
//|         AND upscaled losses accumulate (6 losses = $1,791)        |
//|                                                                  |
//|   v250 HYPOTHESIS: Remove win-streak upscaling entirely          |
//|     Scale_Mid=1.0, Scale_High=1.0 (no bonus on wins)            |
//|     Keep loss downscaling: 0.5×/0.25×/0.1× after 1/2/3+ losses  |
//|     Keep initial balance cap from v249                           |
//|     Max single loss: 7%×1.0×$10k = $700 = 4.6% of $15k ✓       |
//|     6 consecutive losses: $700+$350+$175+$70+$70+$70 = $1,435   |
//|     On $15k peak: $1,435/$15k = 9.6% (still exceeds 5% target)  |
//|     BUT: first loss after win streak = $700 (was $875 in v249)  |
//|     AND: no upscaling variability — consistent $700 max          |
//|     Expected: MaxDD 12-14%, Calmar 8-11, similar trade count     |
//|     All v186 entry conditions UNCHANGED (NON-NEGOTIABLE)         |
//+------------------------------------------------------------------+
#property copyright ""
#property link      ""
#property version   "250.0"
#property strict

#include <stdlib.mqh>

//--- Session (v186 CONFIRMED OPTIMUM: 09:00-21:00)
input string SESSION_SET        = "============"; //====== Session Settings ======
input int    Session_Start_Hour = 9;
input int    Session_End_Hour   = 21;

//--- Trend Filter
input string TREND_SET          = "============"; //====== Trend Filter ======
input int    H4_EMA_Period      = 200;
input int    H1_EMA_Period      = 200;

//--- H1 RSI Gate (v186 CONFIRMED OPTIMUM)
input string H1RSI_SET          = "============"; //====== H1 RSI Gate ======
input int    H1_RSI_Period      = 14;
input double H1_RSI_Min         = 45.0;
input double H1_RSI_Max         = 75.0;
input double H1_RSI_Min_Sell    = 25.0;
input double H1_RSI_Max_Sell    = 55.0;

//--- BB Entry Signal (BB_Dev=2.5 NON-NEGOTIABLE)
input string S1_SET             = "============"; //====== BB Signal ======
input int    BB_Period          = 20;
input double BB_Dev             = 2.5;
input int    RSI_Period         = 14;
input double RSI_Buy            = 40.0;
input double RSI_Sell           = 60.0;
input double Body_Pct           = 0.2;

//--- Stochastic Gate (NON-NEGOTIABLE)
input string STOCH_SET          = "============"; //====== Stochastic Gate ======
input int    Stoch_K            = 5;
input int    Stoch_D            = 3;
input int    Stoch_Slow         = 3;
input double Stoch_OS           = 25.0;
input double Stoch_OB           = 75.0;

//--- Volatility Filter
input string VOL_SET            = "============"; //====== Volatility Filter ======
input double Max_ATR_Pct        = 0.60;
input int    ATR_Spike_MA_Period = 50;
input double ATR_Spike_Multi    = 1.8;

//--- Exit Settings (ATR_SL_Multi=0.8 NON-NEGOTIABLE)
input string EXIT_SET           = "============"; //====== Exit Settings ======
input int    ATR_Period         = 14;
input double ATR_SL_Multi       = 0.8;            // NON-NEGOTIABLE
input double ATR_TP_Multi       = 2.5;
input double Trail_ATR_Multi    = 0.8;
input double Partial_Pct        = 0.50;
input int    Max_Bars           = 100;

//--- Money Management
input string MONEY_SET          = "============"; //====== Money Management ======
input double Risk_Pct           = 7.0;            // v186 CONFIRMED
input double Fixed_Lot          = 0.0;
input int    Max_Buys           = 1;
input int    Max_Sells          = 1;

//--- Anti-Martingale (v250: flat wins, only loss downscaling)
input string AM_SET             = "============"; //====== Anti-Martingale ======
input int    WinStreak_Mid      = 5;
input int    WinStreak_High     = 10;
input double Scale_Mid          = 1.0;            // v250: NO win-streak upscale (was 1.10)
input double Scale_High         = 1.0;            // v250: NO win-streak upscale (was 1.25)

//--- Safety
input string SAFETY_SET         = "============"; //====== Safety Settings ======
input int    MaxSpread          = 35;
input int    Slippage           = 30;
input int    Magic_Number       = 2502057;
input string Order_Comment      = "BSv250";
input double Max_Daily_DD_Pct   = 8.0;
input int    Max_Trades_Day     = 300;

//+------------------------------------------------------------------+
double   g_DayOpenEquity  = 0;
bool     g_DailyDDHit     = false;
int      g_TradesToday    = 0;
datetime g_LastDay        = 0;
double   g_InitialBalance = 0;    // v249: snapshot at startup for position size cap

//+------------------------------------------------------------------+
int OnInit()
{
   g_InitialBalance = AccountBalance();   // Cap positions to this base — no runaway sizing
   return(INIT_SUCCEEDED);
}
void OnDeinit(const int reason) {}

//+------------------------------------------------------------------+
int CountLastStreak()
{
   datetime prevTime = TimeCurrent() + 1;
   int maxLook = 50;
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
   // v250: Scale_Mid=1.0 and Scale_High=1.0 mean upscaling is effectively disabled
   // Win streaks no longer increase position size — only loss recovery scaling applies
   if(streak >= WinStreak_High) return Scale_High;  // = 1.0
   if(streak >= WinStreak_Mid)  return Scale_Mid;   // = 1.0
   if(streak > 0)               return 1.0;
   if(streak == 0)              return 1.0;
   int losses = -streak;
   if(losses == 1) return 0.5;
   if(losses == 2) return 0.25;
   return 0.1;
}

//+------------------------------------------------------------------+
// v249/v250: Risk amount capped to initial balance sizing.
// v250 change: Scale_Mid/High = 1.0 so max riskAmt = 7%×1.0×$10k = $700
// Loss downscaling still applies: after 1 loss = $350, 2 losses = $175, 3+ = $70
double CalcLots(double slDist, double riskScale = 1.0)
{
   if(Fixed_Lot > 0) return NormalizeDouble(Fixed_Lot, 2);
   double tickVal  = MarketInfo(Symbol(), MODE_TICKVALUE);
   double tickSize = MarketInfo(Symbol(), MODE_TICKSIZE);
   if(tickVal <= 0 || tickSize <= 0) return MarketInfo(Symbol(), MODE_MINLOT);

   // Use current equity for normal sizing...
   double riskAmt = AccountEquity() * (Risk_Pct * riskScale) / 100.0;
   // ...but CAP it to initial balance so positions don't grow beyond initial-deposit sizes
   double capAmt  = g_InitialBalance * (Risk_Pct * riskScale) / 100.0;
   if(riskAmt > capAmt) riskAmt = capAmt;

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
         if(bars >= Max_Bars) OrderClose(tkt, OrderLots(), Bid, Slippage, clrYellow);
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

   double curBalance = AccountBalance();

   MqlDateTime dt;
   TimeToStruct(Time[0], dt);
   datetime today = StringToTime(StringFormat("%d.%02d.%02d", dt.year, dt.mon, dt.day));
   if(today != g_LastDay)
   {
      g_DayOpenEquity = curBalance;
      g_DailyDDHit    = false;
      g_TradesToday   = 0;
      g_LastDay       = today;
   }

   // Daily DD gate — balance-based (v247 fix: prevents false triggers on open floating losses)
   if(!g_DailyDDHit && g_DayOpenEquity > 0)
   {
      double ddPct = (g_DayOpenEquity - curBalance) / g_DayOpenEquity * 100.0;
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

   double bbUpper1 = iBands(NULL, 0, BB_Period, BB_Dev, 0, PRICE_CLOSE, MODE_UPPER, 1);
   double bbLower1 = iBands(NULL, 0, BB_Period, BB_Dev, 0, PRICE_CLOSE, MODE_LOWER, 1);

   double rsi1 = iRSI(NULL, 0, RSI_Period, PRICE_CLOSE, 1);
   double rsi2 = iRSI(NULL, 0, RSI_Period, PRICE_CLOSE, 2);

   double stoch_k1 = iStochastic(NULL, 0, Stoch_K, Stoch_D, Stoch_Slow, MODE_SMA, 0, MODE_MAIN, 1);
   double stoch_k2 = iStochastic(NULL, 0, Stoch_K, Stoch_D, Stoch_Slow, MODE_SMA, 0, MODE_MAIN, 2);

   // NON-NEGOTIABLE: Stochastic direction + level filter
   bool stochBuy  = (stoch_k1 < Stoch_OS) && (stoch_k1 > stoch_k2);
   bool stochSell = (stoch_k1 > Stoch_OB) && (stoch_k1 < stoch_k2);

   double slDist    = ATR_SL_Multi * atr1;
   double tpDist    = ATR_TP_Multi * atr1;
   double riskScale = GetRiskScale();   // v250: 1.0 for all wins, 0.5/0.25/0.1 for losses

   double candleRange = High[1] - Low[1];
   double candleBodyB = Close[1] - Open[1];
   double candleBodyS = Open[1] - Close[1];

   //=== BUY: v186 FULL FILTER SET — ALL NON-NEGOTIABLE ===
   if(h4Bull && h1Bull && stochBuy)
   {
      bool bbTouch   = (Low[1] <= bbLower1) && (Close[1] > bbLower1);
      bool rsiOS     = (rsi1 < RSI_Buy);
      bool rsiRising = (rsi1 > rsi2);
      bool bullBody  = (candleBodyB > 0) && (candleRange > 0)
                    && (candleBodyB >= Body_Pct * candleRange);

      if(bbTouch && rsiOS && rsiRising && bullBody)
      {
         if(CountTradesByMagic(OP_BUY, Magic_Number) < Max_Buys)
         {
            double entry = NormalizeDouble(Ask, Digits);
            double sl    = NormalizeDouble(entry - slDist, Digits);
            double tp    = NormalizeDouble(entry + tpDist, Digits);
            double lots  = CalcLots(slDist, riskScale);
            if(lots > 0)
            {
               int tkt = OrderSend(Symbol(), OP_BUY, lots, entry, Slippage,
                                   sl, tp, Order_Comment, Magic_Number, 0, clrGreen);
               if(tkt > 0) g_TradesToday++;
            }
         }
      }
   }

   //=== SELL: v186 FULL FILTER SET — ALL NON-NEGOTIABLE ===
   if(h4Bear && h1Bear && stochSell)
   {
      bool bbTouchUp  = (High[1] >= bbUpper1) && (Close[1] < bbUpper1);
      bool rsiOB      = (rsi1 > RSI_Sell);
      bool rsiFalling = (rsi1 < rsi2);
      bool bearBody   = (candleBodyS > 0) && (candleRange > 0)
                     && (candleBodyS >= Body_Pct * candleRange);

      if(bbTouchUp && rsiOB && rsiFalling && bearBody)
      {
         if(CountTradesByMagic(OP_SELL, Magic_Number) < Max_Sells)
         {
            double entry = NormalizeDouble(Bid, Digits);
            double sl    = NormalizeDouble(entry + slDist, Digits);
            double tp    = NormalizeDouble(entry - tpDist, Digits);
            double lots  = CalcLots(slDist, riskScale);
            if(lots > 0)
            {
               int tkt = OrderSend(Symbol(), OP_SELL, lots, entry, Slippage,
                                   sl, tp, Order_Comment, Magic_Number, 0, clrRed);
               if(tkt > 0) g_TradesToday++;
            }
         }
      }
   }
}
//+------------------------------------------------------------------+
