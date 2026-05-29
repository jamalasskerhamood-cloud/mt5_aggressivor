//+------------------------------------------------------------------+
//|          QuantumShield_TICK_SCALPER_REALISTIC.mq5                |
//|        REALISTIC TICK MOMENTUM SCALPER - FIXED & WORKING         |
//+------------------------------------------------------------------+
#property copyright "Tick Momentum Scalper"
#property version   "35.00"
#property strict

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>

// REALISTIC SETTINGS
input double InpLotSize              = 0.05;
input double InpTakeProfitPips       = 2.0;     // Realistic scalp target
input double InpStopLossPips         = 1.5;     // Tight but realistic

// TICK MOMENTUM DETECTION
input int    InpImbalanceTicks       = 20;
input double InpImbalanceRatio       = 0.3;
input double InpMinPriceMove         = 0.2;

// MARKET PATTERNS
input int    InpAbsorptionTicks      = 10;
input double InpAbsorptionThreshold  = 0.3;

// SPEED SETTINGS - REALISTIC
input int    InpMaxPositions         = 2;
input int    InpMaxDailyTrades       = 300;
input int    InpCooldownMs           = 250;    // Realistic latency
input int    InpMaxTradesPerSecond   = 2;

// INSTANT PROFIT EXITS
input double InpInstantProfitPips    = 0.8;
input double InpStallThreshold       = 0.3;
input int    InpStallTicks           = 5;
input int    InpMaxTradeSeconds      = 45;

// MONEY MANAGEMENT
input double InpDailyProfitTarget    = 50.0;
input double InpDailyLossLimit       = -20.0;

input ulong  InpMagic                = 909090;

CTrade        trade;
CPositionInfo pos_info;

// FIXED STRUCT - long not datetime
struct TickInfo
{
   double bid;
   double ask;
   long   bid_volume;
   long   ask_volume;
   long   time_msc;        // FIXED: was datetime, now long
   bool   is_bid_tick;
};

TickInfo tick_buffer[100];
int tick_count = 0;

// Trade tracking
struct ActiveTrade
{
   ulong  ticket;
   double entry_price;
   double best_price;
   double best_profit_pips;
   datetime entry_time;
   int    stall_ticks;
   bool   profit_locked;
};

ActiveTrade trades[2];

// Indicator handles
int ema_fast_handle;
int ema_slow_handle;

// Daily tracking
int daily_trades = 0;
double daily_pnl = 0;
datetime current_day = 0;
double starting_balance = 0;

// Speed tracking
int second_trades = 0;
datetime current_second = 0;
ulong last_trade_ms = 0;

//====================================================
// INIT - PROPERLY INITIALIZED
//====================================================
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(5);
   trade.SetAsyncMode(false);  // FIXED: Synchronous for reliability
   
   // FIXED: Manual struct initialization instead of ArrayInitialize
   for(int i = 0; i < 100; i++)
   {
      tick_buffer[i].bid = 0;
      tick_buffer[i].ask = 0;
      tick_buffer[i].bid_volume = 0;
      tick_buffer[i].ask_volume = 0;
      tick_buffer[i].time_msc = 0;
      tick_buffer[i].is_bid_tick = false;
   }
   
   // Initialize trade trackers
   for(int i = 0; i < 2; i++)
   {
      trades[i].ticket = 0;
      trades[i].entry_price = 0;
      trades[i].best_price = 0;
      trades[i].best_profit_pips = 0;
      trades[i].entry_time = 0;
      trades[i].stall_ticks = 0;
      trades[i].profit_locked = false;
   }
   
   // Initialize EMA handles for trend filter
   ema_fast_handle = iMA(_Symbol, PERIOD_M1, 20, 0, MODE_EMA, PRICE_CLOSE);
   ema_slow_handle = iMA(_Symbol, PERIOD_M1, 50, 0, MODE_EMA, PRICE_CLOSE);
   
   starting_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   current_day = TimeCurrent() / 86400;
   
   Print("═══════════════════════════════════════");
   Print("⚡ TICK MOMENTUM SCALPER - REALISTIC");
   Print("TP: ", InpTakeProfitPips, " | SL: ", InpStopLossPips);
   Print("Spread Limit: 8 points");
   Print("Cooldown: ", InpCooldownMs, "ms");
   Print("Trend Filter: EMA20/EMA50");
   Print("Starting: $", DoubleToString(starting_balance, 2));
   Print("═══════════════════════════════════════");
   
   return(INIT_SUCCEEDED);
}

