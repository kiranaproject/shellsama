{ Unit ShellSama.IconTheme — freedesktop icon theme lookup }

unit ShellSama.IconTheme;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, StrUtils;

// Resolves an icon name to a file path following the freedesktop icon theme
// specification.
//
// The previous implementation searched a fixed guess: three theme names, a fixed
// category list, and only the top level of each size directory. That missed icons
// which real themes do provide, and the misses were not hypothetical -- on this
// machine six of 122 installed applications got no icon at all:
//
//   package-x-generic           lives in Yaru/mimetypes,  category not searched
//   application-x-executable    same
//   system-search               lives in Yaru/legacy,     category not searched
//   security-medium             lives in the gnome theme, theme not searched
//   preferences-system-windows  same
//
// Instead of guessing, the theme's own index.theme is read: it lists the theme's
// directories and the themes it inherits from. That is the same information a
// desktop's icon loader uses, so a theme's own structure is authoritative.
//
// Search order, per the specification:
//   1. an absolute path, if the name is one and the file exists
//   2. $HOME/.icons, then each $XDG_DATA_DIRS/icons, then /usr/share/pixmaps
//   3. the theme named by $XDG_CURRENT_DESKTOP, then the legacy names, then
//      whatever $HOME/.icons/default points at
//   4. each theme's Inherits chain, depth-first, hicolor last

// Resolves AIconName for a nominal size of ASize. Returns '' when nothing matches.
function ResolveThemeIcon(const AIconName: string; const ASize: Integer = 48): string;

// Exposed for tests: the ordered list of theme names that would be searched.
function ThemeSearchOrder(): TStringArray;

// Exposed for tests: directories listed by a theme's index.theme, largest-first is
// applied by the caller. Empty when the theme has no index.theme.
function ThemeDirectories(const ATheme: string): TStringArray;

implementation

var
  GSearchedOnce: Boolean = false;
  GThemeRoots  : TStringArray;
  GThemeOrder  : TStringArray;

function SplitPaths(const AValue: string): TStringArray;
var
  parts: TStringList;
  i: Integer;
begin
  SetLength(Result, 0);
  if Trim(AValue) = '' then Exit;
  parts := TStringList.Create();
  try
    parts.Delimiter := ':';
    parts.StrictDelimiter := True;
    parts.DelimitedText := AValue;
    for i := 0 to parts.Count - 1 do
      if Trim(parts[i]) <> '' then
      begin
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := ExcludeTrailingPathDelimiter(Trim(parts[i]));
      end;
  finally
    parts.Free();
  end;
end;

procedure AddUnique(var AList: TStringArray; const AValue: string);
var
  i: Integer;
begin
  if AValue = '' then Exit;
  for i := 0 to High(AList) do
    if SameText(AList[i], AValue) then Exit;
  SetLength(AList, Length(AList) + 1);
  AList[High(AList)] := AValue;
end;

// The base directories that can contain a theme directory, in specification order.
procedure BuildThemeRoots();
var
  home, dataDirs: string;
  parts: TStringArray;
  i: Integer;
begin
  if GSearchedOnce then Exit;
  GSearchedOnce := true;

  SetLength(GThemeRoots, 0);
  home := GetEnvironmentVariable('HOME');

  AddUnique(GThemeRoots, home + '/.icons');
  AddUnique(GThemeRoots, home + '/.local/share/icons');

  dataDirs := GetEnvironmentVariable('XDG_DATA_DIRS');
  if Trim(dataDirs) = '' then
    dataDirs := '/usr/local/share:/usr/share';
  parts := SplitPaths(dataDirs);
  for i := 0 to High(parts) do
    AddUnique(GThemeRoots, parts[i] + '/icons');

  AddUnique(GThemeRoots, '/usr/share/pixmaps');
end;

function ThemeHasIndex(const ARoot, ATheme: string): Boolean;
begin
  Result := FileExists(ARoot + '/' + ATheme + '/index.theme');
end;

function FindThemeRoot(const ATheme: string): string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to High(GThemeRoots) do
    if ThemeHasIndex(GThemeRoots[i], ATheme) then
      Exit(GThemeRoots[i]);
end;

// Reads the "default" theme from $HOME/.icons/default/index.theme, which is how a
// desktop records the user's choice.
function DefaultThemeName(): string;
var
  lines: TStringList;
  i: Integer;
  line, key, v: string;
  eq: Integer;
begin
  Result := '';
  lines := TStringList.Create();
  try
    try
      lines.LoadFromFile(GetEnvironmentVariable('HOME') + '/.icons/default/index.theme');
    except
      Exit;
    end;
    for i := 0 to lines.Count - 1 do
    begin
      line := Trim(lines[i]);
      eq := Pos('=', line);
      if eq <= 1 then Continue;
      key := LowerCase(Trim(Copy(line, 1, eq - 1)));
      v := Trim(Copy(line, eq + 1, MaxInt));
      if key = 'inherits' then
      begin
        Result := v;
        Exit;
      end;
    end;
  finally
    lines.Free();
  end;
