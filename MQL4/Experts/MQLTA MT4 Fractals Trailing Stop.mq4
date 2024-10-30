#property link          "https://www.earnforex.com/metatrader-expert-advisors/fractals-trailing-stop/"
#property version       "1.04"
#property strict
#property copyright     "EarnForex.com - 2019-2024"
#property description   "This expert advisor will trail the stop-poss setting it to a recent Fractals value."
#property description   " "
#property description   "WARNING: Use this software at your own risk."
#property description   "The creator of these plugins cannot be held responsible for any damage or loss."
#property description   " "
#property description   "Find More on www.EarnForex.com"
#property icon          "\\Files\\EF-Icon-64x64px.ico"

#include <MQLTA ErrorHandling.mqh>
#include <MQLTA Utils.mqh>

enum ENUM_CONSIDER
{
    All = -1,       // ALL ORDERS
    Buy = OP_BUY,   // BUY ONLY
    Sell = OP_SELL, // SELL ONLY
};

input string Comment_1 = "====================";  // Expert Advisor Settings
input int BarsToScan = 10;                        // Bars To Scan (10=Last Ten Candles)
input int FractalToUse = 1;                       // Fractal Number to Use (1 = First, 2 = Second, ...)
input int ProfitPoints = 0;                       // Profit Points to Start Trailing (0 = ignore profit)
input string Comment_2 = "====================";  // Orders Filtering Options
input bool OnlyCurrentSymbol = true;              // Apply To Current Symbol Only
input ENUM_CONSIDER OnlyType = All;               // Apply To
input bool UseMagic = false;                      // Filter By Magic Number
input int MagicNumber = 0;                        // Magic Number (if above is true)
input bool UseComment = false;                    // Filter By Comment
input string CommentFilter = "";                  // Comment (if above is true)
input bool EnableTrailingParam = false;           // Enable Trailing Stop
input string Comment_3 = "====================";  // Notification Options
input bool EnableNotify = false;                  // Enable Notifications feature
input bool SendAlert = true;                      // Send Alert Notification
input bool SendApp = false;                       // Send Notification to Mobile
input bool SendEmail = false;                     // Send Notification via Email
input string Comment_3a = "===================="; // Graphical Window
input bool ShowPanel = true;                      // Show Graphical Panel
input string ExpertName = "MQLTA-FRTS";           // Expert Name (to name the objects)
input int Xoff = 20;                              // Horizontal spacing for the control panel
input int Yoff = 20;                              // Vertical spacing for the control panel

int OrderOpRetry = 5;
double DPIScale; // Scaling parameter for the panel based on the screen DPI.
int PanelMovY, PanelLabX, PanelLabY, PanelRecX;
bool EnableTrailing = EnableTrailingParam;

int OnInit()
{
    CleanPanel();
    EnableTrailing = EnableTrailingParam;

    DPIScale = (double)TerminalInfoInteger(TERMINAL_SCREEN_DPI) / 96.0;

    PanelMovY = (int)MathRound(20 * DPIScale);
    PanelLabX = (int)MathRound(150 * DPIScale);
    PanelLabY = PanelMovY;
    PanelRecX = PanelLabX + 4;

    if (ShowPanel) DrawPanel();

    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
    CleanPanel();
}

void OnTick()
{
    if (EnableTrailing) TrailingStop();
    if (ShowPanel) DrawPanel();
}

void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
    if (id == CHARTEVENT_OBJECT_CLICK)
    {
        if (sparam == PanelEnableDisable)
        {
            ChangeTrailingEnabled();
        }
    }
    else if (id == CHARTEVENT_KEYDOWN)
    {
        if (lparam == 27)
        {
            if (MessageBox("Are you sure you want to close the EA?", "EXIT ?", MB_YESNO) == IDYES)
            {
                ExpertRemove();
            }
        }
    }
}

double GetStopLossBuy(string symbol)
{
    double FractalDown = 0;
    int counter = 0;
    for (int i = 0; i < BarsToScan; i++)
    {
        FractalDown = iFractals(symbol, PERIOD_CURRENT, MODE_LOWER, i);
        if (FractalDown > 0)
        {
            counter++; // Found next Fractal.
            if (counter >= FractalToUse) break; // Found the right Fractal number.
        }
    }
    double SLValue = FractalDown;
    return SLValue;
}

double GetStopLossSell(string symbol)
{
    double FractalUp = 0;
    int counter = 0;
    for (int i = 0; i < BarsToScan; i++)
    {
        FractalUp = iFractals(symbol, PERIOD_CURRENT, MODE_UPPER, i);
        if (FractalUp > 0)
        {
            counter++; // Found next Fractal.
            if (counter >= FractalToUse) break; // Found the right Fractal number.
        }
    }
    double SLValue = FractalUp;
    return SLValue;
}

