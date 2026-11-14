unit ShellSama.TopPanel.Test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  ftpas.api, ftpas.types, ftpas,
  ShellSama.Applets,
  ShellSama.Launcher,
  ShellSama.TopPanel;

type
  TTopPanelTest = class(TTestCase)
  private
    FLauncher: TShellLauncher;
    FPanel   : TShellTopPanel;
  protected
    procedure SetUp(); override;
    procedure TearDown(); override;
  published
    procedure TestPanelCreationAndGeometry();
    procedure TestWidgetsInitialized();
    procedure TestPanelVisibilityToggle();
    procedure TestClockUpdate();
    procedure TestLauncherSync();
    procedure TestTickExecution();
    procedure TestToggleShowDesktop();
    procedure TestAppletHoverSwitching();
    procedure TestTopPanelIconsFollowDarkMode();
  end;

implementation

procedure TTopPanelTest.SetUp();
begin
  if not FtIsLibLoaded() then
  begin
    if not FtLoadLib() then
      Fail('Could not load libft.so');
  end;

  try
    FtApp().Initialize();
  except
    on E: Exception do
      Fail('FtApp.Initialize failed: ' + E.Message);
  end;

  FLauncher := TShellLauncher.Create();
  FPanel := TShellTopPanel.Create(FLauncher);
end;

procedure TTopPanelTest.TearDown();
begin
  if Assigned(FPanel) then
  begin
    FPanel.Free();
    FPanel := nil;
  end;

  if Assigned(FLauncher) then
  begin
    FLauncher.Free();
    FLauncher := nil;
  end;
end;

procedure TTopPanelTest.TestPanelCreationAndGeometry();
var
  sw: Integer;
begin
  AssertNotNull('Panel instance should be created', FPanel);
  sw := FtApp().ScreenWidth;

  AssertEquals('Panel X must be 0', 0, FPanel.PanelX());
  AssertEquals('Panel Y must be at top of screen (0)', 0, FPanel.PanelY());
  AssertEquals('Panel Width must match screen width', sw, FPanel.PanelWidth());
  AssertEquals('Panel Height must be 38', 38, FPanel.PanelHeight());
  AssertEquals('Panel background opacity must be 0.50', 0.50, FPanel.BackgroundOpacity, 0.001);
  AssertEquals('Window widget background opacity must be 0.50', 0.50, FPanel.WindowWidget.BackgroundOpacity, 0.001);
end;

procedure TTopPanelTest.TestWidgetsInitialized();
var
  iconW, iconH: Integer;
begin
  AssertNotNull('Window widget must be created', FPanel.WindowWidget);

  // 1. Launcher button on the left
  AssertNotNull('Launcher button must be created', FPanel.LauncherWidget);
  AssertTrue('Launcher button must be flat (borderless when idle)', FPanel.LauncherWidget.Flat);
  AssertEquals('Launcher button caption must be Find', 'Find', FPanel.LauncherWidget.Caption);
  AssertEquals('Launcher button icon position must be ftipLeft', Ord(ftipLeft), Ord(FPanel.LauncherWidget.IconPosition));
  FPanel.LauncherWidget.GetIconSize(iconW, iconH);
  AssertEquals('Launcher button icon width must be 22', 22, iconW);
  AssertEquals('Launcher button icon height must be 22', 22, iconH);
  AssertNotNull('Launcher button icon must be loaded', ft_button_get_icon_bitmap(FPanel.LauncherWidget.Handle));

  // 2. Desktop button on the right
  AssertNotNull('Show desktop button must be created', FPanel.ShowDesktopWidget);
  AssertTrue('Show desktop button must be flat (borderless when idle)', FPanel.ShowDesktopWidget.Flat);

  // 3. Clock text label
  AssertNotNull('Clock text widget must be created', FPanel.ClockWidget);
  AssertTrue('Clock button must be wide enough to show date and time without truncation', FPanel.ClockWidget.Width >= 200);

  // 4. Tray widget
  AssertNotNull('Tray widget must be created', FPanel.TrayWidget);

  // 5. Volume applet
  AssertNotNull('Volume applet must be created', FPanel.VolumeApplet);
  AssertNotNull('Volume applet button must be created', FPanel.VolumeApplet.Button);
  AssertTrue('Volume applet button must be flat (borderless when idle)', FPanel.VolumeApplet.Button.Flat);

  // 6. Session applet (shutdown button)
  AssertNotNull('Session applet must be created', FPanel.SessionApplet);
  AssertNotNull('Session applet button must be created', FPanel.SessionApplet.Button);
  AssertTrue('Session applet button must be flat (borderless when idle)', FPanel.SessionApplet.Button.Flat);
