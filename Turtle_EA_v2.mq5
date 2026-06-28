//+------------------------------------------------------------------+
//|                                                 Turtle_EA_v2.mq5  |
//|   Breakout R:R Trailing & MTF Filter - PHIEN BAN 2 (LOT CO DINH)  |
//|                                                                  |
//|   KHAC BIET so voi v1:                                           |
//|   - v1: Lot tu dong tinh sao cho SL luon = R (vd 6$).            |
//|   - v2: Lot NHAP TAY. R duoc dinh nghia tai LOT THAM CHIEU       |
//|         (InpRef_Lot, mac dinh 0.01). Khoang cach gia cua SL la   |
//|         CO DINH (khoang cach ma lot tham chieu thua dung R).     |
//|         => Khi tang lot, khoang cach SL GIU NGUYEN, so tien      |
//|            thua/lai NO RA theo lot.                              |
//|                                                                  |
//|   Vi du (R=6$, ref lot=0.01):                                    |
//|     - Vao 0.01 lot: SL = -6$  | TP(3R) = +18$                    |
//|     - Vao 0.02 lot: SL = -12$ | TP(3R) = +36$                    |
//|     - Vao 0.05 lot: SL = -30$ | TP(3R) = +90$                    |
//|                                                                  |
//|   Cac module con lai giong v1:                                   |
//|   - Loc xu huong da khung (EMA).                                 |
//|   - Vao lenh khi breakout dinh/day gan nhat + hop xu huong.      |
//|   - TP = 3R, doi SL (trailing) khi lai >= 1.5R -> khoa +0.3R.    |
//|   - Chi 1 lenh tai 1 thoi diem.                                  |
//+------------------------------------------------------------------+
#property copyright "Turtle_EA"
#property version   "2.20"
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

input group    "--- Khoi luong & Quan ly von (V2: LOT CO DINH) ---"
input double    InpFixed_Lot            = 0.02;          // *** LOT VAO LENH (nhap tay) ***
input double    InpRisk_Amount_R        = 6.0;           // So tien R (USD) - dinh nghia tai LOT THAM CHIEU
input double    InpRef_Lot              = 0.01;          // Lot tham chieu de quy doi R (mac dinh 0.01)
input double    InpReward_Multiplier    = 3.0;           // TP = bao nhieu R (mac dinh 3R)

input group    "--- Doi lenh (Trailing Stop) ---"
input double    InpTrigger_Trailing_Mult = 1.5;          // Dat bao nhieu R thi kich hoat doi SL (1.5R)
input double    InpLock_Profit_Multiplier= 0.3;          // Muc khoa loi cua SL moi theo R (0.3R)

input group    "--- Khac ---"
input long      InpMagic_Number         = 20240629;      // Magic number (KHAC v1 de chay song song)
input int       InpSlippage_Points      = 20;            // Do truot gia cho phep (Point)

//==================================================================//
//                       GLOBAL OBJECTS                             //
//==================================================================//
CTrade          trade;          // Doi tuong thuc thi lenh
CPositionInfo   posInfo;        // Doi tuong doc thong tin vi the

