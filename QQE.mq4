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
#property strict

#property description "QQE - Qualitative Quantitative Estimation."
#property description "Calculated as two indicators:"
#property description "1) MA on RSI"
#property description "2) Difference of MA on RSI and MA of MA of ATR of MA of RSI"
#property description "The signal for buy is when blue line crosses level 50 from below"
#property description "after crossing the yellow line from below."
#property description "The signal for sell is when blue line crosses level 50 from above"
#property description "after crossing the yellow line from above."

#property indicator_separate_window
#property indicator_buffers 5
#property indicator_plots 2
#property indicator_color1 clrDodgerBlue
#property indicator_width1 2
#property indicator_label1 "RSI MA"
#property indicator_color2 clrYellow
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
datetime LastAlertTime = D'1970.01.01';

// Buffers
double TrLevelSlow[];
double AtrRsi[];
double MaAtrRsi[];
double Rsi[];
double RsiMa[];

void OnInit()
{
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
    counted = Bars - counted - 1;
    if (counted > Bars - StartBar - 1) counted = Bars - StartBar - 1;

    for (int i = counted; i >= 0; i--)
    {
        Rsi[i] = iRSI(NULL, 0, RSI_Period, PRICE_CLOSE, i);
    }
    for (int i = counted; i >= 0; i--)
    {
        RsiMa[i] = iMAOnArray(Rsi, 0, SF, 0, MODE_EMA, i);
        AtrRsi[i] = MathAbs(RsiMa[i + 1] - RsiMa[i]);
    }
    for (int i = counted; i >= 0; i--)
    {
        MaAtrRsi[i] = iMAOnArray(AtrRsi, 0, Wilders_Period, 0, MODE_EMA, i);
    }
    
    int i = counted + 1;
    double tr = TrLevelSlow[i];
    double rsi1 = iMAOnArray(Rsi, 0, SF, 0, MODE_EMA, i);

    while (i > 0)
    {
        i--;
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
        TrLevelSlow[i] = tr;
        rsi1 = rsi0;
    }

    if ((!NativeAlerts) && (!EmailAlerts) && (!NotificationAlerts)) return rates_total;

    if ((((RsiMa[i + 1] < AlertLevel) && (RsiMa[i] > AlertLevel)) || ((RsiMa[i + 1] > AlertLevel) && (RsiMa[i] < AlertLevel))) && (Time[0] > LastAlertTime))
    {
        string base = Symbol() + ", TF: " + TimeframeToString((ENUM_TIMEFRAMES)Period());
        string Subj = base + ", " + IntegerToString(AlertLevel) + " level Cross Up";
        if ((RsiMa[i + 1] > AlertLevel) && (RsiMa[i] < AlertLevel)) Subj = base + " " + IntegerToString(AlertLevel) + " level Cross Down";
        string Msg = Subj + " @ " + TimeToString(TimeLocal(), TIME_SECONDS);
        DoAlerts(Msg, Subj);
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