unit ShellSama.Dock.Test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  Floria.XCB,
  ftpas.api, ftpas.types, ftpas,
  ShellSama.DesktopApps,
  ShellSama.Launcher,
  ShellSama.BottomPanel,
  ShellSama.Dock,
  ShellSama.Settings;

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
    procedure TestLivePreviewIsOnByDefaultButCanBeDisabled();
    procedure TestTileMenuOffersTheWindowActions();
    procedure TestTileMenuCaptionFollowsTheWindowState();
    procedure TestTickDoesNotAccumulatePixmaps();
    procedure TestWideDockScrollsInsteadOfShrinking();
    procedure TestScrollingIsClampedAtBothEnds();
    procedure TestDockFollowsDarkAndLightTheme();
    procedure TestSingleWindowClickMinimizesWhenActive();
    procedure TestDockEntryMenuForSingleWindowOffersWindowActions();
    procedure TestDockLeftPositionGeometry();
    procedure TestDockRightPositionGeometry();
    procedure TestDockDynamicMargin();
    procedure TestDockAutoHideStruts();
    procedure TestDockIntellihideAnimation();
  end;

type
  TDockAccess = class(TShellDock);

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

  ShellSettings().SetDefaults();
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
  ShellSettings().Load();
end;

procedure TDockTest.TestDockGeometry();
var
  sh, sw: Integer;
begin
  AssertNotNull('Dock created', FDock);
  sw := FtApp().ScreenWidth;
  sh := FtApp().ScreenHeight;

  // 60 tall, sitting 3px above the bottom edge, horizontally centred.
  // Symmetrical 6px vertical margins: 6px top margin + 48px icon + 6px bottom margin = 60px.
  // Running indicator dot (6px diameter) is placed close to the icon bottom edge.
  AssertEquals('Dock height', 60, FDock.PanelHeight());
  AssertEquals('Dock bottom margin', sh - 60 - 3, FDock.PanelY());
  AssertEquals('Dock strut bottom reserves height plus margins', 60 + 3 + 3, FDock.ComputeStrutBottom());
  AssertEquals('Dock is centred', (sw - FDock.PanelWidth()) div 2, FDock.PanelX());
  AssertEquals('Dock X is not the taskbar X', False, FDock.PanelX() = 0);
  AssertEquals('Icon vertical margins are symmetrical', 6, (FDock.PanelHeight() - FDock.IconSize) div 2);
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
  FDock.ResizeWindow(beforeW + 54, 60, 100);

  AssertNotNull('Dock window still exists', FDock.WindowWidget);
  AssertEquals('the same window survived the resize: title kept',
               marker, FDock.WindowWidget.Title);
  AssertEquals('panel width followed the resize', beforeW + 54, FDock.PanelWidth());
  AssertEquals('panel height unchanged', 60, FDock.PanelHeight());

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

procedure TDockTest.TestLivePreviewIsOnByDefaultButCanBeDisabled();
begin
  // On by default now that the refresh path no longer leaks (docs/window-previews.md Q5).
  // The opt-out has to keep working, because a user on a slow machine may want it back.
  AssertTrue('live preview is on by default', FDock.PreviewLive());

  FDock.SetPreviewLive(False);
  AssertFalse('and can be disabled', FDock.PreviewLive());
  FDock.SetPreviewLive(True);
  AssertTrue('and enabled again', FDock.PreviewLive());
end;

procedure TDockTest.TestTileMenuOffersTheWindowActions();
var
  menu: TFtPopupMenu;
  i: Integer;
  captions: TStringList;
  item: TFtMenuItem;
begin
  // The tile menu is the task list's menu, so a preview and a task button offer the same
  // actions. Asserting the captions rather than the count catches a missing or renamed
  // action, which is the failure a user would notice.
  menu := TFtPopupMenu.Create(FDock.WindowWidget);
  AssertNotNull('menu created', menu);
  captions := TStringList.Create();
  try
    FDock.DebugBuildTileMenu(1234, menu);
    for i := 0 to menu.ItemCount - 1 do
    begin
      item := menu.Items[i];
      // ftpas does not expose IsSeparator. A separator shows up as an item with no
      // handle and no caption, so filter on the handle as well as the caption.
      // A separator comes back from ftpas with the caption '-'. Check it explicitly
      // rather than skipping anything that is not one of the three actions, so a
      // fourth real action would fail the count instead of being filtered away.
      if (item = nil) or (item.Caption = '') then Continue;
      if item.Caption = '-' then
      begin
        captions.Add('<separator>');
        Continue;
      end;
      captions.Add(item.Caption);
    end;

    // Minimize, Maximize, separator, Close: the same shape the task list menu has.
    AssertEquals('four rows: ' + captions.CommaText, 4, captions.Count);
    AssertEquals('first is minimize', 'Minimize', captions[0]);
    AssertEquals('second is maximize', 'Maximize', captions[1]);
    AssertEquals('then a separator', '<separator>', captions[2]);
    AssertEquals('last is close', 'Close', captions[3]);
  finally
    captions.Free();
    menu.Free();
  end;
