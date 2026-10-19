{ Unit ShellSama.DesktopApps — Freedesktop .desktop file parser and MRU tracker }

unit ShellSama.DesktopApps;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils, ftpas.api, ftpas;

type
  TDesktopApp = record
    DesktopId  : string;   // e.g. 'firefox.desktop'
    Name       : string;   // Name= field
    Exec       : string;   // Exec= field (cleaned, field codes stripped)
    Comment    : string;   // Comment= field
    Icon           : string;   // Icon= field
    Categories     : string;   // Categories= field
    NoDisplay      : Boolean;  // NoDisplay= field
    Hidden         : Boolean;  // Hidden= field
    OnlyShowIn     : string;   // OnlyShowIn= field
    NotShowIn      : string;   // NotShowIn= field
    Terminal       : Boolean;  // Terminal= field
    StartupWMClass : string;   // StartupWMClass= field
    FilePath       : string;   // Full path to the .desktop file
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

    // Matches window class/name to a desktop app entry
    function FindAppByClass(const AResName, AResClass: string; out AApp: TDesktopApp): Boolean;

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

// Resolves a freedesktop icon name to an absolute file path (.png, .svg, .xpm)
function ResolveIconPath(const AIconName: string; const APreferredSize: Integer = 48): string;

// Loads and scales an icon bitmap (PNG, SVG, etc.) to requested dimensions
function LoadIconBitmap(const APath: string; const AWidth, AHeight: Integer): TFtBitmap;

// Creates a crisp default window/app fallback SVG bitmap
function CreateFallbackIcon(const AWidth, AHeight: Integer): TFtBitmap;

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
      else if Key = 'Icon' then
        AApp.Icon := Value
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
        AApp.Terminal := (LowerCase(Value) = 'true')
      else if Key = 'StartupWMClass' then
        AApp.StartupWMClass := Value;
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

function TDesktopAppList.FindAppByClass(const AResName, AResClass: string; out AApp: TDesktopApp): Boolean;
var
  I: Integer;
  lowName, lowClass: string;
  lowExec, lowId: string;
begin
  Result := False;
  FillChar(AApp, SizeOf(AApp), 0);
  lowName := LowerCase(Trim(AResName));
  lowClass := LowerCase(Trim(AResClass));

  if (lowName = '') and (lowClass = '') then Exit;

  // 1. Direct DesktopId match: e.g. 'firefox.desktop'
  for I := 0 to Length(FApps) - 1 do
  begin
    lowId := LowerCase(FApps[I].DesktopId);
    if (lowName <> '') and ((lowId = lowName + '.desktop') or (lowId = lowName)) then
    begin
      AApp := FApps[I];
      Result := True;
      Exit;
    end;
    if (lowClass <> '') and ((lowId = lowClass + '.desktop') or (lowId = lowClass)) then
    begin
      AApp := FApps[I];
      Result := True;
      Exit;
    end;
  end;

  // 2. StartupWMClass match
  for I := 0 to Length(FApps) - 1 do
  begin
    if FApps[I].StartupWMClass <> '' then
    begin
      if (lowClass <> '') and (LowerCase(FApps[I].StartupWMClass) = lowClass) then
      begin
        AApp := FApps[I];
        Result := True;
        Exit;
      end;
      if (lowName <> '') and (LowerCase(FApps[I].StartupWMClass) = lowName) then
      begin
        AApp := FApps[I];
        Result := True;
        Exit;
      end;
    end;
  end;

  // 3. Exec binary name match: e.g. Exec=firefox
  for I := 0 to Length(FApps) - 1 do
  begin
    lowExec := LowerCase(ExtractFileName(FApps[I].Exec));
    if Pos(' ', lowExec) > 0 then
      lowExec := Copy(lowExec, 1, Pos(' ', lowExec) - 1);

    if (lowName <> '') and (lowExec = lowName) then
    begin
      AApp := FApps[I];
      Result := True;
      Exit;
    end;
    if (lowClass <> '') and (lowExec = lowClass) then
    begin
      AApp := FApps[I];
      Result := True;
      Exit;
    end;
  end;
end;

var
  GIconPathCache: TStringList = nil;

function HasValidIconExtension(const AName: string): Boolean;
var
  ext: string;
