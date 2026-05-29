//+------------------------------------------------------------------+
//|          QuantumShield_ULTRA_AGGRESSIVE_PROFIT.mq5               |
//|            INSTANT TRADES + SMART EXITS = PROFIT                  |
//+------------------------------------------------------------------+
#property copyright "Ultra Aggressive Scalping"
#property version   "30.00"
#property strict

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>

input double InpLotSize              = 0.05;

// ASYMMETRIC - Wins bigger than losses
input double InpTakeProfitPips       = 8.0;     // Bigger wins
input double InpStopLossPips         = 4.0;     // Smaller losses

// ULTRA AGGRESSIVE ENTRY
input int    InpMaxSpread            = 25;      // 2.5 pips
input int    InpMaxPositions         = 3;       // Multiple positions
input int    InpCooldownMs           = 200;     // 200ms between trades
input int    InpMaxTradesPerMinute   = 10;      // Up to 10 trades/min

// SMART EXITS
input double InpTrailStartPips       = 4.0;     // Trail after 4 pips
input double InpTrailDistancePips    = 2.0;     // 2 pip trail
input double InpBreakevenPips        = 3.0;     // Breakeven at 3 pips
input int    InpMaxTradeMinutes      = 10;      // Kill after 10 min

// MONEY MANAGEMENT
input double InpDailyProfitTarget    = 100.0;
input double InpDailyLossLimit       = -50.0;
input int    InpMaxDailyTrades       = 200;

input ulong  InpMagic                = 909090;

CTrade        trade;
CPositionInfo pos_info;

// Trading stats
int daily_trades = 0;
double daily_pnl = 0;
datetime current_day = 0;
int minute_trades = 0;
datetime current_minute = 0;

//====================================================
// INIT
//====================================================
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(15);
   trade.SetAsyncMode(true);  // ASYNC FOR SPEED - CRITICAL FOR AGGRESSIVE
   
   current_day = TimeCurrent() / 86400;
   
   Print("═══════════════════════════════════════");
   Print("⚡⚡⚡ ULTRA AGGRESSIVE SCALPER ⚡⚡⚡");
   Print("TP: ", InpTakeProfitPips, " pips | SL: ", InpStopLossPips, " pips");
   Print("Risk:Reward = 1:", InpTakeProfitPips/InpStopLossPips);
   Print("Max Positions: ", InpMaxPositions);
   Print("Max Trades/Min: ", InpMaxTradesPerMinute);
   Print("Cooldown: ", InpCooldownMs, "ms");
   Print("═══════════════════════════════════════");
   
   return(INIT_SUCCEEDED);
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
// SMART EXIT MANAGEMENT
//====================================================
void ManageExits(MqlTick &tick)
{
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      if(!pos_info.SelectByIndex(i))
         continue;
      if(pos_info.Symbol() != _Symbol || pos_info.Magic() != (long)InpMagic)
         continue;
      
      double net_profit = pos_info.Profit() + pos_info.Swap() + pos_info.Commission();
      double open_price = pos_info.PriceOpen();
      double current_sl = pos_info.StopLoss();
      double current_tp = pos_info.TakeProfit();
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)pos_info.PositionType();
      
      // Calculate pips profit
      double pips_profit = 0;
      if(type == POSITION_TYPE_BUY)
         pips_profit = (tick.bid - open_price) / GetPipSize();
      else
         pips_profit = (open_price - tick.ask) / GetPipSize();
      
      double pip_size = GetPipSize();
      
      //================================================
      // EXIT 1: BREAKEVEN LOCK (Most important for win rate)
      //================================================
      if(pips_profit >= InpBreakevenPips && current_sl != open_price)
      {
         double new_sl = open_price;
         if(type == POSITION_TYPE_BUY)
            new_sl = open_price + (pip_size * 0.5);
         else
            new_sl = open_price - (pip_size * 0.5);
         
         if((type == POSITION_TYPE_BUY && new_sl > current_sl) ||
            (type == POSITION_TYPE_SELL && new_sl < current_sl))
         {
            trade.PositionModify(pos_info.Ticket(), new_sl, current_tp);
         }
      }
      
      //================================================
      // EXIT 2: AGGRESSIVE TRAILING
      //================================================
      if(pips_profit >= InpTrailStartPips)
      {
         double trail_sl = 0;
         
         if(type == POSITION_TYPE_BUY)
            trail_sl = tick.bid - (InpTrailDistancePips * pip_size);
         else
            trail_sl = tick.ask + (InpTrailDistancePips * pip_size);
         
         if((type == POSITION_TYPE_BUY && trail_sl > current_sl) ||
            (type == POSITION_TYPE_SELL && trail_sl < current_sl))
         {
            trade.PositionModify(pos_info.Ticket(), trail_sl, current_tp);
         }
      }
      
      //================================================
      // EXIT 3: INSTANT PROFIT LOCK
      //================================================
      if(pips_profit >= 2.0 && pips_profit < InpTrailStartPips)
      {
         // If price reverses 1.5 pips from peak, close
         static double peak_pips = 0;
         static ulong peak_ticket = 0;
         
         if(peak_ticket != pos_info.Ticket())
         {
            peak_pips = 0;
            peak_ticket = pos_info.Ticket();
         }
         
         if(pips_profit > peak_pips)
            peak_pips = pips_profit;
         
         if(peak_pips - pips_profit >= 1.5 && net_profit > 0)
         {
            Print("💰 PROFIT LOCK | From +", DoubleToString(peak_pips, 1), 
                  " to +", DoubleToString(pips_profit, 1), " pips | $", DoubleToString(net_profit, 3));
            trade.PositionClose(pos_info.Ticket());
            daily_pnl += net_profit;
            continue;
         }
      }
      
      //================================================
      // EXIT 4: TIME STOP - No patience for losers
      //================================================
      datetime open_time = (datetime)pos_info.Time();
      int minutes_open = (int)((TimeCurrent() - open_time) / 60);
      
      if(minutes_open >= InpMaxTradeMinutes && pips_profit < 2.0)
      {
         Print("⏰ TIME KILL | ", minutes_open, " min | ", DoubleToString(pips_profit, 1), " pips");
         trade.PositionClose(pos_info.Ticket());
         daily_pnl += net_profit;
         continue;
      }
      
      //================================================
      // EXIT 5: SMALL PROFIT CLOSE - Don't be greedy
      //================================================
      if(pips_profit >= 5.0 && pips_profit < InpTakeProfitPips)
      {
         // Check if momentum is dying (bid/ask spread widening)
         if((tick.ask - tick.bid) / pip_size > 2.0)  // Spread > 2 pips = low liquidity
         {
            Print("📉 LOW LIQUIDITY EXIT | Profit: ", DoubleToString(pips_profit, 1), " pips");
            trade.PositionClose(pos_info.Ticket());
            daily_pnl += net_profit;
            continue;
         }
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
      Print("📅 NEW DAY | Yesterday's P&L: $", DoubleToString(daily_pnl, 2));
      daily_trades = 0;
      daily_pnl = 0;
      current_day = new_day;
   }
}

