//+------------------------------------------------------------------+
//| EURUSD_M15_Upcomers25K_Thunderbolt.mq5                           |
//| Rule-based EURUSD M15 Expert Advisor                             |
//| Attach to your broker's EURUSD chart (suffixes are supported).   |
//+------------------------------------------------------------------+
#property strict
#property version   "2.18"
#property description "EURUSD M15 EA configured for Upcomers $25K Thunderbolt 1-Step challenge. V2.17 trade forensics."

#include <Trade/Trade.mqh>

CTrade trade;

#define SIGNAL_TIMEFRAME PERIOD_M15

//--------------------------- Inputs ---------------------------------
input group "Strategy"
input int      FastEMA              = 20;
input int      SlowEMA              = 50;
input int      RSIPeriod            = 14;
input int      ATRPeriod            = 14;
input int      BreakoutLookback     = 20;
input bool     EnablePullbacks      = false;
input bool     EnableBreakouts      = true;
input double   BuyRSIMin            = 52.0;
input double   SellRSIMax           = 48.0;
input double   MinBodyATR           = 0.18;   // minimum signal-candle body as ATR fraction
input double   PullbackTouchATR     = 0.20;   // EMA20 proximity as ATR fraction
input double   BreakoutBufferATR    = 0.05;   // breakout clearance beyond range
input double   BreakoutMaxExtensionATR = 0.60; // maximum extension of breakout candle
input bool     RequireBreakoutRetest   = true; // wait for next closed M15 candle to retest broken level
input double   RetestTouchATR          = 0.25; // V2.15: slightly deeper retest tolerance
input double   RetestCloseBufferATR    = 0.02; // confirmation close back beyond broken level
input double   PullbackMaxPenetrationATR = 0.35; // reject deep EMA20 penetrations
input double   PullbackRSIBuffer       = 3.0;    // pullbacks need RSI >=55 buy / <=45 sell with defaults
input double   PullbackMinADX          = 22.0;   // stronger trend required specifically for pullbacks
input double   PullbackMinEfficiency   = 0.34;   // reject choppy pullback environments
input double   PullbackCloseBeyondEMAATR = 0.08; // confirmation close beyond EMA20
input double   PullbackSlowEMABufferATR  = 0.15; // keep pullback away from EMA50
input double   PullbackCloseLocationMin  = 0.65; // buy closes in top 35%; sell in bottom 35%
input double   MinEMAGapATR         = 0.10;   // avoid flat/choppy EMA conditions
input double   MaxSignalRangeATR    = 1.60;   // avoid oversized signal candles
input bool     EnableH1TrendFilter  = true;
input int      H1FastEMA            = 20;
input int      H1SlowEMA            = 50;
input bool     EnableStrictH1Regime = true;
input double   H1MinEMAGapATR       = 0.08;   // require meaningful H1 EMA separation
input bool     EnableH1Persistence  = true;
input int      H1PersistenceBars    = 3;      // require H1 trend alignment across closed H1 bars
input bool     EnableADXFilter      = true;
input int      ADXPeriod            = 14;
input double   MinADX               = 18.0;
input double   ADXDeadZoneLow       = 25.0;
input double   ADXDeadZoneHigh      = 30.0;
input bool     RequireADXRising     = true;   // reject fading trend strength
input double   MinADXChange         = 0.0;    // ADX(1)-ADX(2) must be at least this value
input bool     EnableEfficiencyFilter = true;
input int      EfficiencyLookback   = 12;     // M15 closed bars
input double   MinEfficiencyRatio   = 0.28;   // 0=chop, 1=straight-line movement
input bool     EnforceEURUSDSymbol  = true;   // accepts broker prefixes/suffixes containing EURUSD

input group "Upcomers $25K Thunderbolt"
input double   ChallengeStartBalance       = 25000.0;
input double   ChallengeProfitTargetPct    = 5.0;   // official challenge target
input double   OfficialDailyDDPct          = 3.0;   // Upcomers official daily DD
input double   DynamicShieldPct            = 6.0;   // official equity high-water shield
input double   ShieldSafetyBufferPct       = 0.50;  // stop EA before official shield
input bool     StopTradingAtTarget         = true;

input group "Internal Risk"
input double   RiskPercent          = 0.25;   // $62.50 risk at $25K
input double   StopATR              = 1.40;
input double   MinimumStopPips      = 5.0;    // prevents oversized lots in unusually quiet periods
input double   RewardRisk           = 1.80;
input double   BreakEvenAtR         = 1.00;
input double   BreakEvenLockR       = 0.08;
input bool     EnableATRTrail       = true;
input double   TrailStartR          = 1.40;
input double   TrailATR             = 1.10;
input double   TrailMinStepATR      = 0.05;   // minimum SL improvement before modification
input int      TrailModifyMinSeconds = 1; // V2.17: prevent same-second SL modification spam
input double   MaxDailyLossPercent  = 1.00;   // internal stop: ~$250/day
input int      MaxTradesPerDay      = 3;

input group "EURUSD execution filters"
input double   MaxSpreadPips        = 1.5;    // works consistently on 4/5-digit EURUSD quotes
input double   SlippagePips         = 1.0;
input int      SessionStartHour     = 7;      // broker/server time
input int      SessionEndHour       = 20;     // exclusive
input bool     AvoidLateFriday      = true;
input int      FridayStopHour       = 17;
input ulong    MagicNumber          = 26081115;

input group "Diagnostics"
input bool     PrintSignals         = true;
input bool     PrintDiagnosticSummary = true;
input bool     EnableTradeForensics   = true;
input bool     PrintForensicSummary   = true;

//------------------------- Indicator handles -------------------------
int hFastEMA = INVALID_HANDLE;
int hSlowEMA = INVALID_HANDLE;
int hRSI     = INVALID_HANDLE;
int hATR     = INVALID_HANDLE;
int hADX     = INVALID_HANDLE;
int hH1Fast  = INVALID_HANDLE;
int hH1Slow  = INVALID_HANDLE;
int hH1ATR   = INVALID_HANDLE;

//----------------------------- State --------------------------------
datetime lastSLModifyTime = 0;
datetime lastBarTime = 0;
int      dayKey = -1;
double   dayStartEquity = 0.0;
int      tradesToday = 0;
double   equityHighWater = 0.0;
string   hwmGlobalKey = "";
string   dayKeyGlobalKey = "";
string   dayEquityGlobalKey = "";
string   dayTradesGlobalKey = "";

//---------------------- V2.18 diagnostic counters -------------------
long diagBarsEvaluated          = 0;
long diagChallengeGuardReject   = 0;
long diagDailyDDReject          = 0;
long diagShieldReject           = 0;
long diagSessionReject          = 0;
long diagDailyLossReject        = 0;
long diagMaxTradesReject        = 0;
long diagSpreadReject           = 0;
long diagPositionReject         = 0;
long diagIndicatorReadReject    = 0;
long diagATRReject              = 0;

long diagBodyReject             = 0;
long diagRangeReject            = 0;
long diagEMAGapReject           = 0;
long diagADXReject              = 0;
long diagEfficiencyReject       = 0;
long diagH1Reject               = 0;
long diagNoTrendReject          = 0;

long diagBreakoutBarsChecked    = 0;
long diagBreakCandlePass        = 0;
long diagBreakCandleReject      = 0;
long diagRetestPass             = 0;
long diagRetestReject           = 0;
long diagRSIReject              = 0;
long diagFinalBuySignals        = 0;
long diagFinalSellSignals       = 0;
long diagTradesSubmitted        = 0;
long diagPullbackBarsChecked      = 0;
long diagPullbackTouchReject       = 0;
long diagPullbackDepthReject       = 0;
long diagPullbackCandleReject      = 0;
long diagPullbackRSIReject         = 0;
long diagPullbackADXReject         = 0;
long diagPullbackEfficiencyReject  = 0;
long diagPullbackCloseReject       = 0;
long diagPullbackPass              = 0;
long diagPullbackTradesSubmitted   = 0;
long diagBreakoutTradesSubmitted   = 0;
//------------------------- V2.18 trade forensics --------------------

struct ForensicStat
{
   long   trades;
   long   wins;
   double pnl;
   double sumR;
};

struct ActiveForensicTrade
{
   bool     active;
   ulong    positionId;
   datetime entryTime;

   string   setup;
   int      direction; // 1 = BUY, -1 = SELL

   double   entryPrice;
   double   initialSL;
   double   initialTP;
   double   initialRiskMoney;

   double   rsi;
   double   adx;
   double   er;

   int      entryHour;
};

ActiveForensicTrade forensicActive;

ForensicStat forensicSetup[2];       // 0 pullback, 1 breakout
ForensicStat forensicDirection[2];   // 0 sell, 1 buy
ForensicStat forensicRSI[6];
ForensicStat forensicADX[5];
ForensicStat forensicER[5];
ForensicStat forensicHour[24];

long forensicClosedTrades = 0;

void AddForensicStat(ForensicStat &s,
                     double pnl,
                     double resultR)
{
   s.trades++;

   if(pnl > 0.0)
      s.wins++;

   s.pnl  += pnl;
   s.sumR += resultR;
}

