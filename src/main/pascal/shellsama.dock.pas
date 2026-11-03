{ Unit ShellSama.Dock — macOS-style application dock for Samarinda DE }

unit ShellSama.Dock;

// One icon per application rather than one per window.
//
// Each icon has three visual states, which is what makes a text-free dock readable at
// a glance:
//
//   pinned, not running   plain icon, no marker
//   running, not focused  icon + dim dot underneath
//   running and focused   icon + bright dot underneath
//
// Clicking an app with no window launches it; with one window it activates it; with
// several it opens a list of that app's windows. Right-clicking offers pin/unpin.
//
// The dot is its own widget rather than part of the button: the toolkit exposes no
// per-button paint callback through ftpas, and drawing under the button would be
// painted over by it.

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils, Math,
  Floria.XCB,
  ctypes, ftpas.api, ftpas.types, ftpas, ftpas.creative,
  ShellSama.DesktopApps,
  ShellSama.Launcher,
  ShellSama.BottomPanel,
  ShellSama.DockApps;

type
  TDockEntry = record
    AppKey   : string;
    Title    : string;
    Pinned   : Boolean;
    Windows  : array of Cardinal;  // this app's windows
    IsActive : Boolean;            // one of its windows is focused
    Button   : TFtButton;
    Menu     : TFtPopupMenu;
    MenuPin  : TFtMenuItem;
  end;

  TShellDock = class(TShellBottomPanel)
  private
    FIconSize     : Integer;
    FMaxDockWidth : Integer;
    FDockApps     : TShellDockApps;
    FEntries      : array of TDockEntry;
    FWindowList   : TFtPopupMenu;
    FWindowListKey: string;
    FIconKeys     : TStringList;
    FIconBitmaps  : TList;

    procedure BuildEntries();
    procedure FreeEntries();
    function DotWidth(): Double;
    function IndexOfKey(const AAppKey: string): Integer;
    procedure HandleEntryClick(Sender: TFtButton);
    procedure HandleEntryMenuPin(Sender: TFtMenuItem);
    procedure HandleWindowListItem(Sender: TFtMenuItem);
    procedure ShowWindowList(const AAppKey: string);
    procedure ActivateOrLaunch(const AAppKey: string);
    // Icon for an application: the desktop entry's icon, else the first window's.
    // Cached per app key because the dock draws one icon per app, not per window.
    function IconForApp(const AAppKey: string; APreferredSize: Integer): TFtBitmap;
  protected
    function WindowTitle(): string; override;
    procedure SetupWindow(); override;
    procedure LayoutButtons(); override;
    function DesiredWidth(): Integer;
    function ScreenWidthHint(): Integer;
  public
    constructor Create(ALauncher: TShellLauncher = nil);
    destructor Destroy(); override;

    function PanelX(): Integer; override;
    function PanelWidth(): Integer; override;
    function PanelHeight(): Integer; override;
    function PanelY(): Integer; override;

    procedure RefreshDock();

    function EntryCount(): Integer;
    function EntryAppKey(AIndex: Integer): string;
    function EntryRunning(AIndex: Integer): Boolean;
    function EntryFocused(AIndex: Integer): Boolean;
    function EntryPinned(AIndex: Integer): Boolean;
    function EntryWindowCountAt(AIndex: Integer): Integer;

    property IconSize     : Integer        read FIconSize;
    property MaxDockWidth : Integer        read FMaxDockWidth;
    property DockApps     : TShellDockApps read FDockApps;
  end;

implementation

// The paint callback type is a plain procedure pointer, so the painter is a unit-level
// routine and reaches the live dock through this variable. Only one dock exists.
var
  GActiveDock: TShellDock = nil;

const
  DOCK_ICON_SIZE     = 48;
  DOCK_PADDING       = 10;
  DOCK_GAP           = 6;
  DOCK_MAX_WIDTH     = 720;
  // 8 top + 48 icon + 2 gap + 6 dot + 2 bottom padding.
  //
  // Derived from the measured rows rather than trusted: inside the plate the icon box
  // ends at row 55 (8 + 48 - 1), so the dot must start at 58 and end at 63, and the
  // plate must end at 65. 66 rows total.
  DOCK_HEIGHT        = 66;
  DOCK_BOTTOM_MARGIN = 8;
  DOT_SIZE           = 6;

