{ Unit ShellSama.DockApps — pinned apps and app grouping for the dock }

unit ShellSama.DockApps;

// The dock shows one icon per application rather than one per window. That needs two
// things the taskbar never did: a stable identity for "which app is this window", and
// a list of apps that stay on the dock with no window at all.
//
// Identity comes from WM_CLASS, matched against the desktop entries' StartupWMClass
// and their .desktop id. A window that matches nothing falls back to its own class
// string, so an app without a desktop entry still groups with its own windows.
//
// Pinned apps live in ~/.config/shellsama/pinned.conf, one desktop id per line. The
// file is read at startup and rewritten when the user pins or unpins from the dock.

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils,
  ShellSama.DesktopApps;

type
  TPinnedEdit = (peAdd, peRemove);

  TShellDockApps = class
  private
    FApps        : TDesktopAppList;
    FOrder       : TStringList;   // pinned desktop ids, in dock order
    FOwnsApps    : Boolean;
    procedure LoadPinned();
    procedure SavePinned();
  public
    // AApps is borrowed unless AApps is nil, in which case one is created and owned.
    constructor Create(AApps: TDesktopAppList = nil);
    destructor Destroy(); override;

    // Key identifying the app a window belongs to. Never empty for a real window.
    function AppKeyForWindow(const AResName, AResClass: string): string;
    // Display name for an app key.
    function AppNameForKey(const AAppKey: string): string;
    // Icon name for an app key, or '' if none is known.
    function AppIconForKey(const AAppKey: string): string;
    // Desktop entry behind an app key, if one was found.
    function AppForKey(const AAppKey: string; out AApp: TDesktopApp): Boolean;
    // True if the key came from a real desktop entry rather than a bare WM_CLASS.
    function HasDesktopEntry(const AAppKey: string): Boolean;

    function PinnedCount(): Integer;
    function PinnedKey(AIndex: Integer): string;
    function IsPinned(const AAppKey: string): Boolean;
    // Pinning is by desktop id: a key that came from a bare WM_CLASS cannot be
    // pinned, because there is no .desktop file to launch when the app is closed.
    function Pin(const AAppKey: string): Boolean;
    function Unpin(const AAppKey: string): Boolean;

    // Launch a pinned app, detached. Returns False if there is nothing to launch.
    function Launch(const AAppKey: string): Boolean;

    property Apps: TDesktopAppList read FApps;
  end;

implementation

// Same launch mechanism as the launcher unit: no process management is needed for a
// fire-and-forget application start.
function libc_system(cmd: PChar): Integer; cdecl; external 'c' name 'system';

const
  PINNED_FILE = 'pinned.conf';

function ConfigDir(): string;
begin
  Result := GetEnvironmentVariable('HOME') + '/.config/shellsama';
end;

function PinnedPath(): string;
begin
  Result := ConfigDir() + '/' + PINNED_FILE;
end;

constructor TShellDockApps.Create(AApps: TDesktopAppList);
begin
  inherited Create();

  FOwnsApps := AApps = nil;
  if FOwnsApps then
  begin
    FApps := TDesktopAppList.Create();
    FApps.LoadAll();
  end
  else
    FApps := AApps;

  FOrder := TStringList.Create();
  FOrder.CaseSensitive := False;
  LoadPinned();
end;

destructor TShellDockApps.Destroy();
begin
  FOrder.Free();
  if FOwnsApps then
    FApps.Free();
  inherited Destroy();
end;

procedure TShellDockApps.LoadPinned();
var
  lines: TStringList;
  i: Integer;
  line: string;
begin
  FOrder.Clear();
  if not FileExists(PinnedPath()) then Exit;

  lines := TStringList.Create();
  try
    try
      lines.LoadFromFile(PinnedPath());
    except
      Exit;
    end;

    for i := 0 to lines.Count - 1 do
    begin
      line := Trim(lines[i]);
      if (line = '') or (line[1] = '#') then Continue;
      if FOrder.IndexOf(line) < 0 then
        FOrder.Add(line);
    end;
  finally
    lines.Free();
  end;
end;

