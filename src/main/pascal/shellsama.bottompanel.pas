{ Unit ShellSama.BottomPanel — Desktop Bottom Panel & Taskbar for Samarinda DE }

unit ShellSama.BottomPanel;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils, Math,
  Floria.XCB,
  ShellSama.LibFt,
  ShellSama.Launcher;

type
  PCardinalArray = ^TCardinalArray;
  TCardinalArray = array[0..4] of Cardinal;

  TWindowIdArray = array of Cardinal;

  TTaskItem = record
    Window     : Cardinal;
    Title      : string;
    IsActive   : Boolean;
    IsMinimized: Boolean;
    Button     : FtWidget;
  end;

  TShellBottomPanel = class
  private
    FWindow         : FtWidget;
    FLauncherBtn    : FtWidget;
    FClockText      : FtWidget;
    FShowDesktopBtn : FtWidget;
    FLauncher       : TShellLauncher;
    FIsVisible      : Boolean;
    FShowingDesktop : Boolean;
    FPanelHeight    : Integer;
    FPanelWidth     : Integer;

    FTasks          : array of TTaskItem;
    FActiveWindow   : Cardinal;
    FLastClockSec   : Integer;
    FLastActiveWin  : Cardinal;

    // XCB connection details
    FConn           : Pxcb_connection_t;
    FScreen         : Pxcb_screen_t;
    FRootWindow     : Cardinal;

    // Cached EWMH atoms
    FAtomNetClientList        : Cardinal;
    FAtomNetActiveWindow      : Cardinal;
    FAtomNetWmName            : Cardinal;
    FAtomNetWmState           : Cardinal;
    FAtomNetWmStateHidden     : Cardinal;
    FAtomNetWmStateSkipTaskbar: Cardinal;
    FAtomNetWmWindowType      : Cardinal;
    FAtomNetWmWindowTypeDock  : Cardinal;
    FAtomNetWmWindowTypeDesk  : Cardinal;
    FAtomNetWmWindowTypeSplash: Cardinal;
    FAtomNetWmWindowTypeUtil  : Cardinal;
    FAtomNetWmWindowTypeTool  : Cardinal;
    FAtomNetWmWindowTypeMenu  : Cardinal;
    FAtomNetWmWindowTypeTip   : Cardinal;
    FAtomNetShowingDesktop    : Cardinal;
    FAtomUtf8String           : Cardinal;
    FAtomWMChangeState        : Cardinal;
    FAtomWMName               : Cardinal;

    procedure InitAtoms();
    procedure SetupWindow();
    procedure LayoutButtons();
    function QueryClientList(): TWindowIdArray;
    function QueryActiveWindow(): Cardinal;
    function QueryWindowTitle(AWin: Cardinal): string;
    function ShouldShowTask(AWin: Cardinal): Boolean;
    function IsWindowMinimized(AWin: Cardinal): Boolean;
  public
    constructor Create(ALauncher: TShellLauncher = nil);
    destructor Destroy(); override;

    procedure Show();
    procedure Hide();
    procedure RefreshTasks();
    procedure UpdateClock();
    procedure Tick();

    procedure ActivateWindow(AWin: Cardinal);
    procedure MinimizeWindow(AWin: Cardinal);
    procedure ToggleShowDesktop();
    procedure OnLauncherClicked();
    procedure OnTaskClicked(AWin: Cardinal);

    function PanelX(): Integer;
    function PanelY(): Integer;
    function PanelWidth(): Integer;
    function PanelHeight(): Integer;
    function GetTaskCount(): Integer;

    property IsVisible     : Boolean         read FIsVisible;
    property ActiveWindow  : Cardinal        read FActiveWindow;
    property TaskCount     : Integer         read GetTaskCount;
    property WindowWidget  : FtWidget        read FWindow;
    property LauncherWidget: FtWidget        read FLauncherBtn;
    property ClockWidget   : FtWidget        read FClockText;
  end;

var
  GBottomPanelInstance: TShellBottomPanel = nil;

implementation

procedure c_free(p: Pointer); cdecl; external 'c' name 'free';

function InternAtom(AConn: Pxcb_connection_t; const AName: string): Cardinal;
var
  cookie: xcb_intern_atom_cookie_t;
  reply: Pxcb_intern_atom_reply_t;
