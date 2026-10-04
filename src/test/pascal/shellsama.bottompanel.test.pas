unit ShellSama.BottomPanel.Test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  ShellSama.LibFt,
  ShellSama.Launcher,
  ShellSama.BottomPanel;

type
  TBottomPanelTest = class(TTestCase)
  private
    FLauncher: TShellLauncher;
    FPanel   : TShellBottomPanel;
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
  end;

implementation

procedure TBottomPanelTest.SetUp();
begin
  if not IsLibFtLoaded() then
  begin
    if not LoadLibFt() then
      Fail('Could not load libft.so');
  end;

  try
    ft_init();
  except
    on E: Exception do
      Fail('ft_init failed: ' + E.Message);
  end;

  FLauncher := TShellLauncher.Create();
  FPanel := TShellBottomPanel.Create(FLauncher);
end;

procedure TBottomPanelTest.TearDown();
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

procedure TBottomPanelTest.TestPanelCreationAndGeometry();
var
  sw, sh: Integer;
begin
  AssertNotNull('Panel instance should be created', FPanel);
  sw := ft_screen_get_width();
  sh := ft_screen_get_height();

  AssertEquals('Panel X must be 0', 0, FPanel.PanelX());
  AssertEquals('Panel Y must be at bottom of screen', sh - 38, FPanel.PanelY());
  AssertEquals('Panel Width must match screen width', sw, FPanel.PanelWidth());
  AssertEquals('Panel Height must be 38', 38, FPanel.PanelHeight());
end;

procedure TBottomPanelTest.TestWidgetsInitialized();
begin
  AssertNotNull('Window widget must be created', FPanel.WindowWidget);
  AssertNotNull('Launcher button must be created', FPanel.LauncherWidget);
  AssertNotNull('Clock text widget must be created', FPanel.ClockWidget);
end;

procedure TBottomPanelTest.TestPanelVisibilityToggle();
begin
  AssertFalse('Panel should start hidden', FPanel.IsVisible);

  FPanel.Show();
  AssertTrue('Panel should be visible after Show()', FPanel.IsVisible);

  FPanel.Hide();
  AssertFalse('Panel should be hidden after Hide()', FPanel.IsVisible);
end;

procedure TBottomPanelTest.TestClockUpdate();
begin
  // UpdateClock should run without exception
  FPanel.UpdateClock();
  AssertNotNull('Clock widget still valid', FPanel.ClockWidget);
end;

procedure TBottomPanelTest.TestLauncherSync();
begin
  AssertFalse('Launcher should start hidden', FLauncher.IsVisible);

  // Click launcher from bottom panel
  FPanel.OnLauncherClicked();
  AssertTrue('Launcher should now be visible after bottom panel launcher clicked', FLauncher.IsVisible);

  // Toggle off
  FPanel.OnLauncherClicked();
  AssertFalse('Launcher should now be hidden after second click', FLauncher.IsVisible);
end;

procedure TBottomPanelTest.TestTickExecution();
begin
  // Tick should handle clock and task checks gracefully
  FPanel.Tick();
  AssertNotNull('Panel remains valid after Tick', FPanel);
end;

initialization
  RegisterTest(TBottomPanelTest);
end.
