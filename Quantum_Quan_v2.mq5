//+------------------------------------------------------------------+
//|                                                 Quantum_Quan.mq5  |
//|                  EA: QUANTUM QUAN - Breakout Scalping + Smart Grid |
//|                                            XAUUSDm (M15 / M30)     |
//+------------------------------------------------------------------+
#property copyright "Quantum Quan"
#property version   "1.10"
#property strict
#property description "Breakout scalping + ATR Smart Grid (luy tien) + Daily Target % + Time Filter"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//+------------------------------------------------------------------+
//| ENUMS                                                            |
//+------------------------------------------------------------------+
enum enum_mode  { Breakout_Mode = 0 };                  // Chế độ kích hoạt lệnh gốc
enum enum_grid  { No_Grid = 0, Smart_Grid = 1 };        // Chế độ xử lý khi lệnh âm
enum enum_dist  { Fixed_Distance = 0, ATR_Distance = 1 };// Cách tính khoảng cách lưới
enum enum_loss  { No_Total_Loss = 0, Total_Equity_Loss = 1 }; // Cách thức cắt lỗ tổng
enum enum_targ  { No_Target = 0, Daily_Target_Percent = 1 };  // Chế độ mục tiêu hàng ngày

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+
//--- Nhóm cài đặt khối lượng & chế độ giao dịch
input double    InpLotSize              = 0.01;               // Khối lượng lệnh cơ sở
input enum_mode InpTrade_Mode           = Breakout_Mode;      // Chế độ kích hoạt lệnh gốc
input ENUM_TIMEFRAMES InpTimeframe      = PERIOD_M15;         // Khung thời gian phân tích (M15/M30)
input int       InpMagicNumber          = 20260628;           // Magic Number

//--- Nhóm tín hiệu Breakout (Bollinger Bands)
input int       InpBB_Period            = 20;                 // Chu kỳ Bollinger Bands
input double    InpBB_Deviation         = 2.0;                // Độ lệch chuẩn Bollinger Bands

//--- Nhóm thoát lệnh sớm (Module 2)
input int       InpTimeExit_Minutes     = 2;                  // Đóng lệnh có lãi sau X phút (Time-Based Exit)
input bool      InpUse_Trailing         = true;               // Bật Trailing Stop
input double    InpTrailing_Pips        = 80;                 // Khoảng cách Trailing Stop (pips)
input double    InpTrailing_StartPips   = 100;                // Lãi tối thiểu (pips) để kích hoạt Trailing

//--- Nhóm cài đặt Lưới lệnh thông minh (Smart Grid)
input enum_grid InpGrid_Type            = Smart_Grid;         // Chế độ xử lý khi lệnh âm
input enum_dist InpDistance_Method      = ATR_Distance;       // Cách tính khoảng cách lưới (ATR)
input int       InpATR_Period           = 14;                 // Chu kỳ ATR để tính khoảng cách
input double    InpATR_Multiplier       = 2.5;                // Hệ số nhân khoảng cách ATR (base)
input double    InpGrid_Widen_Factor    = 1.3;                // Hệ số dãn lưới lũy tiến cho mỗi lệnh Grid sau
input double    InpFixed_Grid_Pips      = 150;                // Khoảng cách lưới cố định (nếu Fixed)
input double    InpLot_Multiplier       = 1.0;                // Hệ số nhân khối lượng lệnh sau (1.0 = đều lot)
input int       InpMax_Orders           = 5;                  // Số lệnh tối đa trong một chuỗi lưới
input double    InpBasket_TP_Pips       = 60;                 // Chốt lời cả rổ lưới (pips từ giá hòa vốn)

//--- Nhóm quản lý rủi ro và mục tiêu tài khoản
input enum_loss InpClose_Loss_Type      = Total_Equity_Loss;  // Cách thức cắt lỗ tổng
input double    InpMax_Equity_Loss_Pct  = 3.0;                // Cắt lỗ toàn bộ nếu âm % Tài sản (siết chặt)
input double    InpMax_Single_Loss_USD  = 10.0;               // Lỗ tối đa 1 lệnh ($): chạm là đóng cả rổ & ngừng nhồi (0 = tắt)
input enum_targ InpTarget_Method        = Daily_Target_Percent;// Chế độ mục tiêu hàng ngày
input double    InpDaily_Target_Percent = 1.0;                // Mục tiêu lợi nhuận dừng bot (%/ngày)

