//+------------------------------------------------------------------+
//|          QuantumShield_BlueProfit_FOREX_V25.mq5                 |
//|            AGGRESSIVE FOREX SCALPER WITH PROTECTION             |
//+------------------------------------------------------------------+
#property copyright "Proprietary HFT Core"
#property version   "25.00"
#property strict

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>

// Position sizing
input double InpLotSize              = 0.05;

// Spread protection - FOREX VALUES
input int    InpMaxSpread            = 30;      // 3.0 pips max for GBPUSD
input int    InpSpreadSamples        = 50;
input double InpSpreadFactor         = 1.2;     // Allow 120% of average

// Entry velocity - FOREX APPROPRIATE
input double InpVelocityThreshold    = 0.00005; // 0.5 pips per second

// RISK MANAGEMENT
input double InpATRMultiplierSL      = 2.0;
input double InpATRMultiplierTP      = 2.5;     // Better risk:reward
input int    InpATRPeriod            = 14;

// Blue profit close
input double InpMinProfitUSD         = 0.10;

// Position limit
input int    InpMaxPositions         = 2;

// Emergency protection
input int    InpEmergencySeconds     = 30;
input double InpEmergencyLoss        = -5.00;

input ulong  InpMagic                = 909090;

CTrade        trade;
CPositionInfo pos_info;

// Buffers
double spread_buffer[];
int spread_idx = 0;
int atr_handle;
datetime last_bar_time = 0;

//====================================================
// INIT
//====================================================
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(30);  // 3 pips for forex
   trade.SetAsyncMode(false);
   
   // Initialize ATR on M1
   atr_handle = iATR(_Symbol, PERIOD_M1, InpATRPeriod);
   if(atr_handle == INVALID_HANDLE)
      Print("⚠️ ATR INIT FAILED - Using fixed SL");
   
   ArrayResize(spread_buffer, InpSpreadSamples);
   ArrayInitialize(spread_buffer, 0);
   
   // Get current spread
   int current_spread = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   Print("═══════════════════════════════════════");
   Print("🔵 QuantumShield FOREX V25 ACTIVE");
   Print("Symbol: ", _Symbol);
   Print("Current Spread: ", current_spread, " points (", current_spread * point, ")");
   Print("Velocity Threshold: ", InpVelocityThreshold);
   Print("Max Spread: ", InpMaxSpread, " points");
   Print("Max Positions: ", InpMaxPositions);
   Print("Lot Size: ", InpLotSize);
   Print("═══════════════════════════════════════");
   
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
      return 0.00030; // Fallback: ~3 pips for GBPUSD
   return atr_array[0];
}

//====================================================
// POSITION MANAGER
//====================================================
void ManagePositions(MqlTick &tick)
{
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      if(!pos_info.SelectByIndex(i))
         continue;
      if(pos_info.Symbol() != _Symbol)
         continue;
      if(pos_info.Magic() != (long)InpMagic)
         continue;
      
      double net_profit = pos_info.Profit() + pos_info.Swap() + pos_info.Commission();
      double current_sl = pos_info.StopLoss();
      double current_tp = pos_info.TakeProfit();
      
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)pos_info.PositionType();
      
      //================================================
      // BLUE PROFIT EXIT
      //================================================
      if(net_profit >= InpMinProfitUSD)
      {
         Print("💙 BLUE PROFIT CLOSE: $", DoubleToString(net_profit, 2), " | Ticket: ", pos_info.Ticket());
         trade.PositionClose(pos_info.Ticket());
         continue;
      }
      
      //================================================
      // TRAILING STOP WHEN PROFITABLE
      //================================================
      if(net_profit > 0.05 && current_sl > 0)
      {
         double atr = GetATR();
         double trail_distance = atr * 0.5;
         double new_sl = 0;
         
         if(type == POSITION_TYPE_BUY)
         {
            new_sl = tick.bid - trail_distance;
            if(new_sl > current_sl)
            {
               if(trade.PositionModify(pos_info.Ticket(), new_sl, current_tp))
                  Print("📈 BUY SL TRAILED to ", new_sl);
            }
         }
         else if(type == POSITION_TYPE_SELL)
         {
            new_sl = tick.ask + trail_distance;
            if(new_sl < current_sl || current_sl == 0)
            {
               if(trade.PositionModify(pos_info.Ticket(), new_sl, current_tp))
                  Print("📉 SELL SL TRAILED to ", new_sl);
            }
         }
      }
      
      //================================================
      // BREAKEVEN MOVE
      //================================================
      if(net_profit > 0.15 && current_sl != pos_info.PriceOpen())
      {
         if(type == POSITION_TYPE_BUY && tick.bid > pos_info.PriceOpen() + 0.00010)
         {
            trade.PositionModify(pos_info.Ticket(), pos_info.PriceOpen() + 0.00002, current_tp);
            Print("🛡️ BUY MOVED TO BREAKEVEN+");
         }
         else if(type == POSITION_TYPE_SELL && tick.ask < pos_info.PriceOpen() - 0.00010)
         {
            trade.PositionModify(pos_info.Ticket(), pos_info.PriceOpen() - 0.00002, current_tp);
            Print("🛡️ SELL MOVED TO BREAKEVEN+");
         }
      }
      
      //================================================
      // EMERGENCY EXIT
      //================================================
      datetime open_time = (datetime)pos_info.Time();
      int alive_seconds = (int)(TimeCurrent() - open_time);
      
      if(alive_seconds > InpEmergencySeconds && net_profit < InpEmergencyLoss)
      {
         Print("🚨 EMERGENCY CLOSE: $", DoubleToString(net_profit, 2), " | Alive: ", alive_seconds, "s");
         trade.PositionClose(pos_info.Ticket());
         continue;
      }
   }
}

