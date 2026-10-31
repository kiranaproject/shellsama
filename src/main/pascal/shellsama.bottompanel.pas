{ Unit ShellSama.BottomPanel — Desktop Bottom Panel & Taskbar for Samarinda DE }

unit ShellSama.BottomPanel;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils, Math,
  Floria.XCB,
  ftpas.api, ftpas.types, ftpas,
  ShellSama.DesktopApps,
  ShellSama.Launcher;

type
  PCardinalArray = ^TCardinalArray;
  TCardinalArray = array[0..4] of Cardinal;

  TWindowIdArray = array of Cardinal;

  TWindowIconItem = record
    Window: Cardinal;
    Bitmap: TFtBitmap;
  end;

  TTaskItem = record
    Window     : Cardinal;
    Title      : string;
    IsActive   : Boolean;
    IsMinimized: Boolean;
    IsMaximized: Boolean;
    Button     : TFtButton;
    // Per-task context menu. One menu per task rather than one shared menu,
    // because the toolkit pops a widget's own menu and offers no hook before it
    // opens: a shared menu could not tell which task was right-clicked, and
    // OnPress only fires for the left button, so it is not a usable hook either.
    Menu       : TFtPopupMenu;
    MenuMinimize: TFtMenuItem;
    MenuMaximize: TFtMenuItem;
    MenuClose   : TFtMenuItem;
  end;

  TShellBottomPanel = class
  private
    FWindow         : TFtWindow;
    FLauncher       : TShellLauncher;
    FIsVisible      : Boolean;
    FPanelHeight    : Integer;
    FPanelWidth     : Integer;

    FTasks          : array of TTaskItem;
    FActiveWindow   : Cardinal;
    FLastActiveWin  : Cardinal;
    // Window-id signature of the task set as of the last refresh. Lets Tick notice
    // a window appearing or disappearing without a full query every tick.
    FLastTaskSignature : AnsiString;

    // XCB connection details
    FConn           : Pxcb_connection_t;
    FScreen         : Pxcb_screen_t;
    FRootWindow     : Cardinal;

    // Cached EWMH atoms
    FAtomNetClientList        : Cardinal;
    FAtomNetActiveWindow      : Cardinal;
    FAtomNetWmName            : Cardinal;
    FAtomNetWmIcon            : Cardinal;
    FAtomNetWmState           : Cardinal;
    FAtomNetWmStateHidden     : Cardinal;
    FAtomNetWmStateMaxVert    : Cardinal;
    FAtomNetWmStateMaxHorz    : Cardinal;
    FAtomNetCloseWindow       : Cardinal;
    FAtomNetWmStateSkipTaskbar: Cardinal;
    FAtomNetWmWindowType      : Cardinal;
    FAtomNetWmWindowTypeDock  : Cardinal;
    FAtomNetWmWindowTypeDesk  : Cardinal;
    FAtomNetWmWindowTypeSplash: Cardinal;
    FAtomNetWmWindowTypeUtil  : Cardinal;
    FAtomNetWmWindowTypeTool  : Cardinal;
    FAtomNetWmWindowTypeMenu  : Cardinal;
    FAtomNetWmWindowTypeTip   : Cardinal;
    FAtomUtf8String           : Cardinal;
    FAtomWMChangeState        : Cardinal;
    FAtomWMName               : Cardinal;
    FAtomWMClass              : Cardinal;

    // Window icon cache
    FWindowIconCache          : array of TWindowIconItem;

    procedure InitAtoms();
    procedure SetupWindow();
    procedure LayoutButtons();
    function QueryClientList(): TWindowIdArray;
    function QueryActiveWindow(): Cardinal;
    function QueryWindowTitle(AWin: Cardinal): string;
    function ShouldShowTask(AWin: Cardinal): Boolean;
    function IsWindowMinimized(AWin: Cardinal): Boolean;
    function IsWindowMaximized(AWin: Cardinal): Boolean;

    procedure HandleTaskButtonClick(Sender: TFtButton);

    // Task context menu
    procedure BuildTaskMenu(var ATask: TTaskItem);
    procedure UpdateTaskMenuState(var ATask: TTaskItem);
    procedure HandleTaskMenuMinimize(Sender: TFtMenuItem);
    procedure HandleTaskMenuMaximize(Sender: TFtMenuItem);
    procedure HandleTaskMenuClose(Sender: TFtMenuItem);
  public
    constructor Create(ALauncher: TShellLauncher = nil);
    destructor Destroy(); override;

    procedure Show();
    procedure Hide();
    procedure RefreshTasks();
    procedure Tick();
    // Cheap signature of the current task set, so the panel can notice a window
    // appearing or disappearing without a full refresh.
    function TaskSetSignature(): AnsiString;

    function QueryWindowIcon(AWin: Cardinal; APreferredSize: Integer = 18): TFtBitmap;
    function GetOrLoadWindowIcon(AWin: Cardinal; APreferredSize: Integer = 18): TFtBitmap;

    procedure ActivateWindow(AWin: Cardinal);
    procedure MinimizeWindow(AWin: Cardinal);
    procedure UnminimizeWindow(AWin: Cardinal);
    procedure MaximizeWindow(AWin: Cardinal);
    procedure RestoreWindow(AWin: Cardinal);
    procedure CloseWindow(AWin: Cardinal);
    procedure OnTaskClicked(AWin: Cardinal);

    function PanelX(): Integer;
    function PanelY(): Integer;
    function PanelWidth(): Integer;
    function PanelHeight(): Integer;
    function GetTaskCount(): Integer;
    function GetIconCacheCount(): Integer;
    function GetTaskIcon(AIndex: Integer): TFtBitmap;

    property IsVisible     : Boolean         read FIsVisible;
    property ActiveWindow  : Cardinal        read FActiveWindow;
    property TaskCount     : Integer         read GetTaskCount;
    property IconCacheCount: Integer         read GetIconCacheCount;
    property WindowWidget  : TFtWindow       read FWindow;
  end;