//--- Nhóm lọc thời gian giao dịch (Time Filter)
input bool      InpUse_TimeFilter       = true;               // Bật lọc khung giờ vào lệnh
input int       InpServerToVN_Offset    = 4;                  // Chênh lệch giờ: VN = giờ server + offset (broker GMT+3 -> 4)
input int       InpBlock_Start_Hour     = 19;                 // Giờ VN bắt đầu chặn vào lệnh (phiên Mỹ)
input int       InpBlock_Start_Min      = 30;                 // Phút VN bắt đầu chặn
input int       InpBlock_End_Hour       = 23;                 // Giờ VN kết thúc chặn
input int       InpBlock_End_Min        = 59;                 // Phút VN kết thúc chặn
input bool      InpBlock_Mon            = false;              // Chặn thứ 2
input bool      InpBlock_Tue            = false;              // Chặn thứ 3
input bool      InpBlock_Wed            = true;               // Chặn thứ 4 (hay có tin mạnh)
input bool      InpBlock_Thu            = true;               // Chặn thứ 5 (hay có tin mạnh)
input bool      InpBlock_Fri            = true;               // Chặn thứ 6 (NFP/tin Mỹ)

//--- Nhóm phòng vệ biến động mạnh (Volatility & Cooldown)
input bool      InpUse_ATR_Filter       = true;               // Bật lọc nến biến động bất thường (ATR spike)
input int       InpATR_Spike_Lookback   = 50;                 // Số nến tính ATR trung bình nền
input double    InpATR_Spike_Mult       = 1.8;                // Chặn vào lệnh nếu ATR hiện tại > X lần ATR trung bình
input int       InpCooldown_Minutes     = 120;                // Tạm ngừng vào lệnh gốc sau khi bị cắt lỗ rổ (phút)

//--- Nhóm lọc trend khung lớn (Higher-Timeframe Trend Filter)
input bool            InpUse_TrendFilter  = true;             // Chỉ vào lệnh THUẬN trend khung lớn
input ENUM_TIMEFRAMES InpTrend_TF         = PERIOD_H1;        // Khung thời gian xác định trend
input int             InpTrend_EMA_Fast   = 50;               // EMA nhanh (xác định hướng)
input int             InpTrend_EMA_Slow   = 200;              // EMA chậm (xác định hướng)
input bool            InpUse_ADX_Filter   = true;             // Dùng ADX lọc sức mạnh trend
input int             InpADX_Period       = 14;               // Chu kỳ ADX (khung trend)
input double          InpADX_Min          = 20.0;             // Trend đủ mạnh khi ADX >= ngưỡng này

//+------------------------------------------------------------------+
//| GLOBAL OBJECTS & STATE                                           |
//+------------------------------------------------------------------+
CTrade          trade;
CPositionInfo   posInfo;

int             g_bb_handle       = INVALID_HANDLE;
int             g_atr_handle      = INVALID_HANDLE;
int             g_ema_fast_handle = INVALID_HANDLE;
int             g_ema_slow_handle = INVALID_HANDLE;
int             g_adx_handle      = INVALID_HANDLE;

datetime        g_last_bar_time = 0;       // Thời điểm cây nến đã xử lý gần nhất

// Daily target state
double          g_day_base_balance = 0.0;  // Balance cơ sở đầu ngày
int             g_current_day      = -1;    // Ngày giao dịch hiện tại (server)
bool            g_paused_for_day   = false; // Đã đạt target -> ngủ đông
datetime        g_cooldown_until   = 0;     // Ngừng vào lệnh gốc đến thời điểm này (sau cắt lỗ)

