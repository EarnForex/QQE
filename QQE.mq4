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
#property strict

#property description "QQE - Qualitative Quantitative Estimation."
#property description "Calculated as two indicators:"
#property description "1) MA on RSI"
#property description "2) Difference of MA on RSI and MA of MA of ATR of MA of RSI"
#property description "The signal for buy is when blue line crosses level 50 from below after crossing the yellow line from below."
#property description "The signal for sell is when blue line crosses level 50 from above after crossing the yellow line from above."

#property indicator_separate_window
#property indicator_buffers 5
#property indicator_color1 clrDodgerBlue
#property indicator_width1 2
#property indicator_label1 "RSI MA"
#property indicator_color2 clrYellow
#property indicator_style2 STYLE_DOT
#property indicator_label2 "Smoothed"
#property indicator_type3 DRAW_NONE
#property indicator_type4 DRAW_NONE
#property indicator_type5 DRAW_NONE
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
string IndicatorFileName;

// Buffers:
double TrLevelSlow[];
double AtrRsi[];
double MaAtrRsi[];
double Rsi[];
double RsiMa[];

void OnInit()
{
    LastAlertTimeCross = 0;
    LastAlertTimeLevel = 0;
    Wilders_Period = RSI_Period * 2 - 1;
    StartBar = MathMax(SF, Wilders_Period);

    SetIndexBuffer(0, RsiMa);
    SetIndexDrawBegin(0, StartBar);
    SetIndexBuffer(1, TrLevelSlow);
    SetIndexDrawBegin(1, StartBar);
    SetIndexBuffer(2, AtrRsi);
    SetIndexBuffer(3, MaAtrRsi);
    SetIndexBuffer(4, Rsi);
    IndicatorShortName(StringConcatenate("QQE(", SF, ")"));
    IndicatorSetInteger(INDICATOR_DIGITS, 2);
    
    if (PeriodSeconds(UpperTimeframe) < PeriodSeconds())
    {
        Print("UpperTimeframe should be above the current timeframe.");
        IndicatorFileName = "";
    }
    else if (PeriodSeconds(UpperTimeframe) > PeriodSeconds()) IndicatorFileName = WindowExpertName();
    else IndicatorFileName = "";
}

