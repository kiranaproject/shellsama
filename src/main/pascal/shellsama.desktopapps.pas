{ Unit ShellSama.DesktopApps — Freedesktop .desktop file parser and MRU tracker }

unit ShellSama.DesktopApps;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils;

type
  TDesktopApp = record
    DesktopId  : string;   // e.g. 'firefox.desktop'
    Name       : string;   // Name= field
    Exec       : string;   // Exec= field (cleaned, field codes stripped)
    Comment    : string;   // Comment= field
    Categories : string;   // Categories= field
    NoDisplay  : Boolean;  // NoDisplay= field
    Hidden     : Boolean;  // Hidden= field
    OnlyShowIn : string;   // OnlyShowIn= field
    NotShowIn  : string;   // NotShowIn= field
    Terminal   : Boolean;  // Terminal= field
    FilePath   : string;   // Full path to the .desktop file
  end;

  TDesktopAppArray = array of TDesktopApp;

  TDesktopAppList = class
  private
    FApps       : TDesktopAppArray;
    FRecent     : TStringList;
    FRecentPath : string;
    FDesktopEnv : string;

    procedure ParseDesktopFile(const AFilePath: string; out AApp: TDesktopApp; out AValid: Boolean);
    function CleanExecLine(const AExec: string): string;
    function IsFiltered(const AApp: TDesktopApp): Boolean;
    function FindAppIndex(const ADesktopId: string): Integer;
    procedure ScanDirectory(const ADir: string; var AIdSet: TStringList);
    procedure SortApps();
    function GetRecentIndex(const ADesktopId: string): Integer;
  public
    constructor Create();
    destructor Destroy(); override;

    // Scan /usr/share/applications/ and ~/.local/share/applications/
    // User entries override system entries with same DesktopId
    procedure LoadAll();

    // Returns filtered+sorted results matching AQuery (substring, case-insensitive)
    // If AQuery is empty, returns all apps
    // Sorted: up to 4 MRU first, then alphabetical
    function Search(const AQuery: string): TDesktopAppArray;

    // MRU tracking
    procedure RecordLaunch(const ADesktopId: string);
    procedure LoadRecent();
    procedure SaveRecent();

    // Access the full unfiltered list
    function AppCount(): Integer;
    function GetApp(AIndex: Integer): TDesktopApp;

    property DesktopEnv: string read FDesktopEnv write FDesktopEnv;
    property RecentPath: string read FRecentPath write FRecentPath;
  end;

implementation

const
  MAX_RECENT = 4;

// ---------------------------------------------------------------------------
// TDesktopAppList
// ---------------------------------------------------------------------------

constructor TDesktopAppList.Create();
var
  ConfigDir: string;
begin
  inherited Create();
  SetLength(FApps, 0);
  FRecent := TStringList.Create();
  FRecent.CaseSensitive := True;
  FDesktopEnv := GetEnvironmentVariable('XDG_CURRENT_DESKTOP');
  if FDesktopEnv = '' then
    FDesktopEnv := 'Samarinda';

  ConfigDir := GetEnvironmentVariable('HOME') + '/.config/shellsama';
  FRecentPath := ConfigDir + '/recent.txt';
end;

destructor TDesktopAppList.Destroy();
begin
  FRecent.Free();
  inherited Destroy();
end;

procedure TDesktopAppList.ParseDesktopFile(const AFilePath: string;
  out AApp: TDesktopApp; out AValid: Boolean);
var
  Lines: TStringList;
  I: Integer;
  Line, Key, Value: string;
  InDesktopEntry: Boolean;
  EqPos: Integer;
  HasType, IsApp: Boolean;
begin
  AValid := False;
  FillChar(AApp, SizeOf(AApp), 0);
  AApp.DesktopId := ExtractFileName(AFilePath);
  AApp.FilePath := AFilePath;

  if not FileExists(AFilePath) then
    Exit;

  Lines := TStringList.Create();
  try
    Lines.LoadFromFile(AFilePath);
    InDesktopEntry := False;
    HasType := False;
    IsApp := False;

    for I := 0 to Lines.Count - 1 do
    begin
      Line := Trim(Lines[I]);

      // Skip empty lines and comments
      if (Line = '') or (Line[1] = '#') then
        Continue;

      // Section header
      if (Line[1] = '[') then
      begin
        if Line = '[Desktop Entry]' then
          InDesktopEntry := True
        else if InDesktopEntry then
          Break; // Left the [Desktop Entry] section
        Continue;
      end;

      if not InDesktopEntry then
        Continue;

      // Parse key=value
      EqPos := Pos('=', Line);
      if EqPos < 2 then
        Continue;

      Key := Trim(Copy(Line, 1, EqPos - 1));
      Value := Trim(Copy(Line, EqPos + 1, Length(Line) - EqPos));

      if Key = 'Type' then
      begin
        HasType := True;
        IsApp := (Value = 'Application');
      end
      else if Key = 'Name' then
        AApp.Name := Value
      else if Key = 'Exec' then
        AApp.Exec := CleanExecLine(Value)
      else if Key = 'Comment' then
        AApp.Comment := Value
      else if Key = 'Categories' then
        AApp.Categories := Value
      else if Key = 'NoDisplay' then
        AApp.NoDisplay := (LowerCase(Value) = 'true')
      else if Key = 'Hidden' then
        AApp.Hidden := (LowerCase(Value) = 'true')
      else if Key = 'OnlyShowIn' then
        AApp.OnlyShowIn := Value
      else if Key = 'NotShowIn' then
        AApp.NotShowIn := Value
      else if Key = 'Terminal' then
        AApp.Terminal := (LowerCase(Value) = 'true');
    end;

    // Valid if it's an Application type with Name and Exec
    AValid := HasType and IsApp and (AApp.Name <> '') and (AApp.Exec <> '');
  finally
    Lines.Free();
  end;