begin
  ext := LowerCase(ExtractFileExt(AName));
  Result := (ext = '.png') or (ext = '.svg') or (ext = '.xpm') or (ext = '.svgz') or (ext = '.ico');
end;

function ResolveIconPath(const AIconName: string; const APreferredSize: Integer = 48): string;
var
  cacheKey: string;
  idx: Integer;
  trimmedName: string;
  userHome: string;
  baseDirs: array[0..3] of string;
  themes: array[0..2] of string;
  sizes: array of string;
  cats: array[0..6] of string;
  exts: array of string;
  bIdx, tIdx, sIdx, cIdx, eIdx: Integer;
  testPath: string;
begin
  Result := '';
  trimmedName := Trim(AIconName);
  if trimmedName = '' then Exit;

  cacheKey := trimmedName + '@' + IntToStr(APreferredSize);
  if GIconPathCache <> nil then
  begin
    idx := GIconPathCache.IndexOfName(cacheKey);
    if idx >= 0 then
    begin
      Result := GIconPathCache.ValueFromIndex[idx];
      Exit;
    end;
  end;

  // 1. Direct path check
  if (trimmedName[1] = '/') or (Pos('/', trimmedName) > 0) then
  begin
    if FileExists(trimmedName) then
    begin
      Result := trimmedName;
      if GIconPathCache <> nil then
        GIconPathCache.Values[cacheKey] := Result;
      Exit;
    end;
  end;

  // 2. Check /usr/share/pixmaps/
  if HasValidIconExtension(trimmedName) then
  begin
    testPath := '/usr/share/pixmaps/' + trimmedName;
    if FileExists(testPath) then
    begin
      Result := testPath;
      if GIconPathCache <> nil then
        GIconPathCache.Values[cacheKey] := Result;
      Exit;
    end;
  end
  else
  begin
    testPath := '/usr/share/pixmaps/' + trimmedName + '.png';
    if FileExists(testPath) then
    begin
      Result := testPath;
      if GIconPathCache <> nil then
        GIconPathCache.Values[cacheKey] := Result;
      Exit;
    end;
    testPath := '/usr/share/pixmaps/' + trimmedName + '.svg';
    if FileExists(testPath) then
    begin
      Result := testPath;
      if GIconPathCache <> nil then
        GIconPathCache.Values[cacheKey] := Result;
      Exit;
    end;
    testPath := '/usr/share/pixmaps/' + trimmedName + '.svgz';
    if FileExists(testPath) then
    begin
      Result := testPath;
      if GIconPathCache <> nil then
        GIconPathCache.Values[cacheKey] := Result;
      Exit;
    end;
    testPath := '/usr/share/pixmaps/' + trimmedName + '.xpm';
    if FileExists(testPath) then
    begin
      Result := testPath;
      if GIconPathCache <> nil then
        GIconPathCache.Values[cacheKey] := Result;
      Exit;
    end;
  end;

  // 3. Search icon themes
  userHome := GetEnvironmentVariable('HOME');
  baseDirs[0] := userHome + '/.local/share/icons';
  baseDirs[1] := userHome + '/.icons';
  baseDirs[2] := '/usr/share/icons';
  baseDirs[3] := '/usr/local/share/icons';

  themes[0] := 'Yaru';
  themes[1] := 'Adwaita';
  themes[2] := 'hicolor';

  if (Pos('display-im', LowerCase(trimmedName)) > 0) or (Pos('imagemagick', LowerCase(trimmedName)) > 0) then
    sizes := ['scalable', '512x512', '256x256', '128x128', '64x64', '48x48', '32x32', '24x24', '16x16']
  else if APreferredSize <= 24 then
    sizes := ['24x24', '22x22', '16x16', '32x32', '48x48', '64x64', '128x128', '256x256', '512x512', 'scalable']
  else if APreferredSize <= 32 then
    sizes := ['32x32', '24x24', '48x48', '22x22', '16x16', '64x64', '128x128', '256x256', '512x512', 'scalable']
  else if APreferredSize <= 48 then
    sizes := ['48x48', '32x32', '64x64', '24x24', '128x128', '256x256', '512x512', 'scalable', '16x16']
  else
    sizes := ['128x128', '256x256', '512x512', '64x64', '48x48', 'scalable', '32x32', '24x24', '16x16'];

  cats[0] := 'apps';
  cats[1] := 'places';
  cats[2] := 'categories';
  cats[3] := 'devices';
  cats[4] := 'status';
  cats[5] := 'actions';
  cats[6] := '';

  if HasValidIconExtension(trimmedName) then
    exts := ['']
  else
    exts := ['.png', '.svg', '.svgz', '.xpm'];

  for bIdx := 0 to High(baseDirs) do
  begin
    if (baseDirs[bIdx] = '') or not DirectoryExists(baseDirs[bIdx]) then
      Continue;

    for tIdx := 0 to High(themes) do
    begin
      for sIdx := 0 to High(sizes) do
      begin
        for cIdx := 0 to High(cats) do
        begin
          for eIdx := 0 to High(exts) do
          begin
            if cats[cIdx] <> '' then
              testPath := baseDirs[bIdx] + '/' + themes[tIdx] + '/' + sizes[sIdx] + '/' + cats[cIdx] + '/' + trimmedName + exts[eIdx]
            else
              testPath := baseDirs[bIdx] + '/' + themes[tIdx] + '/' + sizes[sIdx] + '/' + trimmedName + exts[eIdx];

            if FileExists(testPath) then
            begin
              Result := testPath;
              if GIconPathCache <> nil then
                GIconPathCache.Values[cacheKey] := Result;
              Exit;
            end;
          end;
        end;
      end;
    end;
  end;

  if GIconPathCache <> nil then
    GIconPathCache.Values[cacheKey] := '';