var
  GBottomPanelInstance: TShellBottomPanel = nil;

implementation

uses
  ShellSama.TopPanel;

const
  PANEL_TIMER_MS = 250;




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

procedure PanelTickCallback(user_data: Pointer); cdecl;
begin
  if Assigned(user_data) then
    TShellBottomPanel(user_data).Tick();
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
  FPanelHeight := 38;
  FLastActiveWin := 0;
  FLastTaskSignature := '';
  FActiveWindow := 0;

  if FtIsLibLoaded() and Assigned(ft_screen_get_width) then
    FPanelWidth := FtApp().ScreenWidth
  else
    FPanelWidth := 1920;

  if FtIsLibLoaded() and Assigned(ft_backend_get_connection) then
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
  SetLength(FWindowIconCache, 0);

  if FtIsLibLoaded() and (GTopPanelInstance = nil) then
  begin
    if Assigned(ft_set_timer) then
      ft_set_timer(PANEL_TIMER_MS, @PanelTickCallback, Self)
    else if Assigned(ft_set_tick_callback) then
      ft_set_tick_callback(@PanelTickCallback, Self);
  end;
end;

destructor TShellBottomPanel.Destroy();
var
  i: Integer;
begin
  if GBottomPanelInstance = Self then
    GBottomPanelInstance := nil;

  if FtIsLibLoaded() and (GTopPanelInstance = nil) then
  begin
    if Assigned(ft_set_timer) then
      ft_set_timer(0, nil, nil)
    else if Assigned(ft_set_tick_callback) then
      ft_set_tick_callback(nil, nil);
  end;

  for i := 0 to High(FTasks) do
  begin
    if Assigned(FTasks[i].Button) then
    begin
      if Assigned(FTasks[i].Menu) then
        FTasks[i].Button.ContextMenuHandle := nil;
      FTasks[i].Button.Free();
      FTasks[i].Button := nil;
    end;
    if Assigned(FTasks[i].Menu) then
    begin
      FTasks[i].Menu.Free();
      FTasks[i].Menu := nil;
    end;
  end;
  SetLength(FTasks, 0);

  for i := 0 to High(FWindowIconCache) do
  begin
    if Assigned(FWindowIconCache[i].Bitmap) then
    begin
      FWindowIconCache[i].Bitmap.Free();
      FWindowIconCache[i].Bitmap := nil;
    end;
  end;
  SetLength(FWindowIconCache, 0);

  if Assigned(FWindow) then
  begin
    FWindow.Free();
    FWindow := nil;
  end;

  inherited Destroy();
end;

procedure TShellBottomPanel.HandleTaskButtonClick(Sender: TFtButton);
begin
  if Assigned(Sender) and (Sender.Tag <> 0) then
    OnTaskClicked(Cardinal(Sender.Tag));
end;

// Builds the per-task context menu.
//
// One menu per task rather than one shared menu: the toolkit pops a widget's own
// ContextMenu and gives no hook before it opens, and OnPress only fires for the
// left button, so a shared menu would have no way to learn which task was
// right-clicked. The cost is one native popup window per task, created lazily
// here and freed with the task.
procedure TShellBottomPanel.BuildTaskMenu(var ATask: TTaskItem);
var
  it: TFtMenuItem;
