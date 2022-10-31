//+------------------------------------------------------------------+
//|                                                          QQE.mq5 |
//|                                 Copyright © 2010-2022, EarnForex |
//|                                        https://www.earnforex.com |
//|                             Based on version by Tim Hyder (2008) |
//|                         Based on version by Roman Ignatov (2006) |
//+------------------------------------------------------------------+
#property copyright "www.EarnForex.com, 2010-2022"
#property link      "https://www.earnforex.com/metatrader-indicators/QQE/"
#property version   "1.03"

#property description "QQE - Qualitative Quantitative Estimation."
#property description "Calculated as two indicators:"
#property description "1) MA on RSI"
#property description "2) Difference of MA on RSI and MA of MA of ATR of MA of RSI"
#property description "The signal for buy is when blue line crosses level 50 from below after crossing the yellow line from below."
#property description "The signal for sell is when blue line crosses level 50 from above after crossing the yellow line from above."

#property indicator_separate_window
#property indicator_buffers 6
#property indicator_plots   2
#property indicator_width1 2
#property indicator_color1 clrDodgerBlue
#property indicator_type1 DRAW_LINE
#property indicator_label1 "RSI MA"
#property indicator_color2 clrYellow
#property indicator_type2 DRAW_LINE
#property indicator_style2 STYLE_DOT
#property indicator_label2 "Smoothed"
#property indicator_level1 50
#property indicator_levelcolor clrAqua
#property indicator_levelstyle STYLE_DOT

// Inputs
input int SF = 5; // Smoothing Factor
input bool AlertOnCrossover = false;
input bool AlertOnLevel = false;
input int AlertLevel = 50;
input bool ArrowsOnCrossover = true;
input color CrossoverUpArrow = clrGreen;
input color CrossoverDnArrow = clrRed;
input bool ArrowsOnLevel = true;
input color LevelUpArrow = clrGreen;
input color LevelDnArrow = clrRed;
input bool NativeAlerts = false;
input bool EmailAlerts = false;
input bool NotificationAlerts = false;
input ENUM_TIMEFRAMES UpperTimeframe = PERIOD_CURRENT;
input string ObjectPrefix = "QQE-";

// Global variables:
int RSI_Period = 14;
int Wilders_Period;
int StartBar;
datetime LastAlertTimeCross, LastAlertTimeLevel;

// For MTF support:
int QQE_handle;

// Buffers:
double TrLevelSlow[];
double AtrRsi[];
double MaAtrRsi[];
double Rsi[];
double RsiMa[];
double MaMaAtrRsi[];

// Indicator handles
int myRSI;

void OnInit()
{
    LastAlertTimeCross = 0;
    LastAlertTimeLevel = 0;
    Wilders_Period = RSI_Period * 2 - 1;
    StartBar = MathMax(SF, Wilders_Period);

    SetIndexBuffer(0, RsiMa, INDICATOR_DATA);
    SetIndexBuffer(1, TrLevelSlow, INDICATOR_DATA);
    SetIndexBuffer(2, AtrRsi, INDICATOR_CALCULATIONS);
    SetIndexBuffer(3, MaAtrRsi, INDICATOR_CALCULATIONS);
    SetIndexBuffer(4, Rsi, INDICATOR_CALCULATIONS);
    SetIndexBuffer(5, MaMaAtrRsi, INDICATOR_CALCULATIONS);

    ArraySetAsSeries(RsiMa, true);
    ArraySetAsSeries(TrLevelSlow, true);
    ArraySetAsSeries(AtrRsi, true);
    ArraySetAsSeries(MaAtrRsi, true);
    ArraySetAsSeries(Rsi, true);
    ArraySetAsSeries(MaMaAtrRsi, true);

    PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, 0);
    PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, 0);

    PlotIndexSetInteger(0, PLOT_DRAW_BEGIN, StartBar);
    PlotIndexSetInteger(1, PLOT_DRAW_BEGIN, StartBar);

    IndicatorSetInteger(INDICATOR_DIGITS, 2);
    
    myRSI = iRSI(Symbol(), Period(), RSI_Period, PRICE_CLOSE);
    
    if (PeriodSeconds(UpperTimeframe) > PeriodSeconds())
    {
        string IndicatorFileName = MQLInfoString(MQL_PROGRAM_NAME);
        QQE_handle = iCustom(Symbol(), UpperTimeframe, IndicatorFileName, SF, false, false, AlertLevel, false, LevelUpArrow, LevelDnArrow, false, CrossoverUpArrow, CrossoverDnArrow, false, false, false, UpperTimeframe, ObjectPrefix);
    }
    else
    {
        QQE_handle = INVALID_HANDLE;
        if (PeriodSeconds(UpperTimeframe) < PeriodSeconds())
        {
            Print("UpperTimeframe should be above the current timeframe.");
        }
    }

    IndicatorSetString(INDICATOR_SHORTNAME, "QQE(" + IntegerToString(SF) + ")");
}

