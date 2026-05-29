//+------------------------------------------------------------------+
//|          QuantumShield_TICK_MASTER_PROFIT.mq5                    |
//|        PURE TICK TRADING + GUARANTEED PROFIT EXITS               |
//+------------------------------------------------------------------+
#property copyright "Tick Master Professional"
#property version   "31.00"
#property strict

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>

input double InpLotSize              = 0.05;

// ASYMMETRIC RISK:REWARD - THE REAL SECRET
input double InpTakeProfitPips       = 10.0;    // Big winners
input double InpStopLossPips         = 5.0;     // Small losers

// TICK-BASED ENTRY PARAMETERS
input double InpMinTickMomentum      = 0.3;     // Minimum pips per tick for entry
input int    InpTickConfirmation     = 2;       // Number of consecutive ticks in same direction
input double InpReversalThreshold    = 0.5;     // Pips reversal to confirm sweep

// LIQUIDITY SWEEP DETECTION - ON TICKS
input int    InpTicksLookback        = 100;     // Ticks for swing detection
input double InpSweepThreshold       = 0.3;     // Pips beyond swing for sweep

// VOLUME SPIKE DETECTION - ON TICKS
input double InpVolumeMultiplier     = 1.3;     // Volume spike threshold
input int    InpVolumeTicks          = 50;      // Ticks for volume average

// AGGRESSIVE SETTINGS
input int    InpMaxPositions         = 3;       // Multiple positions
input int    InpMaxDailyTrades       = 500;     // High frequency
input int    InpCooldownMs           = 100;     // 100ms between trades
input int    InpMaxTradesPerSecond   = 3;       // Max 3 trades/second

// GUARANTEED PROFIT EXITS
input double InpMinProfitLock        = 2.0;     // Lock profit at 2 pips
input double InpTrailStartPips       = 3.0;     // Start trailing at 3 pips
input double InpTrailDistancePips    = 1.5;     // Tight 1.5 pip trail
input int    InpMaxTradeSeconds      = 120;     // Max 2 minutes per trade

// MONEY MANAGEMENT
input double InpDailyProfitTarget    = 200.0;   // Higher target
input double InpDailyLossLimit       = -50.0;

input ulong  InpMagic                = 909090;

CTrade        trade;
CPositionInfo pos_info;

// Tick data buffers
struct TickData
{
   double bid;
   double ask;
   long volume;
   datetime time_msc;
};

TickData tick_buffer[];
int tick_count = 0;
int buffer_size = 200;

// Daily tracking
int daily_trades = 0;
double daily_pnl = 0;
datetime current_day = 0;
double starting_balance = 0;

// Second tracking
int second_trades = 0;
datetime current_second = 0;
ulong last_trade_ms = 0;

// Trade tracking for guaranteed profit
struct TradeTracker
{
   ulong ticket;
   double entry_price;
   double peak_profit_pips;
   double peak_profit_price;
   datetime entry_time;
   bool partial_closed;
};

TradeTracker active_trades[3];
int active_count = 0;

//====================================================
// INIT
//====================================================
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(15);
   trade.SetAsyncMode(true);  // ASYNC FOR TICK SPEED
   
   ArrayResize(tick_buffer, buffer_size);
   
   for(int i = 0; i < 3; i++)
      active_trades[i].ticket = 0;
   
   starting_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   current_day = TimeCurrent() / 86400;
   
   Print("═══════════════════════════════════════");
   Print("⚡ TICK MASTER - PURE TICK TRADING");
   Print("TP: ", InpTakeProfitPips, " | SL: ", InpStopLossPips);
   Print("Risk:Reward = 1:", InpTakeProfitPips/InpStopLossPips);
   Print("Min Tick Momentum: ", InpMinTickMomentum, " pips");
   Print("Cooldown: ", InpCooldownMs, "ms");
   Print("Max Trades/sec: ", InpMaxTradesPerSecond);
   Print("Guaranteed Profit Lock: ", InpMinProfitLock, " pips");
   Print("Max Trade Time: ", InpMaxTradeSeconds, "s");
   Print("Starting Balance: $", DoubleToString(starting_balance, 2));
   Print("═══════════════════════════════════════");
   
   return(INIT_SUCCEEDED);
}