begin
  if ATask.Window = 0 then Exit;
  if Assigned(ATask.Menu) then Exit;
  if not FtIsLibLoaded() then Exit;

  ATask.Menu := TFtPopupMenu.Create(FWindow);
  if ATask.Menu = nil then Exit;

  ATask.MenuMinimize := ATask.Menu.AddItem('Minimize', @HandleTaskMenuMinimize);
  ATask.MenuMaximize := ATask.Menu.AddItem('Maximize', @HandleTaskMenuMaximize);
  ATask.Menu.AddSeparator();
  ATask.MenuClose := ATask.Menu.AddItem('Close', @HandleTaskMenuClose);

  // Every item carries the window id, so one handler shape serves all tasks and
  // the callbacks need no shared mutable state.
  it := ATask.MenuMinimize;
  if it <> nil then it.Tag := Int64(ATask.Window);
  it := ATask.MenuMaximize;
  if it <> nil then it.Tag := Int64(ATask.Window);
  it := ATask.MenuClose;
  if it <> nil then it.Tag := Int64(ATask.Window);

  UpdateTaskMenuState(ATask);
end;

procedure TShellBottomPanel.UpdateTaskMenuState(var ATask: TTaskItem);
begin
  if not Assigned(ATask.Menu) then Exit;

  // Captions reflect current state, the way MATE and KDE do it, so the user is
  // never offered an action that would do nothing.
  //
  // Note: TFtMenuItem.Enabled blocks the click but the toolkit paints enabled and
  // disabled items identically, so a disabled "Minimize" would look clickable and
  // silently do nothing. Toggling the caption avoids that entirely.
  if Assigned(ATask.MenuMinimize) then
  begin
    if ATask.IsMinimized then
      ATask.MenuMinimize.Caption := 'Restore'
    else
      ATask.MenuMinimize.Caption := 'Minimize';
  end;

  if Assigned(ATask.MenuMaximize) then
  begin
    if ATask.IsMaximized then
      ATask.MenuMaximize.Caption := 'Restore'
    else
      ATask.MenuMaximize.Caption := 'Maximize';
  end;
end;

procedure TShellBottomPanel.HandleTaskMenuMinimize(Sender: TFtMenuItem);
var
  win: Cardinal;
begin
  if not Assigned(Sender) then Exit;
  win := Cardinal(Sender.Tag);
  // Re-read the state rather than trusting the cached flag: the window may have
  // been minimized or restored since the menu was built.
  if IsWindowMinimized(win) then
  begin
    UnminimizeWindow(win);
    ActivateWindow(win);
  end
  else
    MinimizeWindow(win);
end;

procedure TShellBottomPanel.HandleTaskMenuMaximize(Sender: TFtMenuItem);
var
  win: Cardinal;
begin
  if not Assigned(Sender) then Exit;
  win := Cardinal(Sender.Tag);
  // Toggle rather than trusting the cached flag: the window may have been
  // maximized or restored by its own titlebar since the menu was built.
  if IsWindowMaximized(win) then
    RestoreWindow(win)
  else
    MaximizeWindow(win);
end;

procedure TShellBottomPanel.HandleTaskMenuClose(Sender: TFtMenuItem);
begin
  if Assigned(Sender) then
    CloseWindow(Cardinal(Sender.Tag));
end;

procedure TShellBottomPanel.InitAtoms();
begin
  if FConn = nil then Exit;

  FAtomNetClientList         := InternAtom(FConn, '_NET_CLIENT_LIST');
  FAtomNetActiveWindow       := InternAtom(FConn, '_NET_ACTIVE_WINDOW');
  FAtomNetWmName             := InternAtom(FConn, '_NET_WM_NAME');
  FAtomNetWmIcon             := InternAtom(FConn, '_NET_WM_ICON');
  FAtomNetWmState            := InternAtom(FConn, '_NET_WM_STATE');
  FAtomNetWmStateHidden      := InternAtom(FConn, '_NET_WM_STATE_HIDDEN');
  FAtomNetWmStateMaxVert     := InternAtom(FConn, '_NET_WM_STATE_MAXIMIZED_VERT');
  FAtomNetWmStateMaxHorz     := InternAtom(FConn, '_NET_WM_STATE_MAXIMIZED_HORZ');
  FAtomNetCloseWindow        := InternAtom(FConn, '_NET_CLOSE_WINDOW');
  FAtomNetWmStateSkipTaskbar := InternAtom(FConn, '_NET_WM_STATE_SKIP_TASKBAR');
  FAtomNetWmWindowType       := InternAtom(FConn, '_NET_WM_WINDOW_TYPE');
  FAtomNetWmWindowTypeDock   := InternAtom(FConn, '_NET_WM_WINDOW_TYPE_DOCK');
  FAtomNetWmWindowTypeDesk   := InternAtom(FConn, '_NET_WM_WINDOW_TYPE_DESKTOP');
  FAtomNetWmWindowTypeSplash := InternAtom(FConn, '_NET_WM_WINDOW_TYPE_SPLASH');
  FAtomNetWmWindowTypeUtil   := InternAtom(FConn, '_NET_WM_WINDOW_TYPE_UTILITY');
  FAtomNetWmWindowTypeTool   := InternAtom(FConn, '_NET_WM_WINDOW_TYPE_TOOLBAR');
  FAtomNetWmWindowTypeMenu   := InternAtom(FConn, '_NET_WM_WINDOW_TYPE_MENU');
  FAtomNetWmWindowTypeTip    := InternAtom(FConn, '_NET_WM_WINDOW_TYPE_TOOLTIP');
  FAtomUtf8String            := InternAtom(FConn, 'UTF8_STRING');
  FAtomWMChangeState         := InternAtom(FConn, 'WM_CHANGE_STATE');
  FAtomWMName                := InternAtom(FConn, 'WM_NAME');
  FAtomWMClass               := InternAtom(FConn, 'WM_CLASS');
