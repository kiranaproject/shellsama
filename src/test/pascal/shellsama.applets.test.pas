unit ShellSama.Applets.Test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  ftpas.api, ftpas.types, ftpas, ftpas.menus,
  ShellSama.Applets;

type
  TAppletsTest = class(TTestCase)
  private
    FTestWin         : TFtWindow;
    FVolumeApplet    : TShellVolumeApplet;
    FClockApplet     : TShellClockApplet;
    FSessionApplet   : TShellSessionApplet;
    FBatteryApplet   : TShellBatteryApplet;
    FWiredApplet     : TShellWiredApplet;
    FLanApplet       : TShellLanApplet;
    FBluetoothApplet : TShellBluetoothApplet;
  protected
    procedure SetUp(); override;
    procedure TearDown(); override;
  published
    procedure TestVolumeAppletCreation();
    procedure TestVolumeAppletGlyphsAndMute();
    procedure TestVolumePopupLifecycle();
    procedure TestClockAppletLifecycle();
    procedure TestSessionAppletCreationAndMenu();
    procedure TestSessionAppletBounds();
    procedure TestBatteryAppletCreationAndGlyphs();
    procedure TestBatteryPopupLifecycle();
    procedure TestWiredAppletCreationAndGlyphs();
    procedure TestWiredPopupLifecycle();
    procedure TestLanAppletCreationAndGlyphs();
    procedure TestLanPopupLifecycle();
    procedure TestBluetoothAppletCreationAndGlyphs();
    procedure TestBluetoothPopupLifecycle();
    procedure TestAppletsDarkModeTheme();
  end;

implementation

procedure TAppletsTest.SetUp();
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

  FTestWin := TFtWindow.Create(600, 100, 'test-applets-window');
  FVolumeApplet := TShellVolumeApplet.Create(FTestWin, 10, 10, 32, 28);
  FClockApplet := TShellClockApplet.Create(FTestWin, 50, 10, 80, 28);
  FSessionApplet := TShellSessionApplet.Create(FTestWin, 140, 10, 32, 28);
  FBatteryApplet := TShellBatteryApplet.Create(FTestWin, 180, 10, 32, 28);
  FWiredApplet := TShellWiredApplet.Create(FTestWin, 220, 10, 32, 28);
  FLanApplet := TShellLanApplet.Create(FTestWin, 260, 10, 32, 28);
  FBluetoothApplet := TShellBluetoothApplet.Create(FTestWin, 300, 10, 32, 28);
end;

procedure TAppletsTest.TearDown();
begin
  if Assigned(FBluetoothApplet) then
  begin
    FBluetoothApplet.Free();
    FBluetoothApplet := nil;
  end;

  if Assigned(FLanApplet) then
  begin
    FLanApplet.Free();
    FLanApplet := nil;
  end;

  if Assigned(FWiredApplet) then
  begin
    FWiredApplet.Free();
    FWiredApplet := nil;
  end;

  if Assigned(FBatteryApplet) then
  begin
    FBatteryApplet.Free();
    FBatteryApplet := nil;
  end;

  if Assigned(FSessionApplet) then
  begin
    FSessionApplet.Free();
    FSessionApplet := nil;
  end;

  if Assigned(FClockApplet) then
  begin
    FClockApplet.Free();
    FClockApplet := nil;
  end;

  if Assigned(FVolumeApplet) then
  begin
    FVolumeApplet.Free();
    FVolumeApplet := nil;
  end;

  if Assigned(FTestWin) then
  begin
    FTestWin.Free();
    FTestWin := nil;
  end;
end;

procedure TAppletsTest.TestVolumeAppletCreation();
begin
  AssertNotNull('Volume applet must be created', FVolumeApplet);
  AssertNotNull('Volume button must be created', FVolumeApplet.Button);
  AssertTrue('Volume must be >= 0', FVolumeApplet.CurrentVolume >= 0);
  AssertTrue('Volume must be <= 150', FVolumeApplet.CurrentVolume <= 150);
  AssertFalse('Popup should start closed', FVolumeApplet.IsPopupOpen());
end;