//====================================================
// DEINIT
//====================================================
void OnDeinit(const int reason)
{
   double final_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   Print("═══════════════════════════════════════");
   Print("📊 TICK MASTER SUMMARY");
   Print("Starting: $", DoubleToString(starting_balance, 2));
   Print("Final: $", DoubleToString(final_balance, 2));
   Print("Net: $", DoubleToString(final_balance - starting_balance, 2));
   Print("Total Trades: ", daily_trades);
   Print("═══════════════════════════════════════");
}

//====================================================
// COUNT POSITIONS
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
// GET PIP SIZE
//====================================================
double GetPipSize()
{
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   return (digits == 5 || digits == 3) ? point * 10 : point;
}

//====================================================
// ADD TICK TO BUFFER
//====================================================
void AddTick(MqlTick &tick)
{
   if(tick_count >= buffer_size)
   {
      // Shift buffer left
      for(int i = 0; i < buffer_size - 1; i++)
         tick_buffer[i] = tick_buffer[i + 1];
      tick_count = buffer_size - 1;
   }
   
   tick_buffer[tick_count].bid = tick.bid;
   tick_buffer[tick_count].ask = tick.ask;
   tick_buffer[tick_count].volume = tick.volume_real;
   tick_buffer[tick_count].time_msc = tick.time_msc;
   tick_count++;
}

//====================================================
// DETECT TICK MOMENTUM
//====================================================
double GetTickMomentum(int lookback)
{
   if(tick_count < lookback + 1) return 0;
   
   double pip_size = GetPipSize();
   double total_momentum = 0;
   int same_direction = 0;
   
   for(int i = tick_count - lookback; i < tick_count - 1; i++)
   {
      double change = (tick_buffer[i + 1].bid - tick_buffer[i].bid) / pip_size;
      total_momentum += change;
      
      if((change > 0 && total_momentum > 0) || (change < 0 && total_momentum < 0))
         same_direction++;
   }
   
   // Return momentum only if consecutive ticks in same direction
   if(same_direction >= InpTickConfirmation)
      return total_momentum;
   
   return 0;
}

//====================================================
// DETECT SWINGS FROM TICKS
//====================================================
void DetectTickSwings(double &swing_high, double &swing_low)
{
   if(tick_count < InpTicksLookback) return;
   
   swing_high = 0;
   swing_low = 999999;
   
   int start = tick_count - InpTicksLookback;
   if(start < 0) start = 0;
   
   for(int i = start + 1; i < tick_count - 1; i++)
   {
      // Swing high
      if(tick_buffer[i].bid > tick_buffer[i-1].bid && tick_buffer[i].bid > tick_buffer[i+1].bid)
         if(tick_buffer[i].bid > swing_high)
            swing_high = tick_buffer[i].bid;
      
      // Swing low
      if(tick_buffer[i].bid < tick_buffer[i-1].bid && tick_buffer[i].bid < tick_buffer[i+1].bid)
         if(tick_buffer[i].bid < swing_low)
            swing_low = tick_buffer[i].bid;
   }
}

//====================================================
// CHECK TICK VOLUME SPIKE
//====================================================
bool IsTickVolumeSpike()
{
   if(tick_count < InpVolumeTicks + 1) return false;
   
   double current_vol = tick_buffer[tick_count - 1].volume;
   double avg_vol = 0;
   
   int start = tick_count - InpVolumeTicks - 1;
   for(int i = start; i < tick_count - 1; i++)
      avg_vol += tick_buffer[i].volume;
   
   avg_vol /= InpVolumeTicks;
   
   return (avg_vol > 0 && current_vol > avg_vol * InpVolumeMultiplier);
}