void PrintOneForensicStat(string label,
                          ForensicStat &s)
{
   if(s.trades <= 0)
   {
      Print(label, ": trades=0");
      return;
   }

   double winRate =
      100.0 * (double)s.wins / (double)s.trades;

   double avgR =
      s.sumR / (double)s.trades;

   PrintFormat(
      "%s: trades=%I64d wins=%I64d WR=%.1f%% PnL=%.2f SumR=%.2f AvgR=%.3f",
      label,
      s.trades,
      s.wins,
      winRate,
      s.pnl,
      s.sumR,
      avgR
   );
}

int RSIBucket(double v)
{
   if(v < 30.0) return 0;
   if(v < 40.0) return 1;
   if(v < 50.0) return 2;
   if(v < 60.0) return 3;
   if(v < 70.0) return 4;

   return 5;
}

int ADXBucket(double v)
{
   if(v < 20.0) return 0;
   if(v < 25.0) return 1;
   if(v < 30.0) return 2;
   if(v < 40.0) return 3;

   return 4;
}

int ERBucket(double v)
{
   if(v < 0.30) return 0;
   if(v < 0.40) return 1;
   if(v < 0.50) return 2;
   if(v < 0.65) return 3;

   return 4;
}

string ExitReasonToString(long reason)
{
   switch((ENUM_DEAL_REASON)reason)
   {
      case DEAL_REASON_SL:
         return "SL";

      case DEAL_REASON_TP:
         return "TP";

      case DEAL_REASON_EXPERT:
         return "EXPERT";

      case DEAL_REASON_CLIENT:
         return "CLIENT";

      case DEAL_REASON_MOBILE:
         return "MOBILE";

      case DEAL_REASON_WEB:
         return "WEB";

      case DEAL_REASON_SO:
         return "STOP_OUT";

      default:
         return "OTHER";
   }
}

double SumPositionNetPnl(ulong positionId,
                         datetime fromTime)
{
   datetime startTime  = fromTime - 86400;
   datetime finishTime = TimeCurrent() + 60;

   if(!HistorySelect(startTime, finishTime))
      return 0.0;

   double total = 0.0;

   int count = HistoryDealsTotal();

   for(int i = 0; i < count; i++)
   {
      ulong dealTicket =
         HistoryDealGetTicket(i);

      if(dealTicket == 0)
         continue;

      ulong dealPositionId =
         (ulong)HistoryDealGetInteger(
            dealTicket,
            DEAL_POSITION_ID
         );

      if(dealPositionId != positionId)
         continue;

      ulong dealMagic =
         (ulong)HistoryDealGetInteger(
            dealTicket,
            DEAL_MAGIC
         );

      if(dealMagic != MagicNumber)
         continue;

      if(HistoryDealGetString(
            dealTicket,
            DEAL_SYMBOL
         ) != _Symbol)
         continue;

      total +=
         HistoryDealGetDouble(
            dealTicket,
            DEAL_PROFIT
         );

      total +=
         HistoryDealGetDouble(
            dealTicket,
            DEAL_COMMISSION
         );

      total +=
         HistoryDealGetDouble(
            dealTicket,
            DEAL_SWAP
         );
   }

   return total;
}

void RegisterForensicTrade(
   string setup,
   int direction,
   double intendedSL,
   double intendedTP,
   double rsi,
   double adx,
   double er
)
{
   if(!EnableTradeForensics)
      return;

   ulong ticket;

   if(!FindOwnPosition(ticket) ||
      !PositionSelectByTicket(ticket))
      return;

   ulong positionId =
      (ulong)PositionGetInteger(
         POSITION_IDENTIFIER
      );

   double entry =
      PositionGetDouble(
         POSITION_PRICE_OPEN
      );

   double volume =
      PositionGetDouble(
         POSITION_VOLUME
      );

   ENUM_ORDER_TYPE orderType =
      direction > 0
      ? ORDER_TYPE_BUY
      : ORDER_TYPE_SELL;

   double riskMoney = 0.0;
   double calc      = 0.0;

   if(OrderCalcProfit(
         orderType,
         _Symbol,
         volume,
         entry,
         intendedSL,
         calc
      ))
   {
      riskMoney = MathAbs(calc);
   }

   if(riskMoney <= 0.0)
   {
      double tickSize =
         SymbolInfoDouble(
            _Symbol,
            SYMBOL_TRADE_TICK_SIZE
         );

      double tickValue =
         SymbolInfoDouble(
            _Symbol,
            SYMBOL_TRADE_TICK_VALUE_LOSS
         );

      if(tickValue <= 0.0)
      {
         tickValue =
            SymbolInfoDouble(
               _Symbol,
               SYMBOL_TRADE_TICK_VALUE
            );
      }

      if(tickSize > 0.0 &&
         tickValue > 0.0)
      {
         riskMoney =
            (
               MathAbs(
                  entry - intendedSL
               ) /
               tickSize
            )
            *
            tickValue
            *
            volume;
      }
   }

   MqlDateTime tm;

   TimeToStruct(
      TimeTradeServer(),
      tm
   );

   forensicActive.active =
      true;

   forensicActive.positionId =
      positionId;

   forensicActive.entryTime =
      TimeTradeServer();

   forensicActive.setup =
      setup;

   forensicActive.direction =
      direction;

   forensicActive.entryPrice =
      entry;

   forensicActive.initialSL =
      intendedSL;

   forensicActive.initialTP =
      intendedTP;

   forensicActive.initialRiskMoney =
      riskMoney;

   forensicActive.rsi =
      rsi;

   forensicActive.adx =
      adx;

   forensicActive.er =
      er;

   forensicActive.entryHour =
      tm.hour;

   PrintFormat(
      "FORENSIC OPEN posID=%I64u setup=%s dir=%s entry=%.*f SL=%.*f TP=%.*f risk$=%.2f RSI=%.1f ADX=%.1f ER=%.2f hour=%d",
      positionId,
      setup,
      direction > 0 ? "BUY" : "SELL",
      _Digits,
      entry,
      _Digits,
      intendedSL,
      _Digits,
      intendedTP,
      riskMoney,
      rsi,
      adx,
      er,
      tm.hour
   );
}

void FinalizeForensicTrade(
   ulong closingDeal
)
{
   if(!EnableTradeForensics ||
      !forensicActive.active)
      return;

   if(!HistoryDealSelect(
         closingDeal
      ))
      return;

   ulong positionId =
      (ulong)HistoryDealGetInteger(
         closingDeal,
         DEAL_POSITION_ID
      );

   if(positionId !=
      forensicActive.positionId)
      return;

   double pnl =
      SumPositionNetPnl(
         positionId,
         forensicActive.entryTime
      );

   double resultR = 0.0;

   if(forensicActive.initialRiskMoney >
      0.0)
   {
      resultR =
         pnl /
         forensicActive.initialRiskMoney;
   }

   long reason =
      HistoryDealGetInteger(
         closingDeal,
         DEAL_REASON
      );

   string exitReason =
      ExitReasonToString(reason);

   int setupIndex =
      StringFind(
         forensicActive.setup,
         "breakout"
      ) >= 0
      ? 1
      : 0;

   int directionIndex =
      forensicActive.direction > 0
      ? 1
      : 0;

   int rsiIndex =
      RSIBucket(
         forensicActive.rsi
      );

   int adxIndex =
      ADXBucket(
         forensicActive.adx
      );

   int erIndex =
      ERBucket(
         forensicActive.er
      );

   int hourIndex =
      MathMax(
         0,
         MathMin(
            23,
            forensicActive.entryHour
         )
      );

   AddForensicStat(
      forensicSetup[setupIndex],
      pnl,
      resultR
   );

   AddForensicStat(
      forensicDirection[directionIndex],
      pnl,
      resultR
   );

   AddForensicStat(
      forensicRSI[rsiIndex],
      pnl,
      resultR
   );

   AddForensicStat(
      forensicADX[adxIndex],
      pnl,
      resultR
   );

   AddForensicStat(
      forensicER[erIndex],
      pnl,
      resultR
   );

   AddForensicStat(
      forensicHour[hourIndex],
      pnl,
      resultR
   );

   forensicClosedTrades++;

   PrintFormat(
      "FORENSIC CLOSE posID=%I64u setup=%s dir=%s reason=%s pnl=%.2f R=%.3f entryRSI=%.1f ADX=%.1f ER=%.2f hour=%d",
      positionId,
      forensicActive.setup,
      forensicActive.direction > 0
         ? "BUY"
         : "SELL",
      exitReason,
      pnl,
      resultR,
      forensicActive.rsi,
      forensicActive.adx,
      forensicActive.er,
      forensicActive.entryHour
   );

   forensicActive.active = false;

   lastSLModifyTime = 0;
}

