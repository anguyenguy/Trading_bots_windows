//+------------------------------------------------------------------+
//|                                                    Turtle_EA.mq5  |
//|        Simple Breakout R:R Trailing & Multi-Timeframe Filter      |
//|                                                                  |
//|   Dac ta:                                                        |
//|   - Module 1: Loc xu huong da khung (EMA tren khung lon hon).    |
//|   - Module 2: Vao lenh khi breakout dinh/day gan nhat + hop      |
//|               xu huong khung lon.                                |
//|   - Module 3: Quan ly von rui ro co dinh $R. SL = -R, TP = 3R.   |
//|   - Module 4: Doi SL (trailing) khi lai >= 1.5R -> khoa +0.3R.   |
//|   - Chi 1 lenh tai 1 thoi diem (khong nhoi lenh).                |
//+------------------------------------------------------------------+
#property copyright "Turtle_EA"
#property version   "2.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//==================================================================//
//                       INPUT PARAMETERS                           //
//==================================================================//
input group    "--- Khung thoi gian & Xu huong ---"
input ENUM_TIMEFRAMES InpExecutionTimeframe = PERIOD_M1; // Khung vao lenh (CHI chon M1 hoac M15)
input int       InpTrend_EMA            = 200;           // Chu ky EMA xac dinh xu huong khung lon

input group    "--- Tin hieu Breakout ---"
input int       InpBreakout_Period      = 20;            // So nen xac dinh dinh/day gan nhat
input int       InpBreakout_Distance    = 20;            // Khoang cach breakout qua dinh/day (Point)

input group    "--- Quan ly von & R:R ---"
input double    InpRisk_Amount_R        = 6.0;           // So tien rui ro R cho moi lenh (USD)
input double    InpReward_Multiplier    = 3.0;           // He so Chot loi (mac dinh 3R)

input group    "--- Doi lenh (Trailing Stop) ---"
input double    InpTrigger_Trailing_Mult = 1.5;          // Dat bao nhieu R thi kich hoat doi SL (1.5R)
input double    InpLock_Profit_Multiplier= 0.3;          // Muc khoa loi cua SL moi theo R (0.3R)

input group    "--- Khac ---"
input long      InpMagic_Number         = 20240628;      // Magic number nhan dien lenh cua EA
input int       InpSlippage_Points      = 20;            // Do truot gia cho phep (Point)

//==================================================================//
//                       GLOBAL OBJECTS                             //
//==================================================================//
CTrade          trade;          // Doi tuong thuc thi lenh
CPositionInfo   posInfo;        // Doi tuong doc thong tin vi the

int             g_emaHandle = INVALID_HANDLE; // Handle EMA tren khung lon
ENUM_TIMEFRAMES g_execTF;                     // Khung vao lenh (= InpExecutionTimeframe sau khi validate)
ENUM_TIMEFRAMES g_trendTF;                    // Khung xac nhan xu huong
datetime        g_lastBarTime = 0;            // Thoi gian nen cuoi cua khung vao lenh (chong vao lenh lap)