begin
  Result := 0;
  if AConn = nil then Exit;
  cookie := xcb_intern_atom(AConn, 0, Length(AName), PChar(AName));
  reply := xcb_intern_atom_reply(AConn, cookie, nil);
  if reply <> nil then
  begin
    Result := reply^.atom;
    c_free(reply);
  end;
end;

procedure LauncherButtonClick(widget: FtWidget; user_data: Pointer); cdecl;
begin
  if Assigned(GBottomPanelInstance) then
    GBottomPanelInstance.OnLauncherClicked();
end;

procedure ShowDesktopButtonClick(widget: FtWidget; user_data: Pointer); cdecl;
begin
  if Assigned(GBottomPanelInstance) then
    GBottomPanelInstance.ToggleShowDesktop();
end;

procedure TaskButtonClick(widget: FtWidget; user_data: Pointer); cdecl;
var
  winId: Cardinal;
begin
  winId := Cardinal(PtrUInt(user_data));
  if Assigned(GBottomPanelInstance) and (winId <> 0) then
    GBottomPanelInstance.OnTaskClicked(winId);
end;

procedure PanelTickCallback(user_data: Pointer); cdecl;
begin
  if Assigned(GBottomPanelInstance) then
    GBottomPanelInstance.Tick();
end;

// -----------------------------------------------------------------------------
// TShellBottomPanel Implementation
// -----------------------------------------------------------------------------

constructor TShellBottomPanel.Create(ALauncher: TShellLauncher);
begin
  inherited Create();
  GBottomPanelInstance := Self;
  FLauncher := ALauncher;
  FIsVisible := False;
  FShowingDesktop := False;
  FPanelHeight := 38;
  FLastClockSec := -1;
  FLastActiveWin := 0;
  FActiveWindow := 0;

  if IsLibFtLoaded() and Assigned(ft_screen_get_width) then
    FPanelWidth := ft_screen_get_width()
  else
    FPanelWidth := 1920;

  if IsLibFtLoaded() and Assigned(ft_backend_get_connection) then
  begin
    FConn := Pxcb_connection_t(ft_backend_get_connection());
    FScreen := Pxcb_screen_t(ft_backend_get_screen());
    if FScreen <> nil then
      FRootWindow := FScreen^.root
    else
      FRootWindow := 0;
  end;

  InitAtoms();
  SetupWindow();

  if IsLibFtLoaded() and Assigned(ft_set_tick_callback) then
    ft_set_tick_callback(@PanelTickCallback, Self);
end;

destructor TShellBottomPanel.Destroy();
var
  i: Integer;
begin
  if GBottomPanelInstance = Self then
    GBottomPanelInstance := nil;

  if IsLibFtLoaded() and Assigned(ft_set_tick_callback) then
    ft_set_tick_callback(nil, nil);

  for i := 0 to High(FTasks) do
  begin
    if Assigned(FTasks[i].Button) and Assigned(ft_widget_destroy) then
      ft_widget_destroy(FTasks[i].Button);
  end;
  SetLength(FTasks, 0);

  inherited Destroy();
end;

procedure TShellBottomPanel.InitAtoms();
begin
  if FConn = nil then Exit;

  FAtomNetClientList         := InternAtom(FConn, '_NET_CLIENT_LIST');
  FAtomNetActiveWindow       := InternAtom(FConn, '_NET_ACTIVE_WINDOW');
  FAtomNetWmName             := InternAtom(FConn, '_NET_WM_NAME');
  FAtomNetWmState            := InternAtom(FConn, '_NET_WM_STATE');
  FAtomNetWmStateHidden      := InternAtom(FConn, '_NET_WM_STATE_HIDDEN');
  FAtomNetWmStateSkipTaskbar := InternAtom(FConn, '_NET_WM_STATE_SKIP_TASKBAR');
  FAtomNetWmWindowType       := InternAtom(FConn, '_NET_WM_WINDOW_TYPE');
  FAtomNetWmWindowTypeDock   := InternAtom(FConn, '_NET_WM_WINDOW_TYPE_DOCK');
  FAtomNetWmWindowTypeDesk   := InternAtom(FConn, '_NET_WM_WINDOW_TYPE_DESKTOP');
  FAtomNetWmWindowTypeSplash := InternAtom(FConn, '_NET_WM_WINDOW_TYPE_SPLASH');
  FAtomNetWmWindowTypeUtil   := InternAtom(FConn, '_NET_WM_WINDOW_TYPE_UTILITY');
  FAtomNetWmWindowTypeTool   := InternAtom(FConn, '_NET_WM_WINDOW_TYPE_TOOLBAR');
  FAtomNetWmWindowTypeMenu   := InternAtom(FConn, '_NET_WM_WINDOW_TYPE_MENU');
  FAtomNetWmWindowTypeTip    := InternAtom(FConn, '_NET_WM_WINDOW_TYPE_TOOLTIP');
  FAtomNetShowingDesktop     := InternAtom(FConn, '_NET_SHOWING_DESKTOP');
  FAtomUtf8String            := InternAtom(FConn, 'UTF8_STRING');
  FAtomWMChangeState         := InternAtom(FConn, 'WM_CHANGE_STATE');
  FAtomWMName                := InternAtom(FConn, 'WM_NAME');