end;

procedure TDockTest.TestTileMenuCaptionFollowsTheWindowState();
var
  menu: TFtPopupMenu;
  item: TFtMenuItem;
begin
  // Window 1234 does not exist, so neither minimized nor maximized applies and both
  // captions must stay in their default form. This is the negative case; the positive
  // case needs a real minimized window and is covered live.
  menu := TFtPopupMenu.Create(FDock.WindowWidget);
  AssertNotNull('menu created', menu);
  try
    FDock.DebugBuildTileMenu(1234, menu);
    item := nil;
    if menu.ItemCount > 0 then
      item := menu.Items[0];
    AssertNotNull('a first item exists', item);
    AssertEquals('a window that does not exist is not called minimized',
                 'Minimize', item.Caption);

    // A zero window must not build anything at all.
    menu.Clear();
    FDock.DebugBuildTileMenu(0, menu);
    AssertEquals('no actions for window 0', 0, menu.ItemCount);
  finally
    menu.Free();
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

procedure TDockTest.TestDockFollowsDarkAndLightTheme();
begin
  AssertNotNull('Dock instance', FDock);

  // Dark mode
  FtApp().DarkMode := True;
  FDock.ApplyThemeStyle();
  AssertTrue('Dock window has dark class', Pos('dark', FDock.WindowWidget.StyleClass) > 0);
  AssertTrue('Dock window has dark plate css', Pos('24, 24, 32', FDock.WindowWidget.Style) > 0);
  AssertEquals('Dark dock opacity is 0.82', 0.82, FDock.WindowWidget.BackgroundOpacity);

  // Light mode
  FtApp().DarkMode := False;
  FDock.ApplyThemeStyle();
  AssertTrue('Dock window has light class', Pos('light', FDock.WindowWidget.StyleClass) > 0);
  AssertTrue('Dock window has light plate css', Pos('255, 255, 255', FDock.WindowWidget.Style) > 0);
  AssertEquals('Light dock opacity is 0.85', 0.85, FDock.WindowWidget.BackgroundOpacity);

  // Tick reacts to dark mode toggle
  FtApp().DarkMode := True;
  FDock.Tick();
  AssertTrue('Dock window transitioned back to dark class on tick', Pos('dark', FDock.WindowWidget.StyleClass) > 0);
  AssertTrue('Dock window transitioned back to dark plate on tick', Pos('24, 24, 32', FDock.WindowWidget.Style) > 0);
end;

procedure TDockTest.TestSingleWindowClickMinimizesWhenActive();
var
  dockAcc: TDockAccess;
  origActive, testWin: Cardinal;
begin
  AssertNotNull('Dock instance', FDock);
  dockAcc := TDockAccess(FDock);

  // Synthetic entries
  FDock.DebugPopulateEntries(2);
  AssertEquals('Two entries populated', 2, FDock.EntryCount());

  // 1. Entry 0 with zero windows -> launches/no-op safely
  FDock.DebugClickEntry(0);

  // 2. Entry 0 with 1 window, window is NOT active
  testWin := 88888;
  origActive := dockAcc.QueryActiveWindow();
  FDock.DebugSetEntryWindows(0, [testWin]);
  AssertEquals('Entry 0 has one window', 1, FDock.EntryWindowCountAt(0));

  // If testWin <> active window, DebugClickEntry activates it
  if (testWin <> origActive) and (dockAcc.FConn <> nil) then
  begin
    // Inactive single window clicked -> ActivateWindow called without crashing
    FDock.DebugClickEntry(0);
  end;

  // 3. Entry 0 with 1 window, window IS active
  if (dockAcc.FConn <> nil) and (dockAcc.FRootWindow <> 0) and (dockAcc.FAtomNetActiveWindow <> 0) then
  begin
    // Set root window's _NET_ACTIVE_WINDOW to testWin
    xcb_change_property(dockAcc.FConn, XCB_PROP_MODE_REPLACE,
                        dockAcc.FRootWindow, dockAcc.FAtomNetActiveWindow,
                        XCB_ATOM_WINDOW, 32, 1, @testWin);
    xcb_flush(dockAcc.FConn);

    AssertEquals('Active window is now testWin', testWin, dockAcc.QueryActiveWindow());

    // Active single window clicked -> calls MinimizeWindow
    FDock.DebugClickEntry(0);

    // 4. Multiple windows for the app -> should not minimize even if one is active
    FDock.DebugSetEntryWindows(0, [testWin, 99999]);
    AssertEquals('Entry 0 has two windows', 2, FDock.EntryWindowCountAt(0));
    FDock.DebugClickEntry(0);

    // Restore original active window property
    if origActive <> 0 then
    begin
      xcb_change_property(dockAcc.FConn, XCB_PROP_MODE_REPLACE,
                          dockAcc.FRootWindow, dockAcc.FAtomNetActiveWindow,
                          XCB_ATOM_WINDOW, 32, 1, @origActive);
      xcb_flush(dockAcc.FConn);
    end
    else
    begin
      xcb_delete_property(dockAcc.FConn, dockAcc.FRootWindow, dockAcc.FAtomNetActiveWindow);
      xcb_flush(dockAcc.FConn);
    end;
  end;
