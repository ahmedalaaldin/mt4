//+------------------------------------------------------------------+
//|  Buy & Sell EA v810 - HYBRID + PORTFOLIO DD GOVERNOR             |
//|  (v800 + equity-drawdown position scaling to hold DD near target) |
//|  Merges two uncorrelated engines in one EA, each with its own    |
//|  Magic number and risk budget, so their drawdowns don't stack:   |
//|    - TREND  : H1 Donchian breakout, SL3/Trail5  (the return engine)|
//|    - MEANREV: M30 BB(0.5)+RSI35, SL4/TP0.5      (the smoother)     |
//|  Optional ADX(H1) regime weighting: strong trend -> trend only;   |
//|  chop -> mean-rev only (proven in v513 that MR dies in strong     |
//|  trends and trend lives there).                                   |
//+------------------------------------------------------------------+
#property strict
#include <stdlib.mqh>

input string GEN_SET        = "==== General ====";
input int    ATR_Period     = 14;
input int    MaxSpread      = 50;
input int    Slippage       = 30;
input bool   Use_ADX_Regime = true;        // route by trend strength (ADX on H1)
input int    ADX_Period     = 14;
input double ADX_Split      = 25.0;        // ADX>=split -> trend regime; else mean-rev regime
input bool   Use_DD_Governor = true;       // v810: scale position size down as equity DD grows
input double DD_Budget       = 5.5;        // throttle toward 0 size as equity DD approaches this %
input double Min_Scale       = 0.05;       // floor on the size scale

input string TREND_SET      = "==== Trend engine (H1 Donchian) ====";
input bool   Use_Trend       = true;
input int    Donchian_Period = 10;
input double T_SL_ATR        = 3.0;
input double T_Trail_ATR     = 5.0;
input double T_Risk_Pct      = 0.35;       // v810: trend risk trimmed (it drives portfolio DD)
input int    T_Max           = 1;
input int    T_Magic         = 8002601;

input string MR_SET         = "==== MeanRev engine (M30 BB+RSI) ====";
input bool   Use_MeanRev     = true;
input int    BB_Period       = 20;
input double BB_Dev          = 0.5;
input int    RSI_Period      = 14;
input double RSI_Buy         = 35.0;
input double RSI_Sell        = 65.0;
input double MR_SL_ATR       = 4.0;
input double MR_TP_ATR       = 0.5;
input double MR_Risk_Pct     = 0.45;       // v810: mean-rev risk
input int    MR_Max          = 1;
input int    MR_Magic        = 8002700;

input string ID_SET         = "==== ID ====";
input string Order_Comment  = "BSv810";

datetime g_lastH1 = 0, g_lastM30 = 0;
double   g_peakEq = 0;

int OnInit(){ g_peakEq = AccountEquity(); return(INIT_SUCCEEDED); }
void OnDeinit(const int r){}

// Portfolio drawdown governor: 1.0 at no DD, throttles to Min_Scale as equity DD -> DD_Budget.
double DDScale(){
   if(!Use_DD_Governor || g_peakEq<=0) return 1.0;
   double ddPct=(g_peakEq-AccountEquity())/g_peakEq*100.0;
   if(ddPct<=0) return 1.0;
   double s=(DD_Budget-ddPct)/DD_Budget;
   return MathMax(Min_Scale, MathMin(1.0, s));
}

int CountByMagic(int type,int magic){
   int n=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
      if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES))
         if(OrderSymbol()==Symbol() && OrderMagicNumber()==magic && OrderType()==type) n++;
   return n;
}
double CalcLots(double slDist,double riskPct){
   double tv=MarketInfo(Symbol(),MODE_TICKVALUE), ts=MarketInfo(Symbol(),MODE_TICKSIZE);
   if(tv<=0||ts<=0||slDist<=0) return MarketInfo(Symbol(),MODE_MINLOT);
   double riskAmt=AccountEquity()*riskPct/100.0 * DDScale();
   double lots=riskAmt/((slDist/ts)*tv);
   double minL=MarketInfo(Symbol(),MODE_MINLOT), maxL=MarketInfo(Symbol(),MODE_MAXLOT), step=MarketInfo(Symbol(),MODE_LOTSTEP);
   lots=MathFloor(lots/step)*step; if(lots<minL)lots=minL; if(lots>maxL)lots=maxL;
   return NormalizeDouble(lots,2);
}

// Trailing stop for TREND positions only
void ManageTrend(){
   double atr=iATR(NULL,PERIOD_H1,ATR_Period,1); if(atr<=0) return;
   double trail=T_Trail_ATR*atr;
   for(int i=OrdersTotal()-1;i>=0;i--){
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderSymbol()!=Symbol()||OrderMagicNumber()!=T_Magic) continue;
      if(OrderType()==OP_BUY){
         double s=NormalizeDouble(Bid-trail,Digits);
         if(s>OrderStopLoss()+Point && s<Bid) OrderModify(OrderTicket(),OrderOpenPrice(),s,0,0,clrLime);
      } else if(OrderType()==OP_SELL){
         double s=NormalizeDouble(Ask+trail,Digits);
         if((OrderStopLoss()==0||s<OrderStopLoss()-Point)&&s>Ask) OrderModify(OrderTicket(),OrderOpenPrice(),s,0,0,clrOrange);
      }
   }
}