// Only declarations the window paint path honours: a background colour and a border
// radius. The radius leaves the corners unpainted, so they show the desktop through
// them. Needs a compositor; without one the corners render black.
DOCK_PLATE_CSS =
  'background-color: rgba(24, 24, 32, 0.82);' +
  'border-radius: 18px;';

// A dock icon has almost no chrome until you point at it. The toolkit's default hover
// is a blue halo plus a fully opaque plate, far too loud against a dark dock; this
// replaces it with a faint white wash. Appended rather than loaded, so the theme's own
// rules stay in place.
//
// Colour and alpha only. A border-radius here would drop the hover onto the toolkit's
// halo path, which is the thing being replaced.
// border-width: 0 matters. Without it the paint path falls back to an implicit 1px
// outline (bg colour x 0.8) on hover, which reads as a bright ring around the icon.
DOCK_ICON_CSS =
  'button.dockicon { background-color: rgba(255, 255, 255, 0.00); border-width: 0; } ' +
  'button.dockicon:hover { background-color: rgba(255, 255, 255, 0.10); border-width: 0; } ' +
  'button.dockicon:active { background-color: rgba(255, 255, 255, 0.16); border-width: 0; }';

DOCK_ICON_STYLE_CLASS = 'dockicon';

constructor TShellDock.Create(ALauncher: TShellLauncher);
var
  apps: TDesktopAppList;
begin
  // Set before the inherited constructor, which creates the window and lays out.
  FIconSize := DOCK_ICON_SIZE;
  FMaxDockWidth := DOCK_MAX_WIDTH;

  apps := nil;
  if Assigned(ALauncher) then
    apps := ALauncher.AppList;
  FDockApps := TShellDockApps.Create(apps);

  GActiveDock := Self;
  FIconKeys := TStringList.Create();
  FIconKeys.CaseSensitive := False;
  FIconBitmaps := TList.Create();

  inherited Create(ALauncher, DOCK_ICON_SIZE + (2 * DOCK_PADDING), DOCK_HEIGHT);
end;

destructor TShellDock.Destroy();
var
  i: Integer;
begin
  if GActiveDock = Self then
    GActiveDock := nil;
  FreeEntries();
  for i := 0 to FIconBitmaps.Count - 1 do
    TFtBitmap(FIconBitmaps[i]).Free();
  FIconBitmaps.Free();
  FIconKeys.Free();
  FDockApps.Free();
  inherited Destroy();
end;

function TShellDock.WindowTitle(): string;
begin
  Result := 'shellsama-dock';
end;

procedure TShellDock.SetupWindow();
begin
  inherited SetupWindow();
  if FWindow = nil then Exit;
  FWindow.Style := DOCK_PLATE_CSS;
  FWindow.BackgroundOpacity := 0.82;

  if Assigned(ft_style_append_css_string) then
    ft_style_append_css_string(PChar(DOCK_ICON_CSS));

  FWindow.Invalidate();
end;

function TShellDock.ScreenWidthHint(): Integer;
begin
  if FtIsLibLoaded() and Assigned(ft_screen_get_width) then
    Result := FtApp().ScreenWidth
  else
    Result := 1920;
end;

function TShellDock.PanelHeight(): Integer;
begin
  Result := DOCK_HEIGHT;
end;

function TShellDock.DesiredWidth(): Integer;
var
  n: Integer;
begin
  n := EntryCount();
  if n < 1 then
    Exit(FIconSize + (2 * DOCK_PADDING));
  Result := Min((2 * DOCK_PADDING) + (n * FIconSize) + ((n - 1) * DOCK_GAP),
                FMaxDockWidth);
end;

function TShellDock.PanelWidth(): Integer;
begin
  Result := FPanelWidth;
end;

function TShellDock.PanelX(): Integer;
begin
  Result := (ScreenWidthHint() - PanelWidth()) div 2;
end;

function TShellDock.PanelY(): Integer;
begin
  if FtIsLibLoaded() and Assigned(ft_screen_get_height) then
    Result := FtApp().ScreenHeight - DOCK_HEIGHT - DOCK_BOTTOM_MARGIN
  else
    Result := 1080 - DOCK_HEIGHT - DOCK_BOTTOM_MARGIN;