end;

procedure TShellBottomPanel.SetupWindow();
var
  py: Integer;
begin
  if not FtIsLibLoaded() then Exit;

  py := PanelY();
  FWindow := TFtWindow.Create(FPanelWidth, FPanelHeight, 'shellsama-bottom-panel');
  if FWindow = nil then Exit;

  FWindow.WindowType := ftwtDock;
  FWindow.Borderless := True;
  FWindow.SkipTaskbar := True;
  FWindow.SetPosition(0, py);

  // Reserve bottom screen space via _NET_WM_STRUT & _NET_WM_STRUT_PARTIAL
  FWindow.SetStrutPartial(
    0, 0, 0, FPanelHeight,
    0, 0, 0, 0, 0, 0,
    0, FPanelWidth - 1
  );

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
  if FtIsLibLoaded() and Assigned(ft_screen_get_height) then
    sh := FtApp().ScreenHeight
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

function TShellBottomPanel.GetIconCacheCount(): Integer;
begin
  Result := Length(FWindowIconCache);
end;

function TShellBottomPanel.GetTaskIcon(AIndex: Integer): TFtBitmap;
begin
  Result := nil;
  if (AIndex >= 0) and (AIndex < Length(FTasks)) then
    Result := GetOrLoadWindowIcon(FTasks[AIndex].Window, 18);
end;

procedure TShellBottomPanel.Show();
begin
  if FWindow = nil then Exit;
  FWindow.Show();
  FIsVisible := True;
  RefreshTasks();
end;

procedure TShellBottomPanel.Hide();
begin
  if FWindow = nil then Exit;
  FWindow.Hide();
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
  pStr: PChar;
begin
  Result := '';
  if (FConn = nil) or (AWin = 0) then Exit;

  // 1. Try _NET_WM_NAME (UTF8_STRING)
  if (FAtomNetWmName <> 0) and (FAtomUtf8String <> 0) then
  begin
    cookie := xcb_get_property(FConn, 0, AWin, FAtomNetWmName, FAtomUtf8String, 0, 256);
    reply := xcb_get_property_reply(FConn, cookie, nil);
    if reply <> nil then
    begin
      try
        len := xcb_get_property_value_length(reply);
        if len > 0 then
        begin
          pStr := PChar(xcb_get_property_value(reply));
          SetString(Result, pStr, len);
          Exit;
        end;
      finally
        c_free(reply);
      end;
    end;
  end;

  // 2. Fallback to WM_NAME (STRING)
  if FAtomWMName <> 0 then
  begin
    cookie := xcb_get_property(FConn, 0, AWin, FAtomWMName, XCB_ATOM_STRING, 0, 256);
    reply := xcb_get_property_reply(FConn, cookie, nil);
    if reply <> nil then
    begin
      try
        len := xcb_get_property_value_length(reply);
        if len > 0 then
        begin
          pStr := PChar(xcb_get_property_value(reply));
          SetString(Result, pStr, len);
        end;
      finally
        c_free(reply);
      end;
    end;
  end;
end;

function TShellBottomPanel.QueryWindowIcon(AWin: Cardinal; APreferredSize: Integer = 18): TFtBitmap;
var
  cookie: xcb_get_property_cookie_t;
  reply: Pxcb_get_property_reply_t;
  pData: PCardinal;
  valLen, numCards, offset, w, h, iconLen: Integer;
  bestW, bestH, bestOffset: Integer;
  candFound: Boolean;
  rawBmp: TFtBitmap;
  resName, resClass, iconPath: string;
  pStr, pNext: PChar;
  strLen: Integer;
  desktopApp: TDesktopApp;
