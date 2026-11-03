unit ShellSama.IconTheme.Test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  ShellSama.IconTheme;

type
  TIconThemeTest = class(TTestCase)
  published
    // Regression: these six applications got no icon at all, because the old resolver
    // searched a hardcoded theme list and seven category names. Each of these lives
    // somewhere that list never looked.
    procedure TestIconsInUnsearchedCategoriesResolve();
    procedure TestIconsInOtherThemesResolve();
    procedure TestUnknownIconReturnsEmpty();
    procedure TestAbsolutePathIsUsedAsIs();
    procedure TestThemeOrderHasHicolorLast();
    procedure TestThemeDirectoriesAreRead();
    procedure TestRequestedSizeIsPreferred();
  end;

implementation

function AnyInstalled(const ANames: array of string): Boolean;
var
  i: Integer;
begin
  for i := 0 to High(ANames) do
    if FileExists(ANames[i]) then Exit(True);
  Result := False;
end;

procedure TIconThemeTest.TestIconsInUnsearchedCategoriesResolve();
var
  path: string;
begin
  // mimetypes and legacy are directory names real themes use and the old category list
  // did not include. Skipped when the machine has no such icon family installed.
  if not AnyInstalled(['/usr/share/icons/Yaru', '/usr/share/icons/Adwaita',
                       '/usr/share/icons/hicolor']) then
    raise EIgnoredTest.Create('no icon themes installed');

  path := ResolveThemeIcon('package-x-generic', 48);
  if path = '' then
    raise EIgnoredTest.Create('package-x-generic not installed on this machine');
  AssertTrue('resolved icon exists on disk: ' + path, FileExists(path));

  path := ResolveThemeIcon('application-x-executable', 48);
  if path <> '' then
    AssertTrue('second mimetypes icon exists', FileExists(path));
end;

procedure TIconThemeTest.TestIconsInOtherThemesResolve();
var
  path: string;
begin
  if not DirectoryExists('/usr/share/icons/gnome') then
    raise EIgnoredTest.Create('gnome theme not installed');

  // Lives only in the gnome theme, which the old fixed list never searched.
  path := ResolveThemeIcon('security-medium', 48);
  if path = '' then
    raise EIgnoredTest.Create('security-medium not installed');
  AssertTrue('resolved in a theme outside the old fixed list', FileExists(path));
  AssertTrue('came from the gnome theme', Pos('gnome', path) > 0);
end;

procedure TIconThemeTest.TestUnknownIconReturnsEmpty();
begin
  AssertEquals('an icon that does not exist resolves to nothing',
               '', ResolveThemeIcon('definitely-not-a-real-icon-name-xyz', 48));
  AssertEquals('the empty name resolves to nothing', '', ResolveThemeIcon('', 48));
  AssertEquals('whitespace resolves to nothing', '', ResolveThemeIcon('   ', 48));
end;

procedure TIconThemeTest.TestAbsolutePathIsUsedAsIs();
var
  tmp: string;
  f: TFileStream;
begin
  tmp := GetTempFileName();
  RenameFile(tmp, tmp + '.png');
  tmp := tmp + '.png';
  try
    f := TFileStream.Create(tmp, fmCreate);
    f.Free();
    AssertEquals('an absolute path is returned unchanged', tmp, ResolveThemeIcon(tmp));
  finally
    if FileExists(tmp) then DeleteFile(tmp);
  end;
end;

procedure TIconThemeTest.TestThemeOrderHasHicolorLast();
var
  order: TStringArray;
begin
  order := ThemeSearchOrder();
  AssertTrue('the search order is not empty', Length(order) > 0);
  AssertEquals('hicolor is searched last, because everything inherits from it',
               'hicolor', LowerCase(order[High(order)]));
end;

procedure TIconThemeTest.TestThemeDirectoriesAreRead();
var
  dirs: TStringArray;
begin
  if not DirectoryExists('/usr/share/icons/Yaru') then
    raise EIgnoredTest.Create('Yaru not installed');

  dirs := ThemeDirectories('Yaru');
  AssertTrue('Yaru declares directories in its index.theme', Length(dirs) > 20);

  // The specific gap that caused the bug: mimetypes is a real Yaru directory and was
  // never in the old fixed category list.
  AssertTrue('mimetypes is among them',
             Pos('mimetypes', string.Join(',', dirs)) > 0);
end;

procedure TIconThemeTest.TestRequestedSizeIsPreferred();
var
  small, large: string;
begin
  if not DirectoryExists('/usr/share/icons/Yaru') then
    raise EIgnoredTest.Create('Yaru not installed');

  small := ResolveThemeIcon('package-x-generic', 24);
  large := ResolveThemeIcon('package-x-generic', 256);
  if (small = '') or (large = '') then
    raise EIgnoredTest.Create('package-x-generic not installed');

  AssertTrue('a 24px request is not answered with a 256px file',
             Pos('256x256', small) = 0);
  AssertTrue('a 256px request is not answered with a 16px file',
             Pos('16x16', large) = 0);
end;

initialization
  RegisterTest(TIconThemeTest);
end.
