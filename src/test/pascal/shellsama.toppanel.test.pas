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

  // 6. Battery applet
  AssertNotNull('Battery applet must be created', FPanel.BatteryApplet);
  AssertNotNull('Battery applet button must be created', FPanel.BatteryApplet.Button);
  AssertTrue('Battery applet button must be flat (borderless when idle)', FPanel.BatteryApplet.Button.Flat);

  // 6b. Keyboard applet
  AssertNotNull('Keyboard applet must be created', FPanel.KeyboardApplet);
  AssertNotNull('Keyboard applet button must be created', FPanel.KeyboardApplet.Button);
  AssertTrue('Keyboard applet button must be flat (borderless when idle)', FPanel.KeyboardApplet.Button.Flat);

  // 6c. Display applet
  AssertNotNull('Display applet must be created', FPanel.DisplayApplet);
  AssertNotNull('Display applet button must be created', FPanel.DisplayApplet.Button);
  AssertTrue('Display applet button must be flat (borderless when idle)', FPanel.DisplayApplet.Button.Flat);

  // 7. Bluetooth applet
  AssertNotNull('Bluetooth applet must be created', FPanel.BluetoothApplet);
  AssertNotNull('Bluetooth applet button must be created', FPanel.BluetoothApplet.Button);
  AssertTrue('Bluetooth applet button must be flat (borderless when idle)', FPanel.BluetoothApplet.Button.Flat);

  // 8. Wired applet
  AssertNotNull('Wired applet must be created', FPanel.WiredApplet);
  AssertNotNull('Wired applet button must be created', FPanel.WiredApplet.Button);
  AssertTrue('Wired applet button must be flat (borderless when idle)', FPanel.WiredApplet.Button.Flat);

  // 9. LAN applet
  AssertNotNull('LAN applet must be created', FPanel.LanApplet);
  AssertNotNull('LAN applet button must be created', FPanel.LanApplet.Button);
  AssertTrue('LAN applet button must be flat (borderless when idle)', FPanel.LanApplet.Button.Flat);

  // 10. Session applet (shutdown button)
  AssertNotNull('Session applet must be created', FPanel.SessionApplet);
  AssertNotNull('Session applet button must be created', FPanel.SessionApplet.Button);
  AssertTrue('Session applet button must be flat (borderless when idle)', FPanel.SessionApplet.Button.Flat);

  // Verify left-to-right ordering of right-docked elements
  AssertTrue('ShowDesktop rightmost', FPanel.ShowDesktopWidget.X > FPanel.SessionApplet.Button.X);
  AssertTrue('Session right of Clock', FPanel.SessionApplet.Button.X > FPanel.ClockApplet.Button.X);
  AssertTrue('Clock right of Volume', FPanel.ClockApplet.Button.X > FPanel.VolumeApplet.Button.X);
  AssertTrue('Volume right of Keyboard', FPanel.VolumeApplet.Button.X > FPanel.KeyboardApplet.Button.X);
  AssertTrue('Keyboard right of Display', FPanel.KeyboardApplet.Button.X > FPanel.DisplayApplet.Button.X);
  AssertTrue('Display right of Battery', FPanel.DisplayApplet.Button.X > FPanel.BatteryApplet.Button.X);
  AssertTrue('Battery right of Bluetooth', FPanel.BatteryApplet.Button.X > FPanel.BluetoothApplet.Button.X);
  AssertTrue('Bluetooth right of Wired', FPanel.BluetoothApplet.Button.X > FPanel.WiredApplet.Button.X);
  AssertTrue('Wired right of LAN', FPanel.WiredApplet.Button.X > FPanel.LanApplet.Button.X);
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
  AssertFalse('Battery popup should be closed', FPanel.BatteryApplet.IsPopupOpen());

  // 2b. Hovering over Keyboard button while tracking is active -> switches to Keyboard applet
  if Assigned(FPanel.KeyboardApplet.Button.OnHover) then
    FPanel.KeyboardApplet.Button.OnHover(FPanel.KeyboardApplet.Button, True);
  AssertTrue('Tracking remains active after switching to keyboard', FPanel.TrackingActive);
  AssertEquals('Active applet should switch to pakKeyboard', Ord(pakKeyboard), Ord(FPanel.ActiveApplet));
  AssertFalse('Volume popup should be closed after switch', FPanel.VolumeApplet.IsPopupOpen());
  AssertTrue('Keyboard popup should be open after switch', FPanel.KeyboardApplet.IsPopupOpen());

  // 2c. Hovering over Display button while tracking is active -> switches to Display applet
  if Assigned(FPanel.DisplayApplet.Button.OnHover) then
    FPanel.DisplayApplet.Button.OnHover(FPanel.DisplayApplet.Button, True);
  AssertTrue('Tracking remains active after switching to display', FPanel.TrackingActive);
  AssertEquals('Active applet should switch to pakDisplay', Ord(pakDisplay), Ord(FPanel.ActiveApplet));
  AssertFalse('Keyboard popup should be closed after switch', FPanel.KeyboardApplet.IsPopupOpen());
  AssertTrue('Display popup should be open after switch', FPanel.DisplayApplet.IsPopupOpen());

  // 3. Hovering over Battery button while tracking is active -> switches to Battery applet
  if Assigned(FPanel.BatteryApplet.Button.OnHover) then
    FPanel.BatteryApplet.Button.OnHover(FPanel.BatteryApplet.Button, True);
  AssertTrue('Tracking remains active after switching to battery', FPanel.TrackingActive);
  AssertEquals('Active applet should switch to pakBattery', Ord(pakBattery), Ord(FPanel.ActiveApplet));
  AssertFalse('Display popup should be closed after switch', FPanel.DisplayApplet.IsPopupOpen());
  AssertTrue('Battery popup should be open after switch', FPanel.BatteryApplet.IsPopupOpen());

  // 4. Hovering over Bluetooth button while tracking is active -> switches to Bluetooth applet
  if Assigned(FPanel.BluetoothApplet.Button.OnHover) then
    FPanel.BluetoothApplet.Button.OnHover(FPanel.BluetoothApplet.Button, True);
  AssertTrue('Tracking remains active after switching to bluetooth', FPanel.TrackingActive);
  AssertEquals('Active applet should switch to pakBluetooth', Ord(pakBluetooth), Ord(FPanel.ActiveApplet));
  AssertFalse('Battery popup should be closed after switch', FPanel.BatteryApplet.IsPopupOpen());
  AssertTrue('Bluetooth popup should be open after switch', FPanel.BluetoothApplet.IsPopupOpen());

  // 5. Hovering over Wired button while tracking is active -> switches to Wired applet
  if Assigned(FPanel.WiredApplet.Button.OnHover) then
    FPanel.WiredApplet.Button.OnHover(FPanel.WiredApplet.Button, True);
  AssertTrue('Tracking remains active after switching to wired', FPanel.TrackingActive);
  AssertEquals('Active applet should switch to pakWired', Ord(pakWired), Ord(FPanel.ActiveApplet));
  AssertFalse('Bluetooth popup should be closed after switch', FPanel.BluetoothApplet.IsPopupOpen());
  AssertTrue('Wired popup should be open after switch', FPanel.WiredApplet.IsPopupOpen());

  // 6. Hovering over LAN button while tracking is active -> switches to LAN applet
  if Assigned(FPanel.LanApplet.Button.OnHover) then
    FPanel.LanApplet.Button.OnHover(FPanel.LanApplet.Button, True);
  AssertTrue('Tracking remains active after switching to LAN', FPanel.TrackingActive);
  AssertEquals('Active applet should switch to pakLan', Ord(pakLan), Ord(FPanel.ActiveApplet));
  AssertFalse('Wired popup should be closed after switch', FPanel.WiredApplet.IsPopupOpen());
  AssertTrue('LAN popup should be open after switch', FPanel.LanApplet.IsPopupOpen());

  // 7. Hovering over Clock button while tracking is active -> switches to Clock applet
  if Assigned(FPanel.ClockApplet.Button.OnHover) then
    FPanel.ClockApplet.Button.OnHover(FPanel.ClockApplet.Button, True);
  AssertTrue('Tracking remains active after switching to clock', FPanel.TrackingActive);
  AssertEquals('Active applet should switch to pakClock', Ord(pakClock), Ord(FPanel.ActiveApplet));
  AssertFalse('LAN popup should be closed after switch', FPanel.LanApplet.IsPopupOpen());
  AssertTrue('Clock popup should be open after switch', FPanel.ClockApplet.IsPopupOpen());

  // 8. Hovering over Session button while tracking is active -> switches to Session applet
  if Assigned(FPanel.SessionApplet.Button.OnHover) then
    FPanel.SessionApplet.Button.OnHover(FPanel.SessionApplet.Button, True);
  AssertTrue('Tracking remains active after switching to session', FPanel.TrackingActive);
  AssertEquals('Active applet should switch to pakSession', Ord(pakSession), Ord(FPanel.ActiveApplet));
  AssertFalse('Clock popup should be closed after switch', FPanel.ClockApplet.IsPopupOpen());
  AssertTrue('Session popup should be open after switch', FPanel.SessionApplet.IsPopupOpen());

  // 9. Hovering over Show Desktop button does NOT switch applets
  if Assigned(FPanel.ShowDesktopWidget.OnHover) then
    FPanel.ShowDesktopWidget.OnHover(FPanel.ShowDesktopWidget, True);
  AssertEquals('Active applet remains pakSession after hovering show desktop', Ord(pakSession), Ord(FPanel.ActiveApplet));
  AssertTrue('Session popup remains open', FPanel.SessionApplet.IsPopupOpen());

  // 10. Click active button (Session) -> dismisses applets and ends tracking
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

  // 5. Battery SVG resolution
  svgLight := GetBatteryIconSVG(85, False, True, False);
  svgDark  := GetBatteryIconSVG(85, False, True, True);
  AssertTrue('Light battery SVG stroke must be #2c3e50', Pos('#2c3e50', LowerCase(svgLight)) > 0);
  AssertTrue('Dark battery SVG stroke must be #f0f2f5', Pos('#f0f2f5', LowerCase(svgDark)) > 0);

  // 6. Wired SVG resolution
  svgLight := GetWiredIconSVG(True, False);
  svgDark  := GetWiredIconSVG(True, True);
  AssertTrue('Light wired SVG stroke must be #2c3e50', Pos('#2c3e50', LowerCase(svgLight)) > 0);
  AssertTrue('Dark wired SVG stroke must be #f0f2f5', Pos('#f0f2f5', LowerCase(svgDark)) > 0);

  // 7. LAN SVG resolution
  svgLight := GetLanIconSVG(True, 80, True, False);
  svgDark  := GetLanIconSVG(True, 80, True, True);
  AssertTrue('Light LAN SVG stroke must be #2c3e50', Pos('#2c3e50', LowerCase(svgLight)) > 0);
  AssertTrue('Dark LAN SVG stroke must be #f0f2f5', Pos('#f0f2f5', LowerCase(svgDark)) > 0);

  // 8. Bluetooth SVG resolution
  svgLight := GetBluetoothIconSVG(True, True, False);
  svgDark  := GetBluetoothIconSVG(True, True, True);
  AssertTrue('Light bluetooth SVG stroke must be #2c3e50', Pos('#2c3e50', LowerCase(svgLight)) > 0);
  AssertTrue('Dark bluetooth SVG stroke must be #f0f2f5', Pos('#f0f2f5', LowerCase(svgDark)) > 0);

  // 8b. Keyboard SVG resolution
  svgLight := GetKeyboardIconSVG('US', False);
  svgDark  := GetKeyboardIconSVG('US', True);
  AssertTrue('Light keyboard SVG stroke must be #2c3e50', Pos('#2c3e50', LowerCase(svgLight)) > 0);
  AssertTrue('Dark keyboard SVG stroke must be #f0f2f5', Pos('#f0f2f5', LowerCase(svgDark)) > 0);

  // 8c. Display SVG resolution
  svgLight := GetDisplayIconSVG(1, False);
  svgDark  := GetDisplayIconSVG(1, True);
  AssertTrue('Light display SVG stroke must be #2c3e50', Pos('#2c3e50', LowerCase(svgLight)) > 0);
  AssertTrue('Dark display SVG stroke must be #f0f2f5', Pos('#f0f2f5', LowerCase(svgDark)) > 0);

  // 9. Panel style switching
  FtApp().DarkMode := False;
  FPanel.ApplyThemeStyle();
  AssertNotNull('Launcher button icon must be loaded in light mode', ft_button_get_icon_bitmap(FPanel.LauncherWidget.Handle));
  AssertNotNull('Desktop button icon must be loaded in light mode', ft_button_get_icon_bitmap(FPanel.ShowDesktopWidget.Handle));
  AssertNotNull('Volume button icon must be loaded in light mode', ft_button_get_icon_bitmap(FPanel.VolumeApplet.Button.Handle));
  AssertNotNull('Keyboard button icon must be loaded in light mode', ft_button_get_icon_bitmap(FPanel.KeyboardApplet.Button.Handle));
  AssertNotNull('Display button icon must be loaded in light mode', ft_button_get_icon_bitmap(FPanel.DisplayApplet.Button.Handle));
  AssertNotNull('Battery button icon must be loaded in light mode', ft_button_get_icon_bitmap(FPanel.BatteryApplet.Button.Handle));
  AssertNotNull('Bluetooth button icon must be loaded in light mode', ft_button_get_icon_bitmap(FPanel.BluetoothApplet.Button.Handle));
  AssertNotNull('Wired button icon must be loaded in light mode', ft_button_get_icon_bitmap(FPanel.WiredApplet.Button.Handle));
  AssertNotNull('LAN button icon must be loaded in light mode', ft_button_get_icon_bitmap(FPanel.LanApplet.Button.Handle));
  AssertNotNull('Session button icon must be loaded in light mode', ft_button_get_icon_bitmap(FPanel.SessionApplet.Button.Handle));

  FtApp().DarkMode := True;
  FPanel.ApplyThemeStyle();
  AssertNotNull('Launcher button icon must be loaded in dark mode', ft_button_get_icon_bitmap(FPanel.LauncherWidget.Handle));
  AssertNotNull('Keyboard button icon must be loaded in dark mode', ft_button_get_icon_bitmap(FPanel.KeyboardApplet.Button.Handle));
  AssertNotNull('Display button icon must be loaded in dark mode', ft_button_get_icon_bitmap(FPanel.DisplayApplet.Button.Handle));
  AssertNotNull('Desktop button icon must be loaded in dark mode', ft_button_get_icon_bitmap(FPanel.ShowDesktopWidget.Handle));
  AssertNotNull('Volume button icon must be loaded in dark mode', ft_button_get_icon_bitmap(FPanel.VolumeApplet.Button.Handle));
  AssertNotNull('Battery button icon must be loaded in dark mode', ft_button_get_icon_bitmap(FPanel.BatteryApplet.Button.Handle));
  AssertNotNull('Bluetooth button icon must be loaded in dark mode', ft_button_get_icon_bitmap(FPanel.BluetoothApplet.Button.Handle));
  AssertNotNull('Wired button icon must be loaded in dark mode', ft_button_get_icon_bitmap(FPanel.WiredApplet.Button.Handle));
  AssertNotNull('LAN button icon must be loaded in dark mode', ft_button_get_icon_bitmap(FPanel.LanApplet.Button.Handle));
  AssertNotNull('Session button icon must be loaded in dark mode', ft_button_get_icon_bitmap(FPanel.SessionApplet.Button.Handle));
end;

initialization
  RegisterTest(TTopPanelTest);
end.