//+------------------------------------------------------------------+
//| Khoi tao EA                                                      |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- B1: Validate khung vao lenh & suy ra khung xu huong tuong ung
   //        M1 -> kiem tra xu huong M15 ; M15 -> kiem tra xu huong H1
   g_execTF = InpExecutionTimeframe;
   if(g_execTF == PERIOD_M1)
      g_trendTF = PERIOD_M15;
   else if(g_execTF == PERIOD_M15)
      g_trendTF = PERIOD_H1;
   else
   {
      Print("[Turtle_EA] LOI: InpExecutionTimeframe chi duoc chon M1 hoac M15. Hien tai: ",
            EnumToString(g_execTF));
      return(INIT_FAILED);
   }

   //--- B2: Tao handle EMA tren khung xu huong
   g_emaHandle = iMA(_Symbol, g_trendTF, InpTrend_EMA, 0, MODE_EMA, PRICE_CLOSE);
   if(g_emaHandle == INVALID_HANDLE)
   {
      Print("[Turtle_EA] LOI: Khong tao duoc handle EMA. Code=", GetLastError());
      return(INIT_FAILED);
   }

   //--- B3: Cau hinh doi tuong giao dich
   trade.SetExpertMagicNumber(InpMagic_Number);
   trade.SetDeviationInPoints(InpSlippage_Points);
   trade.SetTypeFillingBySymbol(_Symbol);

   //--- B4: Validate tham so dau vao
   if(InpRisk_Amount_R <= 0 || InpBreakout_Period < 1 || InpBreakout_Distance < 0 ||
      InpReward_Multiplier <= 0)
   {
      Print("[Turtle_EA] LOI: Tham so dau vao khong hop le.");
      return(INIT_FAILED);
   }
   if(InpTrigger_Trailing_Mult <= InpLock_Profit_Multiplier)
   {
      Print("[Turtle_EA] LOI: Trigger trailing phai lon hon muc khoa loi.");
      return(INIT_FAILED);
   }

   PrintFormat("[Turtle_EA] Khoi dong OK. Exec TF=%s | Trend TF=%s | R=%.2f USD | TP=%.1fR",
               EnumToString(g_execTF), EnumToString(g_trendTF),
               InpRisk_Amount_R, InpReward_Multiplier);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Huy EA                                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_emaHandle != INVALID_HANDLE)
      IndicatorRelease(g_emaHandle);
}

//+------------------------------------------------------------------+
//| Tick chinh                                                       |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- MODULE 4: luon quan ly trailing cho lenh dang mo (chay moi tick)
   ManageOpenPosition();

   //--- Khong nhoi lenh: neu da co lenh cua EA dang mo -> dung
   if(HasOpenPosition())
      return;

   //--- Chi xet tin hieu 1 lan moi nen moi (theo khung vao lenh) de tranh spam
   datetime curBar = (datetime)SeriesInfoInteger(_Symbol, g_execTF, SERIES_LASTBAR_DATE);
   if(curBar == g_lastBarTime)
      return;
   g_lastBarTime = curBar;

   //--- MODULE 1 + 2: kiem tra bo loc xu huong & tin hieu breakout
   CheckForEntry();
}

//+------------------------------------------------------------------+
//| Kiem tra EA co dang giu lenh tren symbol nay khong                |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(posInfo.SelectByIndex(i))
      {
         if(posInfo.Symbol() == _Symbol && posInfo.Magic() == InpMagic_Number)
            return(true);
      }
   }
   return(false);
}

//+------------------------------------------------------------------+
//| MODULE 1: Bo loc xu huong da khung thoi gian                     |
//|   Lay xu huong khung lon bang EMA:                               |
//|     +1 = TANG (gia dong > EMA)                                   |
//|     -1 = GIAM (gia dong < EMA)                                   |
//|      0 = khong xac dinh / loi                                    |
//+------------------------------------------------------------------+
int GetHigherTFTrend()
{
   double emaBuf[];
   //--- EMA cua nen da dong (shift 1) tren khung xu huong
   if(CopyBuffer(g_emaHandle, 0, 1, 1, emaBuf) < 1)
   {
      Print("[Turtle_EA] LOI: Khong doc duoc EMA. Code=", GetLastError());
      return(0);
   }
   double emaValue = emaBuf[0];

   //--- Gia dong cua nen da dong tren khung xu huong
   double closeHTF = iClose(_Symbol, g_trendTF, 1);
   if(closeHTF <= 0)
      return(0);

   if(closeHTF > emaValue) return(+1);   // Gia tren EMA -> TANG
   if(closeHTF < emaValue) return(-1);   // Gia duoi EMA -> GIAM
   return(0);
}