procedure TAppletsTest.TestVolumeAppletGlyphsAndMute();
begin
  // Button icon position must be ftipOnly for centered vector icon
  AssertEquals('Volume button icon position must be ftipOnly', Ord(ftipOnly), Ord(FVolumeApplet.Button.IconPosition));

  // Muted state -> vikMuted
  FVolumeApplet.SetVolumeState(75, True);
  AssertTrue('Applet should report muted', FVolumeApplet.IsMuted);
  AssertEquals('Muted state icon kind', Ord(vikMuted), Ord(FVolumeApplet.IconKind));

  // Unmuted low volume (< 33) -> vikLow
  FVolumeApplet.SetVolumeState(20, False);
  AssertFalse('Applet should report unmuted', FVolumeApplet.IsMuted);
  AssertEquals('Low volume icon kind', Ord(vikLow), Ord(FVolumeApplet.IconKind));

  // Unmuted medium volume (33..65) -> vikMedium
  FVolumeApplet.SetVolumeState(50, False);
  AssertEquals('Medium volume icon kind', Ord(vikMedium), Ord(FVolumeApplet.IconKind));

  // Unmuted high volume (>= 66) -> vikHigh
  FVolumeApplet.SetVolumeState(85, False);
  AssertEquals('High volume icon kind', Ord(vikHigh), Ord(FVolumeApplet.IconKind));
end;

procedure TAppletsTest.TestVolumePopupLifecycle();
begin
  AssertFalse('Popup should not be open initially', FVolumeApplet.IsPopupOpen());
  AssertNull('Popup window should be nil initially', FVolumeApplet.PopupWindow);

  // Open popup
  FVolumeApplet.ShowPopup();
  AssertTrue('Popup should be open after ShowPopup()', FVolumeApplet.IsPopupOpen());
  AssertNotNull('Popup window should exist', FVolumeApplet.PopupWindow);
  AssertNotNull('Volume slider should exist', FVolumeApplet.Slider);
  AssertNotNull('Mute button should exist', FVolumeApplet.MuteButton);
  AssertNotNull('Volume label should exist', FVolumeApplet.VolumeLabel);

  // Close popup
  FVolumeApplet.HidePopup();
  AssertFalse('Popup should be closed after HidePopup()', FVolumeApplet.IsPopupOpen());
  AssertFalse('Popup window should not be visible after HidePopup()', FVolumeApplet.PopupWindow.Visible);

  // Toggle open
  FVolumeApplet.TogglePopup();
  AssertTrue('Popup should be open after TogglePopup()', FVolumeApplet.IsPopupOpen());
  AssertTrue('Popup window should be visible after TogglePopup()', FVolumeApplet.PopupWindow.Visible);

  // Toggle close
  FVolumeApplet.TogglePopup();
  AssertFalse('Popup should be closed after second TogglePopup()', FVolumeApplet.IsPopupOpen());
end;

procedure TAppletsTest.TestClockAppletLifecycle();
begin
  AssertNotNull('Clock applet must be created', FClockApplet);
  AssertNotNull('Clock button must be created', FClockApplet.Button);
  AssertFalse('Clock popup should start closed', FClockApplet.IsPopupOpen());
  AssertNull('Clock popup window should be nil initially', FClockApplet.PopupWindow);

  // UpdateClock should set caption
  FClockApplet.UpdateClock();
  AssertTrue('Clock button should display time', Length(FClockApplet.Button.Caption) > 0);

  // Open popup
  FClockApplet.ShowPopup();
  AssertTrue('Clock popup should be open after ShowPopup()', FClockApplet.IsPopupOpen());
  AssertNotNull('Clock popup window should exist', FClockApplet.PopupWindow);
  AssertTrue('Clock button toggled while popup open', FClockApplet.Button.Toggled);

  // Hide popup
  FClockApplet.HidePopup();
  AssertFalse('Clock popup should be closed after HidePopup()', FClockApplet.IsPopupOpen());
  AssertFalse('Clock button untoggled after HidePopup()', FClockApplet.Button.Toggled);

  // Toggle open and close
  FClockApplet.TogglePopup();
  AssertTrue('Clock popup should be open after TogglePopup()', FClockApplet.IsPopupOpen());
  FClockApplet.TogglePopup();
  AssertFalse('Clock popup should be closed after TogglePopup()', FClockApplet.IsPopupOpen());
end;

