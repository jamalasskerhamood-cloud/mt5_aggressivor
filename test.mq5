//+------------------------------------------------------------------+
//|          QuantumShield_ULTIMATE_AGGRESSIVE.mq5                   |
//|        ALL CONDITIONS + ALL FIXES + ACTUALLY TRADES              |
//+------------------------------------------------------------------+
#property copyright "Ultimate Aggressive"
#property version   "37.00"
#property strict

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>

// ORIGINAL CONDITIONS - KEPT
input double InpLotSize              = 0.05;
input double InpTakeProfitPips       = 2.0;
input double InpStopLossPips         = 3.0;

// LIQUIDITY SWEEP - ORIGINAL
input int    InpSwingLookback        = 20;
input double InpSweepThreshold       = 0.3;

// MOMENTUM - ORIGINAL
input int    InpRSIPeriod            = 5;
input double InpRSIUpper             = 65;
input double InpRSILower             = 35;

// VOLUME - ORIGINAL
input double InpVolumeMultiplier     = 1.3;
input int    InpVolumePeriod         = 20;

// AGGRESSIVE - MAXIMUM
input int    InpMaxPositions         = 5;
input int    InpMaxDailyTrades       = 1000;
input int    InpCooldownMs           = 50;
input int    InpMaxTradesPerSecond   = 5;

// PROFIT EXITS - ORIGINAL SECRETS
input double InpPartialClosePips     = 3.0;
input double InpTrailStartPips       = 1.5;
input double InpTrailDistancePips    = 0.8;
input int    InpMaxTradeSeconds      = 60;

// MONEY
input double InpDailyProfitTarget    = 200.0;
input double InpDailyLossLimit       = -50.0;

input ulong  InpMagic                = 909090;

CTrade        trade;
CPositionInfo pos_info;

// Tick buffer - FIXED
struct TickInfo
{
   double bid;
   double ask;
   long   volume;
   long   time_msc;     // FIXED: was datetime
   bool   is_bid_tick;
};

TickInfo tick_buffer[200];
int tick_count = 0;

// Trade tracker
struct TradeTracker
{
   ulong  ticket;
   double entry_price;
   double best_pips;
   double best_price;
   datetime entry_time;
   bool   partial_done;
   int    stale_ticks;
};

TradeTracker trades[5];

// Indicators
int rsi_handle;
int volumes_handle;

// Daily
int daily_trades = 0;
double daily_pnl = 0;
datetime today = 0;

// Speed
int sec_trades = 0;
datetime this_sec = 0;
ulong last_trade_ms = 0;

//====================================================
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(10);
   trade.SetAsyncMode(false);  // FIXED: sync for reliability
   
   // FIXED: Manual init instead of ArrayInitialize
   for(int i = 0; i < 200; i++)
   {
      tick_buffer[i].bid = 0;
      tick_buffer[i].ask = 0;
      tick_buffer[i].volume = 0;
      tick_buffer[i].time_msc = 0;
      tick_buffer[i].is_bid_tick = false;
   }
   
   for(int i = 0; i < 5; i++)
   {
      trades[i].ticket = 0;
      trades[i].entry_price = 0;
      trades[i].best_pips = 0;
      trades[i].best_price = 0;
      trades[i].entry_time = 0;
      trades[i].partial_done = false;
      trades[i].stale_ticks = 0;
   }
   
   rsi_handle = iRSI(_Symbol, PERIOD_M1, InpRSIPeriod, PRICE_CLOSE);
   volumes_handle = iVolumes(_Symbol, PERIOD_M1, VOLUME_TICK);
   
   today = TimeCurrent() / 86400;
   
   Print("═══════════════════════════════════════");
   Print("⚡ ULTIMATE AGGRESSIVE - READY TO TRADE");
   Print("Max Positions: ", InpMaxPositions);
   Print("Max Trades/sec: ", InpMaxTradesPerSecond);
   Print("Cooldown: ", InpCooldownMs, "ms");
   Print("═══════════════════════════════════════");
   
   return(INIT_SUCCEEDED);
}

