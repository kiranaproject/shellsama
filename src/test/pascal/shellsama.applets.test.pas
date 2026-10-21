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
    FSessionApplet: TShellSessionApplet;
  protected
    procedure SetUp(); override;
    procedure TearDown(); override;
  published
    procedure TestVolumeAppletCreation();
    procedure TestVolumeAppletGlyphsAndMute();
    procedure TestVolumePopupLifecycle();
    procedure TestSessionAppletCreationAndMenu();
    procedure TestSessionAppletBounds();
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
  FSessionApplet := TShellSessionApplet.Create(FTestWin, 50, 10, 32, 28);
end;

procedure TAppletsTest.TearDown();
begin
  if Assigned(FSessionApplet) then
  begin
    FSessionApplet.Free();
    FSessionApplet := nil;
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
  // Muted state -> '🔇'
  FVolumeApplet.SetVolumeState(75, True);
  AssertTrue('Applet should report muted', FVolumeApplet.IsMuted);
  AssertEquals('Muted button glyph must be 🔇', '🔇', FVolumeApplet.Button.Caption);

  // Unmuted low volume (< 33) -> '🔈'
  FVolumeApplet.SetVolumeState(20, False);
  AssertFalse('Applet should report unmuted', FVolumeApplet.IsMuted);
  AssertEquals('Low volume button glyph must be 🔈', '🔈', FVolumeApplet.Button.Caption);

  // Unmuted medium volume (33..65) -> '🔉'
  FVolumeApplet.SetVolumeState(50, False);
  AssertEquals('Medium volume button glyph must be 🔉', '🔉', FVolumeApplet.Button.Caption);

  // Unmuted high volume (>= 66) -> '🔊'
  FVolumeApplet.SetVolumeState(85, False);
  AssertEquals('High volume button glyph must be 🔊', '🔊', FVolumeApplet.Button.Caption);
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

procedure TAppletsTest.TestSessionAppletCreationAndMenu();
begin
  AssertNotNull('Session applet must be created', FSessionApplet);
  AssertNotNull('Session button must be created', FSessionApplet.Button);
  AssertEquals('Session button caption must be ⏻', '⏻', FSessionApplet.Button.Caption);

  AssertNotNull('Session popup menu must be created', FSessionApplet.Menu);
  AssertEquals('Session menu should contain 6 items', 6, FSessionApplet.Menu.ItemCount);

  // Verify key menu items
  AssertEquals('Item 0 should be Lock Screen', 'Lock Screen', FSessionApplet.Menu.Items[0].Caption);
  AssertEquals('Item 1 should be Suspend', 'Suspend', FSessionApplet.Menu.Items[1].Caption);
  AssertEquals('Item 2 should be Log Out...', 'Log Out...', FSessionApplet.Menu.Items[2].Caption);
  // Item 3 is separator
  AssertEquals('Item 4 should be Restart...', 'Restart...', FSessionApplet.Menu.Items[4].Caption);
  AssertEquals('Item 5 should be Shut Down...', 'Shut Down...', FSessionApplet.Menu.Items[5].Caption);
end;

procedure TAppletsTest.TestSessionAppletBounds();
begin
  FSessionApplet.SetBounds(100, 2, 34, 30);
  AssertEquals('Session button X updated', 100, FSessionApplet.Button.X);
  AssertEquals('Session button Y updated', 2, FSessionApplet.Button.Y);
  AssertEquals('Session button W updated', 34, FSessionApplet.Button.Width);
  AssertEquals('Session button H updated', 30, FSessionApplet.Button.Height);
end;

initialization
  RegisterTest(TAppletsTest);
end.