end;

procedure TShellBottomPanel.SetupWindow();
var
  py: Integer;
begin
  if not IsLibFtLoaded() or not Assigned(ft_window_create) then Exit;

  py := PanelY();
  FWindow := ft_window_create(FPanelWidth, FPanelHeight, 'shellsama-bottom-panel');
  if FWindow = nil then Exit;

  ft_window_set_window_type(FWindow, FT_WINDOW_TYPE_DOCK);
  ft_window_set_borderless(FWindow, 1);
  ft_window_set_skip_taskbar(FWindow, 1);
  ft_window_set_position(FWindow, 0, py);

  // Reserve bottom screen space via _NET_WM_STRUT & _NET_WM_STRUT_PARTIAL
  if Assigned(ft_window_set_strut_partial) then
    ft_window_set_strut_partial(
      FWindow,
      0, 0, 0, FPanelHeight,
      0, 0, 0, 0, 0, 0,
      0, FPanelWidth - 1
    );

  // 1. Launcher button on the left
  if Assigned(ft_button_create) then
  begin
    FLauncherBtn := ft_button_create(FWindow, 6, 3, 110, 32, '✦ Samarinda');
    if Assigned(FLauncherBtn) then
    begin
      ft_button_set_toggle(FLauncherBtn, 1);
      ft_button_set_corner_radius(FLauncherBtn, 6.0);
      ft_button_on_click(FLauncherBtn, @LauncherButtonClick, Self);
    end;
  end;

  // 2. Clock text label on the right
  if Assigned(ft_text_create) then
  begin
    FClockText := ft_text_create(FWindow, FPanelWidth - 164, 3, 126, 32, '--:--');
    if Assigned(FClockText) and Assigned(ft_text_set_alignment) then
      ft_text_set_alignment(FClockText, FT_TEXT_ALIGN_CENTER);
  end;

  // 3. Show Desktop button on the extreme right
  if Assigned(ft_button_create) then
  begin
    FShowDesktopBtn := ft_button_create(FWindow, FPanelWidth - 34, 3, 28, 32, '▤');
    if Assigned(FShowDesktopBtn) then
    begin
      ft_button_set_corner_radius(FShowDesktopBtn, 6.0);
      ft_button_on_click(FShowDesktopBtn, @ShowDesktopButtonClick, Self);
    end;
  end;

  UpdateClock();
  RefreshTasks();
end;

function TShellBottomPanel.PanelX(): Integer;
begin
  Result := 0;
end;

function TShellBottomPanel.PanelY(): Integer;
var
  sh: Integer;
begin
  if IsLibFtLoaded() and Assigned(ft_screen_get_height) then
    sh := ft_screen_get_height()
  else
    sh := 1080;
  Result := sh - FPanelHeight;
end;

function TShellBottomPanel.PanelWidth(): Integer;
begin
  Result := FPanelWidth;
end;

function TShellBottomPanel.PanelHeight(): Integer;
begin
  Result := FPanelHeight;
end;

function TShellBottomPanel.GetTaskCount(): Integer;
begin
  Result := Length(FTasks);
end;

procedure TShellBottomPanel.Show();
begin
  if FWindow = nil then Exit;
  ft_widget_show(FWindow);
  FIsVisible := True;
  RefreshTasks();
  UpdateClock();
end;

procedure TShellBottomPanel.Hide();
begin
  if FWindow = nil then Exit;
  ft_widget_hide(FWindow);
  FIsVisible := False;
