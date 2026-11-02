{ Unit ShellSama.Dock — macOS-style dock for Samarinda DE }

unit ShellSama.Dock;

// The dock is the bottom panel with a different presentation: one large icon per
// task, centred, no captions, on a floating rounded plate. Everything else -- the
// client list, icons, EWMH state, window actions, context menus -- is the taskbar's
// and is inherited, so the two cannot drift apart.
//
// It deliberately does not use the full screen width. A dock that spans the screen
// is a taskbar; the point of this mode is the inset plate.

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils, Math,
  Floria.XCB,
  ftpas.api, ftpas.types, ftpas,
  ShellSama.DesktopApps,
  ShellSama.Launcher,
  ShellSama.BottomPanel;

type
  TShellDock = class(TShellBottomPanel)
  private
    FIconSize    : Integer;
    FMaxDockWidth: Integer;
    FRebuilding   : Boolean;
  protected
    function WindowTitle(): string; override;
    procedure SetupWindow(); override;
    procedure LayoutButtons(); override;
    // Width the plate needs for its current contents.
    function DesiredWidth(): Integer;
    function ScreenWidthHint(): Integer;
  public
    constructor Create(ALauncher: TShellLauncher = nil);
    destructor Destroy(); override;

    function PanelX(): Integer; override;
    function PanelWidth(): Integer; override;
    function PanelHeight(): Integer; override;
    function PanelY(): Integer; override;

    // Icon edge length, and the plate's width cap, both exposed for tests.
    property IconSize    : Integer read FIconSize;
    property MaxDockWidth: Integer read FMaxDockWidth;
  end;

implementation

var
  GShellDockInstance: TShellDock = nil;

const
  DOCK_ICON_SIZE      = 48;
  DOCK_PADDING        = 10;
  DOCK_GAP            = 6;
  DOCK_MAX_WIDTH      = 720;
  DOCK_HEIGHT         = 78;
  DOCK_BOTTOM_MARGIN  = 8;

constructor TShellDock.Create(ALauncher: TShellLauncher);
begin
  // Set before the inherited constructor, not after. That constructor creates the
  // window and lays the buttons out, which calls DesiredWidth(); with FIconSize
  // still zero it computed a zero width, decided the plate had to be rebuilt, and
  // rebuilt the window from inside its own creation.
  FIconSize := DOCK_ICON_SIZE;
  FMaxDockWidth := DOCK_MAX_WIDTH;

  // The width for zero tasks is the empty plate. The toolkit fixes a window's size
  // at creation, so the geometry has to be decided here.
  inherited Create(ALauncher, DOCK_ICON_SIZE + (2 * DOCK_PADDING), DOCK_HEIGHT);
  GShellDockInstance := Self;
end;

function TShellDock.WindowTitle(): string;
begin
  Result := 'shellsama-dock';
end;

procedure TShellDock.SetupWindow();
const
  // Only declarations the window paint path honours: a background colour and a
  // border radius. The radius leaves the corners unpainted, so they show the
  // desktop through them -- that is the whole of the rounded look, and it needs a
  // compositor. No border: window borders are not drawn by the toolkit.
  DOCK_PLATE_CSS =
    'background-color: rgba(24, 24, 32, 0.82);' +
    'border-radius: 18px;';
begin
  inherited SetupWindow();
  if FWindow = nil then Exit;

  // A dock plate is dark and translucent, unlike the taskbar strip, so dark app
  // icons stay readable. Set here rather than in the constructor because the window
  // is recreated when the plate resizes.
  FWindow.Style := DOCK_PLATE_CSS;
  FWindow.BackgroundOpacity := 0.82;
  FWindow.Invalidate();
end;

function TShellDock.ScreenWidthHint(): Integer;
begin
  if FtIsLibLoaded() and Assigned(ft_screen_get_width) then
    Result := FtApp().ScreenWidth
  else
    Result := 1920;
end;

function TShellDock.DesiredWidth(): Integer;
var
  n, wanted: Integer;
begin
  n := TaskCount;
  if n < 1 then
    Exit(FIconSize + (2 * DOCK_PADDING));

  wanted := (2 * DOCK_PADDING) + (n * FIconSize) + ((n - 1) * DOCK_GAP);
  Result := Min(wanted, FMaxDockWidth);
end;

destructor TShellDock.Destroy();
begin
  if GShellDockInstance = Self then
    GShellDockInstance := nil;
  inherited Destroy();
end;