void TrailingStop()
{
    for (int i = 0; i < OrdersTotal(); i++)
    {
        if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES ) == false)
        {
            int Error = GetLastError();
            string ErrorText = GetLastErrorText(Error);
            Print("ERROR - Unable to select the order - ", Error);
            Print("ERROR - ", ErrorText);
            break;
        }
        if ((OnlyCurrentSymbol) && (OrderSymbol() != Symbol())) continue;
        if ((UseMagic) && (OrderMagicNumber() != MagicNumber)) continue;
        if ((UseComment) && (StringFind(OrderComment(), CommentFilter) < 0)) continue;
        if ((OnlyType != All) && (OrderType() != OnlyType)) continue;

        string Instrument = OrderSymbol();
        double PointSymbol = MarketInfo(Instrument, MODE_POINT);
        
        if (ProfitPoints > 0) // Check if there is enough profit points on this position.
        {
            if (((OrderType() == OP_BUY)  && ((OrderClosePrice() - OrderOpenPrice()) / PointSymbol < ProfitPoints)) ||
                ((OrderType() == OP_SELL) && ((OrderOpenPrice() - OrderClosePrice()) / PointSymbol < ProfitPoints))) continue;
        }

        double NewSL = 0;
        double NewTP = 0;
        double SLBuy = GetStopLossBuy(Instrument);
        double SLSell = GetStopLossSell(Instrument);

        int eDigits = (int)MarketInfo(Instrument, MODE_DIGITS);
        double SLPrice = NormalizeDouble(OrderStopLoss(), eDigits);
        double TPPrice = NormalizeDouble(OrderTakeProfit(), eDigits);
        double Spread = MarketInfo(Instrument, MODE_SPREAD) * MarketInfo(Instrument, MODE_POINT);
        double StopLevel = MarketInfo(Instrument, MODE_STOPLEVEL) * MarketInfo(Instrument, MODE_POINT);

        // Adjust for tick size granularity.
        double TickSize = SymbolInfoDouble(Instrument, SYMBOL_TRADE_TICK_SIZE);
        if (TickSize > 0)
        {
            SLBuy = NormalizeDouble(MathRound(SLBuy / TickSize) * TickSize, eDigits);
            SLSell = NormalizeDouble(MathRound(SLSell / TickSize) * TickSize, eDigits);
        }
        if ((OrderType() == OP_BUY) && (SLBuy < MarketInfo(Instrument, MODE_BID) - StopLevel) && (SLBuy != 0))
        {
            NewSL = NormalizeDouble(SLBuy, eDigits);
            NewTP = TPPrice;

            if (NewSL > SLPrice)
            {
                ModifyOrder(OrderTicket(), OrderOpenPrice(), NewSL, NewTP);
            }
        }
        else if ((OrderType() == OP_SELL) && (SLSell > MarketInfo(Instrument, MODE_ASK) + StopLevel) && (SLSell != 0))
        {
            NewSL = NormalizeDouble(SLSell + Spread, eDigits);
            NewTP = TPPrice;
            if ((NewSL < SLPrice) || (SLPrice == 0))
            {
                ModifyOrder(OrderTicket(), OrderOpenPrice(), NewSL, NewTP);
            }
        }
    }
}

void ModifyOrder(int Ticket, double OpenPrice, double SLPrice, double TPPrice)
{
    if (OrderSelect(Ticket, SELECT_BY_TICKET) == false)
    {
        int Error = GetLastError();
        string ErrorText = GetLastErrorText(Error);
        Print("ERROR - SELECT TICKET - error selecting order ", Ticket, " return error: ", Error);
        return;
    }
    int eDigits = (int)MarketInfo(OrderSymbol(), MODE_DIGITS);
    SLPrice = NormalizeDouble(SLPrice, eDigits);
    TPPrice = NormalizeDouble(TPPrice, eDigits);
    for (int i = 1; i <= OrderOpRetry; i++)
    {
        bool res = OrderModify(Ticket, OpenPrice, SLPrice, TPPrice, 0, clrBlue);
        if (res)
        {
            Print("TRADE - UPDATE SUCCESS - Order ", Ticket, " new stop-loss ", SLPrice, " new take-profit ", TPPrice);
            NotifyStopLossUpdate(Ticket, SLPrice, OrderSymbol());
            break;
        }
        else
        {
            int Error = GetLastError();
            string ErrorText = GetLastErrorText(Error);
            Print("ERROR - UPDATE FAILED - error modifying order ", Ticket, " in ", OrderSymbol(), " return error: ", Error, " Open=", OpenPrice,
                  " Old SL=", OrderStopLoss(), " Old TP=", OrderTakeProfit(),
                  " New SL=", SLPrice, " New TP=", TPPrice, " Bid=", MarketInfo(OrderSymbol(), MODE_BID), " Ask=", MarketInfo(OrderSymbol(), MODE_ASK));
            Print("ERROR - ", ErrorText);
        }
    }
}

