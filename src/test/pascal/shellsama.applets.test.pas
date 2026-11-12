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
    FTestWin      : TFtWindow;
    FVolumeApplet : TShellVolumeApplet;
    FClockApplet  : TShellClockApplet;
    FSessionApplet: TShellSessionApplet;
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

  FTestWin := TFtWindow.Create(400, 100, 'test-applets-window');
  FVolumeApplet := TShellVolumeApplet.Create(FTestWin, 10, 10, 32, 28);
  FClockApplet := TShellClockApplet.Create(FTestWin, 50, 10, 80, 28);
  FSessionApplet := TShellSessionApplet.Create(FTestWin, 140, 10, 32, 28);
end;

procedure TAppletsTest.TearDown();
begin
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

    // Apply theme styling updates popups without error
    FVolumeApplet.ApplyThemeStyle();
    FClockApplet.ApplyThemeStyle();
    AssertTrue('Volume popup remains open after ApplyThemeStyle', FVolumeApplet.IsPopupOpen());
    AssertTrue('Clock popup remains open after ApplyThemeStyle', FClockApplet.IsPopupOpen());

    // Switch to light mode and apply theme style
    FtApp().DarkMode := False;
    FVolumeApplet.ApplyThemeStyle();
    FClockApplet.ApplyThemeStyle();
    AssertTrue('Volume popup remains open after switching to light mode', FVolumeApplet.IsPopupOpen());
    AssertTrue('Clock popup remains open after switching to light mode', FClockApplet.IsPopupOpen());

    // Hide popups
    FVolumeApplet.HidePopup();
    FClockApplet.HidePopup();
    AssertFalse('Volume popup closed', FVolumeApplet.IsPopupOpen());
    AssertFalse('Clock popup closed', FClockApplet.IsPopupOpen());

    // Reopen in dark mode from closed state
    FtApp().DarkMode := True;
    FVolumeApplet.ShowPopup();
    FClockApplet.ShowPopup();
    AssertTrue('Volume popup reopened in dark mode', FVolumeApplet.IsPopupOpen());
    AssertTrue('Clock popup reopened in dark mode', FClockApplet.IsPopupOpen());

    FVolumeApplet.HidePopup();
    FClockApplet.HidePopup();
  finally
    FtApp().DarkMode := savedDark;
  end;
end;

initialization
  RegisterTest(TAppletsTest);
end.
