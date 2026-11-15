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
  ShellSama.PreviewLayout,
  ShellSama.Settings;

type
  TDockHideState = (
    dhsVisible,
    dhsHiding,
    dhsHidden,
    dhsShowing
  );

  TDockEntry = record
    AppKey   : string;
    Title    : string;
    Pinned   : Boolean;
    Windows  : array of Cardinal;  // this app's windows
    IsActive : Boolean;            // one of its windows is focused
    Button   : TFtButton;
    Menu     : TFtPopupMenu;
    MenuPin  : TFtMenuItem;
    MenuMinimize: TFtMenuItem;
    MenuMaximize: TFtMenuItem;
    MenuClose   : TFtMenuItem;
    MenuWindow  : Cardinal;
  end;

  TShellDock = class(TShellBottomPanel)
  private
    FIconSize     : Integer;
    FMaxDockWidth : Integer;
    FMaxDockHeight: Integer;
    FLastDockPosition : string;
    FLastDockMargin   : Integer;
    FLastDockAutoHide : Boolean;
    FHideState        : TDockHideState;
    FAnimProgress     : Double;
    FAnimTarget       : Double;
    FAnimStart        : QWord;
    FTriggerWin       : xcb_window_t;
    FLayoutIconSize : Integer;
    FLayoutIconX    : Integer;
    FSkipEntryRebuild: Boolean;
    FPreviewLive  : Boolean;
    FScrollOffset   : Integer;   // pixels the row is scrolled left
    FMaxScroll      : Integer;   // 0 when the row fits
    FContentWidth   : Integer;
    FContentHeight  : Integer;
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
    FLastDarkMode : Boolean;

    function ScreenHeightHint(): Integer;
    function DesiredHeight(): Integer;
    function IsWindowOverlapping(): Boolean;
    function IsPointerInsideDock(): Boolean;
    function IsPointerAtTriggerEdge(): Boolean;
    procedure SetupTriggerWindow();
    procedure DestroyTriggerWindow();

    procedure HandleSettingsDarkModeChange(Sender: TObject);
    procedure HandleSettingsDockChange(Sender: TObject);
    procedure BuildEntries();
    procedure FreeEntries();
    function DotWidth(): Double;
    function IndexOfKey(const AAppKey: string): Integer;
    procedure HandleEntryClick(Sender: TFtButton);
    procedure HandleEntryMenuPin(Sender: TFtMenuItem);
    procedure UpdateEntryMenu(AIndex: Integer);
    procedure UpdateEntryMenuStates();
    procedure HandlePreviewActivate(AWindow: Cardinal);
    // Fills the preview tile's context menu with the same window actions the task list
    // offers, so there is one implementation of "minimize, maximize, close".
    procedure BuildPreviewTileMenu(AWindow: Cardinal; AParent: TFtWidget);
    procedure ShowPreview(const AAppKey: string);
    // Closes the popup if the app's window set no longer matches what it was opened
    // with. An activation request for a window that has gone is at best a no-op and at
    // worst raises an unrelated application, because X reuses ids.
    procedure SyncPreview();
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
    function ComputeStrutBottom(): Integer; override;
    function ComputeStrutLeft(): Integer; override;
    function ComputeStrutRight(): Integer; override;
    function IsAnimating(): Boolean; override;
    procedure UpdateStruts(); override;
    procedure ApplyThemeStyle(); override;

    function IsVertical(): Boolean;
    procedure StartShow();
    procedure StartHide();
    procedure StepAnimation();
    procedure ShowImmediate();

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
    procedure ActivateOrLaunch(const AAppKey: string);
    // Simulates clicking an entry by index. Test use only.
    procedure DebugClickEntry(AIndex: Integer);
    // Sets window list for a synthetic entry. Test use only.
    procedure DebugSetEntryWindows(AIndex: Integer; const AWins: array of Cardinal);
    function EntryMenu(AIndex: Integer): TFtPopupMenu;

    property IconSize     : Integer        read FIconSize;
    property MaxDockWidth : Integer        read FMaxDockWidth;
    property MaxDockHeight: Integer        read FMaxDockHeight;
    property DockApps     : TShellDockApps read FDockApps;
    property HideState    : TDockHideState read FHideState;
    property AnimProgress : Double         read FAnimProgress;
    property TriggerWindow: xcb_window_t   read FTriggerWin;
  end;

implementation

// The paint callback type is a plain procedure pointer, so the painter is a unit-level
// routine and reaches the live dock through this variable. Only one dock exists.
var
  GActiveDock: TShellDock = nil;

procedure c_free(p: Pointer); cdecl; external 'c' name 'free';

const
  DOCK_ICON_SIZE     = 48;
  DOCK_PADDING       = 10;
  DOCK_GAP           = 6;
  DOCK_MAX_WIDTH     = 720;
  // 6 top + 48 icon + 6 bottom margin: symmetrical 6px vertical margins.
  // Running window indicator dot (diameter 6px) sits near the icon bottom edge,
  // bleeding slightly to the top close to the icon.
  DOCK_HEIGHT        = 60;
  DOCK_BOTTOM_MARGIN = 3;
  DOCK_TOP_MARGIN    = 3;
  DOT_SIZE           = 6;

