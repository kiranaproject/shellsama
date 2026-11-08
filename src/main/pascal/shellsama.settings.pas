{ Unit ShellSama.Settings — Configuration manager and synchronization for Samarinda DE }

unit ShellSama.Settings;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils, IniFiles, Math;

type
  TWallpaperMode = (
    wmFill,      // Scale to fill screen (crop if necessary, maintain aspect ratio)
    wmFit,       // Fit within screen with letterboxing
    wmStretch,   // Stretch to fill screen (ignore aspect ratio)
    wmCenter,    // Center at original resolution
    wmTile,      // Repeat across screen
    wmSolidColor // Solid background color
  );

  TShellSettings = class
  private
    FSettingsFile     : string;
    FShellDesktopFile : string;
    FLastMTime        : LongInt;
    FLastShellMTime   : LongInt;

    // Appearance
    FWallpaperPath    : string;
    FWallpaperMode    : TWallpaperMode;
    FDarkMode         : Boolean;
    FAccentColor      : string;

    // Displays
    FResolution       : string;
    FRefreshRate      : Integer;
    FScale            : Integer;
    FNightLight       : Boolean;

    // Desktop & Dock
    FDockPosition     : string;
    FDockIconSize     : Integer;
    FDockAutoHide     : Boolean;
    FDockMargin       : Integer;
    FShowDesktopButton: Boolean;
    FClockFormat      : string;

    // Event hooks
    FOnWallpaperChange    : TNotifyEvent;
    FOnDarkModeChange     : TNotifyEvent;
    FOnClockFormatChange  : TNotifyEvent;
    FOnShowDesktopChange  : TNotifyEvent;
    FOnDockSettingsChange : TNotifyEvent;

    function GetConfigDir(): string;
    function ParseWallpaperMode(const AStr: string): TWallpaperMode;
    function WallpaperModeToString(AMode: TWallpaperMode): string;
    procedure LoadFromDesktopConf();
  public
    constructor Create(const ACustomPath: string = '');
    destructor Destroy(); override;

    procedure SetDefaults();
    procedure Load();
    procedure LoadFrom(const APath: string);
    procedure Save();
    function CheckReload(): Boolean;

    // Properties
    property SettingsFile     : string read FSettingsFile;
    property WallpaperPath    : string read FWallpaperPath write FWallpaperPath;
    property WallpaperMode    : TWallpaperMode read FWallpaperMode write FWallpaperMode;
    property DarkMode         : Boolean read FDarkMode write FDarkMode;
    property AccentColor      : string read FAccentColor write FAccentColor;

    property Resolution       : string read FResolution write FResolution;
    property RefreshRate      : Integer read FRefreshRate write FRefreshRate;
    property Scale            : Integer read FScale write FScale;
    property NightLight       : Boolean read FNightLight write FNightLight;

    property DockPosition     : string read FDockPosition write FDockPosition;
    property DockIconSize     : Integer read FDockIconSize write FDockIconSize;
    property DockAutoHide     : Boolean read FDockAutoHide write FDockAutoHide;
    property DockMargin       : Integer read FDockMargin write FDockMargin;
    property ShowDesktopButton: Boolean read FShowDesktopButton write FShowDesktopButton;
    property ClockFormat      : string read FClockFormat write FClockFormat;

    // Event hooks
    property OnWallpaperChange    : TNotifyEvent read FOnWallpaperChange write FOnWallpaperChange;
    property OnDarkModeChange     : TNotifyEvent read FOnDarkModeChange write FOnDarkModeChange;
    property OnClockFormatChange  : TNotifyEvent read FOnClockFormatChange write FOnClockFormatChange;
    property OnShowDesktopChange  : TNotifyEvent read FOnShowDesktopChange write FOnShowDesktopChange;
    property OnDockSettingsChange : TNotifyEvent read FOnDockSettingsChange write FOnDockSettingsChange;
  end;

function StringToWallpaperMode(const AStr: string): TWallpaperMode;
function WallpaperModeToString(AMode: TWallpaperMode): string;
function ShellSettings(): TShellSettings;

implementation

var
  GShellSettings: TShellSettings = nil;

function StringToWallpaperMode(const AStr: string): TWallpaperMode;
var
  s: string;
  v: Integer;