//====================================================
// DEINIT
//====================================================
void OnDeinit(const int reason)
{
   if(ema_fast_handle != INVALID_HANDLE) IndicatorRelease(ema_fast_handle);
   if(ema_slow_handle != INVALID_HANDLE) IndicatorRelease(ema_slow_handle);
   
   double final_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   Print("═══════════════════════════════════════");
   Print("📊 FINAL: $", DoubleToString(final_balance - starting_balance, 2));
   Print("Trades: ", daily_trades);
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
// TREND FILTER - ADDED
//====================================================
bool TrendFilter(int direction)
{
   double ema_fast_arr[1], ema_slow_arr[1];
   
   if(CopyBuffer(ema_fast_handle, 0, 0, 1, ema_fast_arr) <= 0) return true;
   if(CopyBuffer(ema_slow_handle, 0, 0, 1, ema_slow_arr) <= 0) return true;
   
   double ema_fast = ema_fast_arr[0];
   double ema_slow = ema_slow_arr[0];
   
   if(direction > 0)
      return (ema_fast > ema_slow);  // Uptrend
   else
      return (ema_fast < ema_slow);  // Downtrend
}

//====================================================
// ADD TICK TO BUFFER - FIXED VOLUME LOGIC
//====================================================
void AddTick(MqlTick &tick)
{
   static double last_bid = 0;
   static double last_ask = 0;
   
   // FIXED: Array overflow safety
   if(tick_count < 0) tick_count = 0;
   if(tick_count > 99) tick_count = 99;
   
   // Shift buffer if full
   if(tick_count >= 99)
   {
      for(int i = 0; i < 99; i++)
         tick_buffer[i] = tick_buffer[i + 1];
      tick_count = 98;
   }
   
   tick_buffer[tick_count].bid = tick.bid;
   tick_buffer[tick_count].ask = tick.ask;
   tick_buffer[tick_count].time_msc = tick.time_msc;
   
   // FIXED: Directional tick pressure instead of fake order flow
   if(tick.bid > last_bid)
   {
      tick_buffer[tick_count].bid_volume = tick.volume_real;
      tick_buffer[tick_count].ask_volume = 0;
      tick_buffer[tick_count].is_bid_tick = true;
   }
   else if(tick.bid < last_bid)
   {
      tick_buffer[tick_count].bid_volume = 0;
      tick_buffer[tick_count].ask_volume = tick.volume_real;
      tick_buffer[tick_count].is_bid_tick = false;
   }
   else
   {
      tick_buffer[tick_count].bid_volume = 0;
      tick_buffer[tick_count].ask_volume = 0;
      tick_buffer[tick_count].is_bid_tick = (tick.ask > last_ask);
   }
   
   last_bid = tick.bid;
   last_ask = tick.ask;
   tick_count++;
}

//====================================================
// GET TICK IMBALANCE
//====================================================
double GetTickImbalance()
{
   if(tick_count < InpImbalanceTicks) return 0;
   
   int bid_ticks = 0;
   int ask_ticks = 0;
   long bid_vol = 0;
   long ask_vol = 0;
   
   int start = tick_count - InpImbalanceTicks;
   if(start < 0) start = 0;
   
   for(int i = start; i < tick_count; i++)
   {
      if(tick_buffer[i].is_bid_tick)
      {
         bid_ticks++;
         bid_vol += tick_buffer[i].bid_volume;
      }
      else
      {
         ask_ticks++;
         ask_vol += tick_buffer[i].ask_volume;
      }
   }
   
   double imbalance = 0;
   int total = bid_ticks + ask_ticks;
   
   if(total > 0)
   {
      double bid_ratio = (double)bid_ticks / (double)total;
      imbalance = (bid_ratio - 0.5) * 2.0;  // -1 to +1
   }
   
   return imbalance;
}

//====================================================
// DETECT ABSORPTION
//====================================================
bool DetectAbsorption(int direction)
{
   if(tick_count < InpAbsorptionTicks) return false;
   
   int start = tick_count - InpAbsorptionTicks;
   if(start < 0) start = 0;
   
   double first_price = (direction > 0) ? tick_buffer[start].ask : tick_buffer[start].bid;
   double last_price = (direction > 0) ? tick_buffer[tick_count-1].ask : tick_buffer[tick_count-1].bid;
   
   double price_change = MathAbs(last_price - first_price) / GetPipSize();
   
   long total_vol = 0;
   for(int i = start; i < tick_count; i++)
      total_vol += tick_buffer[i].bid_volume + tick_buffer[i].ask_volume;
   
   return (price_change < InpAbsorptionThreshold && total_vol > 50);
}

//====================================================
// CHECK PRICE STALLING
//====================================================
bool IsPriceStalling(int direction, MqlTick &tick)
{
   if(tick_count < InpStallTicks) return false;
   
   double current_price = (direction > 0) ? tick.bid : tick.ask;
   int start = tick_count - InpStallTicks;
   if(start < 0) start = 0;
   
   double max_move = 0;
   for(int i = start; i < tick_count - 1; i++)
   {
      double price = (direction > 0) ? tick_buffer[i].bid : tick_buffer[i].ask;
      double move = MathAbs(current_price - price) / GetPipSize();
      if(move > max_move) max_move = move;
   }
   
   return (max_move < InpStallThreshold);
}

//====================================================
// INSTANT PROFIT EXITS
//====================================================
void InstantProfitExit(MqlTick &tick)
{
   double pip_size = GetPipSize();
   
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      if(!pos_info.SelectByIndex(i)) continue;
      if(pos_info.Symbol() != _Symbol || pos_info.Magic() != (long)InpMagic) continue;
      
      ulong ticket = pos_info.Ticket();
      double net_profit = pos_info.Profit() + pos_info.Swap() + pos_info.Commission();
      double open_price = pos_info.PriceOpen();
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)pos_info.PositionType();
      
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
      
      int direction = (type == POSITION_TYPE_BUY) ? 1 : -1;
      
      // Find tracker
      int idx = -1;
      for(int j = 0; j < 2; j++)
      {
         if(trades[j].ticket == ticket) { idx = j; break; }
      }
      
      if(idx == -1)
      {
         for(int j = 0; j < 2; j++)
         {
            if(trades[j].ticket == 0)
            {
               trades[j].ticket = ticket;
               trades[j].entry_price = open_price;
               trades[j].best_price = current_price;
               trades[j].best_profit_pips = 0;
               trades[j].entry_time = TimeCurrent();
               trades[j].stall_ticks = 0;
               trades[j].profit_locked = false;
               idx = j;
               break;
            }
         }
      }
      
      if(idx == -1) continue;
      
      // Update best
      if(pips_profit > trades[idx].best_profit_pips)
      {
         trades[idx].best_profit_pips = pips_profit;
         trades[idx].best_price = current_price;
         trades[idx].stall_ticks = 0;
      }
      else
      {
         trades[idx].stall_ticks++;
      }
      
      // EXIT 1: Instant profit + stalling
      if(pips_profit >= InpInstantProfitPips && !trades[idx].profit_locked)
      {
         if(IsPriceStalling(direction, tick) || trades[idx].stall_ticks >= InpStallTicks)
         {
            Print("💰 INSTANT +", DoubleToString(pips_profit, 1), "p | $", DoubleToString(net_profit, 3));
            if(trade.PositionClose(ticket))  // FIXED: Check success
            {
               trades[idx].ticket = 0;
               daily_pnl += net_profit;
            }
            continue;
         }
      }
      
      // EXIT 2: Peak reversal
      if(trades[idx].best_profit_pips >= 1.0 && pips_profit <= trades[idx].best_profit_pips - 0.4)
      {
         Print("📉 REVERSAL | Best: +", DoubleToString(trades[idx].best_profit_pips, 1), 
               "p | Exit: +", DoubleToString(pips_profit, 1), "p");
         if(trade.PositionClose(ticket))
         {
            trades[idx].ticket = 0;
            daily_pnl += net_profit;
         }
         continue;
      }
      
      // EXIT 3: Time limit
      int seconds_open = (int)(TimeCurrent() - trades[idx].entry_time);
      if(seconds_open >= InpMaxTradeSeconds && pips_profit > 0)
      {
         Print("⏰ TIME +", DoubleToString(pips_profit, 1), "p | ", seconds_open, "s");
         if(trade.PositionClose(ticket))
         {
            trades[idx].ticket = 0;
            daily_pnl += net_profit;
         }
         continue;
      }
   }
   
   // Clean closed trades
   for(int j = 0; j < 2; j++)
   {
      if(trades[j].ticket != 0)
      {
         bool found = false;
         for(int i = PositionsTotal()-1; i >= 0; i--)
         {
            if(pos_info.SelectByIndex(i))
               if(pos_info.Ticket() == trades[j].ticket) found = true;
         }
         if(!found) trades[j].ticket = 0;
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
      Print("📅 NEW DAY | P&L: $", DoubleToString(daily_pnl, 2), " | Trades: ", daily_trades);
      daily_trades = 0;
      daily_pnl = 0;
      current_day = new_day;
   }
}