end;

function LoadIconBitmap(const APath: string; const AWidth, AHeight: Integer): TFtBitmap;
var
  ext: string;
  rawBmp: TFtBitmap;
begin
  Result := nil;
  if not FtIsLibLoaded() or not FileExists(APath) then Exit;
  ext := LowerCase(ExtractFileExt(APath));
  try
    if (ext = '.svg') or (ext = '.svgz') then
    begin
      Result := TFtBitmap.CreateFromSVGFile(APath, AWidth, AHeight);
      if Assigned(Result) and ((Result.Width = 0) or (Result.Height = 0)) then
      begin
        Result.Free();
        Result := nil;
      end;
    end
    else
    begin
      rawBmp := TFtBitmap.CreateFromFile(APath);
      if Assigned(rawBmp) then
      begin
        if (rawBmp.Width > 0) and (rawBmp.Height > 0) then
        begin
          if (rawBmp.Width = AWidth) and (rawBmp.Height = AHeight) then
            Result := rawBmp
          else
          begin
            Result := rawBmp.CreateScaled(AWidth, AHeight);
            rawBmp.Free();
          end;
        end
        else
        begin
          rawBmp.Free();
          Result := nil;
        end;
      end;
    end;
  except
    Result := nil;
  end;
end;

const
  FALLBACK_WINDOW_ICON_SVG =
    '<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 20 20">' +
    '<rect x="2" y="3" width="16" height="14" rx="2" fill="none" stroke="#94A3B8" stroke-width="1.5"/>' +
    '<line x1="2" y1="7" x2="18" y2="7" stroke="#94A3B8" stroke-width="1.5"/>' +
    '<circle cx="5" cy="5" r="0.8" fill="#94A3B8"/>' +
    '<circle cx="8" cy="5" r="0.8" fill="#94A3B8"/>' +
    '</svg>';

function CreateFallbackIcon(const AWidth, AHeight: Integer): TFtBitmap;
begin
  Result := nil;
  if not FtIsLibLoaded() then Exit;
  try
    Result := TFtBitmap.CreateFromSVG(FALLBACK_WINDOW_ICON_SVG, AWidth, AHeight);
    if Assigned(Result) and ((Result.Width = 0) or (Result.Height = 0)) then
    begin
      Result.Free();
      Result := nil;
    end;
  except
    Result := nil;
  end;
end;

initialization
  GIconPathCache := TStringList.Create();
  GIconPathCache.CaseSensitive := True;

finalization
  if Assigned(GIconPathCache) then
  begin
    GIconPathCache.Free();
    GIconPathCache := nil;
  end;

end.