void PrintForensics()
{
   if(!EnableTradeForensics ||
      !PrintForensicSummary)
      return;

   Print(
      "================ V2.17 TRADE FORENSICS ==================="
   );

   PrintFormat(
      "Closed trades captured: %I64d",
      forensicClosedTrades
   );

   Print(
      "-----------------------------------------------------------"
   );

   PrintOneForensicStat(
      "SETUP Pullback",
      forensicSetup[0]
   );

   PrintOneForensicStat(
      "SETUP Breakout",
      forensicSetup[1]
   );

   Print(
      "-----------------------------------------------------------"
   );

   PrintOneForensicStat(
      "DIR SELL",
      forensicDirection[0]
   );

   PrintOneForensicStat(
      "DIR BUY",
      forensicDirection[1]
   );

   Print(
      "-----------------------------------------------------------"
   );

   PrintOneForensicStat(
      "RSI <30",
      forensicRSI[0]
   );

   PrintOneForensicStat(
      "RSI 30-40",
      forensicRSI[1]
   );

   PrintOneForensicStat(
      "RSI 40-50",
      forensicRSI[2]
   );

   PrintOneForensicStat(
      "RSI 50-60",
      forensicRSI[3]
   );

   PrintOneForensicStat(
      "RSI 60-70",
      forensicRSI[4]
   );

   PrintOneForensicStat(
      "RSI >=70",
      forensicRSI[5]
   );

   Print(
      "-----------------------------------------------------------"
   );

   PrintOneForensicStat(
      "ADX <20",
      forensicADX[0]
   );

   PrintOneForensicStat(
      "ADX 20-25",
      forensicADX[1]
   );

   PrintOneForensicStat(
      "ADX 25-30",
      forensicADX[2]
   );

   PrintOneForensicStat(
      "ADX 30-40",
      forensicADX[3]
   );

   PrintOneForensicStat(
      "ADX >=40",
      forensicADX[4]
   );

   Print(
      "-----------------------------------------------------------"
   );

   PrintOneForensicStat(
      "ER <0.30",
      forensicER[0]
   );

   PrintOneForensicStat(
      "ER 0.30-0.40",
      forensicER[1]
   );

   PrintOneForensicStat(
      "ER 0.40-0.50",
      forensicER[2]
   );

   PrintOneForensicStat(
      "ER 0.50-0.65",
      forensicER[3]
   );

   PrintOneForensicStat(
      "ER >=0.65",
      forensicER[4]
   );

   Print(
      "-----------------------------------------------------------"
   );

   for(int h = 0; h < 24; h++)
   {
      if(forensicHour[h].trades > 0)
      {
         PrintOneForensicStat(
            "HOUR " +
            IntegerToString(h),
            forensicHour[h]
         );
      }
   }

   Print(
      "==========================================================="
   );
}

void PrintDiagnostics()
{
   if(!PrintDiagnosticSummary)
      return;

   Print("================ V2.17 DIAGNOSTIC SUMMARY ================");
   PrintFormat("Bars evaluated:                    %I64d", diagBarsEvaluated);
   PrintFormat("Challenge-target guard rejects:   %I64d", diagChallengeGuardReject);
   PrintFormat("Official daily-DD rejects:         %I64d", diagDailyDDReject);
   PrintFormat("Dynamic-shield rejects:            %I64d", diagShieldReject);
   PrintFormat("Session rejects:                   %I64d", diagSessionReject);
   PrintFormat("Internal daily-loss rejects:       %I64d", diagDailyLossReject);
   PrintFormat("Max-trades/day rejects:            %I64d", diagMaxTradesReject);
   PrintFormat("Spread rejects:                    %I64d", diagSpreadReject);
   PrintFormat("Existing-position rejects:         %I64d", diagPositionReject);
   PrintFormat("Indicator-read rejects:            %I64d", diagIndicatorReadReject);
   PrintFormat("Invalid ATR rejects:               %I64d", diagATRReject);
   Print("-----------------------------------------------------------");
   PrintFormat("Signal candle body rejects:        %I64d", diagBodyReject);
   PrintFormat("Signal candle range rejects:       %I64d", diagRangeReject);
   PrintFormat("M15 EMA-gap rejects:               %I64d", diagEMAGapReject);
   PrintFormat("ADX rejects:                       %I64d", diagADXReject);
   PrintFormat("Efficiency/chop rejects:           %I64d", diagEfficiencyReject);
   PrintFormat("H1 regime/persistence rejects:     %I64d", diagH1Reject);
   PrintFormat("No valid M15 trend after filters:  %I64d", diagNoTrendReject);
   Print("-----------------------------------------------------------");
   PrintFormat("Pullback bars checked:             %I64d", diagPullbackBarsChecked);
   PrintFormat("Pullback touch rejects:            %I64d", diagPullbackTouchReject);
   PrintFormat("Pullback depth/EMA50 rejects:      %I64d", diagPullbackDepthReject);
   PrintFormat("Pullback candle rejects:           %I64d", diagPullbackCandleReject);
   PrintFormat("Pullback RSI rejects:              %I64d", diagPullbackRSIReject);
   PrintFormat("Pullback ADX rejects:              %I64d", diagPullbackADXReject);
   PrintFormat("Pullback efficiency rejects:       %I64d", diagPullbackEfficiencyReject);
   PrintFormat("Pullback close-confirm rejects:    %I64d", diagPullbackCloseReject);
   PrintFormat("Pullbacks passed:                  %I64d", diagPullbackPass);
   Print("-----------------------------------------------------------");
   PrintFormat("Breakout bars checked:             %I64d", diagBreakoutBarsChecked);
   PrintFormat("Break candle passed:               %I64d", diagBreakCandlePass);
   PrintFormat("Break candle rejected:             %I64d", diagBreakCandleReject);
   PrintFormat("Retest passed:                     %I64d", diagRetestPass);
   PrintFormat("Retest rejected:                   %I64d", diagRetestReject);
   PrintFormat("RSI rejected after setup:          %I64d", diagRSIReject);
   PrintFormat("Final BUY signals:                 %I64d", diagFinalBuySignals);
   PrintFormat("Final SELL signals:                %I64d", diagFinalSellSignals);
   PrintFormat("Pullback trades submitted:         %I64d", diagPullbackTradesSubmitted);
   PrintFormat("Breakout trades submitted:         %I64d", diagBreakoutTradesSubmitted);
   PrintFormat("Trades submitted successfully:     %I64d", diagTradesSubmitted);
   Print("===========================================================");
}

//+------------------------------------------------------------------+
//| Utility                                                          |
//+------------------------------------------------------------------+
int CurrentDayKey()
{
   // Upcomers CFD daily drawdown is measured 00:00-23:59 UTC.
   MqlDateTime tm;
   TimeToStruct(TimeGMT(), tm);
   return (tm.year * 10000 + tm.mon * 100 + tm.day);
}

bool RunningInTester()
{
   return (MQLInfoInteger(MQL_TESTER) != 0);
}

void PersistDayState()
{
   if(RunningInTester() || dayKeyGlobalKey == "" ||
      dayEquityGlobalKey == "" || dayTradesGlobalKey == "")
      return;

   GlobalVariableSet(dayKeyGlobalKey, (double)dayKey);
   GlobalVariableSet(dayEquityGlobalKey, dayStartEquity);
   GlobalVariableSet(dayTradesGlobalKey, (double)tradesToday);
}


void RestoreDayState()
{
   if(RunningInTester() || dayKeyGlobalKey == "" ||
      dayEquityGlobalKey == "" || dayTradesGlobalKey == "")
      return;

   if(!GlobalVariableCheck(dayKeyGlobalKey) ||
      !GlobalVariableCheck(dayEquityGlobalKey) ||
      !GlobalVariableCheck(dayTradesGlobalKey))
      return;

   int storedDay = (int)GlobalVariableGet(dayKeyGlobalKey);
   double storedEquity = GlobalVariableGet(dayEquityGlobalKey);
   int storedTrades = (int)GlobalVariableGet(dayTradesGlobalKey);

   if(storedDay == CurrentDayKey() && storedEquity > 0.0 && storedTrades >= 0)
   {
      dayKey = storedDay;
      dayStartEquity = storedEquity;
      tradesToday = storedTrades;
   }
}

void ResetDayIfNeeded()
{
   int k = CurrentDayKey();
   if(k != dayKey)
   {
      dayKey = k;
      dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      tradesToday = 0;
      PersistDayState();
      if(PrintSignals)
         Print("New trading day. Start equity=", DoubleToString(dayStartEquity, 2));
   }
}

bool DailyLossHit()
{
   if(dayStartEquity <= 0.0)
      return false;

   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double dd = (dayStartEquity - eq) / dayStartEquity * 100.0;
   return (dd >= MaxDailyLossPercent);
}

void UpdateHighWater()
{
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq > equityHighWater)
   {
      equityHighWater = eq;
      if(hwmGlobalKey != "")
         GlobalVariableSet(hwmGlobalKey, equityHighWater);
   }
}

double OfficialShieldLevel()
{
   // Upcomers shield: 6% below highest equity, capped at starting balance.
   double level = equityHighWater * (1.0 - DynamicShieldPct / 100.0);
   return MathMin(ChallengeStartBalance, level);
}