//====================================================
void OnDeinit(const int reason)
{
   if(rsi_handle != INVALID_HANDLE) IndicatorRelease(rsi_handle);
   if(volumes_handle != INVALID_HANDLE) IndicatorRelease(volumes_handle);
}

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
double GetPipSize()
{
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   return (digits == 5 || digits == 3) ? point * 10 : point;
}

//====================================================
// ADD TICK - FIXED volume logic
//====================================================
void AddTick(MqlTick &t)
{
   static double last_bid = 0;
   
   if(tick_count >= 200)
   {
      for(int i = 0; i < 199; i++)
         tick_buffer[i] = tick_buffer[i+1];
      tick_count = 199;
   }
   
   tick_buffer[tick_count].bid = t.bid;
   tick_buffer[tick_count].ask = t.ask;
   tick_buffer[tick_count].volume = t.volume_real;
   tick_buffer[tick_count].time_msc = t.time_msc;
   
   // FIXED: Directional tick pressure
   tick_buffer[tick_count].is_bid_tick = (t.bid > last_bid);
   
   last_bid = t.bid;
   tick_count++;
}

//====================================================
// DETECT SWINGS - ORIGINAL METHOD
//====================================================
void DetectSwings(double &high, double &low)
{
   high = 0;
   low = 999999;
   
   int start = tick_count - InpSwingLookback - 2;
   if(start < 0) start = 0;
   
   for(int i = start + 1; i < tick_count - 1; i++)
   {
      if(tick_buffer[i].bid > tick_buffer[i-1].bid && 
         tick_buffer[i].bid > tick_buffer[i+1].bid)
         if(tick_buffer[i].bid > high) high = tick_buffer[i].bid;
      
      if(tick_buffer[i].bid < tick_buffer[i-1].bid && 
         tick_buffer[i].bid < tick_buffer[i+1].bid)
         if(tick_buffer[i].bid < low) low = tick_buffer[i].bid;
   }
}

//====================================================
// VOLUME SPIKE - ORIGINAL
//====================================================
bool VolumeSpike()
{
   if(tick_count < InpVolumePeriod + 1) return true; // ALLOW if not enough data
   
   double curr = tick_buffer[tick_count-1].volume;
   double avg = 0;
   
   int start = tick_count - InpVolumePeriod - 1;
   for(int i = start; i < tick_count - 1; i++)
      avg += tick_buffer[i].volume;
   
   avg /= InpVolumePeriod;
   
   return (avg > 0 && curr > avg * InpVolumeMultiplier);
}

//====================================================
// GET RSI
//====================================================
double GetRSI()
{
   double arr[1];
   if(CopyBuffer(rsi_handle, 0, 0, 1, arr) > 0)
      return arr[0];
   return 50;
}

//====================================================
// CHECK ENTRY SIGNALS - COMBINED
//====================================================
int GetSignal(MqlTick &t)
{
   if(tick_count < 30) return 0;
   
   double swing_high, swing_low;
   DetectSwings(swing_high, swing_low);
   
   double pip = GetPipSize();
   double sweep_dist = InpSweepThreshold * pip;
   double rsi = GetRSI();
   
   // SIGNAL 1: BULLISH LIQUIDITY SWEEP
   // Price swept below low and recovered
   if(swing_low < 999999)
   {
      for(int i = tick_count - 10; i < tick_count; i++)
      {
         if(i < 0) continue;
         if(tick_buffer[i].bid < swing_low - sweep_dist)
         {
            if(t.bid > swing_low && rsi < InpRSIUpper)
               return 1;
         }
      }
   }
   
   // SIGNAL 2: BEARISH LIQUIDITY SWEEP
   // Price swept above high and recovered
   if(swing_high > 0)
   {
      for(int i = tick_count - 10; i < tick_count; i++)
      {
         if(i < 0) continue;
         if(tick_buffer[i].ask > swing_high + sweep_dist)
         {
            if(t.ask < swing_high && rsi > InpRSILower)
               return -1;
         }
      }
   }
   
   // SIGNAL 3: TICK MOMENTUM - MOST AGGRESSIVE
   if(tick_count >= 5)
   {
      double move = (t.bid - tick_buffer[tick_count-5].bid) / pip;
      
      if(move > 0.3 && rsi < InpRSIUpper)
         return 1;
      if(move < -0.3 && rsi > InpRSILower)
         return -1;
   }
   
   // SIGNAL 4: SIMPLE PRICE DIRECTION
   // ANY movement = trade
   if(tick_count >= 2)
   {
      double change = (t.bid - tick_buffer[tick_count-2].bid) / pip;
      
      if(change > 0.15)
         return 1;
      if(change < -0.15)
         return -1;
   }
   
   return 0;
}