//====================================================
// MAIN ENGINE
//====================================================
void OnTick()
{
   // Check if trading is allowed
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      return;
   
   // Get current tick
   MqlTick current_tick;
   if(!SymbolInfoTick(_Symbol, current_tick))
      return;
   
   // Update spread buffer
   int spread = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   spread_buffer[spread_idx] = (double)spread;
   spread_idx++;
   if(spread_idx >= InpSpreadSamples)
      spread_idx = 0;
   
   // Manage existing positions
   ManagePositions(current_tick);
   
   // Position limit check
   if(CountPositions() >= InpMaxPositions)
      return;
   
   // FIRST TICK CHECK
   static MqlTick last_tick;
   if(last_tick.time_msc == 0)
   {
      last_tick = current_tick;
      return;
   }
   
   // Time difference
   double time_diff = (current_tick.time_msc - last_tick.time_msc) / 1000.0;
   if(time_diff <= 0)
   {
      last_tick = current_tick;
      return;
   }
   
   // Price change and velocity
   double price_change = current_tick.bid - last_tick.bid;
   double velocity = MathAbs(price_change) / time_diff;
   
   // Average spread calculation
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
   
   if(valid_samples > 10)
      avg_spread /= valid_samples;
   else
      avg_spread = spread;
   
   bool spread_ok = (spread <= InpMaxSpread && spread <= (avg_spread * InpSpreadFactor));
   
   //================================================
   // ENTRY ENGINE
   //================================================
   if(spread_ok && velocity >= InpVelocityThreshold)
   {
      double atr = GetATR();
      if(atr <= 0) atr = 0.00030; // 3 pips fallback
      
      double sl_distance = atr * InpATRMultiplierSL;
      double tp_distance = atr * InpATRMultiplierTP;
      
      // Ensure minimum distances
      if(sl_distance < 0.00020) sl_distance = 0.00020; // Min 2 pips SL
      if(tp_distance < 0.00030) tp_distance = 0.00030; // Min 3 pips TP
      
      // BUY SIGNAL
      if(price_change > 0)
      {
         double sl = current_tick.bid - sl_distance;
         double tp = current_tick.bid + tp_distance;
         
         Print("🟢 BUY SIGNAL | Velocity: ", DoubleToString(velocity, 6), 
               " | Spread: ", spread, " | SL: ", DoubleToString(sl, 5), 
               " | TP: ", DoubleToString(tp, 5));
         
         if(trade.Buy(InpLotSize, _Symbol, 0, sl, tp, "FOREX_BUY"))
         {
            Print("✅ BUY OPENED at ", current_tick.ask);
         }
         else
         {
            Print("❌ BUY FAILED: Error ", GetLastError());
         }
      }
      // SELL SIGNAL
      else if(price_change < 0)
      {
         double sl = current_tick.ask + sl_distance;
         double tp = current_tick.ask - tp_distance;
         
         Print("🔴 SELL SIGNAL | Velocity: ", DoubleToString(velocity, 6), 
               " | Spread: ", spread, " | SL: ", DoubleToString(sl, 5), 
               " | TP: ", DoubleToString(tp, 5));
         
         if(trade.Sell(InpLotSize, _Symbol, 0, sl, tp, "FOREX_SELL"))
         {
            Print("✅ SELL OPENED at ", current_tick.bid);
         }
         else
         {
            Print("❌ SELL FAILED: Error ", GetLastError());
         }
      }
   }
   
   // Debug output every new bar
   if(TimeCurrent() / 60 != last_bar_time / 60)
   {
      Print("📊 [", TimeToString(TimeCurrent()), "] Velocity: ", DoubleToString(velocity, 6),
            " | Spread: ", spread, " | Avg Spread: ", DoubleToString(avg_spread, 1),
            " | Threshold: ", DoubleToString(InpVelocityThreshold, 6),
            " | ATR: ", DoubleToString(GetATR(), 5));
      last_bar_time = TimeCurrent();
   }
   
   last_tick = current_tick;
}
//+------------------------------------------------------------------+