// Only declarations the window paint path honours: a background colour and a border
// radius. The radius leaves the corners unpainted, so they show the desktop through
// them. Needs a compositor; without one the corners render black.
DOCK_PLATE_CSS_DARK =
  'background-color: rgba(24, 24, 32, 0.82);' +
  'border-radius: 18px;';

DOCK_PLATE_CSS_LIGHT =
  'background-color: rgba(255, 255, 255, 0.85);' +
  'border-radius: 18px;';

DOCK_PLATE_CSS = DOCK_PLATE_CSS_DARK;

// A dock icon has almost no chrome until you point at it. The toolkit's default hover
// is a blue halo plus a fully opaque plate, far too loud against a dock; this replaces
// it with a faint wash (white on dark plate, charcoal on light plate). Appended rather
// than loaded, so the theme's own rules stay in place.
//
// Colour and alpha only. A border-radius here would drop the hover onto the toolkit's
// halo path, which is the thing being replaced.
// border-width: 0 matters. Without it the paint path falls back to an implicit 1px
// outline (bg colour x 0.8) on hover, which reads as a bright ring around the icon.
DOCK_ICON_CSS =
  'button.dockicon { background-color: rgba(0, 0, 0, 0.00); border-width: 0; } ' +
  'button.dockicon:hover { background-color: rgba(0, 0, 0, 0.08); border-width: 0; } ' +
  'button.dockicon:active { background-color: rgba(0, 0, 0, 0.14); border-width: 0; } ' +
  '.dark button.dockicon { background-color: rgba(255, 255, 255, 0.00); border-width: 0; } ' +
  '.dark button.dockicon:hover { background-color: rgba(255, 255, 255, 0.10); border-width: 0; } ' +
  '.dark button.dockicon:active { background-color: rgba(255, 255, 255, 0.16); border-width: 0; } ' +
  'window.dark button.dockicon { background-color: rgba(255, 255, 255, 0.00); border-width: 0; } ' +
  'window.dark button.dockicon:hover { background-color: rgba(255, 255, 255, 0.10); border-width: 0; } ' +
  'window.dark button.dockicon:active { background-color: rgba(255, 255, 255, 0.16); border-width: 0; }';

DOCK_ICON_STYLE_CLASS = 'dockicon';

constructor TShellDock.Create(ALauncher: TShellLauncher);
var
  apps: TDesktopAppList;
begin
  // Set before the inherited constructor, which creates the window and lays out.
  if (ShellSettings().DockIconSize >= 24) and (ShellSettings().DockIconSize <= 128) then
    FIconSize := ShellSettings().DockIconSize
  else
    FIconSize := DOCK_ICON_SIZE;
  FMaxDockWidth := DOCK_MAX_WIDTH;
  FMaxDockHeight := ScreenHeightHint() - 38 - (2 * DOCK_PADDING);
  FLastDockPosition := ShellSettings().DockPosition;
  FLastDockMargin := ShellSettings().DockMargin;
  FLastDockAutoHide := ShellSettings().DockAutoHide;
  FHideState := dhsVisible;
  FAnimProgress := 1.0;
  FAnimTarget := 1.0;
  FAnimStart := 0;
  FTriggerWin := 0;

  // On by default. It was opt-in while a refresh grew the shell's memory by 66MB/30s;
  // that turned out to be the toolkit choosing its EGL backend on a server with no DRI3
  // device, so every repaint ran through gallium's software path. The toolkit now asks
  // the server instead of assuming, and a refresh costs ~3% of one core with flat RSS
  // (see docs/window-previews.md Q5). SHELLSAMA_LIVE_PREVIEW=0 still turns it off.
  FPreviewLive := GetEnvironmentVariable('SHELLSAMA_LIVE_PREVIEW') <> '0';

  apps := nil;
  if Assigned(ALauncher) then
    apps := ALauncher.AppList;
  FDockApps := TShellDockApps.Create(apps);

  GActiveDock := Self;
  FIconKeys := TStringList.Create();
  FIconKeys.CaseSensitive := False;
  FIconBitmaps := TList.Create();

  inherited Create(ALauncher, DOCK_ICON_SIZE + (2 * DOCK_PADDING), DOCK_HEIGHT);

  if FtIsLibLoaded() then
    FLastDarkMode := FtApp().DarkMode
  else
    FLastDarkMode := ShellSettings().DarkMode;

  if not Assigned(ShellSettings().OnDarkModeChange) then
    ShellSettings().OnDarkModeChange := @HandleSettingsDarkModeChange;
  ShellSettings().OnDockSettingsChange := @HandleSettingsDockChange;
end;

destructor TShellDock.Destroy();
var
  i: Integer;
begin
  DestroyTriggerWindow();
  if ShellSettings().OnDarkModeChange = @HandleSettingsDarkModeChange then
    ShellSettings().OnDarkModeChange := nil;
  if ShellSettings().OnDockSettingsChange = @HandleSettingsDockChange then
    ShellSettings().OnDockSettingsChange := nil;

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

procedure TShellDock.ApplyThemeStyle();
var
  isDark: Boolean;
begin
  if FWindow = nil then Exit;

  if FtIsLibLoaded() then
    isDark := FtApp().DarkMode
  else
    isDark := ShellSettings().DarkMode;

  FLastDarkMode := isDark;

  if isDark then
  begin
    FWindow.StyleClass := 'dock dark';
    FWindow.Style := DOCK_PLATE_CSS_DARK;
    FWindow.BackgroundOpacity := 0.82;
  end
  else
  begin
    FWindow.StyleClass := 'dock light';
    FWindow.Style := DOCK_PLATE_CSS_LIGHT;
    FWindow.BackgroundOpacity := 0.85;
  end;

  FWindow.Invalidate();

  if Assigned(FPreview) and FPreview.IsOpen() then
    FPreview.ApplyThemeStyle();