procedure TAppletsTest.TestSessionAppletCreationAndMenu();
begin
  AssertNotNull('Session applet must be created', FSessionApplet);
  AssertNotNull('Session button must be created', FSessionApplet.Button);
  AssertEquals('Session button icon position must be ftipOnly', Ord(ftipOnly), Ord(FSessionApplet.Button.IconPosition));

  AssertNotNull('Session popup menu must be created', FSessionApplet.Menu);
  AssertEquals('Session menu should contain 8 items', 8, FSessionApplet.Menu.ItemCount);

  // Verify key menu items
  AssertEquals('Item 0 should be System Settings...', 'System Settings...', FSessionApplet.Menu.Items[0].Caption);
  // Item 1 is separator
  AssertEquals('Item 2 should be Lock Screen', 'Lock Screen', FSessionApplet.Menu.Items[2].Caption);
  AssertEquals('Item 3 should be Suspend', 'Suspend', FSessionApplet.Menu.Items[3].Caption);
  AssertEquals('Item 4 should be Log Out...', 'Log Out...', FSessionApplet.Menu.Items[4].Caption);
  // Item 5 is separator
  AssertEquals('Item 6 should be Restart...', 'Restart...', FSessionApplet.Menu.Items[6].Caption);
  AssertEquals('Item 7 should be Shut Down...', 'Shut Down...', FSessionApplet.Menu.Items[7].Caption);
end;

procedure TAppletsTest.TestSessionAppletBounds();
begin
  FSessionApplet.SetBounds(100, 2, 34, 30);
  AssertEquals('Session button X updated', 100, FSessionApplet.Button.X);
  AssertEquals('Session button Y updated', 2, FSessionApplet.Button.Y);
  AssertEquals('Session button W updated', 34, FSessionApplet.Button.Width);
  AssertEquals('Session button H updated', 30, FSessionApplet.Button.Height);
end;

procedure TAppletsTest.TestBatteryAppletCreationAndGlyphs();
begin
  AssertNotNull('Battery applet must be created', FBatteryApplet);
  AssertNotNull('Battery button must be created', FBatteryApplet.Button);
  AssertEquals('Battery button icon position must be ftipOnly', Ord(ftipOnly), Ord(FBatteryApplet.Button.IconPosition));
  AssertFalse('Battery popup should start closed', FBatteryApplet.IsPopupOpen());

  // Test state simulation via SetBatteryState
  FBatteryApplet.SetBatteryState(85, False, True);
  AssertEquals('Battery percentage should be 85', 85, FBatteryApplet.CurrentPercentage);
  AssertFalse('Battery should not be charging', FBatteryApplet.IsCharging);
  AssertTrue('Battery should be present', FBatteryApplet.IsBatteryPresent);

  FBatteryApplet.SetBatteryState(30, True, True);
  AssertEquals('Battery percentage should be 30', 30, FBatteryApplet.CurrentPercentage);
  AssertTrue('Battery should be charging', FBatteryApplet.IsCharging);

  FBatteryApplet.SetBatteryState(100, False, False);
  AssertFalse('Battery should not be present (AC only)', FBatteryApplet.IsBatteryPresent);
end;

procedure TAppletsTest.TestBatteryPopupLifecycle();
begin
  AssertFalse('Popup should not be open initially', FBatteryApplet.IsPopupOpen());
  AssertNull('Popup window should be nil initially', FBatteryApplet.PopupWindow);

  // Open popup
  FBatteryApplet.ShowPopup();
  AssertTrue('Popup should be open after ShowPopup()', FBatteryApplet.IsPopupOpen());
  AssertNotNull('Popup window should exist', FBatteryApplet.PopupWindow);
  AssertNotNull('Status label should exist', FBatteryApplet.StatusLabel);
  AssertNotNull('Percentage label should exist', FBatteryApplet.PercentageLabel);
  AssertNotNull('Settings button should exist', FBatteryApplet.SettingsButton);
  AssertTrue('Button toggled while open', FBatteryApplet.Button.Toggled);

  // Hide popup
  FBatteryApplet.HidePopup();
  AssertFalse('Popup should be closed after HidePopup()', FBatteryApplet.IsPopupOpen());
  AssertFalse('Button untoggled after HidePopup()', FBatteryApplet.Button.Toggled);

  // Toggle open and close
  FBatteryApplet.TogglePopup();
  AssertTrue('Popup open after TogglePopup', FBatteryApplet.IsPopupOpen());
  FBatteryApplet.TogglePopup();
  AssertFalse('Popup closed after second TogglePopup', FBatteryApplet.IsPopupOpen());
