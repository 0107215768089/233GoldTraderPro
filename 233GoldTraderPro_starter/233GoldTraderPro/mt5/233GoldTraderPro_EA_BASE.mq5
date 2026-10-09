//+------------------------------------------------------------------+
//| M1_ThirdTouch_Breakout_SR.mq5                                   |
//| Visual EA: trendlines + 3rd-touch momentum breakout arrows      |
//| BUY  = blue arrow, SELL = red arrow                             |
//| Also draws latest support/resistance levels.                    |
//|                                                                  |
//| This version is SIGNAL/DRAWING ONLY: it does not place orders.   |
//+------------------------------------------------------------------+
#property strict
#property version   "2.00"

#include <Trade/Trade.mqh>

CTrade trade;

input ENUM_TIMEFRAMES SignalTF = PERIOD_M1;

// Trendline / swing settings
input int    LookbackBars          = 180;
input int    PivotLeft             = 2;
input int    PivotRight            = 2;
input int    MinPivotGap           = 4;
input double MaxThirdTouchDistance = 0.0008; // fraction of price, e.g. 0.0008 = 0.08%
input double BreakBufferFraction   = 0.00015;
input int    MinTouches             = 3;

// Momentum candle settings
input int    MomentumAvgBars       = 10;
input double MinBodyPercent        = 0.60;
input double MinBodyVsAverage      = 1.50;

// Support / resistance
input int    SRLookbackBars        = 40;
input int    SRRecentBars          = 20;
input bool   DrawSRZones            = true;

// Display
input color  ResistanceLineColor   = clrTomato;
input color  SupportLineColor      = clrDodgerBlue;
input color  BuyArrowColor         = clrBlue;
input color  SellArrowColor        = clrRed;
input int    TrendlineWidth        = 2;
input int    SRWidth               = 1;
input bool   EnableAlerts           = true;
input bool   ShowPreviousSignals    = true; // Draw signals from closed historical candles
input int    HistoricalSignalBars   = 1000; // Number of past candles to scan

//==================================================================
// TRADE EXECUTION
//==================================================================
input bool   EnableTrading          = true;
input long   MagicNumber            = 20261006;
input double StopLossPercent        = 0.11; // SL distance from entry
input int    DeviationPoints        = 50;
input bool   ReEnterAfterInitialSL  = true;
input bool   TrailOlderTradesToNewestSL = true;
input double RiskPercent = 2.0; // Kept for reference; growth lot bands control actual sizing
input double GrowthBaseEquity = 10.0; // Starting equity for growth schedule
input double GrowthBaseLot = 0.01; // Starting lot for Gold; currency schedules override this
input double TakeProfitPercent = 0.05; // Directional target used for TP and trailing trigger


datetime g_lastBarTime = 0;
datetime g_lastBuySignal = 0;
datetime g_lastSellSignal = 0;

string PREFIX = "TTB_";

// Tickets whose original SL has been moved to the SL of a newer
// same-direction trade. If such a trailed SL is hit, the EA does NOT
// immediately re-enter at that trailed level.
ulong g_trailedTickets[];
ulong g_trailedPositionIDs[];

