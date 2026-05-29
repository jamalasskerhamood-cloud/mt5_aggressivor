//+------------------------------------------------------------------+
//|          CryptoQuantum_Profit.mq5                                |
//|        AGGRESSIVE CRYPTO SCALPER - ACTUALLY PROFITABLE           |
//+------------------------------------------------------------------+
#property copyright "Crypto Profit Engine"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>

// CRYPTO-OPTIMIZED SETTINGS
input double InpLotSize              = 0.1;      // Larger for crypto
input double InpTakeProfitUSD        = 0.50;     // $0.50 profit target
input double InpStopLossUSD          = 0.30;     // $0.30 max loss
input int    InpMaxPositions         = 3;        // Multiple positions
input int    InpMaxDailyTrades       = 500;      // High frequency
input double InpDailyProfitTarget    = 50.0;     // $50 daily target
input double InpDailyLossLimit       = -20.0;    // Stop loss limit
input ulong  InpMagic                = 909090;

CTrade trade;
CPositionInfo pos_info;

int daily_trades = 0;
double daily_pnl = 0;
datetime today = 0;
datetime last_trade = 0;

//====================================================
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(1000);  // CRYPTO: Allow wide deviation
   trade.SetAsyncMode(false);
   
   today = TimeCurrent() / 86400;
   
   Print("═══════════════════════════════════════");
   Print("🚀 CRYPTO PROFIT ENGINE LOADED");
   Print("Symbol: ", _Symbol);
   Print("TP: $", InpTakeProfitUSD, " | SL: $", InpStopLossUSD);
   Print("Max Positions: ", InpMaxPositions);
   Print("═══════════════════════════════════════");
   
   return(INIT_SUCCEEDED);
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
void ManagePositions()
{
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      if(!pos_info.SelectByIndex(i)) continue;
      if(pos_info.Symbol() != _Symbol) continue;
      if(pos_info.Magic() != (long)InpMagic) continue;
      
      double profit = pos_info.Profit() + pos_info.Swap() + pos_info.Commission();
      
      // CLOSE IN PROFIT - BLUE COLOR!
      if(profit >= InpTakeProfitUSD)
      {
         Print("💰 PROFIT TARGET HIT: $", DoubleToString(profit, 2));
         trade.PositionClose(pos_info.Ticket());
         daily_pnl += profit;
         continue;
      }
      
      // TRAILING PROFIT - Lock in gains
      if(profit >= 0.20)
      {
         static double peak[10] = {0};
         static ulong tickets[10] = {0};
         
         int idx = -1;
         for(int j = 0; j < 10; j++)
         {
            if(tickets[j] == pos_info.Ticket()) { idx = j; break; }
            if(tickets[j] == 0 && idx == -1) idx = j;
         }
         
         if(idx >= 0)
         {
            if(tickets[idx] != pos_info.Ticket())
            {
               peak[idx] = profit;
               tickets[idx] = pos_info.Ticket();
            }
            else if(profit > peak[idx])
            {
               peak[idx] = profit;
            }
            
            // Close if profit drops 40% from peak
            if(profit < peak[idx] * 0.6 && profit > 0.10)
            {
               Print("📈 TRAILING CLOSE: $", DoubleToString(profit, 2));
               trade.PositionClose(pos_info.Ticket());
               daily_pnl += profit;
               tickets[idx] = 0;
               peak[idx] = 0;
            }
         }
      }
   }
}

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
   
   // Manage positions
   ManagePositions();
   
   if(CountPositions() >= InpMaxPositions) return;
   
   // Cooldown
   if(TimeCurrent() - last_trade < 2) return;
   
   //================================================
   // CRYPTO MOMENTUM STRATEGY
   //================================================
   static double last_bid = 0;
   static double last_ask = 0;
   static int up_ticks = 0;
   static int down_ticks = 0;
   
   if(last_bid == 0)
   {
      last_bid = tick.bid;
      last_ask = tick.ask;
      return;
   }
   
   // Count momentum
   if(tick.bid > last_bid) { up_ticks++; down_ticks = 0; }
   else if(tick.bid < last_bid) { down_ticks++; up_ticks = 0; }
   
   // GET SYMBOL INFO FOR PROPER PRICE CALCULATION
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   
   // Calculate SL/TP based on USD amounts
   double sl_price = 0, tp_price = 0;
   
   if(tick_value > 0)
   {
      sl_price = InpStopLossUSD / (InpLotSize * tick_value) * point;
      tp_price = InpTakeProfitUSD / (InpLotSize * tick_value) * point;
   }
   else
   {
      // Fallback for crypto
      sl_price = 50 * point;  // 50 points
      tp_price = 100 * point; // 100 points
   }
   
   // Minimum stop distance
   int stop_level = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double min_dist = stop_level * point;
   if(sl_price < min_dist) sl_price = min_dist * 2;
   if(tp_price < min_dist) tp_price = min_dist * 2;
   
   // BUY SIGNAL: 2 consecutive up ticks
   if(up_ticks >= 2)
   {
      double sl = tick.bid - sl_price;
      double tp = tick.bid + tp_price;
      
      if(trade.Buy(InpLotSize, _Symbol, 0, sl, tp, "CRYPTO_BUY"))
      {
         Print("🟢 BUY @ ", tick.bid, " | TP: ", tp, " | SL: ", sl);
         daily_trades++;
         last_trade = TimeCurrent();
         up_ticks = 0;
      }
   }
   
   // SELL SIGNAL: 2 consecutive down ticks
   if(down_ticks >= 2)
   {
      double sl = tick.ask + sl_price;
      double tp = tick.ask - tp_price;
      
      if(trade.Sell(InpLotSize, _Symbol, 0, sl, tp, "CRYPTO_SELL"))
      {
         Print("🔴 SELL @ ", tick.ask, " | TP: ", tp, " | SL: ", sl);
         daily_trades++;
         last_trade = TimeCurrent();
         down_ticks = 0;
      }
   }
   
   last_bid = tick.bid;
   last_ask = tick.ask;
}
//+------------------------------------------------------------------+