//+------------------------------------------------------------------+
//| MODULE 2: Kiem tra tin hieu breakout & mo lenh                   |
//+------------------------------------------------------------------+
void CheckForEntry()
{
   //--- B1: loc xu huong khung lon truoc
   int trend = GetHigherTFTrend();
   if(trend == 0)
      return;

   double point = _Point;

   //--- B2: xac dinh dinh/day gan nhat cua N nen DA DONG (bat dau shift 1)
   int idxHighest = iHighest(_Symbol, g_execTF, MODE_HIGH, InpBreakout_Period, 1);
   int idxLowest  = iLowest (_Symbol, g_execTF, MODE_LOW,  InpBreakout_Period, 1);
   if(idxHighest < 0 || idxLowest < 0)
   {
      Print("[Turtle_EA] LOI: Khong xac dinh duoc dinh/day breakout.");
      return;
   }

   double rangeHigh = iHigh(_Symbol, g_execTF, idxHighest); // dinh gan nhat
   double rangeLow  = iLow (_Symbol, g_execTF, idxLowest);  // day gan nhat

   //--- B3: gia hien tai
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   //--- B4: muc breakout (vuot dinh/day + khoang cach Distance)
   double buyTrigger  = rangeHigh + InpBreakout_Distance * point;
   double sellTrigger = rangeLow  - InpBreakout_Distance * point;

   //==================== TIN HIEU BUY ====================//
   // Xu huong khung lon TANG + gia pha vo len tren dinh
   if(trend == +1 && ask > buyTrigger)
   {
      double entry = ask;
      double sl    = rangeLow;          // SL tai day vung (theo cau truc)
      if(sl >= entry) return;           // bao ve: SL phai duoi entry
      OpenTrade(ORDER_TYPE_BUY, entry, sl);
      return;
   }

   //==================== TIN HIEU SELL ===================//
   // Xu huong khung lon GIAM + gia pha vo xuong duoi day
   if(trend == -1 && bid < sellTrigger)
   {
      double entry = bid;
      double sl    = rangeHigh;         // SL tai dinh vung (theo cau truc)
      if(sl <= entry) return;           // bao ve: SL phai tren entry
      OpenTrade(ORDER_TYPE_SELL, entry, sl);
      return;
   }
}

//+------------------------------------------------------------------+
//| MODULE 3: Tinh Lot sao cho cat SL lo dung = InpRisk_Amount_R     |
//|   Lot = R / (KhoangCachSL_gia / TickSize * TickValue)            |
//+------------------------------------------------------------------+
double CalculateLotSize(double slDistancePrice)
{
   if(slDistancePrice <= 0)
      return(0.0);

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE); // gia tri 1 tick / 1 lot (USD)
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);  // buoc gia 1 tick
   if(tickValue <= 0 || tickSize <= 0)
   {
      Print("[Turtle_EA] LOI: TickValue/TickSize khong hop le.");
      return(0.0);
   }

   //--- So tien lo cho 1.0 lot khi gia di chuyen het khoang cach SL
   double lossPerLot = (slDistancePrice / tickSize) * tickValue;
   if(lossPerLot <= 0)
      return(0.0);

   double lot = InpRisk_Amount_R / lossPerLot;

   //--- Chuan hoa theo buoc lot va gioi han broker
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double lotMin  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double lotMax  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   lot = MathFloor(lot / lotStep) * lotStep;   // lam tron xuong theo buoc lot
   if(lot < lotMin)
   {
      PrintFormat("[Turtle_EA] CANH BAO: Lot tinh ra (%.4f) < lot min (%.2f). Bo qua lenh de giu dung rui ro R.",
                  lot, lotMin);
      return(0.0);   // khong ep len lotMin de tranh vuot rui ro R
   }
   if(lot > lotMax)
      lot = lotMax;

   return(lot);
}