void OnDeinit(const int reason)
{
    ObjectsDeleteAll(ChartID(), ObjectPrefix);
}

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &Time[],
                const double &open[],
                const double &High[],
                const double &Low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
    ArraySetAsSeries(Time, true);
    ArraySetAsSeries(High, true);
    ArraySetAsSeries(Low, true);
    
    if (rates_total <= StartBar) return 0;

    int counted = prev_calculated - 1;
    if (counted < 1)
    {
        for (int i = rates_total - StartBar; i < rates_total; i++)
        {
            TrLevelSlow[i] = 0.0;
            AtrRsi[i] = 0.0;
            MaAtrRsi[i] = 0.0;
            Rsi[i] = 0.0;
            RsiMa[i] = 0.0;
            MaMaAtrRsi[i] = 0.0;
        }
    }
    
    bool rec_only_latest_upper_bar = false; // Recalculate only the latest upper timeframe bar.
    if ((counted > 0) && (QQE_handle != INVALID_HANDLE))
    {
        counted = prev_calculated - PeriodSeconds(UpperTimeframe) / PeriodSeconds(); // Make the indicator redraw all current bars that constitute the upper timeframe bar.
        rec_only_latest_upper_bar = true;
    }
    else
    {
        counted = rates_total - counted - 1;
        if (counted > rates_total - StartBar - 1) counted = rates_total - StartBar - 1;
    }
    
    if (QQE_handle == INVALID_HANDLE)
    {
        if (CopyBuffer(myRSI, 0, 0, counted + 2, Rsi) != counted + 2) return 0;
    
        // Fills "counted" cells of RsiMA with EMA of Rsi.
        CalculateEMA(counted + 1, SF, Rsi, RsiMa);

        for (int i = counted; i >= 0; i--)
        {
            AtrRsi[i] = MathAbs(RsiMa[i + 1] - RsiMa[i]);
        }
    }
    else
    {
        for (int i = counted; i >= 0; i--)
        {
            double buf[1];
            if (rec_only_latest_upper_bar)
                if (Time[i] <  iTime(Symbol(), UpperTimeframe, 0)) continue; // Skip bars older than the upper current bar.
            int n = CopyBuffer(QQE_handle, 0, Time[i], 1, buf);
            if (n == 1) RsiMa[i] = buf[0];
            else return prev_calculated;
        }
    }

    int i = counted + 1;
    double tr = 0, rsi1 = 0;
    
    if (QQE_handle == INVALID_HANDLE)
    {
        // Fills "counted" cells of MaAtrRsi with EMA of AtrRsi.
        CalculateEMA(counted, Wilders_Period, AtrRsi, MaAtrRsi);
        tr = TrLevelSlow[i];
        rsi1 = RsiMa[i];
        CalculateEMA(counted, Wilders_Period, MaAtrRsi, MaMaAtrRsi);
    }

    while (i > 0)
    {
        i--;
        if (QQE_handle == INVALID_HANDLE)
        {
            double rsi0 = RsiMa[i];
            double dar = MaMaAtrRsi[i] * 4.236;
            double dv = tr;
    
            if (rsi0 < tr)
            {
                tr = rsi0 + dar;
                if ((rsi1 < dv) && (tr > dv)) tr = dv;
            }
            else if (rsi0 > tr)
            {
                tr = rsi0 - dar;
                if ((rsi1 > dv) && (tr < dv)) tr = dv;
            }
    
            TrLevelSlow[i] = tr;
            rsi1 = rsi0;
        }
        else
        {
            double buf[1];
            if (rec_only_latest_upper_bar)
                if (Time[i] <  iTime(Symbol(), UpperTimeframe, 0)) continue; // Skip bars older than the upper current bar.
            int n = CopyBuffer(QQE_handle, 1, Time[i], 1, buf);
            if (n == 1) TrLevelSlow[i] = buf[0];
            else return prev_calculated;
        }

        // Arrows:
        if ((i > 0) || (QQE_handle != INVALID_HANDLE)) // In MTF mode, check as soon as possible.
        {
            // Prepare for multi-timeframe mode.
            int cur_i = i;
            int pre_i = i + 1;
            // Actual MTF (to avoid non-existing signals):
            if ((QQE_handle != INVALID_HANDLE) && (i < PeriodSeconds(UpperTimeframe) / PeriodSeconds())) // Can safely skip this step if processing old bars.
            {
                // Find the bar that corresponds to the upper timeframe's latest finished bar.
                int customIndex = iBarShift(Symbol(), UpperTimeframe, Time[cur_i]);
                cur_i++;
                while ((cur_i < rates_total) && (iBarShift(Symbol(), UpperTimeframe, Time[cur_i]) == customIndex))
                {
                    cur_i++;
                }
                if (cur_i == rates_total) return prev_calculated;
                // Find the bar that corresponds to the upper timeframe's pre-latest finished bar.
                customIndex = iBarShift(Symbol(), UpperTimeframe, Time[cur_i]);
                pre_i = cur_i + 1;
                while ((pre_i < rates_total) && (iBarShift(Symbol(), UpperTimeframe, Time[pre_i])) == customIndex)
                {
                    pre_i++;
                }
                if (pre_i == rates_total) return prev_calculated;
                cur_i = pre_i - 1; // Use oldest lower timeframe bar inside that upper timeframe bar.
            }
            
            if (ArrowsOnCrossover)
            {
                string name = ObjectPrefix + "CArrow" + TimeToString(Time[cur_i]);
                if ((RsiMa[pre_i] < TrLevelSlow[pre_i]) && (RsiMa[cur_i] > TrLevelSlow[cur_i]))
                {
                    ObjectCreate(ChartID(), name, OBJ_ARROW_THUMB_UP, 0, Time[cur_i], Low[cur_i] - 1 * _Point);
                    ObjectSetInteger(ChartID(), name, OBJPROP_COLOR, LevelUpArrow);
                    ObjectSetInteger(ChartID(), name, OBJPROP_ANCHOR, ANCHOR_TOP);
                    ObjectSetInteger(ChartID(), name, OBJPROP_WIDTH, 5);
                }
                else if ((RsiMa[pre_i] > TrLevelSlow[pre_i]) && (RsiMa[cur_i] < TrLevelSlow[cur_i]))
                {
                    ObjectCreate(ChartID(), name, OBJ_ARROW_THUMB_DOWN, 0, Time[cur_i], High[cur_i] + 1 * _Point);
                    ObjectSetInteger(ChartID(), name, OBJPROP_COLOR, LevelDnArrow);
                    ObjectSetInteger(ChartID(), name, OBJPROP_ANCHOR, ANCHOR_BOTTOM);
                    ObjectSetInteger(ChartID(), name, OBJPROP_WIDTH, 5);
                }
            }
            if (ArrowsOnLevel)
            {
                string name = ObjectPrefix + "LArrow" + TimeToString(Time[cur_i]);
                if ((RsiMa[pre_i] < AlertLevel) && (RsiMa[cur_i] > AlertLevel))
                {
                    ObjectCreate(ChartID(), name, OBJ_ARROW_UP, 0, Time[cur_i], Low[cur_i] - 1 * _Point);
                    ObjectSetInteger(ChartID(), name, OBJPROP_COLOR, LevelUpArrow);
                    ObjectSetInteger(ChartID(), name, OBJPROP_ANCHOR, ANCHOR_TOP);
                    ObjectSetInteger(ChartID(), name, OBJPROP_WIDTH, 5);
                }
                else if ((RsiMa[pre_i] > AlertLevel) && (RsiMa[cur_i] < AlertLevel))
                {
                    ObjectCreate(ChartID(), name, OBJ_ARROW_DOWN, 0, Time[cur_i], High[cur_i] + 1 * _Point);
                    ObjectSetInteger(ChartID(), name, OBJPROP_COLOR, LevelDnArrow);
                    ObjectSetInteger(ChartID(), name, OBJPROP_ANCHOR, ANCHOR_BOTTOM);
                    ObjectSetInteger(ChartID(), name, OBJPROP_WIDTH, 5);
                }
            }
        }
    }

    if ((!NativeAlerts) && (!EmailAlerts) && (!NotificationAlerts)) return rates_total;
    if ((!AlertOnCrossover) && (!AlertOnLevel)) return rates_total;

    // Prepare for multi-timeframe mode.
    int pre_i = 2;
    if (QQE_handle != INVALID_HANDLE)
    {
        // Find the bar that corresponds to the upper timeframe's latest finished bar.
        int cnt = 1;
        int customIndex = iBarShift(Symbol(), UpperTimeframe, Time[0]);
        while ((cnt < rates_total) && (iBarShift(Symbol(), UpperTimeframe, Time[cnt]) == customIndex))
        {
            cnt++;
        }
        i = cnt;
        // Find the bar that corresponds to the upper timeframe's pre-latest finished bar.
        customIndex = iBarShift(Symbol(), UpperTimeframe, Time[cnt]);
        cnt++;
        while ((cnt < rates_total) && (iBarShift(Symbol(), UpperTimeframe, Time[cnt]) == customIndex))
        {
            cnt++;
        }
        pre_i = cnt;
    }
    else i = 1; // Non-MTF.
    
    if (AlertOnLevel)
    {
        if ((LastAlertTimeLevel > 0) && (((RsiMa[pre_i] < AlertLevel) && (RsiMa[i] > AlertLevel)) || ((RsiMa[pre_i] > AlertLevel) && (RsiMa[i] < AlertLevel))) && (Time[i - 1] > LastAlertTimeLevel))
        {
            string TextNative = IntegerToString(AlertLevel) + " level Cross ";
            if ((RsiMa[pre_i] > AlertLevel) && (RsiMa[i] < AlertLevel)) TextNative += "Down";
            else TextNative += "Up";
            string Text = "QQE " + Symbol() + ", TF: " + TimeframeToString((ENUM_TIMEFRAMES)Period()) + " " + TextNative;
            DoAlerts(Text, TextNative);
            LastAlertTimeLevel = Time[i - 1];
        }
    }

    if (AlertOnCrossover)
    {
        if ((LastAlertTimeCross > 0) && (((RsiMa[pre_i] < TrLevelSlow[pre_i]) && (RsiMa[i] > TrLevelSlow[i])) || ((RsiMa[pre_i] > TrLevelSlow[pre_i]) && (RsiMa[i] < TrLevelSlow[i]))) && (Time[i - 1] > LastAlertTimeCross))
        {
            string TextNative = "RSI MA crossed Smoothed Line from ";
            if ((RsiMa[pre_i] > TrLevelSlow[pre_i]) && (RsiMa[i] < TrLevelSlow[i])) TextNative += "above.";
            else TextNative += "below.";
            string Text = "QQE " + Symbol() + ", TF: " + TimeframeToString((ENUM_TIMEFRAMES)Period()) + " " + TextNative;
            DoAlerts(Text, TextNative);
            LastAlertTimeCross = Time[i - 1];
        }
    }

    if (LastAlertTimeLevel == 0) LastAlertTimeLevel = Time[0];
    if (LastAlertTimeCross == 0) LastAlertTimeCross = Time[0];

    return rates_total;
}

void DoAlerts(string Text, string TextNative)
{
    if (NativeAlerts) Alert(TextNative);
    if (EmailAlerts) SendMail(Text, Text);
    if (NotificationAlerts) SendNotification(Text);
}

string TimeframeToString(ENUM_TIMEFRAMES P)
{
    return StringSubstr(EnumToString(P), 7);
}

//+------------------------------------------------------------------+
//|  Exponential Moving Average                                      |
//|  Fills the buffer array with EMA values.                         |
//+------------------------------------------------------------------+
void CalculateEMA(int begin, int period, const double &price[], double &result[])
{
    double SmoothFactor = 2.0 / (1.0 + period);

    for (int i = begin; i >= 0; i--)
    {
        if (price[i] == EMPTY_VALUE) result[i] = 0;
        else result[i] = price[i] * SmoothFactor + result[i + 1] * (1.0 - SmoothFactor);
    }
}
//+------------------------------------------------------------------+