//+------------------------------------------------------------------+
int OnInit()
{
   DeleteObjectsByPrefix(PREFIX);
   g_lastBarTime = 0;

   // Ensure only arrows remain visible; hide SL/TP trade levels.
   ChartSetInteger(0,CHART_SHOW_TRADE_LEVELS,false);

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(DeviationPoints);
   trade.SetTypeFillingBySymbol(Symbol());

   // Display only signal arrows. Hide MT5 trade-level lines (SL/TP).
   ChartSetInteger(0,CHART_SHOW_TRADE_LEVELS,false);

   // Rebuild historical arrows when the EA is attached or inputs change.
   if(ShowPreviousSignals)
      DrawHistoricalSignals();

   return(INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Keep signal arrows on the chart after the EA is removed.
   // They are cleared and rebuilt automatically on the next initialization.
}
//+------------------------------------------------------------------+
void OnTick()
{
   datetime currentBar = iTime(Symbol(), SignalTF, 0);
   if(currentBar == 0) return;

   // Keep the chart clean: only signal arrows are displayed.
   // Structure/trendline/SR drawings are intentionally not rendered.

   if(currentBar != g_lastBarTime)
   {
      g_lastBarTime = currentBar;
      CheckSignals(1,true);
      ManageDirectionalTPTrail();
   }
}
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
void UpdateStructure()
{
   // Intentionally disabled: the EA now displays signal arrows only.
}
//+------------------------------------------------------------------+
// Find swing high/low. Shift 0 is the current forming candle.
// We only use closed candles, so shifts >= PivotRight+1 are used.
//+------------------------------------------------------------------+
bool IsSwingHigh(int shift)
{
   double h = iHigh(Symbol(), SignalTF, shift);
   if(h <= 0) return false;

   for(int j=1; j<=PivotLeft; j++)
      if(iHigh(Symbol(), SignalTF, shift+j) >= h) return false;

   for(int j=1; j<=PivotRight; j++)
      if(iHigh(Symbol(), SignalTF, shift-j) > h) return false;

   return true;
}
//+------------------------------------------------------------------+
bool IsSwingLow(int shift)
{
   double l = iLow(Symbol(), SignalTF, shift);
   if(l <= 0) return false;

   for(int j=1; j<=PivotLeft; j++)
      if(iLow(Symbol(), SignalTF, shift+j) <= l) return false;

   for(int j=1; j<=PivotRight; j++)
      if(iLow(Symbol(), SignalTF, shift-j) < l) return false;

   return true;
}
//+------------------------------------------------------------------+
void GetRecentHighPivots(int &p1, int &p2, int signalShift=1)
{
   p1=-1; p2=-1;
   int maxShift = MathMin(signalShift+LookbackBars, iBars(Symbol(),SignalTF)-PivotLeft-2);

   // Only pivots older than the signal candle are used; no future data.
   for(int s=signalShift+PivotRight+1; s<=maxShift; s++)
   {
      if(IsSwingHigh(s))
      {
         if(p1==-1) p1=s;
         else if(MathAbs(s-p1) >= MinPivotGap)
         {
            p2=s;
            return;
         }
      }
   }
}
//+------------------------------------------------------------------+
void GetRecentLowPivots(int &p1, int &p2, int signalShift=1)
{
   p1=-1; p2=-1;
   int maxShift = MathMin(signalShift+LookbackBars, iBars(Symbol(),SignalTF)-PivotLeft-2);

   // Only pivots older than the signal candle are used; no future data.
   for(int s=signalShift+PivotRight+1; s<=maxShift; s++)
   {
      if(IsSwingLow(s))
      {
         if(p1==-1) p1=s;
         else if(MathAbs(s-p1) >= MinPivotGap)
         {
            p2=s;
            return;
         }
      }
   }
}
//+------------------------------------------------------------------+
double LinePrice(datetime t1,double p1,datetime t2,double p2,datetime t)
{
   if(t2==t1) return p2;
   return p1 + (p2-p1) * ((double)(t-t1)/(double)(t2-t1));
}
//+------------------------------------------------------------------+
void DrawTrend(string name, int s1, int s2, color clr)
{
   datetime t1=iTime(Symbol(),SignalTF,s1);
   datetime t2=iTime(Symbol(),SignalTF,s2);
   double p1 = (clr==ResistanceLineColor) ? iHigh(Symbol(),SignalTF,s1)
                                          : iLow(Symbol(),SignalTF,s1);
   double p2 = (clr==ResistanceLineColor) ? iHigh(Symbol(),SignalTF,s2)
                                          : iLow(Symbol(),SignalTF,s2);

   if(ObjectFind(0,name) < 0)
      ObjectCreate(0,name,OBJ_TREND,0,t2,p2,t1,p1);
   else
   {
      ObjectMove(0,name,0,t2,p2);
      ObjectMove(0,name,1,t1,p1);
   }

   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,TrendlineWidth);
   ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,true);
   ObjectSetInteger(0,name,OBJPROP_BACK,false);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
}
//+------------------------------------------------------------------+
void DrawLatestTrendlines()
{
   int hi1,hi2,lo1,lo2;
   GetRecentHighPivots(hi1,hi2);
   GetRecentLowPivots(lo1,lo2);

   // We want a descending resistance line.
   if(hi1>0 && hi2>0)
   {
      double recentHigh = iHigh(Symbol(),SignalTF,hi1);
      double olderHigh  = iHigh(Symbol(),SignalTF,hi2);

      if(recentHigh < olderHigh)
         DrawTrend(PREFIX+"RES_TREND",hi2,hi1,ResistanceLineColor);
      else
         ObjectDelete(0,PREFIX+"RES_TREND");
   }

   // We want an ascending support line.
   if(lo1>0 && lo2>0)
   {
      double recentLow = iLow(Symbol(),SignalTF,lo1);
      double olderLow  = iLow(Symbol(),SignalTF,lo2);

      if(recentLow > olderLow)
         DrawTrend(PREFIX+"SUP_TREND",lo2,lo1,SupportLineColor);
      else
         ObjectDelete(0,PREFIX+"SUP_TREND");
   }
}
//+------------------------------------------------------------------+
void DrawHLine(string name,double price,color clr)
{
   if(price<=0) return;

   if(ObjectFind(0,name)<0)
      ObjectCreate(0,name,OBJ_HLINE,0,0,price);

   ObjectSetDouble(0,name,OBJPROP_PRICE,price);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,SRWidth);
   ObjectSetInteger(0,name,OBJPROP_STYLE,STYLE_DASH);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_BACK,true);
}
//+------------------------------------------------------------------+
void DrawLatestSR()
{
   if(!DrawSRZones) return;

   int bars=iBars(Symbol(),SignalTF);
   int n=MathMin(SRRecentBars,bars-2);
   if(n<5) return;

   // Use the most recent region, rather than the whole historical chart.
   double resistance=-DBL_MAX;
   double support=DBL_MAX;

   for(int s=1;s<=n;s++)
   {
      resistance=MathMax(resistance,iHigh(Symbol(),SignalTF,s));
      support=MathMin(support,iLow(Symbol(),SignalTF,s));
   }

   DrawHLine(PREFIX+"RESISTANCE",resistance,ResistanceLineColor);
   DrawHLine(PREFIX+"SUPPORT",support,SupportLineColor);
}
//+------------------------------------------------------------------+
// Return average candle body for closed candles before signalShift.
//+------------------------------------------------------------------+
double AverageBody(int signalShift)
{
   double sum=0;
   int count=0;

   for(int s=signalShift+1;s<=signalShift+MomentumAvgBars;s++)
   {
      if(s>=iBars(Symbol(),SignalTF)) break;
      sum += MathAbs(iClose(Symbol(),SignalTF,s)-iOpen(Symbol(),SignalTF,s));
      count++;
   }

   if(count==0) return 0;
   return sum/count;
}
//+------------------------------------------------------------------+
bool IsMomentumBull(int shift)
{
   double o=iOpen(Symbol(),SignalTF,shift);
   double c=iClose(Symbol(),SignalTF,shift);
   double h=iHigh(Symbol(),SignalTF,shift);
   double l=iLow(Symbol(),SignalTF,shift);

   double range=h-l;
   double body=c-o;
   if(range<=0 || body<=0) return false;

   if(body/range < MinBodyPercent) return false;

   double avg=AverageBody(shift);
   if(avg>0 && body < avg*MinBodyVsAverage) return false;

   return true;
}
//+------------------------------------------------------------------+
bool IsMomentumBear(int shift)
{
   double o=iOpen(Symbol(),SignalTF,shift);
   double c=iClose(Symbol(),SignalTF,shift);
   double h=iHigh(Symbol(),SignalTF,shift);
   double l=iLow(Symbol(),SignalTF,shift);

   double range=h-l;
   double body=o-c;
   if(range<=0 || body<=0) return false;

   if(body/range < MinBodyPercent) return false;

   double avg=AverageBody(shift);
   if(avg>0 && body < avg*MinBodyVsAverage) return false;

   return true;
}
//+------------------------------------------------------------------+
// Count touches of a descending resistance trendline between the
// older anchor and the signal candle.
//+------------------------------------------------------------------+
int CountResistanceTouches(int oldShift,int recentShift,int signalShift)
{
   datetime tOld=iTime(Symbol(),SignalTF,oldShift);
   datetime tRecent=iTime(Symbol(),SignalTF,recentShift);
   double pOld=iHigh(Symbol(),SignalTF,oldShift);
   double pRecent=iHigh(Symbol(),SignalTF,recentShift);

   int touches=0;
   double tolerance=_Point*20;

   for(int s=oldShift;s>=signalShift;s--)
   {
      datetime t=iTime(Symbol(),SignalTF,s);
      double line=LinePrice(tOld,pOld,tRecent,pRecent,t);
      double high=iHigh(Symbol(),SignalTF,s);

      if(MathAbs(high-line) <= MathMax(tolerance,line*MaxThirdTouchDistance))
         touches++;
   }
   return touches;
}
//+------------------------------------------------------------------+
int CountSupportTouches(int oldShift,int recentShift,int signalShift)
{
   datetime tOld=iTime(Symbol(),SignalTF,oldShift);
   datetime tRecent=iTime(Symbol(),SignalTF,recentShift);
   double pOld=iLow(Symbol(),SignalTF,oldShift);
   double pRecent=iLow(Symbol(),SignalTF,recentShift);

   int touches=0;
   double tolerance=_Point*20;

   for(int s=oldShift;s>=signalShift;s--)
   {
      datetime t=iTime(Symbol(),SignalTF,s);
      double line=LinePrice(tOld,pOld,tRecent,pRecent,t);
      double low=iLow(Symbol(),SignalTF,s);

      if(MathAbs(low-line) <= MathMax(tolerance,line*MaxThirdTouchDistance))
         touches++;
   }
   return touches;
}
//+------------------------------------------------------------------+
void PutArrow(string name,datetime t,double price,bool buy)
{
   if(ObjectFind(0,name)>=0) return;

   ObjectCreate(0,name,OBJ_ARROW,0,t,price);
   ObjectSetInteger(0,name,OBJPROP_ARROWCODE,buy ? 233 : 234);
   ObjectSetInteger(0,name,OBJPROP_COLOR,buy ? BuyArrowColor : SellArrowColor);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,2);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_BACK,false);
}
//+------------------------------------------------------------------+
void CheckSignals(int signalShift, bool allowAlerts)
{
   int hi1,hi2,lo1,lo2;
   GetRecentHighPivots(hi1,hi2,signalShift);
   GetRecentLowPivots(lo1,lo2,signalShift);

   datetime signalTime=iTime(Symbol(),SignalTF,signalShift);
   double point=_Point;
   double buffer=MathMax(point*10,iClose(Symbol(),SignalTF,signalShift)*BreakBufferFraction);

   // -------- BUY: descending resistance + 3rd touch + bullish break
   if(hi1>0 && hi2>0)
   {
      double recentHigh=iHigh(Symbol(),SignalTF,hi1);
      double olderHigh=iHigh(Symbol(),SignalTF,hi2);

      if(recentHigh<olderHigh)
      {
         datetime tOld=iTime(Symbol(),SignalTF,hi2);
         datetime tRecent=iTime(Symbol(),SignalTF,hi1);
         double line=LinePrice(tOld,olderHigh,tRecent,recentHigh,signalTime);

         int touches=CountResistanceTouches(hi2,hi1,signalShift);

         double close=iClose(Symbol(),SignalTF,signalShift);

         if(touches>=MinTouches &&
            close > line+buffer &&
            IsMomentumBull(signalShift) &&
            signalTime!=g_lastBuySignal)
         {
            double arrowPrice=iLow(Symbol(),SignalTF,signalShift)-10*point;
            PutArrow(PREFIX+"BUY_"+IntegerToString((int)signalTime),
                     signalTime,arrowPrice,true);
            g_lastBuySignal=signalTime;

                        if(allowAlerts && EnableTrading)
               ExecuteArrowTrade(true,signalTime);

            if(EnableAlerts && allowAlerts)
               Alert(Symbol()," M1 BUY: 3rd-touch trendline breakout + momentum candle.");
         }
      }
   }

   // -------- SELL: ascending support + 3rd touch + bearish break
   if(lo1>0 && lo2>0)
   {
      double recentLow=iLow(Symbol(),SignalTF,lo1);
      double olderLow=iLow(Symbol(),SignalTF,lo2);

      if(recentLow>olderLow)
      {
         datetime tOld=iTime(Symbol(),SignalTF,lo2);
         datetime tRecent=iTime(Symbol(),SignalTF,lo1);
         double line=LinePrice(tOld,olderLow,tRecent,recentLow,signalTime);

         int touches=CountSupportTouches(lo2,lo1,signalShift);

         double close=iClose(Symbol(),SignalTF,signalShift);

         if(touches>=MinTouches &&
            close < line-buffer &&
            IsMomentumBear(signalShift) &&
            signalTime!=g_lastSellSignal)
         {
            double arrowPrice=iHigh(Symbol(),SignalTF,signalShift)+10*point;
            PutArrow(PREFIX+"SELL_"+IntegerToString((int)signalTime),
                     signalTime,arrowPrice,false);
            g_lastSellSignal=signalTime;

                        if(allowAlerts && EnableTrading)
               ExecuteArrowTrade(false,signalTime);

            if(EnableAlerts && allowAlerts)
               Alert(Symbol()," M1 SELL: 3rd-touch trendline breakout + momentum candle.");
         }
      }
   }
}
//+------------------------------------------------------------------+
// Account-growth position sizing.
// The existing SL is NOT changed. Lot size is selected from the requested
// equity bands so a small account can trade and size grows as equity grows.
// Gold: $10-$19=0.01, $20-$50=0.02, $51-$100=0.04, then doubles each
// time the upper equity band doubles (101-200=0.08, 201-400=0.16, etc.).
// FX (including USDJPY): $10-$30=0.03, $31-$50=0.06, then doubles
// on each subsequent 2x equity band (51-100=0.12, 101-200=0.24, etc.).
//+------------------------------------------------------------------+
bool IsGoldSymbol()
{
   string s=Symbol();
   StringToUpper(s);
   return (StringFind(s,"XAU",0)>=0 || StringFind(s,"GOLD",0)>=0);
}
//+------------------------------------------------------------------+
double GrowthLotForEquity(double equity)
{
   if(equity<=0.0) return 0.0;

   if(IsGoldSymbol())
   {
      if(equity < 20.0) return 0.01;
      if(equity <= 50.0) return 0.02;

      double lot=0.04;
      double upper=100.0;
      while(equity > upper && upper < 100000000.0)
      {
         lot*=2.0;
         upper*=2.0;
      }
      return lot;
   }

   // Currency-pair schedule (USDJPY and other FX symbols).
   if(equity <= 30.0) return 0.03;
   if(equity <= 50.0) return 0.06;

   double lot=0.12;
   double upper=100.0;
   while(equity > upper && upper < 100000000.0)
   {
      lot*=2.0;
      upper*=2.0;
   }
   return lot;
}
//+------------------------------------------------------------------+
double CalculateGrowthLot(bool buy,double entry,double sl)
{
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity<=0.0) return 0.0;

   double minLot=SymbolInfoDouble(Symbol(),SYMBOL_VOLUME_MIN);
   double maxLot=SymbolInfoDouble(Symbol(),SYMBOL_VOLUME_MAX);
   double stepLot=SymbolInfoDouble(Symbol(),SYMBOL_VOLUME_STEP);
   if(minLot<=0.0) minLot=0.01;
   if(maxLot<=0.0) maxLot=100.0;
   if(stepLot<=0.0) stepLot=minLot;

   double requested=GrowthLotForEquity(equity);
   double lot=MathMax(requested,minLot);
   lot=MathMin(lot,maxLot);

   // Round down to the broker's volume step. If the requested schedule is
   // below the minimum, the broker minimum is used so the trade is allowed.
   lot=MathFloor((lot+1e-12)/stepLot)*stepLot;
   if(lot<minLot) lot=minLot;
   lot=MathMin(lot,maxLot);

   int digits=2;
   if(stepLot<0.01) digits=3;
   if(stepLot<0.001) digits=4;

   Print("Growth lot: symbol=",Symbol(),
         " equity=",DoubleToString(equity,2),
         " requested=",DoubleToString(requested,digits),
         " final=",DoubleToString(lot,digits));
   return NormalizeDouble(lot,digits);
}
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
double NormalizePrice(double price)
{
   int digits=(int)SymbolInfoInteger(Symbol(),SYMBOL_DIGITS);
   return NormalizeDouble(price,digits);
}
//+------------------------------------------------------------------+
// Calculate the initial SL. The distance is 0.17% of the entry price.
// Broker stop-level rules are respected so an order is not rejected.
//+------------------------------------------------------------------+
double InitialStopLoss(bool buy,double entry)
{
   double distance = entry * (StopLossPercent/100.0);
   double minStopDistance = (double)SymbolInfoInteger(Symbol(),SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   double freezeDistance  = (double)SymbolInfoInteger(Symbol(),SYMBOL_TRADE_FREEZE_LEVEL) * _Point;
   double required = MathMax(minStopDistance,freezeDistance);
   if(distance < required) distance = required + (2.0*_Point);

   if(buy)
      return NormalizePrice(entry-distance);
   return NormalizePrice(entry+distance);
}
//+------------------------------------------------------------------+
bool IsTicketTrailed(ulong ticket)
{
   for(int i=0;i<ArraySize(g_trailedTickets);i++)
      if(g_trailedTickets[i]==ticket) return true;
   return false;
}
//+------------------------------------------------------------------+
void MarkTicketTrailed(ulong ticket)
{
   if(ticket==0 || IsTicketTrailed(ticket)) return;

   int n=ArraySize(g_trailedTickets);
   ArrayResize(g_trailedTickets,n+1);
   g_trailedTickets[n]=ticket;

   if(PositionSelectByTicket(ticket))
   {
      ulong positionID=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
      int m=ArraySize(g_trailedPositionIDs);
      ArrayResize(g_trailedPositionIDs,m+1);
      g_trailedPositionIDs[m]=positionID;
   }
}
//+------------------------------------------------------------------+
void RemoveTicketFromTrailingList(ulong ticket)
{
   ulong positionID=0;
   if(PositionSelectByTicket(ticket))
      positionID=(ulong)PositionGetInteger(POSITION_IDENTIFIER);

   for(int i=ArraySize(g_trailedTickets)-1;i>=0;i--)
   {
      if(g_trailedTickets[i]==ticket)
      {
         int last=ArraySize(g_trailedTickets)-1;
         if(i!=last) g_trailedTickets[i]=g_trailedTickets[last];
         ArrayResize(g_trailedTickets,last);
      }
   }

   if(positionID>0)
   {
      for(int i=ArraySize(g_trailedPositionIDs)-1;i>=0;i--)
      {
         if(g_trailedPositionIDs[i]==positionID)
         {
            int last=ArraySize(g_trailedPositionIDs)-1;
            if(i!=last) g_trailedPositionIDs[i]=g_trailedPositionIDs[last];
            ArrayResize(g_trailedPositionIDs,last);
         }
      }
   }
}
//+------------------------------------------------------------------+
bool IsOurPositionTicket(ulong ticket)
{
   if(ticket==0 || !PositionSelectByTicket(ticket)) return false;
   if(PositionGetString(POSITION_SYMBOL)!=Symbol()) return false;
   if((long)PositionGetInteger(POSITION_MAGIC)!=MagicNumber) return false;
   return true;
}
//+------------------------------------------------------------------+
int CountOurPositions(ENUM_POSITION_TYPE type)
{
   int count=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(!IsOurPositionTicket(ticket)) continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)==type)
         count++;
   }
   return count;
}
//+------------------------------------------------------------------+
bool CloseOurPositions(ENUM_POSITION_TYPE type)
{
   bool allClosed=true;

   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(!IsOurPositionTicket(ticket)) continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)!=type) continue;

      if(!trade.PositionClose(ticket))
      {
         allClosed=false;
         Print("Failed to close opposite position #",ticket,
               ". Retcode=",trade.ResultRetcode()," ",trade.ResultRetcodeDescription());
      }
      else
         RemoveTicketFromTrailingList(ticket);
   }

   return allClosed;
}
//+------------------------------------------------------------------+
// Move all older same-direction positions to the newest trade's SL.
// The newest trade keeps its own initial SL.
//+------------------------------------------------------------------+
void TrailOlderPositionsToNewestSL(ENUM_POSITION_TYPE type,double newestSL,ulong newestTicket)
{
   if(!TrailOlderTradesToNewestSL || newestSL<=0) return;

   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(!IsOurPositionTicket(ticket)) continue;
      if(ticket==newestTicket) continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)!=type) continue;

      double oldSL=PositionGetDouble(POSITION_SL);
      bool shouldMove=false;

      if(type==POSITION_TYPE_BUY)
      {
         // A buy SL can only be trailed upward.
         if(oldSL<=0 || newestSL>oldSL+(_Point*0.5)) shouldMove=true;
      }
      else
      {
         // A sell SL can only be trailed downward.
         if(oldSL<=0 || newestSL<oldSL-(_Point*0.5)) shouldMove=true;
      }

      if(!shouldMove) continue;

      if(trade.PositionModify(ticket,newestSL,PositionGetDouble(POSITION_TP)))
      {
         MarkTicketTrailed(ticket);
         Print("Trailed ",type==POSITION_TYPE_BUY?"BUY":"SELL",
               " #",ticket," SL to ",DoubleToString(newestSL,_Digits),
               " using newest trade #",newestTicket);
      }
      else
      {
         Print("Failed to trail position #",ticket,
               ". Retcode=",trade.ResultRetcode()," ",trade.ResultRetcodeDescription());
      }
   }
}
//+------------------------------------------------------------------+
// When a closed candle reaches the 0.05% directional target of an open
// trade, move older same-direction positions' SL to that target. This is
// deliberately candle-close based, so intrabar spikes do not trigger it.
void ManageDirectionalTPTrail()
{
   if(!EnableTrading || !TrailOlderTradesToNewestSL) return;

   double candleClose=iClose(Symbol(),SignalTF,1);
   if(candleClose<=0.0) return;

   for(int typeIndex=0; typeIndex<2; typeIndex++)
   {
      ENUM_POSITION_TYPE type=(typeIndex==0) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
      ulong newestTicket=0;
      datetime newestTime=0;
      double newestTP=0.0;

      for(int i=PositionsTotal()-1;i>=0;i--)
      {
         ulong ticket=PositionGetTicket(i);
         if(!IsOurPositionTicket(ticket)) continue;
         if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)!=type) continue;

         datetime pt=(datetime)PositionGetInteger(POSITION_TIME);
         if(pt>newestTime || (pt==newestTime && ticket>newestTicket))
         {
            newestTime=pt;
            newestTicket=ticket;
            newestTP=PositionGetDouble(POSITION_TP);
         }
      }

      if(newestTicket==0 || newestTP<=0.0) continue;

      bool targetReached=(type==POSITION_TYPE_BUY)
                         ? (candleClose>=newestTP)
                         : (candleClose<=newestTP);
      if(!targetReached) continue;

      TrailOlderPositionsToNewestSL(type,newestTP,newestTicket);
   }
}
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
// Open a market trade for the arrow. Opposite positions are closed
// first. Same-direction arrows create additional positions.
//+------------------------------------------------------------------+
void ExecuteArrowTrade(bool buy,datetime signalTime)
{
   if(!EnableTrading) return;

   ENUM_POSITION_TYPE newType = buy ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
   ENUM_POSITION_TYPE oldType = buy ? POSITION_TYPE_SELL : POSITION_TYPE_BUY;

   // Capture the TP level of the most recent same-direction trade before
   // opening the new one. If the new trade is added in the same direction,
   // that previous TP is the level to which the older trade(s) are trailed.
   double previousSameDirectionTP=0.0;
   datetime previousSameDirectionTime=0;
   ulong previousSameDirectionTicket=0;
   for(int pi=PositionsTotal()-1;pi>=0;pi--)
   {
      ulong pticket=PositionGetTicket(pi);
      if(!IsOurPositionTicket(pticket)) continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)!=newType) continue;
      datetime ptime=(datetime)PositionGetInteger(POSITION_TIME);
      if(ptime>previousSameDirectionTime ||
         (ptime==previousSameDirectionTime && pticket>previousSameDirectionTicket))
      {
         previousSameDirectionTime=ptime;
         previousSameDirectionTicket=pticket;
         previousSameDirectionTP=PositionGetDouble(POSITION_TP);
      }
   }

   // An opposite arrow means: close every floating opposite trade first.
   // Do not open the reversal until all opposite EA positions are closed.
   if(!CloseOurPositions(oldType))
   {
      Print("Reversal cancelled because an opposite position could not be closed.");
      return;
   }

   MqlTick tick;
   if(!SymbolInfoTick(Symbol(),tick))
   {
      Print("No tick available; cannot execute arrow at ",TimeToString(signalTime));
      return;
   }

   double entry=buy ? tick.ask : tick.bid;
   if(entry<=0) return;

   // Keep the existing SL calculation unchanged. Only lot size and TP are
   // added here.
   double sl=InitialStopLoss(buy,entry);
   double lot=CalculateGrowthLot(buy,entry,sl);
   if(lot<=0) return;

   double tpDistance=entry*(TakeProfitPercent/100.0);
   double tp=buy ? NormalizePrice(entry+tpDistance)
                  : NormalizePrice(entry-tpDistance);

   string comment="233Bot";

   bool ok=false;
   if(buy)
      ok=trade.Buy(lot,Symbol(),0.0,sl,tp,comment);
   else
      ok=trade.Sell(lot,Symbol(),0.0,sl,tp,comment);

   if(!ok)
   {
      Print("Arrow trade failed: ",comment,
            " lot=",DoubleToString(lot,2),
            " entry=",DoubleToString(entry,_Digits),
            " SL=",DoubleToString(sl,_Digits),
            " retcode=",trade.ResultRetcode()," ",trade.ResultRetcodeDescription());
      return;
   }

   // CTrade's result order/deal is not guaranteed to be a position ticket
   // in every account mode, so locate the newest position by symbol/magic.
   ulong newestTicket=0;
   datetime newestTime=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(!IsOurPositionTicket(ticket)) continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)!=newType) continue;

      datetime pt=(datetime)PositionGetInteger(POSITION_TIME);
      if(pt>newestTime || (pt==newestTime && ticket>newestTicket))
      {
         newestTime=pt;
         newestTicket=ticket;
      }
   }

   if(newestTicket>0 && PositionSelectByTicket(newestTicket))
   {
      // If this is a second/third/etc. same-direction trade, use the
      // PREVIOUS trade's 0.05% TP level as the trailing SL level.
      if(previousSameDirectionTicket>0 && previousSameDirectionTP>0.0)
         TrailOlderPositionsToNewestSL(newType,previousSameDirectionTP,newestTicket);
   }

   Print("EXECUTED ",comment,
         " | lot=",DoubleToString(lot,2),
         " | entry=",DoubleToString(entry,_Digits),
         " | SL=",DoubleToString(sl,_Digits),
         " | balance=",DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE),2));
}
//+------------------------------------------------------------------+
// If an initial (not previously trailed) SL is hit, immediately
// re-enter in the same direction. A SL that was moved because of a
// newer same-direction trade is deliberately excluded.
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(!EnableTrading || !ReEnterAfterInitialSL) return;
   if(trans.type!=TRADE_TRANSACTION_DEAL_ADD) return;
   if(trans.deal==0) return;
   if(!HistoryDealSelect(trans.deal)) return;

   string dealSymbol=HistoryDealGetString(trans.deal,DEAL_SYMBOL);
   if(dealSymbol!=Symbol()) return;

   long magic=HistoryDealGetInteger(trans.deal,DEAL_MAGIC);
   if(magic!=MagicNumber) return;

   long entry=HistoryDealGetInteger(trans.deal,DEAL_ENTRY);
   long reason=HistoryDealGetInteger(trans.deal,DEAL_REASON);
   if(entry!=DEAL_ENTRY_OUT || reason!=DEAL_REASON_SL) return;

   ulong positionID=(ulong)HistoryDealGetInteger(trans.deal,DEAL_POSITION_ID);
   bool wasTrailed=false;

   // POSITION_IDENTIFIER survives after the position itself is closed,
   // so it is the reliable way to recognise a previously trailed trade.
   if(positionID>0)
   {
      for(int i=ArraySize(g_trailedPositionIDs)-1;i>=0;i--)
      {
         if(g_trailedPositionIDs[i]==positionID)
         {
            wasTrailed=true;
            ArrayRemove(g_trailedPositionIDs,i,1);
            break;
         }
      }
   }

   if(IsTicketTrailed((ulong)trans.position)) wasTrailed=true;
   if(wasTrailed)
   {
      Print("SL hit on a TRAILED position. No re-entry is made at the trailed SL.");
      return;
   }

   long dealType=HistoryDealGetInteger(trans.deal,DEAL_TYPE);
   bool buyReentry=(dealType==DEAL_TYPE_SELL);

   Print("Initial SL hit. Re-entering ",buyReentry?"BUY":"SELL"," immediately.");
   ExecuteArrowTrade(buyReentry,(datetime)TimeCurrent());
}
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
void DrawHistoricalSignals()
{
   int bars=iBars(Symbol(),SignalTF);
   if(bars<=PivotLeft+PivotRight+MomentumAvgBars+5) return;

   int maxSignalShift=MathMin(HistoricalSignalBars,
                              bars-LookbackBars-PivotLeft-2);
   if(maxSignalShift<1)
      maxSignalShift=MathMin(HistoricalSignalBars,bars-PivotLeft-PivotRight-MomentumAvgBars-3);

   // Scan oldest to newest so historical arrows appear in chronological order.
   for(int shift=maxSignalShift; shift>=1; shift--)
      CheckSignals(shift,false);

   ChartRedraw(0);
}
//+------------------------------------------------------------------+
void DeleteObjectsByPrefix(string prefix)
{
   for(int i=ObjectsTotal(0)-1;i>=0;i--)
   {
      string name=ObjectName(0,i);
      if(StringFind(name,prefix,0)==0)
         ObjectDelete(0,name);
   }
}
//+------------------------------------------------------------------+