//====================================================
// EXECUTE TRADE
//====================================================
void ExecuteTrade(int direction, string reason)
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return;
   
   double pip_size = GetPipSize();
   double sl_dist = InpStopLossPips * pip_size;
   double tp_dist = InpTakeProfitPips * pip_size;
   
   double min_stops = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 2;
   if(sl_dist < min_stops) sl_dist = min_stops;
   if(tp_dist < min_stops) tp_dist = min_stops;
   
   if(direction == 1)
   {
      double sl = tick.bid - sl_dist;
      double tp = tick.bid + tp_dist;
      
      if(trade.Buy(InpLotSize, _Symbol, 0, sl, tp, reason))
      {
         Print("🟢 ", reason, " | ", tick.bid);
         second_trades++;
         daily_trades++;
         last_trade_ms = GetTickCount();
      }
   }
   else
   {
      double sl = tick.ask + sl_dist;
      double tp = tick.ask - tp_dist;
      
      if(trade.Sell(InpLotSize, _Symbol, 0, sl, tp, reason))
      {
         Print("🔴 ", reason, " | ", tick.ask);
         second_trades++;
         daily_trades++;
         last_trade_ms = GetTickCount();
      }
   }
}

//====================================================
// MAIN ENGINE
//====================================================
void OnTick()
{
   CheckNewDay();
   
   // Daily limits
   if(daily_trades >= InpMaxDailyTrades || daily_pnl >= InpDailyProfitTarget || daily_pnl <= InpDailyLossLimit)
      return;
   
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) return;
   
   MqlTick current_tick;
   if(!SymbolInfoTick(_Symbol, current_tick)) return;
   
   // Add tick to buffer
   AddTick(current_tick);
   
   // Instant profit exits
   InstantProfitExit(current_tick);
   
   // Position limit
   if(CountPositions() >= InpMaxPositions) return;
   
   // Per-second limit
   if(TimeCurrent() != current_second)
   {
      second_trades = 0;
      current_second = TimeCurrent();
   }
   if(second_trades >= InpMaxTradesPerSecond) return;
   
   // Cooldown
   if(GetTickCount() - last_trade_ms < InpCooldownMs) return;
   
   // FIXED: Tighter spread filter
   int spread = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > 8) return;
   
   double imbalance = GetTickImbalance();
   double pip_size = GetPipSize();
   
   double price_move = 0;
   if(tick_count >= 5)
   {
      int idx = tick_count - 5;
      if(idx >= 0)
         price_move = (current_tick.bid - tick_buffer[idx].bid) / pip_size;
   }
   
   //================================================
   // ENTRY WITH TREND FILTER
   //================================================
   
   // BUY: Momentum + Imbalance + Uptrend
   if(price_move >= InpMinPriceMove && imbalance > InpImbalanceRatio)
   {
      if(TrendFilter(1))  // FIXED: Added trend filter
      {
         if(DetectAbsorption(1))
         {
            ExecuteTrade(1, "BUY_MOMENTUM");
            return;
         }
      }
   }
   
   // SELL: Momentum + Imbalance + Downtrend
   if(price_move <= -InpMinPriceMove && imbalance < -InpImbalanceRatio)
   {
      if(TrendFilter(-1))  // FIXED: Added trend filter
      {
         if(DetectAbsorption(-1))
         {
            ExecuteTrade(-1, "SELL_MOMENTUM");
            return;
         }
      }
   }
}
//+------------------------------------------------------------------+
