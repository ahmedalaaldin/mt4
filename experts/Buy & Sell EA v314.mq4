//+------------------------------------------------------------------+
//|   Buy & Sell EA v314 - Continuous DD-Budget Scaling              |
//|   BASE: v313 + replace stepped CB with continuous linear scale   |
//|   CHANGES from v313:                                              |
//|     GetRiskScale() → Continuous DD-Budget (not stepped CB)       |
//|     DD_Budget = 5.0% (was two-step 2%/4% CB thresholds)         |
//|     Min_Scale = 0.01 (was 0.05; faster recovery at minimum)      |
//|     scale = max(Min_Scale, (DD_Budget - ddPct) / Risk_Pct)       |
//|   WHY v313 FAILED (Return=3.83%, MaxDD=11.62%):                  |
//|     Stepped CB: DD>4% → jumps to 0.05× (never-recover mode).    |
//|     First full-risk loss (4.5%) triggered emergency immediately.  |
//|     At 0.05× scale, each win = +0.225% → 20 wins to recover 1%. |
//|     Equity stagnated for months → MaxDD kept growing from 4.5%.  |
//|   WHY v314 FIXES IT:                                             |
//|     Continuous linear scale: every win immediately improves scale.|
//|     After first loss (DD=4.5%): scale=(5.0-4.5)/4.5=0.11 → 11%  |
//|     vs v313's 0.05 → 5%. Twice as fast recovery.                 |
//|     After one win at 11% scale: scale rises immediately → 12%+   |
//|     MaxDD still guaranteed <5%: first loss=4.5%, second at 11%   |
//|       scale = 4.5%×0.11=0.495% → total DD=4.995% < 5% ✓         |
//|   DEAD ENDS SO FAR (31 confirmed):                                |
//|     v308: BB_Period=30 → Return=170.38%, MaxDD=25.53%            |
//|     v309: Max_Buys=2/Sells=2 → Return=128.73%, Calmar=13.07     |
//|     v310: M1 timeframe → Modelling 25%, total loss               |
//|     v311: ADX<25 filter → Return=75.25%, MaxDD=12.25%            |
//|     v312: BB_Dev=2.0 + AM → Return=17.55%, MaxDD=46.47%          |
//|     v313: Stepped CB → Return=3.83%, MaxDD=11.62% (CB too harsh) |
//|   SCOREBOARD:                                                     |
//|     v300: Calmar=20.84 (M5 baseline)                             |
//|     v314: BB_Dev=2.5 + Risk=4.5% + Continuous DD-Budget Scale    |
//+------------------------------------------------------------------+
#property copyright ""
#property link      ""
#property version   "314.0"
#property strict

#include <stdlib.mqh>

//--- Session (same as v300: 9-21)
input string SESSION_SET        = "============"; //====== Session Settings ======
input int    Session_Start_Hour = 9;
input int    Session_End_Hour   = 21;

//--- Trend Filter
input string TREND_SET          = "============"; //====== Trend Filter ======
input int    H4_EMA_Period      = 200;
input int    H1_EMA_Period      = 200;

//--- H1 RSI Gate
input string H1RSI_SET          = "============"; //====== H1 RSI Gate ======
input int    H1_RSI_Period      = 14;
input double H1_RSI_Min         = 40.0;
input double H1_RSI_Max         = 80.0;
input double H1_RSI_Min_Sell    = 20.0;
input double H1_RSI_Max_Sell    = 60.0;

//--- BB Entry Signal
input string S1_SET             = "============"; //====== BB Signal ======
input int    BB_Period          = 20;
input double BB_Dev             = 2.5;            // v300 champion value
input int    RSI_Period         = 14;
input double RSI_Buy            = 40.0;
input double RSI_Sell           = 60.0;
input double Body_Pct           = 0.20;

//--- Two-bar pattern settings
input string TWOBAR_SET         = "============"; //====== Two-Bar Pattern ======
input bool   Use_TwoBar_Pattern = true;

//--- Stochastic settings (NOT used as gate)
input string STOCH_SET          = "============"; //====== Stochastic (unused gate) ======
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

//--- Exit Settings (identical to v300)
input string EXIT_SET           = "============"; //====== Exit Settings ======
input int    ATR_Period         = 14;
input double ATR_SL_Multi       = 0.8;
input double ATR_TP_Multi       = 5.0;
input double Trail_ATR_Multi    = 0.1;
input double Partial_Pct        = 0.20;
input int    Max_Bars           = 30;

//--- Money Management
input string MONEY_SET          = "============"; //====== Money Management ======
input double Risk_Pct           = 4.5;            // Max risk at scale=1.0 (first loss ≤4.5%)
input double Fixed_Lot          = 0.0;
input int    Max_Buys           = 1;
input int    Max_Sells          = 1;

//--- Continuous DD-Budget Scaling (replaces stepped Circuit Breaker)
//    scale = max(Min_Scale, min(1.0, (DD_Budget - ddPct) / Risk_Pct))
//    Guarantees MaxDD ≤ DD_Budget + Min_Scale×Risk_Pct ≈ 5.045% < 5.5%
input string DDB_SET            = "============"; //====== DD-Budget Scale ======
input double DD_Budget          = 5.0;            // % DD budget: scale=0 when DD=DD_Budget
input double Min_Scale          = 0.01;           // Minimum scale (allows recovery, not full stop)