end;

procedure TShellDock.HandleSettingsDarkModeChange(Sender: TObject);
begin
  if FtIsLibLoaded() then
    FtApp().DarkMode := ShellSettings().DarkMode;
  ApplyThemeStyle();
end;

procedure TShellDock.SetupWindow();
begin
  inherited SetupWindow();
  if FWindow = nil then Exit;
  ApplyThemeStyle();
  FWindow.OnMouseDown := @HandleDockMouseDown;

  if Assigned(ft_style_append_css_string) then
    ft_style_append_css_string(PChar(DOCK_ICON_CSS));

  SetupTriggerWindow();
  FWindow.Invalidate();
end;

function TShellDock.IsVertical(): Boolean;
begin
  Result := SameText(ShellSettings().DockPosition, 'Left') or
            SameText(ShellSettings().DockPosition, 'Right');
end;

function TShellDock.ScreenWidthHint(): Integer;
begin
  if FtIsLibLoaded() and Assigned(ft_screen_get_width) then
    Result := FtApp().ScreenWidth
  else
    Result := 1920;
end;

function TShellDock.ScreenHeightHint(): Integer;
begin
  if FtIsLibLoaded() and Assigned(ft_screen_get_height) then
    Result := FtApp().ScreenHeight
  else
    Result := 1080;
end;

function TShellDock.DesiredHeight(): Integer;
var
  n: Integer;
begin
  if not IsVertical() then
    Exit(DOCK_HEIGHT);

  n := EntryCount();
  if n < 1 then
    Exit(FIconSize + (2 * DOCK_PADDING));
  Result := Min((2 * DOCK_PADDING) + (n * FIconSize) + ((n - 1) * DOCK_GAP),
                FMaxDockHeight);
end;

function TShellDock.PanelHeight(): Integer;
begin
  if IsVertical() then
    Result := FPanelHeight
  else
    Result := DOCK_HEIGHT;
end;

function TShellDock.DesiredWidth(): Integer;
var
  n: Integer;
begin
  if IsVertical() then
    Exit(FIconSize + (2 * DOCK_PADDING));

  n := EntryCount();
  if n < 1 then
    Exit(FIconSize + (2 * DOCK_PADDING));
  Result := Min((2 * DOCK_PADDING) + (n * FIconSize) + ((n - 1) * DOCK_GAP),
                FMaxDockWidth);
end;

function TShellDock.PanelWidth(): Integer;
begin
  if IsVertical() then
    Result := FIconSize + (2 * DOCK_PADDING)
  else
    Result := FPanelWidth;
end;

function TShellDock.PanelX(): Integer;
var
  posStr: string;
  m: Integer;
begin
  posStr := ShellSettings().DockPosition;
  m := ShellSettings().DockMargin;
  if m < 0 then m := 0;

  if SameText(posStr, 'Left') then
    Result := m
  else if SameText(posStr, 'Right') then
    Result := ScreenWidthHint() - PanelWidth() - m
  else
    Result := (ScreenWidthHint() - PanelWidth()) div 2;
end;

function TShellDock.PanelY(): Integer;
var
  posStr: string;
  m, availH, topBarH: Integer;
begin
  posStr := ShellSettings().DockPosition;
  m := ShellSettings().DockMargin;
  if m < 0 then m := 0;

  if SameText(posStr, 'Left') or SameText(posStr, 'Right') then
  begin
    topBarH := 38;
    availH := ScreenHeightHint() - topBarH;
    Result := topBarH + ((availH - PanelHeight()) div 2);
    if Result < topBarH then
      Result := topBarH;
  end
  else
  begin
    if FtIsLibLoaded() and Assigned(ft_screen_get_height) then
      Result := FtApp().ScreenHeight - DOCK_HEIGHT - m
    else
      Result := 1080 - DOCK_HEIGHT - m;
  end;
end;

function TShellDock.ComputeStrutBottom(): Integer;
var
  m: Integer;
begin
  if ShellSettings().DockAutoHide or IsVertical() then
    Exit(0);
  m := ShellSettings().DockMargin;
  if m < 0 then m := 0;
  Result := DOCK_HEIGHT + m + DOCK_TOP_MARGIN;
end;

function TShellDock.ComputeStrutLeft(): Integer;
var
  m: Integer;
begin
  if ShellSettings().DockAutoHide or not SameText(ShellSettings().DockPosition, 'Left') then
    Exit(0);
  m := ShellSettings().DockMargin;
  if m < 0 then m := 0;
  Result := PanelWidth() + m + DOCK_TOP_MARGIN;
end;

function TShellDock.ComputeStrutRight(): Integer;
var
  m: Integer;
begin
  if ShellSettings().DockAutoHide or not SameText(ShellSettings().DockPosition, 'Right') then
    Exit(0);
  m := ShellSettings().DockMargin;
  if m < 0 then m := 0;
  Result := PanelWidth() + m + DOCK_TOP_MARGIN;
end;

