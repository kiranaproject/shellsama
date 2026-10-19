unit ShellSama.Launcher.Test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  ftpas.api, ftpas.types, ftpas,
  ShellSama.DesktopApps,
  ShellSama.Launcher;

type
  TLauncherTest = class(TTestCase)
  private
    FLauncher: TShellLauncher;
  protected
    procedure SetUp(); override;
    procedure TearDown(); override;
  published
    procedure TestLibFtLoaded();
    procedure TestLauncherInitialState();
    procedure TestLauncherSearchFiltering();
    procedure TestLauncherNavigation();
    procedure TestLauncherPageNavigation();
    procedure TestLauncherVirtualScrollOffset();
    procedure TestLauncherToggleAndVisibility();
    procedure TestLauncherAppIcons();
  end;

implementation

procedure TLauncherTest.SetUp();
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
end;

procedure TLauncherTest.TearDown();
begin
  if Assigned(FLauncher) then
  begin
    FLauncher.Free();
    FLauncher := nil;
  end;
end;

procedure TLauncherTest.TestLibFtLoaded();
begin
  AssertTrue('libft.so should be loaded', FtIsLibLoaded());
  AssertNotNull('ft_init should be bound', Pointer(ft_init));
  AssertNotNull('ft_window_create should be bound', Pointer(ft_window_create));
  AssertNotNull('ft_entry_create should be bound', Pointer(ft_entry_create));
  AssertNotNull('ft_button_create should be bound', Pointer(ft_button_create));
  AssertNotNull('ft_screen_get_width should be bound', Pointer(ft_screen_get_width));
  AssertNotNull('ft_screen_get_height should be bound', Pointer(ft_screen_get_height));
  AssertTrue('Screen width > 0', ft_screen_get_width() > 0);
  AssertTrue('Screen height > 0', ft_screen_get_height() > 0);
end;

procedure TLauncherTest.TestLauncherInitialState();
begin
  AssertNotNull('Launcher instance created', FLauncher);
  AssertFalse('Launcher should not be visible initially', FLauncher.IsVisible);
  AssertEquals('Initial selected index is 0', 0, FLauncher.SelectedIndex);
  AssertEquals('Initial scroll offset is 0', 0, FLauncher.ScrollOffset);
  AssertTrue('Results count >= 0', FLauncher.ResultsCount >= 0);
end;

procedure TLauncherTest.TestLauncherSearchFiltering();
var
  origCount: Integer;
begin
  origCount := FLauncher.ResultsCount;

  // Search for an unlikely string to test empty filter
  FLauncher.HandleSearchChanged('__xyz_non_existent_app_query__');
  AssertEquals('Non-existent query should yield 0 results', 0, FLauncher.ResultsCount);
  AssertEquals('Selected index resets to 0', 0, FLauncher.SelectedIndex);
  AssertEquals('Scroll offset resets to 0', 0, FLauncher.ScrollOffset);

  // Clear search query
  FLauncher.HandleSearchChanged('');
  AssertEquals('Empty query restores original results count', origCount, FLauncher.ResultsCount);
end;

procedure TLauncherTest.TestLauncherNavigation();
var
  count: Integer;
begin
  count := FLauncher.ResultsCount;
  if count < 2 then
    Exit; // Not enough items to test navigation

  // Initial
  AssertEquals('Start at 0', 0, FLauncher.SelectedIndex);

  // Next
  FLauncher.SelectNext();
  AssertEquals('Moved to 1', 1, FLauncher.SelectedIndex);

  // Prev
  FLauncher.SelectPrev();
  AssertEquals('Moved back to 0', 0, FLauncher.SelectedIndex);

  // Wrap around backwards (from 0 to count - 1)
  FLauncher.SelectPrev();
  AssertEquals('Wrapped to last item', count - 1, FLauncher.SelectedIndex);

  // Wrap around forwards (from count - 1 to 0)
  FLauncher.SelectNext();
  AssertEquals('Wrapped to first item', 0, FLauncher.SelectedIndex);
end;

procedure TLauncherTest.TestLauncherPageNavigation();
var
  count: Integer;
begin
  count := FLauncher.ResultsCount;
  if count <= LAUNCHER_VISIBLE_ITEMS then
    Exit;

  // Page Down from 0
  FLauncher.SelectPageDown();
  AssertEquals('Page down moves by LAUNCHER_VISIBLE_ITEMS', LAUNCHER_VISIBLE_ITEMS, FLauncher.SelectedIndex);

  // Page Up back to 0
  FLauncher.SelectPageUp();
  AssertEquals('Page up moves back to 0', 0, FLauncher.SelectedIndex);
end;

procedure TLauncherTest.TestLauncherVirtualScrollOffset();
var
  count, i: Integer;
begin
  count := FLauncher.ResultsCount;
  if count <= LAUNCHER_VISIBLE_ITEMS + 2 then
    Exit;

  // Scroll down until selection exceeds the first page
  for i := 1 to LAUNCHER_VISIBLE_ITEMS + 2 do
    FLauncher.SelectNext();

  AssertEquals('Selected index is 12', LAUNCHER_VISIBLE_ITEMS + 2, FLauncher.SelectedIndex);
  AssertTrue('Scroll offset moved to keep item in view', FLauncher.ScrollOffset > 0);
  AssertTrue('Selected index is within visible window',
    (FLauncher.SelectedIndex >= FLauncher.ScrollOffset) and
    (FLauncher.SelectedIndex < FLauncher.ScrollOffset + LAUNCHER_VISIBLE_ITEMS));
end;

procedure TLauncherTest.TestLauncherToggleAndVisibility();
begin
  AssertFalse('Initially not visible', FLauncher.IsVisible);

  FLauncher.Show();
  AssertTrue('Visible after Show()', FLauncher.IsVisible);

  FLauncher.Hide();
  AssertFalse('Not visible after Hide()', FLauncher.IsVisible);

  FLauncher.Toggle();
  AssertTrue('Visible after first Toggle()', FLauncher.IsVisible);

  FLauncher.Toggle();
  AssertFalse('Not visible after second Toggle()', FLauncher.IsVisible);
end;

procedure TLauncherTest.TestLauncherAppIcons();
var
  fallbackBmp: TFtBitmap;
  btn: TFtButton;
begin
  // 1. Fallback icon generation for empty/unknown icon name
  fallbackBmp := FLauncher.GetOrLoadAppIcon('', 20);
  AssertNotNull('GetOrLoadAppIcon("") should return valid bitmap', fallbackBmp);
  AssertEquals('Fallback icon width is 20', 20, fallbackBmp.Width);
  AssertEquals('Fallback icon height is 20', 20, fallbackBmp.Height);

  // 2. Icon cache should contain at least the fallback icon
  AssertTrue('IconCacheCount >= 1', FLauncher.IconCacheCount >= 1);

  // 3. Item buttons should be accessible
  btn := FLauncher.GetItemButton(0);
  AssertNotNull('Item button 0 should be initialized', btn);

  // 4. Updating visible items should maintain valid state
  FLauncher.HandleSearchChanged('');
  AssertTrue('Results count > 0 after search reset', FLauncher.ResultsCount > 0);
end;

initialization
  RegisterTest(TLauncherTest);

end.
