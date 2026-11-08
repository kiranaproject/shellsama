unit ShellSama.Settings.Test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  ShellSama.Settings;

type
  TTestSettingsReceiver = class
  public
    WallpaperChanged: Boolean;
    DarkModeChanged: Boolean;
    ClockFormatChanged: Boolean;
    ShowDesktopChanged: Boolean;
    DockSettingsChanged: Boolean;

    procedure HandleWallpaperChange(Sender: TObject);
    procedure HandleDarkModeChange(Sender: TObject);
    procedure HandleClockFormatChange(Sender: TObject);
    procedure HandleShowDesktopChange(Sender: TObject);
    procedure HandleDockSettingsChange(Sender: TObject);
    procedure Reset();
  end;

  TSettingsTest = class(TTestCase)
  private
    FSettings: TShellSettings;
    FReceiver: TTestSettingsReceiver;
    FTempDir: string;
  protected
    procedure SetUp(); override;
    procedure TearDown(); override;
  published
    procedure TestSingletonAvailable();
    procedure TestWallpaperModeConversions();
    procedure TestDefaultValues();
    procedure TestEventDispatchOnReload();
    procedure TestCheckReloadFileAge();
  end;

implementation

procedure TTestSettingsReceiver.HandleWallpaperChange(Sender: TObject);
begin
  WallpaperChanged := True;
end;

procedure TTestSettingsReceiver.HandleDarkModeChange(Sender: TObject);
begin
  DarkModeChanged := True;
end;

procedure TTestSettingsReceiver.HandleClockFormatChange(Sender: TObject);
begin
  ClockFormatChanged := True;
end;

procedure TTestSettingsReceiver.HandleShowDesktopChange(Sender: TObject);
begin
  ShowDesktopChanged := True;
end;

procedure TTestSettingsReceiver.HandleDockSettingsChange(Sender: TObject);
begin
  DockSettingsChanged := True;
end;

procedure TTestSettingsReceiver.Reset();
begin
  WallpaperChanged := False;
  DarkModeChanged := False;
  ClockFormatChanged := False;
  ShowDesktopChanged := False;
  DockSettingsChanged := False;
end;

procedure TSettingsTest.SetUp();
begin
  FTempDir := GetTempDir() + 'shellsama_settings_test_' + IntToStr(GetProcessID());
  ForceDirectories(FTempDir);
  FSettings := TShellSettings.Create(FTempDir + '/nonexistent.ini');
  FReceiver := TTestSettingsReceiver.Create();
end;

procedure TSettingsTest.TearDown();
begin
  FreeAndNil(FSettings);
  FreeAndNil(FReceiver);
  if FileExists(FTempDir + '/settings.ini') then
    DeleteFile(FTempDir + '/settings.ini');
  if DirectoryExists(FTempDir) then
    RemoveDir(FTempDir);
end;

procedure TSettingsTest.TestSingletonAvailable();
var
  Inst: TShellSettings;
begin
  Inst := ShellSettings();
  AssertNotNull('ShellSettings() singleton must return an instance', Inst);
end;

procedure TSettingsTest.TestWallpaperModeConversions();
begin
  AssertEquals('wmFill to string', 'fill', WallpaperModeToString(wmFill));
  AssertEquals('wmFit to string', 'fit', WallpaperModeToString(wmFit));
  AssertEquals('wmStretch to string', 'stretch', WallpaperModeToString(wmStretch));
  AssertEquals('wmCenter to string', 'center', WallpaperModeToString(wmCenter));
  AssertEquals('wmTile to string', 'tile', WallpaperModeToString(wmTile));
  AssertEquals('wmSolidColor to string', 'solid', WallpaperModeToString(wmSolidColor));

  AssertEquals('Fill string to mode', Ord(wmFill), Ord(StringToWallpaperMode('Fill')));
  AssertEquals('Fit string to mode', Ord(wmFit), Ord(StringToWallpaperMode('Fit')));
  AssertEquals('Stretch string to mode', Ord(wmStretch), Ord(StringToWallpaperMode('Stretch')));
  AssertEquals('Center string to mode', Ord(wmCenter), Ord(StringToWallpaperMode('Center')));
  AssertEquals('Tile string to mode', Ord(wmTile), Ord(StringToWallpaperMode('Tile')));
  AssertEquals('SolidColor string to mode', Ord(wmSolidColor), Ord(StringToWallpaperMode('SolidColor')));
  AssertEquals('Lowercase fill', Ord(wmFill), Ord(StringToWallpaperMode('fill')));
  AssertEquals('Unknown string fallback', Ord(wmFill), Ord(StringToWallpaperMode('UnknownMode')));
