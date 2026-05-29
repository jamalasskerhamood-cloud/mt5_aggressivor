//+------------------------------------------------------------------+
//|          QuantumShield_AGGRESSIVE_SCALPER_PROFIT.mq5             |
//|            ULTRA AGGRESSIVE + TIGHT STOPS + ACTIVE TRADING       |
//+------------------------------------------------------------------+
#property copyright "Aggressive Scalping Strategy"
#property version   "28.00"
#property strict

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>

input double InpLotSize              = 0.05;

// TIGHT EXITS - Keep this protection
input double InpTakeProfitPips       = 5.0;
input double InpStopLossPips         = 4.0;

// MINIMAL FILTERS - Just enough to avoid suicide
input int    InpMaxSpread            = 30;      // 3 pips - wider to allow more trades
input int    InpRSIPeriod            = 7;

// AGGRESSIVE SETTINGS
input int    InpMaxPositions         = 2;       // Allow 2 positions
input int    InpCooldownSeconds      = 30;      // Only 30 seconds between trades
input bool   InpTradeAgainstTrend    = true;    // Trade both directions

input ulong  InpMagic                = 909090;

CTrade        trade;
CPositionInfo pos_info;

int rsi_handle;
datetime last_trade_time = 0;
int trades_this_minute = 0;
datetime current_minute = 0;

//====================================================
// INIT
//====================================================
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(20);
   trade.SetAsyncMode(false);
   
   rsi_handle = iRSI(_Symbol, PERIOD_M1, InpRSIPeriod, PRICE_CLOSE);
   
   Print("═══════════════════════════════════════");
   Print("⚡ AGGRESSIVE SCALPER LOADED");
   Print("TP: ", InpTakeProfitPips, " pips | SL: ", InpStopLossPips, " pips");
   Print("Max Spread: ", InpMaxSpread, " points");
   Print("Max Positions: ", InpMaxPositions);
   Print("Cooldown: ", InpCooldownSeconds, " seconds");
   Print("Trade Against Trend: ", InpTradeAgainstTrend ? "YES" : "NO");
   Print("═══════════════════════════════════════");
   
   return(INIT_SUCCEEDED);
}

//====================================================
// DEINIT
//====================================================
void OnDeinit(const int reason)
{
   if(rsi_handle != INVALID_HANDLE) IndicatorRelease(rsi_handle);
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
// POSITION MANAGEMENT
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
      double open_price = pos_info.PriceOpen();
      double current_sl = pos_info.StopLoss();
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)pos_info.PositionType();
      
      // Calculate pips profit
      double pips_profit = 0;
      if(type == POSITION_TYPE_BUY)
         pips_profit = (tick.bid - open_price) / GetPipSize();
      else
         pips_profit = (open_price - tick.ask) / GetPipSize();
      
      //================================================
      // BREAKEVEN AT 3 PIPS
      //================================================
      if(pips_profit >= 3.0 && current_sl != open_price)
      {
         double breakeven_sl = open_price;
         if(type == POSITION_TYPE_BUY)
            breakeven_sl = open_price + (GetPipSize() * 0.5); // +0.5 pip buffer
         else
            breakeven_sl = open_price - (GetPipSize() * 0.5);
         
         trade.PositionModify(pos_info.Ticket(), breakeven_sl, pos_info.TakeProfit());
      }
      
      //================================================
      // TRAILING STOP AT 4 PIPS
      //================================================
      if(pips_profit >= 4.0)
      {
         double trail_distance = GetPipSize() * 2.0; // 2 pip trail
         double trail_sl = 0;
         
         if(type == POSITION_TYPE_BUY)
            trail_sl = tick.bid - trail_distance;
         else
            trail_sl = tick.ask + trail_distance;
         
         if((type == POSITION_TYPE_BUY && trail_sl > current_sl) ||
            (type == POSITION_TYPE_SELL && trail_sl < current_sl))
         {
            trade.PositionModify(pos_info.Ticket(), trail_sl, pos_info.TakeProfit());
         }
      }
      
      //================================================
      // CLOSE IF REVERSING (protect tiny profits)
      //================================================
      if(net_profit > 0.02 && net_profit < 0.10)
      {
         // Close if price moved 2 pips against us from peak
         double peak_distance = (pips_profit >= 2.0) ? pips_profit - 2.0 : 0;
         if(peak_distance <= 0.5)
         {
            Print("🛡️ PROTECTIVE CLOSE | Profit: $", DoubleToString(net_profit, 3));
            trade.PositionClose(pos_info.Ticket());
            continue;
         }
      }
   }
}

