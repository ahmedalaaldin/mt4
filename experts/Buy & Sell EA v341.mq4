//+------------------------------------------------------------------+
//|   Buy & Sell EA v341 - BUY_STOP Pending Orders                   |
//|   BASE: v328 (RSI_Period=14, WR=83.47%, best performer)          |
//|                                                                   |
//|   M1 TIMEFRAME TEST VERDICT (v328 on M1):                        |
//|     WR=31.90% CATASTROPHIC, Return=-4.64% LOSS                   |
//|     MaxDD=7.25% FAILS, ModellingQuality=25% (bad data)           |
//|     M1 definitively RULED OUT for this strategy                  |
//|                                                                   |
//|   SCOREBOARD (all M5 unless noted):                               |
//|     v328: +16.25%, MaxDD=4.99%, WR=83.47%, 380t   BEST M5 ✓    |
//|     v336: RSI_Period=7 → +11.62%, WR=82.38%, 505t               |
//|     v337: RSI_Period=7+Buy=42 → WR=81.15%, 435t   FAIL ✗       |
//|     v338: Dual RSI(14)<55 → identical to v336      SKIP ~        |
//|     v339: rsiTrough → WR=82.48%, MaxDD=5.04%❌    FAIL ✗       |
//|     v340: RSI_Period=11 → WR=81.84%, 479t          FAIL ✗       |
//|     v328 on M1 → WR=31.90% LOSS                   FAIL ✗       |
//|                                                                   |
//|   v341 HYPOTHESIS: BUY_STOP Pending Orders                       |
//|   Instead of market entry on bar[0], place OP_BUYSTOP at:        |
//|     stopPrice = MathMax(High[1], Ask) + Stop_Offset * ATR        |
//|   Requires bar[0] to BREAK ABOVE bar[1]'s high before filling.  |
//|   Logic: All winning trades must break High[1] to reach BB_mid.  |
//|   False recoveries (never break High[1]) → order expires = SKIP. |
//|   Expected: WR ↑ to ~88-90%, Trades ↓ to ~320-350/year          |
//|   If WR improvement offsets trade count drop: better return.     |
//|                                                                   |
//|   v341 CHANGES from v328:                                        |
//|     RSI_Period: 14 (RESTORED to v328 best)                       |
//|     Entry type: OP_BUY market → OP_BUYSTOP pending               |
//|     Stop price: MathMax(High[1], Ask) + Stop_Offset * ATR        |
//|     Stop expiry: Stop_Expiry_Bars bars                            |
//|     SL/TP: calculated from stop price (not Ask)                  |
//|                                                                   |
//|   NON-NEGOTIABLES (ALL unchanged from v328):                     |
//|     BB_Dev=2.5, BB_Period=20, TwoBar_Lookback=1                  |
//|     Session=9-21, Max_Sells=0, ATR_SL_Multi=0.80                |
//|     Partial_Pct=0.20, Trail_ATR_Multi=0.5, Hard_DD_Stop=0.0     |
//|     RSI_Buy=45.0, RSI_Period=14                                   |
//+------------------------------------------------------------------+
#property copyright ""
#property link      ""
#property version   "341.0"
#property strict

#include <stdlib.mqh>

//--- Session (LOCKED at 9-21)
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
input double H1_RSI_Min         = 0.0;
input double H1_RSI_Max         = 90.0;
input double H1_RSI_Min_Sell    = 20.0;
input double H1_RSI_Max_Sell    = 60.0;

//--- BB Entry Signal
input string S1_SET             = "============"; //====== BB Signal ======
input int    BB_Period          = 20;
input double BB_Dev             = 2.5;            // NON-NEGOTIABLE (LOCKED)
input int    RSI_Period         = 14;             // v341: RESTORED to v328 best (14)
input double RSI_Buy            = 45.0;           // NON-NEGOTIABLE
input double RSI_Sell           = 60.0;
input double Body_Pct           = 0.20;

//--- Two-bar pattern
input string TWOBAR_SET         = "============"; //====== Two-Bar Pattern ======
input bool   Use_TwoBar_Pattern = true;

//--- Volatility Filter
input string VOL_SET            = "============"; //====== Volatility Filter ======
input double Max_ATR_Pct        = 0.0;
input int    ATR_Spike_MA_Period = 50;
input double ATR_Spike_Multi    = 0.0;

