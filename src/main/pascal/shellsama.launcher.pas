{ Unit ShellSama.Launcher — Centered Application Launcher using ftpas }

unit ShellSama.Launcher;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  SysUtils, Classes, Math, BaseUnix, ctypes,
  Floria.XCB, Floria.XCB.Keysyms, Floria.X11.KeySym,
  ftpas.api, ftpas.types, ftpas,
  ShellSama.DesktopApps;

const
  LAUNCHER_WIDTH = 600;
  LAUNCHER_HEIGHT = 400;
  LAUNCHER_VISIBLE_ITEMS = 10;
  LAUNCHER_ITEM_HEIGHT = 32;

type
  TLauncherIconItem = record
    IconKey: string;
    Bitmap : TFtBitmap;
  end;

  TShellLauncher = class
  private
    FWindow          : TFtWindow;
    FSearchEntry     : TFtEntry;
    FItemButtons     : array[0..LAUNCHER_VISIBLE_ITEMS - 1] of TFtButton;
    FAppList         : TDesktopAppList;
    FCurrentResults  : TDesktopAppArray;
    FSelectedIndex   : Integer;
    FScrollOffset    : Integer;
    FVisible         : Boolean;
    FConnection      : Pxcb_connection_t;
    FScreen          : Pxcb_screen_t;
    FKeySymbols      : Pxcb_key_symbols_t;
    FSuperKeycodeL   : xcb_keycode_t;
    FSuperKeycodeR   : xcb_keycode_t;
    FSuperPressed    : Boolean;
    FOtherKeyPressed : Boolean;
    FLauncherIconCache: array of TLauncherIconItem;

    procedure InitializeUI();
    procedure ResolveKeycodes();
    procedure GrabSuperKey();
    procedure UngrabSuperKey();
    procedure UpdateVisibleItems();
    procedure EnsureSelectionVisible();
    procedure LaunchApp(const AApp: TDesktopApp);
    function GetResultsCount(): Integer;

    procedure HandleSearchEntryChange(Sender: TFtWidget; const AText: string);
    procedure HandleSearchEntrySubmit(Sender: TFtWidget; const AText: string);
    procedure HandleItemButtonClick(Sender: TFtButton);
  public
    constructor Create();
    destructor Destroy(); override;

    procedure Show();
    procedure Hide();
    procedure Toggle();

    procedure HandleSearchChanged(const AText: string);
    procedure SelectNext();
    procedure SelectPrev();
    procedure SelectPageDown();
    procedure SelectPageUp();
    procedure SelectAndLaunch(AAppIndex: Integer);
    procedure LaunchCurrentSelection();
    procedure HandleItemClick(AButton: TFtButton);

    function HandleXcbEvent(Event: Pxcb_generic_event_t): Boolean;
    function GetIconCacheCount(): Integer;
    function GetItemButton(AIndex: Integer): TFtButton;
    function GetOrLoadAppIcon(const AIconName: string; const APreferredSize: Integer = 20): TFtBitmap;

    property Window        : TFtWindow        read FWindow;
    property SearchEntry   : TFtEntry         read FSearchEntry;
    property AppList       : TDesktopAppList  read FAppList;
    property SelectedIndex : Integer          read FSelectedIndex;
    property ScrollOffset  : Integer          read FScrollOffset;
    property IsVisible     : Boolean          read FVisible;
    property ResultsCount  : Integer          read GetResultsCount;
    property IconCacheCount: Integer          read GetIconCacheCount;
  end;

var
  GLauncherInstance: TShellLauncher = nil;

implementation

procedure c_free(p: Pointer); cdecl; external 'c' name 'free';
function libc_system(cmd: PChar): cint; cdecl; external 'c' name 'system';

function LauncherEventFilterCallback(event: Pointer): cint32; cdecl;
begin
  if Assigned(GLauncherInstance) and GLauncherInstance.HandleXcbEvent(Pxcb_generic_event_t(event)) then
    Result := 1
  else
    Result := 0;
end;

// -----------------------------------------------------------------------------
// TShellLauncher
// -----------------------------------------------------------------------------