begin
  Result := nil;
  if not FtIsLibLoaded() then Exit;

  // 1. Try _NET_WM_ICON
  if (FConn <> nil) and (AWin <> 0) and (FAtomNetWmIcon <> 0) then
  begin
    cookie := xcb_get_property(FConn, 0, AWin, FAtomNetWmIcon, XCB_ATOM_CARDINAL, 0, 131072);
    reply := xcb_get_property_reply(FConn, cookie, nil);
    if reply <> nil then
    begin
      try
        valLen := xcb_get_property_value_length(reply);
        numCards := valLen div SizeOf(Cardinal);
        if numCards >= 2 then
        begin
          pData := PCardinal(xcb_get_property_value(reply));
          offset := 0;
          candFound := False;
          bestW := 0;
          bestH := 0;
          bestOffset := 0;

          while offset + 2 <= numCards do
          begin
            w := Integer(pData[offset]);
            h := Integer(pData[offset + 1]);
            if (w <= 0) or (h <= 0) or (w > 1024) or (h > 1024) then Break;
            iconLen := w * h;
            if (offset + 2 + iconLen > numCards) or (iconLen < 0) then Break;

            if (w = APreferredSize) and (h = APreferredSize) then
            begin
              candFound := True;
              bestW := w;
              bestH := h;
              bestOffset := offset;
              Break;
            end;

            if not candFound then
            begin
              candFound := True;
              bestW := w;
              bestH := h;
              bestOffset := offset;
            end
            else if bestW < APreferredSize then
            begin
              if (w >= APreferredSize) or (w > bestW) then
              begin
                bestW := w;
                bestH := h;
                bestOffset := offset;
              end;
            end
            else
            begin
              if (w >= APreferredSize) and (w < bestW) then
              begin
                bestW := w;
                bestH := h;
                bestOffset := offset;
              end;
            end;

            Inc(offset, 2 + iconLen);
          end;

          if candFound and (bestW > 0) and (bestH > 0) then
          begin
            try
              rawBmp := TFtBitmap.CreateFromBGRA(@pData[bestOffset + 2], bestW, bestH);
              if Assigned(rawBmp) then
              begin
                if (bestW = APreferredSize) and (bestH = APreferredSize) then
                  Result := rawBmp
                else
                begin
                  Result := rawBmp.CreateScaled(APreferredSize, APreferredSize);
                  rawBmp.Free();
                end;
              end;
            except
              Result := nil;
            end;
            if Result <> nil then Exit;
          end;
        end;
      finally
        c_free(reply);
      end;
    end;
  end;

  // 2. Try WM_CLASS match to desktop apps / pixmaps
  if (FConn <> nil) and (AWin <> 0) then
  begin
    cookie := xcb_get_property(FConn, 0, AWin, XCB_ATOM_WM_CLASS, XCB_ATOM_STRING, 0, 256);
    reply := xcb_get_property_reply(FConn, cookie, nil);
    if reply <> nil then
    begin
      try
        strLen := xcb_get_property_value_length(reply);
        if strLen > 0 then
        begin
          pStr := PChar(xcb_get_property_value(reply));
          resName := StrPas(pStr);
          resClass := '';
          pNext := pStr + Length(resName) + 1;
          if (pNext - pStr) < strLen then
            resClass := StrPas(pNext);

          // A. Match against TDesktopAppList
          if Assigned(FLauncher) and Assigned(FLauncher.AppList) then
          begin
            if FLauncher.AppList.FindAppByClass(resName, resClass, desktopApp) then
            begin
              if desktopApp.Icon <> '' then
              begin
                iconPath := ResolveIconPath(desktopApp.Icon, APreferredSize);
                if iconPath <> '' then
                  Result := LoadIconBitmap(iconPath, APreferredSize, APreferredSize);
              end;
            end;
          end;

          // B. Direct name resolution from resName
          if (Result = nil) and (resName <> '') then
          begin
            iconPath := ResolveIconPath(LowerCase(resName), APreferredSize);
            if iconPath <> '' then
              Result := LoadIconBitmap(iconPath, APreferredSize, APreferredSize);
          end;

          // C. Direct name resolution from resClass
          if (Result = nil) and (resClass <> '') then
          begin
            iconPath := ResolveIconPath(LowerCase(resClass), APreferredSize);
            if iconPath <> '' then
              Result := LoadIconBitmap(iconPath, APreferredSize, APreferredSize);
          end;
        end;
      finally
        c_free(reply);
      end;
    end;
  end;

  // 3. Fallback generic window icon
  if Result = nil then
    Result := CreateFallbackIcon(APreferredSize, APreferredSize);
end;

function TShellBottomPanel.GetOrLoadWindowIcon(AWin: Cardinal; APreferredSize: Integer = 18): TFtBitmap;
var
  i: Integer;
