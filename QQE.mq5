//+------------------------------------------------------------------+
//|                                                          QQE.mq5 |
//|                                 Copyright © 2010-2022, EarnForex |
//|                                        https://www.earnforex.com |
//|                             Based on version by Tim Hyder (2008) |
//|                         Based on version by Roman Ignatov (2006) |
//+------------------------------------------------------------------+
#property copyright "www.EarnForex.com, 2010-2022"
#property link      "https://www.earnforex.com/metatrader-indicators/QQE/"
#property version   "1.02"

#property description "QQE - Qualitative Quantitative Estimation."
#property description "Calculated as two indicators:"
#property description "1) MA on RSI"
#property description "2) Difference of MA on RSI and MA of MA of ATR of MA of RSI"
#property description "The signal for buy is when blue line crosses level 50 from below"
#property description "after crossing the yellow line from below."
#property description "The signal for sell is when blue line crosses level 50 from above"
#property description "after crossing the yellow line from above."

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
input int AlertLevel = 50;
input bool NativeAlerts = false;
input bool EmailAlerts = false;
input bool NotificationAlerts = false;

// Global variables
int RSI_Period = 14;
int Wilders_Period;
int StartBar;
int LastAlertBars = 0;

// Buffers
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

    IndicatorSetString(INDICATOR_SHORTNAME, "QQE(" + IntegerToString(SF) + ")");
    IndicatorSetInteger(INDICATOR_DIGITS, 2);
    
    myRSI = iRSI(NULL, 0, RSI_Period, PRICE_CLOSE);
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
    
    counted = rates_total - counted - 1;
    if (counted > rates_total - StartBar - 1) counted = rates_total - StartBar - 1;
    
    if (CopyBuffer(myRSI, 0, 0, counted + 2, Rsi) != counted + 2) return 0;

    // Fills "counted" cells of RsiMA with EMA of Rsi.
    CalculateEMA(counted + 1, SF, Rsi, RsiMa);

    for (int i = counted; i >= 0; i--)
    {
        AtrRsi[i] = MathAbs(RsiMa[i + 1] - RsiMa[i]);
    }

    // Fills "counted" cells of MaAtrRsi with EMA of AtrRsi.
    CalculateEMA(counted, Wilders_Period, AtrRsi, MaAtrRsi);

    int i = counted + 1;
    double tr = TrLevelSlow[i];
    double rsi1 = RsiMa[i];

    CalculateEMA(counted, Wilders_Period, MaAtrRsi, MaMaAtrRsi);
    while (i > 0)
    {
        i--;
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

    if ((!NativeAlerts) && (!EmailAlerts) && (!NotificationAlerts)) return rates_total;

    if ((((RsiMa[i + 1] < AlertLevel) && (RsiMa[i] > AlertLevel)) || ((RsiMa[i + 1] > AlertLevel) && (RsiMa[i] < AlertLevel))) && (LastAlertBars < rates_total))
    {
        string base = Symbol() + ", TF: " + TimeframeToString((ENUM_TIMEFRAMES)Period());
        string Subj = base + ", " + IntegerToString(AlertLevel) + " level Cross Up";
        if ((RsiMa[i + 1] > AlertLevel) && (RsiMa[i] < AlertLevel)) Subj = base + " " +  IntegerToString(AlertLevel) + " level Cross Down";
        string Msg = Subj + " @ " + TimeToString(TimeLocal(), TIME_SECONDS);
        DoAlerts(Msg, Subj);
        LastAlertBars = rates_total;
    }

    return rates_total;
}

void DoAlerts(string msgText, string eMailSub)
{
    if (NativeAlerts) Alert(msgText);
    if (EmailAlerts) SendMail(eMailSub, msgText);
    if (NotificationAlerts) SendNotification(msgText);
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