end;

function TDesktopAppList.CleanExecLine(const AExec: string): string;
var
  I: Integer;
  Ch: Char;
begin
  Result := '';
  I := 1;
  while I <= Length(AExec) do
  begin
    Ch := AExec[I];
    if (Ch = '%') and (I + 1 <= Length(AExec)) then
    begin
      // Strip known field codes: %f %F %u %U %i %c %k %d %D %n %N %v %m
      case AExec[I + 1] of
        'f', 'F', 'u', 'U', 'i', 'c', 'k', 'd', 'D', 'n', 'N', 'v', 'm':
        begin
          Inc(I, 2);
          Continue;
        end;
        '%':
        begin
          // Literal percent
          Result := Result + '%';
          Inc(I, 2);
          Continue;
        end;
      end;
    end;
    Result := Result + Ch;
    Inc(I);
  end;
  Result := Trim(Result);
end;

function TDesktopAppList.IsFiltered(const AApp: TDesktopApp): Boolean;

  function ContainsDEInList(const AList, ADE: string): Boolean;
  var
    Parts: TStringList;
    J: Integer;
  begin
    Result := False;
    Parts := TStringList.Create();
    try
      Parts.Delimiter := ';';
      Parts.StrictDelimiter := True;
      Parts.DelimitedText := AList;
      for J := 0 to Parts.Count - 1 do
      begin
        if Trim(Parts[J]) = ADE then
        begin
          Result := True;
          Exit;
        end;
      end;
    finally
      Parts.Free();
    end;
  end;

begin
  // Filter out NoDisplay and Hidden
  if AApp.NoDisplay or AApp.Hidden then
  begin
    Result := True;
    Exit;
  end;

  // OnlyShowIn: if set, current DE must be in the list
  if AApp.OnlyShowIn <> '' then
  begin
    if not ContainsDEInList(AApp.OnlyShowIn, FDesktopEnv) then
    begin
      Result := True;
      Exit;
    end;
  end;

  // NotShowIn: if set, current DE must NOT be in the list
  if AApp.NotShowIn <> '' then
  begin
    if ContainsDEInList(AApp.NotShowIn, FDesktopEnv) then
    begin
      Result := True;
      Exit;
    end;
  end;

  Result := False;
end;

function TDesktopAppList.FindAppIndex(const ADesktopId: string): Integer;
var
  I: Integer;
begin
  for I := 0 to Length(FApps) - 1 do
  begin
    if FApps[I].DesktopId = ADesktopId then
    begin
      Result := I;
      Exit;
    end;
  end;
  Result := -1;
end;

procedure TDesktopAppList.ScanDirectory(const ADir: string; var AIdSet: TStringList);
var
  SR: TSearchRec;
  App: TDesktopApp;
  Valid: Boolean;
  FullPath: string;
  Idx: Integer;
begin
  if not DirectoryExists(ADir) then
    Exit;

  if FindFirst(ADir + '/*.desktop', faAnyFile, SR) = 0 then
  begin
    try
      repeat
        FullPath := ADir + '/' + SR.Name;
        ParseDesktopFile(FullPath, App, Valid);

        if Valid and not IsFiltered(App) then
        begin
          if AIdSet.IndexOf(App.DesktopId) >= 0 then
          begin
            // Already seen (user override) — update existing entry
            Idx := FindAppIndex(App.DesktopId);
            if Idx >= 0 then
              FApps[Idx] := App;
          end
          else
          begin
            // New entry
            AIdSet.Add(App.DesktopId);
            SetLength(FApps, Length(FApps) + 1);
            FApps[Length(FApps) - 1] := App;
          end;
        end;
      until FindNext(SR) <> 0;
    finally
      FindClose(SR);
    end;
  end;
end;

procedure TDesktopAppList.SortApps();
var
  I, J: Integer;
  Tmp: TDesktopApp;