begin
  Result := nil;
  if AWin = 0 then Exit;

  for i := 0 to High(FWindowIconCache) do
  begin
    if FWindowIconCache[i].Window = AWin then
    begin
      Result := FWindowIconCache[i].Bitmap;
      Exit;
    end;
  end;

  Result := QueryWindowIcon(AWin, APreferredSize);
  SetLength(FWindowIconCache, Length(FWindowIconCache) + 1);
  FWindowIconCache[High(FWindowIconCache)].Window := AWin;
  FWindowIconCache[High(FWindowIconCache)].Bitmap := Result;
end;

function TShellBottomPanel.ShouldShowTask(AWin: Cardinal): Boolean;
var
  cookie: xcb_get_property_cookie_t;
  reply: Pxcb_get_property_reply_t;
  atoms: Pxcb_atom_t;
  count, i: Integer;
begin
  if (FConn = nil) or (AWin = 0) then Exit(False);

  // 1. Exclude self panel window
  if Assigned(FWindow) and (AWin = Cardinal(PtrUInt(FWindow.NativeHandle))) then
    Exit(False);

  // 2. Exclude launcher window if active
  if Assigned(FLauncher) and Assigned(FLauncher.Window) and
     (AWin = Cardinal(PtrUInt(FLauncher.Window.NativeHandle))) then
    Exit(False);

  // 3. Check _NET_WM_STATE for _NET_WM_STATE_SKIP_TASKBAR
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

  // 4. Check _NET_WM_WINDOW_TYPE (ignore docks, desktop, splash, utilities, toolbars, menus, tooltips)
  if FAtomNetWmWindowType <> 0 then
  begin
    cookie := xcb_get_property(FConn, 0, AWin, FAtomNetWmWindowType, XCB_ATOM_ATOM, 0, 16);
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

function TShellBottomPanel.IsWindowMaximized(AWin: Cardinal): Boolean;
var
  cookie: xcb_get_property_cookie_t;
  reply: Pxcb_get_property_reply_t;
  atoms: Pxcb_atom_t;
  count, i: Integer;
begin
  Result := False;
  if (FConn = nil) or (AWin = 0) or (FAtomNetWmState = 0) then Exit;
  if (FAtomNetWmStateMaxVert = 0) and (FAtomNetWmStateMaxHorz = 0) then Exit;

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
        // Either axis counts as maximized for menu purposes: the WM sets both,
        // and a half-maximized window should still offer "Restore".
        if (atoms[i] = FAtomNetWmStateMaxVert) or (atoms[i] = FAtomNetWmStateMaxHorz) then
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
  i, j: Integer;
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
    FTasks[i].IsMaximized := IsWindowMaximized(validWins[i]);

    // Check if previously existed
    found := False;
    for j := 0 to High(oldTasks) do
    begin
      if oldTasks[j].Window = validWins[i] then
      begin
        FTasks[i].Title := oldTasks[j].Title;
        FTasks[i].Button := oldTasks[j].Button;
        FTasks[i].Menu := oldTasks[j].Menu;
        FTasks[i].MenuMinimize := oldTasks[j].MenuMinimize;
        FTasks[i].MenuMaximize := oldTasks[j].MenuMaximize;
        FTasks[i].MenuClose := oldTasks[j].MenuClose;
        oldTasks[j].Button := nil; // transfer ownership
        oldTasks[j].Menu := nil;
        found := True;
        Break;
      end;
    end;

    title := QueryWindowTitle(validWins[i]);
    if title = '' then
      title := 'Window ' + IntToStr(validWins[i]);
    FTasks[i].Title := title;

    if not found then
    begin
      // SetLength reuses the array, so an overwritten slot still holds the old
      // record's pointers. Clear them or the panel would free a menu twice.
      FTasks[i].Button := nil;
      FTasks[i].Menu := nil;
      FTasks[i].MenuMinimize := nil;
      FTasks[i].MenuMaximize := nil;
      FTasks[i].MenuClose := nil;
    end;
  end;

  // Destroy remaining unused buttons
  for j := 0 to High(oldTasks) do
  begin
    if Assigned(oldTasks[j].Button) then
    begin
      // Detach before freeing: the button holds a raw pointer to the menu and
      // must not outlive it.
      if Assigned(oldTasks[j].Menu) then
        oldTasks[j].Button.ContextMenuHandle := nil;
      oldTasks[j].Button.Free();
      oldTasks[j].Button := nil;
    end;
    if Assigned(oldTasks[j].Menu) then
    begin
      oldTasks[j].Menu.Free();
      oldTasks[j].Menu := nil;
    end;
  end;

  // Evict stale entries from icon cache
  i := 0;
  while i < Length(FWindowIconCache) do
  begin
    found := False;
    for j := 0 to High(validWins) do
    begin
      if validWins[j] = FWindowIconCache[i].Window then
      begin
        found := True;
        Break;
      end;
    end;
    if not found then
    begin
      if Assigned(FWindowIconCache[i].Bitmap) then
        FWindowIconCache[i].Bitmap.Free();
      for j := i to Length(FWindowIconCache) - 2 do
        FWindowIconCache[j] := FWindowIconCache[j + 1];
      SetLength(FWindowIconCache, Length(FWindowIconCache) - 1);
    end
    else
      Inc(i);
  end;

  // Every task gets a context menu, and its captions are refreshed here so a
  // window maximized via its own titlebar is still offered "Restore".
  for i := 0 to High(FTasks) do
  begin
    BuildTaskMenu(FTasks[i]);
    UpdateTaskMenuState(FTasks[i]);
  end;

  LayoutButtons();
