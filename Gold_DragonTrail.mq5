#property strict 

input string TradeSymbol = "XAUUSDm"; 
input double RiskPerTradeUSD = 4.0; 
input double TakeProfitRR = 40.0; 
input double BreakEvenBufferR = 0.05;

//-------------------------------------------------- 
// Phát hiện lệnh BTCUSDm chưa có SL 
//-------------------------------------------------- 
bool NeedInitialize(ulong ticket) 
{ 
if(!PositionSelectByTicket(ticket)) 
return false; 

string symbol = PositionGetString(POSITION_SYMBOL); 
if(symbol != TradeSymbol) 
return false; 

double sl = PositionGetDouble(POSITION_SL); 
if(sl > 0) return false; 

return true; 
}


//-------------------------------------------------- 
// Tính khoảng cách giá tương ứng RiskPerTradeUSD 
//-------------------------------------------------- 
double CalculateRiskDistance(string symbol,double volume) 
{ 
double tickValue = SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_VALUE); 
double tickSize = SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE); 
if(tickValue <= 0 || tickSize <= 0) return 0; 
double distance = (RiskPerTradeUSD / (tickValue * volume)) * tickSize; 
return distance; 
}


//--------------------------------------------------
// Gắn SL ban đầu
//--------------------------------------------------
bool AttachInitialSL(ulong ticket)
{
   if(!PositionSelectByTicket(ticket))
      return false;

   string symbol =
      PositionGetString(POSITION_SYMBOL);

   double volume =
      PositionGetDouble(POSITION_VOLUME);

   double entry =
      PositionGetDouble(POSITION_PRICE_OPEN);

   ENUM_POSITION_TYPE type =
      (ENUM_POSITION_TYPE)
      PositionGetInteger(POSITION_TYPE);

   double rDistance =
      CalculateRiskDistance(symbol,volume);

   double slPrice;

   if(type == POSITION_TYPE_BUY)
      slPrice = entry - rDistance;
   else
      slPrice = entry + rDistance;

   MqlTradeRequest req;
   MqlTradeResult  res;

   ZeroMemory(req);
   ZeroMemory(res);

   req.action   = TRADE_ACTION_SLTP;
   req.position = ticket;
   req.symbol   = symbol;
   req.sl       = NormalizeDouble(slPrice,_Digits);

   if(!OrderSend(req,res))
      return false;

   return true;
}


//--------------------------------------------------
// Lưu thông tin R
//--------------------------------------------------
void SaveTradeInfo(
   ulong ticket,
   double entry,
   double rDistance)
{
   string prefix =
      "BDT_" + IntegerToString(ticket);

   GlobalVariableSet(
      prefix + "_ENTRY",
      entry);

   GlobalVariableSet(
      prefix + "_R",
      rDistance);

   GlobalVariableSet(
      prefix + "_STEP",
      0);
}

//--------------------------------------------------
// Doc thông tin R
//--------------------------------------------------

double GetStoredR(ulong ticket)
{
   string key =
      "BDT_" +
      IntegerToString(ticket) +
      "_R";

   if(!GlobalVariableCheck(key))
      return 0;

   return GlobalVariableGet(key);
}

//--------------------------------------------------
// Tính ProfitR
//--------------------------------------------------
double GetProfitR(ulong ticket)
{
   if(!PositionSelectByTicket(ticket))
      return 0;

   double entry =
      GlobalVariableGet(
      "BDT_" +
      IntegerToString(ticket) +
      "_ENTRY");

   double rDistance =
      GlobalVariableGet(
      "BDT_" +
      IntegerToString(ticket) +
      "_R");

   if(rDistance <= 0)
      return 0;

   ENUM_POSITION_TYPE type =
      (ENUM_POSITION_TYPE)
      PositionGetInteger(POSITION_TYPE);

   string symbol =
      PositionGetString(POSITION_SYMBOL);

   double currentPrice;

   if(type == POSITION_TYPE_BUY)
      currentPrice =
         SymbolInfoDouble(symbol,SYMBOL_BID);
   else
      currentPrice =
         SymbolInfoDouble(symbol,SYMBOL_ASK);

   double profitR;

   if(type == POSITION_TYPE_BUY)
      profitR =
         (currentPrice - entry)
         / rDistance;
   else
      profitR =
         (entry - currentPrice)
         / rDistance;

   return profitR;
}

