//+------------------------------------------------------------------+
//|   Buy & Sell EA v317 - Targeted H1 RSI Fix + DD Control          |
//|   BASE: v315 (balance-peak scaling) with MINIMAL targeted fixes  |
//|                                                                    |
//|   v316 POST-MORTEM (169 trades, -5.70% return, 9.38% MaxDD):     |
//|     MISTAKE 1: H1_EMA_Period 200→50                               |
//|       EMA50 oscillates in bull run → h1Bull=false during corrections|
//|       Corrections = BEST BUY TIMES → we missed them!             |
//|       Also enabled more shorts (65 vs 35) in bull market → -WR   |
//|     MISTAKE 2: Removed two-bar pattern                            |
//|       Confirmed critical quality filter: WR dropped 64.8→60.4%  |
//|     MISTAKE 3: Removed rsiOS condition                            |
//|       Without M5 RSI oversold check, buying weak signals too     |
//|     RESULT: Both changes together produced profit factor 0.52    |
//|                                                                    |
//|   TRUE ROOT CAUSE OF v315's LOW TRADE COUNT (196/year):          |
//|     The condition h1Bull requires BOTH:                           |
//|       (A) H1 close > H1 EMA200 (trend direction)                 |
//|       (B) H1 RSI >= H1_RSI_Min=40 (H1 RSI not oversold)         |
//|     AND the buy entry requires:                                   |
//|       (C) M5 RSI < RSI_Buy=40 (M5 RSI oversold)                  |
//|     Conditions B and C are CONTRADICTORY:                        |
//|       When M5 RSI drops below 40 (C is true), H1 RSI also        |
//|       typically falls (gold moves down on H1 too) → H1 RSI       |
//|       drops below 40 → condition B becomes FALSE → trade BLOCKED |
//|     Result: The EA was blocking its BEST entries — deep dip buys  |
//|     during H1 pullbacks where both H1 RSI and M5 RSI were low.   |
//|                                                                    |
//|   v317 CHANGES (4 changes from v315, everything else unchanged): |
//|     FIX 1: H1_RSI_Min 40→0 — removes the contradictory RSI gate |
//|             h1Bull now = (H1 close > EMA200) AND (H1 RSI <= 90)  |
//|             = just trend direction + mild overbought protection   |
//|     FIX 2: ATR_Spike_Multi 1.8→0 — disables volatile-bar filter  |
//|             Gold bull runs have spike bars that are VALID entries |
//|     FIX 3: Risk_Pct 4.5→2.0 — each SL was 4.5% DD = 90% budget |
//|             Now one SL = 2.0% DD, budget lasts 2+ consecutive losses|
//|     FIX 4: Min_Scale 0.01→0.15 — prevents partial-close failure  |
//|             At 0.01 scale: lots≈0.01→partial=0.002→rounds to 0   |
//|             At 0.15 scale: lots≈0.1+→partial works correctly      |
//|                                                                    |
//|   KEPT FROM v315 (all quality filters preserved):                |
//|     BB_Dev=2.5, H1_EMA_Period=200, Two-bar pattern=true           |
//|     RSI_Buy=40 (M5 oversold check), Body_Pct=0.20, ATR exits     |
//|     Balance-based peak tracking (AccountBalance), Max_Buys=1      |
//|                                                                    |
//|   EXPECTED: ~300-500 trades/year (2x v315), WR maintained ~70%+  |
//|             MaxDD<5% (Risk_Pct=2.0%, Min_Scale=0.15)             |
//|   SCOREBOARD:                                                     |
//|     v300: Calmar=20.84 (1040 trades, 258% return, 12.4% MaxDD)  |
//|     v315: +1.95%, 9.13% MaxDD, 196 trades (H1 RSI contradiction) |
//|     v316: -5.70%, 9.38% MaxDD, 169 trades (EMA50+no-2bar mistake)|
//|     v317: This version — targeted 4-change fix                    |
//+------------------------------------------------------------------+
#property copyright ""
#property link      ""
#property version   "317.0"
#property strict

#include <stdlib.mqh>

