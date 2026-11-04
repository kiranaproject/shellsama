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
  ShellSama.DockApps,
  ShellSama.WindowPixmaps,
  ShellSama.PreviewPopup,
  ShellSama.PreviewLayout;

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
    FLayoutIconSize : Integer;
    FLayoutIconX    : Integer;
    FSkipEntryRebuild: Boolean;
    FPreviewLive  : Boolean;
    FScrollOffset   : Integer;   // pixels the row is scrolled left
    FMaxScroll      : Integer;   // 0 when the row fits
    FContentWidth   : Integer;
    FDockApps     : TShellDockApps;
    FEntries      : array of TDockEntry;
    // Replaces the old text list. See ShellSama.PreviewPopup and the design note.
    FPreview      : TShellPreviewPopup;
    FPreviewKey   : string;
    FPreviewWins  : array of Cardinal;   // what the popup was opened with
    FIconKeys     : TStringList;
    FIconBitmaps  : TList;
    // One Composite pixmap per running window, held for the window's life. See
    // ShellSama.WindowPixmaps for why the name has to be held rather than taken when a
    // preview is opened.
    FPixmaps      : TWindowPixmapStore;

    procedure BuildEntries();
    procedure FreeEntries();
    function DotWidth(): Double;
    function IndexOfKey(const AAppKey: string): Integer;
    procedure HandleEntryClick(Sender: TFtButton);
    procedure HandleEntryMenuPin(Sender: TFtMenuItem);
    procedure HandlePreviewActivate(AWindow: Cardinal);
    // Fills the preview tile's context menu with the same window actions the task list
    // offers, so there is one implementation of "minimize, maximize, close".
    procedure BuildPreviewTileMenu(AWindow: Cardinal; AParent: TFtWidget);
    procedure ShowPreview(const AAppKey: string);
    // Closes the popup if the app's window set no longer matches what it was opened
    // with. An activation request for a window that has gone is at best a no-op and at
    // worst raises an unrelated application, because X reuses ids.
    procedure SyncPreview();
    procedure ActivateOrLaunch(const AAppKey: string);
    // Wheel over the dock: buttons 4 and 5 are vertical, 6 and 7 horizontal. The
    // toolkit forwards wheel events from child buttons up to the window, so this sees
    // them wherever the pointer is over an icon.
    procedure HandleDockMouseDown(Sender: TFtWindow; AX, AY, AButton: Integer);
    // Brings the per-window pixmaps in line with the running windows. Runs on the panel
    // timer, because the toolkit's event loop drops events for windows it does not own,
    // so the dock cannot subscribe to their ConfigureNotify.
    procedure RefreshPixmaps();
    // Icon for an application: the desktop entry's icon, else the first window's.
    // Cached per app key because the dock draws one icon per app, not per window.
    function IconForApp(const AAppKey: string; APreferredSize: Integer): TFtBitmap;
  protected
    // Any window action chosen from a preview tile ends that interaction: the popup was
    // there to pick a window, and acting on one is the answer.
    procedure WindowActionPerformed(AWin: Cardinal); override;
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
    procedure Tick(); override;

    function EntryCount(): Integer;
    // Adds APinnedCount placeholder entries and lays out, so the fit arithmetic can be
    // exercised without starting a dozen real applications. Test use only.
    procedure DebugPopulateEntries(ACount: Integer);
    // Scroll by ADelta pixels, clamped. Returns True if anything moved.
    function ScrollBy(ADelta: Integer): Boolean;
    function ScrollOffset(): Integer;
    function MaxScroll(): Integer;
    // Icon side length the last layout used, after any shrink-to-fit.
    function LayoutIconSize(): Integer;
    function LayoutIconX(): Integer;
    function EntryAppKey(AIndex: Integer): string;
    function EntryRunning(AIndex: Integer): Boolean;
    // How many windows currently have a held pixmap. Test use only.
    function PixmapCount(): Integer;
    // Turns live refresh on for previews. On by default; a test or a low-power session can
    // turn it off.
    procedure SetPreviewLive(AValue: Boolean);
    function PreviewLive(): Boolean;
    // Opens the preview for the app whose key is AAppKey, as a click would. Test use
    // only: without it the popup can only be reached through real pointer input.
    procedure DebugShowPreview(const AAppKey: string);
    // Fills AMenu as a right-click on AWindow's tile would, with AWindow's current
    // state. Test use only: the real path goes through the popup's mouse handling.
    procedure DebugBuildTileMenu(AWindow: Cardinal; AMenu: TFtPopupMenu);
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
  // Off by default: see docs/window-previews.md §9 (Q5). Refreshing an open preview
  // grows the shell's RSS by ~66MB per 30s, and the growth is in the popup's repaint of
  // the sheet rather than in the sheet build. It is not in the toolkit: a standalone
  // program drawing the same bitmap 841 times stays flat. Until that is understood,
  // enabling this by default would trade a cosmetic improvement for a leak, so it is
  // opt-in. SHELLSAMA_LIVE_PREVIEW=1 turns it on.
  FPreviewLive := GetEnvironmentVariable('SHELLSAMA_LIVE_PREVIEW') = '1';

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
  if Assigned(FPixmaps) then
  begin
    FPixmaps.Free();
    FPixmaps := nil;
  end;
  if Assigned(FPreview) then
  begin
    FPreview.Free();
    FPreview := nil;
  end;
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
  FWindow.OnMouseDown := @HandleDockMouseDown;

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