//====================================================
// MAIN ENGINE - ULTRA AGGRESSIVE
//====================================================
void OnTick()
{
   CheckNewDay();
   
   // Daily limits
   if(daily_trades >= InpMaxDailyTrades) return;
   if(daily_pnl >= InpDailyProfitTarget) return;
   if(daily_pnl <= InpDailyLossLimit) return;
   
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) return;
   
   MqlTick current_tick;
   if(!SymbolInfoTick(_Symbol, current_tick)) return;
   
   // Manage exits EVERY tick - critical
   ManageExits(current_tick);
   
   // Reset minute counter
   if(TimeCurrent() / 60 != current_minute / 60)
   {
      minute_trades = 0;
      current_minute = TimeCurrent();
   }
   
   // Position limit
   if(CountPositions() >= InpMaxPositions) return;
   
   // Minute limit
   if(minute_trades >= InpMaxTradesPerMinute) return;
   
   // Spread check - single filter
   int spread = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > InpMaxSpread) return;
   
   //================================================
   // PRICE MOVEMENT DETECTION
   //================================================
   static double last_bid = 0;
   static double last_ask = 0;
   static datetime last_entry_time = 0;
   
   if(last_bid == 0)
   {
      last_bid = current_tick.bid;
      last_ask = current_tick.ask;
      return;
   }
   
   // Cooldown check (in milliseconds)
   if(GetTickCount() - last_entry_time < InpCooldownMs) return;
   
   double bid_change = current_tick.bid - last_bid;
   double ask_change = current_tick.ask - last_ask;
   double pip_size = GetPipSize();
   
   double sl_distance = InpStopLossPips * pip_size;
   double tp_distance = InpTakeProfitPips * pip_size;
   
   // Minimum stop level
   double min_stops = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 2;
   if(sl_distance < min_stops) sl_distance = min_stops;
   if(tp_distance < min_stops) tp_distance = min_stops;
   
   //================================================
   // BUY - On ANY upward movement
   //================================================
   if(bid_change > 0)
   {
      double sl = current_tick.bid - sl_distance;
      double tp = current_tick.bid + tp_distance;
      
      if(trade.Buy(InpLotSize, _Symbol, 0, sl, tp, "AGGRO_BUY"))
      {
         minute_trades++;
         daily_trades++;
         last_entry_time = GetTickCount();
         Print("🟢 #", daily_trades, " BUY @ ", current_tick.bid, 
               " | Δ", DoubleToString(bid_change/pip_size, 1), "p");
      }
   }
   
   //================================================
   // SELL - On ANY downward movement
   //================================================
   if(ask_change < 0)
   {
      double sl = current_tick.ask + sl_distance;
      double tp = current_tick.ask - tp_distance;
      
      if(trade.Sell(InpLotSize, _Symbol, 0, sl, tp, "AGGRO_SELL"))
      {
         minute_trades++;
         daily_trades++;
         last_entry_time = GetTickCount();
         Print("🔴 #", daily_trades, " SELL @ ", current_tick.ask, 
               " | Δ", DoubleToString(ask_change/pip_size, 1), "p");
      }
   }
   
   last_bid = current_tick.bid;
   last_ask = current_tick.ask;
}
//+------------------------------------------------------------------+