end;

procedure TAppletsTest.TestWiredAppletCreationAndGlyphs();
begin
  AssertNotNull('Wired applet must be created', FWiredApplet);
  AssertNotNull('Wired button must be created', FWiredApplet.Button);
  AssertEquals('Wired button icon position must be ftipOnly', Ord(ftipOnly), Ord(FWiredApplet.Button.IconPosition));
  AssertFalse('Wired popup should start closed', FWiredApplet.IsPopupOpen());

  // Test state simulation
  FWiredApplet.SetWiredState(True, 'eth0', '192.168.1.100');
  AssertTrue('Wired should be connected', FWiredApplet.IsConnected);
  AssertEquals('Interface name should be eth0', 'eth0', FWiredApplet.InterfaceName);
  AssertEquals('IP address should match', '192.168.1.100', FWiredApplet.IpAddress);

  FWiredApplet.SetWiredState(False, 'eth0', '');
  AssertFalse('Wired should be disconnected', FWiredApplet.IsConnected);
end;

procedure TAppletsTest.TestWiredPopupLifecycle();
begin
  AssertFalse('Popup should not be open initially', FWiredApplet.IsPopupOpen());
  AssertNull('Popup window should be nil initially', FWiredApplet.PopupWindow);

  // Open popup
  FWiredApplet.ShowPopup();
  AssertTrue('Popup should be open after ShowPopup()', FWiredApplet.IsPopupOpen());
  AssertNotNull('Popup window should exist', FWiredApplet.PopupWindow);
  AssertNotNull('Status label should exist', FWiredApplet.StatusLabel);
  AssertNotNull('Details label should exist', FWiredApplet.DetailsLabel);
  AssertNotNull('Settings button should exist', FWiredApplet.SettingsButton);
  AssertTrue('Button toggled while open', FWiredApplet.Button.Toggled);

  // Hide popup
  FWiredApplet.HidePopup();
  AssertFalse('Popup should be closed after HidePopup()', FWiredApplet.IsPopupOpen());
  AssertFalse('Button untoggled after HidePopup()', FWiredApplet.Button.Toggled);

  // Toggle open and close
  FWiredApplet.TogglePopup();
  AssertTrue('Popup open after TogglePopup', FWiredApplet.IsPopupOpen());
  FWiredApplet.TogglePopup();
  AssertFalse('Popup closed after second TogglePopup', FWiredApplet.IsPopupOpen());
end;

procedure TAppletsTest.TestLanAppletCreationAndGlyphs();
begin
  AssertNotNull('LAN applet must be created', FLanApplet);
  AssertNotNull('LAN button must be created', FLanApplet.Button);
  AssertEquals('LAN button icon position must be ftipOnly', Ord(ftipOnly), Ord(FLanApplet.Button.IconPosition));
  AssertFalse('LAN popup should start closed', FLanApplet.IsPopupOpen());

  // Test state simulation
  FLanApplet.SetLanState(True, 'SamarindaWiFi', 85, True);
  AssertTrue('LAN should be connected', FLanApplet.IsConnected);
  AssertEquals('SSID should match', 'SamarindaWiFi', FLanApplet.Ssid);
  AssertEquals('Signal should match', 85, FLanApplet.Signal);
  AssertTrue('LAN should be enabled', FLanApplet.IsEnabled);

  FLanApplet.SetLanState(False, '', 0, True);
  AssertFalse('LAN should be disconnected', FLanApplet.IsConnected);

  FLanApplet.SetLanState(False, '', 0, False);
  AssertFalse('LAN should be disabled', FLanApplet.IsEnabled);
end;