double          g_point  = 0.0;            // _Point của symbol
double          g_pip    = 0.0;            // 1 pip quy đổi sang giá

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   g_point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   // 1 pip cho vàng/forex: với symbol 3 hoặc 5 chữ số thập phân -> pip = 10 * point
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   g_pip = (digits == 3 || digits == 5) ? g_point * 10.0 : g_point;

   // Khởi tạo chỉ báo
   g_bb_handle = iBands(_Symbol, InpTimeframe, InpBB_Period, 0, InpBB_Deviation, PRICE_CLOSE);
   if(g_bb_handle == INVALID_HANDLE)
   {
      Print("Loi: khong tao duoc handle Bollinger Bands");
      return(INIT_FAILED);
   }

   g_atr_handle = iATR(_Symbol, InpTimeframe, InpATR_Period);
   if(g_atr_handle == INVALID_HANDLE)
   {
      Print("Loi: khong tao duoc handle ATR");
      return(INIT_FAILED);
   }

   // Chỉ báo lọc trend khung lớn
   if(InpUse_TrendFilter)
   {
      g_ema_fast_handle = iMA(_Symbol, InpTrend_TF, InpTrend_EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
      g_ema_slow_handle = iMA(_Symbol, InpTrend_TF, InpTrend_EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
      g_adx_handle      = iADX(_Symbol, InpTrend_TF, InpADX_Period);
      if(g_ema_fast_handle == INVALID_HANDLE || g_ema_slow_handle == INVALID_HANDLE || g_adx_handle == INVALID_HANDLE)
      {
         Print("Loi: khong tao duoc handle EMA/ADX cho loc trend khung lon");
         return(INIT_FAILED);
      }
   }

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetMarginMode();

   // Khởi tạo trạng thái ngày ngay khi nạp EA
   ResetDailyState();

   Print("Quantum Quan EA initialized. Symbol=", _Symbol,
         " TF=", EnumToString(InpTimeframe),
         " Pip=", DoubleToString(g_pip, _Digits));
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_bb_handle       != INVALID_HANDLE) IndicatorRelease(g_bb_handle);
   if(g_atr_handle      != INVALID_HANDLE) IndicatorRelease(g_atr_handle);
   if(g_ema_fast_handle != INVALID_HANDLE) IndicatorRelease(g_ema_fast_handle);
   if(g_ema_slow_handle != INVALID_HANDLE) IndicatorRelease(g_ema_slow_handle);
   if(g_adx_handle      != INVALID_HANDLE) IndicatorRelease(g_adx_handle);
}

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
{
   // 0) Quản lý chu kỳ ngày: reset lúc 00:00 server, kiểm tra target mỗi tick
   ManageDailyCycle();

   // 1a) Chốt chặn theo từng lệnh: 1 lệnh nhồi chạm mức lỗ tối đa -> đóng cả rổ
   if(CheckSingleOrderMaxLoss())
      return; // đã force-close toàn bộ, dừng xử lý tiếp trong tick này

   // 1b) Quản lý rủi ro tổng (chốt chặn cuối) - luôn chạy mỗi tick
   if(CheckTotalEquityLoss())
      return; // đã force-close toàn bộ, dừng xử lý tiếp trong tick này

   // 2) Quản lý các lệnh đang mở (Time exit / Trailing / Basket TP) - mỗi tick
   ManageOpenPositions();

   // 3) Phát hiện cây nến mới -> xử lý logic vào lệnh / rải lưới tại giây thứ 0
   if(IsNewBar())
      OnNewBar();
}