//--- Session (same as v315: 9-21)
input string SESSION_SET        = "============"; //====== Session Settings ======
input int    Session_Start_Hour = 9;
input int    Session_End_Hour   = 21;

//--- Trend Filter
// v317: H1_EMA_Period kept at 200 (v316 used 50 which was a mistake)
// With EMA200, in a bull run h1Bull is almost always true → buys fire freely
// With EMA50, h1Bull=false during corrections = blocking best buy times
input string TREND_SET          = "============"; //====== Trend Filter ======
input int    H4_EMA_Period      = 200;
input int    H1_EMA_Period      = 200;            // v317: kept at 200 (v316's 50 was wrong)

//--- H1 RSI Gate
// FIX 1 (v317): H1_RSI_Min changed 40→0
// WHY: When M5 RSI < 40 (buy signal), H1 RSI also tends to be low (gold pulling back)
// v315 required H1 RSI > 40 WHILE ALSO requiring M5 RSI < 40 → contradictory!
// At H1_RSI_Min=0: h1Bull only checks trend direction and H1_RSI_Max
// H1_RSI_Max=90 kept: mild overbought protection (H1 RSI>90 = too extended, skip)
input string H1RSI_SET          = "============"; //====== H1 RSI Gate ======
input int    H1_RSI_Period      = 14;
input double H1_RSI_Min         = 0.0;            // v317 FIX: was 40.0 → was blocking dip buys
input double H1_RSI_Max         = 90.0;           // kept from v315
input double H1_RSI_Min_Sell    = 20.0;
input double H1_RSI_Max_Sell    = 60.0;

//--- BB Entry Signal (all unchanged from v315)
input string S1_SET             = "============"; //====== BB Signal ======
input int    BB_Period          = 20;
input double BB_Dev             = 2.5;            // v315 champion value — kept
input int    RSI_Period         = 14;
input double RSI_Buy            = 40.0;           // M5 RSI oversold check — kept (quality filter)
input double RSI_Sell           = 60.0;
input double Body_Pct           = 0.20;           // v315 bullish body requirement — kept

//--- Two-bar pattern: KEPT TRUE (v316 proved this is critical quality filter)
input string TWOBAR_SET         = "============"; //====== Two-Bar Pattern ======
input bool   Use_TwoBar_Pattern = true;           // v317: kept true (v316 removal hurt WR badly)

//--- Volatility Filter
// FIX 2 (v317): ATR_Spike_Multi 1.8→0 (disabled)
// v315 still had this active — was blocking volatile gold sessions
// In XAUUSD bull run, spike bars are often valid reversal points
input string VOL_SET            = "============"; //====== Volatility Filter ======
input double Max_ATR_Pct        = 1.00;           // kept from v315
input int    ATR_Spike_MA_Period = 50;
input double ATR_Spike_Multi    = 0.0;            // v317 FIX: was 1.8 → DISABLED

//--- Exit Settings (identical to v315)
input string EXIT_SET           = "============"; //====== Exit Settings ======
input int    ATR_Period         = 14;
input double ATR_SL_Multi       = 0.8;
input double ATR_TP_Multi       = 5.0;
input double Trail_ATR_Multi    = 0.1;
input double Partial_Pct        = 0.20;
input int    Max_Bars           = 30;

//--- Money Management
// FIX 3 (v317): Risk_Pct 4.5→2.0 (DD control)
// At Risk_Pct=4.5: one SL = 4.5% DD ≈ 90% of 5% budget → scale crashes to Min_Scale
// At Risk_Pct=2.0: one SL = 2.0% DD → scale = (5-2)/2 = 1.5 → capped to 1.0 (full risk!)
//   second SL: balance down 4% → scale = (5-4)/2 = 0.5 (50% risk)
//   third SL at 50% scale: 2%×0.5 = 1% → total balance down 5% → scale = Min_Scale=0.15
//   Three consecutive losses needed to hit minimum scale (vs one in v314/v315)
input string MONEY_SET          = "============"; //====== Money Management ======
input double Risk_Pct           = 2.0;            // v317 FIX: was 4.5 → less per-trade DD
input double Fixed_Lot          = 0.0;
input int    Max_Buys           = 1;
input int    Max_Sells          = 1;