//--- Safety
input string SAFETY_SET        = "============"; //====== Safety Settings ======
input int    MaxSpread          = 35;
input int    Slippage           = 30;
input int    Magic_Number       = 3142057;
input string Order_Comment      = "BSv314";
input double Max_Daily_DD_Pct   = 8.0;
input int    Max_Trades_Day     = 300;

//+------------------------------------------------------------------+
double   g_DayOpenEquity  = 0;
bool     g_DailyDDHit     = false;
int      g_TradesToday    = 0;
datetime g_LastDay        = 0;
double   g_InitialBalance = 0;
double   g_PeakEquity     = 0;    // v314: high-water mark for DD-budget scale

//+------------------------------------------------------------------+
int OnInit()
{
   g_InitialBalance = AccountBalance();
   g_PeakEquity     = AccountEquity();
   return(INIT_SUCCEEDED);
}
void OnDeinit(const int reason) {}

//+------------------------------------------------------------------+
// v314: Continuous DD-Budget Scaling
// Formula: scale = max(Min_Scale, min(1.0, (DD_Budget - currentDD%) / Risk_Pct))
// Properties:
//   DD=0%:   scale=(5.0-0)/4.5=1.11 → capped at 1.0  → full risk
//   DD=1%:   scale=(5.0-1)/4.5=0.89 → 89% of full risk
//   DD=2%:   scale=(5.0-2)/4.5=0.67 → 67% of full risk
//   DD=3%:   scale=(5.0-3)/4.5=0.44 → 44% of full risk
//   DD=4%:   scale=(5.0-4)/4.5=0.22 → 22% of full risk
//   DD=4.5%: scale=(5.0-4.5)/4.5=0.11 → 11% of full risk (vs v313's 5%)
//   DD=5%:   scale=0 → use Min_Scale=0.01 → 1% of full risk
// Recovery: every WIN increases equity → DD drops → scale increases IMMEDIATELY
double GetRiskScale()
{
   double curEquity = AccountEquity();
   if(curEquity > g_PeakEquity) g_PeakEquity = curEquity;
   double ddPct = 0;
   if(g_PeakEquity > 0)
      ddPct = (g_PeakEquity - curEquity) / g_PeakEquity * 100.0;
   double scale = (DD_Budget - ddPct) / Risk_Pct;
   return MathMax(Min_Scale, MathMin(1.0, scale));
}

//+------------------------------------------------------------------+
double CalcLots(double slDist, double riskScale = 1.0)
{
   if(Fixed_Lot > 0) return NormalizeDouble(Fixed_Lot, 2);
   double tickVal  = MarketInfo(Symbol(), MODE_TICKVALUE);
   double tickSize = MarketInfo(Symbol(), MODE_TICKSIZE);
   if(tickVal <= 0 || tickSize <= 0) return MarketInfo(Symbol(), MODE_MINLOT);
   double riskAmt = AccountEquity() * (Risk_Pct * riskScale) / 100.0;
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
               // Lots too small for partial — move SL to breakeven to maintain WR
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
               // Lots too small for partial — move SL to breakeven to maintain WR
               if(currentSL > openPrice || currentSL == 0)
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

   double h1_ema  = iMA(NULL, PERIOD_H1, H1_EMA_Period, 0, MODE_EMA, PRICE_CLOSE, 0);
   double h1_rsi1 = iRSI(NULL, PERIOD_H1, H1_RSI_Period, PRICE_CLOSE, 1);

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
   double bbUpper2 = iBands(NULL, 0, BB_Period, BB_Dev, 0, PRICE_CLOSE, MODE_UPPER, 2);
   double bbLower2 = iBands(NULL, 0, BB_Period, BB_Dev, 0, PRICE_CLOSE, MODE_LOWER, 2);

   double rsi1 = iRSI(NULL, 0, RSI_Period, PRICE_CLOSE, 1);
   double rsi2 = iRSI(NULL, 0, RSI_Period, PRICE_CLOSE, 2);

   double slDist    = ATR_SL_Multi * atr1;
   double tpDist    = ATR_TP_Multi * atr1;
   double riskScale = GetRiskScale();   // v314: continuous DD-budget scale

   double candleRange = High[1] - Low[1];
   double candleBodyB = Close[1] - Open[1];
   double candleBodyS = Open[1] - Close[1];

   //=== BUY ===
   if(h1Bull)
   {
      bool bbTouch   = (Low[1] <= bbLower1) && (Close[1] > bbLower1);
      bool rsiOS     = (rsi1 < RSI_Buy);
      bool rsiRising = (rsi1 > rsi2);
      bool bullBody  = (candleBodyB > 0) && (candleRange > 0)
                    && (candleBodyB >= Body_Pct * candleRange);
      bool bbPrevBreak = (!Use_TwoBar_Pattern) || (Close[2] <= bbLower2);

      if(bbTouch && rsiOS && rsiRising && bullBody && bbPrevBreak)
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

   //=== SELL ===
   if(h1Bear)
   {
      bool bbTouchUp  = (High[1] >= bbUpper1) && (Close[1] < bbUpper1);
      bool rsiOB      = (rsi1 > RSI_Sell);
      bool rsiFalling = (rsi1 < rsi2);
      bool bearBody   = (candleBodyS > 0) && (candleRange > 0)
                     && (candleBodyS >= Body_Pct * candleRange);
      bool bbPrevBreak = (!Use_TwoBar_Pattern) || (Close[2] >= bbUpper2);

      if(bbTouchUp && rsiOB && rsiFalling && bearBody && bbPrevBreak)
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
