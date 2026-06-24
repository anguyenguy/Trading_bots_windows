//+------------------------------------------------------------------+
//| AutoSLTP_XAU_Exness.mq5                                          |
//| Auto add SL/TP by USD value for XAUUSD                           |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"

input string TradeSymbol = "XAUUSDm";
input double FixedLot    = 0.01;
input double StopLossUSD = 2.0;
input double TakeProfitUSD = 3.5;

bool HasSLTP(ulong ticket)
{
   if(!PositionSelectByTicket(ticket))
      return true;

   double sl = PositionGetDouble(POSITION_SL);
   double tp = PositionGetDouble(POSITION_TP);

   return (sl > 0.0 || tp > 0.0);
}

bool SetSLTP(ulong ticket)
{
   if(!PositionSelectByTicket(ticket))
      return false;

   string symbol = PositionGetString(POSITION_SYMBOL);

   if(symbol != TradeSymbol)
      return false;

   double volume = PositionGetDouble(POSITION_VOLUME);

   if(MathAbs(volume - FixedLot) > 0.00001)
      return false;

   ENUM_POSITION_TYPE type =
      (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

   double openPrice =
      PositionGetDouble(POSITION_PRICE_OPEN);

   double tickValue =
      SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);

   double tickSize =
      SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);

   if(tickValue <= 0 || tickSize <= 0)
      return false;

   double slDistance =
      (StopLossUSD / (tickValue * volume)) * tickSize;

   double tpDistance =
      (TakeProfitUSD / (tickValue * volume)) * tickSize;

   double newSL = 0;
   double newTP = 0;

   if(type == POSITION_TYPE_BUY)
   {
      newSL = openPrice - slDistance;
      newTP = openPrice + tpDistance;
   }
   else
   {
      newSL = openPrice + slDistance;
      newTP = openPrice - tpDistance;
   }

   MqlTradeRequest request;
   MqlTradeResult  result;

   ZeroMemory(request);
   ZeroMemory(result);

   request.action   = TRADE_ACTION_SLTP;
   request.position = ticket;
   request.symbol   = symbol;
   request.sl       = NormalizeDouble(newSL,_Digits);
   request.tp       = NormalizeDouble(newTP,_Digits);

   if(!OrderSend(request,result))
   {
      Print("OrderSend failed: ", GetLastError());
      return false;
   }

   Print("SL/TP applied. Ticket=", ticket,
         " SL=", request.sl,
         " TP=", request.tp);

   return true;
}

void OnTick()
{
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);

      if(ticket == 0)
         continue;

      if(HasSLTP(ticket))
         continue;

      SetSLTP(ticket);
   }
}