procedure TAppletsTest.TestLanPopupLifecycle();
begin
  AssertFalse('Popup should not be open initially', FLanApplet.IsPopupOpen());
  AssertNull('Popup window should be nil initially', FLanApplet.PopupWindow);

  // Open popup
  FLanApplet.ShowPopup();
  AssertTrue('Popup should be open after ShowPopup()', FLanApplet.IsPopupOpen());
  AssertNotNull('Popup window should exist', FLanApplet.PopupWindow);
  AssertNotNull('Status label should exist', FLanApplet.StatusLabel);
  AssertNotNull('Details label should exist', FLanApplet.DetailsLabel);
  AssertNotNull('Toggle button should exist', FLanApplet.ToggleButton);
  AssertNotNull('Settings button should exist', FLanApplet.SettingsButton);
  AssertTrue('Button toggled while open', FLanApplet.Button.Toggled);

  // Hide popup
  FLanApplet.HidePopup();
  AssertFalse('Popup should be closed after HidePopup()', FLanApplet.IsPopupOpen());
  AssertFalse('Button untoggled after HidePopup()', FLanApplet.Button.Toggled);

  // Toggle open and close
  FLanApplet.TogglePopup();
  AssertTrue('Popup open after TogglePopup', FLanApplet.IsPopupOpen());
  FLanApplet.TogglePopup();
  AssertFalse('Popup closed after second TogglePopup', FLanApplet.IsPopupOpen());
end;

procedure TAppletsTest.TestBluetoothAppletCreationAndGlyphs();
begin
  AssertNotNull('Bluetooth applet must be created', FBluetoothApplet);
  AssertNotNull('Bluetooth button must be created', FBluetoothApplet.Button);
  AssertEquals('Bluetooth button icon position must be ftipOnly', Ord(ftipOnly), Ord(FBluetoothApplet.Button.IconPosition));
  AssertFalse('Bluetooth popup should start closed', FBluetoothApplet.IsPopupOpen());

  // Test state simulation
  FBluetoothApplet.SetBluetoothState(True, True, 'Bluetooth Headset');
  AssertTrue('Bluetooth should be enabled', FBluetoothApplet.IsEnabled);
  AssertTrue('Bluetooth should be connected', FBluetoothApplet.IsConnected);
  AssertEquals('Connected device should match', 'Bluetooth Headset', FBluetoothApplet.ConnectedDevice);

  FBluetoothApplet.SetBluetoothState(True, False, '');
  AssertTrue('Bluetooth should be enabled', FBluetoothApplet.IsEnabled);
  AssertFalse('Bluetooth should be disconnected', FBluetoothApplet.IsConnected);

  FBluetoothApplet.SetBluetoothState(False, False, '');
  AssertFalse('Bluetooth should be disabled', FBluetoothApplet.IsEnabled);
end;

procedure TAppletsTest.TestBluetoothPopupLifecycle();
begin
  AssertFalse('Popup should not be open initially', FBluetoothApplet.IsPopupOpen());
  AssertNull('Popup window should be nil initially', FBluetoothApplet.PopupWindow);

  // Open popup
  FBluetoothApplet.ShowPopup();
  AssertTrue('Popup should be open after ShowPopup()', FBluetoothApplet.IsPopupOpen());
  AssertNotNull('Popup window should exist', FBluetoothApplet.PopupWindow);
  AssertNotNull('Status label should exist', FBluetoothApplet.StatusLabel);
  AssertNotNull('Details label should exist', FBluetoothApplet.DetailsLabel);
  AssertNotNull('Toggle button should exist', FBluetoothApplet.ToggleButton);
  AssertNotNull('Settings button should exist', FBluetoothApplet.SettingsButton);
  AssertTrue('Button toggled while open', FBluetoothApplet.Button.Toggled);

  // Hide popup
  FBluetoothApplet.HidePopup();
  AssertFalse('Popup should be closed after HidePopup()', FBluetoothApplet.IsPopupOpen());
  AssertFalse('Button untoggled after HidePopup()', FBluetoothApplet.Button.Toggled);

  // Toggle open and close
  FBluetoothApplet.TogglePopup();
  AssertTrue('Popup open after TogglePopup', FBluetoothApplet.IsPopupOpen());
  FBluetoothApplet.TogglePopup();
  AssertFalse('Popup closed after second TogglePopup', FBluetoothApplet.IsPopupOpen());
end;

procedure TAppletsTest.TestAppletsDarkModeTheme();
var
  savedDark: Boolean;