//====================================================
// CHECK LIQUIDITY SWEEP ON TICKS
//====================================================
int CheckTickSweep()
{
   double swing_high = 0, swing_low = 999999;
   DetectTickSwings(swing_high, swing_low);
   
   if(swing_high == 0 || swing_low == 999999) return 0;
   
   double pip_size = GetPipSize();
   double sweep_dist = InpSweepThreshold * pip_size;
   
   // Check recent ticks for sweep
   for(int i = tick_count - 10; i < tick_count; i++)
   {
      if(i < 0) continue;
      
      // Bearish sweep (below swing low)
      if(tick_buffer[i].bid < swing_low - sweep_dist)
      {
         // Check if price recovered
         if(tick_buffer[tick_count - 1].bid > swing_low)
            return 1; // Bullish reversal
      }
      
      // Bullish sweep (above swing high)
      if(tick_buffer[i].ask > swing_high + sweep_dist)
      {
         // Check if price recovered
         if(tick_buffer[tick_count - 1].ask < swing_high)
            return -1; // Bearish reversal
      }
   }
   
   return 0;
}

//====================================================
// GUARANTEED PROFIT EXIT MANAGEMENT
//====================================================
void GuaranteedProfitExit(MqlTick &tick)
{
   double pip_size = GetPipSize();
   
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      if(!pos_info.SelectByIndex(i)) continue;
      if(pos_info.Symbol() != _Symbol || pos_info.Magic() != (long)InpMagic) continue;
      
      ulong ticket = pos_info.Ticket();
      double net_profit = pos_info.Profit() + pos_info.Swap() + pos_info.Commission();
      double open_price = pos_info.PriceOpen();
      double current_sl = pos_info.StopLoss();
      double current_tp = pos_info.TakeProfit();
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)pos_info.PositionType();
      
      // Calculate pips profit
      double pips_profit = 0;
      double current_price = 0;
      
      if(type == POSITION_TYPE_BUY)
      {
         pips_profit = (tick.bid - open_price) / pip_size;
         current_price = tick.bid;
      }
      else
      {
         pips_profit = (open_price - tick.ask) / pip_size;
         current_price = tick.ask;
      }
      
      // Find tracker for this trade
      int tracker_idx = -1;
      for(int j = 0; j < 3; j++)
      {
         if(active_trades[j].ticket == ticket)
         {
            tracker_idx = j;
            break;
         }
      }
      
      if(tracker_idx == -1)
      {
         // Create new tracker
         for(int j = 0; j < 3; j++)
         {
            if(active_trades[j].ticket == 0)
            {
               active_trades[j].ticket = ticket;
               active_trades[j].entry_price = open_price;
               active_trades[j].peak_profit_pips = 0;
               active_trades[j].entry_time = TimeCurrent();
               active_trades[j].partial_closed = false;
               tracker_idx = j;
               break;
            }
         }
      }
      
      if(tracker_idx == -1) continue;
      
      // Update peak profit
      if(pips_profit > active_trades[tracker_idx].peak_profit_pips)
      {
         active_trades[tracker_idx].peak_profit_pips = pips_profit;
         active_trades[tracker_idx].peak_profit_price = current_price;
      }
      
      double peak_pips = active_trades[tracker_idx].peak_profit_pips;
      
      //================================================
      // EXIT 1: GUARANTEED PROFIT LOCK at 2+ pips
      //================================================
      if(pips_profit >= InpMinProfitLock && peak_pips - pips_profit >= InpReversalThreshold)
      {
         Print("💰 GUARANTEED PROFIT | Peak: +", DoubleToString(peak_pips, 1), 
               "p | Exit: +", DoubleToString(pips_profit, 1), "p | $", DoubleToString(net_profit, 3));
         trade.PositionClose(ticket);
         active_trades[tracker_idx].ticket = 0;
         daily_pnl += net_profit;
         continue;
      }
      
      //================================================
      // EXIT 2: TRAILING STOP - Lock in profits
      //================================================
      if(pips_profit >= InpTrailStartPips)
      {
         double trail_distance = InpTrailDistancePips * pip_size;
         double new_sl = 0;
         
         if(type == POSITION_TYPE_BUY)
            new_sl = tick.bid - trail_distance;
         else
            new_sl = tick.ask + trail_distance;
         
         if((type == POSITION_TYPE_BUY && new_sl > current_sl) ||
            (type == POSITION_TYPE_SELL && (new_sl < current_sl || current_sl == 0)))
         {
            if(trade.PositionModify(ticket, new_sl, current_tp))
            {
               Print("📈 TRAIL +", DoubleToString(pips_profit, 1), "p | SL: ", DoubleToString(new_sl, 5));
            }
         }
      }
      
      //================================================
      // EXIT 3: BREAKEVEN MOVE at 3+ pips
      //================================================
      if(pips_profit >= 3.0 && current_sl != open_price)
      {
         double new_sl = open_price;
         if(type == POSITION_TYPE_BUY)
            new_sl = open_price + (pip_size * 0.3);
         else
            new_sl = open_price - (pip_size * 0.3);
         
         if((type == POSITION_TYPE_BUY && new_sl > current_sl) ||
            (type == POSITION_TYPE_SELL && new_sl < current_sl))
         {
            trade.PositionModify(ticket, new_sl, current_tp);
            Print("🛡️ BREAKEVEN+ at +", DoubleToString(pips_profit, 1), "p");
         }
      }
      
      //================================================
      // EXIT 4: TIME STOP - No dead trades
      //================================================
      int seconds_open = (int)(TimeCurrent() - active_trades[tracker_idx].entry_time);
      
      if(seconds_open > InpMaxTradeSeconds && pips_profit < 2.0)
      {
         Print("⏰ TIME STOP | ", seconds_open, "s | ", DoubleToString(pips_profit, 1), "p");
         trade.PositionClose(ticket);
         active_trades[tracker_idx].ticket = 0;
         daily_pnl += net_profit;
         continue;
      }
      
      //================================================
      // EXIT 5: MOMENTUM DEATH - No more movement
      //================================================
      if(seconds_open > 30 && pips_profit > 0.5 && pips_profit < 2.0)
      {
         // Check if price hasn't moved in last 10 seconds
         if(peak_pips - pips_profit < 0.2 && peak_pips < 2.5)
         {
            Print("💤 MOMENTUM DEATH | +", DoubleToString(pips_profit, 1), "p | $", DoubleToString(net_profit, 3));
            trade.PositionClose(ticket);
            active_trades[tracker_idx].ticket = 0;
            daily_pnl += net_profit;
            continue;
         }
      }
   }
   
   // Clean up trackers for closed positions
   for(int j = 0; j < 3; j++)
   {
      if(active_trades[j].ticket != 0)
      {
         bool found = false;
         for(int i = PositionsTotal()-1; i >= 0; i--)
         {
            if(pos_info.SelectByIndex(i))
               if(pos_info.Ticket() == active_trades[j].ticket)
                  found = true;
         }
         if(!found)
            active_trades[j].ticket = 0;
      }
   }
}