int             g_emaHandle = INVALID_HANDLE; // Handle EMA tren khung lon
ENUM_TIMEFRAMES g_execTF;                     // Khung vao lenh (sau khi validate)
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
      Print("[Turtle_EA_v2] LOI: InpExecutionTimeframe chi duoc chon M1 hoac M15. Hien tai: ",
            EnumToString(g_execTF));
      return(INIT_FAILED);
   }

   //--- B2: Tao handle EMA tren khung xu huong
   g_emaHandle = iMA(_Symbol, g_trendTF, InpTrend_EMA, 0, MODE_EMA, PRICE_CLOSE);
   if(g_emaHandle == INVALID_HANDLE)
   {
      Print("[Turtle_EA_v2] LOI: Khong tao duoc handle EMA. Code=", GetLastError());
      return(INIT_FAILED);
   }

   //--- B3: Cau hinh doi tuong giao dich
   trade.SetExpertMagicNumber(InpMagic_Number);
   trade.SetDeviationInPoints(InpSlippage_Points);
   trade.SetTypeFillingBySymbol(_Symbol);

   //--- B4: Validate tham so dau vao
   if(InpFixed_Lot <= 0 || InpRisk_Amount_R <= 0 || InpRef_Lot <= 0 ||
      InpBreakout_Period < 1 || InpBreakout_Distance < 0 || InpReward_Multiplier <= 0)
   {
      Print("[Turtle_EA_v2] LOI: Tham so dau vao khong hop le.");
      return(INIT_FAILED);
   }
   if(InpTrigger_Trailing_Mult <= InpLock_Profit_Multiplier)
   {
      Print("[Turtle_EA_v2] LOI: Trigger trailing phai lon hon muc khoa loi.");
      return(INIT_FAILED);
   }

   //--- Hien thi minh hoa so tien thuc te theo lot dang chon
   double scale   = InpFixed_Lot / InpRef_Lot;          // he so no theo lot
   double slMoney = scale * InpRisk_Amount_R;           // tien thua khi cat SL
   double tpMoney = scale * InpRisk_Amount_R * InpReward_Multiplier;
   PrintFormat("[Turtle_EA_v2] Khoi dong OK. Exec=%s | Trend=%s | Lot=%.2f (ref %.2f) | SL=-%.2f$ | TP(%.1fR)=+%.2f$",
               EnumToString(g_execTF), EnumToString(g_trendTF), InpFixed_Lot, InpRef_Lot,
               slMoney, InpReward_Multiplier, tpMoney);
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
   //--- Luon quan ly trailing cho lenh dang mo (chay moi tick)
   ManageOpenPosition();

   //--- Khong nhoi lenh: neu da co lenh cua EA dang mo -> dung
   if(HasOpenPosition())
      return;

   //--- Chi xet tin hieu 1 lan moi nen moi (theo khung vao lenh)
   datetime curBar = (datetime)SeriesInfoInteger(_Symbol, g_execTF, SERIES_LASTBAR_DATE);
   if(curBar == g_lastBarTime)
      return;
   g_lastBarTime = curBar;

   //--- Kiem tra bo loc xu huong & tin hieu breakout
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
//| MODULE 1: Loc xu huong da khung thoi gian (EMA)                  |
//|   +1 = TANG (gia dong > EMA) ; -1 = GIAM ; 0 = khong xac dinh    |
//+------------------------------------------------------------------+
int GetHigherTFTrend()
{
   double emaBuf[];
   if(CopyBuffer(g_emaHandle, 0, 1, 1, emaBuf) < 1)
   {
      Print("[Turtle_EA_v2] LOI: Khong doc duoc EMA. Code=", GetLastError());
      return(0);
   }
   double emaValue = emaBuf[0];

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

   //--- B2: dinh/day gan nhat cua N nen DA DONG (bat dau shift 1)
   int idxHighest = iHighest(_Symbol, g_execTF, MODE_HIGH, InpBreakout_Period, 1);
   int idxLowest  = iLowest (_Symbol, g_execTF, MODE_LOW,  InpBreakout_Period, 1);
   if(idxHighest < 0 || idxLowest < 0)
   {
      Print("[Turtle_EA_v2] LOI: Khong xac dinh duoc dinh/day breakout.");
      return;
   }

   double rangeHigh = iHigh(_Symbol, g_execTF, idxHighest);
   double rangeLow  = iLow (_Symbol, g_execTF, idxLowest);

   //--- B3: gia hien tai & muc breakout
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double buyTrigger  = rangeHigh + InpBreakout_Distance * point;
   double sellTrigger = rangeLow  - InpBreakout_Distance * point;

   //==================== TIN HIEU BUY ====================//
   if(trend == +1 && ask > buyTrigger)
   {
      OpenTrade(ORDER_TYPE_BUY);
      return;
   }

   //==================== TIN HIEU SELL ===================//
   if(trend == -1 && bid < sellTrigger)
   {
      OpenTrade(ORDER_TYPE_SELL);
      return;
   }
}

//+------------------------------------------------------------------+
//| Khoang cach gia cua 1R (CO DINH theo lot tham chieu).            |
//|   Tai InpRef_Lot, gia di chuyen khoang cach nay = thua dung R.   |
//|   R = RefLot * (D / TickSize) * TickValue                        |
//|   => D = R * TickSize / (RefLot * TickValue)                     |
//|        = R / (RefLot * TickValue / TickSize)                     |
//+------------------------------------------------------------------+
double UnitStopDistance()
{
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE); // USD/tick/lot
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);  // buoc gia 1 tick
   if(tickValue <= 0 || tickSize <= 0 || InpRef_Lot <= 0)
   {
      Print("[Turtle_EA_v2] LOI: TickValue/TickSize/RefLot khong hop le.");
      return(0.0);
   }
   double valuePerPricePerLot = tickValue / tickSize;   // USD cho moi 1.0 gia, moi 1.0 lot
   return InpRisk_Amount_R / (InpRef_Lot * valuePerPricePerLot);
}

//+------------------------------------------------------------------+
//| Chuan hoa khoi luong lot theo buoc/min/max cua broker           |
//+------------------------------------------------------------------+
double NormalizeLot(double lot)
{
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double lotMin  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double lotMax  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   if(lotStep > 0)
      lot = MathRound(lot / lotStep) * lotStep;   // lam tron theo buoc lot
   if(lot < lotMin) lot = lotMin;
   if(lot > lotMax) lot = lotMax;
   return(lot);
}