function TShellDock.ScrollBy(ADelta: Integer): Boolean;
var
  before: Integer;
begin
  before := FScrollOffset;
  FScrollOffset := FScrollOffset + ADelta;
  if FScrollOffset > FMaxScroll then
    FScrollOffset := FMaxScroll;
  if FScrollOffset < 0 then
    FScrollOffset := 0;
  Result := FScrollOffset <> before;
  if Result then
    LayoutButtons();
end;

function TShellDock.ScrollOffset(): Integer;
begin
  Result := FScrollOffset;
end;

function TShellDock.MaxScroll(): Integer;
begin
  Result := FMaxScroll;
end;

procedure TShellDock.HandleDockMouseDown(Sender: TFtWindow; AX, AY, AButton: Integer);
const
  WHEEL_STEP = 54;   // one icon plus one gap
begin
  case AButton of
    4: ScrollBy(-WHEEL_STEP);   // wheel up
    5: ScrollBy(WHEEL_STEP);    // wheel down
    6: ScrollBy(-WHEEL_STEP);   // wheel left (horizontal wheels)
    7: ScrollBy(WHEEL_STEP);    // wheel right
  end;
end;

procedure TShellDock.DebugPopulateEntries(ACount: Integer);
var
  i: Integer;
begin
  FreeEntries();
  SetLength(FEntries, ACount);
  for i := 0 to ACount - 1 do
  begin
    FEntries[i].AppKey := 'test-app-' + IntToStr(i);
    FEntries[i].Title := 'Test ' + IntToStr(i);
    FEntries[i].Button := nil;
    FEntries[i].Menu := nil;
    FEntries[i].MenuPin := nil;
    FEntries[i].Windows := nil;
  end;
  FLayoutIconSize := FIconSize;
  FLayoutIconX := 0;
  // Stays set: the synthetic list is only replaced by another DebugPopulateEntries
  // call, so scroll passes during a test do not rebuild it from (empty) live windows.
  FSkipEntryRebuild := True;
  LayoutButtons();
end;

function TShellDock.LayoutIconSize(): Integer;
begin
  Result := FLayoutIconSize;
end;

function TShellDock.LayoutIconX(): Integer;
begin
  Result := FLayoutIconX;
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
  i, iconX, iconY, x, wantW, btnSize, gap, total: Integer;
  opacity: Double;
  iconBmp: TFtBitmap;