//--- Continuous DD-Budget Scaling (v315 formula, same principle)
// FIX 4 (v317): Min_Scale 0.01→0.15
// At Min_Scale=0.01: partial close math fails (0.01 lots × 20% = 0.002 → rounds to 0)
//   → WR collapsed in v314/v315 because partial close wasn't executing
// At Min_Scale=0.15: lots = 0.15× full → partial = 0.03+ → always executable
input string DDB_SET            = "============"; //====== DD-Budget Scale ======
input double DD_Budget          = 5.0;
input double Min_Scale          = 0.15;           // v317 FIX: was 0.01 → partial close now works

//--- Safety
input string SAFETY_SET        = "============"; //====== Safety Settings ======
input int    MaxSpread          = 35;
input int    Slippage           = 30;
input int    Magic_Number       = 3172057;
input string Order_Comment      = "BSv317";
input double Max_Daily_DD_Pct   = 8.0;
input int    Max_Trades_Day     = 300;

//+------------------------------------------------------------------+
double   g_DayOpenEquity  = 0;
bool     g_DailyDDHit     = false;
int      g_TradesToday    = 0;
datetime g_LastDay        = 0;
double   g_InitialBalance = 0;
double   g_PeakBalance    = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   g_InitialBalance = AccountBalance();
   g_PeakBalance    = AccountBalance();
   return(INIT_SUCCEEDED);
}
void OnDeinit(const int reason) {}

//+------------------------------------------------------------------+
// DD-Budget scaling using AccountBalance() (v315 fix, preserved in v317)
// With Risk_Pct=2.0 and Min_Scale=0.15 (v317 fixes 3+4):
//   dd=0%:   scale=2.5→cap 1.0  (full risk)
//   dd=1%:   scale=2.0→cap 1.0  (full risk)
//   dd=2%:   scale=1.5→cap 1.0  (full risk — first loss doesn't reduce scale!)
//   dd=3%:   scale=1.0           (full risk — second loss barely reduces scale)
//   dd=4%:   scale=0.5           (50% risk)
//   dd=4.5%: scale=0.25          (25% risk)
//   dd=5%:   scale=0.0→Min 0.15 (15% risk — recovers in ~4 wins at 70% WR)
// Compare to v315 (Risk_Pct=4.5, Min_Scale=0.01):
//   dd=4.5%: scale=0.11→above 0.01 OK
//   dd=5%:   scale=0.0→0.01 (1% risk — needed 40+ wins to recover at 92% WR)
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

   // v317 FIX 1: H1_RSI_Min changed 40→0
   // h1Bull now fires whenever H1 close > EMA200 AND H1 RSI < 90
   // In XAUUSD bull run: H1 close > EMA200 almost always → buys fire freely
   // H1 RSI > 90 is rare (extreme overbought) → mild protection kept
   // KEY: No longer blocks when H1 RSI < 40 (was blocking dip buys!)
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
   // v317 FIX 2: ATR_Spike_Multi set to 0.0 — disabled
   // v315 had this at 1.8, blocking volatile gold sessions
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
   double riskScale = GetRiskScale();

   double candleRange = High[1] - Low[1];
   double candleBodyB = Close[1] - Open[1];
   double candleBodyS = Open[1] - Close[1];

   //=== BUY ===
   // v317: Same quality conditions as v315 (all kept)
   // h1Bull now fires more often due to H1_RSI_Min=0 fix
   if(h1Bull)
   {
      bool bbTouch     = (Low[1] <= bbLower1) && (Close[1] > bbLower1);
      bool rsiOS       = (rsi1 < RSI_Buy);
      bool rsiRising   = (rsi1 > rsi2);
      bool bullBody    = (candleBodyB > 0) && (candleRange > 0)
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
      bool bbTouchUp   = (High[1] >= bbUpper1) && (Close[1] < bbUpper1);
      bool rsiOB       = (rsi1 > RSI_Sell);
      bool rsiFalling  = (rsi1 < rsi2);
      bool bearBody    = (candleBodyS > 0) && (candleRange > 0)
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
