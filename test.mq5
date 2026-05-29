//+------------------------------------------------------------------+
//|          QuantumShield_ORDERFLOW_PROFIT.mq5                      |
//|        REAL EDGE: ORDER FLOW IMBALANCE + INSTANT EXITS           |
//+------------------------------------------------------------------+
#property copyright "Order Flow Professional"
#property version   "32.00"
#property strict

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>

input double InpLotSize              = 0.05;

// TIGHT SPREAD FOR FAST EXITS
input double InpTakeProfitPips       = 3.0;     // Quick 3 pip target
input double InpStopLossPips         = 2.0;     // Tiny 2 pip stop

// ORDER FLOW IMBALANCE DETECTION
input int    InpImbalanceTicks       = 20;      // Ticks to analyze
input double InpImbalanceRatio       = 1.5;     // Bid volume vs Ask volume ratio
input double InpMinPriceMove         = 0.2;     // Minimum price movement

// MARKET MAKER PATTERNS
input int    InpAbsorptionTicks      = 10;      // Absorption pattern detection
input double InpAbsorptionThreshold  = 0.3;     // Price stall threshold

// AGGRESSIVE SPEED SETTINGS
input int    InpMaxPositions         = 2;
input int    InpMaxDailyTrades       = 500;
input int    InpCooldownMs           = 50;      // 50ms - ULTRA FAST
input int    InpMaxTradesPerSecond   = 5;

// INSTANT PROFIT EXITS
input double InpInstantProfitPips    = 1.0;     // Exit at 1 pip if stalling
input double InpStallThreshold       = 0.3;     // Stall detection
input int    InpStallTicks           = 5;       // Ticks for stall detection
input int    InpMaxTradeSeconds      = 60;      // Max 60 seconds

// MONEY MANAGEMENT
input double InpDailyProfitTarget    = 100.0;
input double InpDailyLossLimit       = -30.0;

input ulong  InpMagic                = 909090;

CTrade        trade;
CPositionInfo pos_info;

// Tick data for order flow analysis
struct TickInfo
{
   double bid;
   double ask;
   long bid_volume;
   long ask_volume;
   datetime time_msc;
   bool is_bid_tick;  // true if bid changed, false if ask changed
};

TickInfo tick_buffer[100];
int tick_count = 0;

// Trade tracking
struct ActiveTrade
{
   ulong ticket;
   double entry_price;
   double best_price;
   double best_profit_pips;
   datetime entry_time;
   int stall_ticks;
   bool profit_locked;
};

ActiveTrade trades[2];
int active_trades = 0;

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
// INIT
//====================================================
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(10);
   trade.SetAsyncMode(true);
   
   ArrayInitialize(tick_buffer, 0);
   
   for(int i = 0; i < 2; i++)
   {
      trades[i].ticket = 0;
      trades[i].profit_locked = false;
   }
   
   starting_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   current_day = TimeCurrent() / 86400;
   
   Print("═══════════════════════════════════════");
   Print("💎 ORDER FLOW PROFIT MASTER");
   Print("TP: ", InpTakeProfitPips, " pips | SL: ", InpStopLossPips, " pips");
   Print("Win Rate Target: 70-80%");
   Print("Imbalance Ratio: ", InpImbalanceRatio, ":1");
   Print("Instant Profit Exit: ", InpInstantProfitPips, " pips");
   Print("Max Trade Time: ", InpMaxTradeSeconds, " seconds");
   Print("Starting: $", DoubleToString(starting_balance, 2));
   Print("═══════════════════════════════════════");
   
   return(INIT_SUCCEEDED);
}