begin
  s := LowerCase(Trim(AStr));
  v := StrToIntDef(s, -1);
  if (v >= Ord(Low(TWallpaperMode))) and (v <= Ord(High(TWallpaperMode))) then
    Exit(TWallpaperMode(v));

  if s = 'fill' then Result := wmFill
  else if s = 'fit' then Result := wmFit
  else if s = 'stretch' then Result := wmStretch
  else if s = 'center' then Result := wmCenter
  else if s = 'tile' then Result := wmTile
  else if (s = 'solid') or (s = 'solidcolor') then Result := wmSolidColor
  else Result := wmFill;
end;

function WallpaperModeToString(AMode: TWallpaperMode): string;
begin
  case AMode of
    wmFill:       Result := 'fill';
    wmFit:        Result := 'fit';
    wmStretch:    Result := 'stretch';
    wmCenter:     Result := 'center';
    wmTile:       Result := 'tile';
    wmSolidColor: Result := 'solid';
    else          Result := 'fill';
  end;
end;

function ShellSettings(): TShellSettings;
begin
  if GShellSettings = nil then
    GShellSettings := TShellSettings.Create();
  Result := GShellSettings;
end;

{ TShellSettings }

function TShellSettings.GetConfigDir(): string;
var
  h: string;
begin
  h := GetEnvironmentVariable('HOME');
  if h = '' then h := '/tmp';
  Result := h + '/.config/samarinda';
end;

function TShellSettings.ParseWallpaperMode(const AStr: string): TWallpaperMode;
begin
  Result := StringToWallpaperMode(AStr);
end;

function TShellSettings.WallpaperModeToString(AMode: TWallpaperMode): string;
begin
  Result := ShellSama.Settings.WallpaperModeToString(AMode);
end;

procedure TShellSettings.LoadFrom(const APath: string);
begin
  FSettingsFile := APath;
  FLastMTime := -1;
  CheckReload();
end;

constructor TShellSettings.Create(const ACustomPath: string = '');
var
  h: string;
begin
  inherited Create();
  h := GetEnvironmentVariable('HOME');
  if h = '' then h := '/tmp';

  if ACustomPath <> '' then
    FSettingsFile := ACustomPath
  else
    FSettingsFile := GetConfigDir() + '/settings.ini';

  FShellDesktopFile := h + '/.config/shellsama/desktop.conf';
  FLastMTime := -1;
  FLastShellMTime := -1;

  SetDefaults();
  try
    Load();
  except
  end;
end;

destructor TShellSettings.Destroy();
begin
  inherited Destroy();
end;

procedure TShellSettings.SetDefaults();
begin
  FWallpaperPath := '/usr/share/backgrounds/samarinda.jpg';
  FWallpaperMode := wmFill;
  FDarkMode := False;
  FAccentColor := 'Purple';

  FResolution := '1920x1080';
  FRefreshRate := 60;
  FScale := 100;
  FNightLight := False;

  FDockPosition := 'Bottom';
  FDockIconSize := 48;
  FDockAutoHide := False;
  FDockMargin := 3;
  FShowDesktopButton := True;
  FClockFormat := '24h';
end;

procedure TShellSettings.LoadFromDesktopConf();
var
  lines: TStringList;
  i, eqPos: Integer;
  line, key, val: string;
begin
  if not FileExists(FShellDesktopFile) then Exit;

  lines := TStringList.Create();
  try
    try
      lines.LoadFromFile(FShellDesktopFile);
    except
      Exit;
    end;

    for i := 0 to lines.Count - 1 do
    begin
      line := Trim(lines[i]);
      if (line = '') or (line[1] = '#') or (line[1] = ';') or (line[1] = '[') then
        Continue;
      eqPos := Pos('=', line);
      if eqPos > 1 then
      begin
        key := LowerCase(Trim(Copy(line, 1, eqPos - 1)));
        val := Trim(Copy(line, eqPos + 1, Length(line)));
        if key = 'wallpaper' then
        begin
          if val <> '' then FWallpaperPath := val;
        end
        else if key = 'mode' then
          FWallpaperMode := ParseWallpaperMode(val);
      end;
    end;
  finally
    lines.Free();
  end;
end;

function ReadIniBool(ini: TIniFile; const ASection, AIdent: string; ADefault: Boolean): Boolean;
var
  s: string;
begin
  if not ini.ValueExists(ASection, AIdent) then Exit(ADefault);
  s := LowerCase(Trim(ini.ReadString(ASection, AIdent, '')));
  if (s = '1') or (s = 'true') or (s = 'yes') or (s = 'on') then
    Result := True
  else if (s = '0') or (s = 'false') or (s = 'no') or (s = 'off') then
    Result := False
  else
    Result := ADefault;