begin
  // Simple insertion sort by Name (case-insensitive)
  for I := 1 to Length(FApps) - 1 do
  begin
    Tmp := FApps[I];
    J := I - 1;
    while (J >= 0) and (CompareText(FApps[J].Name, Tmp.Name) > 0) do
    begin
      FApps[J + 1] := FApps[J];
      Dec(J);
    end;
    FApps[J + 1] := Tmp;
  end;
end;

function TDesktopAppList.GetRecentIndex(const ADesktopId: string): Integer;
begin
  Result := FRecent.IndexOf(ADesktopId);
end;

procedure TDesktopAppList.LoadAll();
var
  IdSet: TStringList;
  UserDir, SystemDir: string;
begin
  SetLength(FApps, 0);

  IdSet := TStringList.Create();
  try
    IdSet.CaseSensitive := True;
    IdSet.Sorted := False;

    // Scan user directory first (higher priority)
    UserDir := GetEnvironmentVariable('HOME') + '/.local/share/applications';
    ScanDirectory(UserDir, IdSet);

    // Scan system directory
    SystemDir := '/usr/share/applications';
    ScanDirectory(SystemDir, IdSet);
  finally
    IdSet.Free();
  end;

  SortApps();
  LoadRecent();
end;

function TDesktopAppList.Search(const AQuery: string): TDesktopAppArray;
var
  I, Count: Integer;
  LowerQuery: string;
  Matched: TDesktopAppArray;
  RecentApps: TDesktopAppArray;
  RestApps: TDesktopAppArray;
  RecentCount, RestCount: Integer;
  RIdx: Integer;
begin
  LowerQuery := LowerCase(Trim(AQuery));

  // First pass: collect matching apps
  SetLength(Matched, Length(FApps));
  Count := 0;
  for I := 0 to Length(FApps) - 1 do
  begin
    if (LowerQuery = '') or (Pos(LowerQuery, LowerCase(FApps[I].Name)) > 0) then
    begin
      Matched[Count] := FApps[I];
      Inc(Count);
    end;
  end;
  SetLength(Matched, Count);

  // Second pass: separate into recent and non-recent
  SetLength(RecentApps, MAX_RECENT);
  SetLength(RestApps, Count);
  RecentCount := 0;
  RestCount := 0;

  // Collect recent apps in MRU order
  for I := 0 to FRecent.Count - 1 do
  begin
    if RecentCount >= MAX_RECENT then
      Break;
    for RIdx := 0 to Count - 1 do
    begin
      if Matched[RIdx].DesktopId = FRecent[I] then
      begin
        RecentApps[RecentCount] := Matched[RIdx];
        Inc(RecentCount);
        Break;
      end;
    end;
  end;

  // Collect non-recent apps (already alphabetically sorted)
  for I := 0 to Count - 1 do
  begin
    if GetRecentIndex(Matched[I].DesktopId) < 0 then
    begin
      RestApps[RestCount] := Matched[I];
      Inc(RestCount);
    end;
  end;

  // Combine: recent first, then alphabetical rest
  SetLength(Result, RecentCount + RestCount);
  for I := 0 to RecentCount - 1 do
    Result[I] := RecentApps[I];
  for I := 0 to RestCount - 1 do
    Result[RecentCount + I] := RestApps[I];
end;

procedure TDesktopAppList.RecordLaunch(const ADesktopId: string);
var
  Idx: Integer;
begin
  // Move to front of recent list
  Idx := FRecent.IndexOf(ADesktopId);
  if Idx >= 0 then
    FRecent.Delete(Idx);

  FRecent.Insert(0, ADesktopId);

  // Trim to MAX_RECENT
  while FRecent.Count > MAX_RECENT do
    FRecent.Delete(FRecent.Count - 1);

  SaveRecent();
end;

procedure TDesktopAppList.LoadRecent();
var
  Lines: TStringList;
  I: Integer;
  Line: string;
begin
  FRecent.Clear();

  if not FileExists(FRecentPath) then
    Exit;

  Lines := TStringList.Create();
  try
    Lines.LoadFromFile(FRecentPath);
    for I := 0 to Lines.Count - 1 do
    begin
      Line := Trim(Lines[I]);
      if (Line <> '') and (FRecent.Count < MAX_RECENT) then
        FRecent.Add(Line);
    end;
  finally
    Lines.Free();
  end;
end;

procedure TDesktopAppList.SaveRecent();
var
  Dir: string;
begin
  Dir := ExtractFilePath(FRecentPath);
  if not DirectoryExists(Dir) then
    ForceDirectories(Dir);

  FRecent.SaveToFile(FRecentPath);
end;

function TDesktopAppList.AppCount(): Integer;
begin
  Result := Length(FApps);
end;

function TDesktopAppList.GetApp(AIndex: Integer): TDesktopApp;
begin
  Result := FApps[AIndex];
end;

end.