function TShellDock.PanelHeight(): Integer;
begin
  Result := DOCK_HEIGHT;
end;

function TShellDock.PanelWidth(): Integer;
begin
  // The plate follows its contents, so the width is whatever the window was last
  // built at. LayoutButtons rebuilds the window when that number changes.
  Result := FPanelWidth;
end;

function TShellDock.PanelX(): Integer;
begin
  // Centred. The plate is symmetric, so the strut-adjusted work area is not needed.
  Result := (ScreenWidthHint() - PanelWidth()) div 2;
end;

function TShellDock.PanelY(): Integer;
var
  sh: Integer;
begin
  if FtIsLibLoaded() and Assigned(ft_screen_get_height) then
    sh := FtApp().ScreenHeight
  else
    sh := 1080;
  Result := sh - DOCK_HEIGHT - DOCK_BOTTOM_MARGIN;
end;

procedure TShellDock.LayoutButtons();
var
  count, i, x, iconX, iconY, btnSize, wantW: Integer;
  dispTitle: string;
  iconBmp: TFtBitmap;
begin
  if FWindow = nil then Exit;

  count := TaskCount;

  // The plate is as wide as its contents. Resize in place rather than recreating the
  // window: a destroyed window drops its strut, and every maximized client on the
  // desktop then expands into the gap and snaps back when the replacement maps.
  // Resizing from inside the layout pass would re-enter (SetupWindow calls
  // RefreshTasks, which calls this), so the resize is guarded and re-run once.
  wantW := DesiredWidth();
  if wantW <> FPanelWidth then
  begin
    if not FRebuilding then
    begin
      FRebuilding := True;
      try
        ResizeWindow(wantW, DOCK_HEIGHT, (ScreenWidthHint() - wantW) div 2);
      finally
        FRebuilding := False;
      end;
    end;
    Exit;
  end;

  if count = 0 then
  begin
    FWindow.Invalidate();
    Exit;
  end;

  btnSize := FIconSize;
  iconY := (DOCK_HEIGHT - btnSize) div 2;

  // Icons are centred in the plate when the cap bites and the row would otherwise
  // be left-aligned with slack on the right.
  iconX := (PanelWidth() - (count * btnSize) - ((count - 1) * DOCK_GAP)) div 2;
  if iconX < DOCK_PADDING then
    iconX := DOCK_PADDING;

  for i := 0 to count - 1 do
  begin
    x := iconX + (i * (btnSize + DOCK_GAP));

    // The caption is still set, but IconPosition is ftipOnly so it is not drawn.
    // It stays because the button's accessible name and the context menu's
    // association both come from it, and a dock icon with no title is unhelpful in
    // a screen reader or a tooltip.
    dispTitle := FTasks[i].Title;

    if FTasks[i].Button = nil then
    begin
      FTasks[i].Button := TFtButton.Create(FWindow, x, iconY, btnSize, btnSize, dispTitle);
      FTasks[i].Button.IsToggle := True;
      FTasks[i].Button.Flat := True;
      FTasks[i].Button.CornerRadius := 10.0;
      FTasks[i].Button.IconPosition := ftipOnly;
      FTasks[i].Button.Tag := PtrInt(FTasks[i].Window);
      FTasks[i].Button.OnClick := @HandleTaskButtonClick;
    end
    else
    begin
      FTasks[i].Button.SetBounds(x, iconY, btnSize, btnSize);
      FTasks[i].Button.Caption := dispTitle;
      FTasks[i].Button.IconPosition := ftipOnly;
    end;

    if Assigned(FTasks[i].Menu) then
      FTasks[i].Button.ContextMenuHandle := FTasks[i].Menu.Handle;

    // Icons are fetched at the size actually drawn, so the dock gets a crisp 48px
    // image rather than an 18px one scaled up.
    iconBmp := GetOrLoadWindowIcon(FTasks[i].Window, FIconSize);
    if Assigned(iconBmp) then
    begin
      FTasks[i].Button.SetIconBitmap(iconBmp, False);
      FTasks[i].Button.SetIconSize(FIconSize, FIconSize);
      FTasks[i].Button.IconGap := 0;
    end
    else
      FTasks[i].Button.ClearIcon();

    // The active window and any minimized one both get a visual difference; the
    // taskbar used Toggled only. A dock needs to show "this is running" as well as
    // "this is focused", or a single task looks like a static icon.
    FTasks[i].Button.Toggled := FTasks[i].IsActive;
  end;

  FWindow.Invalidate();
end;

end.