constructor TShellLauncher.Create();
begin
  inherited Create();
  GLauncherInstance := Self;
  FVisible := False;
  FSelectedIndex := 0;
  FScrollOffset := 0;
  FSuperPressed := False;
  FOtherKeyPressed := False;

  if not FtIsLibLoaded() then
  begin
    if not FtLoadLib() then
      raise Exception.Create('ShellSama: Could not load libft.so shared library.');
  end;

  FConnection := Pxcb_connection_t(ft_backend_get_connection());
  FScreen := Pxcb_screen_t(ft_backend_get_screen());
  FKeySymbols := Pxcb_key_symbols_t(ft_backend_get_key_symbols());

  FAppList := TDesktopAppList.Create();
  FAppList.LoadAll();
  FCurrentResults := FAppList.Search('');

  InitializeUI();
  ResolveKeycodes();
  GrabSuperKey();
  SetLength(FLauncherIconCache, 0);

  if Assigned(ft_register_event_filter) then
    ft_register_event_filter(@LauncherEventFilterCallback);
end;

destructor TShellLauncher.Destroy();
var
  i: Integer;
begin
  if Assigned(ft_register_event_filter) then
    ft_register_event_filter(nil);
  UngrabSuperKey();

  if GLauncherInstance = Self then
    GLauncherInstance := nil;

  for i := 0 to High(FLauncherIconCache) do
  begin
    if Assigned(FLauncherIconCache[i].Bitmap) then
    begin
      FLauncherIconCache[i].Bitmap.Free();
      FLauncherIconCache[i].Bitmap := nil;
    end;
  end;
  SetLength(FLauncherIconCache, 0);

  if Assigned(FWindow) then
  begin
    FWindow.Free();
    FWindow := nil;
    FSearchEntry := nil;
  end;

  if Assigned(FAppList) then
  begin
    FAppList.Free();
    FAppList := nil;
  end;

  inherited Destroy();
end;

function TShellLauncher.GetResultsCount(): Integer;
begin
  Result := Length(FCurrentResults);
end;

function TShellLauncher.GetIconCacheCount(): Integer;
begin
  Result := Length(FLauncherIconCache);
end;

function TShellLauncher.GetItemButton(AIndex: Integer): TFtButton;
begin
  Result := nil;
  if (AIndex >= 0) and (AIndex < LAUNCHER_VISIBLE_ITEMS) then
    Result := FItemButtons[AIndex];
end;

function TShellLauncher.GetOrLoadAppIcon(const AIconName: string; const APreferredSize: Integer = 20): TFtBitmap;
var
  i: Integer;
  key, iconPath: string;
  bmp: TFtBitmap;
begin
  Result := nil;
  if not FtIsLibLoaded() then Exit;

  key := Trim(AIconName);
  if key = '' then
    key := '__fallback__';

  for i := 0 to High(FLauncherIconCache) do
  begin
    if FLauncherIconCache[i].IconKey = key then
    begin
      Result := FLauncherIconCache[i].Bitmap;
      Exit;
    end;
  end;

  bmp := nil;
  if key <> '__fallback__' then
  begin
    iconPath := ResolveIconPath(key, APreferredSize);
    if iconPath <> '' then
      bmp := LoadIconBitmap(iconPath, APreferredSize, APreferredSize);
  end;

  if bmp = nil then
    bmp := CreateFallbackIcon(APreferredSize, APreferredSize);

  SetLength(FLauncherIconCache, Length(FLauncherIconCache) + 1);
  FLauncherIconCache[High(FLauncherIconCache)].IconKey := key;
  FLauncherIconCache[High(FLauncherIconCache)].Bitmap := bmp;
  Result := bmp;
end;

procedure TShellLauncher.HandleSearchEntryChange(Sender: TFtWidget; const AText: string);
begin
  HandleSearchChanged(AText);
end;

procedure TShellLauncher.HandleSearchEntrySubmit(Sender: TFtWidget; const AText: string);
begin
  LaunchCurrentSelection();
end;

procedure TShellLauncher.HandleItemButtonClick(Sender: TFtButton);
begin
  HandleItemClick(Sender);
end;

procedure TShellLauncher.InitializeUI();
var
  i: Integer;
  itemY: Integer;
  screenWidth, screenHeight: Integer;