end;

procedure TSettingsTest.TestDefaultValues();
begin
  AssertNotNull('Settings should initialize cleanly', FSettings);
  AssertTrue('DockIconSize should be positive', FSettings.DockIconSize >= 24);
  AssertTrue('ClockFormat should be 24h or 12h', (FSettings.ClockFormat = '24h') or (FSettings.ClockFormat = '12h'));
end;

procedure TSettingsTest.TestEventDispatchOnReload();
var
  TestIniPath: string;
  SL: TStringList;
begin
  TestIniPath := FTempDir + '/settings.ini';
  SL := TStringList.Create();
  try
    SL.Add('[Desktop]');
    SL.Add('WallpaperPath=/tmp/test_wall.png');
    SL.Add('WallpaperMode=Fit');
    SL.Add('ShowDesktopButton=false');
    SL.Add('');
    SL.Add('[Appearance]');
    SL.Add('DarkMode=true');
    SL.Add('');
    SL.Add('[DateTime]');
    SL.Add('ClockFormat=12h');
    SL.Add('');
    SL.Add('[Dock]');
    SL.Add('IconSize=64');
    SL.SaveToFile(TestIniPath);
  finally
    SL.Free();
  end;

  FSettings.OnWallpaperChange := @FReceiver.HandleWallpaperChange;
  FSettings.OnDarkModeChange := @FReceiver.HandleDarkModeChange;
  FSettings.OnClockFormatChange := @FReceiver.HandleClockFormatChange;
  FSettings.OnShowDesktopChange := @FReceiver.HandleShowDesktopChange;
  FSettings.OnDockSettingsChange := @FReceiver.HandleDockSettingsChange;
  FReceiver.Reset();

  FSettings.LoadFrom(TestIniPath);

  AssertEquals('WallpaperPath parsed', '/tmp/test_wall.png', FSettings.WallpaperPath);
  AssertEquals('WallpaperMode parsed', Ord(wmFit), Ord(FSettings.WallpaperMode));
  AssertTrue('DarkMode parsed', FSettings.DarkMode);
  AssertEquals('ClockFormat parsed', '12h', FSettings.ClockFormat);
  AssertFalse('ShowDesktopButton parsed', FSettings.ShowDesktopButton);
  AssertEquals('DockIconSize parsed', 64, FSettings.DockIconSize);

  AssertTrue('OnWallpaperChange fired', FReceiver.WallpaperChanged);
  AssertTrue('OnDarkModeChange fired', FReceiver.DarkModeChanged);
  AssertTrue('OnClockFormatChange fired', FReceiver.ClockFormatChanged);
  AssertTrue('OnShowDesktopChange fired', FReceiver.ShowDesktopChanged);
  AssertTrue('OnDockSettingsChange fired', FReceiver.DockSettingsChanged);
end;

procedure TSettingsTest.TestCheckReloadFileAge();
var
  TestIniPath: string;
  SL: TStringList;
  ReloadDetected: Boolean;
begin
  TestIniPath := FTempDir + '/settings.ini';
  SL := TStringList.Create();
  try
    SL.Add('[Appearance]');
    SL.Add('DarkMode=false');
    SL.SaveToFile(TestIniPath);
  finally
    SL.Free();
  end;

  // Set initial file timestamp to 10 seconds in the past to ensure FileAge boundary
  FileSetDate(TestIniPath, DateTimeToFileDate(Now - (10.0 / 86400.0)));

  FSettings.LoadFrom(TestIniPath);
  AssertFalse('Initial dark mode false', FSettings.DarkMode);

  // Calling CheckReload immediately without modifications should return False
  ReloadDetected := FSettings.CheckReload();
  AssertFalse('CheckReload without changes returns False', ReloadDetected);

  // Modify file now
  SL := TStringList.Create();
  try
    SL.Add('[Appearance]');
    SL.Add('DarkMode=true');
    SL.SaveToFile(TestIniPath);
  finally
    SL.Free();
  end;

  // Next CheckReload should detect modification
  ReloadDetected := FSettings.CheckReload();
  AssertTrue('CheckReload detected file change', ReloadDetected);
  AssertTrue('DarkMode reloaded', FSettings.DarkMode);
end;

initialization
  RegisterTest(TSettingsTest);
end.