//+------------------------------------------------------------------+
//| CRYPTO_NEWS_SENTIMENT_EA_v2.mq5                                  |
//| Free News Sentiment Strategy - No API Key Required               |
//| Uses cryptocurrency.cv free API (200+ sources, unlimited)        |
//+------------------------------------------------------------------+
#property copyright "News Sentiment Strategy"
#property version "2.0"
#property strict

#include <Trade/Trade.mqh>
#include <JSON.mqh>  // You'll need to download this from MQL5.com

//=== INPUTS ========================================================
input group "=== API Settings ==="
input string   InpNewsURL = "https://cryptocurrency.cv/api/news";  // Free news API
input int      InpRefreshMinutes = 5;           // Refresh news every 5 minutes
input int      InpMaxArticles = 30;             // Max articles to analyze per fetch

input group "=== Keyword Scoring ==="
// Bearish/Fear keywords (oversold = BUY signal - Contrarian)
input string   InpFearKeywords = "crash,sell,dead,crackdown,liquidation,panic,capitulation,plunge";
// Bullish/Greed keywords (overbought = SELL signal - Contrarian)
input string   InpGreedKeywords = "moon,mooning,ath,all time high,bull run,hodl,pump,skyrocket,fomo";

input group "=== Sentiment Thresholds ==="
input double   InpBuyThreshold = -0.3;          // BUY when sentiment <= -0.3
input double   InpSellThreshold = 0.3;          // SELL when sentiment >= 0.3
input int      InpMinKeywordMatches = 2;        // Minimum keywords to trigger

input group "=== Risk Management ==="
input double   InpRiskPercent = 0.5;            // Risk 0.5% per trade
input double   InpATRMultiplierSL = 1.5;        // Stop = ATR * 1.5
input double   InpATRMultiplierTP = 2.5;        // Take = ATR * 2.5
input int      InpATRPeriod = 14;
input int      InpMaxDailyTrades = 5;
input int      InpMagicNumber = 888999;

input group "=== Technical Filter ==="
input bool     InpUseTrendFilter = true;        // Only trade with 200 EMA trend
input int      InpTrendEMA = 200;

//=== GLOBAL VARIABLES ==============================================
CTrade trade;
int atrHandle, trendHandle;
datetime lastNewsFetch;
datetime currentDay;
int dailyTrades;
double currentSentiment;
int fearMatchCount;
int greedMatchCount;
string lastNewsHeadline;

// Keyword arrays
string fearKeywords[];
string greedKeywords[];

//+------------------------------------------------------------------+
//| INITIALIZATION                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Create indicators
   atrHandle = iATR(_Symbol, PERIOD_CURRENT, InpATRPeriod);
   trendHandle = iMA(_Symbol, PERIOD_CURRENT, InpTrendEMA, 0, MODE_EMA, PRICE_CLOSE);
   
   if(atrHandle == INVALID_HANDLE || trendHandle == INVALID_HANDLE)
   {
      Print("❌ Indicator creation failed");
      return INIT_FAILED;
   }
   
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(50);
   
   // Parse keyword inputs into arrays
   ParseKeywords(InpFearKeywords, fearKeywords);
   ParseKeywords(InpGreedKeywords, greedKeywords);
   
   Print("╔══════════════════════════════════════════════════════════════╗");
   Print("║     CRYPTO NEWS SENTIMENT EA - FULLY FREE                    ║");
   Print("║     News Source: cryptocurrency.cv (200+ sources)            ║");
   Print("║     No API Key Required | Unlimited Requests                 ║");
   Print("║     Strategy: Contrarian Sentiment Trading                   ║");
   Print("╚══════════════════════════════════════════════════════════════╝");
   Print("");
   Print("📋 FEAR Keywords (", ArraySize(fearKeywords), "): ", InpFearKeywords);
   Print("📋 GREED Keywords (", ArraySize(greedKeywords), "): ", InpGreedKeywords);
   Print("");
   
   // Initial news fetch
   FetchNewsAndAnalyze();
   lastNewsFetch = TimeCurrent();
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| PARSE KEYWORDS FROM INPUT STRING                                 |
//+------------------------------------------------------------------+
void ParseKeywords(string input, string &output[])
{
   string temp[];
   int count = StringSplit(input, ',', temp);
   ArrayResize(output, count);
   
   for(int i = 0; i < count; i++)
   {
      output[i] = StringTrim(StringLower(temp[i]));
   }
}