end;

// $XDG_CURRENT_DESKTOP is a colon-separated priority list in practice.
function CurrentDesktopThemes(): TStringArray;
begin
  Result := SplitPaths(GetEnvironmentVariable('XDG_CURRENT_DESKTOP'));
end;

procedure BuildThemeOrder();
var
  candidates: TStringArray;
  i: Integer;
  desktop: TStringArray;
begin
  if GThemeOrder <> nil then Exit;

  BuildThemeRoots();
  SetLength(GThemeOrder, 0);

  // 1. The desktop's own theme, then the conventional fallbacks.
  desktop := CurrentDesktopThemes();
  for i := 0 to High(desktop) do
    AddUnique(GThemeOrder, desktop[i]);
  AddUnique(GThemeOrder, 'hicolor');

  // 2. The user's configured default theme, and the legacy names, before hicolor so
  //    a theme that actually exists wins over the last-resort directory.
  AddUnique(GThemeOrder, DefaultThemeName());
  AddUnique(GThemeOrder, 'Adwaita');
  AddUnique(GThemeOrder, 'gnome');
  AddUnique(GThemeOrder, 'Yaru');
  AddUnique(GThemeOrder, 'Humanity');
  AddUnique(GThemeOrder, 'mate');

  // hicolor must come last: everything else inherits from it.
  for i := 0 to High(GThemeOrder) do
    if SameText(GThemeOrder[i], 'hicolor') then
    begin
      if i <> High(GThemeOrder) then
      begin
        GThemeOrder[i] := GThemeOrder[High(GThemeOrder)];
        GThemeOrder[High(GThemeOrder)] := 'hicolor';
      end;
      Break;
    end;
end;

function ThemeSearchOrder(): TStringArray;
begin
  BuildThemeOrder();
  Result := GThemeOrder;
end;

function ThemeDirectories(const ATheme: string): TStringArray;
var
  root: string;

  procedure ParseFile(const APath: string; var ADirs: TStringArray);
  var
    lines: TStringList;
    i, k: Integer;
    line, value: string;
    extra: TStringArray;
  begin
    lines := TStringList.Create();
    try
      try
        lines.LoadFromFile(APath);
      except
        Exit;
      end;
      for i := 0 to lines.Count - 1 do
      begin
        line := Trim(lines[i]);
        if Pos('Directories=', line) = 1 then
        begin
          value := Trim(Copy(line, Length('Directories=') + 1, MaxInt));
          ADirs := SplitPaths(StringReplace(value, ',', ':', [rfReplaceAll]));
        end
        else if Pos('ScaledDirectories=', line) = 1 then
        begin
          // Scaled directories are @2x variants; they are valid entries too.
          value := Trim(Copy(line, Length('ScaledDirectories=') + 1, MaxInt));
          // Appended rather than replacing, and de-duplicated by the caller.
          if value <> '' then
          begin
            extra := SplitPaths(StringReplace(value, ',', ':', [rfReplaceAll]));
            for k := 0 to High(extra) do
              AddUnique(ADirs, extra[k]);
          end;
        end;
      end;
    finally
      lines.Free();
    end;
  end;

begin
  SetLength(Result, 0);
  // ThemeDirectories is usable on its own, so it cannot rely on ResolveThemeIcon
  // having run first. Without this the root list is empty and every theme looks
  // uninstalled.
  BuildThemeRoots();
  root := FindThemeRoot(ATheme);
  if root = '' then Exit;
  ParseFile(root + '/' + ATheme + '/index.theme', Result);
end;

function SizeFromDir(const ADirName: string; out AScale: Integer): Integer;
var
  base: string;
  xPos: Integer;
  wStr: string;
  slash: Integer;
begin
  Result := 0;
  AScale := 1;

  // Directory names look like '48x48/apps', '48x48@2x/apps', 'scalable/apps'.
  base := ADirName;
  slash := Pos('/', base);
  if slash > 0 then
    base := Copy(base, 1, slash - 1);

  xPos := Pos('@', base);
  if xPos > 0 then
  begin
    AScale := StrToIntDef(Copy(base, xPos + 1, 2), 1);
    if AScale <= 0 then AScale := 1;
    base := Copy(base, 1, xPos - 1);
  end;

  if SameText(base, 'scalable') then
    Exit(0);

  wStr := base;
  xPos := Pos('x', base);
  if xPos > 0 then
    wStr := Copy(base, 1, xPos - 1);
  Result := StrToIntDef(wStr, 0);
end;

// True when the name already carries an image extension. Testing for "contains a dot"
// is wrong: reverse-DNS icon names such as org.gnome.DejaDup have dots and are still
// names to be extended, not filenames.
function HasImageExtension(const AName: string): Boolean;
var
  ext: string;