end;

procedure TShellSettings.Load();
var
  ini: TIniFile;
  hasIni: Boolean;
begin
  hasIni := FileExists(FSettingsFile);
  if hasIni then
  begin
    try
      ini := TIniFile.Create(FSettingsFile);
    except
      // File locked or mid-write by another process, defer reload to next tick
      Exit;
    end;
    try
      // Appearance
      FDarkMode := ReadIniBool(ini, 'Appearance', 'darkmode', FDarkMode);
      FAccentColor := ini.ReadString('Appearance', 'accentcolor', FAccentColor);
      FWallpaperPath := ini.ReadString('Appearance', 'wallpaper', FWallpaperPath);
      if ini.ValueExists('Appearance', 'wallpaperpath') then
        FWallpaperPath := ini.ReadString('Appearance', 'wallpaperpath', FWallpaperPath);
      if ini.ValueExists('Desktop', 'wallpaper') then
        FWallpaperPath := ini.ReadString('Desktop', 'wallpaper', FWallpaperPath);
      if ini.ValueExists('Desktop', 'wallpaperpath') then
        FWallpaperPath := ini.ReadString('Desktop', 'wallpaperpath', FWallpaperPath);

      if ini.ValueExists('Appearance', 'wallpapermode') then
        FWallpaperMode := ParseWallpaperMode(ini.ReadString('Appearance', 'wallpapermode', WallpaperModeToString(FWallpaperMode)))
      else if ini.ValueExists('Desktop', 'wallpapermode') then
        FWallpaperMode := ParseWallpaperMode(ini.ReadString('Desktop', 'wallpapermode', WallpaperModeToString(FWallpaperMode)));

      // Displays
      FResolution := ini.ReadString('Displays', 'resolution', FResolution);
      FRefreshRate := ini.ReadInteger('Displays', 'refreshrate', FRefreshRate);
      FScale := ini.ReadInteger('Displays', 'scale', FScale);
      FNightLight := ReadIniBool(ini, 'Displays', 'nightlight', FNightLight);

      // Desktop & Dock
      FDockPosition := ini.ReadString('Desktop', 'dockposition', FDockPosition);
      if ini.ValueExists('Dock', 'dockposition') then
        FDockPosition := ini.ReadString('Dock', 'dockposition', FDockPosition);

      FDockIconSize := ini.ReadInteger('Desktop', 'dockiconsize', FDockIconSize);
      if ini.ValueExists('Dock', 'dockiconsize') then
        FDockIconSize := ini.ReadInteger('Dock', 'dockiconsize', FDockIconSize)
      else if ini.ValueExists('Dock', 'iconsize') then
        FDockIconSize := ini.ReadInteger('Dock', 'iconsize', FDockIconSize);

      FDockAutoHide := ReadIniBool(ini, 'Desktop', 'dockautohide', FDockAutoHide);
      if ini.ValueExists('Dock', 'dockautohide') then
        FDockAutoHide := ReadIniBool(ini, 'Dock', 'dockautohide', FDockAutoHide)
      else if ini.ValueExists('Dock', 'autohide') then
        FDockAutoHide := ReadIniBool(ini, 'Dock', 'autohide', FDockAutoHide);

      FDockMargin := ini.ReadInteger('Desktop', 'dockmargin', FDockMargin);
      FShowDesktopButton := ReadIniBool(ini, 'Desktop', 'showdesktopbutton', FShowDesktopButton);
      FClockFormat := ini.ReadString('Desktop', 'clockformat', FClockFormat);
      if ini.ValueExists('DateTime', 'clockformat') then
        FClockFormat := ini.ReadString('DateTime', 'clockformat', FClockFormat);
    finally
      ini.Free();
    end;
  end
  else
  begin
    // Fallback: load desktop.conf if Samarinda settings.ini has not been generated yet
    LoadFromDesktopConf();
  end;

  if FileExists(FSettingsFile) then
    FLastMTime := FileAge(FSettingsFile)
  else
    FLastMTime := 0;

  if FileExists(FShellDesktopFile) then
    FLastShellMTime := FileAge(FShellDesktopFile)
  else
    FLastShellMTime := 0;
end;