//+------------------------------------------------------------------+
//| MAIN ONTICK                                                      |
//+------------------------------------------------------------------+
void OnTick()
{
   // Daily reset
   datetime today = TimeCurrent() / 86400;
   if(today != currentDay)
   {
      currentDay = today;
      dailyTrades = 0;
      Print("📅 New trading day - Sentiment monitoring active");
   }
   
   // Trade limits
   if(dailyTrades >= InpMaxDailyTrades) return;
   if(PositionsTotal() >= 1) return;
   
   // Refresh news periodically
   if(TimeCurrent() - lastNewsFetch >= InpRefreshMinutes * 60)
   {
      FetchNewsAndAnalyze();
      lastNewsFetch = TimeCurrent();
   }
   
   // Get trading signal from sentiment
   int signal = GetSentimentSignal();
   
   if(signal != 0)
   {
      ExecuteTrade(signal);
   }
}

//+------------------------------------------------------------------+
//| FETCH NEWS AND ANALYZE SENTIMENT                                 |
//+------------------------------------------------------------------+
void FetchNewsAndAnalyze()
{
   string response = FetchNewsFromAPI();
   
   if(response == "")
   {
      Print("⚠️ Failed to fetch news. Using cached sentiment.");
      return;
   }
   
   // Reset counters
   fearMatchCount = 0;
   greedMatchCount = 0;
   double totalSentiment = 0;
   int articlesAnalyzed = 0;
   
   // Simple parsing - look for titles in the JSON response
   // The API returns each article with a "title" field
   
   int titlePos = 0;
   int articlesChecked = 0;
   
   while(titlePos >= 0 && articlesChecked < InpMaxArticles)
   {
      titlePos = StringFind(response, "\"title\":\"", titlePos);
      if(titlePos < 0) break;
      
      titlePos += 9; // Move past "title":"
      int endPos = StringFind(response, "\",", titlePos);
      if(endPos < 0) endPos = StringFind(response, "\"}", titlePos);
      if(endPos < 0) break;
      
      string title = StringSubstr(response, titlePos, endPos - titlePos);
      title = StringReplace(title, "\\u0026", "&");
      title = StringReplace(title, "\\\"", "\"");
      
      // Analyze this headline
      AnalyzeHeadline(title);
      articlesAnalyzed++;
      articlesChecked++;
   }
   
   // Calculate overall sentiment (-1 to +1)
   int totalMatches = fearMatchCount + greedMatchCount;
   if(totalMatches > 0)
   {
      currentSentiment = (greedMatchCount - fearMatchCount) / (double)totalMatches;
   }
   else
   {
      currentSentiment = 0;
   }
   
   Print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
   Print("📰 NEWS SENTIMENT UPDATE - ", TimeToString(TimeCurrent()));
   Print("   Articles Analyzed: ", articlesAnalyzed);
   Print("   Fear Keywords Found: ", fearMatchCount);
   Print("   Greed Keywords Found: ", greedMatchCount);
   Print("   Sentiment Score: ", DoubleToString(currentSentiment, 2), " (-1=Fear, +1=Greed)");
   
   if(currentSentiment <= InpBuyThreshold)
      Print("   🔴 SIGNAL: EXTREME FEAR -> Contrarian BUY signal");
   else if(currentSentiment >= InpSellThreshold)
      Print("   🟢 SIGNAL: EXTREME GREED -> Contrarian SELL signal");
   else
      Print("   ⚪ SIGNAL: NEUTRAL - No trade");
   
   Print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
}

//+------------------------------------------------------------------+
//| FETCH NEWS FROM FREE API                                         |
//+------------------------------------------------------------------+
string FetchNewsFromAPI()
{
   string url = InpNewsURL;
   char result[];
   string headers;
   
   // WebRequest must be enabled in MT5 settings
   int res = WebRequest("GET", url, "", "", 5000, result, headers);
   
   if(res != 200)
   {
      Print("WebRequest error: ", res);
      return "";
   }
   
   string data = CharArrayToString(result);
   return data;
}

//+------------------------------------------------------------------+
//| ANALYZE HEADLINE FOR KEYWORDS                                    |
//+------------------------------------------------------------------+
void AnalyzeHeadline(string headline)
{
   string lowerHeadline = StringLower(headline);
   
   // Check fear keywords
   for(int i = 0; i < ArraySize(fearKeywords); i++)
   {
      if(StringFind(lowerHeadline, fearKeywords[i]) >= 0)
      {
         fearMatchCount++;
         Print("   🔍 FEAR keyword found: '", fearKeywords[i], "' in: ", headline);
         break; // Count once per article
      }
   }
   
   // Check greed keywords
   for(int i = 0; i < ArraySize(greedKeywords); i++)
   {
      if(StringFind(lowerHeadline, greedKeywords[i]) >= 0)
      {
         greedMatchCount++;
         Print("   🔍 GREED keyword found: '", greedKeywords[i], "' in: ", headline);
         break; // Count once per article
      }
   }
}