//+------------------------------------------------------------------+
//| Phát hiện nến mới                                                |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime t = (datetime)iTime(_Symbol, InpTimeframe, 0);
   if(t == 0) return false;
   if(t != g_last_bar_time)
   {
      g_last_bar_time = t;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Xử lý khi mở nến mới (giây thứ 0)                                |
//+------------------------------------------------------------------+
void OnNewBar()
{
   // Nếu đang ngủ đông vì đạt target ngày -> không làm gì
   if(g_paused_for_day) return;

   int basketCount = CountBasketPositions();

   if(basketCount == 0)
   {
      // Cooldown sau khi vừa bị cắt lỗ rổ -> không nhảy lại vào con sóng đang chạy
      if(TimeCurrent() < g_cooldown_until) return;

      // Chỉ MỞ LỆNH GỐC khi nằm trong khung giờ cho phép (Time Filter)
      if(!IsTradingTimeAllowed()) return;

      // Né nến biến động bất thường (ATR spike) -> tránh mở lệnh lúc thị trường vừa bùng nổ
      if(IsVolatilitySpike()) return;

      // Tìm tín hiệu Breakout gốc (Module 1)
      int signal = GetBreakoutSignal();
      if(signal == 0) return;

      // LỌC TREND KHUNG LỚN: chỉ vào lệnh khi breakout THUẬN theo trend H1
      // -> ngăn rổ grid nhồi ngược con sóng mạnh (nguyên nhân các cú thua sâu)
      if(!IsTrendAligned(signal)) return;

      if(signal == 1)
         OpenMarket(ORDER_TYPE_BUY, InpLotSize, "QQ-Base-BUY");
      else if(signal == -1)
         OpenMarket(ORDER_TYPE_SELL, InpLotSize, "QQ-Base-SELL");
   }
   else
   {
      // Đã có rổ lệnh -> tiếp tục quản lý lưới kể cả ngoài giờ (để gỡ lệnh đang ôm)
      if(InpGrid_Type == Smart_Grid)
         ManageGridEntry(basketCount);
   }
}

//+------------------------------------------------------------------+
//| MODULE 1: Tín hiệu Breakout từ nến vừa đóng (shift = 1)          |
//| Trả về: 1 = BUY, -1 = SELL, 0 = không có tín hiệu               |
//+------------------------------------------------------------------+
int GetBreakoutSignal()
{
   // Lấy dữ liệu nến đã đóng: shift 1 (nến vừa đóng), shift 2 (nến trước đó)
   double close1 = iClose(_Symbol, InpTimeframe, 1);
   double open1  = iOpen(_Symbol,  InpTimeframe, 1);
   double high2  = iHigh(_Symbol,  InpTimeframe, 2);
   double low2   = iLow(_Symbol,   InpTimeframe, 2);

   if(close1 == 0.0 || open1 == 0.0) return 0;

   // Lấy giá trị Bollinger Bands tại nến vừa đóng (shift 1)
   double bbUpper[1], bbLower[1];
   if(CopyBuffer(g_bb_handle, 1, 1, 1, bbUpper) <= 0) return 0; // buffer 1 = upper
   if(CopyBuffer(g_bb_handle, 2, 1, 1, bbLower) <= 0) return 0; // buffer 2 = lower

   bool bullishCandle = (close1 > open1);
   bool bearishCandle = (close1 < open1);

   // BUY: nến tăng mạnh, đóng cửa breakout trên BB Upper VÀ vượt đỉnh nến trước
   if(bullishCandle && close1 > bbUpper[0] && close1 > high2)
      return 1;

   // SELL: nến giảm mạnh, đóng cửa breakout dưới BB Lower VÀ thủng đáy nến trước
   if(bearishCandle && close1 < bbLower[0] && close1 < low2)
      return -1;

   return 0;
}

//+------------------------------------------------------------------+
//| MODULE 6 (MỚI): Lọc thời gian giao dịch                         |
//| Chặn vào lệnh gốc trong khung giờ Mỹ (sau 19:30 VN) các ngày    |
//| dễ có tin mạnh, để né các pha quét hai đầu (False Breakout).    |
//| Trả về true = ĐƯỢC PHÉP vào lệnh.                                |
//+------------------------------------------------------------------+
bool IsTradingTimeAllowed()
{
   if(!InpUse_TimeFilter) return true;

   // Quy đổi giờ server -> giờ VN
   datetime vnTime = TimeCurrent() + (datetime)(InpServerToVN_Offset * 3600);
   MqlDateTime vn;
   TimeToStruct(vnTime, vn);

   // Kiểm tra ngày trong tuần có nằm trong danh sách chặn không
   bool dayBlocked = false;
   switch(vn.day_of_week)
   {
      case 1: dayBlocked = InpBlock_Mon; break;
      case 2: dayBlocked = InpBlock_Tue; break;
      case 3: dayBlocked = InpBlock_Wed; break;
      case 4: dayBlocked = InpBlock_Thu; break;
      case 5: dayBlocked = InpBlock_Fri; break;
      default: dayBlocked = false; break; // T7/CN không xét (thị trường đóng)
   }
   if(!dayBlocked) return true; // ngày này không chặn -> cho phép cả ngày

   // Tính phút trong ngày để so sánh khung giờ chặn
   int nowMin   = vn.hour * 60 + vn.min;
   int startMin = InpBlock_Start_Hour * 60 + InpBlock_Start_Min;
   int endMin   = InpBlock_End_Hour   * 60 + InpBlock_End_Min;

   // Trong cửa sổ chặn [start, end] -> KHÔNG cho vào lệnh
   if(nowMin >= startMin && nowMin <= endMin)
      return false;

   return true;
}

//+------------------------------------------------------------------+
//| Lọc biến động bất thường: ATR nến vừa đóng vọt cao so với nền    |
//| Trả về true = ĐANG biến động mạnh -> KHÔNG nên mở lệnh gốc.      |
//+------------------------------------------------------------------+
bool IsVolatilitySpike()
{
   if(!InpUse_ATR_Filter) return false;

   int n = InpATR_Spike_Lookback;
   if(n < 5) n = 5;

   double atr[];
   ArraySetAsSeries(atr, true);
   // Lấy n giá trị ATR tính từ nến vừa đóng (shift 1) trở về trước
   if(CopyBuffer(g_atr_handle, 0, 1, n, atr) < n)
      return false; // chưa đủ dữ liệu -> không chặn

   double sum = 0.0;
   for(int i = 0; i < n; i++) sum += atr[i];
   double avg = sum / n;
   if(avg <= 0.0) return false;

   double cur = atr[0]; // ATR của nến vừa đóng
   if(cur > avg * InpATR_Spike_Mult)
   {
      PrintFormat("Bo qua tin hieu: ATR spike (cur=%.5f > %.1fx avg=%.5f)",
                  cur, InpATR_Spike_Mult, avg);
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Xác định hướng trend khung lớn (EMA fast/slow + ADX)            |
//| Trả về: 1 = trend tăng, -1 = trend giảm, 0 = không rõ / yếu     |
//+------------------------------------------------------------------+
int GetTrendDirection()
{
   double fast[1], slow[1];
   // Đọc tại nến đã đóng (shift 1) của khung trend cho ổn định
   if(CopyBuffer(g_ema_fast_handle, 0, 1, 1, fast) <= 0) return 0;
   if(CopyBuffer(g_ema_slow_handle, 0, 1, 1, slow) <= 0) return 0;

   // ADX: lọc sức mạnh trend (buffer 0 = đường ADX chính)
   if(InpUse_ADX_Filter)
   {
      double adx[1];
      if(CopyBuffer(g_adx_handle, 0, 1, 1, adx) <= 0) return 0;
      if(adx[0] < InpADX_Min) return 0; // trend chưa đủ mạnh -> không xác định hướng
   }

   if(fast[0] > slow[0]) return 1;
   if(fast[0] < slow[0]) return -1;
   return 0;
}

//+------------------------------------------------------------------+
//| Kiểm tra tín hiệu có THUẬN trend khung lớn không                |
//| signal: 1 = BUY, -1 = SELL. Trả về true = được phép vào lệnh.   |
//+------------------------------------------------------------------+
bool IsTrendAligned(int signal)
{
   if(!InpUse_TrendFilter) return true; // tắt lọc -> cho phép cả 2 chiều

   int trend = GetTrendDirection();
   if(trend == 0) return false;          // không rõ trend / trend yếu -> đứng ngoài
   return (signal == trend);             // chỉ vào khi cùng chiều trend lớn
}

//+------------------------------------------------------------------+
//| Mở lệnh thị trường                                               |
//+------------------------------------------------------------------+
bool OpenMarket(ENUM_ORDER_TYPE type, double lots, string comment)
{
   lots = NormalizeLots(lots);
   if(lots <= 0.0) return false;

   double price = (type == ORDER_TYPE_BUY)
                  ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                  : SymbolInfoDouble(_Symbol, SYMBOL_BID);

   bool ok = trade.PositionOpen(_Symbol, type, lots, price, 0.0, 0.0, comment);
   if(!ok)
      PrintFormat("Mo lenh that bai: %s lots=%.2f err=%d",
                  EnumToString(type), lots, trade.ResultRetcode());
   return ok;
}

//+------------------------------------------------------------------+
//| MODULE 3: Rải lưới thông minh (Smart Grid ATR - lũy tiến)       |
//+------------------------------------------------------------------+
void ManageGridEntry(int basketCount)
{
   // Van an toàn: không vượt InpMax_Orders
   if(basketCount >= InpMax_Orders) return;

   // Xác định chiều rổ lệnh + giá vào tệ nhất + lot lệnh cuối
   ENUM_POSITION_TYPE basketType;
   double worstPrice, lastLot;
   if(!GetBasketInfo(basketType, worstPrice, lastLot)) return;

   // Khoảng cách lưới lũy tiến: base * (Widen_Factor ^ số_lệnh_grid_đã_có)
   // basketCount=1 (mới có lệnh gốc) -> exp 0 -> base step
   // basketCount=2 -> exp 1 -> base * 1.3, basketCount=3 -> base * 1.3^2 ...
   int    gridLevel = basketCount - 1;
   double gridStep  = GetGridStepPrice() * MathPow(InpGrid_Widen_Factor, gridLevel);
   if(gridStep <= 0.0) return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(basketType == POSITION_TYPE_BUY)
   {
      // Rổ BUY đang âm khi giá giảm. Rải thêm BUY khi giá thấp hơn giá vào tệ nhất 1 grid step
      if(ask <= worstPrice - gridStep)
      {
         double newLot = NormalizeLots(lastLot * InpLot_Multiplier);
         OpenMarket(ORDER_TYPE_BUY, newLot, "QQ-Grid-BUY-L" + IntegerToString(gridLevel));
      }
   }
   else // POSITION_TYPE_SELL
   {
      // Rổ SELL đang âm khi giá tăng. Rải thêm SELL khi giá cao hơn giá vào tệ nhất 1 grid step
      if(bid >= worstPrice + gridStep)
      {
         double newLot = NormalizeLots(lastLot * InpLot_Multiplier);
         OpenMarket(ORDER_TYPE_SELL, newLot, "QQ-Grid-SELL-L" + IntegerToString(gridLevel));
      }
   }
}

//+------------------------------------------------------------------+
//| Khoảng cách lưới CƠ SỞ (đơn vị giá): ATR * Multiplier hoặc cố định|
//+------------------------------------------------------------------+
double GetGridStepPrice()
{
   if(InpDistance_Method == ATR_Distance)
   {
      double atr[1];
      if(CopyBuffer(g_atr_handle, 0, 1, 1, atr) <= 0) return 0.0;
      return atr[0] * InpATR_Multiplier;
   }
   // Fixed
   return InpFixed_Grid_Pips * g_pip;
}

//+------------------------------------------------------------------+
//| MODULE 2: Quản lý lệnh đang mở (Time exit / Trailing / Basket TP)|
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   int basketCount = CountBasketPositions();
   if(basketCount == 0) return;

   // --- Chốt lời cả rổ khi đạt TP hòa vốn (áp dụng khi đã có lưới >= 2 lệnh) ---
   if(basketCount >= 2)
   {
      if(CheckBasketTakeProfit())
         return; // đã đóng cả rổ
   }

   // --- Lệnh đơn lẻ: Time-Based Exit + Trailing Stop ---
   if(basketCount == 1)
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(!posInfo.SelectByIndex(i)) continue;
         if(posInfo.Symbol() != _Symbol || posInfo.Magic() != InpMagicNumber) continue;

         double profit = posInfo.Profit() + posInfo.Swap() + posInfo.Commission();

         // Time-Based Exit: đang lãi và giữ lệnh quá X phút -> đóng
         long holdSec = (long)(TimeCurrent() - posInfo.Time());
         if(profit > 0.0 && holdSec >= InpTimeExit_Minutes * 60)
         {
            trade.PositionClose(posInfo.Ticket());
            continue;
         }

         // Trailing Stop
         if(InpUse_Trailing)
            ApplyTrailing(posInfo.Ticket());
      }
   }
}

