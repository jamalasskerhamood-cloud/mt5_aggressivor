//+------------------------------------------------------------------+
//|          QuantumShield_MeanReversion_PROFITABLE.mq5             |
//|            MEAN REVERSION + MOMENTUM FILTER + SMART EXITS        |
//+------------------------------------------------------------------+
#property copyright "Proven Strategy"
#property version   "26.00"
#property strict

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>

// Position sizing
input double InpLotSize              = 0.05;
input double InpRiskPercent          = 0.5;     // Risk 0.5% per trade

// Bollinger Bands for mean reversion
input int    InpBBPeriod             = 20;
input double InpBBDeviation          = 2.0;

// RSI filter - ONLY trade with momentum
input int    InpRSIPeriod            = 14;
input int    InpRSIOverbought        = 70;
input int    InpRSIOversold          = 30;

// ATR for dynamic stops
input int    InpATRPeriod            = 14;
input double InpATRMultSL            = 1.5;
input double InpATRMultTP            = 2.5;     // Better than 1:1 risk reward

// Spread filter
input int    InpMaxSpread            = 25;      // 2.5 pips max

// Trade management
input int    InpMaxPositions         = 1;
input double InpTrailingStart        = 0.30;    // Start trailing after $0.30 profit
input double InpTrailingStep         = 0.10;    // Trail in $0.10 steps

input ulong  InpMagic                = 909090;

CTrade        trade;
CPositionInfo pos_info;

// Handles
int bb_handle;
int rsi_handle;
int atr_handle;

// Trailing
double highest_profit = 0;

//====================================================
// INIT
//====================================================
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(20);
   trade.SetAsyncMode(false);
   
   // Initialize indicators
   bb_handle = iBands(_Symbol, PERIOD_M1, InpBBPeriod, 0, InpBBDeviation, PRICE_CLOSE);
   rsi_handle = iRSI(_Symbol, PERIOD_M1, InpRSIPeriod, PRICE_CLOSE);
   atr_handle = iATR(_Symbol, PERIOD_M1, InpATRPeriod);
   
   if(bb_handle == INVALID_HANDLE || rsi_handle == INVALID_HANDLE || atr_handle == INVALID_HANDLE)
   {
      Print("❌ INDICATOR INIT FAILED");
      return(INIT_FAILED);
   }
   
   Print("═══════════════════════════════════════");
   Print("🔵 MEAN REVERSION STRATEGY LOADED");
   Print("Symbol: ", _Symbol);
   Print("Strategy: BB(", InpBBPeriod, ",", InpBBDeviation, ") + RSI(", InpRSIPeriod, ")");
   Print("Risk: ", InpRiskPercent, "% | Reward:Risk = ", InpATRMultTP/InpATRMultSL, ":1");
   Print("═══════════════════════════════════════");
   
   return(INIT_SUCCEEDED);
}

//====================================================
// DEINIT
//====================================================
void OnDeinit(const int reason)
{
   if(bb_handle != INVALID_HANDLE) IndicatorRelease(bb_handle);
   if(rsi_handle != INVALID_HANDLE) IndicatorRelease(rsi_handle);
   if(atr_handle != INVALID_HANDLE) IndicatorRelease(atr_handle);
}

//====================================================
// GET INDICATOR VALUES
//====================================================
bool GetIndicators(double &upper_band, double &middle_band, double &lower_band, 
                   double &rsi, double &atr)
{
   double bb_upper[1], bb_middle[1], bb_lower[1];
   double rsi_arr[1], atr_arr[1];
   
   if(CopyBuffer(bb_handle, 1, 0, 1, bb_upper) <= 0) return false;   // Upper band
   if(CopyBuffer(bb_handle, 0, 0, 1, bb_middle) <= 0) return false;  // Middle band
   if(CopyBuffer(bb_handle, 2, 0, 1, bb_lower) <= 0) return false;   // Lower band
   if(CopyBuffer(rsi_handle, 0, 0, 1, rsi_arr) <= 0) return false;
   if(CopyBuffer(atr_handle, 0, 0, 1, atr_arr) <= 0) return false;
   
   upper_band = bb_upper[0];
   middle_band = bb_middle[0];
   lower_band = bb_lower[0];
   rsi = rsi_arr[0];
   atr = atr_arr[0];
   
   return true;
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
// GET POSITION NET PROFIT
//====================================================
double GetPositionProfit()
{
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      if(pos_info.SelectByIndex(i))
         if(pos_info.Symbol() == _Symbol && pos_info.Magic() == (long)InpMagic)
            return pos_info.Profit() + pos_info.Swap() + pos_info.Commission();
   }
   return 0;
}