end;

procedure TShellBottomPanel.LayoutButtons();
var
  startX, endX, availW, numTasks: Integer;
  btnW, btnX, i: Integer;
  dispTitle: string;
  iconBmp: TFtBitmap;
begin
  if FWindow = nil then Exit;

  startX := 6;
  endX := FPanelWidth - 6;

  availW := Max(100, endX - startX);
  numTasks := Length(FTasks);

  if numTasks = 0 then
  begin
    // Nothing to lay out, but the area still has to be repainted: the last task's
    // button was just freed and its pixels would otherwise stay on screen.
    if FWindow <> nil then
      FWindow.Invalidate();
    Exit;
  end;

  btnW := Min(180, Max(70, (availW - (numTasks - 1) * 4) div numTasks));

  for i := 0 to numTasks - 1 do
  begin
    btnX := startX + i * (btnW + 4);
    dispTitle := FTasks[i].Title;
    if Length(dispTitle) > 22 then
      dispTitle := Copy(dispTitle, 1, 20) + '..';

    iconBmp := GetOrLoadWindowIcon(FTasks[i].Window, 18);

    if FTasks[i].Button = nil then
    begin
      FTasks[i].Button := TFtButton.Create(FWindow, btnX, 3, btnW, 32, dispTitle);
      FTasks[i].Button.IsToggle := True;
      FTasks[i].Button.CornerRadius := 6.0;
      FTasks[i].Button.Alignment := ftaLeft;
      FTasks[i].Button.PaddingX := 8.0;
      FTasks[i].Button.Tag := PtrInt(FTasks[i].Window);
      FTasks[i].Button.OnClick := @HandleTaskButtonClick;
    end
    else
    begin
      FTasks[i].Button.SetBounds(btnX, 3, btnW, 32);
      FTasks[i].Button.Caption := dispTitle;
      FTasks[i].Button.Alignment := ftaLeft;
      FTasks[i].Button.PaddingX := 8.0;
    end;

    // Right-click on the task button opens its context menu. The toolkit walks up
    // from the hit widget to find this, so it must be attached to the button.
    if Assigned(FTasks[i].Menu) then
      FTasks[i].Button.ContextMenuHandle := FTasks[i].Menu.Handle;

    if Assigned(iconBmp) then
    begin
      FTasks[i].Button.SetIconBitmap(iconBmp, False);
      FTasks[i].Button.SetIconSize(18, 18);
      FTasks[i].Button.IconGap := 6;
    end
    else
      FTasks[i].Button.ClearIcon();

    FTasks[i].Button.Toggled := FTasks[i].IsActive;
  end;

  // Repaint the task area explicitly.
  if FWindow <> nil then
    FWindow.Invalidate();
end;

procedure TShellBottomPanel.Tick();
var
  curActive: Cardinal;
  sig: AnsiString;
begin
  // Refresh when EITHER the active window changes OR the set of windows changes.
  sig := TaskSetSignature();
  if sig <> FLastTaskSignature then
  begin
    FLastTaskSignature := sig;
    FLastActiveWin := QueryActiveWindow();
    RefreshTasks();
    Exit;
  end;

  curActive := QueryActiveWindow();
  if curActive <> FLastActiveWin then
  begin
    FLastActiveWin := curActive;
    RefreshTasks();
  end;
end;

// Identity of the current task set, cheap enough to compute every tick.
//
// Built from the window ids only: titles and states change far more often than
// the set itself, and those are handled by RefreshTasks' own state refresh.
function TShellBottomPanel.TaskSetSignature(): AnsiString;
var
  wins: array of Cardinal;
  i: Integer;
begin
  wins := QueryClientList();
  Result := '';
  for i := 0 to High(wins) do
  begin
    if not ShouldShowTask(wins[i]) then Continue;
    Result := Result + IntToHex(QWord(wins[i]), 8) + ',';
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

procedure TShellBottomPanel.UnminimizeWindow(AWin: Cardinal);
var
  ev: xcb_client_message_event_t;
  data32: PCardinalArray;