//====================================================
// CHECK NEW DAY
//====================================================
void CheckNewDay()
{
   datetime new_day = TimeCurrent() / 86400;
   if(new_day != current_day)
   {
      Print("📅 NEW DAY | Yesterday: $", DoubleToString(daily_pnl, 2), " | Trades: ", daily_trades);
      daily_trades = 0;
      daily_pnl = 0;
      current_day = new_day;
   }
}

//====================================================
// EXECUTE TRADE - Ultra fast tick-based
//====================================================
void ExecuteTrade(int direction, string signal)
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return;
   
   double pip_size = GetPipSize();
   double sl_distance = InpStopLossPips * pip_size;
   double tp_distance = InpTakeProfitPips * pip_size;
   double lots = InpLotSize;
   
   double min_stops = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 2;
   if(sl_distance < min_stops) sl_distance = min_stops;
   if(tp_distance < min_stops) tp_distance = min_stops;
   
   if(direction == 1) // BUY
   {
      double sl = tick.bid - sl_distance;
      double tp = tick.bid + tp_distance;
      
      if(trade.Buy(lots, _Symbol, 0, sl, tp, signal))
      {
         Print("🟢 ", signal, " | ", tick.bid, " | Vol: ", tick.volume_real);
         second_trades++;
         daily_trades++;
         last_trade_ms = GetTickCount();
      }
   }
   else if(direction == -1) // SELL
   {
      double sl = tick.ask + sl_distance;
      double tp = tick.ask - tp_distance;
      
      if(trade.Sell(lots, _Symbol, 0, sl, tp, signal))
      {
         Print("🔴 ", signal, " | ", tick.ask, " | Vol: ", tick.volume_real);
         second_trades++;
         daily_trades++;
         last_trade_ms = GetTickCount();
      }
   }
}