end;

// ---------------------------------------------------------------- model

function TShellDock.EntryCount(): Integer;
begin
  Result := Length(FEntries);
end;

function TShellDock.EntryAppKey(AIndex: Integer): string;
begin
  Result := '';
  if (AIndex >= 0) and (AIndex < Length(FEntries)) then
    Result := FEntries[AIndex].AppKey;
end;

function TShellDock.EntryRunning(AIndex: Integer): Boolean;
begin
  Result := False;
  if (AIndex >= 0) and (AIndex < Length(FEntries)) then
    Result := Length(FEntries[AIndex].Windows) > 0;
end;

function TShellDock.EntryFocused(AIndex: Integer): Boolean;
begin
  Result := False;
  if (AIndex >= 0) and (AIndex < Length(FEntries)) then
    Result := FEntries[AIndex].IsActive;
end;

function TShellDock.EntryPinned(AIndex: Integer): Boolean;
begin
  Result := False;
  if (AIndex >= 0) and (AIndex < Length(FEntries)) then
    Result := FEntries[AIndex].Pinned;
end;

function TShellDock.EntryWindowCountAt(AIndex: Integer): Integer;
begin
  Result := 0;
  if (AIndex >= 0) and (AIndex < Length(FEntries)) then
    Result := Length(FEntries[AIndex].Windows);
end;

function TShellDock.IndexOfKey(const AAppKey: string): Integer;
var
  i: Integer;
begin
  Result := -1;
  for i := 0 to High(FEntries) do
    if SameText(FEntries[i].AppKey, AAppKey) then
      Exit(i);
end;

// Rebuild the entry list from the pinned list plus the windows that currently exist.
// Pinned apps come first, in config order, then unpinned running apps.
procedure TShellDock.BuildEntries();
var
  i, j, k, winCount: Integer;
  tmp: TDockEntry;
  key, resName, resClass: string;
  activeWin: Cardinal;
  win: Cardinal;
begin
  // Keep the widgets: they are reused by LayoutButtons when the key is unchanged.
  for i := 0 to High(FEntries) do
  begin
    FEntries[i].Windows := nil;
    FEntries[i].IsActive := False;
  end;

  activeWin := QueryActiveWindow();

  // Seed the pinned apps first. Without this an entry can only be created from a
  // running window, so a pinned app showed up only after it had been launched once --
  // and at startup, with nothing running, the dock was empty despite the config.
  for i := 0 to FDockApps.PinnedCount() - 1 do
  begin
    key := FDockApps.PinnedKey(i);
    if (key = '') or (IndexOfKey(key) >= 0) then Continue;

    SetLength(FEntries, Length(FEntries) + 1);
    j := High(FEntries);
    FEntries[j].AppKey := key;
    FEntries[j].Title := FDockApps.AppNameForKey(key);
    FEntries[j].Pinned := True;
    FEntries[j].Windows := nil;
    FEntries[j].IsActive := False;
    FEntries[j].Button := nil;
    FEntries[j].Menu := nil;
    FEntries[j].MenuPin := nil;
  end;

  winCount := TaskCount;

  for i := 0 to winCount - 1 do
  begin
    win := GetTaskWindow(i);
    if win = 0 then Continue;

    QueryWindowClass(win, resName, resClass);
    key := FDockApps.AppKeyForWindow(resName, resClass);
    if key = '' then Continue;

    j := IndexOfKey(key);
    if j < 0 then
    begin
      SetLength(FEntries, Length(FEntries) + 1);
      j := High(FEntries);
      FEntries[j].AppKey := key;
      FEntries[j].Title := FDockApps.AppNameForKey(key);
      FEntries[j].Pinned := FDockApps.IsPinned(key);
      FEntries[j].Windows := nil;
      FEntries[j].Button := nil;
      FEntries[j].Menu := nil;
      FEntries[j].MenuPin := nil;
    end;

    k := Length(FEntries[j].Windows);
    SetLength(FEntries[j].Windows, k + 1);
    FEntries[j].Windows[k] := win;

    if win = activeWin then
      FEntries[j].IsActive := True;
  end;

  // Drop running entries that are no longer pinned and no longer running.
  i := 0;
  while i < Length(FEntries) do
  begin
    if (Length(FEntries[i].Windows) = 0) and not FEntries[i].Pinned then
    begin
      if Assigned(FEntries[i].Button) then begin
        if Assigned(FEntries[i].Menu) then
          FEntries[i].Button.ContextMenuHandle := nil;
        FEntries[i].Button.Free();
      end;
      if Assigned(FEntries[i].Menu) then
        FEntries[i].Menu.Free();

      for j := i to Length(FEntries) - 2 do
        FEntries[j] := FEntries[j + 1];
      SetLength(FEntries, Length(FEntries) - 1);
    end
    else
      Inc(i);
  end;

  // A pinned app that has come and gone keeps Pinned set; refresh the flag because the
  // user may have unpinned it from the menu since the entry was created.
  for i := 0 to High(FEntries) do
  begin
    FEntries[i].Pinned := FDockApps.IsPinned(FEntries[i].AppKey);
    FEntries[i].Title := FDockApps.AppNameForKey(FEntries[i].AppKey);
  end;

  // Pinned entries to the front, keeping relative order otherwise. Without this the
  // icons jump around as apps start and stop, which defeats the point of pinning.
  if Length(FEntries) > 1 then
    for i := 1 to High(FEntries) do
    begin
      j := i;
      while (j > 0) and FEntries[j].Pinned and (not FEntries[j - 1].Pinned) do
      begin
        tmp := FEntries[j];
        FEntries[j] := FEntries[j - 1];
        FEntries[j - 1] := tmp;
        Dec(j);
      end;
    end;