begin
  FWindow := TFtWindow.Create(LAUNCHER_WIDTH, LAUNCHER_HEIGHT, 'Samarinda Launcher');
  FWindow.Borderless := True;
  FWindow.SkipTaskbar := True;
  FWindow.WindowType := ftwtDialog;

  screenWidth := FtApp().ScreenWidth;
  screenHeight := FtApp().ScreenHeight;
  FWindow.SetPosition(
    (screenWidth - LAUNCHER_WIDTH) div 2,
    (screenHeight - LAUNCHER_HEIGHT) div 2
  );

  // Top search entry
  FSearchEntry := TFtEntry.Create(FWindow, 20, 18, LAUNCHER_WIDTH - 40, 38, '');
  FSearchEntry.Placeholder := 'Search applications...';
  FSearchEntry.OnChange := @HandleSearchEntryChange;
  FSearchEntry.OnSubmit := @HandleSearchEntrySubmit;

  // Pre-allocate 10 visible buttons for virtual scrolling
  for i := 0 to LAUNCHER_VISIBLE_ITEMS - 1 do
  begin
    itemY := 68 + (i * LAUNCHER_ITEM_HEIGHT);
    FItemButtons[i] := TFtButton.Create(FWindow, 20, itemY, LAUNCHER_WIDTH - 40, LAUNCHER_ITEM_HEIGHT, '');
    FItemButtons[i].CornerRadius := 6.0;
    FItemButtons[i].IsToggle := True;
    FItemButtons[i].Alignment := ftaLeft;
    FItemButtons[i].PaddingX := 12.0;
    FItemButtons[i].OnClick := @HandleItemButtonClick;
  end;

  UpdateVisibleItems();
end;

procedure TShellLauncher.ResolveKeycodes();
var
  kcPtr: Pxcb_keycode_t;
begin
  FSuperKeycodeL := 0;
  FSuperKeycodeR := 0;

  if not Assigned(FKeySymbols) then Exit;

  kcPtr := xcb_key_symbols_get_keycode(FKeySymbols, XK_Super_L);
  if Assigned(kcPtr) then
  begin
    FSuperKeycodeL := kcPtr^;
    c_free(kcPtr);
  end;

  kcPtr := xcb_key_symbols_get_keycode(FKeySymbols, XK_Super_R);
  if Assigned(kcPtr) then
  begin
    FSuperKeycodeR := kcPtr^;
    c_free(kcPtr);
  end;
end;

procedure TShellLauncher.GrabSuperKey();
var
  mods: array[0..3] of Word;
  i: Integer;
begin
  if not Assigned(FConnection) or not Assigned(FScreen) then Exit;

  mods[0] := 0;
  mods[1] := XCB_KEY_BUT_MASK_LOCK;
  mods[2] := XCB_KEY_BUT_MASK_MOD_2;
  mods[3] := XCB_KEY_BUT_MASK_LOCK or XCB_KEY_BUT_MASK_MOD_2;

  for i := 0 to 3 do
  begin
    if FSuperKeycodeL <> 0 then
      xcb_grab_key(FConnection, 1, FScreen^.root, mods[i], FSuperKeycodeL,
                   XCB_GRAB_MODE_ASYNC, XCB_GRAB_MODE_ASYNC);
    if FSuperKeycodeR <> 0 then
      xcb_grab_key(FConnection, 1, FScreen^.root, mods[i], FSuperKeycodeR,
                   XCB_GRAB_MODE_ASYNC, XCB_GRAB_MODE_ASYNC);
  end;
  xcb_flush(FConnection);
end;

procedure TShellLauncher.UngrabSuperKey();
var
  mods: array[0..3] of Word;
  i: Integer;
begin
  if not Assigned(FConnection) or not Assigned(FScreen) then Exit;

  mods[0] := 0;
  mods[1] := XCB_KEY_BUT_MASK_LOCK;
  mods[2] := XCB_KEY_BUT_MASK_MOD_2;
  mods[3] := XCB_KEY_BUT_MASK_LOCK or XCB_KEY_BUT_MASK_MOD_2;

  for i := 0 to 3 do
  begin
    if FSuperKeycodeL <> 0 then
      xcb_ungrab_key(FConnection, FSuperKeycodeL, FScreen^.root, mods[i]);
    if FSuperKeycodeR <> 0 then
      xcb_ungrab_key(FConnection, FSuperKeycodeR, FScreen^.root, mods[i]);
  end;
  xcb_flush(FConnection);
end;

procedure TShellLauncher.UpdateVisibleItems();
var
  i, resIdx: Integer;
  totCount: Integer;
  isSelected: Boolean;
  appIcon: TFtBitmap;
