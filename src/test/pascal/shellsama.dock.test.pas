unit ShellSama.Dock.Test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  ftpas.api, ftpas.types, ftpas,
  ShellSama.DesktopApps,
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
    procedure TestResizeKeepsTheSameWindow();
    procedure TestPinnedAppsAppearWithNothingRunning();
    procedure TestTickDoesNotAccumulatePixmaps();
    procedure TestWideDockScrollsInsteadOfShrinking();
    procedure TestScrollingIsClampedAtBothEnds();
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

  // 66 tall, sitting 8px above the bottom edge, horizontally centred. The taskbar it
  // replaces is a 38px full-width strip flush with the bottom, so these are the
  // numbers that distinguish the two modes.
  //
  // 8 top padding + 48 icon + 2 gap + 6 dot + 2 bottom padding, plus the one row the
  // rounded background spends on its bottom antialiased edge. Both gaps are
  // deliberately tight: the dot belongs to the icon, so a wide margin reads as dead
  // space inside the plate.
  AssertEquals('Dock height', 66, FDock.PanelHeight());
  AssertEquals('Dock bottom margin', sh - 66 - 8, FDock.PanelY());
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

// Resizing the plate must not recreate the window. Recreating it drops its
// _NET_WM_STRUT, so wmsama recomputes the work area without the dock, every
// maximized client expands into the gap and snaps back when the replacement maps.
// That is the flicker reported after opening or closing a window.
//
// The check is a marker the recreated window could not keep: SetupWindow always
// titles the dock 'shellsama-dock', so a custom title surviving the resize proves the
// same window was kept. Comparing the X window id does NOT work -- the server reuses
// ids after a destroy, so that assertion passed even with the window recreated.
procedure TDockTest.TestResizeKeepsTheSameWindow();
var
  beforeW: Integer;
  marker: string;
begin
  AssertNotNull('Dock window exists', FDock.WindowWidget);
  beforeW := FDock.PanelWidth();

  marker := 'dock-marker-survives-resize';
  FDock.WindowWidget.Title := marker;

  // A width change of the kind a task appearing causes.
  FDock.ResizeWindow(beforeW + 54, 66, 100);

  AssertNotNull('Dock window still exists', FDock.WindowWidget);
  AssertEquals('the same window survived the resize: title kept',
               marker, FDock.WindowWidget.Title);
  AssertEquals('panel width followed the resize', beforeW + 54, FDock.PanelWidth());
  AssertEquals('panel height unchanged', 66, FDock.PanelHeight());

  // Put the title back so the rest of the suite sees a normal dock.
  FDock.WindowWidget.Title := 'shellsama-dock';
end;

// A pinned app must be on the dock before it has ever been launched. Entries used to
// be created only from running windows, so at startup -- with nothing running -- the
// dock was empty even though the config listed apps, and a pinned app appeared only
// after it had been opened once and closed again.
procedure TDockTest.TestPinnedAppsAppearWithNothingRunning();
var
  cfgPath: string;
  saved: string;
  had: Boolean;
  f: TStringList;
  dock: TShellDock;
  launcher: TShellLauncher;
  apps: TDesktopAppList;
  key: string;
  i, found: Integer;
begin
  cfgPath := GetEnvironmentVariable('HOME') + '/.config/shellsama/pinned.conf';
  had := FileExists(cfgPath);
  saved := '';
  if had then
  begin
    f := TStringList.Create();
    try
      f.LoadFromFile(cfgPath);
      saved := f.Text;
    finally
      f.Free();
    end;
  end;

  apps := TDesktopAppList.Create();
  try
    apps.LoadAll();
    if apps.AppCount() = 0 then
      raise EIgnoredTest.Create('no desktop entries installed');

    key := apps.GetApp(0).DesktopId;
    ForceDirectories(ExtractFileDir(cfgPath));
    f := TStringList.Create();
    try
      f.Add(key);
      f.SaveToFile(cfgPath);
    finally
      f.Free();
    end;

    launcher := TShellLauncher.Create();
    try
      dock := TShellDock.Create(launcher);
      try
        // Nothing is running in this test process, so the only way an entry can exist
        // is if the pinned list seeded it.
        found := -1;
        for i := 0 to dock.EntryCount() - 1 do
          if SameText(dock.EntryAppKey(i), key) then
            found := i;

        AssertTrue('the pinned app has an entry with nothing running', found >= 0);
        AssertTrue('the entry is marked pinned', dock.EntryPinned(found));
        AssertFalse('the entry is not running', dock.EntryRunning(found));
        AssertEquals('no windows behind it', 0, dock.EntryWindowCountAt(found));
      finally
        dock.Free();
      end;
    finally
      launcher.Free();
    end;
  finally
    apps.Free();
    if had then
    begin
      f := TStringList.Create();
      try
        f.Text := saved;
        f.SaveToFile(cfgPath);
      finally
        f.Free();
      end;
    end
    else if FileExists(cfgPath) then
      DeleteFile(cfgPath);
  end;