//+------------------------------------------------------------------+
//| Trailing Stop cho 1 vị thế                                       |
//+------------------------------------------------------------------+
void ApplyTrailing(ulong ticket)
{
   if(!posInfo.SelectByTicket(ticket)) return;

   double openPrice = posInfo.PriceOpen();
   double curSL     = posInfo.StopLoss();
   double trailDist = InpTrailing_Pips * g_pip;
   double startDist = InpTrailing_StartPips * g_pip;
   long   stopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist   = stopLevel * g_point;

   if(posInfo.PositionType() == POSITION_TYPE_BUY)
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(bid - openPrice < startDist) return; // chưa đủ lãi để kích hoạt

      double newSL = bid - trailDist;
      if(bid - newSL < minDist) newSL = bid - minDist;

      if(newSL > openPrice && (curSL == 0.0 || newSL > curSL))
         trade.PositionModify(ticket, NormalizeDouble(newSL, _Digits), posInfo.TakeProfit());
   }
   else if(posInfo.PositionType() == POSITION_TYPE_SELL)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if(openPrice - ask < startDist) return;

      double newSL = ask + trailDist;
      if(newSL - ask < minDist) newSL = ask + minDist;

      if(newSL < openPrice && (curSL == 0.0 || newSL < curSL))
         trade.PositionModify(ticket, NormalizeDouble(newSL, _Digits), posInfo.TakeProfit());
   }
}