procedure TShellDockApps.SavePinned();
begin
  if not DirectoryExists(ConfigDir()) then
    ForceDirectories(ConfigDir());

  try
    FOrder.SaveToFile(PinnedPath());
  except
    // A read-only home should not take the dock down with it; the in-memory list
    // still works for this session.
  end;
end;

function TShellDockApps.AppKeyForWindow(const AResName, AResClass: string): string;
var
  app: TDesktopApp;
  i: Integer;
begin
  Result := '';

  if FApps <> nil then
  begin
    // 1. StartupWMClass is the explicit opt-in; prefer it.
    if AResClass <> '' then
    begin
      for i := 0 to FApps.AppCount() - 1 do
      begin
        app := FApps.GetApp(i);
        if (app.StartupWMClass <> '') and
           SameText(app.StartupWMClass, AResClass) then
        begin
          Result := app.DesktopId;
          Exit;
        end;
      end;
    end;

    // 2. The .desktop id usually matches the class, lowercased.
    if FApps.FindAppByClass(AResName, AResClass, app) then
    begin
      Result := app.DesktopId;
      Exit;
    end;
  end;

  // 3. No desktop entry: group by the window class anyway, so several windows of an
  //    app that has no .desktop file still collapse into one icon.
  if AResClass <> '' then
    Result := LowerCase(AResClass)
  else if AResName <> '' then
    Result := LowerCase(AResName);
end;

function TShellDockApps.AppForKey(const AAppKey: string; out AApp: TDesktopApp): Boolean;
var
  i: Integer;
begin
  Result := False;
  if (FApps = nil) or (AAppKey = '') then Exit;

  for i := 0 to FApps.AppCount() - 1 do
  begin
    AApp := FApps.GetApp(i);
    if SameText(AApp.DesktopId, AAppKey) then
      Exit(True);
  end;
end;

function TShellDockApps.HasDesktopEntry(const AAppKey: string): Boolean;
var
  app: TDesktopApp;
begin
  Result := AppForKey(AAppKey, app);
end;

function TShellDockApps.AppNameForKey(const AAppKey: string): string;
var
  app: TDesktopApp;
begin
  if AppForKey(AAppKey, app) then
    Exit(app.Name);
  // A bare class is at least readable.
  Result := AAppKey;
end;

function TShellDockApps.AppIconForKey(const AAppKey: string): string;
var
  app: TDesktopApp;
begin
  Result := '';
  if AppForKey(AAppKey, app) then
    Result := app.Icon;
end;

function TShellDockApps.PinnedCount(): Integer;
begin
  Result := FOrder.Count;
end;

function TShellDockApps.PinnedKey(AIndex: Integer): string;
begin
  Result := '';
  if (AIndex >= 0) and (AIndex < FOrder.Count) then
    Result := FOrder[AIndex];
end;

function TShellDockApps.IsPinned(const AAppKey: string): Boolean;
begin
  Result := (AAppKey <> '') and (FOrder.IndexOf(AAppKey) >= 0);
end;

function TShellDockApps.Pin(const AAppKey: string): Boolean;
begin
  Result := False;
  if (AAppKey = '') or IsPinned(AAppKey) then Exit;
  // Only an app with a desktop entry can be launched when it has no window, which is
  // the entire point of pinning.
  if not HasDesktopEntry(AAppKey) then Exit;

  FOrder.Add(AAppKey);
  SavePinned();
  Result := True;
end;

function TShellDockApps.Unpin(const AAppKey: string): Boolean;
var
  i: Integer;
begin
  i := FOrder.IndexOf(AAppKey);
  Result := i >= 0;
  if Result then
  begin
    FOrder.Delete(i);
    SavePinned();
  end;
end;

function TShellDockApps.Launch(const AAppKey: string): Boolean;
var
  app: TDesktopApp;
  cmd: string;
begin
  Result := False;
  if not AppForKey(AAppKey, app) then Exit;
  cmd := app.Exec;
  if cmd = '' then Exit;

  // Detached, with stdio closed: the dock must not block on a child or inherit its
  // descriptors.
  libc_system(PChar('( ' + cmd + ' ) >/dev/null 2>&1 &'));
  Result := True;
end;

end.