//--------------------------------------------------
// Hàm đọc step hiện tại
//--------------------------------------------------

int GetCurrentStep(ulong ticket)
{
   string key =
      "BDT_" +
      IntegerToString(ticket) +
      "_STEP";

   if(!GlobalVariableCheck(key))
      return 0;

   return (int)GlobalVariableGet(key);
}

//--------------------------------------------------
// Hàm lưu step mới
//--------------------------------------------------
void SetCurrentStep(
   ulong ticket,
   int step)
{
   string key =
      "BDT_" +
      IntegerToString(ticket) +
      "_STEP";

   GlobalVariableSet(key,step);
}

//--------------------------------------------------
// Hàm sửa SL
//--------------------------------------------------

bool ModifySL(
   ulong ticket,
   double newSL)
{
   if(!PositionSelectByTicket(ticket))
      return false;

   string symbol =
      PositionGetString(POSITION_SYMBOL);

   double tp =
      PositionGetDouble(POSITION_TP);

   MqlTradeRequest req;
   MqlTradeResult  res;

   ZeroMemory(req);
   ZeroMemory(res);

   req.action   = TRADE_ACTION_SLTP;
   req.position = ticket;
   req.symbol   = symbol;
   req.sl       = NormalizeDouble(newSL,_Digits);
   req.tp       = tp;

   return OrderSend(req,res);
}
//--------------------------------------------------
// Hàm tính giá SL theo step
//--------------------------------------------------

double CalculateSLPrice(
   ulong ticket,
   int targetStep)
{
   if(!PositionSelectByTicket(ticket))
      return 0;

   double entry =
      GlobalVariableGet(
      "BDT_" +
      IntegerToString(ticket) +
      "_ENTRY");

   double rDistance =
      GlobalVariableGet(
      "BDT_" +
      IntegerToString(ticket) +
      "_R");

   ENUM_POSITION_TYPE type =
      (ENUM_POSITION_TYPE)
      PositionGetInteger(POSITION_TYPE);

   double lockR;

   if(targetStep == 1)
      lockR = BreakEvenBufferR;
   else
      lockR = targetStep - 1;

   if(type == POSITION_TYPE_BUY)
      return entry + (lockR * rDistance);
   else
      return entry - (lockR * rDistance);
}
//--------------------------------------------------
// Hàm quản lý Trailing
//--------------------------------------------------
void ManageTrailing(
   ulong ticket)
{
   double profitR =
      GetProfitR(ticket);

   int currentStep =
      GetCurrentStep(ticket);

   int targetStep =
      (int)MathFloor(profitR);

   if(targetStep < 1)
      return;

   if(targetStep <= currentStep)
      return;

   double newSL =
      CalculateSLPrice(
      ticket,
      targetStep);

   if(newSL <= 0)
      return;

   if(ModifySL(ticket,newSL))
   {
      SetCurrentStep(
         ticket,
         targetStep);

      Print(
      "Ticket ",
      ticket,
      " moved to step ",
      targetStep);
   }
}


void OnTick()
{
   for(int i=0;i<PositionsTotal();i++)
   {
      ulong ticket =
         PositionGetTicket(i);

      if(ticket <= 0)
         continue;

      if(NeedInitialize(ticket))
      {
         if(AttachInitialSL(ticket))
         {
            PositionSelectByTicket(ticket);

            SaveTradeInfo(
               ticket,
               PositionGetDouble(
                  POSITION_PRICE_OPEN),
               CalculateRiskDistance(
                  PositionGetString(
                     POSITION_SYMBOL),
                  PositionGetDouble(
                     POSITION_VOLUME))
            );
         }
      }

      ManageTrailing(ticket);
   }
}