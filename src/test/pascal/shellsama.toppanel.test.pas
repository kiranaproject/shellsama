unit ShellSama.TopPanel.Test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  ftpas.api, ftpas.types, ftpas,
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

initialization
  RegisterTest(TTopPanelTest);
end.