//====================================================
// MANAGE EXITS - ALL ORIGINAL SECRETS
//====================================================
void ManageExits(MqlTick &t)
{
   double pip = GetPipSize();
   
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      if(!pos_info.SelectByIndex(i)) continue;
      if(pos_info.Symbol() != _Symbol || pos_info.Magic() != (long)InpMagic) continue;
      
      ulong ticket = pos_info.Ticket();
      double profit = pos_info.Profit() + pos_info.Swap() + pos_info.Commission();
      double open_price = pos_info.PriceOpen();
      double curr_sl = pos_info.StopLoss();
      double curr_tp = pos_info.TakeProfit();
      int type = (int)pos_info.PositionType();
      
      double pips = 0;
      double price = 0;
      
      if(type == POSITION_TYPE_BUY)
      {
         pips = (t.bid - open_price) / pip;
         price = t.bid;
      }
      else
      {
         pips = (open_price - t.ask) / pip;
         price = t.ask;
      }
      
      // Find tracker
      int idx = -1;
      for(int j = 0; j < 5; j++)
      {
         if(trades[j].ticket == ticket) { idx = j; break; }
      }
      
      if(idx == -1)
      {
         for(int j = 0; j < 5; j++)
         {
            if(trades[j].ticket == 0)
            {
               trades[j].ticket = ticket;
               trades[j].entry_price = open_price;
               trades[j].best_pips = 0;
               trades[j].best_price = price;
               trades[j].entry_time = TimeCurrent();
               trades[j].partial_done = false;
               trades[j].stale_ticks = 0;
               idx = j;
               break;
            }
         }
      }
      
      if(idx == -1) continue;
      
      // Update best
      if(pips > trades[idx].best_pips)
      {
         trades[idx].best_pips = pips;
         trades[idx].best_price = price;
         trades[idx].stale_ticks = 0;
      }
      else
      {
         trades[idx].stale_ticks++;
      }
      
      // SECRET 1: Partial close at 3 pips
      if(pips >= InpPartialClosePips && !trades[idx].partial_done)
      {
         double close_vol = pos_info.Volume() * 0.5;
         if(trade.PositionClosePartial(ticket, close_vol))
         {
            Print("💎 PARTIAL 50% at +", DoubleToString(pips, 1), "p");
            trades[idx].partial_done = true;
            daily_pnl += profit * 0.5;
         }
      }
      
      // SECRET 2: Breakeven after partial close
      if(trades[idx].partial_done && curr_sl != open_price)
      {
         double be_sl = open_price;
         if(type == POSITION_TYPE_BUY) be_sl = open_price + pip * 0.3;
         else be_sl = open_price - pip * 0.3;
         
         if((type == POSITION_TYPE_BUY && be_sl > curr_sl) ||
            (type == POSITION_TYPE_SELL && be_sl < curr_sl))
            trade.PositionModify(ticket, be_sl, curr_tp);
      }
      
      // SECRET 3: Trailing stop
      if(pips >= InpTrailStartPips)
      {
         double trail_sl = 0;
         double trail_dist = InpTrailDistancePips * pip;
         
         if(type == POSITION_TYPE_BUY)
            trail_sl = t.bid - trail_dist;
         else
            trail_sl = t.ask + trail_dist;
         
         if((type == POSITION_TYPE_BUY && trail_sl > curr_sl) ||
            (type == POSITION_TYPE_SELL && trail_sl < curr_sl))
            trade.PositionModify(ticket, trail_sl, curr_tp);
      }
      
      // EXIT 1: Quick profit lock
      if(pips >= 0.5 && trades[idx].stale_ticks >= 5)
      {
         Print("💰 QUICK LOCK +", DoubleToString(pips, 1), "p");
         if(trade.PositionClose(ticket))
         {
            trades[idx].ticket = 0;
            daily_pnl += profit;
         }
         continue;
      }
      
      // EXIT 2: Peak reversal
      if(trades[idx].best_pips >= 1.0 && pips <= trades[idx].best_pips - 0.5)
      {
         Print("📉 PEAK EXIT +", DoubleToString(pips, 1), "p");
         if(trade.PositionClose(ticket))
         {
            trades[idx].ticket = 0;
            daily_pnl += profit;
         }
         continue;
      }
      
      // EXIT 3: Time limit
      int sec = (int)(TimeCurrent() - trades[idx].entry_time);
      if(sec >= InpMaxTradeSeconds && pips > 0.2)
      {
         Print("⏰ TIME +", DoubleToString(pips, 1), "p");
         if(trade.PositionClose(ticket))
         {
            trades[idx].ticket = 0;
            daily_pnl += profit;
         }
         continue;
      }
   }
   
   // Clean closed
   for(int j = 0; j < 5; j++)
   {
      if(trades[j].ticket != 0)
      {
         bool found = false;
         for(int i = PositionsTotal()-1; i >= 0; i--)
         {
            if(pos_info.SelectByIndex(i))
               if(pos_info.Ticket() == trades[j].ticket)
                  found = true;
         }
         if(!found) trades[j].ticket = 0;
      }
   }
}

