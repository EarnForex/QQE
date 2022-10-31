// -------------------------------------------------------------------------------
//   
// QQE - Qualitative Quantitative Estimation.
// Calculated as two indicators:
//  1) MA on RSI
//  2) Difference of MA on RSI and MA of MA of ATR of MA of RSI
// The signal for buy is when blue line crosses level 50 from below after crossing the yellow line from below.
// The signal for sell is when blue line crosses level 50 from above after crossing the yellow line from above.
// 
// Version 1.03
// Copyright 2010-2022, EarnForex.com
// https://www.earnforex.com/metatrader-indicators/QQE/
// -------------------------------------------------------------------------------
using System;
using cAlgo.API;
using cAlgo.API.Indicators;

namespace cAlgo.Indicators
{
    [Levels(50)]
    [Indicator(TimeZone = TimeZones.UTC, AccessRights = AccessRights.None)]
    public class QQE : Indicator
    {
        public enum ENUM_CANDLE_TO_CHECK
        {
            Current,
            Previous
        }
        
        [Parameter(DefaultValue = 5, MinValue = 1)]
        public int SF { get; set; }

        [Parameter(DefaultValue = false)]
        public bool AlertOnCrossover { get; set; }

        [Parameter(DefaultValue = false)]
        public bool AlertOnLevel { get; set; }

        [Parameter(DefaultValue = 50, MinValue = 1, MaxValue = 99)]
        public int AlertLevel { get; set; }

        [Parameter(DefaultValue = true)]
        public bool ArrowsOnCrossover { get; set; }
        
        [Parameter(DefaultValue = "Green")]
        public string CrossoverUpArrow { get; set; }

        [Parameter(DefaultValue = "Red")]
        public string CrossoverDnArrow { get; set; }

        [Parameter(DefaultValue = true)]
        public bool ArrowsOnLevel { get; set; }
        
        [Parameter(DefaultValue = "Green")]
        public string LevelUpArrow { get; set; }

        [Parameter(DefaultValue = "Red")]
        public string LevelDnArrow { get; set; }

        [Parameter("Enable email alerts", DefaultValue = false)]
        public bool EnableEmailAlerts { get; set; }

        [Parameter("AlertEmail: Email From", DefaultValue = "")]
        public string AlertEmailFrom { get; set; }

        [Parameter("AlertEmail: Email To", DefaultValue = "")]
        public string AlertEmailTo { get; set; }

        [Parameter("Upper timeframe")]
        public TimeFrame UpperTimeframe { get; set; }

        [Parameter(DefaultValue = "QQE-")]
        public string ObjectPrefix { get; set; }

        [Output("RSI MA", LineColor = "DodgerBlue", Thickness = 2)]
        public IndicatorDataSeries RsiMa { get; set; }

        [Output("Smoothed", LineColor = "Yellow")]
        public IndicatorDataSeries TrLevelSlow { get; set; }

        private IndicatorDataSeries AtrRsi;
        private IndicatorDataSeries TrLevelSlow_;
        private IndicatorDataSeries MaAtrRsi_, MaAtrRsi_Wilders_;
        private RelativeStrengthIndex Rsi_;
        private MovingAverage RsiMa_;
        
        private bool UseUpperTimeFrame;

        private Bars customBars;

        private const int RSI_Period = 14;
        private int Wilders_Period;
        private double Wilders_Multiplier;
        
        private int Is_Initialized_MaAtrRsi = -1;
        private int Is_Initialized_MaAtrRsi_Wilders = -1;
        
        private int prev_index = -1;
        private int CI_zero = 0;

        private DateTime LastAlertTimeCross, LastAlertTimeLevel, unix_epoch;
        
        protected override void Initialize()
        {
            Wilders_Period = RSI_Period * 2 - 1;
            Wilders_Multiplier = 2.0 / (Wilders_Period + 1.0);
            
            if (UpperTimeframe <= TimeFrame)
            {
                Print("UpperTimeframe <= current timeframe. Ignored.");
                UseUpperTimeFrame = false;
                customBars = Bars;
            }
            else
            {
                UseUpperTimeFrame = true;
                customBars = MarketData.GetBars(UpperTimeframe);
            }
            
            Rsi_ = Indicators.RelativeStrengthIndex(customBars.ClosePrices, RSI_Period);
            RsiMa_ = Indicators.MovingAverage(Rsi_.Result, SF, MovingAverageType.Exponential);
            AtrRsi = CreateDataSeries();
            MaAtrRsi_ = CreateDataSeries();
            MaAtrRsi_Wilders_ = CreateDataSeries();
            TrLevelSlow_ = CreateDataSeries();
            
            unix_epoch = new DateTime(1970, 1, 1, 0, 0, 0);
            LastAlertTimeCross = unix_epoch;
            LastAlertTimeLevel = unix_epoch;
        }
        
