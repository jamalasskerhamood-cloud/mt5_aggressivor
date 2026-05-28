//+------------------------------------------------------------------+
//|          QuantumShield_BlueProfit_FIXED_V25.mq5                 |
//|            AGGRESSIVE + PROTECTED + PROFITABLE                  |
//+------------------------------------------------------------------+
#property copyright "Proprietary HFT Core"
#property version   "25.00"
#property strict

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>

// Position sizing
input double InpLotSize              = 0.05;

// Spread protection
input int    InpMaxSpread            = 5000;
input int    InpSpreadSamples        = 50;
input double InpSpreadFactor         = 0.85;

// Entry velocity - RAISED to filter noise
input double InpVelocityThreshold    = 0.5;

// RISK MANAGEMENT - THE FIX
input double InpRiskPercent          = 1.0;      // Risk per trade %
input double InpATRMultiplierSL      = 2.5;      // SL = ATR * multiplier
input double InpATRMultiplierTP      = 1.5;      // TP = ATR * multiplier (closer TP)
input int    InpATRPeriod            = 14;

// Blue profit - SECOND PROFIT TAKER
input double InpMinProfitUSD         = 0.05;

// Position limit
input int    InpMaxPositions         = 2;

// Emergency protection
input int    InpEmergencySeconds     = 15;
input double InpEmergencyLoss        = -1.50;
input double InpDailyLossLimit       = -10.00;   // Stop trading for day

input ulong  InpMagic                = 909090;

CTrade        trade;
CPositionInfo pos_info;

// Buffers
double spread_buffer[50];
int spread_idx = 0;
int atr_handle;
double daily_pnl = 0;
datetime last_day = 0;

//====================================================
// INIT
//====================================================
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(200);
   
   // Initialize ATR
   atr_handle = iATR(_Symbol, PERIOD_M1, InpATRPeriod);
   if(atr_handle == INVALID_HANDLE)
   {
      Print("ATR INIT FAILED");
      return(INIT_FAILED);
   }
   
   ArrayInitialize(spread_buffer, 0);
   
   Print("QuantumShield V25 - PROTECTED MODE");
   return(INIT_SUCCEEDED);
}

//====================================================
// DEINIT
//====================================================
void OnDeinit(const int reason)
{
   if(atr_handle != INVALID_HANDLE)
      IndicatorRelease(atr_handle);
}

//====================================================
// POSITION COUNTER
//====================================================
int CountPositions()
{
   int count = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      if(pos_info.SelectByIndex(i))
         if(pos_info.Symbol() == _Symbol && pos_info.Magic() == (long)InpMagic)
            count++;
   }
   return count;
}

//====================================================
// GET CURRENT ATR
//====================================================
double GetATR()
{
   double atr_array[1];
   if(CopyBuffer(atr_handle, 0, 0, 1, atr_array) <= 0)
   {
      Print("ATR COPY FAILED");
      return 0;
   }
   return atr_array[0];
}

//====================================================
// CALCULATE LOT SIZE BY RISK
//====================================================
double CalculateLots(double sl_distance)
{
   if(sl_distance <= 0)
      return InpLotSize;
   
   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   
   if(tick_value <= 0 || tick_size <= 0)
      return InpLotSize;
   
   double risk_money = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPercent / 100.0;
   double sl_ticks = sl_distance / tick_size;
   double lot_size = risk_money / (sl_ticks * tick_value);
   
   // Normalize
   double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   
   lot_size = MathFloor(lot_size / lot_step) * lot_step;
   lot_size = MathMax(min_lot, MathMin(max_lot, lot_size));
   
   return lot_size;
}