begin
  totCount := Length(FCurrentResults);

  for i := 0 to LAUNCHER_VISIBLE_ITEMS - 1 do
  begin
    resIdx := FScrollOffset + i;
    if resIdx < totCount then
    begin
      isSelected := (resIdx = FSelectedIndex);
      FItemButtons[i].Caption := FCurrentResults[resIdx].Name;
      FItemButtons[i].Toggled := isSelected;

      appIcon := GetOrLoadAppIcon(FCurrentResults[resIdx].Icon, 20);
      if Assigned(appIcon) then
      begin
        FItemButtons[i].SetIconBitmap(appIcon, False);
        FItemButtons[i].SetIconSize(20, 20);
        FItemButtons[i].IconGap := 8;
      end
      else
        FItemButtons[i].ClearIcon();

      FItemButtons[i].Show();
    end
    else
    begin
      FItemButtons[i].Caption := '';
      FItemButtons[i].Toggled := False;
      FItemButtons[i].ClearIcon();
      FItemButtons[i].Hide();
    end;
    FItemButtons[i].Invalidate();
  end;
end;

procedure TShellLauncher.EnsureSelectionVisible();
var
  totCount: Integer;
begin
  totCount := Length(FCurrentResults);
  if totCount = 0 then
  begin
    FSelectedIndex := 0;
    FScrollOffset := 0;
    Exit;
  end;

  if FSelectedIndex < 0 then
    FSelectedIndex := 0
  else if FSelectedIndex >= totCount then
    FSelectedIndex := totCount - 1;

  if FSelectedIndex < FScrollOffset then
    FScrollOffset := FSelectedIndex
  else if FSelectedIndex >= FScrollOffset + LAUNCHER_VISIBLE_ITEMS then
    FScrollOffset := FSelectedIndex - LAUNCHER_VISIBLE_ITEMS + 1;

  UpdateVisibleItems();
end;

procedure TShellLauncher.HandleSearchChanged(const AText: string);
begin
  FCurrentResults := FAppList.Search(AText);
  FSelectedIndex := 0;
  FScrollOffset := 0;
  UpdateVisibleItems();
  if Assigned(FWindow) then
    FWindow.Invalidate();
end;

procedure TShellLauncher.SelectNext();
begin
  if Length(FCurrentResults) > 0 then
  begin
    Inc(FSelectedIndex);
    if FSelectedIndex >= Length(FCurrentResults) then
      FSelectedIndex := 0;
    EnsureSelectionVisible();
  end;
end;

procedure TShellLauncher.SelectPrev();
begin
  if Length(FCurrentResults) > 0 then
  begin
    Dec(FSelectedIndex);
    if FSelectedIndex < 0 then
      FSelectedIndex := Length(FCurrentResults) - 1;
    EnsureSelectionVisible();
  end;
end;

procedure TShellLauncher.SelectPageDown();
begin
  if Length(FCurrentResults) > 0 then
  begin
    Inc(FSelectedIndex, LAUNCHER_VISIBLE_ITEMS);
    if FSelectedIndex >= Length(FCurrentResults) then
      FSelectedIndex := Length(FCurrentResults) - 1;
    EnsureSelectionVisible();
  end;
end;

procedure TShellLauncher.SelectPageUp();
begin
  if Length(FCurrentResults) > 0 then
  begin
    Dec(FSelectedIndex, LAUNCHER_VISIBLE_ITEMS);
    if FSelectedIndex < 0 then
      FSelectedIndex := 0;
    EnsureSelectionVisible();
  end;
end;

procedure TShellLauncher.SelectAndLaunch(AAppIndex: Integer);
begin
  if (AAppIndex >= 0) and (AAppIndex < Length(FCurrentResults)) then
  begin
    FSelectedIndex := AAppIndex;
    LaunchCurrentSelection();
  end;
end;

procedure TShellLauncher.HandleItemClick(AButton: TFtButton);
var
  i, appIdx: Integer;
begin
  for i := 0 to LAUNCHER_VISIBLE_ITEMS - 1 do
  begin
    if FItemButtons[i] = AButton then
    begin
      appIdx := FScrollOffset + i;
      SelectAndLaunch(appIdx);
      Exit;
    end;
  end;
end;

procedure TShellLauncher.LaunchCurrentSelection();
var
  app: TDesktopApp;
begin
  if (FSelectedIndex >= 0) and (FSelectedIndex < Length(FCurrentResults)) then
  begin
    app := FCurrentResults[FSelectedIndex];
    FAppList.RecordLaunch(app.DesktopId);
    LaunchApp(app);
    Hide();
  end;
end;