        protected override void OnDestroy()
        {
            if ((ArrowsOnLevel) || (ArrowsOnCrossover))
            {
                var icons = Chart.FindAllObjects(ChartObjectType.Icon);
                for (int i = icons.Length - 1; i >= 0; i--)
                {
                    if (icons[i].Name.StartsWith(ObjectPrefix))
                        Chart.RemoveObject(icons[i].Name);
                }
            }
        }
        
        public override void Calculate(int index)
        {
            int customIndex = index;
            int cnt = 0; // How many bars of the current timeframe should be recalculated.
            if (UseUpperTimeFrame)
            {
                customIndex = customBars.OpenTimes.GetIndexByTime(Bars.OpenTimes[index]);
                if (index == 0) CI_zero = customIndex; // customIndex at zero. Because an upper timeframe index may start from non-zero value.
                if (customIndex <= CI_zero + SF) return; // Too early to calculate anything.
                // Find how many current timeframe bars should be recalculated:
                while (customBars.OpenTimes.GetIndexByTime(Bars.OpenTimes[index - cnt]) == customIndex)
                {
                    cnt++;
                }
            }
            else
            {
                cnt = 1; // Non-MTF.
                if (customIndex <= SF) return; // Too early to calculate anything.
            }
            
          
            RsiMa[index] = RsiMa_.Result[customIndex];
            
            AtrRsi[customIndex] = Math.Abs(RsiMa_.Result[customIndex - 1] - RsiMa_.Result[customIndex]);
          
            if (customIndex <= CI_zero + SF + Wilders_Period + 1) return; // Too early to calculate MaAtrRsi.

            if (Is_Initialized_MaAtrRsi == -1)
            {
                // Simple average for the first value.
                MaAtrRsi_[customIndex] = GetAverage(AtrRsi, customIndex, Wilders_Period);
                Is_Initialized_MaAtrRsi = customIndex;
            }
            else if (Is_Initialized_MaAtrRsi < customIndex) // On next index.
            {
                // Fail-safe for NaN.
                if (double.IsNaN(MaAtrRsi_[customIndex - 1])) MaAtrRsi_[customIndex] = GetAverage(AtrRsi, customIndex, Wilders_Period);
                // Exponential average formula.
                else MaAtrRsi_[customIndex] = (AtrRsi[customIndex] - MaAtrRsi_[customIndex - 1]) * Wilders_Multiplier + MaAtrRsi_[customIndex - 1];
            }
            
            if (customIndex <= CI_zero + SF + Wilders_Period + Wilders_Period) return; // Too early to calculate MaAtrRsi_Wilders.

            if (Is_Initialized_MaAtrRsi_Wilders == -1)
            {
                // Simple average for the first value.
                MaAtrRsi_Wilders_[customIndex] = GetAverage(MaAtrRsi_, customIndex, Wilders_Period);
                Is_Initialized_MaAtrRsi_Wilders = customIndex;
            }
            else if (Is_Initialized_MaAtrRsi_Wilders < customIndex) // On next index.
            {
                // Fail-safe for NaN.
                if (double.IsNaN(MaAtrRsi_Wilders_[customIndex - 1])) MaAtrRsi_Wilders_[customIndex] = GetAverage(MaAtrRsi_, customIndex, Wilders_Period);
                // Exponential average formula.
                else MaAtrRsi_Wilders_[customIndex] = (MaAtrRsi_[customIndex] - MaAtrRsi_Wilders_[customIndex - 1]) * Wilders_Multiplier + MaAtrRsi_Wilders_[customIndex - 1];
            }

            double rsi1 = RsiMa_.Result[customIndex - 1];
            double rsi0 = RsiMa_.Result[customIndex];
            double dar = MaAtrRsi_Wilders_[customIndex] * 4.236;

            double tr = TrLevelSlow_[customIndex - 1];
            if (double.IsNaN(tr)) tr = 0;
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
            TrLevelSlow_[customIndex] = tr;

            TrLevelSlow[index] = TrLevelSlow_[customIndex];

            int cnt_prev = 2;
            if (UseUpperTimeFrame)
            {
                for (int i = 1; i < cnt; i++)
                {
                    TrLevelSlow[index - i] = TrLevelSlow[index];
                    RsiMa[index - i] = RsiMa[index];
                }
                
                int ci_temp = customBars.OpenTimes.GetIndexByTime(Bars.OpenTimes[index - cnt]); // Latest finished bar.
                // Find pre-latest finished bar.
                cnt_prev = cnt + 1;
                while (customBars.OpenTimes.GetIndexByTime(Bars.OpenTimes[index - cnt_prev]) == ci_temp)
                {
                    cnt_prev++;
                }
            }

            // Arrows
            if (ArrowsOnCrossover)
            {
                if ((RsiMa[index - cnt_prev] < TrLevelSlow[index - cnt_prev]) && (RsiMa[index - cnt] > TrLevelSlow[index - cnt])) // Cross up.
                {
                    Chart.DrawIcon(ObjectPrefix + "C" + Bars.OpenTimes[index - cnt + 1].ToString(), ChartIconType.UpTriangle, index - cnt + 1, Bars.LowPrices[index - cnt + 1], Color.FromName(CrossoverUpArrow));
                }
                else if ((RsiMa[index - cnt_prev] > TrLevelSlow[index - cnt_prev]) && (RsiMa[index - cnt] < TrLevelSlow[index - cnt])) // Cross down.
                {
                    Chart.DrawIcon(ObjectPrefix + "C" + Bars.OpenTimes[index - cnt + 1].ToString(), ChartIconType.DownTriangle, index - cnt + 1, Bars.HighPrices[index - cnt + 1], Color.FromName(CrossoverDnArrow));
                }
            }
            if (ArrowsOnLevel)
            {
                if ((RsiMa[index - cnt_prev] < AlertLevel) && (RsiMa[index - cnt] > AlertLevel))
                {
                    Chart.DrawIcon(ObjectPrefix + "L" + Bars.OpenTimes[index - cnt + 1].ToString(), ChartIconType.UpArrow, index - cnt + 1, Bars.LowPrices[index - cnt + 1], Color.FromName(LevelUpArrow));
                }
                else if ((RsiMa[index - cnt_prev] > AlertLevel) && (RsiMa[index - cnt] < AlertLevel))
                {
                    Chart.DrawIcon(ObjectPrefix + "L" + Bars.OpenTimes[index - cnt + 1].ToString(), ChartIconType.DownArrow, index - cnt + 1, Bars.LowPrices[index - cnt + 1], Color.FromName(LevelDnArrow));
                }
            }

            // Alerts
            if (!EnableEmailAlerts) return; // No need to go further.
            if ((!AlertOnCrossover) && (!AlertOnLevel)) return;

            if (AlertOnLevel)
            {
                if ((LastAlertTimeLevel > unix_epoch) && (((RsiMa[index - cnt_prev] < AlertLevel) && (RsiMa[index - cnt] > AlertLevel)) || ((RsiMa[index - cnt_prev] > AlertLevel) && (RsiMa[index - cnt] < AlertLevel))) && (Bars.OpenTimes[index - cnt] > LastAlertTimeLevel))
                {
                    string Text = "QQE: " + Symbol.Name + " - " + TimeFrame.Name + " - Level Cross Up";
                    if ((RsiMa[index - cnt_prev] > AlertLevel) && (RsiMa[index - cnt] < AlertLevel)) Text = "QQE: " + Symbol.Name + " - " + TimeFrame.Name + " - Level Cross Down";
                    Notifications.SendEmail(AlertEmailFrom, AlertEmailTo, "QQE Alert - " + Symbol.Name + " @ " + TimeFrame.Name, Text);
                    LastAlertTimeLevel = Bars.OpenTimes[index - cnt];
                }
            }
            
            if (AlertOnCrossover)
            {
                if ((LastAlertTimeCross > unix_epoch) && (((RsiMa[index - cnt_prev] < TrLevelSlow[index - cnt_prev]) && (RsiMa[index - cnt] > TrLevelSlow[index - cnt])) || ((RsiMa[index - cnt_prev] > TrLevelSlow[index - cnt_prev]) && (RsiMa[index - cnt] < TrLevelSlow[index - cnt]))) && (Bars.OpenTimes[index - cnt] > LastAlertTimeCross))
                {
                    string Text = "QQE: " + Symbol.Name + " - " + TimeFrame.Name + " - RSI MA crossed Smoothed Line from below.";
                    if ((RsiMa[index - cnt_prev] > TrLevelSlow[index - cnt_prev]) && (RsiMa[index - cnt] < TrLevelSlow[index - cnt])) Text = "QQE: " + Symbol.Name + " - " + TimeFrame.Name + " - RSI MA crossed Smoothed Line from above.";
                    Notifications.SendEmail(AlertEmailFrom, AlertEmailTo, "QQE Alert - " + Symbol.Name + " @ " + TimeFrame.Name, Text);
                    LastAlertTimeCross = Bars.OpenTimes[index - cnt];
                }
            }
            
            if ((LastAlertTimeLevel == unix_epoch) && (prev_index == index)) LastAlertTimeLevel = Bars.OpenTimes.LastValue;
            if ((LastAlertTimeCross == unix_epoch) && (prev_index == index)) LastAlertTimeCross = Bars.OpenTimes.LastValue;
            prev_index = index;
        }
        
        // Simple moving average to seed the first value of the exponential moving average.
        private double GetAverage(DataSeries series, int index, int period)
        {
            var lastIndex = index - period;
            double sum = 0;

            for (var i = index; i > lastIndex; i--)
            {
                sum += series[i];
            }

            return sum / period;
        }
    }
}