end;

function TShellBottomPanel.QueryClientList(): TWindowIdArray;
var
  cookie: xcb_get_property_cookie_t;
  reply: Pxcb_get_property_reply_t;
  len, i: Integer;
  pWins: Pxcb_window_t;
begin
  SetLength(Result, 0);
  if (FConn = nil) or (FRootWindow = 0) or (FAtomNetClientList = 0) then Exit;

  cookie := xcb_get_property(FConn, 0, FRootWindow, FAtomNetClientList, XCB_ATOM_WINDOW, 0, 1024);
  reply := xcb_get_property_reply(FConn, cookie, nil);
  if reply = nil then Exit;

  try
    len := xcb_get_property_value_length(reply) div SizeOf(xcb_window_t);
    if len > 0 then
    begin
      pWins := Pxcb_window_t(xcb_get_property_value(reply));
      SetLength(Result, len);
      for i := 0 to len - 1 do
        Result[i] := pWins[i];
    end;
  finally
    c_free(reply);
  end;
end;

function TShellBottomPanel.QueryActiveWindow(): Cardinal;
var
  cookie: xcb_get_property_cookie_t;
  reply: Pxcb_get_property_reply_t;
begin
  Result := 0;
  if (FConn = nil) or (FRootWindow = 0) or (FAtomNetActiveWindow = 0) then Exit;

  cookie := xcb_get_property(FConn, 0, FRootWindow, FAtomNetActiveWindow, XCB_ATOM_WINDOW, 0, 1);
  reply := xcb_get_property_reply(FConn, cookie, nil);
  if reply = nil then Exit;

  try
    if xcb_get_property_value_length(reply) >= SizeOf(xcb_window_t) then
      Result := Pxcb_window_t(xcb_get_property_value(reply))^;
  finally
    c_free(reply);
  end;
end;

function TShellBottomPanel.QueryWindowTitle(AWin: Cardinal): string;
var
  cookie: xcb_get_property_cookie_t;
  reply: Pxcb_get_property_reply_t;
  len: Integer;
begin
  Result := '';
  if (FConn = nil) or (AWin = 0) then Exit;

  // Try _NET_WM_NAME (UTF-8)
  if (FAtomNetWmName <> 0) and (FAtomUtf8String <> 0) then
  begin
    cookie := xcb_get_property(FConn, 0, AWin, FAtomNetWmName, FAtomUtf8String, 0, 256);
    reply := xcb_get_property_reply(FConn, cookie, nil);
    if reply <> nil then
    begin
      len := xcb_get_property_value_length(reply);
      if len > 0 then
      begin
        SetString(Result, PAnsiChar(xcb_get_property_value(reply)), len);
        c_free(reply);
        Exit;
      end;
      c_free(reply);
    end;
  end;

  // Fallback to WM_NAME (ISO-8859-1 or ASCII)
  if FAtomWMName <> 0 then
  begin
    cookie := xcb_get_property(FConn, 0, AWin, FAtomWMName, XCB_ATOM_STRING, 0, 256);
    reply := xcb_get_property_reply(FConn, cookie, nil);
    if reply <> nil then
    begin
      len := xcb_get_property_value_length(reply);
      if len > 0 then
        SetString(Result, PAnsiChar(xcb_get_property_value(reply)), len);
      c_free(reply);
    end;
  end;
end;

function TShellBottomPanel.ShouldShowTask(AWin: Cardinal): Boolean;
var
  cookie: xcb_get_property_cookie_t;
  reply: Pxcb_get_property_reply_t;
  atoms: Pxcb_atom_t;
  count, i: Integer;
  panelWin: Cardinal;