double InternalShieldFloor()
{
   // Maintain extra room above the official breach line.
   return OfficialShieldLevel() + ChallengeStartBalance * (ShieldSafetyBufferPct / 100.0);
}

bool ChallengeTargetReached()
{
   double targetBalance = ChallengeStartBalance * (1.0 + ChallengeProfitTargetPct / 100.0);
   return (AccountInfoDouble(ACCOUNT_BALANCE) >= targetBalance);
}

bool OfficialDailyLimitTooClose()
{
   if(dayStartEquity <= 0.0)
      return false;

   double officialFloor = dayStartEquity - ChallengeStartBalance * (OfficialDailyDDPct / 100.0);
   double internalBuffer = ChallengeStartBalance * (ShieldSafetyBufferPct / 100.0);
   return (AccountInfoDouble(ACCOUNT_EQUITY) <= officialFloor + internalBuffer);
}

bool DynamicShieldTooClose()
{
   UpdateHighWater();
   return (AccountInfoDouble(ACCOUNT_EQUITY) <= InternalShieldFloor());
}

bool InTradingSession()
{
   MqlDateTime tm;
   TimeToStruct(TimeTradeServer(), tm);

   // Sunday=0, Saturday=6
   if(tm.day_of_week == 0 || tm.day_of_week == 6)
      return false;

   if(AvoidLateFriday && tm.day_of_week == 5 && tm.hour >= FridayStopHour)
      return false;

   if(SessionStartHour == SessionEndHour)
      return true; // 24h

   if(SessionStartHour < SessionEndHour)
      return (tm.hour >= SessionStartHour && tm.hour < SessionEndHour);

   // overnight session, e.g. 22 -> 6
   return (tm.hour >= SessionStartHour || tm.hour < SessionEndHour);
}

bool IsEURUSDSymbol()
{
   string symbolName = _Symbol;
   StringToUpper(symbolName);
   return (StringFind(symbolName, "EURUSD") >= 0);
}

double PipSize()
{
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   // One pip is 10 broker points on fractional 3/5-digit FX quotes.
   if(digits == 3 || digits == 5)
      return point * 10.0;

   return point;
}

int PipsToPoints(double pips)
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double pip = PipSize();
   if(point <= 0.0 || pip <= 0.0 || pips <= 0.0)
      return 0;

   return (int)MathRound(pips * pip / point);
}

double NormalizePrice(double price)
{
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   return NormalizeDouble(price, digits);
}

int VolumeDigits()
{
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step >= 1.0)   return 0;
   if(step >= 0.1)   return 1;
   if(step >= 0.01)  return 2;
   if(step >= 0.001) return 3;
   return 4;
}

double NormalizeVolume(double lots)
{
   double vmin  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double vstep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(vmin <= 0.0 || vmax <= 0.0 || vstep <= 0.0 || lots < vmin)
      return 0.0;

   // Always round down. Never raise a calculated size to the broker minimum.
   lots = MathMin(vmax, lots);
   lots = MathFloor((lots / vstep) + 1e-9) * vstep;
   if(lots < vmin)
      return 0.0;

   return NormalizeDouble(lots, VolumeDigits());
}

double LotsForRisk(ENUM_ORDER_TYPE orderType, double entry, double stop)
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   // Do not increase dollar risk as the challenge account approaches its target.
   double riskBase = MathMin(equity, ChallengeStartBalance);
   double riskMoney = riskBase * (RiskPercent / 100.0);
   double distance = MathAbs(entry - stop);

   if(riskMoney <= 0.0 || distance <= 0.0)
      return 0.0;

   // OrderCalcProfit handles the account currency and the broker's EURUSD
   // contract specification more reliably than hard-coded pip values.
   double oneLotProfit = 0.0;
   if(OrderCalcProfit(orderType, _Symbol, 1.0, entry, stop, oneLotProfit))
   {
      double moneyPerLot = MathAbs(oneLotProfit);
      if(moneyPerLot > 0.0)
         return NormalizeVolume(riskMoney / moneyPerLot);
   }

   // Fallback for brokers that do not provide OrderCalcProfit in the tester.
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);

   if(tickValue <= 0.0)
      tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);

   if(tickSize <= 0.0 || tickValue <= 0.0)
      return 0.0;

   double moneyPerLot = (distance / tickSize) * tickValue;
   if(moneyPerLot <= 0.0)
      return 0.0;

   return NormalizeVolume(riskMoney / moneyPerLot);
}

bool SpreadOK()
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick))
      return false;

   double pip = PipSize();
   if(pip <= 0.0)
      return false;

   double spreadPips = (tick.ask - tick.bid) / pip;
   return (spreadPips <= MaxSpreadPips);
}

bool NewBar()
{
   datetime t = iTime(_Symbol, SIGNAL_TIMEFRAME, 0);
   if(t == 0)
      return false;

   if(t != lastBarTime)
   {
      lastBarTime = t;
      return true;
   }
   return false;
}

bool GetBufferValue(int handle, int buffer, int shift, double &value)
{
   double x[1];
   if(CopyBuffer(handle, buffer, shift, 1, x) != 1)
      return false;
   value = x[0];
   return true;
}

double HighestHigh(int fromShift, int count)
{
   double highest = -DBL_MAX;
   for(int i = fromShift; i < fromShift + count; i++)
   {
      double h = iHigh(_Symbol, SIGNAL_TIMEFRAME, i);
      if(h > highest)
         highest = h;
   }
   return highest;
}

double LowestLow(int fromShift, int count)
{
   double lowest = DBL_MAX;
   for(int i = fromShift; i < fromShift + count; i++)
   {
      double l = iLow(_Symbol, SIGNAL_TIMEFRAME, i);
      if(l < lowest)
         lowest = l;
   }
   return lowest;
}

double MinStopDistancePrice()
{
   long stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   return (double)stopsLevel * point;
}

double MinModifyDistancePrice()
{
   long stopsLevel  = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long freezeLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   long requiredPoints = MathMax(stopsLevel, freezeLevel);
   return ((double)requiredPoints + 1.0) * point;
}

double MinimumInitialStopDistancePrice()
{
   return MathMax(MinStopDistancePrice(), MinimumStopPips * PipSize());
}

// Find this EA's position by symbol + magic. Ticket-based management avoids
// accidentally modifying/closing another EURUSD position on hedging accounts.
bool FindOwnPosition(ulong &ticket)
{
   ticket = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0 || !PositionSelectByTicket(t))
         continue;

      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         (ulong)PositionGetInteger(POSITION_MAGIC) == MagicNumber)
      {
         ticket = t;
         return true;
      }
   }
   return false;
}

bool AnyPositionOnSymbol()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0 || !PositionSelectByTicket(t))
         continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol)
         return true;
   }
   return false;
}

double CurrentDailySafetyFloor()
{
   if(dayStartEquity <= 0.0)
      return 0.0;

   double officialFloor = dayStartEquity - ChallengeStartBalance * (OfficialDailyDDPct / 100.0);
   double internalBuffer = ChallengeStartBalance * (ShieldSafetyBufferPct / 100.0);
   return officialFloor + internalBuffer;
}

bool TradeRiskFitsGuardrails(ENUM_ORDER_TYPE orderType, double lots, double entry, double stop)
{
   double loss = 0.0;
   if(OrderCalcProfit(orderType, _Symbol, lots, entry, stop, loss))
   {
      loss = MathAbs(loss);
   }
   else
   {
      // Tester/broker fallback: derive the expected SL loss from tick size/value.
      double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
      if(tickValue <= 0.0)
         tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);

      if(tickSize <= 0.0 || tickValue <= 0.0)
         return false;

      loss = (MathAbs(entry - stop) / tickSize) * tickValue * lots;
   }

   if(loss <= 0.0)
      return false;

   double projectedEquity = AccountInfoDouble(ACCOUNT_EQUITY) - loss;
   double floor = MathMax(CurrentDailySafetyFloor(), InternalShieldFloor());

   // Leave a small execution allowance for commission/slippage beyond the modelled SL loss.
   double executionAllowance = ChallengeStartBalance * 0.0005; // 0.05% = $12.50 on $25K
   return (projectedEquity > floor + executionAllowance);
}