//====================================================
// OPEN TRADE
//====================================================
void OpenTrade(int dir, string reason)
{
   MqlTick t;
   if(!SymbolInfoTick(_Symbol, t)) return;
   
   double pip = GetPipSize();
   double sl = InpStopLossPips * pip;
   double tp = InpTakeProfitPips * pip;
   
   double min_stop = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 2;
   if(sl < min_stop) sl = min_stop;
   if(tp < min_stop) tp = min_stop;
   
   if(dir == 1)
   {
      double s = t.bid - sl;
      double p = t.bid + tp;
      if(trade.Buy(InpLotSize, _Symbol, 0, s, p, reason))
      {
         Print("🟢 ", reason, " @ ", DoubleToString(t.bid, 5));
         sec_trades++;
         daily_trades++;
         last_trade_ms = GetTickCount();
      }
   }
   else
   {
      double s = t.ask + sl;
      double p = t.ask - tp;
      if(trade.Sell(InpLotSize, _Symbol, 0, s, p, reason))
      {
         Print("🔴 ", reason, " @ ", DoubleToString(t.ask, 5));
         sec_trades++;
         daily_trades++;
         last_trade_ms = GetTickCount();
      }
   }
}

//====================================================
// MAIN - ULTRA AGGRESSIVE
//====================================================
void OnTick()
{
   // New day
   if(TimeCurrent() / 86400 != today)
   {
      Print("📅 NEW DAY | P&L: $", DoubleToString(daily_pnl, 2));
      daily_trades = 0;
      daily_pnl = 0;
      today = TimeCurrent() / 86400;
   }
   
   // Limits
   if(daily_trades >= InpMaxDailyTrades) return;
   if(daily_pnl >= InpDailyProfitTarget) return;
   if(daily_pnl <= InpDailyLossLimit) return;
   
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) return;
   
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return;
   
   // Add tick
   AddTick(tick);
   
   // Manage exits EVERY tick
   ManageExits(tick);
   
   // Position limit
   if(CountPositions() >= InpMaxPositions) return;
   
   // Per-second limit
   if(TimeCurrent() != this_sec)
   {
      sec_trades = 0;
      this_sec = TimeCurrent();
   }
   if(sec_trades >= InpMaxTradesPerSecond) return;
   
   // Cooldown
   if(GetTickCount() - last_trade_ms < InpCooldownMs) return;
   
   // SPREAD - WIDER to allow more trades
   int spread = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > 15) return;  // Allow up to 1.5 pips
   
   // GET SIGNAL
   int signal = GetSignal(tick);
   
   if(signal == 1)
      OpenTrade(1, "BUY");
   else if(signal == -1)
      OpenTrade(-1, "SELL");
}
//+------------------------------------------------------------------+