begin
  Result := False;
  if (FConn = nil) or (AWin = 0) then Exit;

  // Exclude panel window itself
  if Assigned(FWindow) and Assigned(ft_window_get_native_handle) then
  begin
    panelWin := Cardinal(PtrUInt(ft_window_get_native_handle(FWindow)));
    if AWin = panelWin then Exit(False);
  end;

  // Exclude launcher window if open
  if Assigned(FLauncher) and Assigned(FLauncher.Window) and Assigned(ft_window_get_native_handle) then
  begin
    panelWin := Cardinal(PtrUInt(ft_window_get_native_handle(FLauncher.Window)));
    if AWin = panelWin then Exit(False);
  end;

  // Check _NET_WM_STATE for SKIP_TASKBAR
  if (FAtomNetWmState <> 0) and (FAtomNetWmStateSkipTaskbar <> 0) then
  begin
    cookie := xcb_get_property(FConn, 0, AWin, FAtomNetWmState, XCB_ATOM_ATOM, 0, 64);
    reply := xcb_get_property_reply(FConn, cookie, nil);
    if reply <> nil then
    begin
      count := xcb_get_property_value_length(reply) div SizeOf(xcb_atom_t);
      if count > 0 then
      begin
        atoms := Pxcb_atom_t(xcb_get_property_value(reply));
        for i := 0 to count - 1 do
        begin
          if atoms[i] = FAtomNetWmStateSkipTaskbar then
          begin
            c_free(reply);
            Exit(False);
          end;
        end;
      end;
      c_free(reply);
    end;
  end;

  // Check _NET_WM_WINDOW_TYPE
  if (FAtomNetWmWindowType <> 0) then
  begin
    cookie := xcb_get_property(FConn, 0, AWin, FAtomNetWmWindowType, XCB_ATOM_ATOM, 0, 64);
    reply := xcb_get_property_reply(FConn, cookie, nil);
    if reply <> nil then
    begin
      count := xcb_get_property_value_length(reply) div SizeOf(xcb_atom_t);
      if count > 0 then
      begin
        atoms := Pxcb_atom_t(xcb_get_property_value(reply));
        for i := 0 to count - 1 do
        begin
          if (atoms[i] = FAtomNetWmWindowTypeDock) or
             (atoms[i] = FAtomNetWmWindowTypeDesk) or
             (atoms[i] = FAtomNetWmWindowTypeSplash) or
             (atoms[i] = FAtomNetWmWindowTypeUtil) or
             (atoms[i] = FAtomNetWmWindowTypeTool) or
             (atoms[i] = FAtomNetWmWindowTypeMenu) or
             (atoms[i] = FAtomNetWmWindowTypeTip) then
          begin
            c_free(reply);
            Exit(False);
          end;
        end;
      end;
      c_free(reply);
    end;
  end;

  Result := True;
end;

function TShellBottomPanel.IsWindowMinimized(AWin: Cardinal): Boolean;
var
  cookie: xcb_get_property_cookie_t;
  reply: Pxcb_get_property_reply_t;
  atoms: Pxcb_atom_t;
  count, i: Integer;
begin
  Result := False;
  if (FConn = nil) or (AWin = 0) or (FAtomNetWmState = 0) or (FAtomNetWmStateHidden = 0) then Exit;

  cookie := xcb_get_property(FConn, 0, AWin, FAtomNetWmState, XCB_ATOM_ATOM, 0, 64);
  reply := xcb_get_property_reply(FConn, cookie, nil);
  if reply = nil then Exit;

  try
    count := xcb_get_property_value_length(reply) div SizeOf(xcb_atom_t);
    if count > 0 then
    begin
      atoms := Pxcb_atom_t(xcb_get_property_value(reply));
      for i := 0 to count - 1 do
      begin
        if atoms[i] = FAtomNetWmStateHidden then
          Exit(True);
      end;
    end;
  finally
    c_free(reply);
  end;
end;

procedure TShellBottomPanel.RefreshTasks();
var
  rawWins: array of Cardinal;
  validWins: array of Cardinal;
  i, j, n: Integer;
  title: string;
  found: Boolean;
  oldTasks: array of TTaskItem;
begin
  rawWins := QueryClientList();
  FActiveWindow := QueryActiveWindow();

  // Filter windows eligible for taskbar
  SetLength(validWins, 0);
  for i := 0 to High(rawWins) do
  begin
    if ShouldShowTask(rawWins[i]) then
    begin
      SetLength(validWins, Length(validWins) + 1);
      validWins[High(validWins)] := rawWins[i];
    end;
  end;

  // Preserve existing task items if matching
  oldTasks := Copy(FTasks);
  SetLength(FTasks, Length(validWins));

  for i := 0 to High(validWins) do
  begin
    FTasks[i].Window := validWins[i];
    FTasks[i].IsActive := (validWins[i] = FActiveWindow);
    FTasks[i].IsMinimized := IsWindowMinimized(validWins[i]);

    // Check if previously existed
    found := False;
    for j := 0 to High(oldTasks) do
    begin
      if oldTasks[j].Window = validWins[i] then
      begin
        FTasks[i].Title := oldTasks[j].Title;
        FTasks[i].Button := oldTasks[j].Button;
        oldTasks[j].Button := nil; // transfer ownership
        found := True;
        Break;
      end;
    end;

    title := QueryWindowTitle(validWins[i]);
    if title = '' then
      title := 'Window ' + IntToStr(validWins[i]);
    FTasks[i].Title := title;

    if not found then
      FTasks[i].Button := nil;
  end;

  // Destroy remaining unused buttons
  for j := 0 to High(oldTasks) do
  begin
    if Assigned(oldTasks[j].Button) and Assigned(ft_widget_destroy) then
      ft_widget_destroy(oldTasks[j].Button);
  end;

  LayoutButtons();