begin
  savedDark := FtApp().DarkMode;
  try
    // Test opening popups in dark mode
    FtApp().DarkMode := True;
    FVolumeApplet.ShowPopup();
    AssertTrue('Volume popup open in dark mode', FVolumeApplet.IsPopupOpen());
    AssertNotNull('Volume popup window exists in dark mode', FVolumeApplet.PopupWindow);

    FClockApplet.ShowPopup();
    AssertTrue('Clock popup open in dark mode', FClockApplet.IsPopupOpen());
    AssertNotNull('Clock popup window exists in dark mode', FClockApplet.PopupWindow);

    FBatteryApplet.ShowPopup();
    AssertTrue('Battery popup open in dark mode', FBatteryApplet.IsPopupOpen());
    AssertNotNull('Battery popup window exists in dark mode', FBatteryApplet.PopupWindow);

    FWiredApplet.ShowPopup();
    AssertTrue('Wired popup open in dark mode', FWiredApplet.IsPopupOpen());
    AssertNotNull('Wired popup window exists in dark mode', FWiredApplet.PopupWindow);

    FLanApplet.ShowPopup();
    AssertTrue('LAN popup open in dark mode', FLanApplet.IsPopupOpen());
    AssertNotNull('LAN popup window exists in dark mode', FLanApplet.PopupWindow);

    FBluetoothApplet.ShowPopup();
    AssertTrue('Bluetooth popup open in dark mode', FBluetoothApplet.IsPopupOpen());
    AssertNotNull('Bluetooth popup window exists in dark mode', FBluetoothApplet.PopupWindow);

    // Apply theme styling updates popups without error
    FVolumeApplet.ApplyThemeStyle();
    FClockApplet.ApplyThemeStyle();
    FBatteryApplet.ApplyThemeStyle();
    FWiredApplet.ApplyThemeStyle();
    FLanApplet.ApplyThemeStyle();
    FBluetoothApplet.ApplyThemeStyle();
    AssertTrue('Volume popup remains open after ApplyThemeStyle', FVolumeApplet.IsPopupOpen());
    AssertTrue('Clock popup remains open after ApplyThemeStyle', FClockApplet.IsPopupOpen());
    AssertTrue('Battery popup remains open after ApplyThemeStyle', FBatteryApplet.IsPopupOpen());
    AssertTrue('Wired popup remains open after ApplyThemeStyle', FWiredApplet.IsPopupOpen());
    AssertTrue('LAN popup remains open after ApplyThemeStyle', FLanApplet.IsPopupOpen());
    AssertTrue('Bluetooth popup remains open after ApplyThemeStyle', FBluetoothApplet.IsPopupOpen());

    // Switch to light mode and apply theme style
    FtApp().DarkMode := False;
    FVolumeApplet.ApplyThemeStyle();
    FClockApplet.ApplyThemeStyle();
    FBatteryApplet.ApplyThemeStyle();
    FWiredApplet.ApplyThemeStyle();
    FLanApplet.ApplyThemeStyle();
    FBluetoothApplet.ApplyThemeStyle();
    AssertTrue('Volume popup remains open after switching to light mode', FVolumeApplet.IsPopupOpen());
    AssertTrue('Clock popup remains open after switching to light mode', FClockApplet.IsPopupOpen());
    AssertTrue('Battery popup remains open after switching to light mode', FBatteryApplet.IsPopupOpen());
    AssertTrue('Wired popup remains open after switching to light mode', FWiredApplet.IsPopupOpen());
    AssertTrue('LAN popup remains open after switching to light mode', FLanApplet.IsPopupOpen());
    AssertTrue('Bluetooth popup remains open after switching to light mode', FBluetoothApplet.IsPopupOpen());

    // Hide popups
    FVolumeApplet.HidePopup();
    FClockApplet.HidePopup();
    FBatteryApplet.HidePopup();
    FWiredApplet.HidePopup();
    FLanApplet.HidePopup();
    FBluetoothApplet.HidePopup();
    AssertFalse('Volume popup closed', FVolumeApplet.IsPopupOpen());
    AssertFalse('Clock popup closed', FClockApplet.IsPopupOpen());
    AssertFalse('Battery popup closed', FBatteryApplet.IsPopupOpen());
    AssertFalse('Wired popup closed', FWiredApplet.IsPopupOpen());
    AssertFalse('LAN popup closed', FLanApplet.IsPopupOpen());
    AssertFalse('Bluetooth popup closed', FBluetoothApplet.IsPopupOpen());
  finally
    FtApp().DarkMode := savedDark;
  end;
end;

initialization
  RegisterTest(TAppletsTest);
end.