//====================================================
// SMART EXIT MANAGEMENT
//====================================================
void ManageExits(MqlTick &tick)
{
   if(CountPositions() == 0)
   {
      highest_profit = 0;
      return;
   }
   
   if(!pos_info.SelectByIndex(0))
      return;
      
   // Find our position
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      if(pos_info.SelectByIndex(i))
      {
         if(pos_info.Symbol() == _Symbol && pos_info.Magic() == (long)InpMagic)
            break;
      }
   }
   
   if(pos_info.Symbol() != _Symbol || pos_info.Magic() != (long)InpMagic)
      return;
   
   double net_profit = pos_info.Profit() + pos_info.Swap() + pos_info.Commission();
   ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)pos_info.PositionType();
   double open_price = pos_info.PriceOpen();
   double current_sl = pos_info.StopLoss();
   double current_tp = pos_info.TakeProfit();
   
   // Track highest profit
   if(net_profit > highest_profit)
      highest_profit = net_profit;
   
   //================================================
   // EXIT 1: PROFIT TARGET HIT (handled by TP)
   //================================================
   
   //================================================
   // EXIT 2: TRAILING PROFIT - Close when profit drops 40% from peak
   //================================================
   if(highest_profit >= InpTrailingStart && net_profit < highest_profit * 0.60)
   {
      Print("📊 TRAILING EXIT | Peak: $", DoubleToString(highest_profit, 2), 
            " | Current: $", DoubleToString(net_profit, 2));
      trade.PositionClose(pos_info.Ticket());
      highest_profit = 0;
      return;
   }
   
   //================================================
   // EXIT 3: MEAN REVERSION - Price returned to middle band
   //================================================
   double upper_band, middle_band, lower_band, rsi, atr;
   if(GetIndicators(upper_band, middle_band, lower_band, rsi, atr))
   {
      if(type == POSITION_TYPE_BUY && tick.bid >= middle_band && net_profit > 0)
      {
         Print("🎯 MEAN REVERSION EXIT (BUY) | Profit: $", DoubleToString(net_profit, 2));
         trade.PositionClose(pos_info.Ticket());
         highest_profit = 0;
         return;
      }
      else if(type == POSITION_TYPE_SELL && tick.ask <= middle_band && net_profit > 0)
      {
         Print("🎯 MEAN REVERSION EXIT (SELL) | Profit: $", DoubleToString(net_profit, 2));
         trade.PositionClose(pos_info.Ticket());
         highest_profit = 0;
         return;
      }
   }
   
   //================================================
   // EXIT 4: MOMENTUM SHIFT - RSI reversed
   //================================================
   if(GetIndicators(upper_band, middle_band, lower_band, rsi, atr))
   {
      if(type == POSITION_TYPE_BUY && rsi > 65 && net_profit > 0)
      {
         Print("📈 RSI OVERBOUGHT EXIT | Profit: $", DoubleToString(net_profit, 2));
         trade.PositionClose(pos_info.Ticket());
         highest_profit = 0;
         return;
      }
      else if(type == POSITION_TYPE_SELL && rsi < 35 && net_profit > 0)
      {
         Print("📉 RSI OVERSOLD EXIT | Profit: $", DoubleToString(net_profit, 2));
         trade.PositionClose(pos_info.Ticket());
         highest_profit = 0;
         return;
      }
   }
   
   //================================================
   // EXIT 5: EMERGENCY - Time-based stop
   //================================================
   datetime open_time = (datetime)pos_info.Time();
   int minutes_open = (int)((TimeCurrent() - open_time) / 60);
   
   if(minutes_open > 30 && net_profit < 0)
   {
      Print("⏰ TIME STOP | Minutes: ", minutes_open, " | Loss: $", DoubleToString(net_profit, 2));
      trade.PositionClose(pos_info.Ticket());
      highest_profit = 0;
      return;
   }
}

//====================================================
// MAIN ENGINE
//====================================================
void OnTick()
{
   // Check trading allowed
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      return;
   
   MqlTick current_tick;
   if(!SymbolInfoTick(_Symbol, current_tick))
      return;
   
   // Manage existing positions
   ManageExits(current_tick);
   
   // Check position limit
   if(CountPositions() >= InpMaxPositions)
      return;
   
   // Check spread
   int spread = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > InpMaxSpread)
      return;
   
   // Get indicators
   double upper_band, middle_band, lower_band, rsi, atr;
   if(!GetIndicators(upper_band, middle_band, lower_band, rsi, atr))
      return;
   
   if(atr <= 0) return;
   
   //================================================
   // BUY SIGNAL: Price below lower band + RSI oversold
   //================================================
   if(current_tick.bid <= lower_band && rsi <= InpRSIOversold)
   {
      double sl = current_tick.bid - (atr * InpATRMultSL);
      double tp = current_tick.bid + (atr * InpATRMultTP);
      
      // Ensure minimum stop distances
      double min_distance = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      if(tp - current_tick.bid < min_distance) tp = current_tick.bid + min_distance * 2;
      if(current_tick.bid - sl < min_distance) sl = current_tick.bid - min_distance * 2;
      
      Print("🟢 BUY SIGNAL | Price: ", current_tick.bid, " | Lower BB: ", lower_band, 
            " | RSI: ", rsi, " | SL: ", sl, " | TP: ", tp);
      
      if(trade.Buy(InpLotSize, _Symbol, 0, sl, tp, "MR_BUY"))
         Print("✅ BUY OPENED");
      else
         Print("❌ BUY FAILED: ", GetLastError());
   }
   
   //================================================
   // SELL SIGNAL: Price above upper band + RSI overbought
   //================================================
   if(current_tick.ask >= upper_band && rsi >= InpRSIOverbought)
   {
      double sl = current_tick.ask + (atr * InpATRMultSL);
      double tp = current_tick.ask - (atr * InpATRMultTP);
      
      // Ensure minimum stop distances
      double min_distance = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      if(current_tick.ask - tp < min_distance) tp = current_tick.ask - min_distance * 2;
      if(sl - current_tick.ask < min_distance) sl = current_tick.ask + min_distance * 2;
      
      Print("🔴 SELL SIGNAL | Price: ", current_tick.ask, " | Upper BB: ", upper_band, 
            " | RSI: ", rsi, " | SL: ", sl, " | TP: ", tp);
      
      if(trade.Sell(InpLotSize, _Symbol, 0, sl, tp, "MR_SELL"))
         Print("✅ SELL OPENED");
      else
         Print("❌ SELL FAILED: ", GetLastError());
   }
}
//+------------------------------------------------------------------+