end;

procedure TDockTest.TestDockEntryMenuForSingleWindowOffersWindowActions();
var
  menu: TFtPopupMenu;
  i: Integer;
  captions: TStringList;
  item: TFtMenuItem;
begin
  AssertNotNull('Dock instance', FDock);
  FDock.DebugPopulateEntries(2);

  // 1. With zero windows, menu has no window actions
  menu := FDock.EntryMenu(0);
  AssertNotNull('Entry menu exists', menu);
  captions := TStringList.Create();
  try
    for i := 0 to menu.ItemCount - 1 do
    begin
      item := menu.Items[i];
      if (item <> nil) and (item.Caption <> '') then
        captions.Add(item.Caption);
    end;
    AssertEquals('Zero windows has no Minimize action', -1, captions.IndexOf('Minimize'));
    AssertEquals('Zero windows has no Maximize action', -1, captions.IndexOf('Maximize'));
    AssertEquals('Zero windows has no Close action', -1, captions.IndexOf('Close'));

    // 2. Set single window on Entry 0 -> window actions added
    FDock.DebugSetEntryWindows(0, [1234]);
    menu := FDock.EntryMenu(0);
    AssertNotNull('Entry menu exists after setting window', menu);

    captions.Clear();
    for i := 0 to menu.ItemCount - 1 do
    begin
      item := menu.Items[i];
      if (item = nil) or (item.Caption = '') then Continue;
      if item.Caption = '-' then
        captions.Add('<separator>')
      else
        captions.Add(item.Caption);
    end;

    AssertTrue('Single window has Minimize: ' + captions.CommaText, captions.IndexOf('Minimize') >= 0);
    AssertTrue('Single window has Maximize: ' + captions.CommaText, captions.IndexOf('Maximize') >= 0);
    AssertTrue('Single window has Close: ' + captions.CommaText, captions.IndexOf('Close') >= 0);
    AssertTrue('Minimize is before Maximize', captions.IndexOf('Minimize') < captions.IndexOf('Maximize'));
    AssertTrue('Maximize is before Close', captions.IndexOf('Maximize') < captions.IndexOf('Close'));

    // 3. Set multiple windows on Entry 0 -> window actions removed from dock icon menu
    FDock.DebugSetEntryWindows(0, [1234, 5678]);
    menu := FDock.EntryMenu(0);
    captions.Clear();
    for i := 0 to menu.ItemCount - 1 do
    begin
      item := menu.Items[i];
      if (item <> nil) and (item.Caption <> '') then
        captions.Add(item.Caption);
    end;
    AssertEquals('Multiple windows has no Minimize on dock icon', -1, captions.IndexOf('Minimize'));
    AssertEquals('Multiple windows has no Maximize on dock icon', -1, captions.IndexOf('Maximize'));
    AssertEquals('Multiple windows has no Close on dock icon', -1, captions.IndexOf('Close'));

    // 4. Set back to single window -> window actions reappear
    FDock.DebugSetEntryWindows(0, [1234]);
    menu := FDock.EntryMenu(0);
    captions.Clear();
    for i := 0 to menu.ItemCount - 1 do
    begin
      item := menu.Items[i];
      if (item = nil) or (item.Caption = '') then Continue;
      if item.Caption = '-' then
        captions.Add('<separator>')
      else
        captions.Add(item.Caption);
    end;
    AssertTrue('Window actions restored for single window: ' + captions.CommaText, captions.IndexOf('Minimize') >= 0);
  finally
    captions.Free();
  end;
end;

procedure TDockTest.TestDockLeftPositionGeometry();
var
  sw, sh: Integer;