//+------------------------------------------------------------------+
//| Position management                                              |
//+------------------------------------------------------------------+
void ManagePosition()
{
   ulong ticket;

   if(!FindOwnPosition(ticket) ||
      !PositionSelectByTicket(ticket))
   {
      lastSLModifyTime = 0;
      return;
   }

   long type =
      PositionGetInteger(
         POSITION_TYPE
      );

   double entry =
      PositionGetDouble(
         POSITION_PRICE_OPEN
      );

   double oldSL =
      PositionGetDouble(
         POSITION_SL
      );

   double tp =
      PositionGetDouble(
         POSITION_TP
      );

   double atr;

   if(!GetBufferValue(
         hATR,
         0,
         1,
         atr
      ) ||
      atr <= 0.0)
      return;

   MqlTick tick;

   if(!SymbolInfoTick(
         _Symbol,
         tick
      ))
      return;

   double current =
      type == POSITION_TYPE_BUY
      ? tick.bid
      : tick.ask;

   double initialRisk = 0.0;

   if(tp > 0.0 &&
      RewardRisk > 0.0)
   {
      initialRisk =
         MathAbs(
            tp - entry
         ) /
         RewardRisk;
   }

   if(initialRisk <= 0.0)
      initialRisk =
         StopATR * atr;

   if(initialRisk <= 0.0)
      return;

   double rNow =
      type == POSITION_TYPE_BUY
      ? (current - entry) / initialRisk
      : (entry - current) / initialRisk;

   double newSL =
      oldSL;

   // Break-even
   if(rNow >= BreakEvenAtR)
   {
      double be =
         type == POSITION_TYPE_BUY
         ? entry +
           initialRisk *
           BreakEvenLockR
         : entry -
           initialRisk *
           BreakEvenLockR;

      if(type == POSITION_TYPE_BUY)
      {
         if(oldSL == 0.0 ||
            be > newSL)
         {
            newSL = be;
         }
      }
      else
      {
         if(oldSL == 0.0 ||
            be < newSL)
         {
            newSL = be;
         }
      }
   }

   // ATR trail
   if(EnableATRTrail &&
      rNow >= TrailStartR)
   {
      double trail =
         type == POSITION_TYPE_BUY
         ? current -
           TrailATR *
           atr
         : current +
           TrailATR *
           atr;

      if(type == POSITION_TYPE_BUY)
      {
         if(oldSL == 0.0 ||
            trail > newSL)
         {
            newSL = trail;
         }
      }
      else
      {
         if(oldSL == 0.0 ||
            trail < newSL)
         {
            newSL = trail;
         }
      }
   }

   if(newSL == oldSL ||
      newSL <= 0.0)
      return;

   // V2.17 modification throttle
   if(TrailModifyMinSeconds > 0 &&
      lastSLModifyTime > 0)
   {
      datetime now =
         TimeTradeServer();

      if(
         now -
         lastSLModifyTime
         <
         TrailModifyMinSeconds
      )
      {
         return;
      }
   }

   double minModifyDistance =
      MinModifyDistancePrice();

   double point =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_POINT
      );

   double minImprovement =
      MathMax(
         point * 2.0,
         atr *
         TrailMinStepATR
      );

   if(type ==
      POSITION_TYPE_BUY)
   {
      double highestValidSL =
         tick.bid -
         minModifyDistance;

      newSL =
         MathMin(
            newSL,
            highestValidSL
         );

      if(newSL <= 0.0)
         return;

      if(oldSL > 0.0 &&
         newSL - oldSL <
         minImprovement)
      {
         return;
      }
   }
   else
   {
      double lowestValidSL =
         tick.ask +
         minModifyDistance;

      newSL =
         MathMax(
            newSL,
            lowestValidSL
         );

      if(newSL <= 0.0)
         return;

      if(oldSL > 0.0 &&
         oldSL - newSL <
         minImprovement)
      {
         return;
      }
   }

   newSL =
      NormalizePrice(
         newSL
      );

   // Final broker-distance check after rounding
   if(type ==
      POSITION_TYPE_BUY)
   {
      double maxSL =
         NormalizePrice(
            tick.bid -
            minModifyDistance
         );

      if(newSL > maxSL)
         newSL = maxSL;

      if(oldSL > 0.0 &&
         newSL - oldSL <
         minImprovement)
      {
         return;
      }
   }
   else
   {
      double minSL =
         NormalizePrice(
            tick.ask +
            minModifyDistance
         );

      if(newSL < minSL)
         newSL = minSL;

      if(oldSL > 0.0 &&
         oldSL - newSL <
         minImprovement)
      {
         return;
      }
   }

   if(
      trade.PositionModify(
         ticket,
         newSL,
         tp
      )
   )
   {
      lastSLModifyTime =
         TimeTradeServer();
   }
   else if(PrintSignals)
   {
      Print(
         "PositionModify failed. Retcode=",
         trade.ResultRetcode(),
         " ",
         trade.ResultRetcodeDescription(),
         " requestedSL=",
         DoubleToString(
            newSL,
            _Digits
         )
      );
   }
}

//+------------------------------------------------------------------+
//| Regime-quality helpers                                           |
//+------------------------------------------------------------------+
double EfficiencyRatioM15(int lookback)
{
   if(lookback < 2)
      return 0.0;

   double firstClose = iClose(_Symbol, SIGNAL_TIMEFRAME, 1);
   double lastClose  = iClose(_Symbol, SIGNAL_TIMEFRAME, lookback + 1);
   if(firstClose <= 0.0 || lastClose <= 0.0)
      return 0.0;

   double directionalMove = MathAbs(firstClose - lastClose);
   double path = 0.0;

   for(int i = 1; i <= lookback; i++)
   {
      double cNow  = iClose(_Symbol, SIGNAL_TIMEFRAME, i);
      double cPrev = iClose(_Symbol, SIGNAL_TIMEFRAME, i + 1);
      if(cNow <= 0.0 || cPrev <= 0.0)
         return 0.0;
      path += MathAbs(cNow - cPrev);
   }

   if(path <= 0.0)
      return 0.0;

   return directionalMove / path;
}

bool H1TrendPersistent(bool wantUp)
{
   if(!EnableH1Persistence)
      return true;

   int bars = MathMax(2, H1PersistenceBars);

   for(int shift = 1; shift <= bars; shift++)
   {
      double fast, slow;
      if(!GetBufferValue(hH1Fast, 0, shift, fast)) return false;
      if(!GetBufferValue(hH1Slow, 0, shift, slow)) return false;

      double closeH1 = iClose(_Symbol, PERIOD_H1, shift);
      if(closeH1 <= 0.0)
         return false;

      if(wantUp)
      {
         if(fast <= slow || closeH1 <= fast)
            return false;
      }
      else
      {
         if(fast >= slow || closeH1 >= fast)
            return false;
      }
   }

   return true;
}