//====================================================
// MAIN ENGINE
//====================================================
void OnTick()
{
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      return;
   
   MqlTick current_tick;
   if(!SymbolInfoTick(_Symbol, current_tick))
      return;
   
   // Manage positions
   ManagePositions(current_tick);
   
   // Reset trades per minute counter
   if(TimeCurrent() / 60 != current_minute / 60)
   {
      trades_this_minute = 0;
      current_minute = TimeCurrent();
   }
   
   // Check max positions
   if(CountPositions() >= InpMaxPositions)
      return;
   
   // Limit trades per minute (max 4 per minute)
   if(trades_this_minute >= 4)
      return;
   
   // Short cooldown
   if(TimeCurrent() - last_trade_time < InpCooldownSeconds)
      return;
   
   // Check spread - WIDER tolerance
   int spread = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > InpMaxSpread)
      return;
   
   // Get RSI
   double rsi_arr[1];
   double rsi = 50; // Default neutral
   if(CopyBuffer(rsi_handle, 0, 0, 1, rsi_arr) > 0)
      rsi = rsi_arr[0];
   
   double pip_size = GetPipSize();
   double sl_distance = InpStopLossPips * pip_size;
   double tp_distance = InpTakeProfitPips * pip_size;
   
   // Ensure minimum distances
   double min_stops = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(sl_distance < min_stops) sl_distance = min_stops * 1.5;
   if(tp_distance < min_stops) tp_distance = min_stops * 1.5;
   
   //================================================
   // PRICE MOMENTUM - The trigger
   //================================================
   static double last_bid = 0;
   static double last_ask = 0;
   
   if(last_bid == 0)
   {
      last_bid = current_tick.bid;
      last_ask = current_tick.ask;
      return;
   }
   
   double bid_change = current_tick.bid - last_bid;
   double ask_change = current_tick.ask - last_ask;
   
   //================================================
   // BUY SIGNAL - Any upward movement
   //================================================
   bool buy_signal = false;
   
   // SIMPLE: Price moving up
   if(bid_change > 0 && InpTradeAgainstTrend)
      buy_signal = true;
   
   // With RSI filter (not overbought)
   if(bid_change > 0 && rsi < 65)
      buy_signal = true;
   
   if(buy_signal)
   {
      double sl = current_tick.bid - sl_distance;
      double tp = current_tick.bid + tp_distance;
      
      if(trade.Buy(InpLotSize, _Symbol, 0, sl, tp, "AGGRO_BUY"))
      {
         Print("🟢 BUY | Bid: ", current_tick.bid, 
               " | Change: ", DoubleToString(bid_change/GetPipSize(), 1), " pips",
               " | RSI: ", DoubleToString(rsi, 1),
               " | SL: ", DoubleToString(sl, 5),
               " | TP: ", DoubleToString(tp, 5));
         trades_this_minute++;
         last_trade_time = TimeCurrent();
      }
   }
   
   //================================================
   // SELL SIGNAL - Any downward movement
   //================================================
   bool sell_signal = false;
   
   // SIMPLE: Price moving down
   if(ask_change < 0 && InpTradeAgainstTrend)
      sell_signal = true;
   
   // With RSI filter (not oversold)
   if(ask_change < 0 && rsi > 35)
      sell_signal = true;
   
   if(sell_signal)
   {
      double sl = current_tick.ask + sl_distance;
      double tp = current_tick.ask - tp_distance;
      
      if(trade.Sell(InpLotSize, _Symbol, 0, sl, tp, "AGGRO_SELL"))
      {
         Print("🔴 SELL | Ask: ", current_tick.ask, 
               " | Change: ", DoubleToString(ask_change/GetPipSize(), 1), " pips",
               " | RSI: ", DoubleToString(rsi, 1),
               " | SL: ", DoubleToString(sl, 5),
               " | TP: ", DoubleToString(tp, 5));
         trades_this_minute++;
         last_trade_time = TimeCurrent();
      }
   }
   
   last_bid = current_tick.bid;
   last_ask = current_tick.ask;
}
//+------------------------------------------------------------------+