//====================================================
// POSITION MANAGER WITH PROTECTION
//====================================================
void ManagePositions(MqlTick &tick, double velocity)
{
   double atr = GetATR();
   
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      if(!pos_info.SelectByIndex(i))
         continue;
      if(pos_info.Symbol() != _Symbol)
         continue;
      if(pos_info.Magic() != (long)InpMagic)
         continue;
      
      double net_profit = pos_info.Profit() + pos_info.Swap() + pos_info.Commission();
      double open_price = pos_info.PriceOpen();
      double current_sl = pos_info.StopLoss();
      double current_tp = pos_info.TakeProfit();
      
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)pos_info.PositionType();
      
      //================================================
      // BLUE PROFIT EXIT - Trail profit
      //================================================
      if(net_profit >= InpMinProfitUSD)
      {
         // Close if velocity slowing down
         static double peak_profit[100] = {0};
         static int peak_idx = 0;
         
         // Track peak profit per position
         double pos_peak = 0;
         for(int j = 0; j < 100; j++)
         {
            if(peak_profit[j] > pos_peak)
               pos_peak = peak_profit[j];
         }
         
         if(net_profit > pos_peak)
            peak_profit[peak_idx++ % 100] = net_profit;
         
         // Close if profit drops 30% from peak
         if(pos_peak > 0 && net_profit < pos_peak * 0.7)
         {
            Print("BLUE PROFIT TRAIL CLOSE: ", net_profit);
            trade.PositionClose(pos_info.Ticket());
            continue;
         }
      }
      
      //================================================
      // UPDATE STOP LOSS - Trail if profitable
      //================================================
      if(atr > 0 && net_profit > 0)
      {
         double new_sl = 0;
         double trail_distance = atr * 1.0;
         
         if(type == POSITION_TYPE_BUY)
         {
            new_sl = tick.bid - trail_distance;
            // Only move SL up
            if(new_sl > current_sl || current_sl == 0)
               trade.PositionModify(pos_info.Ticket(), new_sl, current_tp);
         }
         else if(type == POSITION_TYPE_SELL)
         {
            new_sl = tick.ask + trail_distance;
            // Only move SL down
            if(new_sl < current_sl || current_sl == 0)
               trade.PositionModify(pos_info.Ticket(), new_sl, current_tp);
         }
      }
      
      //================================================
      // EMERGENCY EXIT
      //================================================
      datetime open_time = (datetime)pos_info.Time();
      int alive_seconds = (int)(TimeCurrent() - open_time);
      
      if(alive_seconds > InpEmergencySeconds && net_profit < InpEmergencyLoss)
      {
         Print("EMERGENCY CLOSE: ", net_profit, " | Alive: ", alive_seconds, "s");
         trade.PositionClose(pos_info.Ticket());
         continue;
      }
      
      // Update daily P&L
      daily_pnl += net_profit;
   }
}

//====================================================
// MAIN ENGINE
//====================================================
void OnTick()
{
   // Check daily loss limit
   if(TimeCurrent() / 86400 != last_day / 86400)
   {
      daily_pnl = 0;
      last_day = TimeCurrent();
   }
   
   if(daily_pnl < InpDailyLossLimit)
   {
      // Silent - stop trading for day
      return;
   }
   
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      return;
   
   MqlTick current_tick;
   if(!SymbolInfoTick(_Symbol, current_tick))
      return;
   
   // Update spread buffer
   int spread = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   spread_buffer[spread_idx++ % InpSpreadSamples] = spread;
   
   static MqlTick last_tick;
   if(last_tick.time_msc == 0)
   {
      last_tick = current_tick;
      return;
   }
   
   double time_diff = (current_tick.time_msc - last_tick.time_msc) / 1000.0;
   if(time_diff <= 0)
   {
      last_tick = current_tick;
      return;
   }
   
   // Price change and velocity
   double price_change = current_tick.bid - last_tick.bid;
   double velocity = MathAbs(price_change) / time_diff;
   
   // Manage existing positions
   ManagePositions(current_tick, velocity);
   
   // Position limit check
   if(CountPositions() >= InpMaxPositions)
   {
      last_tick = current_tick;
      return;
   }
   
   // Average spread filter
   double avg_spread = 0;
   int valid_samples = 0;
   for(int i = 0; i < InpSpreadSamples; i++)
   {
      if(spread_buffer[i] > 0)
      {
         avg_spread += spread_buffer[i];
         valid_samples++;
      }
   }
   
   if(valid_samples > 0)
      avg_spread /= valid_samples;
   else
      avg_spread = spread;
   
   bool low_spread = spread <= (avg_spread * InpSpreadFactor) && spread <= InpMaxSpread;
   
   //================================================
   // ENTRY ENGINE - KEEP AGGRESSIVE BUT PROTECTED
   //================================================
   if(low_spread && velocity >= InpVelocityThreshold)
   {
      double atr = GetATR();
      if(atr <= 0)
         atr = 0.0001; // Fallback
      
      double sl_distance = atr * InpATRMultiplierSL;
      double tp_distance = atr * InpATRMultiplierTP;
      
      double lots = CalculateLots(sl_distance);
      
      if(lots <= 0)
         lots = InpLotSize;
      
      // BUY SIGNAL
      if(price_change > 0)
      {
         double sl = current_tick.bid - sl_distance;
         double tp = current_tick.bid + tp_distance;
         
         bool result = trade.Buy(lots, _Symbol, 0, sl, tp, "SHIELD_BUY");
         
         if(result)
            Print("BUY | Lots: ", lots, " | SL: ", sl, " | TP: ", tp, " | Velocity: ", velocity);
         else
            Print("BUY FAILED | Error: ", GetLastError());
      }
      // SELL SIGNAL
      else if(price_change < 0)
      {
         double sl = current_tick.ask + sl_distance;
         double tp = current_tick.ask - tp_distance;
         
         bool result = trade.Sell(lots, _Symbol, 0, sl, tp, "SHIELD_SELL");
         
         if(result)
            Print("SELL | Lots: ", lots, " | SL: ", sl, " | TP: ", tp, " | Velocity: ", velocity);
         else
            Print("SELL FAILED | Error: ", GetLastError());
      }
   }
   
   last_tick = current_tick;
}
//+------------------------------------------------------------------+