procedure TShellLauncher.LaunchApp(const AApp: TDesktopApp);
var
  pid: pid_t;
  execCmd: string;
begin
  execCmd := Trim(AApp.Exec);
  if execCmd = '' then Exit;

  pid := fpFork();
  if pid = 0 then
  begin
    fpSetsid();
    libc_system(PChar(execCmd));
    fpExit(0);
  end;
end;

procedure TShellLauncher.Show();
var
  screenWidth, screenHeight: Integer;
begin
  if FVisible or (FWindow = nil) then Exit;

  screenWidth := FtApp().ScreenWidth;
  screenHeight := FtApp().ScreenHeight;
  FWindow.SetPosition(
    (screenWidth - LAUNCHER_WIDTH) div 2,
    (screenHeight - LAUNCHER_HEIGHT) div 2
  );

  FSearchEntry.Text := '';
  FCurrentResults := FAppList.Search('');
  FSelectedIndex := 0;
  FScrollOffset := 0;
  UpdateVisibleItems();

  FWindow.Show();
  FWindow.BringToFront();
  FSearchEntry.SetFocus();
  FWindow.GrabInput();

  FVisible := True;
  FWindow.Invalidate();
end;

procedure TShellLauncher.Hide();
begin
  if not FVisible or (FWindow = nil) then Exit;

  FWindow.UngrabInput();
  FWindow.Hide();
  FVisible := False;
end;

procedure TShellLauncher.Toggle();
begin
  if FVisible then
    Hide()
  else
    Show();
end;

function TShellLauncher.HandleXcbEvent(Event: Pxcb_generic_event_t): Boolean;
var
  evType: Byte;
  kp: Pxcb_key_press_event_t;
  kr: Pxcb_key_release_event_t;
  bp: Pxcb_button_press_event_t;
  isSuper: Boolean;
  keysym: xcb_keysym_t;
begin
  Result := False;
  if Event = nil then Exit;

  evType := Event^.response_type and $7F;

  case evType of
    XCB_KEY_PRESS:
    begin
      kp := Pxcb_key_press_event_t(Event);
      isSuper := ((FSuperKeycodeL <> 0) and (kp^.detail = FSuperKeycodeL)) or
                 ((FSuperKeycodeR <> 0) and (kp^.detail = FSuperKeycodeR));

      if isSuper then
      begin
        FSuperPressed := True;
        FOtherKeyPressed := False;
        Exit(True);
      end
      else if FSuperPressed then
      begin
        FOtherKeyPressed := True;
      end;

      if FVisible and Assigned(FKeySymbols) then
      begin
        keysym := xcb_key_press_lookup_keysym(FKeySymbols, kp, 0);
        case keysym of
          XK_Escape:
          begin
            Hide();
            Exit(True);
          end;
          XK_Down, XK_KP_Down:
          begin
            SelectNext();
            Exit(True);
          end;
          XK_Up, XK_KP_Up:
          begin
            SelectPrev();
            Exit(True);
          end;
          XK_Page_Down, XK_KP_Page_Down:
          begin
            SelectPageDown();
            Exit(True);
          end;
          XK_Page_Up, XK_KP_Page_Up:
          begin
            SelectPageUp();
            Exit(True);
          end;
        end;
      end;
    end;

    XCB_KEY_RELEASE:
    begin
      kr := Pxcb_key_release_event_t(Event);
      isSuper := ((FSuperKeycodeL <> 0) and (kr^.detail = FSuperKeycodeL)) or
                 ((FSuperKeycodeR <> 0) and (kr^.detail = FSuperKeycodeR));

      if isSuper then
      begin
        if FSuperPressed and not FOtherKeyPressed then
        begin
          Toggle();
        end;
        FSuperPressed := False;
        Exit(True);
      end;
    end;

    XCB_BUTTON_PRESS:
    begin
      if FVisible then
      begin
        bp := Pxcb_button_press_event_t(Event);

        if bp^.detail = 4 then
        begin
          SelectPrev();
          Exit(True);
        end
        else if bp^.detail = 5 then
        begin
          SelectNext();
          Exit(True);
        end;

        if (bp^.event_x < 0) or (bp^.event_x >= LAUNCHER_WIDTH) or
           (bp^.event_y < 0) or (bp^.event_y >= LAUNCHER_HEIGHT) then
        begin
          Hide();
          Exit(True);
        end;
      end;
    end;
  end;
end;

end.