//+------------------------------------------------------------------+
//| Chốt lời cả rổ lưới khi giá đạt mức hòa vốn + TP pips            |
//+------------------------------------------------------------------+
bool CheckBasketTakeProfit()
{
   double totalLots = 0.0, weighted = 0.0;
   ENUM_POSITION_TYPE basketType = POSITION_TYPE_BUY;
   bool found = false;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol || posInfo.Magic() != InpMagicNumber) continue;

      totalLots += posInfo.Volume();
      weighted  += posInfo.PriceOpen() * posInfo.Volume();
      basketType = posInfo.PositionType();
      found = true;
   }

   if(!found || totalLots <= 0.0) return false;

   double breakEven = weighted / totalLots;       // giá hòa vốn theo khối lượng
   double tpDist    = InpBasket_TP_Pips * g_pip;

   if(basketType == POSITION_TYPE_BUY)
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(bid >= breakEven + tpDist)
      {
         CloseAllBasket("Basket TP (BUY)");
         return true;
      }
   }
   else
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if(ask <= breakEven - tpDist)
      {
         CloseAllBasket("Basket TP (SELL)");
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| MODULE 4b: Chốt chặn theo TỪNG LỆNH                             |
//| Nếu BẤT KỲ lệnh nào trong rổ nhồi chạm mức lỗ tối đa ($) ->     |
//| đóng sạch cả rổ ngay và kích hoạt cooldown (ngừng nhồi thêm).   |
//+------------------------------------------------------------------+
bool CheckSingleOrderMaxLoss()
{
   if(InpMax_Single_Loss_USD <= 0.0) return false; // tắt tính năng

   double threshold = -InpMax_Single_Loss_USD; // ngưỡng lỗ (số âm)

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol || posInfo.Magic() != InpMagicNumber) continue;

      double pl = posInfo.Profit() + posInfo.Swap() + posInfo.Commission();
      if(pl <= threshold)
      {
         CloseAllBasket("SINGLE ORDER MAX LOSS - Force Close");
         // Ngừng nhồi thêm: cooldown chặn mở lệnh gốc mới một khoảng thời gian
         g_cooldown_until = TimeCurrent() + (datetime)(InpCooldown_Minutes * 60);
         PrintFormat("FORCE CLOSE: lenh ticket=%I64u lo %.2f$ >= nguong %.2f$. Dong ca ro, cooldown %d phut.",
                     posInfo.Ticket(), pl, InpMax_Single_Loss_USD, InpCooldown_Minutes);
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| MODULE 4: Cắt lỗ tổng theo % Equity (chốt chặn cuối)            |
//+------------------------------------------------------------------+
bool CheckTotalEquityLoss()
{
   if(InpClose_Loss_Type != Total_Equity_Loss) return false;

   int basketCount = CountBasketPositions();
   if(basketCount == 0) return false;

   double floatingPL = BasketFloatingProfit();
   double equity     = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity <= 0.0) return false;

   // Ngưỡng âm tối đa (số tiền) = % * equity
   double maxLossMoney = equity * (InpMax_Equity_Loss_Pct / 100.0);

   if(floatingPL < 0.0 && MathAbs(floatingPL) >= maxLossMoney)
   {
      CloseAllBasket("MAX EQUITY LOSS - Force Close");
      // Kích hoạt cooldown: ngừng vào lệnh gốc để không nhảy lại vào con sóng đang chạy
      g_cooldown_until = TimeCurrent() + (datetime)(InpCooldown_Minutes * 60);
      PrintFormat("FORCE CLOSE: floating=%.2f >= maxLoss=%.2f (%.1f%% equity). Cooldown %d phut.",
                  floatingPL, maxLossMoney, InpMax_Equity_Loss_Pct, InpCooldown_Minutes);
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| MODULE 5: Quản lý chu kỳ ngày + mục tiêu lợi nhuận              |
//+------------------------------------------------------------------+
void ManageDailyCycle()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);

   // Sang ngày mới (00:00 server) -> reset trạng thái, thức dậy
   if(dt.day != g_current_day)
   {
      ResetDailyState();
   }

   if(InpTarget_Method != Daily_Target_Percent) return;
   if(g_paused_for_day) return; // đã đạt target, đang ngủ đông

   // Lợi nhuận đã đóng trong ngày + lợi nhuận đang trôi nổi
   double dayProfit = GetTodayClosedProfit() + BasketFloatingProfit();
   double targetMoney = g_day_base_balance * (InpDaily_Target_Percent / 100.0);

   if(g_day_base_balance > 0.0 && dayProfit >= targetMoney)
   {
      // Đạt mục tiêu: đóng toàn bộ lệnh + hủy lệnh chờ + ngủ đông
      CloseAllBasket("DAILY TARGET REACHED");
      DeleteAllPending();
      g_paused_for_day = true;

      string msg = StringFormat("QUANTUM QUAN: Dat muc tieu ngay %.1f%% (loi nhuan=%.2f). EA ngu dong den 00:00 hom sau.",
                                InpDaily_Target_Percent, dayProfit);
      Print(msg);
      Alert(msg);
      SendNotification(msg);
   }
}

//+------------------------------------------------------------------+
//| Reset trạng thái ngày (gọi lúc init và mỗi 00:00 server)        |
//+------------------------------------------------------------------+
void ResetDailyState()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   g_current_day      = dt.day;
   g_day_base_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_paused_for_day   = false;
   PrintFormat("Reset ngay moi: day=%d base_balance=%.2f", g_current_day, g_day_base_balance);
}