//====================================================
// DEINIT
//====================================================
void OnDeinit(const int reason)
{
   double final_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double net = final_balance - starting_balance;
   
   Print("═══════════════════════════════════════");
   Print("📊 FINAL RESULTS");
   Print("Profit: $", DoubleToString(net, 2));
   Print("Trades Today: ", daily_trades);
   if(daily_trades > 0)
      Print("Avg per trade: $", DoubleToString(net/daily_trades, 3));
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
// ADD TICK TO ORDER FLOW BUFFER
//====================================================
void AddTick(MqlTick &tick)
{
   static double last_bid = 0;
   static double last_ask = 0;
   
   if(tick_count >= 100)
   {
      for(int i = 0; i < 99; i++)
         tick_buffer[i] = tick_buffer[i + 1];
      tick_count = 99;
   }
   
   tick_buffer[tick_count].bid = tick.bid;
   tick_buffer[tick_count].ask = tick.ask;
   tick_buffer[tick_count].bid_volume = tick.volume_real;
   tick_buffer[tick_count].ask_volume = tick.volume_real;
   tick_buffer[tick_count].time_msc = tick.time_msc;
   
   // Determine if bid or ask driven
   if(tick.bid != last_bid)
      tick_buffer[tick_count].is_bid_tick = true;
   else if(tick.ask != last_ask)
      tick_buffer[tick_count].is_bid_tick = false;
   
   last_bid = tick.bid;
   last_ask = tick.ask;
   tick_count++;
}

//====================================================
// ANALYZE ORDER FLOW IMBALANCE
//====================================================
double GetOrderFlowImbalance()
{
   if(tick_count < InpImbalanceTicks) return 0;
   
   int bid_ticks = 0;
   int ask_ticks = 0;
   long bid_volume = 0;
   long ask_volume = 0;
   
   int start = tick_count - InpImbalanceTicks;
   
   for(int i = start; i < tick_count; i++)
   {
      if(tick_buffer[i].is_bid_tick)
      {
         bid_ticks++;
         bid_volume += tick_buffer[i].bid_volume;
      }
      else
      {
         ask_ticks++;
         ask_volume += tick_buffer[i].ask_volume;
      }
   }
   
   // Calculate imbalance ratio
   double imbalance = 0;
   
   if(ask_ticks > 0 && ask_volume > 0)
   {
      double tick_ratio = (double)bid_ticks / (double)ask_ticks;
      double vol_ratio = (double)bid_volume / (double)ask_volume;
      
      // Positive = buying pressure, Negative = selling pressure
      imbalance = (tick_ratio + vol_ratio) / 2.0 - 1.0;
   }
   
   return imbalance;
}

//====================================================
// DETECT MARKET MAKER ABSORPTION
//====================================================
bool DetectAbsorption(int direction)
{
   if(tick_count < InpAbsorptionTicks) return false;
   
   int start = tick_count - InpAbsorptionTicks;
   double first_price = (direction > 0) ? tick_buffer[start].ask : tick_buffer[start].bid;
   double last_price = (direction > 0) ? tick_buffer[tick_count-1].ask : tick_buffer[tick_count-1].bid;
   
   double price_change = MathAbs(last_price - first_price) / GetPipSize();
   
   // Absorption = high volume but price barely moved
   long total_volume = 0;
   for(int i = start; i < tick_count; i++)
      total_volume += tick_buffer[i].bid_volume + tick_buffer[i].ask_volume;
   
   return (price_change < InpAbsorptionThreshold && total_volume > 100);
}

//====================================================
// CHECK PRICE STALLING
//====================================================
bool IsPriceStalling(int direction, MqlTick &tick)
{
   if(tick_count < InpStallTicks) return false;
   
   double current_price = (direction > 0) ? tick.bid : tick.ask;
   int start = tick_count - InpStallTicks;
   
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
// INSTANT PROFIT EXIT SYSTEM
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
      
      // Find trade tracker
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
      
      // Update best profit
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
      
      int direction = (type == POSITION_TYPE_BUY) ? 1 : -1;
      
      //================================================
      // EXIT 1: INSTANT PROFIT - The moment we have 1+ pip, watch for stalling
      //================================================
      if(pips_profit >= InpInstantProfitPips && !trades[idx].profit_locked)
      {
         if(IsPriceStalling(direction, tick) || trades[idx].stall_ticks >= InpStallTicks)
         {
            Print("💰 INSTANT PROFIT | +", DoubleToString(pips_profit, 1), "p | $", DoubleToString(net_profit, 3));
            trade.PositionClose(ticket);
            trades[idx].ticket = 0;
            daily_pnl += net_profit;
            continue;
         }
      }
      
      //================================================
      // EXIT 2: PEAK REVERSAL - Price reversed 0.5 pips from best
      //================================================
      if(trades[idx].best_profit_pips >= 1.5 && pips_profit <= trades[idx].best_profit_pips - 0.5)
      {
         Print("📉 PEAK REVERSAL | Best: +", DoubleToString(trades[idx].best_profit_pips, 1), 
               "p | Exit: +", DoubleToString(pips_profit, 1), "p | $", DoubleToString(net_profit, 3));
         trade.PositionClose(ticket);
         trades[idx].ticket = 0;
         daily_pnl += net_profit;
         continue;
      }
      
      //================================================
      // EXIT 3: TIME LIMIT - No patience
      //================================================
      int seconds_open = (int)(TimeCurrent() - trades[idx].entry_time);
      
      if(seconds_open >= InpMaxTradeSeconds)
      {
         if(pips_profit > 0)
         {
            Print("⏰ TIME EXIT | +", DoubleToString(pips_profit, 1), "p | ", seconds_open, "s");
            trade.PositionClose(ticket);
            trades[idx].ticket = 0;
            daily_pnl += net_profit;
            continue;
         }
      }
      
      //================================================
      // EXIT 4: MICRO PROFIT - Even 0.5 pip profit is fine
      //================================================
      if(pips_profit > 0 && pips_profit < 1.0 && trades[idx].stall_ticks >= 8)
      {
         Print("💵 MICRO PROFIT | +", DoubleToString(pips_profit, 1), "p | $", DoubleToString(net_profit, 4));
         trade.PositionClose(ticket);
         trades[idx].ticket = 0;
         daily_pnl += net_profit;
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
         Print("🟢 ", reason, " | Bid: ", tick.bid, " | Imbalance: ", DoubleToString(GetOrderFlowImbalance(), 2));
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
         Print("🔴 ", reason, " | Ask: ", tick.ask, " | Imbalance: ", DoubleToString(GetOrderFlowImbalance(), 2));
         second_trades++;
         daily_trades++;
         last_trade_ms = GetTickCount();
      }
   }
}