//+------------------------------------------------------------------+
//| Signal engine                                                    |
//+------------------------------------------------------------------+
void EvaluateEntries()
{
   if(Bars(_Symbol, SIGNAL_TIMEFRAME) < MathMax(SlowEMA + 20, BreakoutLookback + 20))
      return;

   diagBarsEvaluated++;

   ResetDayIfNeeded();
   UpdateHighWater();

   if(StopTradingAtTarget && ChallengeTargetReached())
   {
      diagChallengeGuardReject++;
      if(PrintSignals)
         Print("Challenge target reached. New entries disabled.");
      return;
   }

   if(OfficialDailyLimitTooClose())
   {
      diagDailyDDReject++;
      if(PrintSignals)
         Print("Upcomers daily-DD safety buffer active. New entries disabled.");
      return;
   }

   if(DynamicShieldTooClose())
   {
      diagShieldReject++;
      if(PrintSignals)
         Print("Dynamic Risk Shield safety buffer active. New entries disabled.");
      return;
   }

   if(!InTradingSession())
   {
      diagSessionReject++;
      return;
   }

   if(DailyLossHit())
   {
      diagDailyLossReject++;
      if(PrintSignals)
         Print("Daily loss guard active.");
      return;
   }

   if(tradesToday >= MaxTradesPerDay)
   {
      diagMaxTradesReject++;
      return;
   }

   if(!SpreadOK())
   {
      diagSpreadReject++;
      return;
   }

   // Deliberately limit EURUSD to one position at a time, including manual/other-EA positions.
   if(AnyPositionOnSymbol())
   {
      diagPositionReject++;
      return;
   }

   double emaFast1, emaFast2, emaSlow1, emaSlow2, rsi1, atr1;
   double adx1 = 100.0, adx2 = 100.0, h1Fast1 = 0.0, h1Fast2 = 0.0, h1Slow1 = 0.0, h1Slow2 = 0.0, h1ATR1 = 0.0;
   if(!GetBufferValue(hFastEMA, 0, 1, emaFast1) ||
      !GetBufferValue(hFastEMA, 0, 2, emaFast2) ||
      !GetBufferValue(hSlowEMA, 0, 1, emaSlow1) ||
      !GetBufferValue(hSlowEMA, 0, 2, emaSlow2) ||
      !GetBufferValue(hRSI,     0, 1, rsi1) ||
      !GetBufferValue(hATR,     0, 1, atr1))
   {
      diagIndicatorReadReject++;
      return;
   }

   if(EnableADXFilter)
   {
      if(!GetBufferValue(hADX, 0, 1, adx1) ||
         !GetBufferValue(hADX, 0, 2, adx2))
      {
         diagIndicatorReadReject++;
         return;
      }
   }
   if(EnableH1TrendFilter)
   {
      if(!GetBufferValue(hH1Fast, 0, 1, h1Fast1) ||
         !GetBufferValue(hH1Fast, 0, 2, h1Fast2) ||
         !GetBufferValue(hH1Slow, 0, 1, h1Slow1) ||
         !GetBufferValue(hH1Slow, 0, 2, h1Slow2) ||
         !GetBufferValue(hH1ATR,  0, 1, h1ATR1))
      {
         diagIndicatorReadReject++;
         return;
      }
   }

   if(atr1 <= 0.0)
   {
      diagATRReject++;
      return;
   }

   double o1 = iOpen(_Symbol, SIGNAL_TIMEFRAME, 1);
   double h1 = iHigh(_Symbol, SIGNAL_TIMEFRAME, 1);
   double l1 = iLow(_Symbol, SIGNAL_TIMEFRAME, 1);
   double c1 = iClose(_Symbol, SIGNAL_TIMEFRAME, 1);

   double body = MathAbs(c1 - o1);
   double range = h1 - l1;
   bool bodyOK = (body >= atr1 * MinBodyATR);
   bool rangeOK = (range > 0.0 && range <= atr1 * MaxSignalRangeATR);
   bool emaGapOK = (MathAbs(emaFast1 - emaSlow1) >= atr1 * MinEMAGapATR);
   bool adxLevelOK = (!EnableADXFilter || adx1 >= MinADX);
   bool adxSlopeOK = (!EnableADXFilter || !RequireADXRising || (adx1 - adx2) >= MinADXChange);
   
   bool adxDeadZoneOK =
   (!EnableADXFilter ||
    adx1 < ADXDeadZoneLow ||
    adx1 >= ADXDeadZoneHigh);

bool adxOK =
   adxLevelOK &&
   adxDeadZoneOK &&
   adxSlopeOK;

   double efficiency = EfficiencyRatioM15(EfficiencyLookback);
   bool efficiencyOK = (!EnableEfficiencyFilter || efficiency >= MinEfficiencyRatio);

   double h1Close1 = iClose(_Symbol, PERIOD_H1, 1);
   bool strictH1Up = (!EnableStrictH1Regime ||
                      (h1ATR1 > 0.0 && h1Fast1 > h1Fast2 && h1Slow1 >= h1Slow2 &&
                       h1Close1 > h1Fast1 &&
                       (h1Fast1 - h1Slow1) >= h1ATR1 * H1MinEMAGapATR));
   bool strictH1Down = (!EnableStrictH1Regime ||
                        (h1ATR1 > 0.0 && h1Fast1 < h1Fast2 && h1Slow1 <= h1Slow2 &&
                         h1Close1 < h1Fast1 &&
                         (h1Slow1 - h1Fast1) >= h1ATR1 * H1MinEMAGapATR));

   bool h1Up = (!EnableH1TrendFilter ||
                (h1Fast1 > h1Slow1 && strictH1Up && H1TrendPersistent(true)));
   bool h1Down = (!EnableH1TrendFilter ||
                  (h1Fast1 < h1Slow1 && strictH1Down && H1TrendPersistent(false)));

   // Independent diagnostics: these counters do not change strategy decisions.
   if(!bodyOK)       diagBodyReject++;
   if(!rangeOK)      diagRangeReject++;
   if(!emaGapOK)     diagEMAGapReject++;
   if(!adxOK)        diagADXReject++;
   if(!efficiencyOK) diagEfficiencyReject++;
   if(EnableH1TrendFilter && !h1Up && !h1Down)
      diagH1Reject++;

   bool upTrend   = (emaFast1 > emaSlow1 && emaFast1 > emaFast2 && emaSlow1 >= emaSlow2 &&
                     emaGapOK && adxOK && efficiencyOK && h1Up);
   bool downTrend = (emaFast1 < emaSlow1 && emaFast1 < emaFast2 && emaSlow1 <= emaSlow2 &&
                     emaGapOK && adxOK && efficiencyOK && h1Down);

   if(!upTrend && !downTrend)
      diagNoTrendReject++;

   bool bullishCandle = (c1 > o1);
   bool bearishCandle = (c1 < o1);

   // V2.16 pullback:
   // Keep the same higher-timeframe trend regime, but require a cleaner
   // EMA20 rejection and stronger momentum before allowing a pullback entry.
   bool buyPullback = false;
   bool sellPullback = false;

   if(EnablePullbacks)
   {
      diagPullbackBarsChecked++;

      bool pullbackTrend = (upTrend || downTrend);

      bool buyTouch =
         upTrend &&
         l1 <= emaFast1 + (atr1 * PullbackTouchATR);

      bool sellTouch =
         downTrend &&
         h1 >= emaFast1 - (atr1 * PullbackTouchATR);

      bool buyDepthOK =
         upTrend &&
         l1 >= emaFast1 - (atr1 * PullbackMaxPenetrationATR) &&
         l1 >= emaSlow1 + (atr1 * PullbackSlowEMABufferATR);

      bool sellDepthOK =
         downTrend &&
         h1 <= emaFast1 + (atr1 * PullbackMaxPenetrationATR) &&
         h1 <= emaSlow1 - (atr1 * PullbackSlowEMABufferATR);

      bool buyCandleOK  = upTrend && bullishCandle && bodyOK && rangeOK;
      bool sellCandleOK = downTrend && bearishCandle && bodyOK && rangeOK;

      double closeLocation = 0.5;
      if(range > 0.0)
         closeLocation = (c1 - l1) / range;

      bool buyCloseLocationOK  = (closeLocation >= PullbackCloseLocationMin);
      bool sellCloseLocationOK = (closeLocation <= (1.0 - PullbackCloseLocationMin));

      bool buyRSIOK  = (rsi1 >= BuyRSIMin + PullbackRSIBuffer);
      bool sellRSIOK = (rsi1 <= SellRSIMax - PullbackRSIBuffer);

      bool pullbackADXOK =
         (!EnableADXFilter ||
          (adx1 >= MathMax(MinADX, PullbackMinADX) &&
           (!RequireADXRising || (adx1 - adx2) >= MinADXChange)));

      bool pullbackEfficiencyOK =
         (!EnableEfficiencyFilter ||
          efficiency >= MathMax(MinEfficiencyRatio, PullbackMinEfficiency));

      bool buyCloseConfirm =
         upTrend &&
         c1 >= emaFast1 + (atr1 * PullbackCloseBeyondEMAATR) &&
         buyCloseLocationOK;

      bool sellCloseConfirm =
         downTrend &&
         c1 <= emaFast1 - (atr1 * PullbackCloseBeyondEMAATR) &&
         sellCloseLocationOK;

      if(pullbackTrend)
      {
         if(!(buyTouch || sellTouch))
            diagPullbackTouchReject++;
         else if(!(buyDepthOK || sellDepthOK))
            diagPullbackDepthReject++;
         else if(!(buyCandleOK || sellCandleOK))
            diagPullbackCandleReject++;
         else if(!(buyRSIOK || sellRSIOK))
            diagPullbackRSIReject++;
         else if(!pullbackADXOK)
            diagPullbackADXReject++;
         else if(!pullbackEfficiencyOK)
            diagPullbackEfficiencyReject++;
         else if(!(buyCloseConfirm || sellCloseConfirm))
            diagPullbackCloseReject++;
      }

      buyPullback =
         buyTouch &&
         buyDepthOK &&
         buyCandleOK &&
         buyRSIOK &&
         pullbackADXOK &&
         pullbackEfficiencyOK &&
         buyCloseConfirm;

      sellPullback =
         sellTouch &&
         sellDepthOK &&
         sellCandleOK &&
         sellRSIOK &&
         pullbackADXOK &&
         pullbackEfficiencyOK &&
         sellCloseConfirm;

      if(buyPullback || sellPullback)
         diagPullbackPass++;
   }

   // Breakout logic.
   // V2.15 uses a two-candle breakout + retest:
   // bar 2 breaks the prior range, then bar 1 retests that level and confirms.
   double priorHigh = HighestHigh(RequireBreakoutRetest ? 3 : 2, BreakoutLookback);
   double priorLow  = LowestLow(RequireBreakoutRetest ? 3 : 2, BreakoutLookback);

   bool buyBreakout = false;
   bool sellBreakout = false;

   if(EnableBreakouts)
   {
      if(RequireBreakoutRetest)
      {
         double o2 = iOpen(_Symbol, SIGNAL_TIMEFRAME, 2);
         double h2 = iHigh(_Symbol, SIGNAL_TIMEFRAME, 2);
         double l2 = iLow(_Symbol, SIGNAL_TIMEFRAME, 2);
         double c2 = iClose(_Symbol, SIGNAL_TIMEFRAME, 2);

         double atr2 = 0.0;
         if(!GetBufferValue(hATR, 0, 2, atr2) || atr2 <= 0.0)
            return;

         double body2 = MathAbs(c2 - o2);
         double range2 = h2 - l2;
         bool breakoutBodyOK = (body2 >= atr2 * MinBodyATR);
         bool breakoutRangeOK = (range2 > 0.0 && range2 <= atr2 * MaxSignalRangeATR);

         bool bullishBreakCandle = (c2 > o2);
         bool bearishBreakCandle = (c2 < o2);

         bool brokeUp =
            bullishBreakCandle &&
            breakoutBodyOK && breakoutRangeOK &&
            c2 > priorHigh + (atr2 * BreakoutBufferATR) &&
            c2 <= priorHigh + (atr2 * BreakoutMaxExtensionATR);

         bool brokeDown =
            bearishBreakCandle &&
            breakoutBodyOK && breakoutRangeOK &&
            c2 < priorLow - (atr2 * BreakoutBufferATR) &&
            c2 >= priorLow - (atr2 * BreakoutMaxExtensionATR);

         // Retest candle must revisit the broken level, then close back on
         // the breakout side. This avoids entering the initial breakout spike.
         bool buyRetest =
            l1 <= priorHigh + (atr1 * RetestTouchATR) &&
            l1 >= priorHigh - (atr1 * RetestTouchATR) &&
            c1 > priorHigh + (atr1 * RetestCloseBufferATR) &&
            c1 > o1;

         bool sellRetest =
            h1 >= priorLow - (atr1 * RetestTouchATR) &&
            h1 <= priorLow + (atr1 * RetestTouchATR) &&
            c1 < priorLow - (atr1 * RetestCloseBufferATR) &&
            c1 < o1;

         diagBreakoutBarsChecked++;

         bool directionalBreak = ((upTrend && brokeUp) || (downTrend && brokeDown));
         if(directionalBreak)
            diagBreakCandlePass++;
         else
            diagBreakCandleReject++;

         bool directionalRetest = ((upTrend && brokeUp && buyRetest) ||
                                   (downTrend && brokeDown && sellRetest));
         if(directionalBreak)
         {
            if(directionalRetest) diagRetestPass++;
            else                  diagRetestReject++;
         }

         if(upTrend && brokeUp && buyRetest && rsi1 < BuyRSIMin)
            diagRSIReject++;
         if(downTrend && brokeDown && sellRetest && rsi1 > SellRSIMax)
            diagRSIReject++;

         buyBreakout =
            upTrend &&
            rsi1 >= BuyRSIMin &&
            bodyOK && rangeOK &&
            brokeUp && buyRetest;

         sellBreakout =
            downTrend &&
            rsi1 <= SellRSIMax &&
            bodyOK && rangeOK &&
            brokeDown && sellRetest;
      }
      else
      {
         buyBreakout =
            upTrend &&
            rsi1 >= BuyRSIMin &&
            bullishCandle &&
            bodyOK && rangeOK &&
            c1 > priorHigh + (atr1 * BreakoutBufferATR) &&
            c1 <= priorHigh + (atr1 * BreakoutMaxExtensionATR);

         sellBreakout =
            downTrend &&
            rsi1 <= SellRSIMax &&
            bearishCandle &&
            bodyOK && rangeOK &&
            c1 < priorLow - (atr1 * BreakoutBufferATR) &&
            c1 >= priorLow - (atr1 * BreakoutMaxExtensionATR);
      }
   }

   bool buySignal  = buyPullback || buyBreakout;
   bool sellSignal = sellPullback || sellBreakout;

   if(buySignal)  diagFinalBuySignals++;
   if(sellSignal) diagFinalSellSignals++;

   // Never act on conflicting signal state.
   if(buySignal == sellSignal)
      return;

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick))
      return;

   double entry, sl, tp, lots;
   double minStop = MinimumInitialStopDistancePrice();

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(PipsToPoints(SlippagePips));
   trade.SetTypeFillingBySymbol(_Symbol);

   if(buySignal)
   {
      entry = tick.ask;
      sl = entry - StopATR * atr1;

      // Put SL below signal candle if that is farther away.
      sl = MathMin(sl, l1 - 0.10 * atr1);
      if(entry - sl < minStop)
         sl = entry - minStop;

      double riskDist = entry - sl;
      tp = entry + riskDist * RewardRisk;

      sl = NormalizePrice(sl);
      tp = NormalizePrice(tp);
      lots = LotsForRisk(ORDER_TYPE_BUY, entry, sl);

      if(lots <= 0.0)
      {
         if(PrintSignals)
            Print("BUY skipped: calculated risk size is below the broker minimum or symbol data is unavailable.");
         return;
      }

      if(!TradeRiskFitsGuardrails(ORDER_TYPE_BUY, lots, entry, sl))
      {
         if(PrintSignals)
            Print("BUY skipped: SL risk would leave too little room above an Upcomers safety floor.");
         return;
      }

      string setup = buyBreakout ? "M15 breakout" : "M15 pullback";

      if(trade.Buy(lots, _Symbol, 0.0, sl, tp, setup))
      {
         diagTradesSubmitted++;
         if(buyBreakout) diagBreakoutTradesSubmitted++;
         else            diagPullbackTradesSubmitted++;
         tradesToday++;
         PersistDayState();
         RegisterForensicTrade(
   setup,
   1,
   sl,
   tp,
   rsi1,
   adx1,
   efficiency
);
         if(PrintSignals)
            Print("BUY ", setup, " lots=", lots, " SL=", sl, " TP=", tp,
                  " RSI=", DoubleToString(rsi1,1),
                  " ADX=", DoubleToString(adx1,1), " ER=", DoubleToString(efficiency,2));
      }
      else if(PrintSignals)
      {
         Print("BUY failed. Retcode=", trade.ResultRetcode(),
               " ", trade.ResultRetcodeDescription());
      }
   }
   else if(sellSignal)
   {
      entry = tick.bid;
      sl = entry + StopATR * atr1;

      sl = MathMax(sl, h1 + 0.10 * atr1);
      if(sl - entry < minStop)
         sl = entry + minStop;

      double riskDist = sl - entry;
      tp = entry - riskDist * RewardRisk;

      sl = NormalizePrice(sl);
      tp = NormalizePrice(tp);
      lots = LotsForRisk(ORDER_TYPE_SELL, entry, sl);

      if(lots <= 0.0)
      {
         if(PrintSignals)
            Print("SELL skipped: calculated risk size is below the broker minimum or symbol data is unavailable.");
         return;
      }

      if(!TradeRiskFitsGuardrails(ORDER_TYPE_SELL, lots, entry, sl))
      {
         if(PrintSignals)
            Print("SELL skipped: SL risk would leave too little room above an Upcomers safety floor.");
         return;
      }

      string setup = sellBreakout ? "M15 breakout" : "M15 pullback";

      if(trade.Sell(lots, _Symbol, 0.0, sl, tp, setup))
      {
         diagTradesSubmitted++;
         if(sellBreakout) diagBreakoutTradesSubmitted++;
         else             diagPullbackTradesSubmitted++;
         tradesToday++;
         PersistDayState();
         RegisterForensicTrade(
   setup,
   -1,
   sl,
   tp,
   rsi1,
   adx1,
   efficiency
);
         if(PrintSignals)
            Print("SELL ", setup, " lots=", lots, " SL=", sl, " TP=", tp,
                  " RSI=", DoubleToString(rsi1,1),
                  " ADX=", DoubleToString(adx1,1), " ER=", DoubleToString(efficiency,2));
      }
      else if(PrintSignals)
      {
         Print("SELL failed. Retcode=", trade.ResultRetcode(),
               " ", trade.ResultRetcodeDescription());
      }
   }
}

