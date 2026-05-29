//+------------------------------------------------------------------+
//|          QuantumShield_MOMENTUM_SCALPER_PROFIT.mq5              |
//|            HIGH WIN RATE + SMALL LOSSES + QUICK PROFITS         |
//+------------------------------------------------------------------+
#property copyright "Proven Scalping Strategy"
#property version   "27.00"
#property strict

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>

input double InpLotSize              = 0.05;

// TIGHT EXITS - Small losses, small wins, high win rate
input double InpTakeProfitPips       = 5.0;     // Quick 5 pip profit
input double InpStopLossPips         = 3.0;     // Tighter stop than target

// ENTRY FILTERS - Only high probability setups
input int    InpFastMA               = 5;       // Fast EMA
input int    InpSlowMA               = 20;      // Slow EMA
input int    InpRSIPeriod            = 7;       // Short RSI for scalping
input double InpMinMomentum          = 0.2;     // Minimum price momentum

// MARKET CONDITIONS
input int    InpMaxSpread            = 15;      // Max 1.5 pips
input int    InpMinVolume            = 10;      // Minimum tick volume

// RISK MANAGEMENT
input int    InpMaxPositions         = 1;
input int    InpMaxDailyTrades       = 20;      // Max trades per day
input double InpDailyProfitTarget    = 10.0;    // Stop after $10 profit
input double InpDailyLossLimit       = -8.0;    // Stop after -$8 loss
input int    InpCooldownMinutes      = 2;       // Wait between trades

input ulong  InpMagic                = 909090;

CTrade        trade;
CPositionInfo pos_info;

int fast_ma_handle, slow_ma_handle, rsi_handle;

// Trading statistics
int daily_trades = 0;
double daily_pnl = 0;
datetime last_trade_time = 0;
datetime current_day = 0;

//====================================================
// INIT
//====================================================
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(10);
   trade.SetAsyncMode(false);
   
   fast_ma_handle = iMA(_Symbol, PERIOD_M1, InpFastMA, 0, MODE_EMA, PRICE_CLOSE);
   slow_ma_handle = iMA(_Symbol, PERIOD_M1, InpSlowMA, 0, MODE_EMA, PRICE_CLOSE);
   rsi_handle = iRSI(_Symbol, PERIOD_M1, InpRSIPeriod, PRICE_CLOSE);
   
   if(fast_ma_handle == INVALID_HANDLE || slow_ma_handle == INVALID_HANDLE || rsi_handle == INVALID_HANDLE)
   {
      Print("❌ INDICATOR INIT FAILED");
      return(INIT_FAILED);
   }
   
   current_day = TimeCurrent() / 86400;
   
   Print("═══════════════════════════════════════");
   Print("⚡ MOMENTUM SCALPER LOADED");
   Print("TP: ", InpTakeProfitPips, " pips | SL: ", InpStopLossPips, " pips");
   Print("Risk:Reward = 1:", InpTakeProfitPips/InpStopLossPips);
   Print("Daily Limit: ", InpMaxDailyTrades, " trades");
   Print("═══════════════════════════════════════");
   
   return(INIT_SUCCEEDED);
}

//====================================================
// DEINIT
//====================================================
void OnDeinit(const int reason)
{
   if(fast_ma_handle != INVALID_HANDLE) IndicatorRelease(fast_ma_handle);
   if(slow_ma_handle != INVALID_HANDLE) IndicatorRelease(slow_ma_handle);
   if(rsi_handle != INVALID_HANDLE) IndicatorRelease(rsi_handle);
}

//====================================================
// GET INDICATORS
//====================================================
bool GetIndicators(double &fast_ma, double &slow_ma, double &rsi)
{
   double fast_arr[1], slow_arr[1], rsi_arr[1];
   
   if(CopyBuffer(fast_ma_handle, 0, 0, 1, fast_arr) <= 0) return false;
   if(CopyBuffer(slow_ma_handle, 0, 0, 1, slow_arr) <= 0) return false;
   if(CopyBuffer(rsi_handle, 0, 0, 1, rsi_arr) <= 0) return false;
   
   fast_ma = fast_arr[0];
   slow_ma = slow_arr[0];
   rsi = rsi_arr[0];
   
   return true;
}

//====================================================
// POSITION MANAGEMENT
//====================================================
void ManagePosition(MqlTick &tick)
{
   if(CountPositions() == 0) return;
   
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      if(pos_info.SelectByIndex(i))
      {
         if(pos_info.Symbol() == _Symbol && pos_info.Magic() == (long)InpMagic)
         {
            double net_profit = pos_info.Profit() + pos_info.Swap() + pos_info.Commission();
            double open_price = pos_info.PriceOpen();
            ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)pos_info.PositionType();
            
            // Calculate pips in profit
            double pips_profit = 0;
            if(type == POSITION_TYPE_BUY)
               pips_profit = (tick.bid - open_price) / GetPipSize();
            else
               pips_profit = (open_price - tick.ask) / GetPipSize();
            
            //================================================
            // QUICK EXIT: At 3 pips profit, move SL to breakeven
            //================================================
            if(pips_profit >= 3.0)
            {
               double breakeven_sl = open_price;
               if(type == POSITION_TYPE_BUY)
                  breakeven_sl = open_price + GetPipSize(); // +1 pip buffer
               else
                  breakeven_sl = open_price - GetPipSize();
               
               if(pos_info.StopLoss() != breakeven_sl)
               {
                  trade.PositionModify(pos_info.Ticket(), breakeven_sl, pos_info.TakeProfit());
               }
            }
            
            //================================================
            // TRAILING STOP: At 4 pips, trail with 2 pip stop
            //================================================
            if(pips_profit >= 4.0)
            {
               double trail_sl = 0;
               double trail_distance = GetPipSize() * 2.0; // 2 pip trail
               
               if(type == POSITION_TYPE_BUY)
                  trail_sl = tick.bid - trail_distance;
               else
                  trail_sl = tick.ask + trail_distance;
               
               if((type == POSITION_TYPE_BUY && trail_sl > pos_info.StopLoss()) ||
                  (type == POSITION_TYPE_SELL && trail_sl < pos_info.StopLoss()))
               {
                  trade.PositionModify(pos_info.Ticket(), trail_sl, pos_info.TakeProfit());
               }
            }
            
            break;
         }
      }
   }
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
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   
   if(digits == 5 || digits == 3)
      return point * 10;
   else
      return point;
}

