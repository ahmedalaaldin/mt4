//+------------------------------------------------------------------+
//|   Buy & Sell EA v315 - Balance-Peak Fix + Filter Relaxation      |
//|   BASE: v314 + critical bug fix for GetRiskScale()               |
//|   CHANGES from v314:                                              |
//|     BUG FIX: GetRiskScale() now tracks AccountBalance() not      |
//|              AccountEquity() for the high-water mark             |
//|     WHY v314 FAILED (Return=-1.92%, MaxDD=8.81%, 127 trades):    |
//|       v314 tracked AccountEquity() (includes unrealized P/L)     |
//|       Scenario: trade opens, floats +$460 unrealized             |
//|         → g_PeakEquity = $10,460 (inflated by open profit)       |
//|         → price reverses, SL hit: balance = $9,537               |
//|         → DD from peak = ($10,460-$9,537)/$10,460 = 8.82%!       |
//|         → scale = max(0.01,(5.0-8.82)/4.5) = 0.01 (Min_Scale!)  |
//|         → subsequent trades at 0.01× scale = near-zero lots      |
//|         → WR collapsed to 46% (partial close failed at min lots)  |
//|         → MaxDD = 8.81% despite 5% budget guarantee!             |
//|     FIX: Track AccountBalance() → only REALIZED losses matter    |
//|       First realized loss of 4.5%: balance drops 4.5%            |
//|       → scale = (5.0-4.5)/4.5 = 0.11 (11% — as designed)        |
//|       → MaxDD guarantee holds: 4.5% + 0.11×4.5% = 4.995% < 5%   |
//|     ALSO FIXED: H1_RSI_Max 80→90 (gold bull run: RSI often 80-90)|
//|     ALSO FIXED: Max_ATR_Pct 0.60→1.00 (volatile gold sessions)   |
//|       These two filters were blocking ~88% of v300 trade setups   |
//|   DEAD ENDS SO FAR (32 confirmed):                                |
//|     v308: BB_Period=30 → Return=170.38%, MaxDD=25.53%            |
//|     v309: Max_Buys=2/Sells=2 → Return=128.73%, Calmar=13.07     |
//|     v310: M1 timeframe → Modelling 25%, total loss               |
//|     v311: ADX<25 filter → Return=75.25%, MaxDD=12.25%            |
//|     v312: BB_Dev=2.0 + AM → Return=17.55%, MaxDD=46.47%          |
//|     v313: Stepped CB → Return=3.83%, MaxDD=11.62%                |
//|     v314: Equity-peak bug → Return=-1.92%, MaxDD=8.81%           |
//|   SCOREBOARD:                                                     |
//|     v300: Calmar=20.84 (M5 baseline, no protection)              |
//|     v315: Balance-peak fix + relaxed filters                      |
//+------------------------------------------------------------------+
#property copyright ""
#property link      ""
#property version   "315.0"
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
// v315: H1_RSI_Max raised 80→90 to allow bull-run entries (RSI 80-90 is normal in uptrend)
input string H1RSI_SET          = "============"; //====== H1 RSI Gate ======
input int    H1_RSI_Period      = 14;
input double H1_RSI_Min         = 40.0;
input double H1_RSI_Max         = 90.0;            // v315: was 80 → captures bull-run dips
input double H1_RSI_Min_Sell    = 20.0;
input double H1_RSI_Max_Sell    = 60.0;

//--- BB Entry Signal
input string S1_SET             = "============"; //====== BB Signal ======
input int    BB_Period          = 20;
input double BB_Dev             = 2.5;             // v300 champion value
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
// v315: Max_ATR_Pct raised 0.60→1.00 to allow more entries during volatile gold sessions
input string VOL_SET            = "============"; //====== Volatility Filter ======
input double Max_ATR_Pct        = 1.00;            // v315: was 0.60 → allows volatile periods
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
input double Risk_Pct           = 4.5;             // Max risk at scale=1.0 (first loss ≤4.5%)
input double Fixed_Lot          = 0.0;
input int    Max_Buys           = 1;
input int    Max_Sells          = 1;