procedure TShellSettings.Save();
var
  ini: TIniFile;
  d: string;
  lines: TStringList;
begin
  d := ExtractFilePath(FSettingsFile);
  if (d <> '') and not DirectoryExists(d) then
    ForceDirectories(d);

  ini := TIniFile.Create(FSettingsFile);
  try
    ini.WriteBool('Appearance', 'darkmode', FDarkMode);
    ini.WriteString('Appearance', 'accentcolor', FAccentColor);
    ini.WriteString('Appearance', 'wallpaper', FWallpaperPath);
    ini.WriteString('Appearance', 'wallpapermode', WallpaperModeToString(FWallpaperMode));

    ini.WriteString('Displays', 'resolution', FResolution);
    ini.WriteInteger('Displays', 'refreshrate', FRefreshRate);
    ini.WriteInteger('Displays', 'scale', FScale);
    ini.WriteBool('Displays', 'nightlight', FNightLight);

    ini.WriteString('Desktop', 'dockposition', FDockPosition);
    ini.WriteInteger('Desktop', 'dockiconsize', FDockIconSize);
    ini.WriteBool('Desktop', 'dockautohide', FDockAutoHide);
    ini.WriteInteger('Desktop', 'dockmargin', FDockMargin);
    ini.WriteBool('Desktop', 'showdesktopbutton', FShowDesktopButton);
    ini.WriteString('Desktop', 'clockformat', FClockFormat);
  finally
    ini.Free();
  end;

  // Also sync to desktop.conf
  d := ExtractFilePath(FShellDesktopFile);
  if (d <> '') and not DirectoryExists(d) then
    ForceDirectories(d);

  lines := TStringList.Create();
  try
    lines.Add('# shellsama desktop wallpaper configuration');
    lines.Add('wallpaper=' + FWallpaperPath);
    lines.Add('mode=' + WallpaperModeToString(FWallpaperMode));
    try
      lines.SaveToFile(FShellDesktopFile);
    except
    end;
  finally
    lines.Free();
  end;

  FLastMTime := FileAge(FSettingsFile);
  FLastShellMTime := FileAge(FShellDesktopFile);
end;

function TShellSettings.CheckReload(): Boolean;
var
  curMTime, curShellMTime: LongInt;
  oldWall, oldModeStr, oldClock, oldDockPos: string;
  oldMode: TWallpaperMode;
  oldDark, oldShowDesk, oldDockHide: Boolean;
  oldDockSize: Integer;
begin
  Result := False;

  if FileExists(FSettingsFile) then
    curMTime := FileAge(FSettingsFile)
  else
    curMTime := 0;

  if FileExists(FShellDesktopFile) then
    curShellMTime := FileAge(FShellDesktopFile)
  else
    curShellMTime := 0;

  if (curMTime = FLastMTime) and (curShellMTime = FLastShellMTime) then
    Exit(False);

  // Preserve previous state for delta detection
  oldWall := FWallpaperPath;
  oldMode := FWallpaperMode;
  oldDark := FDarkMode;
  oldClock := FClockFormat;
  oldShowDesk := FShowDesktopButton;
  oldDockSize := FDockIconSize;
  oldDockHide := FDockAutoHide;
  oldDockPos := FDockPosition;

  try
    Load();
  except
    Exit(False);
  end;

  Result := True;

  // Dispatch change events
  if (oldWall <> FWallpaperPath) or (oldMode <> FWallpaperMode) then
  begin
    if Assigned(FOnWallpaperChange) then
      FOnWallpaperChange(Self);
  end;

  if oldDark <> FDarkMode then
  begin
    if Assigned(FOnDarkModeChange) then
      FOnDarkModeChange(Self);
  end;

  if not SameText(oldClock, FClockFormat) then
  begin
    if Assigned(FOnClockFormatChange) then
      FOnClockFormatChange(Self);
  end;

  if oldShowDesk <> FShowDesktopButton then
  begin
    if Assigned(FOnShowDesktopChange) then
      FOnShowDesktopChange(Self);
  end;

  if (oldDockSize <> FDockIconSize) or (oldDockHide <> FDockAutoHide) or
     (oldDockPos <> FDockPosition) then
  begin
    if Assigned(FOnDockSettingsChange) then
      FOnDockSettingsChange(Self);
  end;
end;

initialization

finalization
  if Assigned(GShellSettings) then
  begin
    GShellSettings.Free();
    GShellSettings := nil;
  end;

end.