//+------------------------------------------------------------------+
//| Lifecycle                                                        |
//+------------------------------------------------------------------+
bool InputsValid()
{
   if(FastEMA <= 0 || SlowEMA <= FastEMA || RSIPeriod <= 0 || ATRPeriod <= 0)
      return false;

   if(BreakoutLookback < 2 || (!EnablePullbacks && !EnableBreakouts))
      return false;

   if(BuyRSIMin < 0.0 || BuyRSIMin > 100.0 ||
      SellRSIMax < 0.0 || SellRSIMax > 100.0)
      return false;

   if(MinBodyATR < 0.0 ||
      PullbackTouchATR < 0.0 ||
      BreakoutBufferATR < 0.0 ||
      BreakoutMaxExtensionATR <= BreakoutBufferATR ||
      RetestTouchATR < 0.0 ||
      RetestCloseBufferATR < 0.0 ||
      PullbackMaxPenetrationATR < 0.0 ||
      PullbackRSIBuffer < 0.0 ||
      PullbackMinADX < 0.0 ||
      PullbackMinEfficiency < 0.0 ||
      PullbackMinEfficiency > 1.0 ||
      PullbackCloseBeyondEMAATR < 0.0 ||
      PullbackSlowEMABufferATR < 0.0 ||
      PullbackCloseLocationMin < 0.5 ||
      PullbackCloseLocationMin > 1.0 ||
      MinEMAGapATR < 0.0 ||
      MaxSignalRangeATR <= 0.0)
      return false;

   if(H1FastEMA <= 0 ||
      H1SlowEMA <= H1FastEMA ||
      ADXPeriod <= 0 ||
      MinADX < 0.0)
      return false;

   if(H1PersistenceBars < 2 ||
      EfficiencyLookback < 2 ||
      MinEfficiencyRatio < 0.0 ||
      MinEfficiencyRatio > 1.0)
      return false;

   if(ChallengeStartBalance <= 0.0 ||
      ChallengeProfitTargetPct <= 0.0 ||
      OfficialDailyDDPct <= 0.0 ||
      DynamicShieldPct <= 0.0 ||
      ShieldSafetyBufferPct < 0.0)
      return false;

   if(ShieldSafetyBufferPct >= OfficialDailyDDPct ||
      ShieldSafetyBufferPct >= DynamicShieldPct)
      return false;

   if(RiskPercent <= 0.0 ||
      StopATR <= 0.0 ||
      MinimumStopPips <= 0.0 ||
      RewardRisk <= 0.0 ||
      MaxDailyLossPercent <= 0.0 ||
      MaxTradesPerDay <= 0)
      return false;

   if(MaxDailyLossPercent >= OfficialDailyDDPct)
      return false;

   if(BreakEvenAtR <= 0.0 ||
      BreakEvenLockR < 0.0 ||
      BreakEvenLockR >= BreakEvenAtR ||
      TrailStartR <= 0.0 ||
      TrailATR <= 0.0 ||
      TrailMinStepATR < 0.0 ||
      TrailModifyMinSeconds < 0)
      return false;

   if(MaxSpreadPips <= 0.0 ||
      SlippagePips < 0.0)
      return false;

   if(SessionStartHour < 0 ||
      SessionStartHour > 23 ||
      SessionEndHour < 0 ||
      SessionEndHour > 23 ||
      FridayStopHour < 0 ||
      FridayStopHour > 23)
      return false;

   return true;
}