end;

procedure TShellDock.FreeEntries();
var
  i: Integer;
begin
  for i := 0 to High(FEntries) do
  begin
    if Assigned(FEntries[i].Button) then
    begin
      if Assigned(FEntries[i].Menu) then
        FEntries[i].Button.ContextMenuHandle := nil;
      FEntries[i].Button.Free();
    end;
    if Assigned(FEntries[i].Menu) then
      FEntries[i].Menu.Free();
  end;
  SetLength(FEntries, 0);
end;

// Draws the running indicator under the icon. AUserData carries the entry index, so
// the painter needs no lookup through the widget tree.
procedure DockButtonOverlay(Button: Pointer; ACanvas: Pointer;
  AX, AY, AW, AH: Double; AState: cint32; AUserData: Pointer); cdecl;
var
  idx: Integer;
  cv: TFtCanvas;
  radius, cxp, cyp: Double;
  focused: Boolean;
begin
  if (ACanvas = nil) or (GActiveDock = nil) then Exit;
  idx := PtrInt(AUserData);
  if (idx < 0) or (idx >= GActiveDock.EntryCount) then Exit;
  if GActiveDock.EntryWindowCountAt(idx) = 0 then Exit;

  focused := GActiveDock.EntryFocused(idx);
  // AX/AY are the button's position in WINDOW coordinates, not offsets inside it, so
  // the dot is placed relative to the button's own rectangle.
  cxp := AX + (AW / 2);
  cyp := AY + AH + 3;
  radius := DOT_SIZE / 2;

  cv := TFtCanvas.Create(ACanvas);
  try
    if focused then
      cv.DrawCircle(cxp, cyp, radius, 0.95, 0.95, 0.98, 1.0)
    else
      cv.DrawCircle(cxp, cyp, radius - 0.5, 0.55, 0.58, 0.64, 0.85);
  finally
    cv.Free();
  end;
end;

// ---------------------------------------------------------------- layout

procedure TShellDock.LayoutButtons();
var
  i, iconX, iconY, x, wantW: Integer;
  iconBmp: TFtBitmap;