void OnDeinit(const int reason)
{
    ObjectsDeleteAll(ChartID(), ObjectPrefix);
}

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
    if (Bars <= StartBar) return 0;

    int counted = IndicatorCounted();
    if (counted < 1)
    {
        for (int i = Bars - StartBar; i < Bars; i++)
        {
            TrLevelSlow[i] = 0.0;
            AtrRsi[i] = 0.0;
            MaAtrRsi[i] = 0.0;
            Rsi[i] = 0.0;
            RsiMa[i] = 0.0;
        }
    }
    if ((counted > 0) && (IndicatorFileName != "")) counted -= PeriodSeconds(UpperTimeframe) / PeriodSeconds(); // Make the indicator redraw all current bars that constitute the upper timeframe bar.
    else counted = Bars - counted - 1;
    if (counted > Bars - StartBar - 1) counted = Bars - StartBar - 1;

    if (IndicatorFileName == "")
    {
        for (int i = counted; i >= 0; i--)
        {
            Rsi[i] = iRSI(Symbol(), Period(), RSI_Period, PRICE_CLOSE, i);
        }
    }
    for (int i = counted; i >= 0; i--)
    {
        if (IndicatorFileName == "") RsiMa[i] = iMAOnArray(Rsi, 0, SF, 0, MODE_EMA, i);
        else
        {
            int shift = iBarShift(Symbol(), UpperTimeframe, Time[i]); // Get the upper timeframe shift based on the current timeframe bar's time.
            RsiMa[i] = iCustom(Symbol(), UpperTimeframe, IndicatorFileName, SF, false, false, AlertLevel, false, LevelUpArrow, LevelDnArrow, false, CrossoverUpArrow, CrossoverDnArrow, false, false, false, UpperTimeframe, ObjectPrefix, 0, shift);
        }
        if (IndicatorFileName == "") AtrRsi[i] = MathAbs(RsiMa[i + 1] - RsiMa[i]);
    }
    if (IndicatorFileName == "")
    {
        for (int i = counted; i >= 0; i--)
        {
            MaAtrRsi[i] = iMAOnArray(AtrRsi, 0, Wilders_Period, 0, MODE_EMA, i);
        }
    }
    
    int i = counted + 1;
    double tr = 0, rsi1 = 0;
    
    if (IndicatorFileName == "")
    {
        tr = TrLevelSlow[i];
        rsi1 = iMAOnArray(Rsi, 0, SF, 0, MODE_EMA, i);
    }
    
    while (i > 0)
    {
        i--;
        if (IndicatorFileName == "")
        {
            double rsi0 = iMAOnArray(Rsi, 0, SF, 0, MODE_EMA, i);
            double dar = iMAOnArray(MaAtrRsi, 0, Wilders_Period, 0, MODE_EMA, i) * 4.236;
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
            rsi1 = rsi0;
            TrLevelSlow[i] = tr;
        }
        else
        {
            int shift = iBarShift(Symbol(), UpperTimeframe, Time[i]); // Get the upper timeframe shift based on the current timeframe bar's time.
            TrLevelSlow[i] = iCustom(Symbol(), UpperTimeframe, IndicatorFileName, SF, false, false, AlertLevel, false, LevelUpArrow, LevelDnArrow, false, CrossoverUpArrow, CrossoverDnArrow, false, false, false, UpperTimeframe, ObjectPrefix, 1, shift);
        }
        
        // Arrows:
        if ((i > 0) || (IndicatorFileName != "")) // In MTF mode, check as soon as possible.
        {
            // Prepare for multi-timeframe mode.
            int cur_i = i;
            int pre_i = i + 1;
            // Actual MTF (to avoid non-existing signals):
            if ((IndicatorFileName != "") && (i < PeriodSeconds(UpperTimeframe) / PeriodSeconds())) // Can safely skip this step if processing old bars.
            {
                // Find the bar that corresponds to the upper timeframe's latest finished bar.
                int customIndex = iBarShift(Symbol(), UpperTimeframe, Time[cur_i]);
                cur_i++;
                while (iBarShift(Symbol(), UpperTimeframe, Time[cur_i]) == customIndex)
                {
                    cur_i++;
                }
                // Find the bar that corresponds to the upper timeframe's pre-latest finished bar.
                customIndex = iBarShift(Symbol(), UpperTimeframe, Time[cur_i]);
                pre_i = cur_i + 1;
                while (iBarShift(Symbol(), UpperTimeframe, Time[pre_i]) == customIndex)
                {
                    pre_i++;
                }
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
    if (IndicatorFileName != "")
    {
        // Find the bar that corresponds to the upper timeframe's latest finished bar.
        int cnt = 1;
        int customIndex = iBarShift(Symbol(), UpperTimeframe, Time[0]);
        while (iBarShift(Symbol(), UpperTimeframe, Time[cnt]) == customIndex)
        {
            cnt++;
        }
        i = cnt;
        // Find the bar that corresponds to the upper timeframe's pre-latest finished bar.
        customIndex = iBarShift(Symbol(), UpperTimeframe, Time[cnt]);
        cnt++;
        while (iBarShift(Symbol(), UpperTimeframe, Time[cnt]) == customIndex)
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
            string base = "QQE " + Symbol() + ", TF: " + TimeframeToString((ENUM_TIMEFRAMES)Period());
            string text = base + ", " + IntegerToString(AlertLevel) + " level Cross Up";
            if ((RsiMa[pre_i] > AlertLevel) && (RsiMa[i] < AlertLevel)) text = base + " " + IntegerToString(AlertLevel) + " level Cross Down";
            DoAlerts(text);
            LastAlertTimeLevel = Time[i - 1];
        }
    }
    
    if (AlertOnCrossover)
    {
        if ((LastAlertTimeCross > 0) && (((RsiMa[pre_i] < TrLevelSlow[pre_i]) && (RsiMa[i] > TrLevelSlow[i])) || ((RsiMa[pre_i] > TrLevelSlow[pre_i]) && (RsiMa[i] < TrLevelSlow[i]))) && (Time[i - 1] > LastAlertTimeCross))
        {
            string base = "QQE " + Symbol() + ", TF: " + TimeframeToString((ENUM_TIMEFRAMES)Period());
            string text = base + ", RSI MA crossed Smoothed Line from below.";
            if ((RsiMa[pre_i] > TrLevelSlow[pre_i]) && (RsiMa[i] < TrLevelSlow[i])) text = base + ", RSI MA crossed Smoothed Line from above.";
            DoAlerts(text);
            LastAlertTimeCross = Time[i - 1];
        }
    }
    
    if (LastAlertTimeLevel == 0) LastAlertTimeLevel = Time[0];
    if (LastAlertTimeCross == 0) LastAlertTimeCross = Time[0];
    
    return rates_total;
}

void DoAlerts(const string msgText)
{
    if (NativeAlerts) Alert(msgText);
    if (EmailAlerts) SendMail(msgText, msgText);
    if (NotificationAlerts) SendNotification(msgText);
}

string TimeframeToString(ENUM_TIMEFRAMES P)
{
    return StringSubstr(EnumToString(P), 7);
}
//+------------------------------------------------------------------+