//--- Exit Settings
input string EXIT_SET           = "============"; //====== Exit Settings ======
input int    ATR_Period         = 14;
input double ATR_SL_Multi       = 0.8;            // NON-NEGOTIABLE
input double ATR_TP_Multi       = 5.0;
input double Trail_ATR_Multi    = 0.5;            // NON-NEGOTIABLE
input double Partial_Pct        = 0.20;           // NON-NEGOTIABLE
input int    Max_Bars           = 30;

//--- v341 NEW: BUY_STOP Pending Order Settings
input string STOP_SET           = "============"; //====== Stop Order Settings ======
input double Stop_Offset        = 0.05;           // v341: ATR multiplier above High[1] for stop entry
input int    Stop_Expiry_Bars   = 3;              // v341: bars before pending order expires (15 min on M5)

//--- Money Management
input string MONEY_SET          = "============"; //====== Money Management ======
input double Risk_Pct           = 0.85;
input double Fixed_Lot          = 0.0;
input int    Max_Buys           = 1;
input int    Max_Sells          = 0;              // NON-NEGOTIABLE (DISABLED)

//--- DD-Budget Scaling
input string DDB_SET            = "============"; //====== DD-Budget Scale ======
input double DD_Budget          = 3.8;
input double Min_Scale          = 0.01;

//--- Safety
input string SAFETY_SET        = "============"; //====== Safety Settings ======
input int    MaxSpread          = 35;
input int    Slippage           = 30;
input int    Magic_Number       = 3412057;        // v341 unique magic
input string Order_Comment      = "BSv341";
input double Max_Daily_DD_Pct   = 8.0;
input int    Max_Trades_Day     = 300;
input double Hard_DD_Stop       = 0.0;            // NON-NEGOTIABLE (DISABLED)

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
   double capAmt  = g_PeakBalance * (Risk_Pct * riskScale) / 100.0;
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
// v341: Count pending stop orders
int CountPendingBuyStops(int magic)
{
   int n = 0;
   for(int i = 0; i < OrdersTotal(); i++)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() == Symbol() && OrderMagicNumber() == magic && OrderType() == OP_BUYSTOP) n++;
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
      else if(OrderType() == OP_BUYSTOP || OrderType() == OP_SELLSTOP ||
              OrderType() == OP_BUYLIMIT || OrderType() == OP_SELLLIMIT)
         OrderDelete(OrderTicket());
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

      // Only manage FILLED orders (OP_BUY/OP_SELL), not pending
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

   if(Hard_DD_Stop > 0.0 && g_PeakBalance > 0)
   {
      double globalDD = (g_PeakBalance - curBalance) / g_PeakBalance * 100.0;
      if(globalDD >= Hard_DD_Stop) return;
   }

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
   double riskScale = GetRiskScale();

   double candleRange = High[1] - Low[1];
   double candleBodyB = Close[1] - Open[1];
   double candleBodyS = Open[1] - Close[1];

   //=== BUY (v341: OP_BUYSTOP pending order) ===
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
         int activeBuys  = CountTradesByMagic(OP_BUY, Magic_Number);
         int pendingBuys = CountPendingBuyStops(Magic_Number);

         if(activeBuys + pendingBuys < Max_Buys)
         {
            // v341: Place BUY_STOP just above bar[1]'s high
            // This requires bar[0] to break above the recovery bar before entry
            // MathMax(High[1], Ask) ensures stop is always above current price
            double stopPrice = NormalizeDouble(MathMax(High[1], Ask) + Stop_Offset * atr1, Digits);
            double sl        = NormalizeDouble(stopPrice - slDist, Digits);
            double tp        = NormalizeDouble(stopPrice + tpDist, Digits);
            double lots      = CalcLots(slDist, riskScale);
            datetime expiry  = TimeCurrent() + Stop_Expiry_Bars * PeriodSeconds();

            if(lots > 0)
            {
               int tkt = OrderSend(Symbol(), OP_BUYSTOP, lots, stopPrice, Slippage,
                                   sl, tp, Order_Comment, Magic_Number, expiry, clrGreen);
               if(tkt > 0) g_TradesToday++;
            }
         }
      }
   }

   //=== SELL (DISABLED - Max_Sells=0) ===
   if(Max_Sells > 0 && h1Bear)
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