procedure TShellDock.UpdateStruts();
begin
  if (FWindow = nil) or not FtIsLibLoaded() then Exit;
  if ShellSettings().DockAutoHide then
    FWindow.SetStrutPartial(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
  else
    inherited UpdateStruts();
end;

function TShellDock.IsAnimating(): Boolean;
begin
  Result := (FHideState = dhsShowing) or (FHideState = dhsHiding);
end;

function TShellDock.IsWindowOverlapping(): Boolean;
var
  activeWin: Cardinal;
  geomReply: Pxcb_get_geometry_reply_t;
  cookie: xcb_get_geometry_cookie_t;
  transReply: Pxcb_translate_coordinates_reply_t;
  transCookie: xcb_translate_coordinates_cookie_t;
  propCookie: xcb_get_property_cookie_t;
  propReply: Pxcb_get_property_reply_t;
  wx, wy, ww, wh: Integer;
  dx, dy, dw, dh: Integer;
  stateLen, i: Integer;
  pStates: PCardinal;
begin
  Result := False;
  if FConn = nil then Exit;

  activeWin := QueryActiveWindow();
  if (activeWin = 0) or (activeWin = FRootWindow) or
     ((FWindow <> nil) and (activeWin = Cardinal(PtrUInt(FWindow.NativeHandle)))) then
    Exit(False);

  // Check if active window is maximized via _NET_WM_STATE
  if FAtomNetWmState <> 0 then
  begin
    propCookie := xcb_get_property(FConn, 0, activeWin, FAtomNetWmState, XCB_ATOM_ATOM, 0, 32);
    propReply := xcb_get_property_reply(FConn, propCookie, nil);
    if propReply <> nil then
    begin
      try
        stateLen := xcb_get_property_value_length(propReply) div SizeOf(Cardinal);
        pStates := PCardinal(xcb_get_property_value(propReply));
        for i := 0 to stateLen - 1 do
        begin
          if (pStates^ = FAtomNetWmStateMaxVert) or (pStates^ = FAtomNetWmStateMaxHorz) then
          begin
            Exit(True);
          end;
          Inc(pStates);
        end;
      finally
        c_free(propReply);
      end;
    end;
  end;

  // Query window geometry
  cookie := xcb_get_geometry(FConn, activeWin);
  geomReply := xcb_get_geometry_reply(FConn, cookie, nil);
  if geomReply = nil then Exit(False);

  try
    ww := geomReply^.width;
    wh := geomReply^.height;
  finally
    c_free(geomReply);
  end;

  transCookie := xcb_translate_coordinates(FConn, activeWin, FRootWindow, 0, 0);
  transReply := xcb_translate_coordinates_reply(FConn, transCookie, nil);
  if transReply = nil then Exit(False);

  try
    wx := transReply^.dst_x;
    wy := transReply^.dst_y;
  finally
    c_free(transReply);
  end;

  dx := PanelX();
  dy := PanelY();
  dw := PanelWidth();
  dh := PanelHeight();

  // Rectangle intersection
  Result := not ((wx + ww <= dx) or (dx + dw <= wx) or (wy + wh <= dy) or (dy + dh <= wy));
end;

function TShellDock.IsPointerInsideDock(): Boolean;
var
  cookie: xcb_query_pointer_cookie_t;
  reply: Pxcb_query_pointer_reply_t;
  px, py: Integer;
  dx, dy, dw, dh: Integer;
begin
  Result := False;
  if (FConn = nil) or (FRootWindow = 0) or (FWindow = nil) then Exit;

  cookie := xcb_query_pointer(FConn, FRootWindow);
  reply := xcb_query_pointer_reply(FConn, cookie, nil);
  if reply = nil then Exit;

  try
    px := reply^.root_x;
    py := reply^.root_y;
  finally
    c_free(reply);
  end;

  dx := FWindow.X;
  dy := FWindow.Y;
  dw := PanelWidth();
  dh := PanelHeight();

  Result := (px >= dx) and (px < dx + dw) and (py >= dy) and (py < dy + dh);
end;

function TShellDock.IsPointerAtTriggerEdge(): Boolean;
var
  cookie: xcb_query_pointer_cookie_t;
  reply: Pxcb_query_pointer_reply_t;
  px, py: Integer;
  scrW, scrH: Integer;
  posStr: string;
begin
  Result := False;
  if (FConn = nil) or (FRootWindow = 0) then Exit;

  cookie := xcb_query_pointer(FConn, FRootWindow);
  reply := xcb_query_pointer_reply(FConn, cookie, nil);
  if reply = nil then Exit;

  try
    px := reply^.root_x;
    py := reply^.root_y;
  finally
    c_free(reply);
  end;

  scrW := ScreenWidthHint();
  scrH := ScreenHeightHint();
  posStr := ShellSettings().DockPosition;

  if SameText(posStr, 'Left') then
    Result := (px <= 4) and (py >= PanelY()) and (py <= PanelY() + PanelHeight())
  else if SameText(posStr, 'Right') then
    Result := (px >= scrW - 4) and (py >= PanelY()) and (py <= PanelY() + PanelHeight())
  else
    Result := (py >= scrH - 4) and (px >= PanelX()) and (px <= PanelX() + PanelWidth());
end;

procedure TShellDock.StartShow();
begin
  if FHideState = dhsVisible then Exit;
  FHideState := dhsShowing;
  FAnimTarget := 1.0;
  FAnimStart := GetTickCount64() - Round(FAnimProgress * 150.0);
end;

procedure TShellDock.StartHide();
begin
  if FHideState = dhsHidden then Exit;
  FHideState := dhsHiding;
  FAnimTarget := 0.0;
  FAnimStart := GetTickCount64() - Round((1.0 - FAnimProgress) * 150.0);
end;

procedure TShellDock.ShowImmediate();
begin
  FHideState := dhsVisible;
  FAnimProgress := 1.0;
  FAnimTarget := 1.0;
  if FWindow <> nil then
    FWindow.SetPosition(PanelX(), PanelY());
end;

procedure TShellDock.StepAnimation();
var
  nowMs: QWord;
  elapsed: Double;
  normX, normY, hidX, hidY, curX, curY: Integer;
begin
  if FWindow = nil then Exit;

  nowMs := GetTickCount64();
  elapsed := (nowMs - FAnimStart) / 150.0;
  if elapsed >= 1.0 then
  begin
    FAnimProgress := FAnimTarget;
    if FAnimTarget = 1.0 then
      FHideState := dhsVisible
    else
      FHideState := dhsHidden;
  end
  else
  begin
    if FAnimTarget = 1.0 then
      FAnimProgress := elapsed
    else
      FAnimProgress := 1.0 - elapsed;
  end;

  normX := PanelX();
  normY := PanelY();

  if SameText(ShellSettings().DockPosition, 'Left') then
  begin
    hidX := -PanelWidth();
    curX := Round(hidX + (normX - hidX) * FAnimProgress);
    FWindow.SetPosition(curX, normY);
  end
  else if SameText(ShellSettings().DockPosition, 'Right') then
  begin
    hidX := ScreenWidthHint();
    curX := Round(hidX + (normX - hidX) * FAnimProgress);
    FWindow.SetPosition(curX, normY);
  end
  else
  begin
    hidY := ScreenHeightHint();
    curY := Round(hidY + (normY - hidY) * FAnimProgress);
    FWindow.SetPosition(normX, curY);
  end;
end;

procedure TShellDock.DestroyTriggerWindow();
begin
  if (FConn <> nil) and (FTriggerWin <> 0) then
  begin
    xcb_destroy_window(FConn, FTriggerWin);
    xcb_flush(FConn);
    FTriggerWin := 0;
  end;
end;

procedure TShellDock.SetupTriggerWindow();
var
  wid: xcb_window_t;
  tx, ty, tw, th: Integer;
  valMask: Cardinal;
  valList: array[0..3] of Cardinal;
  scrW, scrH: Integer;
  posStr: string;
begin
  if (FConn = nil) or (FRootWindow = 0) then Exit;
  if not ShellSettings().DockAutoHide then
  begin
    DestroyTriggerWindow();
    Exit;
  end;

  scrW := ScreenWidthHint();
  scrH := ScreenHeightHint();
  posStr := ShellSettings().DockPosition;

  if SameText(posStr, 'Left') then
  begin
    tx := 0;
    ty := PanelY();
    tw := 2;
    th := PanelHeight();
  end
  else if SameText(posStr, 'Right') then
  begin
    tx := scrW - 2;
    ty := PanelY();
    tw := 2;
    th := PanelHeight();
  end
  else
  begin
    tx := PanelX();
    ty := scrH - 2;
    tw := PanelWidth();
    th := 2;
  end;

  if FTriggerWin = 0 then
  begin
    wid := xcb_generate_id(FConn);
    valMask := XCB_CW_OVERRIDE_REDIRECT or XCB_CW_EVENT_MASK;
    valList[0] := 1;
    valList[1] := XCB_EVENT_MASK_ENTER_WINDOW;

    xcb_create_window(FConn, 0, wid, FRootWindow,
                      tx, ty, tw, th, 0,
                      XCB_WINDOW_CLASS_INPUT_ONLY,
                      0, valMask, @valList[0]);
    xcb_map_window(FConn, wid);
    xcb_flush(FConn);
    FTriggerWin := wid;
  end
  else
  begin
    valMask := XCB_CONFIG_WINDOW_X or XCB_CONFIG_WINDOW_Y or
               XCB_CONFIG_WINDOW_WIDTH or XCB_CONFIG_WINDOW_HEIGHT;
    valList[0] := tx;
    valList[1] := ty;
    valList[2] := tw;
    valList[3] := th;
    xcb_configure_window(FConn, FTriggerWin, valMask, @valList[0]);
    xcb_flush(FConn);
  end;
end;

procedure TShellDock.HandleSettingsDockChange(Sender: TObject);
var
  needRelayout: Boolean;
begin
  needRelayout := False;

  if (ShellSettings().DockIconSize >= 24) and (ShellSettings().DockIconSize <= 128) then
  begin
    if FIconSize <> ShellSettings().DockIconSize then
    begin
      FIconSize := ShellSettings().DockIconSize;
      needRelayout := True;
    end;
  end;

  if FLastDockPosition <> ShellSettings().DockPosition then
  begin
    FLastDockPosition := ShellSettings().DockPosition;
    needRelayout := True;
  end;

  if FLastDockMargin <> ShellSettings().DockMargin then
  begin
    FLastDockMargin := ShellSettings().DockMargin;
    needRelayout := True;
  end;

  if FLastDockAutoHide <> ShellSettings().DockAutoHide then
  begin
    FLastDockAutoHide := ShellSettings().DockAutoHide;
    UpdateStruts();
    SetupTriggerWindow();
    if not FLastDockAutoHide then
      ShowImmediate();
  end;

  if needRelayout then
    LayoutButtons()
  else
    UpdateStruts();
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
    FEntries[i].MenuMinimize := nil;
    FEntries[i].MenuMaximize := nil;
    FEntries[i].MenuClose := nil;
    FEntries[i].MenuWindow := 0;
    FEntries[i].Windows := nil;
  end;
  FLayoutIconSize := FIconSize;
  FLayoutIconX := 0;
  // Stays set: the synthetic list is only replaced by another DebugPopulateEntries
  // call, so scroll passes during a test do not rebuild it from (empty) live windows.
  FSkipEntryRebuild := True;
  LayoutButtons();
end;

procedure TShellDock.DebugSetEntryWindows(AIndex: Integer; const AWins: array of Cardinal);
var
  i: Integer;
begin
  if (AIndex < 0) or (AIndex >= Length(FEntries)) then Exit;
  SetLength(FEntries[AIndex].Windows, Length(AWins));
  for i := 0 to High(AWins) do
    FEntries[AIndex].Windows[i] := AWins[i];
  UpdateEntryMenu(AIndex);
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

function TShellDock.EntryMenu(AIndex: Integer): TFtPopupMenu;
begin
  Result := nil;
  if (AIndex >= 0) and (AIndex < Length(FEntries)) then
    Result := FEntries[AIndex].Menu;
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
    FEntries[j].MenuMinimize := nil;
    FEntries[j].MenuMaximize := nil;
    FEntries[j].MenuClose := nil;
    FEntries[j].MenuWindow := 0;
  end;

  winCount := TaskCount;

  for i := 0 to winCount - 1 do
  begin
    win := GetTaskWindow(i);
    if win = 0 then Continue;

    QueryWindowClass(win, resName, resClass);
    key := FDockApps.AppKeyForWindow(resName, resClass);
    if key = '' then
      key := 'window-' + IntToStr(win);

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
      FEntries[j].MenuMinimize := nil;
      FEntries[j].MenuMaximize := nil;
      FEntries[j].MenuClose := nil;
      FEntries[j].MenuWindow := 0;
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
  focused, isDark: Boolean;
begin
  if (ACanvas = nil) or (GActiveDock = nil) then Exit;
  idx := PtrInt(AUserData);
  if (idx < 0) or (idx >= GActiveDock.EntryCount) then Exit;
  if GActiveDock.EntryWindowCountAt(idx) = 0 then Exit;

  focused := GActiveDock.EntryFocused(idx);
  // AX/AY are the button's position in WINDOW coordinates, not offsets inside it.
  // The dot is placed relative to the button's own rectangle.
  if SameText(ShellSettings().DockPosition, 'Left') then
  begin
    cxp := AX - 1.0;
    cyp := AY + (AH / 2);
  end
  else if SameText(ShellSettings().DockPosition, 'Right') then
  begin
    cxp := (AX + AW) + 1.0;
    cyp := AY + (AH / 2);
  end
  else
  begin
    cxp := AX + (AW / 2);
    cyp := (AY + AH) + 1.0;
  end;
  radius := DOT_SIZE / 2;

  isDark := True;
  if FtIsLibLoaded() then
    isDark := FtApp().DarkMode
  else
    isDark := ShellSettings().DarkMode;

  cv := TFtCanvas.Create(ACanvas);
  try
    if isDark then
    begin
      if focused then
        cv.DrawCircle(cxp, cyp, radius, 0.95, 0.95, 0.98, 1.0)
      else
        cv.DrawCircle(cxp, cyp, radius - 0.5, 0.55, 0.58, 0.64, 0.85);
    end
    else
    begin
      if focused then
        cv.DrawCircle(cxp, cyp, radius, 0.15, 0.18, 0.23, 1.0)
      else
        cv.DrawCircle(cxp, cyp, radius - 0.5, 0.48, 0.52, 0.58, 0.80);
    end;
  finally
    cv.Free();
  end;
end;

// ---------------------------------------------------------------- layout

procedure TShellDock.LayoutButtons();
var
  i, k, iconX, iconY, x, y, wantW, wantH, btnSize, gap, total: Integer;
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
  wantH := DesiredHeight();
  if (wantW <> FPanelWidth) or (wantH <> FPanelHeight) then
    ResizeWindow(wantW, wantH, PanelX());

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

  if IsVertical() then
  begin
    FContentHeight := total;
    FMaxScroll := total + (2 * DOCK_PADDING) - PanelHeight();
    if FMaxScroll < 0 then
      FMaxScroll := 0;
    if FScrollOffset > FMaxScroll then
      FScrollOffset := FMaxScroll;
    if FScrollOffset < 0 then
      FScrollOffset := 0;

    iconX := (PanelWidth() - btnSize) div 2;
    if FMaxScroll = 0 then
      iconY := (PanelHeight() - total) div 2
    else
      iconY := DOCK_PADDING - FScrollOffset;
    if (FMaxScroll = 0) and (iconY < DOCK_PADDING) then
      iconY := DOCK_PADDING;

    FLayoutIconSize := btnSize;
    FLayoutIconX := iconX;
  end
  else
  begin
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

    iconY := (DOCK_HEIGHT - btnSize) div 2;
    FLayoutIconSize := btnSize;
    FLayoutIconX := iconX;
  end;

  for i := 0 to High(FEntries) do
  begin
    if IsVertical() then
    begin
      x := iconX;
      y := iconY + (i * (btnSize + gap));
    end
    else
    begin
      x := iconX + (i * (btnSize + gap));
      y := iconY;
    end;

    if FEntries[i].Button = nil then
    begin
      FEntries[i].Button := TFtButton.Create(FWindow, x, y, btnSize, btnSize,
                                             FEntries[i].Title);
      FEntries[i].Button.IsToggle := False;
      FEntries[i].Button.Flat := True;
      FEntries[i].Button.StyleClass := DOCK_ICON_STYLE_CLASS;
      // A tooltip per icon is redundant: the icon is the label.
      FEntries[i].Button.ShowHint := False;
      FEntries[i].Button.IconPosition := ftipOnly;
      FEntries[i].Button.OnClick := @HandleEntryClick;
    end
    else
      FEntries[i].Button.SetBounds(x, y, btnSize, btnSize);

    FEntries[i].Button.Tag := i;
    FEntries[i].Button.Caption := FEntries[i].Title;

    UpdateEntryMenu(i);

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

    for k := 0 to High(FEntries[i].Windows) do
      SetWindowIconGeometry(FEntries[i].Windows[k], PanelX() + x, PanelY() + y, btnSize, btnSize);

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
      if IsVertical() then
      begin
        if y < DOCK_PADDING then
          opacity := 0.15 + (0.85 * ((y + btnSize - DOCK_PADDING) / btnSize))
        else if y + btnSize > PanelHeight() - DOCK_PADDING then
          opacity := 0.15 + (0.85 * (((PanelHeight() - DOCK_PADDING) - y) / btnSize));
      end
      else
      begin
        if x < DOCK_PADDING then
          opacity := 0.15 + (0.85 * ((x + btnSize - DOCK_PADDING) / btnSize))
        else if x + btnSize > PanelWidth() - DOCK_PADDING then
          opacity := 0.15 + (0.85 * (((PanelWidth() - DOCK_PADDING) - x) / btnSize));
      end;
      if opacity < 0.15 then opacity := 0.15;
      if opacity > 1.0 then opacity := 1.0;
    end;
    FEntries[i].Button.Opacity := opacity;
  end;

  SetupTriggerWindow();
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

  Sender.Toggled := False;

  // Several windows: let the user pick one. One window: activate or minimize. None: launch.
  if Length(FEntries[idx].Windows) > 1 then
    ShowPreview(FEntries[idx].AppKey)
  else
    ActivateOrLaunch(FEntries[idx].AppKey);
end;

procedure TShellDock.DebugClickEntry(AIndex: Integer);
begin
  if (AIndex < 0) or (AIndex >= Length(FEntries)) then Exit;
  if FEntries[AIndex].Button <> nil then
    HandleEntryClick(FEntries[AIndex].Button)
  else if Length(FEntries[AIndex].Windows) > 1 then
    ShowPreview(FEntries[AIndex].AppKey)
  else
    ActivateOrLaunch(FEntries[AIndex].AppKey);
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
  if (Length(FEntries[idx].Windows) = 1) and (win = QueryActiveWindow()) then
    MinimizeWindow(win)
  else
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

  if (FPixmaps = nil) and (FConn <> nil) then
    FPixmaps := TWindowPixmapStore.Create(FConn);

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
  UpdateEntryMenuStates();
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


procedure TShellDock.UpdateEntryMenu(AIndex: Integer);
var
  win: Cardinal;
  hasDesktop: Boolean;
begin
  if (AIndex < 0) or (AIndex >= Length(FEntries)) then Exit;

  if FEntries[AIndex].Menu = nil then
    FEntries[AIndex].Menu := TFtPopupMenu.Create(FWindow);

  if FEntries[AIndex].Menu = nil then Exit;

  hasDesktop := FDockApps.HasDesktopEntry(FEntries[AIndex].AppKey);

  if Length(FEntries[AIndex].Windows) = 1 then
  begin
    win := FEntries[AIndex].Windows[0];

    // If already built for this window, update dynamic captions
    if (FEntries[AIndex].MenuWindow = win) and (FEntries[AIndex].MenuMinimize <> nil) then
    begin
      if IsWindowMinimized(win) then
        FEntries[AIndex].MenuMinimize.Caption := 'Restore'
      else
        FEntries[AIndex].MenuMinimize.Caption := 'Minimize';

      if Assigned(FEntries[AIndex].MenuMaximize) then
      begin
        if IsWindowMaximized(win) then
          FEntries[AIndex].MenuMaximize.Caption := 'Restore'
        else
          FEntries[AIndex].MenuMaximize.Caption := 'Maximize';
      end;

      if Assigned(FEntries[AIndex].MenuPin) then
      begin
        FEntries[AIndex].MenuPin.Tag := AIndex;
        if FEntries[AIndex].Pinned and hasDesktop then
          FEntries[AIndex].MenuPin.Caption := 'Unpin from dock'
        else if hasDesktop then
          FEntries[AIndex].MenuPin.Caption := 'Pin to dock';
      end;
    end
    else
    begin
      // Full rebuild for single window: Minimize, Maximize, separator, Close, separator, Pin/Unpin
      FEntries[AIndex].Menu.Clear();

      AddWindowActions(FEntries[AIndex].Menu, win);

      FEntries[AIndex].MenuMinimize := FindWindowAction(FEntries[AIndex].Menu, 'Minimize');
      if (FEntries[AIndex].MenuMinimize <> nil) and IsWindowMinimized(win) then
        FEntries[AIndex].MenuMinimize.Caption := 'Restore';

      FEntries[AIndex].MenuMaximize := FindWindowAction(FEntries[AIndex].Menu, 'Maximize');
      if (FEntries[AIndex].MenuMaximize <> nil) and IsWindowMaximized(win) then
        FEntries[AIndex].MenuMaximize.Caption := 'Restore';

      FEntries[AIndex].MenuClose := FindWindowAction(FEntries[AIndex].Menu, 'Close');

      if hasDesktop then
      begin
        FEntries[AIndex].Menu.AddSeparator();
        if FEntries[AIndex].Pinned then
          FEntries[AIndex].MenuPin := FEntries[AIndex].Menu.AddItem('Unpin from dock', @HandleEntryMenuPin)
        else
          FEntries[AIndex].MenuPin := FEntries[AIndex].Menu.AddItem('Pin to dock', @HandleEntryMenuPin);
        if Assigned(FEntries[AIndex].MenuPin) then
          FEntries[AIndex].MenuPin.Tag := AIndex;
      end
      else
        FEntries[AIndex].MenuPin := nil;

      FEntries[AIndex].MenuWindow := win;
    end;
  end
  else
  begin
    // 0 or >1 windows: no window-specific actions on dock icon
    if (FEntries[AIndex].MenuWindow <> 0) or (FEntries[AIndex].MenuMinimize <> nil) then
    begin
      FEntries[AIndex].Menu.Clear();
      FEntries[AIndex].MenuMinimize := nil;
      FEntries[AIndex].MenuMaximize := nil;
      FEntries[AIndex].MenuClose := nil;
      FEntries[AIndex].MenuPin := nil;

      if hasDesktop then
      begin
        if FEntries[AIndex].Pinned then
          FEntries[AIndex].MenuPin := FEntries[AIndex].Menu.AddItem('Unpin from dock', @HandleEntryMenuPin)
        else
          FEntries[AIndex].MenuPin := FEntries[AIndex].Menu.AddItem('Pin to dock', @HandleEntryMenuPin);
        if Assigned(FEntries[AIndex].MenuPin) then
          FEntries[AIndex].MenuPin.Tag := AIndex;
      end;

      FEntries[AIndex].MenuWindow := 0;
    end
    else if Assigned(FEntries[AIndex].MenuPin) then
    begin
      FEntries[AIndex].MenuPin.Tag := AIndex;
      if FEntries[AIndex].Pinned and hasDesktop then
        FEntries[AIndex].MenuPin.Caption := 'Unpin from dock'
      else if hasDesktop then
        FEntries[AIndex].MenuPin.Caption := 'Pin to dock';
    end
    else if hasDesktop then
    begin
      if FEntries[AIndex].Pinned then
        FEntries[AIndex].MenuPin := FEntries[AIndex].Menu.AddItem('Unpin from dock', @HandleEntryMenuPin)
      else
        FEntries[AIndex].MenuPin := FEntries[AIndex].Menu.AddItem('Pin to dock', @HandleEntryMenuPin);
      if Assigned(FEntries[AIndex].MenuPin) then
        FEntries[AIndex].MenuPin.Tag := AIndex;
    end;
  end;

  if Assigned(FEntries[AIndex].Button) then
    FEntries[AIndex].Button.ContextMenuHandle := FEntries[AIndex].Menu.Handle;
end;

procedure TShellDock.UpdateEntryMenuStates();
var
  i: Integer;
begin
  for i := 0 to High(FEntries) do
    UpdateEntryMenu(i);
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

  UpdateEntryMenu(idx);
  FWindow.Invalidate();
end;

procedure TShellDock.RefreshDock();
begin
  if FWindow = nil then Exit;
  LayoutButtons();
end;

procedure TShellDock.Tick();
var
  curDark: Boolean;
begin
  inherited Tick();

  if FtIsLibLoaded() then
    curDark := FtApp().DarkMode
  else
    curDark := ShellSettings().DarkMode;

  if curDark <> FLastDarkMode then
  begin
    FLastDarkMode := curDark;
    ApplyThemeStyle();
  end;

  // Ensure settings updates are detected if dock is running standalone
  ShellSettings().CheckReload();

  if ShellSettings().DockAutoHide then
  begin
    if IsPointerInsideDock() or IsPointerAtTriggerEdge() then
    begin
      if FHideState in [dhsHidden, dhsHiding] then
        StartShow();
    end
    else
    begin
      if IsWindowOverlapping() then
      begin
        if FHideState in [dhsVisible, dhsShowing] then
          StartHide();
      end
      else
      begin
        if FHideState in [dhsHidden, dhsHiding] then
          StartShow();
      end;
    end;

    if IsAnimating() then
      StepAnimation();
  end
  else if FHideState <> dhsVisible then
    ShowImmediate();

  RefreshPixmaps();
  SyncPreview();
  UpdateEntryMenuStates();

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