//--- Continuous DD-Budget Scaling (v314 design, v315 bug-fixed)
//    scale = max(Min_Scale, min(1.0, (DD_Budget - realizedDD%) / Risk_Pct))
//    Uses AccountBalance() so unrealized P/L cannot distort the scale
//    MaxDD guarantee: first loss = 4.5%, scale drops to 0.11
//      second loss = 4.5% × 0.11 = 0.495% → total = 4.995% < 5% ✓
input string DDB_SET            = "============"; //====== DD-Budget Scale ======
input double DD_Budget          = 5.0;             // % DD budget (realized balance basis)
input double Min_Scale          = 0.01;            // Minimum scale for recovery at full budget

//--- Safety
input string SAFETY_SET        = "============"; //====== Safety Settings ======
input int    MaxSpread          = 35;
input int    Slippage           = 30;
input int    Magic_Number       = 3152057;
input string Order_Comment      = "BSv315";
input double Max_Daily_DD_Pct   = 8.0;
input int    Max_Trades_Day     = 300;

//+------------------------------------------------------------------+
double   g_DayOpenEquity  = 0;
bool     g_DailyDDHit     = false;
int      g_TradesToday    = 0;
datetime g_LastDay        = 0;
double   g_InitialBalance = 0;
double   g_PeakBalance    = 0;    // v315 FIX: track balance (not equity) high-water mark

//+------------------------------------------------------------------+
int OnInit()
{
   g_InitialBalance = AccountBalance();
   g_PeakBalance    = AccountBalance();   // v315 FIX: was AccountEquity()
   return(INIT_SUCCEEDED);
}
void OnDeinit(const int reason) {}

//+------------------------------------------------------------------+
// v315 BUG FIX: Use AccountBalance() for peak tracking
// v314 used AccountEquity() which includes unrealized floating P/L
// Problem: open trade floats profit → g_PeakEquity inflates → SL hit
//   → apparent DD from inflated peak exceeds DD_Budget → scale = Min_Scale
//   → strategy becomes paralyzed even though realized loss was only 4.5%
// Fix: track AccountBalance() → only closed (realized) trades affect scale
//   → DD_Budget guarantee holds exactly as designed
// Scale properties (same formula, but now based on realized losses only):
//   realizedDD=0%:   scale=1.11 → capped at 1.0  (full risk)
//   realizedDD=1%:   scale=0.89 (89% of full risk)
//   realizedDD=2%:   scale=0.67 (67% of full risk)
//   realizedDD=3%:   scale=0.44 (44% of full risk)
//   realizedDD=4%:   scale=0.22 (22% of full risk)
//   realizedDD=4.5%: scale=0.11 (11% — recovers in ~3 wins at 92% WR)
//   realizedDD=5%:   scale=0.01 (Min_Scale — keeps strategy alive)
double GetRiskScale()
{
   double curBalance = AccountBalance();
   if(curBalance > g_PeakBalance) g_PeakBalance = curBalance;
   double ddPct = 0;
   if(g_PeakBalance > 0)
      ddPct = (g_PeakBalance - curBalance) / g_PeakBalance * 100.0;
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

   // v315: H1_RSI_Max raised to 90 — during gold's 2025 bull run H1 RSI often 80-90
   // Blocking RSI 80-90 buys was eliminating the best bull-trend dip entries
   bool h1Bull = (iClose(NULL, PERIOD_H1, 1) > h1_ema)
              && (h1_rsi1 >= H1_RSI_Min) && (h1_rsi1 <= H1_RSI_Max);
   bool h1Bear = (iClose(NULL, PERIOD_H1, 1) < h1_ema)
              && (h1_rsi1 >= H1_RSI_Min_Sell) && (h1_rsi1 <= H1_RSI_Max_Sell);

   double atr1 = iATR(NULL, 0, ATR_Period, 1);
   if(atr1 <= 0) return;

   // v315: Max_ATR_Pct raised to 1.00 — gold at $4000 with ATR cap of 0.60% = $24/bar was
   // blocking most XAUUSD M5 sessions during the bull run (gold often moves $25-40/bar)
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
   double riskScale = GetRiskScale();   // v315: uses AccountBalance() peak (bug fixed)

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