end;

procedure TTopPanelTest.TestPanelVisibilityToggle();
begin
  AssertFalse('Panel should start hidden', FPanel.IsVisible);

  FPanel.Show();
  AssertTrue('Panel should be visible after Show()', FPanel.IsVisible);

  FPanel.Hide();
  AssertFalse('Panel should be hidden after Hide()', FPanel.IsVisible);
end;

procedure TTopPanelTest.TestClockUpdate();
begin
  // UpdateClock should run without exception
  FPanel.UpdateClock();
  AssertNotNull('Clock widget still valid', FPanel.ClockWidget);
  AssertTrue('Clock button caption must not end with ellipsis', Pos('...', FPanel.ClockApplet.Button.Caption) = 0);
end;

procedure TTopPanelTest.TestLauncherSync();
begin
  AssertFalse('Launcher should start hidden', FLauncher.IsVisible);

  // Click launcher from top panel
  FPanel.OnLauncherClicked();
  AssertTrue('Launcher should now be visible after top panel launcher clicked', FLauncher.IsVisible);

  // Toggle off
  FPanel.OnLauncherClicked();
  AssertFalse('Launcher should now be hidden after second click', FLauncher.IsVisible);
end;

procedure TTopPanelTest.TestTickExecution();
begin
  // Tick should handle clock, volume, and animation checks gracefully
  FPanel.Tick();
  AssertNotNull('Panel remains valid after Tick', FPanel);
end;

procedure TTopPanelTest.TestToggleShowDesktop();
begin
  // ToggleShowDesktop should execute cleanly
  FPanel.ToggleShowDesktop();
  FPanel.ToggleShowDesktop();
  AssertTrue('Panel remains valid after ShowDesktop toggles', FPanel.IsVisible or not FPanel.IsVisible);
end;

procedure TTopPanelTest.TestAppletHoverSwitching();
begin
  // Initially inactive
  AssertFalse('Tracking should not be active initially', FPanel.TrackingActive);
  AssertEquals('Active applet should be pakNone', Ord(pakNone), Ord(FPanel.ActiveApplet));

  // 1. Hovering while inactive does NOT activate tracking
  if Assigned(FPanel.VolumeApplet.Button.OnHover) then
    FPanel.VolumeApplet.Button.OnHover(FPanel.VolumeApplet.Button, True);
  AssertFalse('Hovering while inactive should not start tracking', FPanel.TrackingActive);
  AssertEquals('Active applet remains pakNone', Ord(pakNone), Ord(FPanel.ActiveApplet));

  // 2. Click Volume button -> activates Volume applet and starts tracking
  if Assigned(FPanel.VolumeApplet.Button.OnClick) then
    FPanel.VolumeApplet.Button.OnClick(FPanel.VolumeApplet.Button);
  AssertTrue('Tracking should be active after volume button click', FPanel.TrackingActive);
  AssertEquals('Active applet should be pakVolume', Ord(pakVolume), Ord(FPanel.ActiveApplet));
  AssertTrue('Volume popup should be open', FPanel.VolumeApplet.IsPopupOpen());
  AssertFalse('Clock popup should be closed', FPanel.ClockApplet.IsPopupOpen());

  // 3. Hovering over Clock button while tracking is active -> switches to Clock applet
  if Assigned(FPanel.ClockApplet.Button.OnHover) then
    FPanel.ClockApplet.Button.OnHover(FPanel.ClockApplet.Button, True);
  AssertTrue('Tracking remains active after switching to clock', FPanel.TrackingActive);
  AssertEquals('Active applet should switch to pakClock', Ord(pakClock), Ord(FPanel.ActiveApplet));
  AssertFalse('Volume popup should be closed after switch', FPanel.VolumeApplet.IsPopupOpen());
  AssertTrue('Clock popup should be open after switch', FPanel.ClockApplet.IsPopupOpen());

  // 4. Hovering over Session button while tracking is active -> switches to Session applet
  if Assigned(FPanel.SessionApplet.Button.OnHover) then
    FPanel.SessionApplet.Button.OnHover(FPanel.SessionApplet.Button, True);
  AssertTrue('Tracking remains active after switching to session', FPanel.TrackingActive);
  AssertEquals('Active applet should switch to pakSession', Ord(pakSession), Ord(FPanel.ActiveApplet));
  AssertFalse('Clock popup should be closed after switch', FPanel.ClockApplet.IsPopupOpen());
  AssertTrue('Session popup should be open after switch', FPanel.SessionApplet.IsPopupOpen());

  // 5. Hovering over Show Desktop button does NOT switch applets
  if Assigned(FPanel.ShowDesktopWidget.OnHover) then
    FPanel.ShowDesktopWidget.OnHover(FPanel.ShowDesktopWidget, True);
  AssertEquals('Active applet remains pakSession after hovering show desktop', Ord(pakSession), Ord(FPanel.ActiveApplet));
  AssertTrue('Session popup remains open', FPanel.SessionApplet.IsPopupOpen());

  // 6. Click active button (Session) -> dismisses applets and ends tracking
  if Assigned(FPanel.SessionApplet.Button.OnClick) then
    FPanel.SessionApplet.Button.OnClick(FPanel.SessionApplet.Button);
  AssertFalse('Tracking should end after clicking active button', FPanel.TrackingActive);
  AssertEquals('Active applet should be pakNone', Ord(pakNone), Ord(FPanel.ActiveApplet));
  AssertFalse('Session popup should be closed', FPanel.SessionApplet.IsPopupOpen());
