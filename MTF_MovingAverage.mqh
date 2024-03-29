//+------------------------------------------------------------------+
//|                                            MTF_MovingAverage.mqh |
//|                                  Copyright 2022, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2022, MetaQuotes Ltd."
#property link      "https://www.mql5.com"


#include<Mircea/_profitpoint/Base/IndicatorBase.mqh>


enum ENUM_DRAW_MODE
{
   ENUM_DRAW_MODE_STEPS=0,  // Steps
   ENUM_DRAW_MODE_SLOPE=1   // Linear Interpolation(Slope)
};


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
class CMTFMaParams: public CAppParams
{
   ObjectAttr(ENUM_TIMEFRAMES, TimeFrame);
   ObjectAttr(int, Period);
   ObjectAttrProtected(int, Shift);
   ObjectAttr(ENUM_MA_METHOD, Method);
   ObjectAttr(ENUM_APPLIED_PRICE, AppliedPrice);
   ObjectAttr(ENUM_DRAW_MODE, DrawMode);

public:
};
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
class CMTFMovingAverage : public Indicator
{

protected:
   CMTFMaParams*     _params;
   double             _bufferMA[], _bufferTFMA[];
   int                _maHandle;
   double             _maValue;
   ENUM_TIMEFRAMES   timeframe_g;
   int               period_ma;


public:
   ~CMTFMovingAverage()
   {
      SafeDelete(_params);
   }
   CMTFMovingAverage(CMTFMaParams& params)
   {

      _params = GetPointer(params);
#ifdef __MQL5__
      _maHandle = iMA(Symbol(), _params.GetTimeFrame(), _params.GetPeriod(), 0, _params.GetMethod(), _params.GetAppliedPrice());

      if(_maHandle == INVALID_HANDLE)
         Fail("Failed to retrieve data from iMACD Indicator", INIT_FAILED, LOGGER_PREFIX_ERROR);
#endif


      EventSetTimer(90);
      //--- set global variables
      period_ma = int(_params.GetPeriod() < 1 ? 1 : _params.GetPeriod());
      timeframe_g = _params.GetTimeFrame(); //(InpTimeframe>Period() ? InpTimeframe : Period());

      string label = MethodToString(_params.GetMethod()) + " (" + (string)period_ma + "," + TimeframeToString(timeframe_g) + ")";
      IndicatorSetString(INDICATOR_SHORTNAME, label);
      IndicatorSetInteger(INDICATOR_DIGITS, Digits());

      SetIndexBuffer(0, _bufferTFMA, INDICATOR_DATA);
      SetIndexBuffer(1, _bufferMA, INDICATOR_DATA);
      //--- setting plot buffer parameters
      PlotIndexSetString(0, PLOT_LABEL, label);
      //--- setting buffer arrays as timeseries
      ArraySetAsSeries(_bufferTFMA, true);
      ArraySetAsSeries(_bufferMA, true);
   }

public:
   int                Main(const int totalCalc,// size of input time series
                           const int prevCalc,// bars handled in previous call
                           const datetime &time[],
                           const double &open[],
                           const double &high[],
                           const double &low[],
                           const double &close[],
                           const long &tickVolume[],
                           const long &volume[],
                           const int &spread[]) override;


private:
   string MethodToString(ENUM_MA_METHOD method);
   string TimeframeToString(const ENUM_TIMEFRAMES timeframe);
   double EquationDirect(const int left_bar, const double left_price, const int right_bar, const double right_price, const int bar_to_search);
   int BarShift(const string symbol_name, const ENUM_TIMEFRAMES timeframe, const datetime time, bool exact = false);
   datetime Time(const string symbol_name, const ENUM_TIMEFRAMES timeframe, const int shift);

};
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int CMTFMovingAverage::Main(const int totalCalc, const int prevCalc, const datetime &time[], const double &open[], const double &high[], const double &low[], const double &close[], const long &tickVolume[], const long &volume[], const int &spread[])
{
//--- Checking the number of available bars
   if(totalCalc < fmax(period_ma, 4))
      return 0;
//--- Checking and calculating the number of bars to be counted
   int limit = totalCalc - prevCalc;
   if(limit > 1)
   {
      limit = totalCalc - period_ma - 2;
      ArrayInitialize(_bufferTFMA, EMPTY_VALUE);
      ArrayInitialize(_bufferMA, 0);
   }
//---  Data preparation
   if(Time(NULL, timeframe_g, 1) == 0)
      return 0;

   int bars = (timeframe_g == Period() ? totalCalc : Bars(NULL, timeframe_g));

   int count = (limit > 1 ? fmin(bars, totalCalc) : 1);
#ifdef __MQL5__
   int copied = 0;
   copied = CopyBuffer(_maHandle, 0, 0, count, _bufferMA);
   if(copied != count)
      return 0;
#endif


//--- Calculating the indicator
   for(int i = limit; i >= 0 && !IsStopped(); i--)
   {
      datetime time_g = Time(NULL, timeframe_g, i);
      if(time_g == 0)
         continue;
      int bar_curr = BarShift(NULL, PERIOD_CURRENT, time_g);
      if(bar_curr == WRONG_VALUE || bar_curr > totalCalc - period_ma - 2)
         continue;
      int shift = (i > 0 ? 1 : 0);
      datetime time_next = Time(NULL, timeframe_g, i - shift);
      if(time_next == 0)
         continue;
      int bar_next = (i > 0 ? BarShift(NULL, PERIOD_CURRENT, time_next) : 0);
      if(bar_next == WRONG_VALUE || bar_next > totalCalc - period_ma - 2)
         continue;

#ifdef __MQL5__
      _bufferTFMA[bar_curr] = _bufferMA[i];
#else
      _bufferTFMA[bar_curr] = iMA(NULL, _params.GetTimeFrame(), _params.GetPeriod(), 0, _params.GetMethod(), _params.GetAppliedPrice(), i);
#endif
      if(_params.GetDrawMode() == ENUM_DRAW_MODE_STEPS)
         for(int j = bar_curr; j >= bar_next; j--)
            _bufferTFMA[j] = _bufferTFMA[bar_curr];
      else
      {
         datetime time_prev = Time(NULL, timeframe_g, i + 1);
         if(time_prev == 0)
            continue;
         int bar_prev = BarShift(NULL, PERIOD_CURRENT, time_prev);
         if(bar_prev == WRONG_VALUE)
            continue;
         for(int j = bar_prev; j >= bar_curr; j--)
            _bufferTFMA[j] = EquationDirect(bar_prev, _bufferTFMA[bar_prev], bar_curr, _bufferTFMA[bar_curr], j);
      }
   }

//--- return value of prev_calculated for next call
   return(totalCalc);
}
//+------------------------------------------------------------------+
string CMTFMovingAverage::MethodToString(ENUM_MA_METHOD method)
{
   return StringSubstr(EnumToString(method), 5);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
string CMTFMovingAverage::TimeframeToString(const ENUM_TIMEFRAMES timeframe)
{
   return StringSubstr(EnumToString(timeframe), 7);
}
//+------------------------------------------------------------------+
double CMTFMovingAverage::EquationDirect(const int left_bar, const double left_price, const int right_bar, const double right_price, const int bar_to_search)
{
   return(right_bar == left_bar ? left_price : (right_price - left_price) / (right_bar - left_bar) * (bar_to_search - left_bar) + left_price);
}
//+------------------------------------------------------------------+
//| Returns the time offset of the bar                               |
//| https://www.mql5.com/ru/forum/743/page11#comment_7010041         |
//+------------------------------------------------------------------+
int CMTFMovingAverage::BarShift(const string symbol_name, const ENUM_TIMEFRAMES timeframe, const datetime time, bool exact = false)
{
   int res = Bars(symbol_name, timeframe, time + 1, UINT_MAX);
   if(exact)
      if((timeframe != PERIOD_MN1 || time > TimeCurrent()) && res == Bars(symbol_name, timeframe, time - PeriodSeconds(timeframe) + 1, UINT_MAX))
         return(WRONG_VALUE);
   return res;
}
//+------------------------------------------------------------------+
//| Returns Time                                                   |
//+------------------------------------------------------------------+
datetime CMTFMovingAverage::Time(const string symbol_name, const ENUM_TIMEFRAMES timeframe, const int shift)
{
   datetime array[];
   ArraySetAsSeries(array, true);
   return(CopyTime(symbol_name, timeframe, shift, 1, array) == 1 ? array[0] : 0);
}





//+------------------------------------------------------------------+

//
////+------------------------------------------------------------------+
////|                                                                  |
////+------------------------------------------------------------------+
//int CMTFMovingAverage::Main(const int totalCalc, const int prevCalc, const datetime &time[], const double &open[], const double &high[], const double &low[], const double &close[], const long &tickVolume[], const long &volume[], const int &spread[])
//{
////--- Checking the number of available bars
//   if(totalCalc < fmax(period_ma, 4))
//      return 0;
////--- Checking and calculating the number of bars to be counted
//   int limit = totalCalc - prevCalc;
//   if(limit > 1)
//   {
//      limit = totalCalc - period_ma - 2;
//      ArrayInitialize(_bufferTFMA, EMPTY_VALUE);
//      ArrayInitialize(_bufferMA, 0);
//   }
////---  Data preparation
//   if(Time(NULL, timeframe_g, 1) == 0)
//      return 0;
//
//   int bars = (timeframe_g == Period() ? totalCalc : Bars(NULL, timeframe_g));
//
//   int count = (limit > 1 ? fmin(bars, totalCalc) : 1);
//
////--- Calculating the indicator
//   for(int i = limit; i >= 0 && !IsStopped(); i--)
//   {
//      datetime time_g = Time(NULL, timeframe_g, i);
//      if(time_g == 0)
//         continue;
//      int bar_curr = BarShift(NULL, PERIOD_CURRENT, time_g);
//      if(bar_curr == WRONG_VALUE || bar_curr > totalCalc - period_ma - 2)
//         continue;
//      int shift = (i > 0 ? 1 : 0);
//      datetime time_next = Time(NULL, timeframe_g, i - shift);
//      if(time_next == 0)
//         continue;
//      int bar_next = (i > 0 ? BarShift(NULL, PERIOD_CURRENT, time_next) : 0);
//      if(bar_next == WRONG_VALUE || bar_next > totalCalc - period_ma - 2)
//         continue;
//      _bufferTFMA[bar_curr] = iMA(NULL, _params.GetTimeFrame(), _params.GetPeriod(), 0, _params.GetMethod(), _params.GetAppliedPrice(), i);
//
//
//
//      if(_params.GetDrawMode() == DRAW_MODE_STEPS)
//         for(int j = bar_curr; j >= bar_next; j--)
//            _bufferTFMA[j] = _bufferTFMA[bar_curr];
//      else
//      {
//         datetime time_prev = Time(NULL, timeframe_g, i + 1);
//         if(time_prev == 0)
//            continue;
//         int bar_prev = BarShift(NULL, PERIOD_CURRENT, time_prev);
//         if(bar_prev == WRONG_VALUE)
//            continue;
//         for(int j = bar_prev; j >= bar_curr; j--)
//            _bufferTFMA[j] = EquationDirect(bar_prev, _bufferTFMA[bar_prev], bar_curr, _bufferTFMA[bar_curr], j);
//      }
//   }
//
////--- return value of prev_calculated for next call
//   return(totalCalc);
//
//}