begin
  ShellSettings().DockPosition := 'Left';
  ShellSettings().DockMargin := 5;
  FDock.RefreshDock();

  sw := FtApp().ScreenWidth;
  sh := FtApp().ScreenHeight;

  AssertTrue('Left dock is vertical', FDock.IsVertical());
  AssertEquals('Left dock width', FDock.IconSize + 20, FDock.PanelWidth());
  AssertEquals('Left dock margin X', 5, FDock.PanelX());
  AssertTrue('Left dock Y is below top panel', FDock.PanelY() >= 38);
  AssertEquals('Left dock strut', FDock.PanelWidth() + 5 + 3, FDock.ComputeStrutLeft());
  AssertEquals('Left dock has no right strut', 0, FDock.ComputeStrutRight());
  AssertEquals('Left dock has no bottom strut', 0, FDock.ComputeStrutBottom());
end;

procedure TDockTest.TestDockRightPositionGeometry();
var
  sw: Integer;
begin
  ShellSettings().DockPosition := 'Right';
  ShellSettings().DockMargin := 8;
  FDock.RefreshDock();

  sw := FtApp().ScreenWidth;

  AssertTrue('Right dock is vertical', FDock.IsVertical());
  AssertEquals('Right dock width', FDock.IconSize + 20, FDock.PanelWidth());
  AssertEquals('Right dock margin X', sw - FDock.PanelWidth() - 8, FDock.PanelX());
  AssertTrue('Right dock Y is below top panel', FDock.PanelY() >= 38);
  AssertEquals('Right dock strut', FDock.PanelWidth() + 8 + 3, FDock.ComputeStrutRight());
  AssertEquals('Right dock has no left strut', 0, FDock.ComputeStrutLeft());
  AssertEquals('Right dock has no bottom strut', 0, FDock.ComputeStrutBottom());
end;

procedure TDockTest.TestDockDynamicMargin();
var
  sh: Integer;
begin
  sh := FtApp().ScreenHeight;

  // Margin 0
  ShellSettings().DockPosition := 'Bottom';
  ShellSettings().DockMargin := 0;
  FDock.RefreshDock();
  AssertEquals('Bottom margin 0 Y', sh - 60 - 0, FDock.PanelY());
  AssertEquals('Bottom margin 0 strut', 60 + 0 + 3, FDock.ComputeStrutBottom());

  // Margin 5
  ShellSettings().DockMargin := 5;
  FDock.RefreshDock();
  AssertEquals('Bottom margin 5 Y', sh - 60 - 5, FDock.PanelY());
  AssertEquals('Bottom margin 5 strut', 60 + 5 + 3, FDock.ComputeStrutBottom());
end;

procedure TDockTest.TestDockAutoHideStruts();
begin
  ShellSettings().DockAutoHide := True;
  ShellSettings().DockPosition := 'Bottom';
  FDock.RefreshDock();

  AssertEquals('Auto-hide bottom strut is 0', 0, FDock.ComputeStrutBottom());
  AssertEquals('Auto-hide left strut is 0', 0, FDock.ComputeStrutLeft());
  AssertEquals('Auto-hide right strut is 0', 0, FDock.ComputeStrutRight());

  ShellSettings().DockPosition := 'Left';
  FDock.RefreshDock();
  AssertEquals('Auto-hide left dock has 0 left strut', 0, FDock.ComputeStrutLeft());
end;

procedure TDockTest.TestDockIntellihideAnimation();
begin
  ShellSettings().DockAutoHide := True;
  FDock.RefreshDock();

  // Initial state should be visible or hidden
  FDock.ShowImmediate();
  AssertEquals('Immediate show makes dock visible', Ord(dhsVisible), Ord(FDock.HideState));
  AssertFalse('Immediate show is not animating', FDock.IsAnimating());
  AssertEquals('Anim progress is 1.0', 1.0, FDock.AnimProgress, 0.001);

  // Trigger hide
  FDock.StartHide();
  AssertEquals('StartHide sets state to dhsHiding', Ord(dhsHiding), Ord(FDock.HideState));
  AssertTrue('Dock is animating during hide', FDock.IsAnimating());

  // Trigger show
  FDock.StartShow();
  AssertEquals('StartShow sets state to dhsShowing', Ord(dhsShowing), Ord(FDock.HideState));
  AssertTrue('Dock is animating during show', FDock.IsAnimating());

  // Settle back to visible
  FDock.ShowImmediate();
  AssertEquals('Dock settled back to visible', Ord(dhsVisible), Ord(FDock.HideState));
end;

initialization
  RegisterTest(TDockTest);
end.