//====================================================
// MAIN ENGINE - ORDER FLOW PROFIT
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
   
   // INSTANT PROFIT EXITS - Every tick
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
   
   // Spread check
   int spread = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > 20) return;
   
   //================================================
   // ORDER FLOW ANALYSIS
   //================================================
   
   double imbalance = GetOrderFlowImbalance();
   double pip_size = GetPipSize();
   
   // Calculate recent price movement
   double price_move = 0;
   if(tick_count >= 5)
   {
      price_move = (current_tick.bid - tick_buffer[tick_count - 5].bid) / pip_size;
   }
   
   //================================================
   // SIGNAL 1: STRONG BUYING IMBALANCE
   // Buyers are aggressive - price will go up
   //================================================
   if(imbalance > InpImbalanceRatio / 10.0 && price_move > 0)
   {
      if(DetectAbsorption(1))
      {
         ExecuteTrade(1, "BUY_IMBALANCE");
         return;
      }
   }
   
   //================================================
   // SIGNAL 2: STRONG SELLING IMBALANCE
   // Sellers are aggressive - price will go down
   //================================================
   if(imbalance < -InpImbalanceRatio / 10.0 && price_move < 0)
   {
      if(DetectAbsorption(-1))
      {
         ExecuteTrade(-1, "SELL_IMBALANCE");
         return;
      }
   }
   
   //================================================
   // SIGNAL 3: ABSORPTION + BREAKOUT
   // Market maker absorbing then price breaks
   //================================================
   if(tick_count >= InpAbsorptionTicks + 3)
   {
      double old_price = tick_buffer[tick_count - InpAbsorptionTicks - 3].bid;
      double new_price = current_tick.bid;
      double move_pips = (new_price - old_price) / pip_size;
      
      if(DetectAbsorption(1) && move_pips > InpMinPriceMove && imbalance > 0)
      {
         ExecuteTrade(1, "ABSORPTION_BREAK");
         return;
      }
      
      if(DetectAbsorption(-1) && move_pips < -InpMinPriceMove && imbalance < 0)
      {
         ExecuteTrade(-1, "ABSORPTION_BREAK");
         return;
      }
   }
   
   //================================================
   // SIGNAL 4: QUICK SCALP - Tick momentum
   //================================================
   if(tick_count >= 3)
   {
      double tick1 = tick_buffer[tick_count - 3].bid;
      double tick3 = current_tick.bid;
      double momentum = (tick3 - tick1) / pip_size;
      
      if(momentum >= InpMinPriceMove && imbalance > 0)
      {
         ExecuteTrade(1, "TICK_MOMENTUM");
         return;
      }
      
      if(momentum <= -InpMinPriceMove && imbalance < 0)
      {
         ExecuteTrade(-1, "TICK_MOMENTUM");
         return;
      }
   }
}
//+------------------------------------------------------------------+