//+------------------------------------------------------------------+
//| Tổng lợi nhuận các lệnh đã ĐÓNG trong ngày hôm nay              |
//+------------------------------------------------------------------+
double GetTodayClosedProfit()
{
   datetime dayStart = TodayStartServer();
   if(!HistorySelect(dayStart, TimeCurrent())) return 0.0;

   double profit = 0.0;
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol) continue;
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != InpMagicNumber) continue;

      // Chỉ tính deal liên quan PnL (đóng vị thế)
      long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT || entry == DEAL_ENTRY_OUT_BY)
      {
         profit += HistoryDealGetDouble(ticket, DEAL_PROFIT);
         profit += HistoryDealGetDouble(ticket, DEAL_SWAP);
         profit += HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      }
   }
   return profit;
}

//+------------------------------------------------------------------+
//| Thời điểm 00:00 server của hôm nay                              |
//+------------------------------------------------------------------+
datetime TodayStartServer()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   return StructToTime(dt);
}

//+------------------------------------------------------------------+
//| HELPERS: đếm rổ, thông tin rổ, đóng rổ, lợi nhuận trôi nổi       |
//+------------------------------------------------------------------+
int CountBasketPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() == _Symbol && posInfo.Magic() == InpMagicNumber)
         count++;
   }
   return count;
}