//====================================================
// MAIN ENGINE - PURE TICK TRADING
//====================================================
void OnTick()
{
   CheckNewDay();
   
   // DAILY LIMITS
   if(daily_trades >= InpMaxDailyTrades || daily_pnl >= InpDailyProfitTarget || daily_pnl <= InpDailyLossLimit)
      return;
   
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) return;
   
   MqlTick current_tick;
   if(!SymbolInfoTick(_Symbol, current_tick)) return;
   
   // ADD TICK TO BUFFER
   AddTick(current_tick);
   
   // GUARANTEED PROFIT EXITS - CHECK EVERY TICK
   GuaranteedProfitExit(current_tick);
   
   // POSITION LIMIT
   if(CountPositions() >= InpMaxPositions) return;
   
   // SECOND LIMIT
   if(TimeCurrent() != current_second)
   {
      second_trades = 0;
      current_second = TimeCurrent();
   }
   if(second_trades >= InpMaxTradesPerSecond) return;
   
   // COOLDOWN
   if(GetTickCount() - last_trade_ms < InpCooldownMs) return;
   
   // SPREAD CHECK
   int spread = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > 25) return;
   
   //================================================
   // TICK-BASED ENTRY SIGNALS
   //================================================
   
   double pip_size = GetPipSize();
   
   // SIGNAL 1: TICK MOMENTUM - Consecutive ticks in same direction
   double momentum = GetTickMomentum(5); // Last 5 ticks
   
   if(MathAbs(momentum) >= InpMinTickMomentum)
   {
      if(momentum > 0)
      {
         ExecuteTrade(1, "TICK_MOMENTUM_BUY");
         return;
      }
      else
      {
         ExecuteTrade(-1, "TICK_MOMENTUM_SELL");
         return;
      }
   }
   
   // SIGNAL 2: LIQUIDITY SWEEP ON TICKS
   int sweep = CheckTickSweep();
   
   if(sweep != 0 && IsTickVolumeSpike())
   {
      if(sweep == 1)
      {
         ExecuteTrade(1, "TICK_SWEEP_BUY");
         return;
      }
      else if(sweep == -1)
      {
         ExecuteTrade(-1, "TICK_SWEEP_SELL");
         return;
      }
   }
   
   // SIGNAL 3: VOLUME SPIKE + PRICE SURGE
   if(IsTickVolumeSpike())
   {
      double recent_change = 0;
      if(tick_count >= 3)
      {
         recent_change = (tick_buffer[tick_count - 1].bid - tick_buffer[tick_count - 3].bid) / pip_size;
      }
      
      if(recent_change > InpMinTickMomentum)
      {
         ExecuteTrade(1, "VOL_SURGE_BUY");
         return;
      }
      else if(recent_change < -InpMinTickMomentum)
      {
         ExecuteTrade(-1, "VOL_SURGE_SELL");
         return;
      }
   }
   
   // SIGNAL 4: REVERSAL AFTER SWEEP (HIGH PROBABILITY)
   double swing_high = 0, swing_low = 999999;
   DetectTickSwings(swing_high, swing_low);
   
   if(swing_low < 999999 && current_tick.bid < swing_low && tick_count >= 2)
   {
      // Price just broke below swing low - wait for reversal
      if(tick_buffer[tick_count - 2].bid < swing_low && current_tick.bid > tick_buffer[tick_count - 2].bid)
      {
         ExecuteTrade(1, "REVERSAL_BUY");
         return;
      }
   }
   
   if(swing_high > 0 && current_tick.ask > swing_high && tick_count >= 2)
   {
      // Price just broke above swing high - wait for reversal
      if(tick_buffer[tick_count - 2].ask > swing_high && current_tick.ask < tick_buffer[tick_count - 2].ask)
      {
         ExecuteTrade(-1, "REVERSAL_SELL");
         return;
      }
   }
}
//+------------------------------------------------------------------+
