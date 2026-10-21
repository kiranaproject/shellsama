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
  ShellSama.Launcher,
  ShellSama.Tray,
  ShellSama.Applets;

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
    Button     : TFtButton;
  end;

  TShellBottomPanel = class
  private
    FWindow         : TFtWindow;
    FLauncherBtn    : TFtButton;
    FClockText      : TFtLabel;
    FShowDesktopBtn : TFtButton;
    FSessionApplet  : TShellSessionApplet;
    FVolumeApplet   : TShellVolumeApplet;
    FTray           : TShellSystemTray;
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
    FAtomNetWmIcon            : Cardinal;
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

    procedure HandleLauncherButtonClick(Sender: TFtButton);
    procedure HandleShowDesktopButtonClick(Sender: TFtButton);
    procedure HandleTaskButtonClick(Sender: TFtButton);
    procedure HandleTrayLayoutChanged(Sender: TObject);
  public
    constructor Create(ALauncher: TShellLauncher = nil);
    destructor Destroy(); override;

    procedure Show();
    procedure Hide();
    procedure RefreshTasks();
    procedure UpdateClock();
    procedure Tick();

    function QueryWindowIcon(AWin: Cardinal; APreferredSize: Integer = 18): TFtBitmap;
    function GetOrLoadWindowIcon(AWin: Cardinal; APreferredSize: Integer = 18): TFtBitmap;

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
    function GetIconCacheCount(): Integer;
    function GetTaskIcon(AIndex: Integer): TFtBitmap;

    property IsVisible     : Boolean         read FIsVisible;
    property ActiveWindow  : Cardinal        read FActiveWindow;
    property TaskCount     : Integer         read GetTaskCount;
    property IconCacheCount: Integer         read GetIconCacheCount;
    property WindowWidget  : TFtWindow       read FWindow;
    property LauncherWidget: TFtButton       read FLauncherBtn;
    property ClockWidget   : TFtLabel        read FClockText;
    property TrayWidget    : TShellSystemTray read FTray;
    property VolumeApplet  : TShellVolumeApplet read FVolumeApplet;
    property SessionApplet : TShellSessionApplet read FSessionApplet;
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
  FShowingDesktop := False;
  FPanelHeight := 38;
  FLastClockSec := -1;
  FLastActiveWin := 0;
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

  if FtIsLibLoaded() and Assigned(ft_set_tick_callback) then
    ft_set_tick_callback(@PanelTickCallback, Self);
end;

destructor TShellBottomPanel.Destroy();
var
  i: Integer;
begin
  if GBottomPanelInstance = Self then
    GBottomPanelInstance := nil;

  if FtIsLibLoaded() and Assigned(ft_set_tick_callback) then
    ft_set_tick_callback(nil, nil);

  for i := 0 to High(FTasks) do
  begin
    if Assigned(FTasks[i].Button) then
    begin
      FTasks[i].Button.Free();
      FTasks[i].Button := nil;
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

  if Assigned(FTray) then
  begin
    FTray.Free();
    FTray := nil;
  end;

  if Assigned(FVolumeApplet) then
  begin
    FVolumeApplet.Free();
    FVolumeApplet := nil;
  end;

  if Assigned(FSessionApplet) then
  begin
    FSessionApplet.Free();
    FSessionApplet := nil;
  end;

  if Assigned(FWindow) then
  begin
    FWindow.Free();
    FWindow := nil;
    FLauncherBtn := nil;
    FClockText := nil;
    FShowDesktopBtn := nil;
  end;

  inherited Destroy();
end;

procedure TShellBottomPanel.HandleLauncherButtonClick(Sender: TFtButton);
begin
  OnLauncherClicked();
end;

procedure TShellBottomPanel.HandleShowDesktopButtonClick(Sender: TFtButton);
begin
  ToggleShowDesktop();
end;

procedure TShellBottomPanel.HandleTaskButtonClick(Sender: TFtButton);
begin
  if Assigned(Sender) and (Sender.Tag <> 0) then
    OnTaskClicked(Cardinal(Sender.Tag));
end;

procedure TShellBottomPanel.HandleTrayLayoutChanged(Sender: TObject);
begin
  LayoutButtons();
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

  // 1. Launcher button on the left
  FLauncherBtn := TFtButton.Create(FWindow, 6, 3, 110, 32, '✦ Samarinda');
  FLauncherBtn.IsToggle := True;
  FLauncherBtn.CornerRadius := 6.0;
  FLauncherBtn.OnClick := @HandleLauncherButtonClick;

  // 2. Show Desktop button on the extreme right
  FShowDesktopBtn := TFtButton.Create(FWindow, FPanelWidth - 36, 3, 32, 32, '▭');
  FShowDesktopBtn.CornerRadius := 6.0;
  FShowDesktopBtn.PaddingX := 2.0;
  FShowDesktopBtn.Font := 'Noto Sans Symbols2 12';
  FShowDesktopBtn.OnClick := @HandleShowDesktopButtonClick;

  // 3. Power / Session Applet
  FSessionApplet := TShellSessionApplet.Create(FWindow, FPanelWidth - 70, 3, 32, 32);

  // 4. Clock text label
  FClockText := TFtLabel.Create(FWindow, FPanelWidth - 164, 3, 90, 32, '--:--');
  FClockText.Alignment := ftaCenter;

  // 5. Volume Applet
  FVolumeApplet := TShellVolumeApplet.Create(FWindow, FPanelWidth - 204, 3, 36, 32);

  // 6. System Tray Host
  FTray := TShellSystemTray.Create(FWindow, 0);
  FTray.IconSize := 22;
  FTray.IconGap := 4;
  FTray.StartY := (FPanelHeight - FTray.IconSize) div 2;
  FTray.OnLayoutChanged := @HandleTrayLayoutChanged;
  FTray.ClaimSelection();

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
  UpdateClock();
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
    if Assigned(oldTasks[j].Button) then
    begin
      oldTasks[j].Button.Free();
      oldTasks[j].Button := nil;
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

  LayoutButtons();
end;

procedure TShellBottomPanel.LayoutButtons();
var
  startX, endX, availW, numTasks: Integer;
  trayW, trayX: Integer;
  btnW, btnX, i: Integer;
  dispTitle: string;
  iconBmp: TFtBitmap;
begin
  if FWindow = nil then Exit;

  startX := 122;

  // Calculate dynamic endX based on System Tray and Applets
  if Assigned(FTray) then
  begin
    trayW := FTray.Width;
    trayX := (FPanelWidth - 212) - trayW;
    FTray.SetPosition(trayX, (FPanelHeight - FTray.IconSize) div 2);
    endX := trayX - 8;
  end
  else
    endX := FPanelWidth - 212;

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
  if Assigned(FClockText) then
    FClockText.Text := timeStr;
end;

procedure TShellBottomPanel.Tick();
var
  curActive: Cardinal;
begin
  UpdateClock();

  if Assigned(FVolumeApplet) then
    FVolumeApplet.Tick();

  // Sync launcher button toggled state
  if Assigned(FLauncherBtn) and Assigned(FLauncher) then
    FLauncherBtn.Toggled := FLauncher.IsVisible;

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
    if Assigned(FLauncherBtn) then
      FLauncherBtn.Toggled := FLauncher.IsVisible;
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
