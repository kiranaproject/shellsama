unit ShellSama.Dock.Test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  ftpas.api, ftpas.types, ftpas,
  ShellSama.Launcher,
  ShellSama.BottomPanel,
  ShellSama.Dock;

type
  TDockTest = class(TTestCase)
  private
    FLauncher: TShellLauncher;
    FDock    : TShellDock;
  protected
    procedure SetUp(); override;
    procedure TearDown(); override;
  published
    procedure TestDockGeometry();
    procedure TestDockIsATaskSurface();
    procedure TestDockWindowIdentity();
    procedure TestDockPlateWidthMatchesContents();
    procedure TestDockTickIsSafe();
  end;

implementation

procedure TDockTest.SetUp();
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
  FDock := TShellDock.Create(FLauncher);
end;

procedure TDockTest.TearDown();
begin
  if Assigned(FDock) then
  begin
    FDock.Free();
    FDock := nil;
  end;
  if Assigned(FLauncher) then
  begin
    FLauncher.Free();
    FLauncher := nil;
  end;
end;

procedure TDockTest.TestDockGeometry();
var
  sh, sw: Integer;
begin
  AssertNotNull('Dock created', FDock);
  sw := FtApp().ScreenWidth;
  sh := FtApp().ScreenHeight;

  // 78 tall, sitting 8px above the bottom edge, horizontally centred. The taskbar
  // it replaces is a 38px full-width strip flush with the bottom, so these are the
  // numbers that distinguish the two modes.
  AssertEquals('Dock height', 78, FDock.PanelHeight());
  AssertEquals('Dock bottom margin', sh - 78 - 8, FDock.PanelY());
  AssertEquals('Dock is centred', (sw - FDock.PanelWidth()) div 2, FDock.PanelX());
  AssertEquals('Dock X is not the taskbar X', False, FDock.PanelX() = 0);
end;

procedure TDockTest.TestDockIsATaskSurface();
begin
  // The dock must stay a descendant of the taskbar: the EWMH task model, the
  // context menus and the window actions are inherited, not copied. If this ever
  // stops holding, the dock has been duplicated rather than derived.
  AssertTrue('Dock descends from the task surface', FDock is TShellTaskSurface);
  AssertTrue('Dock descends from the bottom panel', FDock is TShellBottomPanel);
  AssertEquals('Task count is non-negative', True, FDock.TaskCount >= 0);
end;

procedure TDockTest.TestDockWindowIdentity();
begin
  AssertNotNull('Dock window exists', FDock.WindowWidget);
  AssertEquals('Dock window title', 'shellsama-dock', FDock.WindowWidget.Title);
  AssertEquals('Dock plate opacity', 0.82, FDock.WindowWidget.BackgroundOpacity, 0.001);
  AssertEquals('Icon size', 48, FDock.IconSize);
end;

procedure TDockTest.TestDockPlateWidthMatchesContents();
var
  w: Integer;
begin
  // The plate follows its contents: padding + n icons + gaps, capped. The suite runs
  // against a live display, so the task count is whatever windows exist rather than
  // zero; the relationship is what is under test, not a specific number.
  //
  // For n >= 1 that width is 2*10 + 48n + 6(n-1) = 14 + 54n, so an uncapped plate is
  // always 14 mod 54.
  w := FDock.PanelWidth();
  AssertTrue('Plate is at least one icon plus padding', w >= 48 + 20);
  AssertTrue('Plate never exceeds the cap', w <= FDock.MaxDockWidth);
  if w < FDock.MaxDockWidth then
    AssertEquals('Uncapped plate width follows 14 + 54n', 0, (w - 14) mod 54);
end;

procedure TDockTest.TestDockTickIsSafe();
begin
  // Tick queries X and re-lays out on change. On a display with no clients it must
  // be a no-op rather than a crash, which is what the rebuild path used to do.
  FDock.Tick();
  AssertNotNull('Dock survives Tick', FDock);
  FDock.RefreshTasks();
  AssertNotNull('Dock survives RefreshTasks', FDock);
end;

initialization
  RegisterTest(TDockTest);
end.