end;

procedure TDockTest.TestTickDoesNotAccumulatePixmaps();
var
  first, second: Integer;
begin
  // The dock takes a pixmap name per running window, on the panel timer. The absolute
  // count depends on what is running on the display the suite is pointed at, so the
  // property worth asserting is stability: a steady window set must not add a name on
  // every tick, which is what a leak or a re-capture-every-tick bug would look like.
  FDock.Tick();
  first := FDock.PixmapCount();

  FDock.Tick();
  FDock.Tick();
  second := FDock.PixmapCount();

  AssertEquals('repeated ticks do not accumulate names', first, second);
end;

// Past the width cap the row scrolls rather than shrinking. Shrinking was tried first
// and made a busy dock unreadable; icons now stay at their full size and the row slides.
procedure TDockTest.TestWideDockScrollsInsteadOfShrinking();
var
  launcher: TShellLauncher;
  dock: TShellDock;
  n: Integer;
begin
  launcher := TShellLauncher.Create();
  try
    dock := TShellDock.Create(launcher);
    try
      // A few icons: full size, no scroll.
      dock.DebugPopulateEntries(3);
      AssertEquals('three icons keep full size', 48, dock.LayoutIconSize());
      AssertEquals('nothing to scroll with three icons', 0, dock.MaxScroll());
      AssertEquals('no scroll offset when it fits', 0, dock.ScrollOffset());

      // Enough to overflow the cap: 16*48 + 15*6 + 20 = 878 > 720.
      n := 16;
      dock.DebugPopulateEntries(n);
      AssertEquals('icons are NOT shrunk', 48, dock.LayoutIconSize());
      AssertTrue('there is content to scroll to', dock.MaxScroll() > 0);
      AssertEquals('scroll starts at the beginning',
                   0, dock.ScrollOffset());

      // Scrolling moves the row and the first icon goes left of the padding.
      AssertTrue('scrolling down moves the offset', dock.ScrollBy(54));
      AssertEquals('offset moved by one step', 54, dock.ScrollOffset());
      AssertTrue('the row slid left', dock.LayoutIconX() < 10);
    finally
      dock.Free();
    end;
  finally
    launcher.Free();
  end;
end;

procedure TDockTest.TestScrollingIsClampedAtBothEnds();
var
  launcher: TShellLauncher;
  dock: TShellDock;
begin
  launcher := TShellLauncher.Create();
  try
    dock := TShellDock.Create(launcher);
    try
      dock.DebugPopulateEntries(16);
      AssertTrue('the dock can scroll', dock.MaxScroll() > 0);

      // Far past the end.
      dock.ScrollBy(100000);
      AssertEquals('clamped to the maximum', dock.MaxScroll(), dock.ScrollOffset());
      AssertFalse('further scrolling past the end does nothing', dock.ScrollBy(54));

      // Far past the start.
      dock.ScrollBy(-100000);
      AssertEquals('clamped to zero', 0, dock.ScrollOffset());
      AssertFalse('further scrolling before the start does nothing', dock.ScrollBy(-54));

      // A dock that fits cannot be scrolled at all.
      dock.DebugPopulateEntries(2);
      AssertEquals('nothing to scroll', 0, dock.MaxScroll());
      AssertFalse('scrolling a dock that fits is a no-op', dock.ScrollBy(54));
      AssertEquals('and the offset stays zero', 0, dock.ScrollOffset());
    finally
      dock.Free();
    end;
  finally
    launcher.Free();
  end;
end;

initialization
  RegisterTest(TDockTest);
end.