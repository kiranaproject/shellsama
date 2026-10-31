unit ShellSama.BottomPanel.Test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  ftpas.api, ftpas.types, ftpas,
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
    procedure TestTickExecution();
    procedure TestWindowIconQueryAndCache();
  end;

implementation

procedure TBottomPanelTest.SetUp();
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
  sw := FtApp().ScreenWidth;
  sh := FtApp().ScreenHeight;

  AssertEquals('Panel X must be 0', 0, FPanel.PanelX());
  AssertEquals('Panel Y must be at bottom of screen', sh - 38, FPanel.PanelY());
  AssertEquals('Panel Width must match screen width', sw, FPanel.PanelWidth());
  AssertEquals('Panel Height must be 38', 38, FPanel.PanelHeight());
  AssertEquals('Panel background opacity must be 0.90', 0.90, FPanel.BackgroundOpacity, 0.001);
  AssertEquals('Window widget background opacity must be 0.90', 0.90, FPanel.WindowWidget.BackgroundOpacity, 0.001);
end;

procedure TBottomPanelTest.TestWidgetsInitialized();
begin
  AssertNotNull('Window widget must be created', FPanel.WindowWidget);
  AssertTrue('Task count is non-negative', FPanel.TaskCount >= 0);
end;

procedure TBottomPanelTest.TestPanelVisibilityToggle();
begin
  AssertFalse('Panel should start hidden', FPanel.IsVisible);

  FPanel.Show();
  AssertTrue('Panel should be visible after Show()', FPanel.IsVisible);

  FPanel.Hide();
  AssertFalse('Panel should be hidden after Hide()', FPanel.IsVisible);
end;

procedure TBottomPanelTest.TestTickExecution();
begin
  // Tick should handle task checks gracefully
  FPanel.Tick();
  AssertNotNull('Panel remains valid after Tick', FPanel);
end;

procedure TBottomPanelTest.TestWindowIconQueryAndCache();
var
  fallbackBmp: TFtBitmap;
begin
  // Query for a non-existent or 0 window returns fallback icon
  fallbackBmp := FPanel.QueryWindowIcon(0, 18);
  AssertNotNull('QueryWindowIcon(0) should return fallback icon', fallbackBmp);
  AssertEquals('Fallback icon width is 18', 18, fallbackBmp.Width);
  AssertEquals('Fallback icon height is 18', 18, fallbackBmp.Height);
  fallbackBmp.Free();

  // Calling RefreshTasks updates tasks and layout without exception
  FPanel.RefreshTasks();
  AssertTrue('Icon cache count >= 0', FPanel.IconCacheCount >= 0);
end;

initialization
  RegisterTest(TBottomPanelTest);
end.