//+------------------------------------------------------------------+
//| MODULE 3 (V2): Mo lenh voi LOT CO DINH.                          |
//|   Khoang cach SL = D (1R, co dinh). TP = InpReward_Multiplier*D. |
//|   So tien thua/lai = (Lot / RefLot) * R (no ra theo lot).        |
//+------------------------------------------------------------------+
void OpenTrade(ENUM_ORDER_TYPE type)
{
   //--- Lot co dinh (chuan hoa theo broker)
   double lot = NormalizeLot(InpFixed_Lot);
   if(lot <= 0)
   {
      Print("[Turtle_EA_v2] LOI: Lot khong hop le sau chuan hoa.");
      return;
   }

   //--- Khoang cach gia cua SL (1R) & TP (theo bo so R)
   double slDistance = UnitStopDistance();                       // = D (co dinh)
   if(slDistance <= 0)
      return;
   double tpDistance = InpReward_Multiplier * slDistance;        // vd 3D

   //--- Kiem tra khoang cach toi thieu cho phep cua broker (stops level)
   double stopsLevel = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   if(slDistance < stopsLevel || tpDistance < stopsLevel)
   {
      PrintFormat("[Turtle_EA_v2] Bo qua lenh: SL/TP (%.5f/%.5f) < stops level toi thieu (%.5f).",
                  slDistance, tpDistance, stopsLevel);
      return;
   }

   //--- Gia vao lenh & tinh SL/TP theo huong lenh
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double entry, sl, tp;

   if(type == ORDER_TYPE_BUY)
   {
      entry = ask;
      sl    = entry - slDistance;
      tp    = entry + tpDistance;
   }
   else
   {
      entry = bid;
      sl    = entry + slDistance;
      tp    = entry - tpDistance;
   }

   //--- Chuan hoa gia
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);

   //--- Gui lenh thi truong
   bool ok;
   if(type == ORDER_TYPE_BUY)
      ok = trade.Buy(lot, _Symbol, 0.0, sl, tp, "Turtle_EA_v2 BUY");
   else
      ok = trade.Sell(lot, _Symbol, 0.0, sl, tp, "Turtle_EA_v2 SELL");

   //--- Xu ly loi
   if(!ok || (trade.ResultRetcode() != TRADE_RETCODE_DONE &&
              trade.ResultRetcode() != TRADE_RETCODE_PLACED))
   {
      PrintFormat("[Turtle_EA_v2] LOI mo lenh %s. Retcode=%d (%s)",
                  EnumToString(type), trade.ResultRetcode(), trade.ResultRetcodeDescription());
   }
   else
   {
      double scale   = lot / InpRef_Lot;
      double slMoney = scale * InpRisk_Amount_R;
      double tpMoney = slMoney * InpReward_Multiplier;
      PrintFormat("[Turtle_EA_v2] Mo %s OK | Lot=%.2f | Entry~%.5f | SL=%.5f (-%.2f$) | TP=%.5f (+%.2f$)",
                  EnumToString(type), lot, entry, sl, slMoney, tp, tpMoney);
   }
}

//+------------------------------------------------------------------+
//| MODULE 4: Quan ly lenh - doi SL khi lai >= 1.5R -> khoa +0.3R    |
//|                                                                  |
//|   D (khoang cach 1R) suy nguoc tu TP (an toan khi EA restart):   |
//|     TP = entry +/- InpReward_Multiplier * D                      |
//|     => D = |TP - entry| / InpReward_Multiplier                   |
//|   Vi khoang cach co dinh, "1.5R lai" = gia di duoc 1.5 * D.      |
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
         continue;   // khong co TP -> khong suy duoc D

      //--- D = khoang cach 1R
      double D = MathAbs(tp - entry) / InpReward_Multiplier;
      if(D <= 0)
         continue;

      double triggerDist = InpTrigger_Trailing_Mult * D;   // 1.5R (theo gia)
      double lockDist    = InpLock_Profit_Multiplier  * D; // 0.3R (theo gia)

      //==================== LENH BUY ====================//
      if(type == POSITION_TYPE_BUY)
      {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double profitPrice = bid - entry;                  // lai hien tai (theo gia)

         if(profitPrice >= triggerDist)                     // lai >= 1.5R
         {
            double newSL = NormalizeDouble(entry + lockDist, digits);  // khoa +0.3R
            if(newSL > curSL)
               ModifySL(ticket, newSL, tp);
         }
      }
      //==================== LENH SELL ===================//
      else if(type == POSITION_TYPE_SELL)
      {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double profitPrice = entry - ask;                  // lai hien tai (theo gia)

         if(profitPrice >= triggerDist)
         {
            double newSL = NormalizeDouble(entry - lockDist, digits);
            if(curSL == 0.0 || newSL < curSL)
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
      PrintFormat("[Turtle_EA_v2] LOI doi SL ticket=%I64u. Retcode=%d (%s)",
                  ticket, trade.ResultRetcode(), trade.ResultRetcodeDescription());
   }
   else
   {
      PrintFormat("[Turtle_EA_v2] Da doi SL ticket=%I64u -> %.5f (khoa loi +%.1fR)",
                  ticket, newSL, InpLock_Profit_Multiplier);
   }
}
//+------------------------------------------------------------------+