//+------------------------------------------------------------------+
//| GET TRADING SIGNAL FROM SENTIMENT                                |
//+------------------------------------------------------------------+
int GetSentimentSignal()
{
   int totalMatches = fearMatchCount + greedMatchCount;
   
   // Need minimum keyword matches for confidence
   if(totalMatches < InpMinKeywordMatches)
      return 0;
   
   // Get technical indicators
   double atrBuf[1], trendBuf[1];
   if(CopyBuffer(atrHandle, 0, 1, 1, atrBuf) < 1) return 0;
   if(CopyBuffer(trendHandle, 0, 1, 1, trendBuf) < 1) return 0;
   
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double trendEMA = trendBuf[0];
   
   bool uptrend = (currentPrice > trendEMA);
   bool downtrend = (currentPrice < trendEMA);
   
   // CONTRARIAN LOGIC: Fear = BUY, Greed = SELL
   if(currentSentiment <= InpBuyThreshold)  // Extreme fear -> BUY
   {
      if(!InpUseTrendFilter || (InpUseTrendFilter && uptrend))
      {
         Print("🎯 TRADE SIGNAL: BUY");
         Print("   Sentiment: ", DoubleToString(currentSentiment, 2), " (Fear)");
         Print("   Fear Keywords: ", fearMatchCount, " | Greed: ", greedMatchCount);
         return 1;
      }
   }
   else if(currentSentiment >= InpSellThreshold)  // Extreme greed -> SELL
   {
      if(!InpUseTrendFilter || (InpUseTrendFilter && downtrend))
      {
         Print("🎯 TRADE SIGNAL: SELL");
         Print("   Sentiment: ", DoubleToString(currentSentiment, 2), " (Greed)");
         Print("   Fear Keywords: ", fearMatchCount, " | Greed: ", greedMatchCount);
         return -1;
      }
   }
   
   return 0;
}

//+------------------------------------------------------------------+
//| EXECUTE TRADE                                                    |
//+------------------------------------------------------------------+
void ExecuteTrade(int signal)
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return;
   
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   // Get ATR for dynamic stops
   double atrBuf[1];
   if(CopyBuffer(atrHandle, 0, 1, 1, atrBuf) < 1) return;
   double atr = atrBuf[0];
   
   double slDistance = atr * InpATRMultiplierSL;
   double tpDistance = atr * InpATRMultiplierTP;
   
   // Position sizing
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = accountBalance * (InpRiskPercent / 100.0);
   double lotSize = riskAmount / slDistance;
   
   // Normalize lot size
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   if(lotSize < minLot) lotSize = minLot;
   if(lotSize > maxLot) lotSize = maxLot;
   if(lotStep > 0) lotSize = MathRound(lotSize / lotStep) * lotStep;
   
   double sl, tp;
   bool success = false;
   string comment = "";
   
   if(signal == 1)  // BUY (Fear)
   {
      sl = tick.ask - slDistance;
      tp = tick.ask + tpDistance;
      comment = StringFormat("NEWS_FEAR_%.2f", currentSentiment);
      success = trade.Buy(lotSize, _Symbol, 0, sl, tp, comment);
   }
   else if(signal == -1)  // SELL (Greed)
   {
      sl = tick.bid + slDistance;
      tp = tick.bid - tpDistance;
      comment = StringFormat("NEWS_GREED_%.2f", currentSentiment);
      success = trade.Sell(lotSize, _Symbol, 0, sl, tp, comment);
   }
   
   if(success)
   {
      Print("✅ ORDER EXECUTED");
      Print("   Sentiment Score: ", DoubleToString(currentSentiment, 2));
      Print("   Fear/Greed: ", fearMatchCount, "/", greedMatchCount);
      dailyTrades++;
   }
   else
   {
      Print("❌ Order failed | Error: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| HELPER: String to lowercase                                      |
//+------------------------------------------------------------------+
string StringLower(string str)
{
   string result = "";
   for(int i = 0; i < StringLen(str); i++)
   {
      ushort ch = StringGetChar(str, i);
      if(ch >= 65 && ch <= 90) ch += 32;
      result += CharToString(ch);
   }
   return result;
}

//+------------------------------------------------------------------+
//| HELPER: String Replace All                                       |
//+------------------------------------------------------------------+
string StringReplace(string str, string find, string replace)
{
   int pos = 0;
   while((pos = StringFind(str, find, pos)) >= 0)
   {
      str = StringSubstr(str, 0, pos) + replace + StringSubstr(str, pos + StringLen(find));
      pos += StringLen(replace);
   }
   return str;
}

//+------------------------------------------------------------------+
//| DEINITIALIZATION                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(atrHandle != INVALID_HANDLE) IndicatorRelease(atrHandle);
   if(trendHandle != INVALID_HANDLE) IndicatorRelease(trendHandle);
   
   Print("╔══════════════════════════════════════════════════════════════╗");
   Print("║     NEWS SENTIMENT EA SHUTDOWN                               ║");
   Print("║     Today's trades: ", dailyTrades);
   Print("╚══════════════════════════════════════════════════════════════╝");
}
//+------------------------------------------------------------------+