begin
  if (FConn = nil) or (AWin = 0) or (FAtomNetWmState = 0) or (FAtomNetWmStateHidden = 0) then Exit;

  // _NET_WM_STATE_REMOVE of _NET_WM_STATE_HIDDEN. The WM maps the window and
  // clears the flag; the caller also activates, because unminimizing alone does
  // not raise or focus on every window manager.
  FillChar(ev, SizeOf(ev), 0);
  ev.response_type := XCB_CLIENT_MESSAGE;
  ev.format := 32;
  ev.window := AWin;
  ev.type_ := FAtomNetWmState;
  data32 := PCardinalArray(@ev.data.raw[0]);
  data32^[0] := 0; // _NET_WM_STATE_REMOVE
  data32^[1] := FAtomNetWmStateHidden;
  data32^[2] := 0;
  data32^[3] := 2; // source indication: pager
  xcb_send_event(FConn, 0, FRootWindow,
                 XCB_EVENT_MASK_SUBSTRUCTURE_REDIRECT or XCB_EVENT_MASK_SUBSTRUCTURE_NOTIFY,
                 PAnsiChar(@ev));
  xcb_flush(FConn);
end;

procedure TShellBottomPanel.MaximizeWindow(AWin: Cardinal);
var
  ev: xcb_client_message_event_t;
  data32: PCardinalArray;
begin
  if (FConn = nil) or (AWin = 0) or (FAtomNetWmState = 0) then Exit;

  // _NET_WM_STATE_ADD with both maximized atoms. The WM only checks that either
  // atom appears in the property list, so one message is enough.
  FillChar(ev, SizeOf(ev), 0);
  ev.response_type := XCB_CLIENT_MESSAGE;
  ev.format := 32;
  ev.window := AWin;
  ev.type_ := FAtomNetWmState;
  data32 := PCardinalArray(@ev.data.raw[0]);
  data32^[0] := 1; // _NET_WM_STATE_ADD
  data32^[1] := FAtomNetWmStateMaxVert;
  data32^[2] := FAtomNetWmStateMaxHorz;
  data32^[3] := 2; // source indication: pager
  xcb_send_event(FConn, 0, FRootWindow,
                 XCB_EVENT_MASK_SUBSTRUCTURE_REDIRECT or XCB_EVENT_MASK_SUBSTRUCTURE_NOTIFY,
                 PAnsiChar(@ev));
  xcb_flush(FConn);
end;

procedure TShellBottomPanel.RestoreWindow(AWin: Cardinal);
var
  ev: xcb_client_message_event_t;
  data32: PCardinalArray;
begin
  if (FConn = nil) or (AWin = 0) or (FAtomNetWmState = 0) then Exit;

  FillChar(ev, SizeOf(ev), 0);
  ev.response_type := XCB_CLIENT_MESSAGE;
  ev.format := 32;
  ev.window := AWin;
  ev.type_ := FAtomNetWmState;
  data32 := PCardinalArray(@ev.data.raw[0]);
  data32^[0] := 0; // _NET_WM_STATE_REMOVE
  data32^[1] := FAtomNetWmStateMaxVert;
  data32^[2] := FAtomNetWmStateMaxHorz;
  data32^[3] := 2;
  xcb_send_event(FConn, 0, FRootWindow,
                 XCB_EVENT_MASK_SUBSTRUCTURE_REDIRECT or XCB_EVENT_MASK_SUBSTRUCTURE_NOTIFY,
                 PAnsiChar(@ev));
  xcb_flush(FConn);
end;

procedure TShellBottomPanel.CloseWindow(AWin: Cardinal);
var
  ev: xcb_client_message_event_t;
  data32: PCardinalArray;
begin
  if (FConn = nil) or (AWin = 0) or (FAtomNetCloseWindow = 0) then Exit;

  // _NET_CLOSE_WINDOW asks the WM to close the window politely, which lets the
  // application prompt about unsaved work. Deliberately not xcb_kill_client:
  // that would terminate the connection and lose the user's data.
  FillChar(ev, SizeOf(ev), 0);
  ev.response_type := XCB_CLIENT_MESSAGE;
  ev.format := 32;
  ev.window := AWin;
  ev.type_ := FAtomNetCloseWindow;
  data32 := PCardinalArray(@ev.data.raw[0]);
  data32^[0] := 2; // source indication: pager
  data32^[1] := XCB_CURRENT_TIME;
  xcb_send_event(FConn, 0, FRootWindow,
                 XCB_EVENT_MASK_SUBSTRUCTURE_REDIRECT or XCB_EVENT_MASK_SUBSTRUCTURE_NOTIFY,
                 PAnsiChar(@ev));
  xcb_flush(FConn);
end;


end.