end;

procedure TShellBottomPanel.LayoutButtons();
var
  startX, endX, availW, numTasks: Integer;
  btnW, btnX, i: Integer;
  dispTitle: string;
begin
  if FWindow = nil then Exit;

  startX := 122;
  endX := FPanelWidth - 172;
  availW := Max(100, endX - startX);
  numTasks := Length(FTasks);

  if numTasks = 0 then Exit;

  btnW := Min(160, Max(70, (availW - (numTasks - 1) * 4) div numTasks));

  for i := 0 to numTasks - 1 do
  begin
    btnX := startX + i * (btnW + 4);
    dispTitle := FTasks[i].Title;
    if Length(dispTitle) > 22 then
      dispTitle := Copy(dispTitle, 1, 20) + '..';

    if FTasks[i].Button = nil then
    begin
      if Assigned(ft_button_create) then
      begin
        FTasks[i].Button := ft_button_create(FWindow, btnX, 3, btnW, 32, PChar(dispTitle));
        if Assigned(FTasks[i].Button) then
        begin
          ft_button_set_toggle(FTasks[i].Button, 1);
          ft_button_set_corner_radius(FTasks[i].Button, 6.0);
          ft_button_on_click(FTasks[i].Button, @TaskButtonClick, Pointer(PtrUInt(FTasks[i].Window)));
        end;
      end;
    end
    else
    begin
      if Assigned(ft_widget_set_bounds) then
        ft_widget_set_bounds(FTasks[i].Button, btnX, 3, btnW, 32);
      if Assigned(ft_button_set_caption) then
        ft_button_set_caption(FTasks[i].Button, PChar(dispTitle));
    end;

    if Assigned(FTasks[i].Button) and Assigned(ft_button_set_toggled) then
    begin
      if FTasks[i].IsActive then
        ft_button_set_toggled(FTasks[i].Button, 1)
      else
        ft_button_set_toggled(FTasks[i].Button, 0);
    end;
  end;
end;

procedure TShellBottomPanel.UpdateClock();
var
  dt: TDateTime;
  sec: Integer;
  timeStr: string;
begin
  dt := Now();
  sec := DateTimeToTimeStamp(dt).Time div 1000;
  if sec = FLastClockSec then Exit;
  FLastClockSec := sec;

  timeStr := FormatDateTime('hh:nn:ss', dt);
  if Assigned(FClockText) and Assigned(ft_text_set_text) then
    ft_text_set_text(FClockText, PChar(timeStr));
end;

procedure TShellBottomPanel.Tick();
var
  curActive: Cardinal;
begin
  UpdateClock();

  // Sync launcher button toggled state
  if Assigned(FLauncherBtn) and Assigned(FLauncher) and Assigned(ft_button_set_toggled) then
    ft_button_set_toggled(FLauncherBtn, Ord(FLauncher.IsVisible));

  // Check if active window changed
  curActive := QueryActiveWindow();
  if curActive <> FLastActiveWin then
  begin
    FLastActiveWin := curActive;
    RefreshTasks();
  end;
end;

procedure TShellBottomPanel.OnLauncherClicked();
begin
  if Assigned(FLauncher) then
  begin
    FLauncher.Toggle();
    if Assigned(FLauncherBtn) and Assigned(ft_button_set_toggled) then
      ft_button_set_toggled(FLauncherBtn, Ord(FLauncher.IsVisible));
  end;
end;