//====================================================
// RESET DAILY STATS
//====================================================
void CheckNewDay()
{
   datetime new_day = TimeCurrent() / 86400;
   if(new_day != current_day)
   {
      daily_trades = 0;
      daily_pnl = 0;
      current_day = new_day;
      Print("📅 NEW DAY - Stats Reset");
   }
}

//====================================================
// MAIN ENGINE
//====================================================
void OnTick()
{
   CheckNewDay();
   
   // Stop trading if daily limits hit
   if(daily_trades >= InpMaxDailyTrades)
      return;
   if(daily_pnl >= InpDailyProfitTarget)
      return;
   if(daily_pnl <= InpDailyLossLimit)
      return;
   
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      return;
   
   MqlTick current_tick;
   if(!SymbolInfoTick(_Symbol, current_tick))
      return;
   
   // Manage existing position
   ManagePosition(current_tick);
   
   if(CountPositions() >= InpMaxPositions)
      return;
   
   // Cooldown between trades
   if(TimeCurrent() - last_trade_time < InpCooldownMinutes * 60)
      return;
   
   // Check spread
   int spread = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > InpMaxSpread)
      return;
   
   // Check tick volume (liquidity)
   long tick_volume = SymbolInfoInteger(_Symbol, SYMBOL_VOLUME);
   if(tick_volume < InpMinVolume)
      return;
   
   // Get indicators
   double fast_ma, slow_ma, rsi;
   if(!GetIndicators(fast_ma, slow_ma, rsi))
      return;
   
   double pip_size = GetPipSize();
   double sl_price = InpStopLossPips * pip_size;
   double tp_price = InpTakeProfitPips * pip_size;
   
   // Ensure minimum stop distances
   double min_distance = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 2;
   if(sl_price < min_distance) sl_price = min_distance;
   if(tp_price < min_distance) tp_price = min_distance;
   
   //================================================
   // BUY SIGNAL: Fast MA > Slow MA + RSI 40-60 + Pullback
   //================================================
   bool trend_up = (fast_ma > slow_ma);
   bool rsi_zone = (rsi >= 40 && rsi <= 60);
   bool pullback = (current_tick.bid <= fast_ma && current_tick.bid > slow_ma);
   
   if(trend_up && rsi_zone && pullback)
   {
      double sl = current_tick.bid - sl_price;
      double tp = current_tick.bid + tp_price;
      
      if(trade.Buy(InpLotSize, _Symbol, 0, sl, tp, "SCALP_BUY"))
      {
         Print("🟢 BUY | Price: ", current_tick.bid, " | SL: ", sl, " | TP: ", tp);
         daily_trades++;
         last_trade_time = TimeCurrent();
         UpdateDailyPNL();
      }
   }
   
   //================================================
   // SELL SIGNAL: Fast MA < Slow MA + RSI 40-60 + Rally
   //================================================
   bool trend_down = (fast_ma < slow_ma);
   bool rally = (current_tick.ask >= fast_ma && current_tick.ask < slow_ma);
   
   if(trend_down && rsi_zone && rally)
   {
      double sl = current_tick.ask + sl_price;
      double tp = current_tick.ask - tp_price;
      
      if(trade.Sell(InpLotSize, _Symbol, 0, sl, tp, "SCALP_SELL"))
      {
         Print("🔴 SELL | Price: ", current_tick.ask, " | SL: ", sl, " | TP: ", tp);
         daily_trades++;
         last_trade_time = TimeCurrent();
         UpdateDailyPNL();
      }
   }
}

//====================================================
// UPDATE DAILY PNL
//====================================================
void UpdateDailyPNL()
{
   daily_pnl = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      if(pos_info.SelectByIndex(i))
         if(pos_info.Symbol() == _Symbol && pos_info.Magic() == (long)InpMagic)
            daily_pnl += pos_info.Profit() + pos_info.Swap() + pos_info.Commission();
   }
   
   // Also check history for closed trades today
   HistorySelect(TimeCurrent() - 86400, TimeCurrent());
   for(int i = HistoryDealsTotal()-1; i >= 0; i--)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) == InpMagic)
         daily_pnl += HistoryDealGetDouble(ticket, DEAL_PROFIT);
   }
   
   if(daily_pnl >= InpDailyProfitTarget)
      Print("🎯 DAILY PROFIT TARGET HIT: $", DoubleToString(daily_pnl, 2));
   else if(daily_pnl <= InpDailyLossLimit)
      Print("⛔ DAILY LOSS LIMIT HIT: $", DoubleToString(daily_pnl, 2));
}
//+------------------------------------------------------------------+