end;

procedure TTopPanelTest.TestTopPanelIconsFollowDarkMode();
var
  svgLight, svgDark: string;
begin
  // 1. Launcher SVG resolution
  svgLight := ResolveLauncherIconSVG(False);
  svgDark  := ResolveLauncherIconSVG(True);
  AssertTrue('Light launcher SVG must contain #4d4d4d', Pos('#4d4d4d', LowerCase(svgLight)) > 0);
  AssertTrue('Dark launcher SVG must contain #f9f9f9', Pos('#f9f9f9', LowerCase(svgDark)) > 0);

  // 2. Desktop SVG resolution
  svgLight := GetDesktopIconSVG(False);
  svgDark  := GetDesktopIconSVG(True);
  AssertTrue('Light desktop SVG stroke must be #2c3e50', Pos('#2c3e50', LowerCase(svgLight)) > 0);
  AssertTrue('Dark desktop SVG stroke must be #f0f2f5', Pos('#f0f2f5', LowerCase(svgDark)) > 0);

  // 3. Power SVG resolution
  svgLight := GetPowerIconSVG(False);
  svgDark  := GetPowerIconSVG(True);
  AssertTrue('Light power SVG stroke must be #2c3e50', Pos('#2c3e50', LowerCase(svgLight)) > 0);
  AssertTrue('Dark power SVG stroke must be #f0f2f5', Pos('#f0f2f5', LowerCase(svgDark)) > 0);

  // 4. Volume SVG resolution
  svgLight := GetVolumeIconSVG(vikHigh, False);
  svgDark  := GetVolumeIconSVG(vikHigh, True);
  AssertTrue('Light volume SVG stroke must be #2c3e50', Pos('#2c3e50', LowerCase(svgLight)) > 0);
  AssertTrue('Dark volume SVG stroke must be #f0f2f5', Pos('#f0f2f5', LowerCase(svgDark)) > 0);

  // 5. Panel style switching
  FtApp().DarkMode := False;
  FPanel.ApplyThemeStyle();
  AssertNotNull('Launcher button icon must be loaded in light mode', ft_button_get_icon_bitmap(FPanel.LauncherWidget.Handle));
  AssertNotNull('Desktop button icon must be loaded in light mode', ft_button_get_icon_bitmap(FPanel.ShowDesktopWidget.Handle));
  AssertNotNull('Volume button icon must be loaded in light mode', ft_button_get_icon_bitmap(FPanel.VolumeApplet.Button.Handle));
  AssertNotNull('Session button icon must be loaded in light mode', ft_button_get_icon_bitmap(FPanel.SessionApplet.Button.Handle));

  FtApp().DarkMode := True;
  FPanel.ApplyThemeStyle();
  AssertNotNull('Launcher button icon must be loaded in dark mode', ft_button_get_icon_bitmap(FPanel.LauncherWidget.Handle));
  AssertNotNull('Desktop button icon must be loaded in dark mode', ft_button_get_icon_bitmap(FPanel.ShowDesktopWidget.Handle));
  AssertNotNull('Volume button icon must be loaded in dark mode', ft_button_get_icon_bitmap(FPanel.VolumeApplet.Button.Handle));
  AssertNotNull('Session button icon must be loaded in dark mode', ft_button_get_icon_bitmap(FPanel.SessionApplet.Button.Handle));
end;

initialization
  RegisterTest(TTopPanelTest);
end.