procedure TShellBottomPanel.OnTaskClicked(AWin: Cardinal);
begin
  if AWin = 0 then Exit;

  if AWin = QueryActiveWindow() then
  begin
    // Active window clicked -> minimize it
    MinimizeWindow(AWin);
  end
  else
  begin
    // Inactive or minimized window clicked -> activate it
    ActivateWindow(AWin);
  end;
  RefreshTasks();
end;

procedure TShellBottomPanel.ActivateWindow(AWin: Cardinal);
var
  ev: xcb_client_message_event_t;
  data32: PCardinalArray;
begin
  if (FConn = nil) or (AWin = 0) or (FAtomNetActiveWindow = 0) then Exit;

  FillChar(ev, SizeOf(ev), 0);
  ev.response_type := XCB_CLIENT_MESSAGE;
  ev.format := 32;
  ev.window := AWin;
  ev.type_ := FAtomNetActiveWindow;
  data32 := PCardinalArray(@ev.data.raw[0]);
  data32^[0] := 1; // 1 = application request
  data32^[1] := XCB_CURRENT_TIME;

  xcb_send_event(FConn, 0, FRootWindow,
                 XCB_EVENT_MASK_SUBSTRUCTURE_REDIRECT or XCB_EVENT_MASK_SUBSTRUCTURE_NOTIFY,
                 PAnsiChar(@ev));
  xcb_flush(FConn);
end;

procedure TShellBottomPanel.MinimizeWindow(AWin: Cardinal);
var
  ev: xcb_client_message_event_t;
  data32: PCardinalArray;
begin
  if (FConn = nil) or (AWin = 0) then Exit;

  // 1. Send EWMH _NET_WM_STATE add _NET_WM_STATE_HIDDEN
  if (FAtomNetWmState <> 0) and (FAtomNetWmStateHidden <> 0) then
  begin
    FillChar(ev, SizeOf(ev), 0);
    ev.response_type := XCB_CLIENT_MESSAGE;
    ev.format := 32;
    ev.window := AWin;
    ev.type_ := FAtomNetWmState;
    data32 := PCardinalArray(@ev.data.raw[0]);
    data32^[0] := 1; // _NET_WM_STATE_ADD
    data32^[1] := FAtomNetWmStateHidden;
    data32^[2] := 0;
    data32^[3] := 1; // application
    xcb_send_event(FConn, 0, FRootWindow,
                   XCB_EVENT_MASK_SUBSTRUCTURE_REDIRECT or XCB_EVENT_MASK_SUBSTRUCTURE_NOTIFY,
                   PAnsiChar(@ev));
  end;

  // 2. Also send ICCCM WM_CHANGE_STATE IconicState (3)
  if FAtomWMChangeState <> 0 then
  begin
    FillChar(ev, SizeOf(ev), 0);
    ev.response_type := XCB_CLIENT_MESSAGE;
    ev.format := 32;
    ev.window := AWin;
    ev.type_ := FAtomWMChangeState;
    data32 := PCardinalArray(@ev.data.raw[0]);
    data32^[0] := 3; // IconicState
    xcb_send_event(FConn, 0, FRootWindow,
                   XCB_EVENT_MASK_SUBSTRUCTURE_REDIRECT or XCB_EVENT_MASK_SUBSTRUCTURE_NOTIFY,
                   PAnsiChar(@ev));
  end;

  xcb_flush(FConn);
end;

procedure TShellBottomPanel.ToggleShowDesktop();
var
  ev: xcb_client_message_event_t;
  data32: PCardinalArray;
begin
  if (FConn = nil) or (FRootWindow = 0) or (FAtomNetShowingDesktop = 0) then Exit;

  FShowingDesktop := not FShowingDesktop;

  FillChar(ev, SizeOf(ev), 0);
  ev.response_type := XCB_CLIENT_MESSAGE;
  ev.format := 32;
  ev.window := FRootWindow;
  ev.type_ := FAtomNetShowingDesktop;
  data32 := PCardinalArray(@ev.data.raw[0]);
  if FShowingDesktop then
    data32^[0] := 1
  else
    data32^[0] := 0;

  xcb_send_event(FConn, 0, FRootWindow,
                 XCB_EVENT_MASK_SUBSTRUCTURE_REDIRECT or XCB_EVENT_MASK_SUBSTRUCTURE_NOTIFY,
                 PAnsiChar(@ev));
  xcb_flush(FConn);
end;

end.