begin
  if FWindow = nil then Exit;

  // The test seam fills the list itself; rebuilding from windows would discard it.
  if not FSkipEntryRebuild then
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

  // Icons keep their size; when the row is wider than the plate the dock scrolls
  // instead of shrinking. Shrinking was the earlier behaviour and it made a busy dock
  // unreadable, which is the opposite of what a dock is for.
  btnSize := FIconSize;
  gap := DOCK_GAP;
  total := (Length(FEntries) * btnSize) + ((Length(FEntries) - 1) * gap);

  FContentWidth := total;
  FMaxScroll := total + (2 * DOCK_PADDING) - PanelWidth();
  if FMaxScroll < 0 then
    FMaxScroll := 0;
  // Clamp AFTER the new maximum is known. Clamping first truncates the offset using
  // the previous layout's maximum, which silently undoes a scroll on the pass that
  // changes the entry count.
  if FScrollOffset > FMaxScroll then
    FScrollOffset := FMaxScroll;
  if FScrollOffset < 0 then
    FScrollOffset := 0;

  // Centred when the row fits, scrolled from the left padding when it does not.
  if FMaxScroll = 0 then
    iconX := (PanelWidth() - total) div 2
  else
    iconX := DOCK_PADDING - FScrollOffset;
  if (FMaxScroll = 0) and (iconX < DOCK_PADDING) then
    iconX := DOCK_PADDING;

  iconY := (DOCK_HEIGHT - btnSize) div 2 - 3;
  FLayoutIconSize := btnSize;
  FLayoutIconX := iconX;

  for i := 0 to High(FEntries) do
  begin
    x := iconX + (i * (btnSize + gap));

    if FEntries[i].Button = nil then
    begin
      FEntries[i].Button := TFtButton.Create(FWindow, x, iconY, btnSize, btnSize,
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
      FEntries[i].Button.SetBounds(x, iconY, btnSize, btnSize);

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

    iconBmp := IconForApp(FEntries[i].AppKey, btnSize);
    if Assigned(iconBmp) then
    begin
      FEntries[i].Button.SetIconBitmap(iconBmp, False);
      FEntries[i].Button.SetIconSize(btnSize, btnSize);
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

    // Fade the icons that are leaving or entering at the clipped edge, when the row is
    // scrolled. Nothing else marks the overflow, so without this the dock just looks
    // cut off. Opacity is per widget, so this needs no window paint hook.
    opacity := 1.0;
    if FMaxScroll > 0 then
    begin
      if x < DOCK_PADDING then
        opacity := 0.15 + (0.85 * ((x + btnSize - DOCK_PADDING) / btnSize))
      else if x + btnSize > PanelWidth() - DOCK_PADDING then
        opacity := 0.15 + (0.85 * (((PanelWidth() - DOCK_PADDING) - x) / btnSize));
      if opacity < 0.15 then opacity := 0.15;
      if opacity > 1.0 then opacity := 1.0;
    end;
    FEntries[i].Button.Opacity := opacity;
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
    ShowPreview(FEntries[idx].AppKey)
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

procedure TShellDock.ShowPreview(const AAppKey: string);
var
  idx, i: Integer;
  wins: array of Cardinal;
  titles: array of string;
  centerX, iconTop, screenW: Integer;
  rootVisual: Cardinal;
  dockX, dockY: Integer;
begin
  idx := IndexOfKey(AAppKey);
  if idx < 0 then Exit;
  if Length(FEntries[idx].Windows) = 0 then Exit;

  if FPreview = nil then
  begin
    if FConn = nil then Exit;
    rootVisual := 0;
    if FScreen <> nil then
      rootVisual := FScreen^.root_visual;
    FPreview := TShellPreviewPopup.Create(FConn, FRootWindow, rootVisual, TopInset());
    if FPreview = nil then Exit;
    FPreview.OnActivate := @HandlePreviewActivate;
    FPreview.OnBuildTileMenu := @BuildPreviewTileMenu;
    // Dismissal closes the popup by itself; the dock only needs to forget which app it
    // belonged to, so the next click on the same icon reopens rather than toggles.
    FPreview.OnDismiss := nil;
  end;

  SetLength(wins, Length(FEntries[idx].Windows));
  SetLength(titles, Length(FEntries[idx].Windows));
  for i := 0 to High(wins) do
  begin
    wins[i] := FEntries[idx].Windows[i];
    titles[i] := QueryWindowTitle(wins[i]);
    if titles[i] = '' then
      titles[i] := FDockApps.AppNameForKey(AAppKey);
  end;

  FPreviewKey := AAppKey;
  FPreviewWins := Copy(wins);

  // Anchor to the icon's centre, not its left edge: the popup is centred on it.
  //
  // The button's bounds are LOCAL to the dock window, and the popup is a top-level
  // window placed in screen coordinates. Passing the local values put the popup at the
  // top-left of the screen, which is what happens when the dock's own position is left
  // out of the arithmetic.
  screenW := ScreenWidthHint();
  dockX := 0;
  dockY := 0;
  if Assigned(FWindow) then
    FWindow.GetPosition(dockX, dockY);

  if Assigned(FEntries[idx].Button) then
  begin
    centerX := dockX + FEntries[idx].Button.X + (FEntries[idx].Button.Width div 2);
    iconTop := dockY + FEntries[idx].Button.Y;
  end
  else
  begin
    centerX := dockX + (PanelWidth() div 2);
    iconTop := dockY;
  end;

  FPreview.SetLive(FPreviewLive);
  FPreview.Show(wins, titles, FPixmaps, centerX, iconTop, screenW);
end;

procedure TShellDock.SyncPreview();
var
  idx, i: Integer;
  same: Boolean;
begin
  if (FPreview = nil) or not FPreview.IsOpen() then Exit;

  idx := IndexOfKey(FPreviewKey);
  same := (idx >= 0) and (Length(FEntries[idx].Windows) = Length(FPreviewWins));
  if same then
    for i := 0 to High(FPreviewWins) do
      if FEntries[idx].Windows[i] <> FPreviewWins[i] then
      begin
        same := False;
        Break;
      end;

  if same then Exit;

  // The list changed under it. Close rather than re-lay-out: the popup was anchored to
  // an icon whose window count no longer matches, and rebuilding it mid-interaction
  // would move the thing under the pointer.
  FPreview.Close();
  FPreviewKey := '';
  FPreviewWins := nil;
end;

procedure TShellDock.WindowActionPerformed(AWin: Cardinal);
begin
  inherited WindowActionPerformed(AWin);
  if Assigned(FPreview) and FPreview.IsOpen() then
  begin
    FPreview.Close();
    FPreviewKey := '';
    FPreviewWins := nil;
  end;
end;

procedure TShellDock.BuildPreviewTileMenu(AWindow: Cardinal; AParent: TFtWidget);
var
  menu: TFtPopupMenu;
  item: TFtMenuItem;
begin
  if (AWindow = 0) or not (AParent is TFtPopupMenu) then Exit;
  menu := TFtPopupMenu(AParent);

  AddWindowActions(menu, AWindow);

  // Captions follow the window's state, the way the task list does it, so the user is
  // never offered "Minimize" for a window that is already minimized. Re-read here rather
  // than trusting a cached flag: the menu is built at the moment of the right-click.
  item := FindWindowAction(menu, 'Minimize');
  if (item <> nil) and IsWindowMinimized(AWindow) then
    item.Caption := 'Restore';

  item := FindWindowAction(menu, 'Maximize');
  if (item <> nil) and IsWindowMaximized(AWindow) then
    item.Caption := 'Restore';
end;

procedure TShellDock.HandlePreviewActivate(AWindow: Cardinal);
var
  idx, i: Integer;
begin
  // The popup was open when this window was listed, but it may have closed since. X
  // reuses ids, so activating a stale one would raise an unrelated application.
  idx := IndexOfKey(FPreviewKey);
  if idx >= 0 then
    for i := 0 to High(FEntries[idx].Windows) do
      if FEntries[idx].Windows[i] = AWindow then
      begin
        ActivateWindow(AWindow);
        Exit;
      end;
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

procedure TShellDock.Tick();
begin
  inherited Tick();
  RefreshPixmaps();
  SyncPreview();

  // Live previews. Cheap enough to run here: a full eight-tile sheet measures ~2.3ms
  // (scripts/probe-refresh-cost.py), and the popup only asks for one every 100ms.
  //
  // This is why damage is not used. The toolkit's event filter is a single global
  // callback that shellsama's tray already chains to the launcher's; a third link in that
  // chain would silently replace one of them, and DamageNotify delivery to a non-owning
  // client depends on initialising the extension first, which is one more thing to get
  // wrong for a popup that is open for a second.
  if FPreviewLive and Assigned(FPreview) and FPreview.IsOpen() then
    FPreview.RefreshIfDue(GetTickCount64());
end;

procedure TShellDock.RefreshPixmaps();
var
  wins: array of Cardinal;
  snapshots: TWindowSnapshotArray;
  i, j, n: Integer;
begin
  if FConn = nil then Exit;

  // Created lazily: the store needs the connection, which only exists once libft is up.
  if FPixmaps = nil then
    FPixmaps := TWindowPixmapStore.Create(FConn);

  SetLength(wins, 0);
  n := 0;
  for i := 0 to High(FEntries) do
    for j := 0 to High(FEntries[i].Windows) do
    begin
      SetLength(wins, n + 1);
      wins[n] := FEntries[i].Windows[j];
      Inc(n);
    end;

  // Nothing running: release every name instead of holding them for an app that may
  // never come back. A held name outlives its window, so this is the difference between
  // releasing and leaking.
  if n = 0 then
  begin
    if FPixmaps.Count() > 0 then
      FPixmaps.Clear();
    Exit;
  end;

  snapshots := QueryWindowSnapshots(FConn, wins);
  FPixmaps.Refresh(snapshots);
end;

procedure TShellDock.SetPreviewLive(AValue: Boolean);
begin
  FPreviewLive := AValue;
  if Assigned(FPreview) then
    FPreview.SetLive(AValue);
end;

function TShellDock.PreviewLive(): Boolean;
begin
  Result := FPreviewLive;
end;

procedure TShellDock.DebugBuildTileMenu(AWindow: Cardinal; AMenu: TFtPopupMenu);
begin
  BuildPreviewTileMenu(AWindow, AMenu);
end;

procedure TShellDock.DebugShowPreview(const AAppKey: string);
begin
  ShowPreview(AAppKey);
end;

function TShellDock.PixmapCount(): Integer;
begin
  if FPixmaps = nil then
    Exit(0);
  Result := FPixmaps.Count();
end;

end.