begin
  if FWindow = nil then Exit;

  BuildEntries();

  // Resize in place, in the same pass. Recreating the window would drop its strut and
  // make every maximized client flash.
  wantW := DesiredWidth();
  if wantW <> FPanelWidth then
    ResizeWindow(wantW, DOCK_HEIGHT, (ScreenWidthHint() - wantW) div 2);

  iconY := 8;

  if Length(FEntries) = 0 then
  begin
    FWindow.Invalidate();
    Exit;
  end;

  iconX := (PanelWidth() - (Length(FEntries) * FIconSize) -
            ((Length(FEntries) - 1) * DOCK_GAP)) div 2;
  if iconX < DOCK_PADDING then
    iconX := DOCK_PADDING;

  for i := 0 to High(FEntries) do
  begin
    x := iconX + (i * (FIconSize + DOCK_GAP));

    if FEntries[i].Button = nil then
    begin
      FEntries[i].Button := TFtButton.Create(FWindow, x, iconY, FIconSize, FIconSize,
                                             FEntries[i].Title);
      FEntries[i].Button.IsToggle := True;
      FEntries[i].Button.Flat := True;
      FEntries[i].Button.StyleClass := DOCK_ICON_STYLE_CLASS;
      // A tooltip per icon is redundant: the icon is the label.
      FEntries[i].Button.ShowHint := False;
      FEntries[i].Button.IconPosition := ftipOnly;
      FEntries[i].Button.OnClick := @HandleEntryClick;
    end
    else
      FEntries[i].Button.SetBounds(x, iconY, FIconSize, FIconSize);

    FEntries[i].Button.Tag := i;
    FEntries[i].Button.Caption := FEntries[i].Title;

    if FEntries[i].Menu = nil then
    begin
      FEntries[i].Menu := TFtPopupMenu.Create(FWindow);
      if FEntries[i].Menu <> nil then
      begin
        FEntries[i].MenuPin := FEntries[i].Menu.AddItem('Pin to dock', @HandleEntryMenuPin);
        if Assigned(FEntries[i].MenuPin) then
          FEntries[i].MenuPin.Tag := i;
      end;
    end
    else if Assigned(FEntries[i].MenuPin) then
    begin
      FEntries[i].MenuPin.Tag := i;
      if FEntries[i].Pinned and FDockApps.HasDesktopEntry(FEntries[i].AppKey) then
        FEntries[i].MenuPin.Caption := 'Unpin from dock'
      else if FDockApps.HasDesktopEntry(FEntries[i].AppKey) then
        FEntries[i].MenuPin.Caption := 'Pin to dock';
    end;

    if Assigned(FEntries[i].Menu) then
      FEntries[i].Button.ContextMenuHandle := FEntries[i].Menu.Handle;

    iconBmp := IconForApp(FEntries[i].AppKey, FIconSize);
    if Assigned(iconBmp) then
    begin
      FEntries[i].Button.SetIconBitmap(iconBmp, False);
      FEntries[i].Button.SetIconSize(FIconSize, FIconSize);
      FEntries[i].Button.IconGap := 0;
    end
    else
      FEntries[i].Button.ClearIcon();

    // No toggled plate: the dot underneath says whether the app is running and which
    // app has focus, so a filled button on top of that is redundant and heavy.
    FEntries[i].Button.Toggled := False;

    // The running indicator is drawn by the button's own paint overlay, not by a
    // child widget: a child at the bottom of the stack is covered by its siblings, and
    // a drawing area above them would intercept clicks meant for the icon.
    FEntries[i].Button.SetOnPaint(@DockButtonOverlay, Pointer(PtrInt(i)));
  end;

  FWindow.Invalidate();
end;

function TShellDock.IconForApp(const AAppKey: string; APreferredSize: Integer): TFtBitmap;
var
  i, idx: Integer;
  path: string;
begin
  Result := nil;
  if AAppKey = '' then Exit;

  i := FIconKeys.IndexOf(AAppKey);
  if i >= 0 then
    Exit(TFtBitmap(FIconBitmaps[i]));

  // A pinned app that is not running has no windows to take an icon from, so the
  // desktop entry's icon is the only source.
  path := '';
  if FDockApps.AppIconForKey(AAppKey) <> '' then
    path := ResolveIconPath(FDockApps.AppIconForKey(AAppKey), APreferredSize);

  if path <> '' then
    Result := LoadIconBitmap(path, APreferredSize, APreferredSize);

  if Result = nil then
  begin
    idx := IndexOfKey(AAppKey);
    if (idx >= 0) and (Length(FEntries[idx].Windows) > 0) then
      Result := QueryWindowIcon(FEntries[idx].Windows[0], APreferredSize);
  end;

  if Result = nil then
    Result := CreateFallbackIcon(APreferredSize, APreferredSize);

  FIconKeys.Add(AAppKey);
  FIconBitmaps.Add(Result);
