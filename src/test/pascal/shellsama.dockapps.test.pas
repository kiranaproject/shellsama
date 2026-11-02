unit ShellSama.DockApps.Test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  ShellSama.DesktopApps,
  ShellSama.DockApps;

type
  TDockAppsTest = class(TTestCase)
  private
    FApps: TShellDockApps;
    FConfigPath: string;
    FSavedConfig: string;
    FHadConfig: Boolean;
  protected
    procedure SetUp(); override;
    procedure TearDown(); override;
  published
    procedure TestPinnedListStartsEmpty();
    procedure TestPinRequiresDesktopEntry();
    procedure TestPinAndUnpinPersist();
    procedure TestPinnedOrderPreserved();
    procedure TestBareClassGroupsWindows();
  end;

implementation

function ConfigPath(): string;
begin
  Result := GetEnvironmentVariable('HOME') + '/.config/shellsama/pinned.conf';
end;

procedure TDockAppsTest.SetUp();
var
  f: TStringList;
begin
  // Preserve whatever the user has, and start from a known empty state.
  FConfigPath := ConfigPath();
  FHadConfig := FileExists(FConfigPath);
  FSavedConfig := '';
  if FHadConfig then
  begin
    f := TStringList.Create();
    try
      f.LoadFromFile(FConfigPath);
      FSavedConfig := f.Text;
    finally
      f.Free();
    end;
  end;
  if FHadConfig then
    DeleteFile(FConfigPath);

  FApps := TShellDockApps.Create();
end;

procedure TDockAppsTest.TearDown();
var
  f: TStringList;
begin
  FApps.Free();
  FApps := nil;

  if FHadConfig then
  begin
    ForceDirectories(ExtractFileDir(FConfigPath));
    f := TStringList.Create();
    try
      f.Text := FSavedConfig;
      f.SaveToFile(FConfigPath);
    finally
      f.Free();
    end;
  end
  else if FileExists(FConfigPath) then
    DeleteFile(FConfigPath);
end;

procedure TDockAppsTest.TestPinnedListStartsEmpty();
begin
  AssertEquals('no pinned apps before anything is pinned', 0, FApps.PinnedCount());
  AssertFalse('a made-up key is not pinned', FApps.IsPinned('nothing.desktop'));
end;

procedure TDockAppsTest.TestPinRequiresDesktopEntry();
begin
  // A key that is only a bare WM_CLASS has no .desktop file behind it, so pinning it
  // would leave an icon that cannot launch anything.
  AssertFalse('a bare class cannot be pinned', FApps.Pin('some-random-class'));
  AssertEquals('pin was refused', 0, FApps.PinnedCount());
end;

procedure TDockAppsTest.TestPinAndUnpinPersist();
var
  key: string;
  reloaded: TShellDockApps;
begin
  if FApps.Apps.AppCount() = 0 then
    raise EIgnoredTest.Create('no desktop entries installed');

  key := FApps.Apps.GetApp(0).DesktopId;
  AssertTrue('pinning a real desktop entry succeeds', FApps.Pin(key));
  AssertTrue('key is pinned', FApps.IsPinned(key));
  AssertEquals('one pinned app', 1, FApps.PinnedCount());

  // A fresh instance must see the same list, i.e. it was written to disk.
  reloaded := TShellDockApps.Create(FApps.Apps);
  try
    AssertTrue('the pin survived a reload', reloaded.IsPinned(key));
    AssertEquals('reloaded count', 1, reloaded.PinnedCount());
  finally
    reloaded.Free();
  end;

  AssertTrue('unpin succeeds', FApps.Unpin(key));
  AssertFalse('key is no longer pinned', FApps.IsPinned(key));
  AssertEquals('nothing pinned', 0, FApps.PinnedCount());

  reloaded := TShellDockApps.Create(FApps.Apps);
  try
    AssertEquals('the unpin survived a reload', 0, reloaded.PinnedCount());
  finally
    reloaded.Free();
  end;
end;

procedure TDockAppsTest.TestPinnedOrderPreserved();
var
  a, b: string;
  reloaded: TShellDockApps;
begin
  if FApps.Apps.AppCount() < 2 then
    raise EIgnoredTest.Create('need at least two desktop entries');

  a := FApps.Apps.GetApp(0).DesktopId;
  b := FApps.Apps.GetApp(1).DesktopId;
  FApps.Pin(a);
  FApps.Pin(b);

  reloaded := TShellDockApps.Create(FApps.Apps);
  try
    AssertEquals('two pinned', 2, reloaded.PinnedCount());
    AssertEquals('first pinned stays first', a, reloaded.PinnedKey(0));
    AssertEquals('second pinned stays second', b, reloaded.PinnedKey(1));
  finally
    reloaded.Free();
  end;
end;

procedure TDockAppsTest.TestBareClassGroupsWindows();
var
  k1, k2, k3: string;
begin
  // Same class, different instance names: one app, so one key. This is what collapses
  // several windows of the same application into a single dock icon.
  k1 := FApps.AppKeyForWindow('instance-a', 'NoSuchAppClass');
  k2 := FApps.AppKeyForWindow('instance-b', 'NoSuchAppClass');
  k3 := FApps.AppKeyForWindow('other', 'DifferentAppClass');

  AssertEquals('same class gives the same key', k1, k2);
  AssertTrue('different class gives a different key', k1 <> k3);
  AssertEquals('the key is the lowercased class', 'nosuchappclass', k1);
  AssertTrue('a bare class has no desktop entry', not FApps.HasDesktopEntry(k1));
end;

initialization
  RegisterTest(TDockAppsTest);
end.