void NotifyStopLossUpdate(int OrderNumber, double SLPrice, string symbol)
{
    if (!EnableNotify) return;
    if ((!SendAlert) && (!SendApp) && (!SendEmail)) return;
    string EmailSubject = ExpertName + " " + symbol + " Notification ";
    string EmailBody = AccountCompany() + " - " + AccountName() + " - " + IntegerToString(AccountNumber()) + "\r\n" + ExpertName + " Notification for " + symbol + "\r\n";
    EmailBody += "Stop-loss for order " + IntegerToString(OrderNumber) + " moved to " + DoubleToString(SLPrice, (int)MarketInfo(symbol, MODE_DIGITS));
    string AlertText = ExpertName + " - " + symbol + " - stop-loss for order " + IntegerToString(OrderNumber) + " was moved to " + DoubleToString(SLPrice, (int)MarketInfo(symbol, MODE_DIGITS));
    string AppText = AccountCompany() + " - " + AccountName() + " - " + IntegerToString(AccountNumber()) + " - " + ExpertName + " - " + symbol + " - ";
    AppText += "stop-loss for order: " + IntegerToString(OrderNumber) + " was moved to " + DoubleToString(SLPrice, (int)MarketInfo(symbol, MODE_DIGITS)) + "";
    if (SendAlert) Alert(AlertText);
    if (SendEmail)
    {
        if (!SendMail(EmailSubject, EmailBody)) Print("Error sending email " + IntegerToString(GetLastError()));
    }
    if (SendApp)
    {
        if (!SendNotification(AppText)) Print("Error sending notification " + IntegerToString(GetLastError()));
    }
}

string PanelBase = ExpertName + "-P-BAS";
string PanelLabel = ExpertName + "-P-LAB";
string PanelEnableDisable = ExpertName + "-P-ENADIS";
void DrawPanel()
{
    string PanelText = "MQLTA FRTS";
    string PanelToolTip = "Fractals Trailing Stop-Loss by EarnForex.com";
    int Rows = 1;
    ObjectCreate(0, PanelBase, OBJ_RECTANGLE_LABEL, 0, 0, 0);
    ObjectSet(PanelBase, OBJPROP_XDISTANCE, Xoff);
    ObjectSet(PanelBase, OBJPROP_YDISTANCE, Yoff);
    ObjectSetInteger(0, PanelBase, OBJPROP_XSIZE, PanelRecX);
    ObjectSetInteger(0, PanelBase, OBJPROP_YSIZE, (PanelMovY + 2) * 1 + 2);
    ObjectSetInteger(0, PanelBase, OBJPROP_BGCOLOR, clrWhite);
    ObjectSetInteger(0, PanelBase, OBJPROP_BORDER_TYPE, BORDER_FLAT);
    ObjectSetInteger(0, PanelBase, OBJPROP_STATE, false);
    ObjectSetInteger(0, PanelBase, OBJPROP_HIDDEN, true);
    ObjectSetInteger(0, PanelBase, OBJPROP_FONTSIZE, 8);
    ObjectSet(PanelBase, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, PanelBase, OBJPROP_COLOR, clrBlack);

    DrawEdit(PanelLabel,
             Xoff + 2,
             Yoff + 2,
             PanelLabX,
             PanelLabY,
             true,
             10,
             PanelToolTip,
             ALIGN_CENTER,
             "Consolas",
             PanelText,
             false,
             clrNavy,
             clrKhaki,
             clrBlack);

    string EnableDisabledText = "";
    color EnableDisabledColor = clrNavy;
    color EnableDisabledBack = clrKhaki;
    if (EnableTrailing)
    {
        EnableDisabledText = "TRAILING ENABLED";
        EnableDisabledColor = clrWhite;
        EnableDisabledBack = clrDarkGreen;
    }
    else
    {
        EnableDisabledText = "TRAILING DISABLED";
        EnableDisabledColor = clrWhite;
        EnableDisabledBack = clrDarkRed;
    }

    DrawEdit(PanelEnableDisable,
             Xoff + 2,
             Yoff + (PanelMovY + 1)*Rows + 2,
             PanelLabX,
             PanelLabY,
             true,
             8,
             "Click to Enable or Disable the Trailing Stop Feature",
             ALIGN_CENTER,
             "Consolas",
             EnableDisabledText,
             false,
             EnableDisabledColor,
             EnableDisabledBack,
             clrBlack);

    Rows++;

    ObjectSetInteger(0, PanelBase, OBJPROP_XSIZE, PanelRecX);
    ObjectSetInteger(0, PanelBase, OBJPROP_YSIZE, (PanelMovY + 1) * Rows + 3);
}

void CleanPanel()
{
    ObjectsDeleteAll(0, ExpertName + "-P-");
}

void ChangeTrailingEnabled()
{
    if (EnableTrailing == false)
    {
        if (!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
        {
            MessageBox("Automated trading is disabled in the platform's options! Please enable it via Tools->Options->Expert Advisors.", "WARNING", MB_OK);
            return;
        }
        if (!MQLInfoInteger(MQL_TRADE_ALLOWED))
        {
            MessageBox("Live Trading is disabled in the Position Sizer's settings! Please tick the Allow Live Trading checkbox on the Common tab.", "WARNING", MB_OK);
            return;
        }
        EnableTrailing = true;
    }
    else EnableTrailing = false;
    DrawPanel();
}
//+------------------------------------------------------------------+