//+------------------------------------------------------------------+
//| Mo lenh: tinh lot, SL, TP va gui lenh (co xu ly loi)             |
//+------------------------------------------------------------------+
void OpenTrade(ENUM_ORDER_TYPE type, double entry, double sl)
{
   //--- Khoang cach SL (gia) -> dung tinh lot va TP
   double slDistance = MathAbs(entry - sl);

   //--- Kiem tra khoang cach toi thieu cho phep cua broker (stops level)
   double stopsLevel = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   if(slDistance < stopsLevel)
   {
      PrintFormat("[Turtle_EA] Bo qua lenh: khoang cach SL (%.5f) < stops level toi thieu (%.5f).",
                  slDistance, stopsLevel);
      return;
   }

   //--- Tinh khoi luong theo so tien R
   double lot = CalculateLotSize(slDistance);
   if(lot <= 0)
      return;

   //--- TP = InpReward_Multiplier lan khoang cach SL (mac dinh 3R)
   double tp;
   if(type == ORDER_TYPE_BUY)
      tp = entry + slDistance * InpReward_Multiplier;
   else
      tp = entry - slDistance * InpReward_Multiplier;

   //--- Chuan hoa gia theo so chu so symbol
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);

   //--- Gui lenh thi truong
   bool ok;
   if(type == ORDER_TYPE_BUY)
      ok = trade.Buy(lot, _Symbol, 0.0, sl, tp, "Turtle_EA Breakout BUY");
   else
      ok = trade.Sell(lot, _Symbol, 0.0, sl, tp, "Turtle_EA Breakout SELL");

   //--- Xu ly loi
   if(!ok || (trade.ResultRetcode() != TRADE_RETCODE_DONE &&
              trade.ResultRetcode() != TRADE_RETCODE_PLACED))
   {
      PrintFormat("[Turtle_EA] LOI mo lenh %s. Retcode=%d (%s)",
                  EnumToString(type), trade.ResultRetcode(), trade.ResultRetcodeDescription());
   }
   else
   {
      PrintFormat("[Turtle_EA] Mo %s OK | Lot=%.2f | Entry~%.5f | SL=%.5f | TP=%.5f | Risk=%.2f USD",
                  EnumToString(type), lot, entry, sl, tp, InpRisk_Amount_R);
   }
}

//+------------------------------------------------------------------+
//| MODULE 4: Quan ly lenh - doi SL khi lai >= 1.5R -> khoa +0.3R    |
//|                                                                  |
//|   R theo gia duoc suy nguoc tu TP (an toan khi EA restart):      |
//|     TP = entry +/- InpReward_Multiplier * R_price                |
//|     => R_price = |TP - entry| / InpReward_Multiplier             |
//+------------------------------------------------------------------+
void ManageOpenPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i))
         continue;
      if(posInfo.Symbol() != _Symbol || posInfo.Magic() != InpMagic_Number)
         continue;

      double entry  = posInfo.PriceOpen();
      double curSL  = posInfo.StopLoss();
      double tp     = posInfo.TakeProfit();
      ulong  ticket = posInfo.Ticket();
      long   type   = posInfo.PositionType();
      int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

      if(tp == 0.0)
         continue;   // khong co TP -> khong suy duoc R

      //--- R theo gia (khoang cach 1R)
      double rPrice = MathAbs(tp - entry) / InpReward_Multiplier;
      if(rPrice <= 0)
         continue;

      //==================== LENH BUY ====================//
      if(type == POSITION_TYPE_BUY)
      {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double profitPrice = bid - entry;                          // lai hien tai (theo gia)

         //--- Lai >= 1.5R -> doi SL ve khoa +0.3R
         if(profitPrice >= rPrice * InpTrigger_Trailing_Mult)
         {
            double newSL = NormalizeDouble(entry + rPrice * InpLock_Profit_Multiplier, digits);
            if(newSL > curSL)            // chi doi khi SL moi tot hon
               ModifySL(ticket, newSL, tp);
         }
      }
      //==================== LENH SELL ===================//
      else if(type == POSITION_TYPE_SELL)
      {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double profitPrice = entry - ask;                          // lai hien tai (theo gia)

         if(profitPrice >= rPrice * InpTrigger_Trailing_Mult)
         {
            double newSL = NormalizeDouble(entry - rPrice * InpLock_Profit_Multiplier, digits);
            if(curSL == 0.0 || newSL < curSL)   // SELL: SL moi phai thap hon
               ModifySL(ticket, newSL, tp);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Doi Stop Loss (co xu ly loi)                                     |
//+------------------------------------------------------------------+
void ModifySL(ulong ticket, double newSL, double tp)
{
   if(!trade.PositionModify(ticket, newSL, tp))
   {
      PrintFormat("[Turtle_EA] LOI doi SL ticket=%I64u. Retcode=%d (%s)",
                  ticket, trade.ResultRetcode(), trade.ResultRetcodeDescription());
   }
   else
   {
      PrintFormat("[Turtle_EA] Da doi SL ticket=%I64u -> %.5f (khoa loi +%.1fR)",
                  ticket, newSL, InpLock_Profit_Multiplier);
   }
}
//+------------------------------------------------------------------+