void OnTick(){
   if(AccountEquity()>g_peakEq) g_peakEq=AccountEquity();   // track equity peak for DD governor
   ManageTrend();
   if((Ask-Bid)/Point>MaxSpread) return;

   double adx = iADX(NULL,PERIOD_H1,ADX_Period,PRICE_CLOSE,MODE_MAIN,1);
   bool trendRegime = (!Use_ADX_Regime) || (adx>=ADX_Split);
   bool mrRegime    = (!Use_ADX_Regime) || (adx< ADX_Split);

   //==== TREND engine (new H1 bar) ====
   if(Use_Trend && trendRegime){
      datetime h1=iTime(NULL,PERIOD_H1,0);
      if(h1!=g_lastH1){
         g_lastH1=h1;
         double atr=iATR(NULL,PERIOD_H1,ATR_Period,1);
         if(atr>0){
            double dHigh=iHigh(NULL,PERIOD_H1,iHighest(NULL,PERIOD_H1,MODE_HIGH,Donchian_Period,2));
            double dLow =iLow (NULL,PERIOD_H1,iLowest (NULL,PERIOD_H1,MODE_LOW ,Donchian_Period,2));
            double c1=iClose(NULL,PERIOD_H1,1);
            double sl=T_SL_ATR*atr;
            if(c1>dHigh && CountByMagic(OP_BUY,T_Magic)<T_Max && CountByMagic(OP_SELL,T_Magic)==0){
               double e=NormalizeDouble(Ask,Digits); double l=CalcLots(sl,T_Risk_Pct);
               if(l>0) OrderSend(Symbol(),OP_BUY,l,e,Slippage,NormalizeDouble(e-sl,Digits),0,Order_Comment,T_Magic,0,clrBlue);
            } else if(c1<dLow && CountByMagic(OP_SELL,T_Magic)<T_Max && CountByMagic(OP_BUY,T_Magic)==0){
               double e=NormalizeDouble(Bid,Digits); double l=CalcLots(sl,T_Risk_Pct);
               if(l>0) OrderSend(Symbol(),OP_SELL,l,e,Slippage,NormalizeDouble(e+sl,Digits),0,Order_Comment,T_Magic,0,clrRed);
            }
         }
      }
   }

   //==== MEAN-REVERSION engine (new M30 bar) ====
   if(Use_MeanRev && mrRegime){
      datetime m30=iTime(NULL,PERIOD_M30,0);
      if(m30!=g_lastM30){
         g_lastM30=m30;
         double atr=iATR(NULL,PERIOD_M30,ATR_Period,1);
         if(atr>0){
            double bbLow=iBands(NULL,PERIOD_M30,BB_Period,BB_Dev,0,PRICE_CLOSE,MODE_LOWER,1);
            double bbUp =iBands(NULL,PERIOD_M30,BB_Period,BB_Dev,0,PRICE_CLOSE,MODE_UPPER,1);
            double rsi  =iRSI (NULL,PERIOD_M30,RSI_Period,PRICE_CLOSE,1);
            double lo1=iLow(NULL,PERIOD_M30,1), hi1=iHigh(NULL,PERIOD_M30,1), c1=iClose(NULL,PERIOD_M30,1);
            double sl=MR_SL_ATR*atr, tp=MR_TP_ATR*atr;
            if(lo1<=bbLow && c1>bbLow && rsi<RSI_Buy && CountByMagic(OP_BUY,MR_Magic)<MR_Max){
               double e=NormalizeDouble(Ask,Digits); double l=CalcLots(sl,MR_Risk_Pct);
               if(l>0) OrderSend(Symbol(),OP_BUY,l,e,Slippage,NormalizeDouble(e-sl,Digits),NormalizeDouble(e+tp,Digits),Order_Comment,MR_Magic,0,clrAqua);
            } else if(hi1>=bbUp && c1<bbUp && rsi>RSI_Sell && CountByMagic(OP_SELL,MR_Magic)<MR_Max){
               double e=NormalizeDouble(Bid,Digits); double l=CalcLots(sl,MR_Risk_Pct);
               if(l>0) OrderSend(Symbol(),OP_SELL,l,e,Slippage,NormalizeDouble(e+sl,Digits),NormalizeDouble(e-tp,Digits),Order_Comment,MR_Magic,0,clrMagenta);
            }
         }
      }
   }
}
//+------------------------------------------------------------------+