double BasketFloatingProfit()
{
   double pl = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol || posInfo.Magic() != InpMagicNumber) continue;
      pl += posInfo.Profit() + posInfo.Swap() + posInfo.Commission();
   }
   return pl;
}

//+------------------------------------------------------------------+
//| Lấy thông tin rổ: chiều, giá vào tệ nhất, lot của lệnh cuối     |
//+------------------------------------------------------------------+
bool GetBasketInfo(ENUM_POSITION_TYPE &basketType, double &worstPrice, double &lastLot)
{
   bool found = false;
   double bestEntryForBuy  = DBL_MAX;  // giá thấp nhất với rổ BUY = vào tệ nhất
   double bestEntryForSell = 0.0;      // giá cao nhất với rổ SELL = vào tệ nhất
   datetime lastTime = 0;
   lastLot = InpLotSize;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol || posInfo.Magic() != InpMagicNumber) continue;

      basketType = posInfo.PositionType();
      double op  = posInfo.PriceOpen();

      if(basketType == POSITION_TYPE_BUY  && op < bestEntryForBuy)  bestEntryForBuy  = op;
      if(basketType == POSITION_TYPE_SELL && op > bestEntryForSell) bestEntryForSell = op;

      // Lot của lệnh mới nhất (theo thời gian mở)
      if(posInfo.Time() >= lastTime)
      {
         lastTime = posInfo.Time();
         lastLot  = posInfo.Volume();
      }
      found = true;
   }

   if(!found) return false;
   worstPrice = (basketType == POSITION_TYPE_BUY) ? bestEntryForBuy : bestEntryForSell;
   return true;
}

//+------------------------------------------------------------------+
//| Đóng toàn bộ lệnh trong rổ (cùng symbol + magic)                |
//+------------------------------------------------------------------+
void CloseAllBasket(string reason)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol || posInfo.Magic() != InpMagicNumber) continue;
      trade.PositionClose(posInfo.Ticket());
   }
   if(reason != "")
      Print("CloseAllBasket: ", reason);
}

//+------------------------------------------------------------------+
//| Hủy toàn bộ lệnh chờ (cùng symbol + magic)                      |
//+------------------------------------------------------------------+
void DeleteAllPending()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      if(OrderGetInteger(ORDER_MAGIC) != InpMagicNumber) continue;
      trade.OrderDelete(ticket);
   }
}

//+------------------------------------------------------------------+
//| Chuẩn hóa khối lượng theo ràng buộc của broker                  |
//+------------------------------------------------------------------+
double NormalizeLots(double lots)
{
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(lotStep <= 0.0) lotStep = 0.01;
   lots = MathRound(lots / lotStep) * lotStep;
   if(lots < minLot) lots = minLot;
   if(lots > maxLot) lots = maxLot;

   // Làm tròn theo số chữ số của lotStep
   int lotDigits = (int)MathRound(MathLog10(1.0 / lotStep));
   if(lotDigits < 0) lotDigits = 2;
   return NormalizeDouble(lots, lotDigits);
}
//+------------------------------------------------------------------+