begin
  ext := LowerCase(ExtractFileExt(AName));
  Result := (ext = '.png') or (ext = '.svg') or (ext = '.svgz') or
            (ext = '.xpm') or (ext = '.ico');
end;

function ThemeRootFor(const ATheme: string): string;
begin
  Result := FindThemeRoot(ATheme);
end;

// Names whose raster versions lose a property the vector keeps. ImageMagick installs
// display-im*.svgz with a transparent background and a 22px PNG without one, so the
// vector is the correct choice regardless of the nominal size.
function IsLargeArtworkName(const AName: string): Boolean;
var
  low: string;
begin
  low := LowerCase(AName);
  Result := (Pos('display-im', low) = 1) or (Pos('imagemagick', low) > 0);
end;

function TryInTheme(const ATheme, AName: string; ASize: Integer): string;
var
  root: string;
  dirs: TStringArray;
  bestPath: string;
  bestScore: Int64;
  i, r, dirSize, scale, score: Integer;
  candidate: string;
  exts: array[0..3] of string;
  extCount, e: Integer;
begin
  Result := '';
  dirs := ThemeDirectories(ATheme);
  if Length(dirs) = 0 then Exit;

  if HasImageExtension(AName) then
  begin
    exts[0] := '';
    extCount := 1;
  end
  else
  begin
    exts[0] := '.png';
    exts[1] := '.svg';
    exts[2] := '.svgz';
    exts[3] := '.xpm';
    extCount := 4;
  end;

  bestPath := '';
  bestScore := High(Int64);

  for r := 0 to High(GThemeRoots) do
  begin
    root := GThemeRoots[r];
    if not ThemeHasIndex(root, ATheme) then Continue;
    dirs := ThemeDirectories(ATheme);
    if Length(dirs) = 0 then Continue;

  for i := 0 to High(dirs) do
  begin
    dirSize := SizeFromDir(dirs[i], scale);
    for e := 0 to extCount - 1 do
    begin
      candidate := root + '/' + ATheme + '/' + dirs[i] + '/' + AName + exts[e];
      if not FileExists(candidate) then Continue;

      // Scoring, in priority order:
      //   1. scale 1 beats a hi-dpi variant, always
      //   2. a raster size at or above the requested one beats going smaller, because
      //      downscaling looks better than upscaling
      //   3. of those, the smallest sufficient size, so a 24px request does not get a
      //      256px file scaled down to nothing
      //   4. scalable is a fallback for when no raster size is sufficient
      //
      // The one exception is a name that only exists as large artwork: ImageMagick's
      // display-*.svgz keeps its transparent background, while the 22px PNG does not,
      // so it must win. These names carry a version suffix and are handled explicitly.
      if dirSize = 0 then
        score := 2000          // scalable: below any sufficient raster
      else if dirSize >= ASize then
        score := 1000 + (dirSize - ASize)   // sufficient: prefer the smallest
      else
        score := 3000 + (ASize - dirSize);  // too small: last resort

      if IsLargeArtworkName(AName) then
      begin
        if dirSize = 0 then
          score := 0         // scalable wins outright for these
        else
          Inc(score, 5000);
      end;

      if scale <> 1 then
        Inc(score, 10000);   // hi-dpi variants only when nothing else matched

      if score < bestScore then
      begin
        bestScore := score;
        bestPath := candidate;
      end;
    end;
  end;
  end;

  Result := bestPath;
end;

function ResolveThemeIcon(const AIconName: string; const ASize: Integer): string;
var
  name: string;
  roots: TStringArray;
  order: TStringArray;
  i: Integer;
  path: string;
begin
  Result := '';
  name := Trim(AIconName);
  if name = '' then Exit;

  // 1. An absolute path is used as-is.
  if (name[1] = '/') and FileExists(name) then
    Exit(name);

  BuildThemeRoots();
  BuildThemeOrder();

  // 2. Loose files in the icon directories and pixmaps.
  roots := GThemeRoots;
  for i := 0 to High(roots) do
  begin
    if HasImageExtension(name) then
    begin
      path := roots[i] + '/' + name;
      if FileExists(path) then Exit(path);
    end
    else
    begin
      path := roots[i] + '/' + name + '.png';
      if FileExists(path) then Exit(path);
      path := roots[i] + '/' + name + '.svg';
      if FileExists(path) then Exit(path);
      path := roots[i] + '/' + name + '.svgz';
      if FileExists(path) then Exit(path);
      path := roots[i] + '/' + name + '.xpm';
      if FileExists(path) then Exit(path);
    end;
  end;

  // 3. Every theme in order, including what each inherits from.
  order := GThemeOrder;
  for i := 0 to High(order) do
  begin
    path := TryInTheme(order[i], name, ASize);
    if path <> '' then Exit(path);
  end;
end;

end.
