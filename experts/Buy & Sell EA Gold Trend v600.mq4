//+------------------------------------------------------------------+
//|  Buy & Sell EA - Gold Trend v600 (recreated from spec)           |
//|  H1 Donchian breakout trend-follower. D10 / SL3 / Trail5.        |
//|  Recreated 2026-06-02 from documented backtest spec:            |
//|  2019-2026: +392% realized, PF 1.41, MaxDD 42.3%, WR 35.8%.     |
//+------------------------------------------------------------------+
#property strict
#include <stdlib.mqh>

input string TREND_SET      = "==== Gold Trend (Donchian) ====";
input int    Donchian_Period = 10;        // D10: breakout of N-bar high/low (on H1)
input int    ATR_Period      = 14;
input double SL_ATR_Multi    = 3.0;        // SL3: initial stop = 3 x ATR
input double Trail_ATR_Multi = 5.0;        // Trail5: trailing stop = 5 x ATR
input ENUM_TIMEFRAMES TrendTF = PERIOD_H1;

input string MM_SET         = "==== Money Management ====";
input double Risk_Pct       = 1.0;         // % equity risked per trade
input double Fixed_Lot      = 0.0;         // >0 overrides Risk_Pct
input int    Max_Positions  = 1;           // concurrent trend positions

input string SAFE_SET       = "==== Safety ====";
input int    MaxSpread      = 50;
input int    Slippage       = 30;
input int    Magic_Number   = 6002057;
input string Order_Comment  = "GTv600";

datetime g_lastBar = 0;

int OnInit(){ return(INIT_SUCCEEDED); }
void OnDeinit(const int r){}

int CountByMagic(int type){
   int n=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
      if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES))
         if(OrderSymbol()==Symbol() && OrderMagicNumber()==Magic_Number && OrderType()==type) n++;
   return n;
}

double CalcLots(double slDistPrice){
   if(Fixed_Lot>0) return NormalizeDouble(Fixed_Lot,2);
   double tv=MarketInfo(Symbol(),MODE_TICKVALUE), ts=MarketInfo(Symbol(),MODE_TICKSIZE);
   if(tv<=0||ts<=0||slDistPrice<=0) return MarketInfo(Symbol(),MODE_MINLOT);
   double riskAmt=AccountEquity()*Risk_Pct/100.0;
   double slTicks=slDistPrice/ts;
   double lots=riskAmt/(slTicks*tv);
   double minL=MarketInfo(Symbol(),MODE_MINLOT), maxL=MarketInfo(Symbol(),MODE_MAXLOT), step=MarketInfo(Symbol(),MODE_LOTSTEP);
   lots=MathFloor(lots/step)*step;
   if(lots<minL) lots=minL;
   if(lots>maxL) lots=maxL;
   return NormalizeDouble(lots,2);
}

void ManageTrailing(){
   double atr=iATR(NULL,TrendTF,ATR_Period,1);
   if(atr<=0) return;
   double trail=Trail_ATR_Multi*atr;
   for(int i=OrdersTotal()-1;i>=0;i--){
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderSymbol()!=Symbol()||OrderMagicNumber()!=Magic_Number) continue;
      if(OrderType()==OP_BUY){
         double newSL=NormalizeDouble(Bid-trail,Digits);
         if(newSL>OrderStopLoss()+Point && newSL<Bid) OrderModify(OrderTicket(),OrderOpenPrice(),newSL,0,0,clrLime);
      } else if(OrderType()==OP_SELL){
         double newSL=NormalizeDouble(Ask+trail,Digits);
         if((OrderStopLoss()==0||newSL<OrderStopLoss()-Point) && newSL>Ask) OrderModify(OrderTicket(),OrderOpenPrice(),newSL,0,0,clrOrange);
      }
   }
}

void OnTick(){
   ManageTrailing();
   datetime bt=iTime(NULL,TrendTF,0);
   if(bt==g_lastBar) return;   // act once per new H1 bar
   g_lastBar=bt;

   double atr=iATR(NULL,TrendTF,ATR_Period,1);
   if(atr<=0) return;
   if((Ask-Bid)/Point>MaxSpread) return;

   // Donchian channel over the previous N bars (shift 1..N), excluding the just-formed bar's break ref
   double donHigh=iHigh(NULL,TrendTF,iHighest(NULL,TrendTF,MODE_HIGH,Donchian_Period,2));
   double donLow =iLow (NULL,TrendTF,iLowest (NULL,TrendTF,MODE_LOW ,Donchian_Period,2));
   double c1=iClose(NULL,TrendTF,1);

   double slDist=SL_ATR_Multi*atr;

   // Breakout LONG
   if(c1>donHigh && CountByMagic(OP_BUY)<Max_Positions && CountByMagic(OP_SELL)==0){
      double e=NormalizeDouble(Ask,Digits);
      double l=CalcLots(slDist);
      if(l>0) OrderSend(Symbol(),OP_BUY,l,e,Slippage,NormalizeDouble(e-slDist,Digits),0,Order_Comment,Magic_Number,0,clrBlue);
   }
   // Breakout SHORT
   else if(c1<donLow && CountByMagic(OP_SELL)<Max_Positions && CountByMagic(OP_BUY)==0){
      double e=NormalizeDouble(Bid,Digits);
      double l=CalcLots(slDist);
      if(l>0) OrderSend(Symbol(),OP_SELL,l,e,Slippage,NormalizeDouble(e+slDist,Digits),0,Order_Comment,Magic_Number,0,clrRed);
   }
}
//+------------------------------------------------------------------+