end;

function TShellDock.DotWidth(): Double;
begin
  Result := DOT_SIZE;
end;

// Draws the running indicator under the icon. AUserData carries the entry index, so
// the painter needs no lookup and no global state.

// ---------------------------------------------------------------- interaction

procedure TShellDock.HandleEntryClick(Sender: TFtButton);
var
  idx: Integer;
begin
  if Sender = nil then Exit;
  idx := Integer(Sender.Tag);
  if (idx < 0) or (idx >= Length(FEntries)) then Exit;

  // Several windows: let the user pick one. One window: just activate. None: launch.
  if Length(FEntries[idx].Windows) > 1 then
    ShowWindowList(FEntries[idx].AppKey)
  else
    ActivateOrLaunch(FEntries[idx].AppKey);
end;

procedure TShellDock.ActivateOrLaunch(const AAppKey: string);
var
  idx: Integer;
  win: Cardinal;
begin
  idx := IndexOfKey(AAppKey);
  if (idx < 0) then Exit;

  if Length(FEntries[idx].Windows) = 0 then
  begin
    FDockApps.Launch(AAppKey);
    Exit;
  end;

  win := FEntries[idx].Windows[Length(FEntries[idx].Windows) - 1];
  ActivateWindow(win);
end;

procedure TShellDock.ShowWindowList(const AAppKey: string);
var
  idx, i, listH: Integer;
  item: TFtMenuItem;
  title: string;
begin
  idx := IndexOfKey(AAppKey);
  if idx < 0 then Exit;

  if Assigned(FWindowList) then
  begin
    FWindowList.Free();
    FWindowList := nil;
  end;

  FWindowList := TFtPopupMenu.Create(FWindow);
  if FWindowList = nil then Exit;
  FWindowListKey := AAppKey;

  for i := 0 to High(FEntries[idx].Windows) do
  begin
    title := QueryWindowTitle(FEntries[idx].Windows[i]);
    if title = '' then
      title := FDockApps.AppNameForKey(AAppKey);
    item := FWindowList.AddItem(title, @HandleWindowListItem);
    if item <> nil then
      item.Tag := Int64(FEntries[idx].Windows[i]);
  end;

  // Anchor the list above the icon that opened it. Show() takes coordinates LOCAL to
  // the dock window and converts them to screen itself, so the icon's button bounds are
  // already the right coordinate space. Passing screen coordinates here put the list
  // off at the bottom-right of the screen, because the dock's own position was then
  // added a second time.
  // Sit the list ABOVE the icon, not on top of it. The toolkit's item height is 28px
  // and it lays out one row per entry, so the list's own height follows from the
  // window count and can be subtracted here.
  listH := FWindowList.ItemCount * 28;
  if Assigned(FEntries[idx].Button) then
    FWindowList.Show(FEntries[idx].Button.X,
                     FEntries[idx].Button.Y - listH - 4)
  else
    FWindowList.Show(PanelWidth() div 2, 0);
end;

procedure TShellDock.HandleWindowListItem(Sender: TFtMenuItem);
begin
  if (Sender = nil) or (Sender.Tag = 0) then Exit;
  ActivateWindow(Cardinal(Sender.Tag));
end;

procedure TShellDock.HandleEntryMenuPin(Sender: TFtMenuItem);
var
  idx: Integer;
begin
  if Sender = nil then Exit;
  idx := Sender.Tag;
  if (idx < 0) or (idx >= Length(FEntries)) then Exit;

  if FDockApps.IsPinned(FEntries[idx].AppKey) then
  begin
    FDockApps.Unpin(FEntries[idx].AppKey);
    FEntries[idx].Pinned := False;
  end
  else if FDockApps.Pin(FEntries[idx].AppKey) then
    FEntries[idx].Pinned := True;

  FWindow.Invalidate();
end;

procedure TShellDock.RefreshDock();
begin
  if FWindow = nil then Exit;
  LayoutButtons();
end;

end.
