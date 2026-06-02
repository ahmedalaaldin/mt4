//+------------------------------------------------------------------+
//|  Buy & Sell EA - MeanRev v700 (recreated from spec)              |
//|  M30 Bollinger mean-reversion. RSI35 / SL4 / BBdev0.5.          |
//|  Recreated 2026-06-02 from documented spec:                     |
//|  2023: +4.1%, DD 2.4%, WR 81.6%, PF 1.78, 103 trades.          |
//+------------------------------------------------------------------+
#property strict
#include <stdlib.mqh>

input string MR_SET         = "==== MeanRev (BB+RSI) ====";
input int    BB_Period      = 20;
input double BB_Dev         = 0.5;         // BBdev0.5: tight bands -> frequent touches
input int    RSI_Period     = 14;
input double RSI_Buy        = 35.0;        // RSI35: buy when RSI < 35
input double RSI_Sell       = 65.0;        // sell when RSI > 65
input int    ATR_Period     = 14;
input double SL_ATR_Multi   = 4.0;         // SL4
input double TP_ATR_Multi   = 0.5;         // TP0.5 (quick reversion target)
input ENUM_TIMEFRAMES MRTF  = PERIOD_M30;

input string MM_SET         = "==== Money Management ====";
input double Risk_Pct       = 1.0;
input double Fixed_Lot      = 0.0;
input int    Max_Positions  = 1;

input string SAFE_SET       = "==== Safety ====";
input int    MaxSpread      = 50;
input int    Slippage       = 30;
input int    Magic_Number   = 7002057;
input string Order_Comment  = "MRv700";

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

void OnTick(){
   datetime bt=iTime(NULL,MRTF,0);
   if(bt==g_lastBar) return;
   g_lastBar=bt;

   double atr=iATR(NULL,MRTF,ATR_Period,1);
   if(atr<=0) return;
   if((Ask-Bid)/Point>MaxSpread) return;

   double bbLow =iBands(NULL,MRTF,BB_Period,BB_Dev,0,PRICE_CLOSE,MODE_LOWER,1);
   double bbUp  =iBands(NULL,MRTF,BB_Period,BB_Dev,0,PRICE_CLOSE,MODE_UPPER,1);
   double rsi   =iRSI (NULL,MRTF,RSI_Period,PRICE_CLOSE,1);
   double lo1=iLow(NULL,MRTF,1), hi1=iHigh(NULL,MRTF,1), c1=iClose(NULL,MRTF,1);

   double slDist=SL_ATR_Multi*atr, tpDist=TP_ATR_Multi*atr;

   // Mean-reversion LONG: touched lower band, closed back above, RSI oversold
   if((lo1<=bbLow) && (c1>bbLow) && (rsi<RSI_Buy) && CountByMagic(OP_BUY)<Max_Positions){
      double e=NormalizeDouble(Ask,Digits);
      double l=CalcLots(slDist);
      if(l>0) OrderSend(Symbol(),OP_BUY,l,e,Slippage,NormalizeDouble(e-slDist,Digits),NormalizeDouble(e+tpDist,Digits),Order_Comment,Magic_Number,0,clrBlue);
   }
   // Mean-reversion SHORT: touched upper band, closed back below, RSI overbought
   else if((hi1>=bbUp) && (c1<bbUp) && (rsi>RSI_Sell) && CountByMagic(OP_SELL)<Max_Positions){
      double e=NormalizeDouble(Bid,Digits);
      double l=CalcLots(slDist);
      if(l>0) OrderSend(Symbol(),OP_SELL,l,e,Slippage,NormalizeDouble(e+slDist,Digits),NormalizeDouble(e-tpDist,Digits),Order_Comment,Magic_Number,0,clrRed);
   }
}
//+------------------------------------------------------------------+