int OnInit()
{
   if(!InputsValid())
   {
      Print("Invalid EA input detected. Check EMA, risk, spread, session and challenge settings.");
      return INIT_PARAMETERS_INCORRECT;
   }

   forensicActive.active = false;
   forensicActive.positionId = 0;
   lastSLModifyTime = 0;

   if(EnforceEURUSDSymbol && !IsEURUSDSymbol())
   {
      Print(
         "Initialization stopped: attach this EA to EURUSD (broker prefixes/suffixes are supported). Current symbol=",
         _Symbol
      );

      return INIT_FAILED;
   }

   if(_Period != SIGNAL_TIMEFRAME)
   {
      Print(
         "Notice: signals are fixed to M15 even though the current chart period is ",
         _Period,
         "."
      );
   }

   hFastEMA = iMA(
      _Symbol,
      SIGNAL_TIMEFRAME,
      FastEMA,
      0,
      MODE_EMA,
      PRICE_CLOSE
   );

   hSlowEMA = iMA(
      _Symbol,
      SIGNAL_TIMEFRAME,
      SlowEMA,
      0,
      MODE_EMA,
      PRICE_CLOSE
   );

   hRSI = iRSI(
      _Symbol,
      SIGNAL_TIMEFRAME,
      RSIPeriod,
      PRICE_CLOSE
   );

   hATR = iATR(
      _Symbol,
      SIGNAL_TIMEFRAME,
      ATRPeriod
   );

   hADX = iADX(
      _Symbol,
      SIGNAL_TIMEFRAME,
      ADXPeriod
   );

   hH1Fast = iMA(
      _Symbol,
      PERIOD_H1,
      H1FastEMA,
      0,
      MODE_EMA,
      PRICE_CLOSE
   );

   hH1Slow = iMA(
      _Symbol,
      PERIOD_H1,
      H1SlowEMA,
      0,
      MODE_EMA,
      PRICE_CLOSE
   );

   hH1ATR = iATR(
      _Symbol,
      PERIOD_H1,
      ATRPeriod
   );

   if(hFastEMA == INVALID_HANDLE ||
      hSlowEMA == INVALID_HANDLE ||
      hRSI == INVALID_HANDLE ||
      hATR == INVALID_HANDLE ||
      hADX == INVALID_HANDLE ||
      hH1Fast == INVALID_HANDLE ||
      hH1Slow == INVALID_HANDLE ||
      hH1ATR == INVALID_HANDLE)
   {
      Print(
         "Failed to create indicator handle(s). Error=",
         GetLastError()
      );

      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(PipsToPoints(SlippagePips));
   trade.SetTypeFillingBySymbol(_Symbol);

   string stateSuffix =
      IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))
      + "_"
      + IntegerToString((long)MagicNumber);

   if(RunningInTester())
   {
      equityHighWater =
         MathMax(
            ChallengeStartBalance,
            AccountInfoDouble(ACCOUNT_EQUITY)
         );
   }
   else
   {
      hwmGlobalKey =
         "UP25_EU15_HWM_" + stateSuffix;

      dayKeyGlobalKey =
         "UP25_EU15_DAY_K_" + stateSuffix;

      dayEquityGlobalKey =
         "UP25_EU15_DAY_E_" + stateSuffix;

      dayTradesGlobalKey =
         "UP25_EU15_DAY_T_" + stateSuffix;

      if(GlobalVariableCheck(hwmGlobalKey))
      {
         equityHighWater =
            GlobalVariableGet(hwmGlobalKey);
      }
      else
      {
         equityHighWater =
            MathMax(
               ChallengeStartBalance,
               AccountInfoDouble(ACCOUNT_EQUITY)
            );
      }

      equityHighWater =
         MathMax(
            equityHighWater,
            AccountInfoDouble(ACCOUNT_EQUITY)
         );

      GlobalVariableSet(
         hwmGlobalKey,
         equityHighWater
      );

      RestoreDayState();
   }

   ResetDayIfNeeded();

   lastBarTime =
      iTime(
         _Symbol,
         SIGNAL_TIMEFRAME,
         0
      );

   Print(
      "Upcomers $25K Thunderbolt EURUSD M15 EA initialized on ",
      _Symbol,
      ". Risk=",
      DoubleToString(RiskPercent, 2),
      "% | HWM=",
      DoubleToString(equityHighWater, 2),
      " | Shield=",
      DoubleToString(OfficialShieldLevel(), 2),
      " | H1Persist=",
      H1PersistenceBars,
      " | ADXRising=",
      (RequireADXRising ? "on" : "off"),
      " | ERmin=",
      DoubleToString(MinEfficiencyRatio, 2)
   );

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   PersistDayState();

   if(RunningInTester())
   {
      PrintDiagnostics();
      PrintForensics();
   }

   if(hFastEMA != INVALID_HANDLE)
      IndicatorRelease(hFastEMA);

   if(hSlowEMA != INVALID_HANDLE)
      IndicatorRelease(hSlowEMA);

   if(hRSI != INVALID_HANDLE)
      IndicatorRelease(hRSI);

   if(hATR != INVALID_HANDLE)
      IndicatorRelease(hATR);

   if(hADX != INVALID_HANDLE)
      IndicatorRelease(hADX);

   if(hH1Fast != INVALID_HANDLE)
      IndicatorRelease(hH1Fast);

   if(hH1Slow != INVALID_HANDLE)
      IndicatorRelease(hH1Slow);

   if(hH1ATR != INVALID_HANDLE)
      IndicatorRelease(hH1ATR);
}

//+------------------------------------------------------------------+
//| V2.18 forensic exit listener                                     |
//+------------------------------------------------------------------+
void OnTradeTransaction(
   const MqlTradeTransaction &trans,
   const MqlTradeRequest &request,
   const MqlTradeResult &result
)
{
   if(!EnableTradeForensics)
      return;

   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;

   if(trans.deal == 0)
      return;

   if(!HistoryDealSelect(trans.deal))
      return;

   string dealSymbol =
      HistoryDealGetString(
         trans.deal,
         DEAL_SYMBOL
      );

   if(dealSymbol != _Symbol)
      return;

   ulong dealMagic =
      (ulong)HistoryDealGetInteger(
         trans.deal,
         DEAL_MAGIC
      );

   if(dealMagic != MagicNumber)
      return;

   ENUM_DEAL_ENTRY dealEntry =
      (ENUM_DEAL_ENTRY)HistoryDealGetInteger(
         trans.deal,
         DEAL_ENTRY
      );

   if(dealEntry != DEAL_ENTRY_OUT &&
      dealEntry != DEAL_ENTRY_OUT_BY)
      return;

   if(!forensicActive.active)
      return;

   ulong positionId =
      (ulong)HistoryDealGetInteger(
         trans.deal,
         DEAL_POSITION_ID
      );

   if(positionId != forensicActive.positionId)
      return;

   FinalizeForensicTrade(
      trans.deal
   );
}

void OnTick()
{
   ResetDayIfNeeded();
   UpdateHighWater();

   // Position management occurs every tick.
   ManagePosition();

   // Close the EA's EURUSD position at the internal daily stop or before
   // an official challenge guardrail is reached.
   ulong ownTicket;

   if(
      FindOwnPosition(ownTicket) &&
      PositionSelectByTicket(ownTicket) &&
      (
         DailyLossHit() ||
         OfficialDailyLimitTooClose() ||
         DynamicShieldTooClose()
      )
   )
   {
      if(
         !trade.PositionClose(ownTicket) &&
         PrintSignals
      )
      {
         Print(
            "Emergency position close failed: ",
            trade.ResultRetcodeDescription()
         );
      }

      return;
   }

   // New entries only once per new M15 bar, based on the closed bar.
   if(!NewBar())
      return;

   EvaluateEntries();
}
//+------------------------------------------------------------------+
