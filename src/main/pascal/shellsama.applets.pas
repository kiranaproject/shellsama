{ Unit ShellSama.Applets — Desktop Panel Built-in Applets (Volume, Clock & Session) }

unit ShellSama.Applets;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Process, DateUtils, StrUtils,
  ftpas.api, ftpas.types, ftpas, ftpas.controls, ftpas.menus,
  ftpas.canvas, ftpas.creative, ftpas.font,
  ShellSama.Settings;

type
  TVolumeIconKind = (vikMuted, vikLow, vikMedium, vikHigh);

  { TShellVolumeApplet — Interactive Volume Control Applet & Popup }
  TShellVolumeApplet = class
  private
    FPanelWindow   : TFtWindow;
    FButton        : TFtButton;
    FPopupWindow   : TFtWindow;
    FPlate         : TFtDrawingArea;
    FVolumeLabel   : TFtLabel;
    FVolumeSlider  : TFtSlider;
    FMuteBtn       : TFtButton;

    FCurVolume     : Integer;
    FIsMuted       : Boolean;
    FIconKind      : TVolumeIconKind;
    FIsUpdatingUI  : Boolean;
    FLastCheckTick : Int64;
    // Guards against a slow volume probe stacking up on the main loop thread.
  FQueryBusy     : Boolean;
    FOnDismiss     : TNotifyEvent;

    procedure HandleButtonClick(Sender: TFtButton);
    procedure HandleSliderChange(Sender: TFtSlider; Value: Double);
    procedure HandleMuteClick(Sender: TFtButton);
    procedure HandlePlatePaint(Sender: TFtDrawingArea; Canvas: TFtCanvas);
    procedure HandlePopupWindowDismiss(Sender: TFtWindow);

    procedure CreatePopupWindow();
    procedure DestroyPopupWindow();
  public
    constructor Create(AParentWindow: TFtWindow; AX, AY, AW, AH: Integer);
    destructor Destroy(); override;

    function QueryVolume(out APercent: Integer; out AIsMuted: Boolean): Boolean;
    procedure ApplyVolume(APercent: Integer);
    procedure SetVolumeState(APercent: Integer; AMuted: Boolean);
    procedure ToggleMute();
    procedure StepVolume(ADelta: Integer);

    procedure UpdateUI();
    procedure ApplyThemeStyle();
    procedure ShowPopup();
    procedure HidePopup();
    procedure TogglePopup();
    function IsPopupOpen(): Boolean;

    procedure Tick();
    procedure SetBounds(AX, AY, AW, AH: Integer);

    property Button: TFtButton read FButton;
    property CurrentVolume: Integer read FCurVolume;
    property IsMuted: Boolean read FIsMuted;
    property IconKind: TVolumeIconKind read FIconKind;
    property PopupWindow: TFtWindow read FPopupWindow;
    property Slider: TFtSlider read FVolumeSlider;
    property MuteButton: TFtButton read FMuteBtn;
    property VolumeLabel: TFtLabel read FVolumeLabel;
    property OnDismiss: TNotifyEvent read FOnDismiss write FOnDismiss;
  end;

  { TShellClockApplet — Interactive Clock & Calendar Applet }
  TShellClockApplet = class
  private
    FPanelWindow   : TFtWindow;
    FButton        : TFtButton;
    FPopupWindow   : TFtWindow;
    FPlate         : TFtDrawingArea;
    FPrevBtn       : TFtButton;
    FNextBtn       : TFtButton;
    FClockFont     : TFtFontRef;
    FViewYear      : Word;
    FViewMonth     : Word;
    FLastClockSec  : Integer;
    FOnDismiss     : TNotifyEvent;

    procedure HandleButtonClick(Sender: TFtButton);
    procedure HandlePrevClick(Sender: TFtButton);
    procedure HandleNextClick(Sender: TFtButton);
    procedure HandlePlateMouseDown(Sender: TFtDrawingArea; X, Y, Button: Integer);
    procedure HandlePlatePaint(Sender: TFtDrawingArea; Canvas: TFtCanvas);
    procedure HandlePopupWindowDismiss(Sender: TFtWindow);

    procedure CreatePopupWindow();
    procedure DestroyPopupWindow();
  public
    constructor Create(AParentWindow: TFtWindow; AX, AY, AW, AH: Integer);
    destructor Destroy(); override;

    function GetPreferredWidth(): Integer;
    procedure UpdateClock();
    procedure ApplyThemeStyle();
    procedure ShowPopup();
    procedure HidePopup();
    procedure TogglePopup();
    function IsPopupOpen(): Boolean;

    procedure SetBounds(AX, AY, AW, AH: Integer);

    property Button: TFtButton read FButton;
    property PopupWindow: TFtWindow read FPopupWindow;
    property ViewYear: Word read FViewYear;
    property ViewMonth: Word read FViewMonth;
    property OnDismiss: TNotifyEvent read FOnDismiss write FOnDismiss;
  end;

  { TShellSessionApplet — Power / Session Management Applet }
  TShellSessionApplet = class
  private
    FPanelWindow : TFtWindow;
    FButton      : TFtButton;
    FMenu        : TFtPopupMenu;
    FIsOpen      : Boolean;

    procedure HandleButtonClick(Sender: TFtButton);
    procedure HandleSettings(Sender: TFtMenuItem);
    procedure HandleLockScreen(Sender: TFtMenuItem);
    procedure HandleSuspend(Sender: TFtMenuItem);
    procedure HandleLogOut(Sender: TFtMenuItem);
    procedure HandleRestart(Sender: TFtMenuItem);
    procedure HandleShutDown(Sender: TFtMenuItem);
  public
    constructor Create(AParentWindow: TFtWindow; AX, AY, AW, AH: Integer);
    destructor Destroy(); override;

    procedure SetBounds(AX, AY, AW, AH: Integer);
    procedure ApplyThemeStyle();
    procedure ShowPopup();
    procedure HidePopup();
    procedure TogglePopup();
    function IsPopupOpen(): Boolean;

    property Button: TFtButton read FButton;
    property Menu: TFtPopupMenu read FMenu;
  end;

  { TShellBatteryApplet — Interactive Battery & Power Status Applet }
  TShellBatteryApplet = class
  private
    FPanelWindow      : TFtWindow;
    FButton           : TFtButton;
    FPopupWindow      : TFtWindow;
    FPlate            : TFtDrawingArea;
    FStatusLabel      : TFtLabel;
    FPercentageLabel  : TFtLabel;
    FSettingsBtn      : TFtButton;

    FCurPercentage    : Integer;
    FIsCharging       : Boolean;
    FIsBatteryPresent : Boolean;
    FMockMode         : Boolean;
    FLastCheckTick    : Int64;
    FQueryBusy        : Boolean;
    FOnDismiss        : TNotifyEvent;

    procedure HandleButtonClick(Sender: TFtButton);
    procedure HandleSettingsClick(Sender: TFtButton);
    procedure HandlePlatePaint(Sender: TFtDrawingArea; Canvas: TFtCanvas);
    procedure HandlePopupWindowDismiss(Sender: TFtWindow);

    procedure CreatePopupWindow();
    procedure DestroyPopupWindow();
    procedure UpdatePopupContent();
  public
    constructor Create(AParentWindow: TFtWindow; AX, AY, AW, AH: Integer);
    destructor Destroy(); override;

    function QueryBattery(out APercent: Integer; out ACharging: Boolean; out APresent: Boolean): Boolean;
    procedure SetBatteryState(APercent: Integer; ACharging: Boolean; APresent: Boolean);

    procedure UpdateUI();
    procedure ApplyThemeStyle();
    procedure ShowPopup();
    procedure HidePopup();
    procedure TogglePopup();
    function IsPopupOpen(): Boolean;

    procedure Tick();
    procedure SetBounds(AX, AY, AW, AH: Integer);

    property Button: TFtButton read FButton;
    property CurrentPercentage: Integer read FCurPercentage;
    property IsCharging: Boolean read FIsCharging;
    property IsBatteryPresent: Boolean read FIsBatteryPresent;
    property MockMode: Boolean read FMockMode write FMockMode;
    property PopupWindow: TFtWindow read FPopupWindow;
    property Plate: TFtDrawingArea read FPlate;
    property StatusLabel: TFtLabel read FStatusLabel;
    property PercentageLabel: TFtLabel read FPercentageLabel;
    property SettingsButton: TFtButton read FSettingsBtn;
    property OnDismiss: TNotifyEvent read FOnDismiss write FOnDismiss;
  end;

  { TShellWiredApplet — Ethernet / Wired Network Status Applet }
  TShellWiredApplet = class
  private
    FPanelWindow   : TFtWindow;
    FButton        : TFtButton;
    FPopupWindow   : TFtWindow;
    FPlate         : TFtDrawingArea;
    FStatusLabel   : TFtLabel;
    FDetailsLabel  : TFtLabel;
    FSettingsBtn   : TFtButton;

    FIsConnected   : Boolean;
    FInterfaceName : string;
    FIpAddress     : string;
    FMockMode      : Boolean;
    FLastCheckTick : Int64;
    FQueryBusy     : Boolean;
    FOnDismiss     : TNotifyEvent;

    procedure HandleButtonClick(Sender: TFtButton);
    procedure HandleSettingsClick(Sender: TFtButton);
    procedure HandlePlatePaint(Sender: TFtDrawingArea; Canvas: TFtCanvas);
    procedure HandlePopupWindowDismiss(Sender: TFtWindow);

    procedure CreatePopupWindow();
    procedure DestroyPopupWindow();
    procedure UpdatePopupContent();
  public
    constructor Create(AParentWindow: TFtWindow; AX, AY, AW, AH: Integer);
    destructor Destroy(); override;

    function QueryWired(out AConnected: Boolean; out AInterfaceName: string; out AIpAddress: string): Boolean;
    procedure SetWiredState(AConnected: Boolean; const AInterfaceName: string; const AIpAddress: string);

    procedure UpdateUI();
    procedure ApplyThemeStyle();
    procedure ShowPopup();
    procedure HidePopup();
    procedure TogglePopup();
    function IsPopupOpen(): Boolean;

    procedure Tick();
    procedure SetBounds(AX, AY, AW, AH: Integer);

    property Button: TFtButton read FButton;
    property IsConnected: Boolean read FIsConnected;
    property InterfaceName: string read FInterfaceName;
    property IpAddress: string read FIpAddress;
    property MockMode: Boolean read FMockMode write FMockMode;
    property PopupWindow: TFtWindow read FPopupWindow;
    property Plate: TFtDrawingArea read FPlate;
    property StatusLabel: TFtLabel read FStatusLabel;
    property DetailsLabel: TFtLabel read FDetailsLabel;
    property SettingsButton: TFtButton read FSettingsBtn;
    property OnDismiss: TNotifyEvent read FOnDismiss write FOnDismiss;
  end;

  { TShellLanApplet — LAN / Wireless Network Status Applet }
  TShellLanApplet = class
  private
    FPanelWindow   : TFtWindow;
    FButton        : TFtButton;
    FPopupWindow   : TFtWindow;
    FPlate         : TFtDrawingArea;
    FStatusLabel   : TFtLabel;
    FDetailsLabel  : TFtLabel;
    FToggleBtn     : TFtButton;
    FSettingsBtn   : TFtButton;

    FIsConnected   : Boolean;
    FIsEnabled     : Boolean;
    FSsid          : string;
    FSignal        : Integer;
    FMockMode      : Boolean;
    FLastCheckTick : Int64;
    FQueryBusy     : Boolean;
    FOnDismiss     : TNotifyEvent;

    procedure HandleButtonClick(Sender: TFtButton);
    procedure HandleToggleClick(Sender: TFtButton);
    procedure HandleSettingsClick(Sender: TFtButton);
    procedure HandlePlatePaint(Sender: TFtDrawingArea; Canvas: TFtCanvas);
    procedure HandlePopupWindowDismiss(Sender: TFtWindow);

    procedure CreatePopupWindow();
    procedure DestroyPopupWindow();
    procedure UpdatePopupContent();
  public
    constructor Create(AParentWindow: TFtWindow; AX, AY, AW, AH: Integer);
    destructor Destroy(); override;

    function QueryLan(out AConnected: Boolean; out ASsid: string; out ASignal: Integer; out AEnabled: Boolean): Boolean;
    procedure SetLanState(AConnected: Boolean; const ASsid: string; ASignal: Integer; AEnabled: Boolean);
    procedure ToggleLan();

    procedure UpdateUI();
    procedure ApplyThemeStyle();
    procedure ShowPopup();
    procedure HidePopup();
    procedure TogglePopup();
    function IsPopupOpen(): Boolean;

    procedure Tick();
    procedure SetBounds(AX, AY, AW, AH: Integer);

    property Button: TFtButton read FButton;
    property IsConnected: Boolean read FIsConnected;
    property IsEnabled: Boolean read FIsEnabled;
    property Ssid: string read FSsid;
    property Signal: Integer read FSignal;
    property MockMode: Boolean read FMockMode write FMockMode;
    property PopupWindow: TFtWindow read FPopupWindow;
    property Plate: TFtDrawingArea read FPlate;
    property StatusLabel: TFtLabel read FStatusLabel;
    property DetailsLabel: TFtLabel read FDetailsLabel;
    property ToggleButton: TFtButton read FToggleBtn;
    property SettingsButton: TFtButton read FSettingsBtn;
    property OnDismiss: TNotifyEvent read FOnDismiss write FOnDismiss;
  end;

  { TShellBluetoothApplet — Bluetooth Status & Peripheral Applet }
  TShellBluetoothApplet = class
  private
    FPanelWindow     : TFtWindow;
    FButton          : TFtButton;
    FPopupWindow     : TFtWindow;
    FPlate           : TFtDrawingArea;
    FStatusLabel     : TFtLabel;
    FDetailsLabel    : TFtLabel;
    FToggleBtn       : TFtButton;
    FSettingsBtn     : TFtButton;

    FIsEnabled       : Boolean;
    FIsConnected     : Boolean;
    FConnectedDevice : string;
    FMockMode        : Boolean;
    FLastCheckTick   : Int64;
    FQueryBusy       : Boolean;
    FOnDismiss       : TNotifyEvent;

    procedure HandleButtonClick(Sender: TFtButton);
    procedure HandleToggleClick(Sender: TFtButton);
    procedure HandleSettingsClick(Sender: TFtButton);
    procedure HandlePlatePaint(Sender: TFtDrawingArea; Canvas: TFtCanvas);
    procedure HandlePopupWindowDismiss(Sender: TFtWindow);

    procedure CreatePopupWindow();
    procedure DestroyPopupWindow();
    procedure UpdatePopupContent();
  public
    constructor Create(AParentWindow: TFtWindow; AX, AY, AW, AH: Integer);
    destructor Destroy(); override;

    function QueryBluetooth(out AEnabled: Boolean; out AConnected: Boolean; out AConnectedDevice: string): Boolean;
    procedure SetBluetoothState(AEnabled: Boolean; AConnected: Boolean; const AConnectedDevice: string);
    procedure ToggleBluetooth();

    procedure UpdateUI();
    procedure ApplyThemeStyle();
    procedure ShowPopup();
    procedure HidePopup();
    procedure TogglePopup();
    function IsPopupOpen(): Boolean;

    procedure Tick();
    procedure SetBounds(AX, AY, AW, AH: Integer);

    property Button: TFtButton read FButton;
    property IsEnabled: Boolean read FIsEnabled;
    property IsConnected: Boolean read FIsConnected;
    property ConnectedDevice: string read FConnectedDevice;
    property MockMode: Boolean read FMockMode write FMockMode;
    property PopupWindow: TFtWindow read FPopupWindow;
    property Plate: TFtDrawingArea read FPlate;
    property StatusLabel: TFtLabel read FStatusLabel;
    property DetailsLabel: TFtLabel read FDetailsLabel;
    property ToggleButton: TFtButton read FToggleBtn;
    property SettingsButton: TFtButton read FSettingsBtn;
    property OnDismiss: TNotifyEvent read FOnDismiss write FOnDismiss;
  end;

  { TShellKeyboardApplet — Input Method & Keyboard Layout Status Applet }
  TShellKeyboardApplet = class
  private
    FPanelWindow      : TFtWindow;
    FButton           : TFtButton;
    FPopupWindow      : TFtWindow;
    FPlate            : TFtDrawingArea;
    FTitleLabel       : TFtLabel;
    FStatusLabel      : TFtLabel;
    FDetailsLabel     : TFtLabel;
    FSwitchBtn        : TFtButton;
    FPreferencesBtn   : TFtButton;
    FSettingsBtn      : TFtButton;

    FCurrentLayout    : string;
    FCurrentEngine    : string;
    FEngineDisplayName: string;
    FIsIbusActive     : Boolean;
    FHasMozc          : Boolean;
    FMockMode         : Boolean;
    FLastCheckTick    : Int64;
    FQueryBusy        : Boolean;
    FOnDismiss        : TNotifyEvent;

    procedure HandleButtonClick(Sender: TFtButton);
    procedure HandleSwitchClick(Sender: TFtButton);
    procedure HandlePreferencesClick(Sender: TFtButton);
    procedure HandleSettingsClick(Sender: TFtButton);
    procedure HandlePlatePaint(Sender: TFtDrawingArea; Canvas: TFtCanvas);
    procedure HandlePopupWindowDismiss(Sender: TFtWindow);

    procedure CreatePopupWindow();
    procedure DestroyPopupWindow();
    procedure UpdatePopupContent();
  public
    constructor Create(AParentWindow: TFtWindow; AX, AY, AW, AH: Integer);
    destructor Destroy(); override;

    function QueryKeyboard(out ALayout, AEngine, AEngineName: string; out AIsIbus, AHasMozc: Boolean): Boolean;
    procedure SetKeyboardState(const ALayout, AEngine, AEngineName: string; AIsIbus: Boolean = True; AHasMozc: Boolean = True);
    procedure SwitchEngine(const AEngine: string);
    procedure ToggleInputMethod();

    procedure UpdateUI();
    procedure ApplyThemeStyle();
    procedure ShowPopup();
    procedure HidePopup();
    procedure TogglePopup();
    function IsPopupOpen(): Boolean;

    procedure Tick();
    procedure SetBounds(AX, AY, AW, AH: Integer);

    property Button: TFtButton read FButton;
    property CurrentLayout: string read FCurrentLayout;
    property CurrentEngine: string read FCurrentEngine;
    property EngineDisplayName: string read FEngineDisplayName;
    property IsIbusActive: Boolean read FIsIbusActive;
    property HasMozc: Boolean read FHasMozc;
    property MockMode: Boolean read FMockMode write FMockMode;
    property PopupWindow: TFtWindow read FPopupWindow;
    property Plate: TFtDrawingArea read FPlate;
    property TitleLabel: TFtLabel read FTitleLabel;
    property StatusLabel: TFtLabel read FStatusLabel;
    property DetailsLabel: TFtLabel read FDetailsLabel;
    property SwitchButton: TFtButton read FSwitchBtn;
    property PreferencesButton: TFtButton read FPreferencesBtn;
    property SettingsButton: TFtButton read FSettingsBtn;
    property OnDismiss: TNotifyEvent read FOnDismiss write FOnDismiss;
  end;

  { TShellDisplayApplet — Monitor Topology & External Display Status Applet }
  TShellDisplayApplet = class
  private
    FPanelWindow        : TFtWindow;
    FButton             : TFtButton;
    FPopupWindow        : TFtWindow;
    FPlate              : TFtDrawingArea;
    FTitleLabel         : TFtLabel;
    FSummaryLabel       : TFtLabel;
    FPrimaryLabel       : TFtLabel;
    FSecondaryLabel     : TFtLabel;
    FExtendBtn          : TFtButton;
    FMirrorBtn          : TFtButton;
    FSettingsBtn        : TFtButton;

    FConnectedCount     : Integer;
    FPrimaryName        : string;
    FPrimaryResolution  : string;
    FSecondaryName      : string;
    FSecondaryResolution: string;
    FMockMode           : Boolean;
    FLastCheckTick      : Int64;
    FQueryBusy          : Boolean;
    FOnDismiss          : TNotifyEvent;

    procedure HandleButtonClick(Sender: TFtButton);
    procedure HandleExtendClick(Sender: TFtButton);
    procedure HandleMirrorClick(Sender: TFtButton);
    procedure HandleSettingsClick(Sender: TFtButton);
    procedure HandlePlatePaint(Sender: TFtDrawingArea; Canvas: TFtCanvas);
    procedure HandlePopupWindowDismiss(Sender: TFtWindow);

    procedure CreatePopupWindow();
    procedure DestroyPopupWindow();
    procedure UpdatePopupContent();
  public
    constructor Create(AParentWindow: TFtWindow; AX, AY, AW, AH: Integer);
    destructor Destroy(); override;

    function QueryDisplays(out ACount: Integer; out APriName, APriRes, ASecName, ASecRes: string): Boolean;
    procedure SetDisplayState(ACount: Integer; const APriName, APriRes: string; const ASecName: string = ''; const ASecRes: string = '');
    procedure ExtendDisplays();
    procedure MirrorDisplays();

    procedure UpdateUI();
    procedure ApplyThemeStyle();
    procedure ShowPopup();
    procedure HidePopup();
    procedure TogglePopup();
    function IsPopupOpen(): Boolean;

    procedure Tick();
    procedure SetBounds(AX, AY, AW, AH: Integer);

    property Button: TFtButton read FButton;
    property ConnectedCount: Integer read FConnectedCount;
    property PrimaryName: string read FPrimaryName;
    property PrimaryResolution: string read FPrimaryResolution;
    property SecondaryName: string read FSecondaryName;
    property SecondaryResolution: string read FSecondaryResolution;
    property MockMode: Boolean read FMockMode write FMockMode;
    property PopupWindow: TFtWindow read FPopupWindow;
    property Plate: TFtDrawingArea read FPlate;
    property TitleLabel: TFtLabel read FTitleLabel;
    property SummaryLabel: TFtLabel read FSummaryLabel;
    property PrimaryLabel: TFtLabel read FPrimaryLabel;
    property SecondaryLabel: TFtLabel read FSecondaryLabel;
    property ExtendButton: TFtButton read FExtendBtn;
    property MirrorButton: TFtButton read FMirrorBtn;
    property SettingsButton: TFtButton read FSettingsBtn;
    property OnDismiss: TNotifyEvent read FOnDismiss write FOnDismiss;
  end;

function GetPowerIconSVG(AIsDark: Boolean): string;
function GetVolumeIconSVG(AKind: TVolumeIconKind; AIsDark: Boolean): string;
function GetBatteryIconSVG(APercent: Integer; ACharging: Boolean; APresent: Boolean; AIsDark: Boolean): string;
function GetWiredIconSVG(AConnected: Boolean; AIsDark: Boolean): string;
function GetLanIconSVG(AConnected: Boolean; ASignal: Integer; AEnabled: Boolean; AIsDark: Boolean): string;
function GetBluetoothIconSVG(AEnabled: Boolean; AConnected: Boolean; AIsDark: Boolean): string;
function GetKeyboardIconSVG(const ALayout: string; AIsDark: Boolean): string;
function GetDisplayIconSVG(AMonitorCount: Integer; AIsDark: Boolean): string;

implementation

function IsDarkTheme(): Boolean;
begin
  if FtIsLibLoaded() then
    Result := FtApp().DarkMode
  else
    Result := ShellSettings().DarkMode;
end;

const
  SVG_ICON_COLOR_LIGHT = '#2c3e50';
  SVG_ICON_COLOR_DARK  = '#f0f2f5';
  SVG_ICON_COLOR       = SVG_ICON_COLOR_LIGHT;

function GetPowerIconSVG(AIsDark: Boolean): string;
var
  c: string;
begin
  if AIsDark then
    c := SVG_ICON_COLOR_DARK
  else
    c := SVG_ICON_COLOR_LIGHT;

  Result :=
    '<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="' + c + '" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round">' +
    '<path d="M18.36 6.64a9 9 0 1 1-12.73 0"/>' +
    '<line x1="12" y1="2" x2="12" y2="12"/>' +
    '</svg>';
end;

function GetVolumeIconSVG(AKind: TVolumeIconKind; AIsDark: Boolean): string;
var
  c: string;
begin
  if AIsDark then
    c := SVG_ICON_COLOR_DARK
  else
    c := SVG_ICON_COLOR_LIGHT;

  case AKind of
    vikMuted:
      Result :=
        '<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="' + c + '" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">' +
        '<polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5" fill="' + c + '"/>' +
        '<line x1="22" y1="9" x2="16" y2="15"/>' +
        '<line x1="16" y1="9" x2="22" y2="15"/>' +
        '</svg>';
    vikLow:
      Result :=
        '<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="' + c + '" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">' +
        '<polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5" fill="' + c + '"/>' +
        '<path d="M15.54 8.46a5 5 0 0 1 0 7.07"/>' +
        '</svg>';
    vikMedium:
      Result :=
        '<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="' + c + '" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">' +
        '<polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5" fill="' + c + '"/>' +
        '<path d="M15.54 8.46a5 5 0 0 1 0 7.07"/>' +
        '<path d="M19.07 4.93a10 10 0 0 1 0 14.14"/>' +
        '</svg>';
    vikHigh:
      Result :=
        '<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="' + c + '" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">' +
        '<polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5" fill="' + c + '"/>' +
        '<path d="M15.54 8.46a5 5 0 0 1 0 7.07"/>' +
        '<path d="M19.07 4.93a10 10 0 0 1 0 14.14"/>' +
        '</svg>';
  end;
end;

const
  SVG_POWER_ICON =
    '<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="' + SVG_ICON_COLOR + '" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round">' +
    '<path d="M18.36 6.64a9 9 0 1 1-12.73 0"/>' +
    '<line x1="12" y1="2" x2="12" y2="12"/>' +
    '</svg>';

  SVG_VOL_HIGH =
    '<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="' + SVG_ICON_COLOR + '" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">' +
    '<polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5" fill="' + SVG_ICON_COLOR + '"/>' +
    '<path d="M15.54 8.46a5 5 0 0 1 0 7.07"/>' +
    '<path d="M19.07 4.93a10 10 0 0 1 0 14.14"/>' +
    '</svg>';

  SVG_VOL_MED =
    '<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="' + SVG_ICON_COLOR + '" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">' +
    '<polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5" fill="' + SVG_ICON_COLOR + '"/>' +
    '<path d="M15.54 8.46a5 5 0 0 1 0 7.07"/>' +
    '</svg>';

  SVG_VOL_LOW =
    '<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="' + SVG_ICON_COLOR + '" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">' +
    '<polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5" fill="' + SVG_ICON_COLOR + '"/>' +
    '</svg>';

  SVG_VOL_MUTE =
    '<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="' + SVG_ICON_COLOR + '" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">' +
    '<polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5" fill="' + SVG_ICON_COLOR + '"/>' +
    '<line x1="22" y1="9" x2="16" y2="15"/>' +
    '<line x1="16" y1="9" x2="22" y2="15"/>' +
    '</svg>';

function ReadSysfsFirstLine(const APath: string): string;
var
  f: TextFile;
  line: string;
begin
  Result := '';
  if not FileExists(APath) then Exit;
  try
    AssignFile(f, APath);
    Reset(f);
    if not Eof(f) then
    begin
      ReadLn(f, line);
      Result := Trim(line);
    end;
    CloseFile(f);
  except
    Result := '';
  end;
end;

function GetBatteryIconSVG(APercent: Integer; ACharging: Boolean; APresent: Boolean; AIsDark: Boolean): string;
var
  c: string;
  fillW: Integer;
begin
  if AIsDark then
    c := SVG_ICON_COLOR_DARK
  else
    c := SVG_ICON_COLOR_LIGHT;

  if not APresent then
  begin
    Result :=
      '<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="' + c + '" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">' +
      '<rect x="2" y="6" width="16" height="12" rx="2" ry="2"/>' +
      '<line x1="22" y1="11" x2="22" y2="13"/>' +
      '<line x1="6" y1="12" x2="14" y2="12"/>' +
      '</svg>';
    Exit;
  end;

  if ACharging then
  begin
    Result :=
      '<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="' + c + '" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">' +
      '<rect x="2" y="6" width="16" height="12" rx="2" ry="2"/>' +
      '<line x1="22" y1="11" x2="22" y2="13"/>' +
      '<polygon points="11 7 8 12 11 12 10 17 14 11 11 11" fill="' + c + '"/>' +
      '</svg>';
    Exit;
  end;

  if APercent < 15 then
    fillW := 0
  else if APercent < 40 then
    fillW := 4
  else if APercent < 75 then
    fillW := 8
  else
    fillW := 12;

  Result :=
    '<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="' + c + '" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">' +
    '<rect x="2" y="6" width="16" height="12" rx="2" ry="2"/>' +
    '<line x1="22" y1="11" x2="22" y2="13"/>';

  if fillW > 0 then
    Result := Result + '<rect x="4" y="8" width="' + IntToStr(fillW) + '" height="8" rx="1" fill="' + c + '" stroke="none"/>';

  Result := Result + '</svg>';
end;

function GetWiredIconSVG(AConnected: Boolean; AIsDark: Boolean): string;
var
  c: string;
begin
  if AIsDark then
    c := SVG_ICON_COLOR_DARK
  else
    c := SVG_ICON_COLOR_LIGHT;

  Result :=
    '<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="' + c + '" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">' +
    '<rect x="3" y="4" width="18" height="14" rx="2"/>' +
    '<path d="M7 18v2h10v-2"/>' +
    '<line x1="8" y1="8" x2="8" y2="12"/>' +
    '<line x1="12" y1="8" x2="12" y2="12"/>' +
    '<line x1="16" y1="8" x2="16" y2="12"/>';

  if not AConnected then
    Result := Result + '<line x1="2" y1="2" x2="22" y2="22" stroke-width="2.2"/>';

  Result := Result + '</svg>';
end;

function GetLanIconSVG(AConnected: Boolean; ASignal: Integer; AEnabled: Boolean; AIsDark: Boolean): string;
var
  c: string;
begin
  if AIsDark then
    c := SVG_ICON_COLOR_DARK
  else
    c := SVG_ICON_COLOR_LIGHT;

  if (not AEnabled) or (not AConnected) then
  begin
    Result :=
      '<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="' + c + '" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">' +
      '<path d="M12 20h.01"/>' +
      '<path d="M8.5 16.5a5 5 0 0 1 7 0"/>' +
      '<path d="M5 12.5a10 10 0 0 1 14 0"/>' +
      '<line x1="2" y1="2" x2="22" y2="22" stroke-width="2.2"/>' +
      '</svg>';
    Exit;
  end;

  Result :=
    '<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="' + c + '" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">' +
    '<path d="M12 20h.01"/>' +
    '<path d="M8.5 16.5a5 5 0 0 1 7 0"/>';

  if ASignal >= 35 then
    Result := Result + '<path d="M5 12.5a10 10 0 0 1 14 0"/>';

  if ASignal >= 70 then
    Result := Result + '<path d="M1.5 8.5a15 15 0 0 1 21 0"/>';

  Result := Result + '</svg>';
end;

function GetBluetoothIconSVG(AEnabled: Boolean; AConnected: Boolean; AIsDark: Boolean): string;
var
  c: string;
begin
  if AIsDark then
    c := SVG_ICON_COLOR_DARK
  else
    c := SVG_ICON_COLOR_LIGHT;

  if not AEnabled then
  begin
    Result :=
      '<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="' + c + '" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">' +
      '<path d="M7 7l10 10-5 5V2l5 5L7 17"/>' +
      '<line x1="2" y1="2" x2="22" y2="22" stroke-width="2.2"/>' +
      '</svg>';
    Exit;
  end;

  Result :=
    '<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="' + c + '" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">' +
    '<path d="M7 7l10 10-5 5V2l5 5L7 17"/>';

  if AConnected then
  begin
    Result := Result +
      '<circle cx="4" cy="9" r="1.5" fill="' + c + '" stroke="none"/>' +
      '<circle cx="4" cy="15" r="1.5" fill="' + c + '" stroke="none"/>';
  end;

  Result := Result + '</svg>';
end;

function GetKeyboardIconSVG(const ALayout: string; AIsDark: Boolean): string;
var
  c: string;
begin
  if AIsDark then
    c := SVG_ICON_COLOR_DARK
  else
    c := SVG_ICON_COLOR_LIGHT;

  Result :=
    '<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="' + c + '" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">' +
    '<rect x="2" y="4" width="20" height="16" rx="2"/>' +
    '<path d="M6 8h.001M10 8h.001M14 8h.001M18 8h.001M6 12h.001M10 12h.001M14 12h.001M18 12h.001M7 16h10"/>' +
    '</svg>';
end;

function GetDisplayIconSVG(AMonitorCount: Integer; AIsDark: Boolean): string;
var
  c: string;
begin
  if AIsDark then
    c := SVG_ICON_COLOR_DARK
  else
    c := SVG_ICON_COLOR_LIGHT;

  if AMonitorCount > 1 then
  begin
    Result :=
      '<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="' + c + '" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">' +
      '<rect x="1" y="5" width="13" height="10" rx="1.5"/>' +
      '<rect x="10" y="8" width="13" height="10" rx="1.5"/>' +
      '<line x1="4" y1="18" x2="10" y2="18"/>' +
      '<line x1="14" y1="21" x2="20" y2="21"/>' +
      '</svg>';
  end
  else
  begin
    Result :=
      '<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="' + c + '" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">' +
      '<rect x="2" y="3" width="20" height="14" rx="2"/>' +
      '<line x1="8" y1="21" x2="16" y2="21"/>' +
      '<line x1="12" y1="17" x2="12" y2="21"/>' +
      '</svg>';
  end;
end;

procedure ExecShellCmdAsync(const ACmd: string);
var
  AProcess: TProcess;
begin
  AProcess := TProcess.Create(nil);
  try
    AProcess.Executable := '/bin/sh';
    AProcess.Parameters.Add('-c');
    AProcess.Parameters.Add(ACmd);
    AProcess.Options := [poNoConsole];
    AProcess.Execute();
  finally
    AProcess.Free();
  end;
end;

// =============================================================================
// TShellVolumeApplet Implementation
// =============================================================================

constructor TShellVolumeApplet.Create(AParentWindow: TFtWindow; AX, AY, AW, AH: Integer);
begin
  inherited Create();
  FPanelWindow := AParentWindow;
  FCurVolume := 100;
  FIsMuted := False;
  FIconKind := vikHigh;
  FIsUpdatingUI := False;
  FLastCheckTick := 0;
  FQueryBusy := False;
  FOnDismiss := nil;

  FButton := TFtButton.Create(FPanelWindow, AX, AY, AW, AH, '');
  FButton.Flat := True;
  FButton.IsToggle := True;
  FButton.CornerRadius := 6.0;
  FButton.IconPosition := ftipOnly;
  FButton.SetIconSize(18, 18);
  FButton.OnClick := @HandleButtonClick;

  QueryVolume(FCurVolume, FIsMuted);
  UpdateUI();
end;

destructor TShellVolumeApplet.Destroy();
begin
  DestroyPopupWindow();
  if Assigned(FButton) then
  begin
    FButton.Free();
    FButton := nil;
  end;
  inherited Destroy();
end;

procedure TShellVolumeApplet.SetBounds(AX, AY, AW, AH: Integer);
begin
  if Assigned(FButton) then
    FButton.SetBounds(AX, AY, AW, AH);
end;

function TShellVolumeApplet.QueryVolume(out APercent: Integer; out AIsMuted: Boolean): Boolean;
var
  outStr: string;
  volStr: string;
  volVal: Double;
  p, q: Integer;
begin
  APercent := 100;
  AIsMuted := False;
  Result := False;

  // Try wpctl first (modern PipeWire standard)
  if RunCommand('/usr/bin/wpctl', ['get-volume', '@DEFAULT_AUDIO_SINK@'], outStr) then
  begin
    outStr := Trim(outStr);
    p := Pos('Volume:', outStr);
    if p > 0 then
    begin
      volStr := Trim(Copy(outStr, p + 7, Length(outStr)));
      q := Pos(' ', volStr);
      if q > 0 then
        volStr := Copy(volStr, 1, q - 1);

      volVal := StrToFloatDef(volStr, 1.0);
      APercent := EnsureRange(Round(volVal * 100), 0, 150);
      AIsMuted := (Pos('[MUTED]', outStr) > 0);
      Exit(True);
    end;
  end;

  // Fallback to amixer (ALSA)
  if RunCommand('/usr/bin/amixer', ['sget', 'Master'], outStr) then
  begin
    p := Pos('[', outStr);
    if p > 0 then
    begin
      q := Pos('%]', outStr);
      if (q > p) then
      begin
        volStr := Copy(outStr, p + 1, q - p - 1);
        APercent := StrToIntDef(volStr, 100);
        AIsMuted := (Pos('[off]', outStr) > 0);
        Exit(True);
      end;
    end;
  end;
end;

procedure TShellVolumeApplet.ApplyVolume(APercent: Integer);
var
  fracStr, dummy: string;
begin
  FCurVolume := EnsureRange(APercent, 0, 150);
  fracStr := FormatFloat('0.00', FCurVolume / 100.0);

  if not RunCommand('/usr/bin/wpctl', ['set-volume', '@DEFAULT_AUDIO_SINK@', fracStr], dummy) then
  begin
    RunCommand('/usr/bin/amixer', ['-q', 'sset', 'Master', IntToStr(FCurVolume) + '%'], dummy);
  end;

  UpdateUI();
end;

procedure TShellVolumeApplet.SetVolumeState(APercent: Integer; AMuted: Boolean);
begin
  FCurVolume := EnsureRange(APercent, 0, 150);
  FIsMuted := AMuted;
  UpdateUI();
end;

procedure TShellVolumeApplet.ToggleMute();
var
  dummy: string;
begin
  if not RunCommand('/usr/bin/wpctl', ['set-mute', '@DEFAULT_AUDIO_SINK@', 'toggle'], dummy) then
  begin
    RunCommand('/usr/bin/amixer', ['-q', 'sset', 'Master', 'toggle'], dummy);
  end;

  QueryVolume(FCurVolume, FIsMuted);
  UpdateUI();
end;

procedure TShellVolumeApplet.StepVolume(ADelta: Integer);
begin
  ApplyVolume(FCurVolume + ADelta);
end;

procedure TShellVolumeApplet.ApplyThemeStyle();
begin
  UpdateUI();
  if Assigned(FPlate) then
    FPlate.Invalidate();
  if Assigned(FVolumeSlider) then
    FVolumeSlider.Invalidate();
  if Assigned(FMuteBtn) then
    FMuteBtn.Invalidate();
  if Assigned(FPopupWindow) then
    FPopupWindow.Invalidate();
end;

procedure TShellVolumeApplet.UpdateUI();
var
  isDark: Boolean;
begin
  if FButton = nil then Exit;

  isDark := IsDarkTheme();

  FButton.Caption := '';
  FButton.IconPosition := ftipOnly;
  FButton.SetIconSize(18, 18);

  if FIsMuted or (FCurVolume = 0) then
  begin
    FIconKind := vikMuted;
    FButton.SetIconSVG(GetVolumeIconSVG(vikMuted, isDark));
  end
  else if FCurVolume < 33 then
  begin
    FIconKind := vikLow;
    FButton.SetIconSVG(GetVolumeIconSVG(vikLow, isDark));
  end
  else if FCurVolume < 66 then
  begin
    FIconKind := vikMedium;
    FButton.SetIconSVG(GetVolumeIconSVG(vikMedium, isDark));
  end
  else
  begin
    FIconKind := vikHigh;
    FButton.SetIconSVG(GetVolumeIconSVG(vikHigh, isDark));
  end;

  if Assigned(FPopupWindow) and not FIsUpdatingUI then
  begin
    FIsUpdatingUI := True;
    try
      if Assigned(FVolumeLabel) then
      begin
        if FIsMuted then
          FVolumeLabel.Text := 'Volume: Muted (' + IntToStr(FCurVolume) + '%)'
        else
          FVolumeLabel.Text := 'Volume: ' + IntToStr(FCurVolume) + '%';

        if isDark then
          FVolumeLabel.SetColor(0.85, 0.88, 0.95)
        else
          FVolumeLabel.SetColor(0.12, 0.16, 0.23);
      end;

      if Assigned(FVolumeSlider) then
        FVolumeSlider.Value := FCurVolume;

      if Assigned(FMuteBtn) then
      begin
        if FIsMuted then
          FMuteBtn.Caption := 'Unmute Audio'
        else
          FMuteBtn.Caption := 'Mute Audio';
      end;
    finally
      FIsUpdatingUI := False;
    end;
  end;
end;

procedure TShellVolumeApplet.HandlePlatePaint(Sender: TFtDrawingArea; Canvas: TFtCanvas);
var
  isDark: Boolean;
begin
  if not Assigned(Sender) or not Assigned(Canvas) then Exit;

  isDark := IsDarkTheme();
  if isDark then
  begin
    // Dark mode plate and outline
    Canvas.DrawRoundedRect(0, 0, Sender.Width, Sender.Height, 6.0, 24 / 255, 25 / 255, 38 / 255, 0.98);
    Canvas.DrawRoundedRectOutline(0, 0, Sender.Width, Sender.Height, 6.0, 1.0, 69 / 255, 71 / 255, 90 / 255, 0.80);
  end
  else
  begin
    // White card background with subtle rounded border
    Canvas.DrawRoundedRect(0, 0, Sender.Width, Sender.Height, 6.0, 1.0, 1.0, 1.0, 1.0);
    Canvas.DrawRoundedRectOutline(0, 0, Sender.Width, Sender.Height, 6.0, 1.0, 0.80, 0.84, 0.88, 1.0);
  end;
end;

procedure TShellVolumeApplet.HandlePopupWindowDismiss(Sender: TFtWindow);
begin
  HidePopup();
  if Assigned(FOnDismiss) then
    FOnDismiss(Self);
end;

procedure TShellVolumeApplet.CreatePopupWindow();
var
  popX, popY, popW, popH: Integer;
begin
  if Assigned(FPopupWindow) then Exit;

  popW := 200;
  popH := 92;

  if Assigned(FButton) and Assigned(FPanelWindow) then
  begin
    popX := Max(10, FButton.X - (popW - FButton.Width) div 2);
    if FPanelWindow.Y < 100 then
      popY := FPanelWindow.Y + FPanelWindow.Height + 4
    else
      popY := FPanelWindow.Y - popH - 4;
  end
  else
  begin
    popX := 100;
    popY := 100;
  end;

  FPopupWindow := TFtWindow.Create(popW, popH, 'shellsama-volume-popup');
  FPopupWindow.WindowType := ftwtPopupMenu;
  FPopupWindow.Borderless := True;
  FPopupWindow.SkipTaskbar := True;
  FPopupWindow.SetPosition(popX, popY);
  FPopupWindow.OnPopupDismiss := @HandlePopupWindowDismiss;

  // Background plate
  FPlate := TFtDrawingArea.Create(FPopupWindow, 0, 0, popW, popH);
  FPlate.OnPaint := @HandlePlatePaint;

  // Volume text label
  FVolumeLabel := TFtLabel.Create(FPopupWindow, 16, 10, popW - 32, 18, 'Volume: ' + IntToStr(FCurVolume) + '%');
  FVolumeLabel.Alignment := ftaLeft;
  if IsDarkTheme() then
    FVolumeLabel.SetColor(0.85, 0.88, 0.95)
  else
    FVolumeLabel.SetColor(0.12, 0.16, 0.23);

  // Volume slider
  FVolumeSlider := TFtSlider.Create(FPopupWindow, 16, 32, popW - 32, 22, ftsoHorizontal);
  FVolumeSlider.SetRange(0.0, 100.0);
  FVolumeSlider.Step := 1.0;
  FVolumeSlider.Value := FCurVolume;
  FVolumeSlider.OnChange := @HandleSliderChange;

  // Mute button
  FMuteBtn := TFtButton.Create(FPopupWindow, 16, 58, popW - 32, 24, 'Mute Audio');
  FMuteBtn.Flat := True;
  FMuteBtn.CornerRadius := 4.0;
  FMuteBtn.OnClick := @HandleMuteClick;

  ApplyThemeStyle();
end;

procedure TShellVolumeApplet.DestroyPopupWindow();
begin
  if Assigned(FPopupWindow) then
  begin
    FVolumeLabel := nil;
    FVolumeSlider := nil;
    FMuteBtn := nil;
    FPlate := nil;
    FPopupWindow.Free();
    FPopupWindow := nil;
  end;
end;

procedure TShellVolumeApplet.ShowPopup();
begin
  if not Assigned(FPopupWindow) then
    CreatePopupWindow();

  ApplyThemeStyle();

  if Assigned(FPopupWindow) then
  begin
    FPopupWindow.Show();
    FPopupWindow.GrabPopupInput();
    if Assigned(FButton) then
      FButton.Toggled := True;
  end;

  Tick();
end;

procedure TShellVolumeApplet.HidePopup();
begin
  if Assigned(FPopupWindow) then
  begin
    FPopupWindow.UngrabInput();
    FPopupWindow.Hide();
    if Assigned(FButton) then
      FButton.Toggled := False;
  end;
end;

procedure TShellVolumeApplet.TogglePopup();
begin
  if IsPopupOpen() then
    HidePopup()
  else
    ShowPopup();
end;

function TShellVolumeApplet.IsPopupOpen(): Boolean;
begin
  Result := Assigned(FPopupWindow) and FPopupWindow.Visible;
end;

procedure TShellVolumeApplet.Tick();
var
  nowTick: Int64;
  newVol: Integer;
  newMuted: Boolean;
begin
  if not IsPopupOpen() then Exit;

  nowTick := DateTimeToTimeStamp(Now()).Time;
  if Abs(nowTick - FLastCheckTick) < 1500 then Exit;
  FLastCheckTick := nowTick;

  if FQueryBusy then Exit;
  FQueryBusy := True;
  try
    if QueryVolume(newVol, newMuted) then
    begin
      if (newVol <> FCurVolume) or (newMuted <> FIsMuted) then
      begin
        FCurVolume := newVol;
        FIsMuted := newMuted;
        UpdateUI();
      end;
    end;
  finally
    FQueryBusy := False;
  end;
end;

procedure TShellVolumeApplet.HandleButtonClick(Sender: TFtButton);
begin
  TogglePopup();
end;

procedure TShellVolumeApplet.HandleSliderChange(Sender: TFtSlider; Value: Double);
begin
  if FIsUpdatingUI then Exit;
  ApplyVolume(Round(Value));
end;

procedure TShellVolumeApplet.HandleMuteClick(Sender: TFtButton);
begin
  ToggleMute();
end;

// =============================================================================
// TShellClockApplet Implementation
// =============================================================================

constructor TShellClockApplet.Create(AParentWindow: TFtWindow; AX, AY, AW, AH: Integer);
begin
  inherited Create();
  FPanelWindow := AParentWindow;
  FLastClockSec := -1;
  FOnDismiss := nil;
  FViewYear := 0;
  FViewMonth := 0;
  FPrevBtn := nil;
  FNextBtn := nil;
  FClockFont := TFtFontRef.Create('Sans:bold 18');

  FButton := TFtButton.Create(FPanelWindow, AX, AY, AW, AH, '--:--');
  FButton.Flat := True;
  FButton.IsToggle := True;
  FButton.CornerRadius := 6.0;
  FButton.PaddingX := 9.0;
  FButton.OnClick := @HandleButtonClick;

  UpdateClock();
end;

destructor TShellClockApplet.Destroy();
begin
  DestroyPopupWindow();
  if Assigned(FClockFont) then
  begin
    FClockFont.Free();
    FClockFont := nil;
  end;
  if Assigned(FButton) then
  begin
    FButton.Free();
    FButton := nil;
  end;
  inherited Destroy();
end;

function TShellClockApplet.GetPreferredWidth(): Integer;
var
  tw: Double;
begin
  Result := 146;
  if Assigned(FButton) and (FButton.Caption <> '') and Assigned(ft_font_text_width) then
  begin
    tw := ft_font_text_width(nil, PChar(FButton.Caption));
    if tw > 0.0 then
      Result := Round(tw) + 18; // 9px margin on left and right, matching other applets
  end;
end;

procedure TShellClockApplet.SetBounds(AX, AY, AW, AH: Integer);
begin
  if Assigned(FButton) then
    FButton.SetBounds(AX, AY, AW, AH);
end;

procedure TShellClockApplet.HandlePlatePaint(Sender: TFtDrawingArea; Canvas: TFtCanvas);
var
  nowDt: TDateTime;
  curYr, curMo, curDa: Word;
  hr, mn, sc, ms: Word;
  dateStr, timeStr, monthYearStr: string;
  startCol, daysInMonth, prevDaysInMonth, d, col, row: Integer;
  cellIndex, prevYear, prevMonth: Integer;
  gridX, colW, rowH, cellX, cellY, bx, by, badgeW, badgeH: Integer;
  isToday, isDark: Boolean;
const
  DayNames: array[0..6] of string = ('Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su');
begin
  if not Assigned(Sender) or not Assigned(Canvas) then Exit;

  isDark := IsDarkTheme();

  nowDt := Now();
  DecodeDate(nowDt, curYr, curMo, curDa);
  DecodeTime(nowDt, hr, mn, sc, ms);

  if FViewYear = 0 then
  begin
    FViewYear := curYr;
    FViewMonth := curMo;
  end;

  if isDark then
  begin
    // 1. Dark card plate + subtle outline
    Canvas.DrawRoundedRect(0, 0, Sender.Width, Sender.Height, 8.0, 24 / 255, 25 / 255, 38 / 255, 0.98);
    Canvas.DrawRoundedRectOutline(0, 0, Sender.Width, Sender.Height, 8.0, 1.0, 69 / 255, 71 / 255, 90 / 255, 0.80);

    // 2. Header background band (top clock area)
    Canvas.DrawRoundedRect(1, 1, Sender.Width - 2, 65, 7.0, 36 / 255, 39 / 255, 58 / 255, 1.0);
    Canvas.DrawLine(12, 66, Sender.Width - 12, 66, 1.0, 49 / 255, 50 / 255, 68 / 255, 0.80);

    // 3. Digital Clock in bright text
    timeStr := FormatDateTime('hh:nn:ss', nowDt);
    if Assigned(FClockFont) and FClockFont.Valid then
      Canvas.DrawText(20, 18, timeStr, 0.85, 0.88, 0.95, FClockFont.Handle)
    else
      Canvas.DrawText(20, 18, timeStr, 0.85, 0.88, 0.95);

    // 4. Formatted Date subtitle
    dateStr := FormatDateTime('dddd, d mmmm yyyy', nowDt);
    Canvas.DrawText(20, 44, dateStr, 147 / 255, 153 / 255, 178 / 255);

    // 5. Month & Year Title
    monthYearStr := FormatDateTime('mmmm yyyy', EncodeDate(FViewYear, FViewMonth, 1));
    Canvas.DrawTextCentered(40, 73, Sender.Width - 80, 26, monthYearStr, 0.85, 0.88, 0.95);
  end
  else
  begin
    // 1. White card plate + subtle slate border
    Canvas.DrawRoundedRect(0, 0, Sender.Width, Sender.Height, 8.0, 1.0, 1.0, 1.0, 1.0);
    Canvas.DrawRoundedRectOutline(0, 0, Sender.Width, Sender.Height, 8.0, 1.0, 0.82, 0.85, 0.90, 1.0);

    // 2. Header background band (subtle light tint for top clock area)
    Canvas.DrawRoundedRect(1, 1, Sender.Width - 2, 65, 7.0, 0.97, 0.98, 0.99, 1.0);
    Canvas.DrawLine(12, 66, Sender.Width - 12, 66, 1.0, 0.88, 0.91, 0.94, 1.0);

    // 3. Digital Clock in dark slate (large font if available)
    timeStr := FormatDateTime('hh:nn:ss', nowDt);
    if Assigned(FClockFont) and FClockFont.Valid then
      Canvas.DrawText(20, 18, timeStr, 0.06, 0.09, 0.16, FClockFont.Handle)
    else
      Canvas.DrawText(20, 18, timeStr, 0.06, 0.09, 0.16);

    // 4. Formatted Date subtitle in medium slate
    dateStr := FormatDateTime('dddd, d mmmm yyyy', nowDt);
    Canvas.DrawText(20, 44, dateStr, 0.39, 0.45, 0.55);

    // 5. Month & Year Title in Navigation row (centered, click returns to Today)
    monthYearStr := FormatDateTime('mmmm yyyy', EncodeDate(FViewYear, FViewMonth, 1));
    Canvas.DrawTextCentered(40, 73, Sender.Width - 80, 26, monthYearStr, 0.12, 0.16, 0.23);
  end;

  // 6. Day of week names header
  gridX := 14;
  colW := 36;
  rowH := 26;

  for col := 0 to 6 do
  begin
    cellX := gridX + col * colW;
    if isDark then
    begin
      if col >= 5 then
        Canvas.DrawTextCentered(cellX, 104, colW, 18, DayNames[col], 186 / 255, 194 / 255, 222 / 255)
      else
        Canvas.DrawTextCentered(cellX, 104, colW, 18, DayNames[col], 147 / 255, 153 / 255, 178 / 255);
    end
    else
    begin
      if col >= 5 then
        Canvas.DrawTextCentered(cellX, 104, colW, 18, DayNames[col], 0.30, 0.35, 0.44)
      else
        Canvas.DrawTextCentered(cellX, 104, colW, 18, DayNames[col], 0.45, 0.50, 0.60);
    end;
  end;

  // 7. Days Grid: Full 6-week matrix (42 cells: 6 rows * 7 columns)
  // Monday = column 0, Sunday = column 6
  startCol := (DayOfWeek(EncodeDate(FViewYear, FViewMonth, 1)) + 5) mod 7;
  daysInMonth := MonthDays[IsLeapYear(FViewYear)][FViewMonth];

  // Previous month trailing days
  if FViewMonth = 1 then
  begin
    prevYear := FViewYear - 1;
    prevMonth := 12;
  end
  else
  begin
    prevYear := FViewYear;
    prevMonth := FViewMonth - 1;
  end;
  prevDaysInMonth := MonthDays[IsLeapYear(prevYear)][prevMonth];

  // A. Draw leading days from previous month
  for col := 0 to startCol - 1 do
  begin
    d := prevDaysInMonth - (startCol - 1 - col);
    cellX := gridX + col * colW;
    cellY := 126;
    if isDark then
      Canvas.DrawTextCentered(cellX, cellY, colW, rowH, IntToStr(d), 88 / 255, 91 / 255, 112 / 255)
    else
      Canvas.DrawTextCentered(cellX, cellY, colW, rowH, IntToStr(d), 0.70, 0.74, 0.80);
  end;

  // B. Draw current viewed month days
  badgeW := 26;
  badgeH := 24;
  for d := 1 to daysInMonth do
  begin
    cellIndex := startCol + d - 1;
    col := cellIndex mod 7;
    row := cellIndex div 7;
    cellX := gridX + col * colW;
    cellY := 126 + row * rowH;

    isToday := (FViewYear = curYr) and (FViewMonth = curMo) and (d = curDa);
    if isToday then
    begin
      bx := cellX + (colW - badgeW) div 2;
      by := cellY + (rowH - badgeH) div 2;
      if isDark then
      begin
        Canvas.DrawRoundedRect(bx, by, badgeW, badgeH, 6.0, 137 / 255, 180 / 255, 250 / 255, 1.0);
        Canvas.DrawTextCentered(cellX, cellY, colW, rowH, IntToStr(d), 17 / 255, 17 / 255, 27 / 255);
      end
      else
      begin
        Canvas.DrawRoundedRect(bx, by, badgeW, badgeH, 6.0, 0.15, 0.39, 0.92, 1.0);
        Canvas.DrawTextCentered(cellX, cellY, colW, rowH, IntToStr(d), 1.0, 1.0, 1.0);
      end;
    end
    else
    begin
      if isDark then
        Canvas.DrawTextCentered(cellX, cellY, colW, rowH, IntToStr(d), 0.85, 0.88, 0.95)
      else
        Canvas.DrawTextCentered(cellX, cellY, colW, rowH, IntToStr(d), 0.12, 0.16, 0.23);
    end;
  end;

  // C. Draw trailing days from next month up to 42 cells
  d := 1;
  for cellIndex := (startCol + daysInMonth) to 41 do
  begin
    col := cellIndex mod 7;
    row := cellIndex div 7;
    cellX := gridX + col * colW;
    cellY := 126 + row * rowH;
    if isDark then
      Canvas.DrawTextCentered(cellX, cellY, colW, rowH, IntToStr(d), 88 / 255, 91 / 255, 112 / 255)
    else
      Canvas.DrawTextCentered(cellX, cellY, colW, rowH, IntToStr(d), 0.70, 0.74, 0.80);
    Inc(d);
  end;
end;

procedure TShellClockApplet.HandlePopupWindowDismiss(Sender: TFtWindow);
begin
  HidePopup();
  if Assigned(FOnDismiss) then
    FOnDismiss(Self);
end;

procedure TShellClockApplet.CreatePopupWindow();
var
  popX, popY, popW, popH: Integer;
  curDt: TDateTime;
  curY, curM, curD: Word;
begin
  if Assigned(FPopupWindow) then Exit;

  popW := 280;
  popH := 300;

  curDt := Now();
  DecodeDate(curDt, curY, curM, curD);
  FViewYear := curY;
  FViewMonth := curM;

  if Assigned(FButton) and Assigned(FPanelWindow) then
  begin
    popX := FButton.X + (FButton.Width - popW) div 2;
    popX := Max(10, Min(popX, FPanelWindow.Width - popW - 10));
    if FPanelWindow.Y < 100 then
      popY := FPanelWindow.Y + FPanelWindow.Height + 4
    else
      popY := FPanelWindow.Y - popH - 4;
  end
  else
  begin
    popX := 100;
    popY := 100;
  end;

  FPopupWindow := TFtWindow.Create(popW, popH, 'shellsama-clock-popup');
  FPopupWindow.WindowType := ftwtPopupMenu;
  FPopupWindow.Borderless := True;
  FPopupWindow.SkipTaskbar := True;
  FPopupWindow.SetPosition(popX, popY);
  FPopupWindow.OnPopupDismiss := @HandlePopupWindowDismiss;

  // Background drawing area (card plate, digital clock, date, calendar grid)
  FPlate := TFtDrawingArea.Create(FPopupWindow, 0, 0, popW, popH);
  FPlate.OnPaint := @HandlePlatePaint;
  FPlate.OnMouseDown := @HandlePlateMouseDown;

  // Month navigation: Prev button
  FPrevBtn := TFtButton.Create(FPopupWindow, 14, 73, 26, 26, '<');
  FPrevBtn.Flat := True;
  FPrevBtn.CornerRadius := 4.0;
  FPrevBtn.OnClick := @HandlePrevClick;

  // Month navigation: Next button
  FNextBtn := TFtButton.Create(FPopupWindow, popW - 40, 73, 26, 26, '>');
  FNextBtn.Flat := True;
  FNextBtn.CornerRadius := 4.0;
  FNextBtn.OnClick := @HandleNextClick;

  ApplyThemeStyle();
end;

procedure TShellClockApplet.DestroyPopupWindow();
begin
  if Assigned(FPopupWindow) then
  begin
    FPlate := nil;
    FPrevBtn := nil;
    FNextBtn := nil;
    FPopupWindow.Free();
    FPopupWindow := nil;
  end;
end;

procedure TShellClockApplet.HandlePrevClick(Sender: TFtButton);
begin
  if FViewMonth <= 1 then
  begin
    FViewMonth := 12;
    Dec(FViewYear);
  end
  else
    Dec(FViewMonth);

  if Assigned(FPlate) then
    FPlate.Invalidate();
end;

procedure TShellClockApplet.HandleNextClick(Sender: TFtButton);
begin
  if FViewMonth >= 12 then
  begin
    FViewMonth := 1;
    Inc(FViewYear);
  end
  else
    Inc(FViewMonth);

  if Assigned(FPlate) then
    FPlate.Invalidate();
end;

procedure TShellClockApplet.HandlePlateMouseDown(Sender: TFtDrawingArea; X, Y, Button: Integer);
var
  curY, curM, curD: Word;
begin
  if (Y <= 102) and (FPlate <> nil) then
  begin
    DecodeDate(Now(), curY, curM, curD);
    if (FViewYear <> curY) or (FViewMonth <> curM) then
    begin
      FViewYear := curY;
      FViewMonth := curM;
      FPlate.Invalidate();
    end;
  end;
end;

procedure TShellClockApplet.UpdateClock();
var
  nowDt: TDateTime;
  sec: Integer;
begin
  nowDt := Now();
  sec := DateTimeToTimeStamp(nowDt).Time div 1000;
  if sec <> FLastClockSec then
  begin
    FLastClockSec := sec;
    if Assigned(FButton) then
    begin
      if SameText(ShellSettings().ClockFormat, '12h') then
        FButton.Caption := FormatDateTime('ddd d mmm  h:nn am/pm', nowDt)
      else
        FButton.Caption := FormatDateTime('ddd d mmm  hh:nn', nowDt);
    end;
    if IsPopupOpen() and Assigned(FPlate) then
      FPlate.Invalidate();
  end;
end;

procedure TShellClockApplet.ApplyThemeStyle();
begin
  if Assigned(FPlate) then
    FPlate.Invalidate();
  if Assigned(FPrevBtn) then
    FPrevBtn.Invalidate();
  if Assigned(FNextBtn) then
    FNextBtn.Invalidate();
  if Assigned(FPopupWindow) then
    FPopupWindow.Invalidate();
end;

procedure TShellClockApplet.ShowPopup();
var
  curY, curM, curD: Word;
  popX, popY, popW, popH: Integer;
begin
  DecodeDate(Now(), curY, curM, curD);
  FViewYear := curY;
  FViewMonth := curM;

  if not Assigned(FPopupWindow) then
    CreatePopupWindow()
  else if Assigned(FButton) and Assigned(FPanelWindow) then
  begin
    popW := FPopupWindow.Width;
    popH := FPopupWindow.Height;
    popX := FButton.X + (FButton.Width - popW) div 2;
    popX := Max(10, Min(popX, FPanelWindow.Width - popW - 10));
    if FPanelWindow.Y < 100 then
      popY := FPanelWindow.Y + FPanelWindow.Height + 4
    else
      popY := FPanelWindow.Y - popH - 4;
    FPopupWindow.SetPosition(popX, popY);
  end;

  ApplyThemeStyle();

  if Assigned(FPopupWindow) then
  begin
    FPopupWindow.Show();
    FPopupWindow.GrabPopupInput();
    if Assigned(FPlate) then
      FPlate.Invalidate();
    if Assigned(FButton) then
      FButton.Toggled := True;
  end;
end;

procedure TShellClockApplet.HidePopup();
begin
  if Assigned(FPopupWindow) then
  begin
    FPopupWindow.UngrabInput();
    FPopupWindow.Hide();
    if Assigned(FButton) then
      FButton.Toggled := False;
  end;
end;

procedure TShellClockApplet.TogglePopup();
begin
  if IsPopupOpen() then
    HidePopup()
  else
    ShowPopup();
end;

function TShellClockApplet.IsPopupOpen(): Boolean;
begin
  Result := Assigned(FPopupWindow) and FPopupWindow.Visible;
end;

procedure TShellClockApplet.HandleButtonClick(Sender: TFtButton);
begin
  TogglePopup();
end;

// =============================================================================
// TShellSessionApplet Implementation
// =============================================================================

constructor TShellSessionApplet.Create(AParentWindow: TFtWindow; AX, AY, AW, AH: Integer);
begin
  inherited Create();
  FPanelWindow := AParentWindow;
  FIsOpen := False;

  FButton := TFtButton.Create(FPanelWindow, AX, AY, AW, AH, '');
  FButton.Flat := True;
  FButton.IsToggle := True;
  FButton.CornerRadius := 6.0;
  FButton.IconPosition := ftipOnly;
  FButton.SetIconSize(18, 18);
  ApplyThemeStyle();
  FButton.OnClick := @HandleButtonClick;

  FMenu := TFtPopupMenu.Create(FPanelWindow);
  FMenu.AddItem('System Settings...', @HandleSettings);
  FMenu.AddSeparator();
  FMenu.AddItem('Lock Screen', @HandleLockScreen);
  FMenu.AddItem('Suspend', @HandleSuspend);
  FMenu.AddItem('Log Out...', @HandleLogOut);
  FMenu.AddSeparator();
  FMenu.AddItem('Restart...', @HandleRestart);
  FMenu.AddItem('Shut Down...', @HandleShutDown);
end;

destructor TShellSessionApplet.Destroy();
begin
  if Assigned(FMenu) then
  begin
    FMenu.Free();
    FMenu := nil;
  end;

  if Assigned(FButton) then
  begin
    FButton.Free();
    FButton := nil;
  end;

  inherited Destroy();
end;

procedure TShellSessionApplet.SetBounds(AX, AY, AW, AH: Integer);
begin
  if Assigned(FButton) then
    FButton.SetBounds(AX, AY, AW, AH);
end;

procedure TShellSessionApplet.ApplyThemeStyle();
var
  isDark: Boolean;
begin
  if FButton = nil then Exit;
  isDark := False;
  if FtIsLibLoaded() then
    isDark := FtApp().DarkMode;
  FButton.SetIconSVG(GetPowerIconSVG(isDark));
end;

procedure TShellSessionApplet.ShowPopup();
var
  menuX, menuY: Integer;
begin
  if FMenu = nil then Exit;

  if Assigned(FButton) and Assigned(FPanelWindow) then
  begin
    menuX := Max(10, FButton.X - 120);
    if FPanelWindow.Y < 100 then
      menuY := FPanelWindow.Y + FPanelWindow.Height + 4
    else
      menuY := FPanelWindow.Y - 170;
  end
  else
  begin
    menuX := 100;
    menuY := 100;
  end;

  FIsOpen := True;
  if Assigned(FButton) then
    FButton.Toggled := True;
  FMenu.Show(menuX, menuY);
end;

procedure TShellSessionApplet.HidePopup();
begin
  if Assigned(FMenu) then
    FMenu.Close();
  FIsOpen := False;
  if Assigned(FButton) then
    FButton.Toggled := False;
end;

procedure TShellSessionApplet.TogglePopup();
begin
  if IsPopupOpen() then
    HidePopup()
  else
    ShowPopup();
end;

function TShellSessionApplet.IsPopupOpen(): Boolean;
begin
  Result := FIsOpen and Assigned(FMenu) and FMenu.Visible;
  if not Result then
  begin
    FIsOpen := False;
    if Assigned(FButton) then
      FButton.Toggled := False;
  end;
end;

procedure TShellSessionApplet.HandleButtonClick(Sender: TFtButton);
begin
  TogglePopup();
end;

procedure TShellSessionApplet.HandleSettings(Sender: TFtMenuItem);
begin
  ExecShellCmdAsync('configsama');
end;

procedure TShellSessionApplet.HandleLockScreen(Sender: TFtMenuItem);
begin
  ExecShellCmdAsync('xdg-screensaver lock || loginctl lock-session || xflock4');
end;

procedure TShellSessionApplet.HandleSuspend(Sender: TFtMenuItem);
begin
  ExecShellCmdAsync('systemctl suspend');
end;

procedure TShellSessionApplet.HandleLogOut(Sender: TFtMenuItem);
begin
  ExecShellCmdAsync('loginctl terminate-user $USER || pkill -u $USER');
end;

procedure TShellSessionApplet.HandleRestart(Sender: TFtMenuItem);
begin
  ExecShellCmdAsync('systemctl reboot');
end;

procedure TShellSessionApplet.HandleShutDown(Sender: TFtMenuItem);
begin
  ExecShellCmdAsync('systemctl poweroff');
end;

// =============================================================================
// TShellBatteryApplet Implementation
// =============================================================================

constructor TShellBatteryApplet.Create(AParentWindow: TFtWindow; AX, AY, AW, AH: Integer);
begin
  inherited Create();
  FPanelWindow := AParentWindow;
  FCurPercentage := 100;
  FIsCharging := False;
  FIsBatteryPresent := False;
  FMockMode := False;
  FLastCheckTick := 0;
  FQueryBusy := False;
  FOnDismiss := nil;

  FButton := TFtButton.Create(FPanelWindow, AX, AY, AW, AH, '');
  FButton.Flat := True;
  FButton.IsToggle := True;
  FButton.CornerRadius := 6.0;
  FButton.IconPosition := ftipOnly;
  FButton.SetIconSize(18, 18);
  FButton.OnClick := @HandleButtonClick;

  QueryBattery(FCurPercentage, FIsCharging, FIsBatteryPresent);
  UpdateUI();
end;

destructor TShellBatteryApplet.Destroy();
begin
  DestroyPopupWindow();
  if Assigned(FButton) then
  begin
    FButton.Free();
    FButton := nil;
  end;
  inherited Destroy();
end;

procedure TShellBatteryApplet.SetBounds(AX, AY, AW, AH: Integer);
begin
  if Assigned(FButton) then
    FButton.SetBounds(AX, AY, AW, AH);
end;

function TShellBatteryApplet.QueryBattery(out APercent: Integer; out ACharging: Boolean; out APresent: Boolean): Boolean;
var
  batPath: string;
  capStr, statStr: string;
  info: TSearchRec;
begin
  APercent := 100;
  ACharging := False;
  APresent := False;
  Result := False;

  batPath := '';
  if FindFirst('/sys/class/power_supply/BAT*', faAnyFile, info) = 0 then
  begin
    repeat
      if (info.Name <> '.') and (info.Name <> '..') then
      begin
        batPath := '/sys/class/power_supply/' + info.Name;
        Break;
      end;
    until FindNext(info) <> 0;
    FindClose(info);
  end;

  if (batPath <> '') and DirectoryExists(batPath) then
  begin
    APresent := True;
    capStr := ReadSysfsFirstLine(batPath + '/capacity');
    statStr := ReadSysfsFirstLine(batPath + '/status');
    APercent := EnsureRange(StrToIntDef(capStr, 100), 0, 100);
    ACharging := SameText(statStr, 'Charging');
    Result := True;
    Exit;
  end;

  // Check if AC adapter is present (desktop system without battery)
  if DirectoryExists('/sys/class/power_supply/ACAD') or
     (FindFirst('/sys/class/power_supply/AC*', faAnyFile, info) = 0) then
  begin
    if info.Name <> '' then
      FindClose(info);
    APresent := False;
    APercent := 100;
    ACharging := False;
    Result := True;
  end;
end;

procedure TShellBatteryApplet.SetBatteryState(APercent: Integer; ACharging: Boolean; APresent: Boolean);
begin
  FMockMode := True;
  FCurPercentage := EnsureRange(APercent, 0, 100);
  FIsCharging := ACharging;
  FIsBatteryPresent := APresent;
  UpdateUI();
  if IsPopupOpen() then
  begin
    UpdatePopupContent();
    if Assigned(FPlate) then
      FPlate.Invalidate();
  end;
end;

procedure TShellBatteryApplet.ApplyThemeStyle();
var
  isDark: Boolean;
begin
  UpdateUI();
  isDark := IsDarkTheme();

  if Assigned(FStatusLabel) then
  begin
    if isDark then
      FStatusLabel.SetColor(0.85, 0.88, 0.95)
    else
      FStatusLabel.SetColor(0.12, 0.16, 0.23);
  end;

  if Assigned(FPercentageLabel) then
  begin
    if isDark then
      FPercentageLabel.SetColor(0.65, 0.70, 0.80)
    else
      FPercentageLabel.SetColor(0.40, 0.45, 0.55);
  end;

  if Assigned(FPlate) then
    FPlate.Invalidate();
  if Assigned(FSettingsBtn) then
    FSettingsBtn.Invalidate();
  if Assigned(FPopupWindow) then
    FPopupWindow.Invalidate();
end;

procedure TShellBatteryApplet.UpdateUI();
var
  isDark: Boolean;
begin
  if FButton = nil then Exit;

  isDark := IsDarkTheme();
  FButton.Caption := '';
  FButton.IconPosition := ftipOnly;
  FButton.SetIconSize(18, 18);
  FButton.SetIconSVG(GetBatteryIconSVG(FCurPercentage, FIsCharging, FIsBatteryPresent, isDark));
end;

procedure TShellBatteryApplet.HandlePlatePaint(Sender: TFtDrawingArea; Canvas: TFtCanvas);
var
  isDark: Boolean;
  barX, barY, barW, barH: Integer;
  fillW: Integer;
begin
  if not Assigned(Sender) or not Assigned(Canvas) then Exit;

  isDark := IsDarkTheme();
  if isDark then
  begin
    Canvas.DrawRoundedRect(0, 0, Sender.Width, Sender.Height, 6.0, 24 / 255, 25 / 255, 38 / 255, 0.98);
    Canvas.DrawRoundedRectOutline(0, 0, Sender.Width, Sender.Height, 6.0, 1.0, 69 / 255, 71 / 255, 90 / 255, 0.80);
  end
  else
  begin
    Canvas.DrawRoundedRect(0, 0, Sender.Width, Sender.Height, 6.0, 1.0, 1.0, 1.0, 1.0);
    Canvas.DrawRoundedRectOutline(0, 0, Sender.Width, Sender.Height, 6.0, 1.0, 0.80, 0.84, 0.88, 1.0);
  end;

  barX := 16;
  barY := 34;
  barW := Sender.Width - 32;
  barH := 10;

  if isDark then
    Canvas.DrawRoundedRect(barX, barY, barW, barH, 4.0, 49 / 255, 50 / 255, 68 / 255, 1.0)
  else
    Canvas.DrawRoundedRect(barX, barY, barW, barH, 4.0, 0.88, 0.91, 0.94, 1.0);

  if FIsBatteryPresent and (FCurPercentage > 0) then
  begin
    fillW := Max(6, Round((FCurPercentage / 100.0) * barW));
    if FIsCharging then
      Canvas.DrawRoundedRect(barX, barY, fillW, barH, 4.0, 0.18, 0.80, 0.44, 1.0)
    else if FCurPercentage <= 20 then
      Canvas.DrawRoundedRect(barX, barY, fillW, barH, 4.0, 0.92, 0.26, 0.21, 1.0)
    else
      Canvas.DrawRoundedRect(barX, barY, fillW, barH, 4.0, 0.20, 0.60, 0.86, 1.0);
  end;
end;

procedure TShellBatteryApplet.HandlePopupWindowDismiss(Sender: TFtWindow);
begin
  HidePopup();
  if Assigned(FOnDismiss) then
    FOnDismiss(Self);
end;

procedure TShellBatteryApplet.HandleSettingsClick(Sender: TFtButton);
begin
  HidePopup();
  if Assigned(FOnDismiss) then
    FOnDismiss(Self);
  ExecShellCmdAsync('configsama Power || configsama');
end;

procedure TShellBatteryApplet.UpdatePopupContent();
var
  statText, pctText: string;
begin
  if not Assigned(FPopupWindow) then Exit;
  if not FIsBatteryPresent then
  begin
    statText := 'Power Source: AC';
    pctText := 'No battery detected';
  end
  else
  begin
    if FIsCharging then
      statText := 'Battery: Charging (' + IntToStr(FCurPercentage) + '%)'
    else if FCurPercentage >= 100 then
      statText := 'Battery: Fully Charged'
    else
      statText := 'Battery: Discharging (' + IntToStr(FCurPercentage) + '%)';
    pctText := IntToStr(FCurPercentage) + '% available';
  end;

  if Assigned(FStatusLabel) then
    FStatusLabel.Text := statText;
  if Assigned(FPercentageLabel) then
    FPercentageLabel.Text := pctText;
end;

procedure TShellBatteryApplet.CreatePopupWindow();
var
  popX, popY, popW, popH: Integer;
begin
  if Assigned(FPopupWindow) then Exit;

  popW := 220;
  popH := 105;

  if Assigned(FButton) and Assigned(FPanelWindow) then
  begin
    popX := FButton.X + (FButton.Width - popW) div 2;
    popX := Max(10, Min(popX, FPanelWindow.Width - popW - 10));
    if FPanelWindow.Y < 100 then
      popY := FPanelWindow.Y + FPanelWindow.Height + 4
    else
      popY := FPanelWindow.Y - popH - 4;
  end
  else
  begin
    popX := 100;
    popY := 100;
  end;

  FPopupWindow := TFtWindow.Create(popW, popH, 'shellsama-battery-popup');
  FPopupWindow.WindowType := ftwtPopupMenu;
  FPopupWindow.Borderless := True;
  FPopupWindow.SkipTaskbar := True;
  FPopupWindow.SetPosition(popX, popY);
  FPopupWindow.OnPopupDismiss := @HandlePopupWindowDismiss;

  FPlate := TFtDrawingArea.Create(FPopupWindow, 0, 0, popW, popH);
  FPlate.OnPaint := @HandlePlatePaint;

  FStatusLabel := TFtLabel.Create(FPopupWindow, 16, 10, popW - 32, 18, '');
  FStatusLabel.Alignment := ftaLeft;

  FPercentageLabel := TFtLabel.Create(FPopupWindow, 16, 48, popW - 32, 16, '');
  FPercentageLabel.Alignment := ftaLeft;

  FSettingsBtn := TFtButton.Create(FPopupWindow, 16, 70, popW - 32, 24, 'Power Settings...');
  FSettingsBtn.Flat := True;
  FSettingsBtn.CornerRadius := 4.0;
  FSettingsBtn.OnClick := @HandleSettingsClick;

  UpdatePopupContent();
  ApplyThemeStyle();
end;

procedure TShellBatteryApplet.DestroyPopupWindow();
begin
  if Assigned(FPopupWindow) then
  begin
    FPlate := nil;
    FStatusLabel := nil;
    FPercentageLabel := nil;
    FSettingsBtn := nil;
    FPopupWindow.Free();
    FPopupWindow := nil;
  end;
end;

procedure TShellBatteryApplet.ShowPopup();
begin
  if not Assigned(FPopupWindow) then
    CreatePopupWindow();
  UpdatePopupContent();
  ApplyThemeStyle();
  if Assigned(FPopupWindow) then
  begin
    FPopupWindow.Show();
    FPopupWindow.GrabPopupInput();
    if Assigned(FPlate) then
      FPlate.Invalidate();
    if Assigned(FButton) then
      FButton.Toggled := True;
  end;
end;

procedure TShellBatteryApplet.HidePopup();
begin
  if Assigned(FPopupWindow) then
  begin
    FPopupWindow.UngrabInput();
    FPopupWindow.Hide();
    if Assigned(FButton) then
      FButton.Toggled := False;
  end;
end;

procedure TShellBatteryApplet.TogglePopup();
begin
  if IsPopupOpen() then
    HidePopup()
  else
    ShowPopup();
end;

function TShellBatteryApplet.IsPopupOpen(): Boolean;
begin
  Result := Assigned(FPopupWindow) and FPopupWindow.Visible;
end;

procedure TShellBatteryApplet.HandleButtonClick(Sender: TFtButton);
begin
  TogglePopup();
end;

procedure TShellBatteryApplet.Tick();
var
  nowTick: Int64;
  curPct: Integer;
  curChg, curPres: Boolean;
begin
  if FMockMode then Exit;
  nowTick := GetTickCount64();
  if (nowTick - FLastCheckTick < 3000) or FQueryBusy then Exit;
  FLastCheckTick := nowTick;
  FQueryBusy := True;
  try
    if QueryBattery(curPct, curChg, curPres) then
    begin
      if (curPct <> FCurPercentage) or (curChg <> FIsCharging) or (curPres <> FIsBatteryPresent) then
      begin
        FCurPercentage := curPct;
        FIsCharging := curChg;
        FIsBatteryPresent := curPres;
        UpdateUI();
        if IsPopupOpen() then
        begin
          UpdatePopupContent();
          if Assigned(FPlate) then
            FPlate.Invalidate();
        end;
      end;
    end;
  finally
    FQueryBusy := False;
  end;
end;

// =============================================================================
// TShellWiredApplet Implementation
// =============================================================================

constructor TShellWiredApplet.Create(AParentWindow: TFtWindow; AX, AY, AW, AH: Integer);
begin
  inherited Create();
  FPanelWindow := AParentWindow;
  FIsConnected := False;
  FInterfaceName := '';
  FIpAddress := '';
  FMockMode := False;
  FLastCheckTick := 0;
  FQueryBusy := False;
  FOnDismiss := nil;

  FButton := TFtButton.Create(FPanelWindow, AX, AY, AW, AH, '');
  FButton.Flat := True;
  FButton.IsToggle := True;
  FButton.CornerRadius := 6.0;
  FButton.IconPosition := ftipOnly;
  FButton.SetIconSize(18, 18);
  FButton.OnClick := @HandleButtonClick;

  QueryWired(FIsConnected, FInterfaceName, FIpAddress);
  UpdateUI();
end;

destructor TShellWiredApplet.Destroy();
begin
  DestroyPopupWindow();
  if Assigned(FButton) then
  begin
    FButton.Free();
    FButton := nil;
  end;
  inherited Destroy();
end;

procedure TShellWiredApplet.SetBounds(AX, AY, AW, AH: Integer);
begin
  if Assigned(FButton) then
    FButton.SetBounds(AX, AY, AW, AH);
end;

function TShellWiredApplet.QueryWired(out AConnected: Boolean; out AInterfaceName: string; out AIpAddress: string): Boolean;
var
  info: TSearchRec;
  devName, devPath: string;
  carrierStr, operStr: string;
  nmOut: string;
  lines: TStringList;
  i, p: Integer;
begin
  AConnected := False;
  AInterfaceName := '';
  AIpAddress := '';
  Result := False;

  if FindFirst('/sys/class/net/*', faAnyFile, info) = 0 then
  begin
    repeat
      devName := info.Name;
      if (devName <> '.') and (devName <> '..') and (devName <> 'lo') and
         (Pos('wl', devName) <> 1) and (Pos('ww', devName) <> 1) and
         (Pos('docker', devName) <> 1) and (Pos('veth', devName) <> 1) and
         (Pos('virbr', devName) <> 1) and (Pos('br-', devName) <> 1) then
      begin
        devPath := '/sys/class/net/' + devName;
        carrierStr := ReadSysfsFirstLine(devPath + '/carrier');
        operStr := ReadSysfsFirstLine(devPath + '/operstate');
        if (carrierStr = '1') or SameText(operStr, 'up') then
        begin
          AConnected := True;
          AInterfaceName := devName;
          Break;
        end
        else if AInterfaceName = '' then
          AInterfaceName := devName;
      end;
    until FindNext(info) <> 0;
    FindClose(info);
  end;

  if AConnected and (AInterfaceName <> '') then
  begin
    if RunCommand('/usr/bin/nmcli', ['-t', '-f', 'IP4.ADDRESS', 'dev', 'show', AInterfaceName], nmOut) then
    begin
      lines := TStringList.Create();
      try
        lines.Text := Trim(nmOut);
        for i := 0 to lines.Count - 1 do
        begin
          p := Pos('IP4.ADDRESS', lines[i]);
          if p > 0 then
          begin
            AIpAddress := Trim(Copy(lines[i], Pos(':', lines[i]) + 1, Length(lines[i])));
            Break;
          end;
        end;
      finally
        lines.Free();
      end;
    end;
  end;

  Result := (AInterfaceName <> '');
end;

procedure TShellWiredApplet.SetWiredState(AConnected: Boolean; const AInterfaceName: string; const AIpAddress: string);
begin
  FMockMode := True;
  FIsConnected := AConnected;
  FInterfaceName := AInterfaceName;
  FIpAddress := AIpAddress;
  UpdateUI();
  if IsPopupOpen() then
  begin
    UpdatePopupContent();
    if Assigned(FPlate) then
      FPlate.Invalidate();
  end;
end;

procedure TShellWiredApplet.ApplyThemeStyle();
var
  isDark: Boolean;
begin
  UpdateUI();
  isDark := IsDarkTheme();

  if Assigned(FStatusLabel) then
  begin
    if isDark then
      FStatusLabel.SetColor(0.85, 0.88, 0.95)
    else
      FStatusLabel.SetColor(0.12, 0.16, 0.23);
  end;

  if Assigned(FDetailsLabel) then
  begin
    if isDark then
      FDetailsLabel.SetColor(0.65, 0.70, 0.80)
    else
      FDetailsLabel.SetColor(0.40, 0.45, 0.55);
  end;

  if Assigned(FPlate) then
    FPlate.Invalidate();
  if Assigned(FSettingsBtn) then
    FSettingsBtn.Invalidate();
  if Assigned(FPopupWindow) then
    FPopupWindow.Invalidate();
end;

procedure TShellWiredApplet.UpdateUI();
var
  isDark: Boolean;
begin
  if FButton = nil then Exit;

  isDark := IsDarkTheme();
  FButton.Caption := '';
  FButton.IconPosition := ftipOnly;
  FButton.SetIconSize(18, 18);
  FButton.SetIconSVG(GetWiredIconSVG(FIsConnected, isDark));
end;

procedure TShellWiredApplet.HandlePlatePaint(Sender: TFtDrawingArea; Canvas: TFtCanvas);
var
  isDark: Boolean;
begin
  if not Assigned(Sender) or not Assigned(Canvas) then Exit;

  isDark := IsDarkTheme();
  if isDark then
  begin
    Canvas.DrawRoundedRect(0, 0, Sender.Width, Sender.Height, 6.0, 24 / 255, 25 / 255, 38 / 255, 0.98);
    Canvas.DrawRoundedRectOutline(0, 0, Sender.Width, Sender.Height, 6.0, 1.0, 69 / 255, 71 / 255, 90 / 255, 0.80);
  end
  else
  begin
    Canvas.DrawRoundedRect(0, 0, Sender.Width, Sender.Height, 6.0, 1.0, 1.0, 1.0, 1.0);
    Canvas.DrawRoundedRectOutline(0, 0, Sender.Width, Sender.Height, 6.0, 1.0, 0.80, 0.84, 0.88, 1.0);
  end;
end;

procedure TShellWiredApplet.HandlePopupWindowDismiss(Sender: TFtWindow);
begin
  HidePopup();
  if Assigned(FOnDismiss) then
    FOnDismiss(Self);
end;

procedure TShellWiredApplet.HandleSettingsClick(Sender: TFtButton);
begin
  HidePopup();
  if Assigned(FOnDismiss) then
    FOnDismiss(Self);
  ExecShellCmdAsync('configsama Wired || configsama');
end;

procedure TShellWiredApplet.UpdatePopupContent();
var
  statText, detText: string;
begin
  if not Assigned(FPopupWindow) then Exit;
  if FIsConnected then
  begin
    statText := 'Wired: Connected';
    if FIpAddress <> '' then
      detText := FInterfaceName + ' (' + FIpAddress + ')'
    else if FInterfaceName <> '' then
      detText := 'Interface: ' + FInterfaceName
    else
      detText := 'Cable connected';
  end
  else
  begin
    statText := 'Wired: Disconnected';
    if FInterfaceName <> '' then
      detText := FInterfaceName + ' (Cable unplugged)'
    else
      detText := 'No ethernet link';
  end;

  if Assigned(FStatusLabel) then
    FStatusLabel.Text := statText;
  if Assigned(FDetailsLabel) then
    FDetailsLabel.Text := detText;
end;

procedure TShellWiredApplet.CreatePopupWindow();
var
  popX, popY, popW, popH: Integer;
begin
  if Assigned(FPopupWindow) then Exit;

  popW := 220;
  popH := 95;

  if Assigned(FButton) and Assigned(FPanelWindow) then
  begin
    popX := FButton.X + (FButton.Width - popW) div 2;
    popX := Max(10, Min(popX, FPanelWindow.Width - popW - 10));
    if FPanelWindow.Y < 100 then
      popY := FPanelWindow.Y + FPanelWindow.Height + 4
    else
      popY := FPanelWindow.Y - popH - 4;
  end
  else
  begin
    popX := 100;
    popY := 100;
  end;

  FPopupWindow := TFtWindow.Create(popW, popH, 'shellsama-wired-popup');
  FPopupWindow.WindowType := ftwtPopupMenu;
  FPopupWindow.Borderless := True;
  FPopupWindow.SkipTaskbar := True;
  FPopupWindow.SetPosition(popX, popY);
  FPopupWindow.OnPopupDismiss := @HandlePopupWindowDismiss;

  FPlate := TFtDrawingArea.Create(FPopupWindow, 0, 0, popW, popH);
  FPlate.OnPaint := @HandlePlatePaint;

  FStatusLabel := TFtLabel.Create(FPopupWindow, 16, 12, popW - 32, 18, '');
  FStatusLabel.Alignment := ftaLeft;

  FDetailsLabel := TFtLabel.Create(FPopupWindow, 16, 34, popW - 32, 16, '');
  FDetailsLabel.Alignment := ftaLeft;

  FSettingsBtn := TFtButton.Create(FPopupWindow, 16, 58, popW - 32, 24, 'Wired Settings...');
  FSettingsBtn.Flat := True;
  FSettingsBtn.CornerRadius := 4.0;
  FSettingsBtn.OnClick := @HandleSettingsClick;

  UpdatePopupContent();
  ApplyThemeStyle();
end;

procedure TShellWiredApplet.DestroyPopupWindow();
begin
  if Assigned(FPopupWindow) then
  begin
    FPlate := nil;
    FStatusLabel := nil;
    FDetailsLabel := nil;
    FSettingsBtn := nil;
    FPopupWindow.Free();
    FPopupWindow := nil;
  end;
end;

procedure TShellWiredApplet.ShowPopup();
begin
  if not Assigned(FPopupWindow) then
    CreatePopupWindow();
  UpdatePopupContent();
  ApplyThemeStyle();
  if Assigned(FPopupWindow) then
  begin
    FPopupWindow.Show();
    FPopupWindow.GrabPopupInput();
    if Assigned(FPlate) then
      FPlate.Invalidate();
    if Assigned(FButton) then
      FButton.Toggled := True;
  end;
end;

procedure TShellWiredApplet.HidePopup();
begin
  if Assigned(FPopupWindow) then
  begin
    FPopupWindow.UngrabInput();
    FPopupWindow.Hide();
    if Assigned(FButton) then
      FButton.Toggled := False;
  end;
end;

procedure TShellWiredApplet.TogglePopup();
begin
  if IsPopupOpen() then
    HidePopup()
  else
    ShowPopup();
end;

function TShellWiredApplet.IsPopupOpen(): Boolean;
begin
  Result := Assigned(FPopupWindow) and FPopupWindow.Visible;
end;

procedure TShellWiredApplet.HandleButtonClick(Sender: TFtButton);
begin
  TogglePopup();
end;

procedure TShellWiredApplet.Tick();
var
  nowTick: Int64;
  curConn: Boolean;
  curIface, curIp: string;
begin
  if FMockMode then Exit;
  nowTick := GetTickCount64();
  if (nowTick - FLastCheckTick < 3000) or FQueryBusy then Exit;
  FLastCheckTick := nowTick;
  FQueryBusy := True;
  try
    if QueryWired(curConn, curIface, curIp) then
    begin
      if (curConn <> FIsConnected) or (curIface <> FInterfaceName) or (curIp <> FIpAddress) then
      begin
        FIsConnected := curConn;
        FInterfaceName := curIface;
        FIpAddress := curIp;
        UpdateUI();
        if IsPopupOpen() then
        begin
          UpdatePopupContent();
          if Assigned(FPlate) then
            FPlate.Invalidate();
        end;
      end;
    end;
  finally
    FQueryBusy := False;
  end;
end;

// =============================================================================
// TShellLanApplet Implementation
// =============================================================================

constructor TShellLanApplet.Create(AParentWindow: TFtWindow; AX, AY, AW, AH: Integer);
begin
  inherited Create();
  FPanelWindow := AParentWindow;
  FIsConnected := False;
  FIsEnabled := True;
  FSsid := '';
  FSignal := 0;
  FMockMode := False;
  FLastCheckTick := 0;
  FQueryBusy := False;
  FOnDismiss := nil;

  FButton := TFtButton.Create(FPanelWindow, AX, AY, AW, AH, '');
  FButton.Flat := True;
  FButton.IsToggle := True;
  FButton.CornerRadius := 6.0;
  FButton.IconPosition := ftipOnly;
  FButton.SetIconSize(18, 18);
  FButton.OnClick := @HandleButtonClick;

  QueryLan(FIsConnected, FSsid, FSignal, FIsEnabled);
  UpdateUI();
end;

destructor TShellLanApplet.Destroy();
begin
  DestroyPopupWindow();
  if Assigned(FButton) then
  begin
    FButton.Free();
    FButton := nil;
  end;
  inherited Destroy();
end;

procedure TShellLanApplet.SetBounds(AX, AY, AW, AH: Integer);
begin
  if Assigned(FButton) then
    FButton.SetBounds(AX, AY, AW, AH);
end;

function TShellLanApplet.QueryLan(out AConnected: Boolean; out ASsid: string; out ASignal: Integer; out AEnabled: Boolean): Boolean;
var
  nmOut: string;
  lines: TStringList;
  i, p: Integer;
  line, restField, ssidField, sigField: string;
begin
  AConnected := False;
  ASsid := '';
  ASignal := 0;
  AEnabled := True;
  Result := False;

  if RunCommand('/usr/bin/nmcli', ['-t', '-f', 'active,ssid,signal', 'dev', 'wifi'], nmOut) then
  begin
    lines := TStringList.Create();
    try
      lines.Text := Trim(nmOut);
      for i := 0 to lines.Count - 1 do
      begin
        line := lines[i];
        if Pos('yes:', line) = 1 then
        begin
          AConnected := True;
          restField := Copy(line, 5, Length(line));
          p := LastDelimiter(':', restField);
          if p > 0 then
          begin
            ssidField := Copy(restField, 1, p - 1);
            sigField := Copy(restField, p + 1, Length(restField));
            ASsid := ssidField;
            ASignal := StrToIntDef(sigField, 50);
          end
          else
            ASsid := restField;
          Break;
        end;
      end;
      Result := True;
    finally
      lines.Free();
    end;
  end;

  if not AConnected then
  begin
    if RunCommand('/usr/bin/nmcli', ['radio', 'wifi'], nmOut) then
      AEnabled := SameText(Trim(nmOut), 'enabled');
  end;
end;

procedure TShellLanApplet.SetLanState(AConnected: Boolean; const ASsid: string; ASignal: Integer; AEnabled: Boolean);
begin
  FMockMode := True;
  FIsConnected := AConnected;
  FSsid := ASsid;
  FSignal := EnsureRange(ASignal, 0, 100);
  FIsEnabled := AEnabled;
  UpdateUI();
  if IsPopupOpen() then
  begin
    UpdatePopupContent();
    if Assigned(FPlate) then
      FPlate.Invalidate();
  end;
end;

procedure TShellLanApplet.ToggleLan();
var
  dummy: string;
begin
  if FIsEnabled then
    RunCommand('/usr/bin/nmcli', ['radio', 'wifi', 'off'], dummy)
  else
    RunCommand('/usr/bin/nmcli', ['radio', 'wifi', 'on'], dummy);
  FIsEnabled := not FIsEnabled;
  UpdateUI();
  if IsPopupOpen() then
  begin
    UpdatePopupContent();
    if Assigned(FPlate) then
      FPlate.Invalidate();
  end;
end;

procedure TShellLanApplet.ApplyThemeStyle();
var
  isDark: Boolean;
begin
  UpdateUI();
  isDark := IsDarkTheme();

  if Assigned(FStatusLabel) then
  begin
    if isDark then
      FStatusLabel.SetColor(0.85, 0.88, 0.95)
    else
      FStatusLabel.SetColor(0.12, 0.16, 0.23);
  end;

  if Assigned(FDetailsLabel) then
  begin
    if isDark then
      FDetailsLabel.SetColor(0.65, 0.70, 0.80)
    else
      FDetailsLabel.SetColor(0.40, 0.45, 0.55);
  end;

  if Assigned(FPlate) then
    FPlate.Invalidate();
  if Assigned(FToggleBtn) then
    FToggleBtn.Invalidate();
  if Assigned(FSettingsBtn) then
    FSettingsBtn.Invalidate();
  if Assigned(FPopupWindow) then
    FPopupWindow.Invalidate();
end;

procedure TShellLanApplet.UpdateUI();
var
  isDark: Boolean;
begin
  if FButton = nil then Exit;

  isDark := IsDarkTheme();
  FButton.Caption := '';
  FButton.IconPosition := ftipOnly;
  FButton.SetIconSize(18, 18);
  FButton.SetIconSVG(GetLanIconSVG(FIsConnected, FSignal, FIsEnabled, isDark));
end;

procedure TShellLanApplet.HandlePlatePaint(Sender: TFtDrawingArea; Canvas: TFtCanvas);
var
  isDark: Boolean;
begin
  if not Assigned(Sender) or not Assigned(Canvas) then Exit;

  isDark := IsDarkTheme();
  if isDark then
  begin
    Canvas.DrawRoundedRect(0, 0, Sender.Width, Sender.Height, 6.0, 24 / 255, 25 / 255, 38 / 255, 0.98);
    Canvas.DrawRoundedRectOutline(0, 0, Sender.Width, Sender.Height, 6.0, 1.0, 69 / 255, 71 / 255, 90 / 255, 0.80);
  end
  else
  begin
    Canvas.DrawRoundedRect(0, 0, Sender.Width, Sender.Height, 6.0, 1.0, 1.0, 1.0, 1.0);
    Canvas.DrawRoundedRectOutline(0, 0, Sender.Width, Sender.Height, 6.0, 1.0, 0.80, 0.84, 0.88, 1.0);
  end;
end;

procedure TShellLanApplet.HandlePopupWindowDismiss(Sender: TFtWindow);
begin
  HidePopup();
  if Assigned(FOnDismiss) then
    FOnDismiss(Self);
end;

procedure TShellLanApplet.HandleToggleClick(Sender: TFtButton);
begin
  ToggleLan();
end;

procedure TShellLanApplet.HandleSettingsClick(Sender: TFtButton);
begin
  HidePopup();
  if Assigned(FOnDismiss) then
    FOnDismiss(Self);
  ExecShellCmdAsync('configsama WLAN || configsama');
end;

procedure TShellLanApplet.UpdatePopupContent();
var
  statText, detText: string;
begin
  if not Assigned(FPopupWindow) then Exit;
  if not FIsEnabled then
  begin
    statText := 'Wi-Fi: Disabled';
    detText := 'Wireless radio is off';
  end
  else if FIsConnected then
  begin
    statText := 'Wi-Fi: Connected';
    if FSsid <> '' then
      detText := FSsid + ' (' + IntToStr(FSignal) + '%)'
    else
      detText := 'Signal: ' + IntToStr(FSignal) + '%';
  end
  else
  begin
    statText := 'Wi-Fi: Disconnected';
    detText := 'Not connected to any network';
  end;

  if Assigned(FStatusLabel) then
    FStatusLabel.Text := statText;
  if Assigned(FDetailsLabel) then
    FDetailsLabel.Text := detText;
end;

procedure TShellLanApplet.CreatePopupWindow();
var
  popX, popY, popW, popH: Integer;
begin
  if Assigned(FPopupWindow) then Exit;

  popW := 240;
  popH := 105;

  if Assigned(FButton) and Assigned(FPanelWindow) then
  begin
    popX := FButton.X + (FButton.Width - popW) div 2;
    popX := Max(10, Min(popX, FPanelWindow.Width - popW - 10));
    if FPanelWindow.Y < 100 then
      popY := FPanelWindow.Y + FPanelWindow.Height + 4
    else
      popY := FPanelWindow.Y - popH - 4;
  end
  else
  begin
    popX := 100;
    popY := 100;
  end;

  FPopupWindow := TFtWindow.Create(popW, popH, 'shellsama-lan-popup');
  FPopupWindow.WindowType := ftwtPopupMenu;
  FPopupWindow.Borderless := True;
  FPopupWindow.SkipTaskbar := True;
  FPopupWindow.SetPosition(popX, popY);
  FPopupWindow.OnPopupDismiss := @HandlePopupWindowDismiss;

  FPlate := TFtDrawingArea.Create(FPopupWindow, 0, 0, popW, popH);
  FPlate.OnPaint := @HandlePlatePaint;

  FStatusLabel := TFtLabel.Create(FPopupWindow, 16, 12, popW - 32, 18, '');
  FStatusLabel.Alignment := ftaLeft;

  FDetailsLabel := TFtLabel.Create(FPopupWindow, 16, 34, popW - 32, 16, '');
  FDetailsLabel.Alignment := ftaLeft;

  FToggleBtn := TFtButton.Create(FPopupWindow, 16, 62, 95, 26, 'Toggle Wi-Fi');
  FToggleBtn.Flat := True;
  FToggleBtn.CornerRadius := 4.0;
  FToggleBtn.OnClick := @HandleToggleClick;

  FSettingsBtn := TFtButton.Create(FPopupWindow, 116, 62, popW - 132, 26, 'Wi-Fi Settings...');
  FSettingsBtn.Flat := True;
  FSettingsBtn.CornerRadius := 4.0;
  FSettingsBtn.OnClick := @HandleSettingsClick;

  UpdatePopupContent();
  ApplyThemeStyle();
end;

procedure TShellLanApplet.DestroyPopupWindow();
begin
  if Assigned(FPopupWindow) then
  begin
    FPlate := nil;
    FStatusLabel := nil;
    FDetailsLabel := nil;
    FToggleBtn := nil;
    FSettingsBtn := nil;
    FPopupWindow.Free();
    FPopupWindow := nil;
  end;
end;

procedure TShellLanApplet.ShowPopup();
begin
  if not Assigned(FPopupWindow) then
    CreatePopupWindow();
  UpdatePopupContent();
  ApplyThemeStyle();
  if Assigned(FPopupWindow) then
  begin
    FPopupWindow.Show();
    FPopupWindow.GrabPopupInput();
    if Assigned(FPlate) then
      FPlate.Invalidate();
    if Assigned(FButton) then
      FButton.Toggled := True;
  end;
end;

procedure TShellLanApplet.HidePopup();
begin
  if Assigned(FPopupWindow) then
  begin
    FPopupWindow.UngrabInput();
    FPopupWindow.Hide();
    if Assigned(FButton) then
      FButton.Toggled := False;
  end;
end;

procedure TShellLanApplet.TogglePopup();
begin
  if IsPopupOpen() then
    HidePopup()
  else
    ShowPopup();
end;

function TShellLanApplet.IsPopupOpen(): Boolean;
begin
  Result := Assigned(FPopupWindow) and FPopupWindow.Visible;
end;

procedure TShellLanApplet.HandleButtonClick(Sender: TFtButton);
begin
  TogglePopup();
end;

procedure TShellLanApplet.Tick();
var
  nowTick: Int64;
  curConn, curEn: Boolean;
  curSsid: string;
  curSig: Integer;
begin
  if FMockMode then Exit;
  nowTick := GetTickCount64();
  if (nowTick - FLastCheckTick < 3000) or FQueryBusy then Exit;
  FLastCheckTick := nowTick;
  FQueryBusy := True;
  try
    if QueryLan(curConn, curSsid, curSig, curEn) then
    begin
      if (curConn <> FIsConnected) or (curSsid <> FSsid) or (curSig <> FSignal) or (curEn <> FIsEnabled) then
      begin
        FIsConnected := curConn;
        FSsid := curSsid;
        FSignal := curSig;
        FIsEnabled := curEn;
        UpdateUI();
        if IsPopupOpen() then
        begin
          UpdatePopupContent();
          if Assigned(FPlate) then
            FPlate.Invalidate();
        end;
      end;
    end;
  finally
    FQueryBusy := False;
  end;
end;

// =============================================================================
// TShellBluetoothApplet Implementation
// =============================================================================

constructor TShellBluetoothApplet.Create(AParentWindow: TFtWindow; AX, AY, AW, AH: Integer);
begin
  inherited Create();
  FPanelWindow := AParentWindow;
  FIsEnabled := False;
  FIsConnected := False;
  FConnectedDevice := '';
  FMockMode := False;
  FLastCheckTick := 0;
  FQueryBusy := False;
  FOnDismiss := nil;

  FButton := TFtButton.Create(FPanelWindow, AX, AY, AW, AH, '');
  FButton.Flat := True;
  FButton.IsToggle := True;
  FButton.CornerRadius := 6.0;
  FButton.IconPosition := ftipOnly;
  FButton.SetIconSize(18, 18);
  FButton.OnClick := @HandleButtonClick;

  QueryBluetooth(FIsEnabled, FIsConnected, FConnectedDevice);
  UpdateUI();
end;

destructor TShellBluetoothApplet.Destroy();
begin
  DestroyPopupWindow();
  if Assigned(FButton) then
  begin
    FButton.Free();
    FButton := nil;
  end;
  inherited Destroy();
end;

procedure TShellBluetoothApplet.SetBounds(AX, AY, AW, AH: Integer);
begin
  if Assigned(FButton) then
    FButton.SetBounds(AX, AY, AW, AH);
end;

function TShellBluetoothApplet.QueryBluetooth(out AEnabled: Boolean; out AConnected: Boolean; out AConnectedDevice: string): Boolean;
var
  outStr: string;
  lines: TStringList;
  p: Integer;
begin
  AEnabled := False;
  AConnected := False;
  AConnectedDevice := '';
  Result := False;

  if RunCommand('/usr/bin/bluetoothctl', ['show'], outStr) then
  begin
    Result := True;
    if Pos('Powered: yes', outStr) > 0 then
      AEnabled := True;
  end;

  if AEnabled then
  begin
    if RunCommand('/usr/bin/bluetoothctl', ['devices', 'Connected'], outStr) then
    begin
      outStr := Trim(outStr);
      if Length(outStr) > 0 then
      begin
        AConnected := True;
        lines := TStringList.Create();
        try
          lines.Text := outStr;
          if lines.Count > 0 then
          begin
            p := Pos(' ', lines[0]);
            if p > 0 then
            begin
              p := PosEx(' ', lines[0], p + 1);
              if p > 0 then
                AConnectedDevice := Trim(Copy(lines[0], p + 1, Length(lines[0])))
              else
                AConnectedDevice := 'Connected Device';
            end
            else
              AConnectedDevice := 'Connected Device';
          end;
        finally
          lines.Free();
        end;
      end;
    end;
  end;
end;

procedure TShellBluetoothApplet.SetBluetoothState(AEnabled: Boolean; AConnected: Boolean; const AConnectedDevice: string);
begin
  FMockMode := True;
  FIsEnabled := AEnabled;
  FIsConnected := AConnected;
  FConnectedDevice := AConnectedDevice;
  UpdateUI();
  if IsPopupOpen() then
  begin
    UpdatePopupContent();
    if Assigned(FPlate) then
      FPlate.Invalidate();
  end;
end;

procedure TShellBluetoothApplet.ToggleBluetooth();
var
  dummy: string;
begin
  if FIsEnabled then
    RunCommand('/usr/bin/bluetoothctl', ['power', 'off'], dummy)
  else
    RunCommand('/usr/bin/bluetoothctl', ['power', 'on'], dummy);
  FIsEnabled := not FIsEnabled;
  UpdateUI();
  if IsPopupOpen() then
  begin
    UpdatePopupContent();
    if Assigned(FPlate) then
      FPlate.Invalidate();
  end;
end;

procedure TShellBluetoothApplet.ApplyThemeStyle();
var
  isDark: Boolean;
begin
  UpdateUI();
  isDark := IsDarkTheme();

  if Assigned(FStatusLabel) then
  begin
    if isDark then
      FStatusLabel.SetColor(0.85, 0.88, 0.95)
    else
      FStatusLabel.SetColor(0.12, 0.16, 0.23);
  end;

  if Assigned(FDetailsLabel) then
  begin
    if isDark then
      FDetailsLabel.SetColor(0.65, 0.70, 0.80)
    else
      FDetailsLabel.SetColor(0.40, 0.45, 0.55);
  end;

  if Assigned(FPlate) then
    FPlate.Invalidate();
  if Assigned(FToggleBtn) then
    FToggleBtn.Invalidate();
  if Assigned(FSettingsBtn) then
    FSettingsBtn.Invalidate();
  if Assigned(FPopupWindow) then
    FPopupWindow.Invalidate();
end;

procedure TShellBluetoothApplet.UpdateUI();
var
  isDark: Boolean;
begin
  if FButton = nil then Exit;

  isDark := IsDarkTheme();
  FButton.Caption := '';
  FButton.IconPosition := ftipOnly;
  FButton.SetIconSize(18, 18);
  FButton.SetIconSVG(GetBluetoothIconSVG(FIsEnabled, FIsConnected, isDark));
end;

procedure TShellBluetoothApplet.HandlePlatePaint(Sender: TFtDrawingArea; Canvas: TFtCanvas);
var
  isDark: Boolean;
begin
  if not Assigned(Sender) or not Assigned(Canvas) then Exit;

  isDark := IsDarkTheme();
  if isDark then
  begin
    Canvas.DrawRoundedRect(0, 0, Sender.Width, Sender.Height, 6.0, 24 / 255, 25 / 255, 38 / 255, 0.98);
    Canvas.DrawRoundedRectOutline(0, 0, Sender.Width, Sender.Height, 6.0, 1.0, 69 / 255, 71 / 255, 90 / 255, 0.80);
  end
  else
  begin
    Canvas.DrawRoundedRect(0, 0, Sender.Width, Sender.Height, 6.0, 1.0, 1.0, 1.0, 1.0);
    Canvas.DrawRoundedRectOutline(0, 0, Sender.Width, Sender.Height, 6.0, 1.0, 0.80, 0.84, 0.88, 1.0);
  end;
end;

procedure TShellBluetoothApplet.HandlePopupWindowDismiss(Sender: TFtWindow);
begin
  HidePopup();
  if Assigned(FOnDismiss) then
    FOnDismiss(Self);
end;

procedure TShellBluetoothApplet.HandleToggleClick(Sender: TFtButton);
begin
  ToggleBluetooth();
end;

procedure TShellBluetoothApplet.HandleSettingsClick(Sender: TFtButton);
begin
  HidePopup();
  if Assigned(FOnDismiss) then
    FOnDismiss(Self);
  ExecShellCmdAsync('configsama Bluetooth || configsama');
end;

procedure TShellBluetoothApplet.UpdatePopupContent();
var
  statText, detText: string;
begin
  if not Assigned(FPopupWindow) then Exit;
  if not FIsEnabled then
  begin
    statText := 'Bluetooth: Disabled';
    detText := 'Controller is turned off';
  end
  else if FIsConnected then
  begin
    statText := 'Bluetooth: Connected';
    if FConnectedDevice <> '' then
      detText := FConnectedDevice
    else
      detText := 'Peripheral connected';
  end
  else
  begin
    statText := 'Bluetooth: Enabled';
    detText := 'No devices connected';
  end;

  if Assigned(FStatusLabel) then
    FStatusLabel.Text := statText;
  if Assigned(FDetailsLabel) then
    FDetailsLabel.Text := detText;
end;

procedure TShellBluetoothApplet.CreatePopupWindow();
var
  popX, popY, popW, popH: Integer;
begin
  if Assigned(FPopupWindow) then Exit;

  popW := 240;
  popH := 105;

  if Assigned(FButton) and Assigned(FPanelWindow) then
  begin
    popX := FButton.X + (FButton.Width - popW) div 2;
    popX := Max(10, Min(popX, FPanelWindow.Width - popW - 10));
    if FPanelWindow.Y < 100 then
      popY := FPanelWindow.Y + FPanelWindow.Height + 4
    else
      popY := FPanelWindow.Y - popH - 4;
  end
  else
  begin
    popX := 100;
    popY := 100;
  end;

  FPopupWindow := TFtWindow.Create(popW, popH, 'shellsama-bluetooth-popup');
  FPopupWindow.WindowType := ftwtPopupMenu;
  FPopupWindow.Borderless := True;
  FPopupWindow.SkipTaskbar := True;
  FPopupWindow.SetPosition(popX, popY);
  FPopupWindow.OnPopupDismiss := @HandlePopupWindowDismiss;

  FPlate := TFtDrawingArea.Create(FPopupWindow, 0, 0, popW, popH);
  FPlate.OnPaint := @HandlePlatePaint;

  FStatusLabel := TFtLabel.Create(FPopupWindow, 16, 12, popW - 32, 18, '');
  FStatusLabel.Alignment := ftaLeft;

  FDetailsLabel := TFtLabel.Create(FPopupWindow, 16, 34, popW - 32, 16, '');
  FDetailsLabel.Alignment := ftaLeft;

  FToggleBtn := TFtButton.Create(FPopupWindow, 16, 62, 95, 26, 'Toggle BT');
  FToggleBtn.Flat := True;
  FToggleBtn.CornerRadius := 4.0;
  FToggleBtn.OnClick := @HandleToggleClick;

  FSettingsBtn := TFtButton.Create(FPopupWindow, 116, 62, popW - 132, 26, 'BT Settings...');
  FSettingsBtn.Flat := True;
  FSettingsBtn.CornerRadius := 4.0;
  FSettingsBtn.OnClick := @HandleSettingsClick;

  UpdatePopupContent();
  ApplyThemeStyle();
end;

procedure TShellBluetoothApplet.DestroyPopupWindow();
begin
  if Assigned(FPopupWindow) then
  begin
    FPlate := nil;
    FStatusLabel := nil;
    FDetailsLabel := nil;
    FToggleBtn := nil;
    FSettingsBtn := nil;
    FPopupWindow.Free();
    FPopupWindow := nil;
  end;
end;

procedure TShellBluetoothApplet.ShowPopup();
begin
  if not Assigned(FPopupWindow) then
    CreatePopupWindow();
  UpdatePopupContent();
  ApplyThemeStyle();
  if Assigned(FPopupWindow) then
  begin
    FPopupWindow.Show();
    FPopupWindow.GrabPopupInput();
    if Assigned(FPlate) then
      FPlate.Invalidate();
    if Assigned(FButton) then
      FButton.Toggled := True;
  end;
end;

procedure TShellBluetoothApplet.HidePopup();
begin
  if Assigned(FPopupWindow) then
  begin
    FPopupWindow.UngrabInput();
    FPopupWindow.Hide();
    if Assigned(FButton) then
      FButton.Toggled := False;
  end;
end;

procedure TShellBluetoothApplet.TogglePopup();
begin
  if IsPopupOpen() then
    HidePopup()
  else
    ShowPopup();
end;

function TShellBluetoothApplet.IsPopupOpen(): Boolean;
begin
  Result := Assigned(FPopupWindow) and FPopupWindow.Visible;
end;

procedure TShellBluetoothApplet.HandleButtonClick(Sender: TFtButton);
begin
  TogglePopup();
end;

procedure TShellBluetoothApplet.Tick();
var
  nowTick: Int64;
  curEn, curConn: Boolean;
  curDev: string;
begin
  if FMockMode then Exit;
  nowTick := GetTickCount64();
  if (nowTick - FLastCheckTick < 3000) or FQueryBusy then Exit;
  FLastCheckTick := nowTick;
  FQueryBusy := True;
  try
    if QueryBluetooth(curEn, curConn, curDev) then
    begin
      if (curEn <> FIsEnabled) or (curConn <> FIsConnected) or (curDev <> FConnectedDevice) then
      begin
        FIsEnabled := curEn;
        FIsConnected := curConn;
        FConnectedDevice := curDev;
        UpdateUI();
        if IsPopupOpen() then
        begin
          UpdatePopupContent();
          if Assigned(FPlate) then
            FPlate.Invalidate();
        end;
      end;
    end;
  finally
    FQueryBusy := False;
  end;
end;

// =============================================================================
// TShellKeyboardApplet Implementation
// =============================================================================

constructor TShellKeyboardApplet.Create(AParentWindow: TFtWindow; AX, AY, AW, AH: Integer);
begin
  inherited Create();
  FPanelWindow := AParentWindow;
  FCurrentLayout := 'US';
  FCurrentEngine := 'xkb:us::eng';
  FEngineDisplayName := 'English (US)';
  FIsIbusActive := False;
  FHasMozc := False;
  FMockMode := False;
  FLastCheckTick := 0;
  FQueryBusy := False;

  if Assigned(FPanelWindow) then
  begin
    FButton := TFtButton.Create(FPanelWindow, AX, AY, AW, AH, '');
    FButton.IsToggle := True;
    FButton.Flat := True;
    FButton.CornerRadius := 6.0;
    FButton.IconPosition := ftipOnly;
    FButton.SetIconSize(18, 18);
    FButton.OnClick := @HandleButtonClick;
  end;

  QueryKeyboard(FCurrentLayout, FCurrentEngine, FEngineDisplayName, FIsIbusActive, FHasMozc);
  UpdateUI();
  ApplyThemeStyle();
end;

destructor TShellKeyboardApplet.Destroy();
begin
  DestroyPopupWindow();
  if Assigned(FButton) then
  begin
    FButton.Free();
    FButton := nil;
  end;
  inherited Destroy();
end;

function libc_setenv(name: PChar; value: PChar; overwrite: LongInt): LongInt; cdecl; external 'c' name 'setenv';

function TShellKeyboardApplet.QueryKeyboard(out ALayout, AEngine, AEngineName: string; out AIsIbus, AHasMozc: Boolean): Boolean;
var
  ibusOut, xkbOut: string;
  lines: TStringList;
  i, p: Integer;
  lineStr, busDir, addrVal: string;
  sr: TSearchRec;
begin
  ALayout := 'US';
  AEngine := 'xkb:us::eng';
  AEngineName := 'English (US)';
  AIsIbus := False;
  AHasMozc := False;
  Result := False;

  // Ensure IBUS_ADDRESS is discovered from ~/.config/ibus/bus/ if unset
  if GetEnvironmentVariable('IBUS_ADDRESS') = '' then
  begin
    busDir := GetEnvironmentVariable('HOME') + '/.config/ibus/bus/';
    if DirectoryExists(busDir) then
    begin
      if FindFirst(busDir + '*-unix-*', faAnyFile, sr) = 0 then
      begin
        try
          repeat
            if (sr.Name <> '.') and (sr.Name <> '..') then
            begin
              lines := TStringList.Create();
              try
                lines.LoadFromFile(busDir + sr.Name);
                for i := 0 to lines.Count - 1 do
                begin
                  lineStr := Trim(lines[i]);
                  if Pos('IBUS_ADDRESS=', lineStr) = 1 then
                  begin
                    addrVal := Copy(lineStr, 14, Length(lineStr));
                    libc_setenv('IBUS_ADDRESS', PChar(addrVal), 1);
                    Break;
                  end;
                end;
              finally
                lines.Free();
              end;
              if GetEnvironmentVariable('IBUS_ADDRESS') <> '' then Break;
            end;
          until FindNext(sr) <> 0;
        finally
          FindClose(sr);
        end;
      end;
    end;
  end;

  // 1. Probe ibus if available
  if RunCommand('/usr/bin/ibus', ['engine'], ibusOut) then
  begin
    ibusOut := Trim(ibusOut);
    if ibusOut <> '' then
    begin
      AIsIbus := True;
      AEngine := ibusOut;
      Result := True;

      if Pos('mozc', LowerCase(ibusOut)) > 0 then
      begin
        ALayout := 'JA';
        AEngineName := 'Mozc (Japanese)';
        AHasMozc := True;
      end
      else if Pos('xkb:', LowerCase(ibusOut)) = 1 then
      begin
        lines := TStringList.Create();
        try
          lines.Delimiter := ':';
          lines.StrictDelimiter := True;
          lines.DelimitedText := ibusOut;
          if lines.Count > 1 then
            ALayout := UpperCase(lines[1])
          else
            ALayout := 'EN';
        finally
          lines.Free();
        end;
        if ALayout = 'US' then
          AEngineName := 'English (US)'
        else if ALayout = 'JP' then
          AEngineName := 'Japanese (xkb)'
        else
          AEngineName := 'Keyboard (' + ALayout + ')';
      end
      else
      begin
        ALayout := UpperCase(Copy(ibusOut, 1, 2));
        AEngineName := ibusOut;
      end;
    end;
  end;

  // Check if Mozc is installed
  if not AHasMozc then
  begin
    if FileExists('/usr/lib/ibus-mozc/ibus-engine-mozc') or
       FileExists('/usr/share/ibus/component/mozc.xml') or
       DirectoryExists('/usr/share/ibus-mozc') then
      AHasMozc := True;
  end;

  // 2. Fallback to setxkbmap if ibus is not active
  if not AIsIbus then
  begin
    if RunCommand('/usr/bin/setxkbmap', ['-query'], xkbOut) then
    begin
      lines := TStringList.Create();
      try
        lines.Text := xkbOut;
        for i := 0 to lines.Count - 1 do
        begin
          lineStr := Trim(lines[i]);
          p := Pos('layout:', lineStr);
          if p = 1 then
          begin
            ALayout := UpperCase(Trim(Copy(lineStr, 8, Length(lineStr))));
            AEngine := 'xkb:' + LowerCase(ALayout);
            if ALayout = 'US' then
              AEngineName := 'English (US)'
            else
              AEngineName := 'Standard (' + ALayout + ')';
            Result := True;
            Break;
          end;
        end;
      finally
        lines.Free();
      end;
    end;
  end;
end;

procedure TShellKeyboardApplet.SetKeyboardState(const ALayout, AEngine, AEngineName: string; AIsIbus: Boolean; AHasMozc: Boolean);
begin
  FCurrentLayout := ALayout;
  FCurrentEngine := AEngine;
  FEngineDisplayName := AEngineName;
  FIsIbusActive := AIsIbus;
  FHasMozc := AHasMozc;
  UpdateUI();
  if IsPopupOpen() then
  begin
    UpdatePopupContent();
    if Assigned(FPlate) then
      FPlate.Invalidate();
  end;
end;

procedure TShellKeyboardApplet.SwitchEngine(const AEngine: string);
var
  dummy: string;
begin
  if FMockMode then
  begin
    FCurrentEngine := AEngine;
    if Pos('mozc', LowerCase(AEngine)) > 0 then
    begin
      FCurrentLayout := 'JA';
      FEngineDisplayName := 'Mozc (Japanese)';
    end
    else
    begin
      FCurrentLayout := 'US';
      FEngineDisplayName := 'English (US)';
    end;
    UpdateUI();
    if IsPopupOpen() then
    begin
      UpdatePopupContent();
      if Assigned(FPlate) then
        FPlate.Invalidate();
    end;
    Exit;
  end;

  if FIsIbusActive and (AEngine <> '') then
  begin
    RunCommand('/usr/bin/ibus', ['engine', AEngine], dummy);
    Tick();
  end;
end;

procedure TShellKeyboardApplet.ToggleInputMethod();
begin
  if Pos('mozc', LowerCase(FCurrentEngine)) > 0 then
    SwitchEngine('xkb:us::eng')
  else
    SwitchEngine('mozc-jp');
end;

procedure TShellKeyboardApplet.UpdateUI();
begin
  if Assigned(FButton) then
  begin
    FButton.Caption := '';
    FButton.IconPosition := ftipOnly;
    FButton.SetIconSize(18, 18);
    FButton.SetIconSVG(GetKeyboardIconSVG(FCurrentLayout, IsDarkTheme()));
    FButton.Hint := 'Keyboard: ' + FEngineDisplayName;
  end;
end;

procedure TShellKeyboardApplet.ApplyThemeStyle();
var
  isDark: Boolean;
begin
  isDark := IsDarkTheme();
  UpdateUI();

  if Assigned(FTitleLabel) then
  begin
    if isDark then
      FTitleLabel.SetColor(0.65, 0.70, 0.80)
    else
      FTitleLabel.SetColor(0.40, 0.45, 0.55);
  end;

  if Assigned(FStatusLabel) then
  begin
    if isDark then
      FStatusLabel.SetColor(0.85, 0.88, 0.95)
    else
      FStatusLabel.SetColor(0.12, 0.16, 0.23);
  end;

  if Assigned(FDetailsLabel) then
  begin
    if isDark then
      FDetailsLabel.SetColor(0.65, 0.70, 0.80)
    else
      FDetailsLabel.SetColor(0.40, 0.45, 0.55);
  end;

  if Assigned(FPlate) then
    FPlate.Invalidate();
  if Assigned(FSwitchBtn) then
    FSwitchBtn.Invalidate();
  if Assigned(FPreferencesBtn) then
    FPreferencesBtn.Invalidate();
  if Assigned(FSettingsBtn) then
    FSettingsBtn.Invalidate();
  if Assigned(FPopupWindow) then
    FPopupWindow.Invalidate();
end;

procedure TShellKeyboardApplet.HandlePlatePaint(Sender: TFtDrawingArea; Canvas: TFtCanvas);
var
  isDark: Boolean;
begin
  if not Assigned(Sender) or not Assigned(Canvas) then Exit;
  isDark := IsDarkTheme();
  if isDark then
  begin
    Canvas.DrawRoundedRect(0, 0, Sender.Width, Sender.Height, 6.0, 24 / 255, 25 / 255, 38 / 255, 0.98);
    Canvas.DrawRoundedRectOutline(0, 0, Sender.Width, Sender.Height, 6.0, 1.0, 69 / 255, 71 / 255, 90 / 255, 0.80);
  end
  else
  begin
    Canvas.DrawRoundedRect(0, 0, Sender.Width, Sender.Height, 6.0, 1.0, 1.0, 1.0, 1.0);
    Canvas.DrawRoundedRectOutline(0, 0, Sender.Width, Sender.Height, 6.0, 1.0, 0.80, 0.84, 0.88, 1.0);
  end;
end;

procedure TShellKeyboardApplet.HandlePopupWindowDismiss(Sender: TFtWindow);
begin
  HidePopup();
  if Assigned(FOnDismiss) then
    FOnDismiss(Self);
end;

procedure TShellKeyboardApplet.CreatePopupWindow();
var
  popX, popY, popW, popH: Integer;
begin
  if Assigned(FPopupWindow) then Exit;

  popW := 250;
  popH := 160;

  if Assigned(FButton) and Assigned(FPanelWindow) then
  begin
    popX := FButton.X + (FButton.Width - popW) div 2;
    popX := Max(10, Min(popX, FPanelWindow.Width - popW - 10));
    if FPanelWindow.Y < 100 then
      popY := FPanelWindow.Y + FPanelWindow.Height + 4
    else
      popY := FPanelWindow.Y - popH - 4;
  end
  else
  begin
    popX := 100;
    popY := 100;
  end;

  FPopupWindow := TFtWindow.Create(popW, popH, 'shellsama-keyboard-popup');
  FPopupWindow.WindowType := ftwtPopupMenu;
  FPopupWindow.Borderless := True;
  FPopupWindow.SkipTaskbar := True;
  FPopupWindow.SetPosition(popX, popY);
  FPopupWindow.OnPopupDismiss := @HandlePopupWindowDismiss;

  FPlate := TFtDrawingArea.Create(FPopupWindow, 0, 0, popW, popH);
  FPlate.OnPaint := @HandlePlatePaint;

  FTitleLabel := TFtLabel.Create(FPopupWindow, 16, 10, popW - 32, 18, 'Keyboard & Input Method');
  FTitleLabel.Alignment := ftaLeft;

  FStatusLabel := TFtLabel.Create(FPopupWindow, 16, 32, popW - 32, 16, '');
  FStatusLabel.Alignment := ftaLeft;

  FDetailsLabel := TFtLabel.Create(FPopupWindow, 16, 50, popW - 32, 16, '');
  FDetailsLabel.Alignment := ftaLeft;

  FSwitchBtn := TFtButton.Create(FPopupWindow, 16, 72, popW - 32, 24, 'Switch Input Method');
  FSwitchBtn.Flat := True;
  FSwitchBtn.CornerRadius := 4.0;
  FSwitchBtn.OnClick := @HandleSwitchClick;

  FPreferencesBtn := TFtButton.Create(FPopupWindow, 16, 100, popW - 32, 24, 'Input Method Preferences...');
  FPreferencesBtn.Flat := True;
  FPreferencesBtn.CornerRadius := 4.0;
  FPreferencesBtn.OnClick := @HandlePreferencesClick;

  FSettingsBtn := TFtButton.Create(FPopupWindow, 16, 128, popW - 32, 24, 'Keyboard Settings...');
  FSettingsBtn.Flat := True;
  FSettingsBtn.CornerRadius := 4.0;
  FSettingsBtn.OnClick := @HandleSettingsClick;

  UpdatePopupContent();
  ApplyThemeStyle();
end;

procedure TShellKeyboardApplet.DestroyPopupWindow();
begin
  if Assigned(FPopupWindow) then
  begin
    FPlate := nil;
    FTitleLabel := nil;
    FStatusLabel := nil;
    FDetailsLabel := nil;
    FSwitchBtn := nil;
    FPreferencesBtn := nil;
    FSettingsBtn := nil;
    FPopupWindow.Free();
    FPopupWindow := nil;
  end;
end;

procedure TShellKeyboardApplet.UpdatePopupContent();
begin
  if Assigned(FStatusLabel) then
    FStatusLabel.Text := FEngineDisplayName;

  if Assigned(FDetailsLabel) then
  begin
    if FCurrentEngine <> '' then
      FDetailsLabel.Text := 'Active Engine: ' + FCurrentEngine
    else
      FDetailsLabel.Text := 'Layout: ' + FCurrentLayout;
  end;

  if Assigned(FSwitchBtn) then
  begin
    if Pos('mozc', LowerCase(FCurrentEngine)) > 0 then
      FSwitchBtn.Caption := 'Switch to English (US)'
    else if FHasMozc or FIsIbusActive then
      FSwitchBtn.Caption := 'Switch to Mozc (Japanese)'
    else
      FSwitchBtn.Caption := 'Switch Input Engine';
  end;
end;

procedure TShellKeyboardApplet.ShowPopup();
begin
  if not Assigned(FPopupWindow) then
    CreatePopupWindow();
  UpdatePopupContent();
  ApplyThemeStyle();
  if Assigned(FPopupWindow) then
  begin
    FPopupWindow.Show();
    FPopupWindow.GrabPopupInput();
    if Assigned(FPlate) then
      FPlate.Invalidate();
    if Assigned(FButton) then
      FButton.Toggled := True;
  end;
end;

procedure TShellKeyboardApplet.HidePopup();
begin
  if Assigned(FPopupWindow) then
  begin
    FPopupWindow.UngrabInput();
    FPopupWindow.Hide();
    if Assigned(FButton) then
      FButton.Toggled := False;
  end;
end;

procedure TShellKeyboardApplet.TogglePopup();
begin
  if IsPopupOpen() then
    HidePopup()
  else
    ShowPopup();
end;

function TShellKeyboardApplet.IsPopupOpen(): Boolean;
begin
  Result := Assigned(FPopupWindow) and FPopupWindow.Visible;
end;

procedure TShellKeyboardApplet.HandleButtonClick(Sender: TFtButton);
begin
  TogglePopup();
end;

procedure TShellKeyboardApplet.HandleSwitchClick(Sender: TFtButton);
begin
  ToggleInputMethod();
end;

procedure TShellKeyboardApplet.HandlePreferencesClick(Sender: TFtButton);
begin
  HidePopup();
  ExecShellCmdAsync('ibus-setup || configsama Keyboard');
end;

procedure TShellKeyboardApplet.HandleSettingsClick(Sender: TFtButton);
begin
  HidePopup();
  ExecShellCmdAsync('configsama Keyboard || configsama');
end;

procedure TShellKeyboardApplet.SetBounds(AX, AY, AW, AH: Integer);
begin
  if Assigned(FButton) then
    FButton.SetBounds(AX, AY, AW, AH);
end;

procedure TShellKeyboardApplet.Tick();
var
  nowTick: Int64;
  curLay, curEng, curName: string;
  curIbus, curMozc: Boolean;
begin
  if FMockMode then Exit;
  nowTick := GetTickCount64();
  if (nowTick - FLastCheckTick < 3000) or FQueryBusy then Exit;
  FLastCheckTick := nowTick;
  FQueryBusy := True;
  try
    if QueryKeyboard(curLay, curEng, curName, curIbus, curMozc) then
    begin
      if (curLay <> FCurrentLayout) or (curEng <> FCurrentEngine) or (curName <> FEngineDisplayName) or
         (curIbus <> FIsIbusActive) or (curMozc <> FHasMozc) then
      begin
        FCurrentLayout := curLay;
        FCurrentEngine := curEng;
        FEngineDisplayName := curName;
        FIsIbusActive := curIbus;
        FHasMozc := curMozc;
        UpdateUI();
        if IsPopupOpen() then
        begin
          UpdatePopupContent();
          if Assigned(FPlate) then
            FPlate.Invalidate();
        end;
      end;
    end;
  finally
    FQueryBusy := False;
  end;
end;

// =============================================================================
// TShellDisplayApplet Implementation
// =============================================================================

constructor TShellDisplayApplet.Create(AParentWindow: TFtWindow; AX, AY, AW, AH: Integer);
begin
  inherited Create();
  FPanelWindow := AParentWindow;
  FConnectedCount := 1;
  FPrimaryName := 'eDP-1';
  FPrimaryResolution := '1920x1080';
  FSecondaryName := '';
  FSecondaryResolution := '';
  FMockMode := False;
  FLastCheckTick := 0;
  FQueryBusy := False;

  if Assigned(FPanelWindow) then
  begin
    FButton := TFtButton.Create(FPanelWindow, AX, AY, AW, AH, '');
    FButton.IsToggle := True;
    FButton.Flat := True;
    FButton.CornerRadius := 6.0;
    FButton.IconPosition := ftipOnly;
    FButton.SetIconSize(18, 18);
    FButton.OnClick := @HandleButtonClick;
  end;

  QueryDisplays(FConnectedCount, FPrimaryName, FPrimaryResolution, FSecondaryName, FSecondaryResolution);
  UpdateUI();
  ApplyThemeStyle();
end;

destructor TShellDisplayApplet.Destroy();
begin
  DestroyPopupWindow();
  if Assigned(FButton) then
  begin
    FButton.Free();
    FButton := nil;
  end;
  inherited Destroy();
end;

function TShellDisplayApplet.QueryDisplays(out ACount: Integer; out APriName, APriRes, ASecName, ASecRes: string): Boolean;
var
  xrandrOut: string;
  lines, tokens: TStringList;
  i: Integer;
  lineStr, tok, resTok: string;
  monIdx: Integer;
  sr: TSearchRec;
  drmPath, statStr: string;
  pSlash1, pX, pSlash2, pDash: Integer;
begin
  ACount := 0;
  APriName := '';
  APriRes := '';
  ASecName := '';
  ASecRes := '';
  Result := False;

  if RunCommand('/usr/bin/xrandr', ['--listmonitors'], xrandrOut) then
  begin
    lines := TStringList.Create();
    tokens := TStringList.Create();
    try
      lines.Text := xrandrOut;
      monIdx := 0;
      for i := 0 to lines.Count - 1 do
      begin
        lineStr := Trim(lines[i]);
        if Pos('Monitors:', lineStr) = 1 then
          Continue;

        if (Length(lineStr) > 0) and (lineStr[1] in ['0'..'9']) then
        begin
          Inc(monIdx);
          tokens.Clear();
          tokens.Delimiter := ' ';
          tokens.StrictDelimiter := False;
          tokens.DelimitedText := lineStr;

          if tokens.Count > 0 then
            tok := tokens[tokens.Count - 1]
          else
            tok := 'Display' + IntToStr(monIdx);

          resTok := '';
          if tokens.Count >= 3 then
          begin
            resTok := tokens[2];
            pSlash1 := Pos('/', resTok);
            pX := Pos('x', resTok);
            if (pSlash1 > 0) and (pX > pSlash1) then
            begin
              pSlash2 := PosEx('/', resTok, pX);
              if pSlash2 > pX then
                resTok := Copy(resTok, 1, pSlash1 - 1) + 'x' + Copy(resTok, pX + 1, pSlash2 - pX - 1);
            end;
          end;

          if (monIdx = 1) or (Pos('*', lineStr) > 0) then
          begin
            APriName := tok;
            if resTok <> '' then
              APriRes := resTok
            else
              APriRes := 'Active';
          end
          else
          begin
            ASecName := tok;
            if resTok <> '' then
              ASecRes := resTok
            else
              ASecRes := 'Active';
          end;
        end;
      end;
      if monIdx > 0 then
      begin
        ACount := monIdx;
        Result := True;
        Exit;
      end;
    finally
      tokens.Free();
      lines.Free();
    end;
  end;

  // Fallback to /sys/class/drm/card*-*
  if FindFirst('/sys/class/drm/card*-*', faDirectory, sr) = 0 then
  begin
    repeat
      if (sr.Name <> '.') and (sr.Name <> '..') then
      begin
        drmPath := '/sys/class/drm/' + sr.Name;
        statStr := ReadSysfsFirstLine(drmPath + '/status');
        if SameText(statStr, 'connected') then
        begin
          Inc(ACount);
          pDash := Pos('-', sr.Name);
          if pDash > 0 then
            tok := Copy(sr.Name, pDash + 1, Length(sr.Name))
          else
            tok := sr.Name;

          if ACount = 1 then
          begin
            APriName := tok;
            APriRes := 'Active';
          end
          else
          begin
            ASecName := tok;
            ASecRes := 'Active';
          end;
        end;
      end;
    until FindNext(sr) <> 0;
    FindClose(sr);
    if ACount > 0 then
      Result := True;
  end;
end;

procedure TShellDisplayApplet.SetDisplayState(ACount: Integer; const APriName, APriRes: string; const ASecName: string; const ASecRes: string);
begin
  FConnectedCount := ACount;
  FPrimaryName := APriName;
  FPrimaryResolution := APriRes;
  FSecondaryName := ASecName;
  FSecondaryResolution := ASecRes;
  UpdateUI();
  if IsPopupOpen() then
  begin
    UpdatePopupContent();
    if Assigned(FPlate) then
      FPlate.Invalidate();
  end;
end;

procedure TShellDisplayApplet.ExtendDisplays();
begin
  if (FSecondaryName <> '') and (FPrimaryName <> '') then
    ExecShellCmdAsync('xrandr --output ' + FSecondaryName + ' --auto --right-of ' + FPrimaryName);
end;

procedure TShellDisplayApplet.MirrorDisplays();
begin
  if (FSecondaryName <> '') and (FPrimaryName <> '') then
    ExecShellCmdAsync('xrandr --output ' + FSecondaryName + ' --auto --same-as ' + FPrimaryName);
end;

procedure TShellDisplayApplet.UpdateUI();
begin
  if Assigned(FButton) then
  begin
    FButton.Caption := '';
    FButton.IconPosition := ftipOnly;
    FButton.SetIconSize(18, 18);
    FButton.SetIconSVG(GetDisplayIconSVG(FConnectedCount, IsDarkTheme()));
    if FConnectedCount > 1 then
      FButton.Hint := 'Displays: ' + IntToStr(FConnectedCount) + ' connected (' + FPrimaryName + ', ' + FSecondaryName + ')'
    else
      FButton.Hint := 'Display: ' + FPrimaryName + ' (' + FPrimaryResolution + ')';
  end;
end;

procedure TShellDisplayApplet.ApplyThemeStyle();
var
  isDark: Boolean;
begin
  isDark := IsDarkTheme();
  UpdateUI();

  if Assigned(FTitleLabel) then
  begin
    if isDark then
      FTitleLabel.SetColor(0.65, 0.70, 0.80)
    else
      FTitleLabel.SetColor(0.40, 0.45, 0.55);
  end;

  if Assigned(FSummaryLabel) then
  begin
    if isDark then
      FSummaryLabel.SetColor(0.85, 0.88, 0.95)
    else
      FSummaryLabel.SetColor(0.12, 0.16, 0.23);
  end;

  if Assigned(FPrimaryLabel) then
  begin
    if isDark then
      FPrimaryLabel.SetColor(0.65, 0.70, 0.80)
    else
      FPrimaryLabel.SetColor(0.40, 0.45, 0.55);
  end;

  if Assigned(FSecondaryLabel) then
  begin
    if isDark then
      FSecondaryLabel.SetColor(0.65, 0.70, 0.80)
    else
      FSecondaryLabel.SetColor(0.40, 0.45, 0.55);
  end;

  if Assigned(FPlate) then
    FPlate.Invalidate();
  if Assigned(FExtendBtn) then
    FExtendBtn.Invalidate();
  if Assigned(FMirrorBtn) then
    FMirrorBtn.Invalidate();
  if Assigned(FSettingsBtn) then
    FSettingsBtn.Invalidate();
  if Assigned(FPopupWindow) then
    FPopupWindow.Invalidate();
end;

procedure TShellDisplayApplet.HandlePlatePaint(Sender: TFtDrawingArea; Canvas: TFtCanvas);
var
  isDark: Boolean;
begin
  if not Assigned(Sender) or not Assigned(Canvas) then Exit;
  isDark := IsDarkTheme();
  if isDark then
  begin
    Canvas.DrawRoundedRect(0, 0, Sender.Width, Sender.Height, 6.0, 24 / 255, 25 / 255, 38 / 255, 0.98);
    Canvas.DrawRoundedRectOutline(0, 0, Sender.Width, Sender.Height, 6.0, 1.0, 69 / 255, 71 / 255, 90 / 255, 0.80);
  end
  else
  begin
    Canvas.DrawRoundedRect(0, 0, Sender.Width, Sender.Height, 6.0, 1.0, 1.0, 1.0, 1.0);
    Canvas.DrawRoundedRectOutline(0, 0, Sender.Width, Sender.Height, 6.0, 1.0, 0.80, 0.84, 0.88, 1.0);
  end;
end;

procedure TShellDisplayApplet.HandlePopupWindowDismiss(Sender: TFtWindow);
begin
  HidePopup();
  if Assigned(FOnDismiss) then
    FOnDismiss(Self);
end;

procedure TShellDisplayApplet.CreatePopupWindow();
var
  popX, popY, popW, popH: Integer;
begin
  if Assigned(FPopupWindow) then Exit;

  popW := 250;
  if FConnectedCount > 1 then
    popH := 160
  else
    popH := 115;

  if Assigned(FButton) and Assigned(FPanelWindow) then
  begin
    popX := FButton.X + (FButton.Width - popW) div 2;
    popX := Max(10, Min(popX, FPanelWindow.Width - popW - 10));
    if FPanelWindow.Y < 100 then
      popY := FPanelWindow.Y + FPanelWindow.Height + 4
    else
      popY := FPanelWindow.Y - popH - 4;
  end
  else
  begin
    popX := 100;
    popY := 100;
  end;

  FPopupWindow := TFtWindow.Create(popW, popH, 'shellsama-display-popup');
  FPopupWindow.WindowType := ftwtPopupMenu;
  FPopupWindow.Borderless := True;
  FPopupWindow.SkipTaskbar := True;
  FPopupWindow.SetPosition(popX, popY);
  FPopupWindow.OnPopupDismiss := @HandlePopupWindowDismiss;

  FPlate := TFtDrawingArea.Create(FPopupWindow, 0, 0, popW, popH);
  FPlate.OnPaint := @HandlePlatePaint;

  FTitleLabel := TFtLabel.Create(FPopupWindow, 16, 10, popW - 32, 18, 'Displays & Monitors');
  FTitleLabel.Alignment := ftaLeft;

  FSummaryLabel := TFtLabel.Create(FPopupWindow, 16, 32, popW - 32, 16, '');
  FSummaryLabel.Alignment := ftaLeft;

  FPrimaryLabel := TFtLabel.Create(FPopupWindow, 16, 50, popW - 32, 16, '');
  FPrimaryLabel.Alignment := ftaLeft;

  FSecondaryLabel := TFtLabel.Create(FPopupWindow, 16, 68, popW - 32, 16, '');
  FSecondaryLabel.Alignment := ftaLeft;

  FExtendBtn := TFtButton.Create(FPopupWindow, 16, 92, (popW - 38) div 2, 24, 'Extend');
  FExtendBtn.Flat := True;
  FExtendBtn.CornerRadius := 4.0;
  FExtendBtn.OnClick := @HandleExtendClick;

  FMirrorBtn := TFtButton.Create(FPopupWindow, 16 + (popW - 38) div 2 + 6, 92, (popW - 38) div 2, 24, 'Mirror');
  FMirrorBtn.Flat := True;
  FMirrorBtn.CornerRadius := 4.0;
  FMirrorBtn.OnClick := @HandleMirrorClick;

  FSettingsBtn := TFtButton.Create(FPopupWindow, 16, 124, popW - 32, 24, 'Display Settings...');
  FSettingsBtn.Flat := True;
  FSettingsBtn.CornerRadius := 4.0;
  FSettingsBtn.OnClick := @HandleSettingsClick;

  UpdatePopupContent();
  ApplyThemeStyle();
end;

procedure TShellDisplayApplet.DestroyPopupWindow();
begin
  if Assigned(FPopupWindow) then
  begin
    FPlate := nil;
    FTitleLabel := nil;
    FSummaryLabel := nil;
    FPrimaryLabel := nil;
    FSecondaryLabel := nil;
    FExtendBtn := nil;
    FMirrorBtn := nil;
    FSettingsBtn := nil;
    FPopupWindow.Free();
    FPopupWindow := nil;
  end;
end;

procedure TShellDisplayApplet.UpdatePopupContent();
var
  hasMulti: Boolean;
begin
  hasMulti := (FConnectedCount > 1);

  if Assigned(FSummaryLabel) then
  begin
    if FConnectedCount = 1 then
      FSummaryLabel.Text := '1 Display connected'
    else if FConnectedCount > 1 then
      FSummaryLabel.Text := IntToStr(FConnectedCount) + ' Displays connected'
    else
      FSummaryLabel.Text := 'No displays detected';
  end;

  if Assigned(FPrimaryLabel) then
  begin
    if FPrimaryName <> '' then
      FPrimaryLabel.Text := 'Primary: ' + FPrimaryName + ' (' + FPrimaryResolution + ')'
    else
      FPrimaryLabel.Text := 'Primary: None';
  end;

  if Assigned(FSecondaryLabel) then
  begin
    if hasMulti and (FSecondaryName <> '') then
    begin
      FSecondaryLabel.Visible := True;
      FSecondaryLabel.Text := 'External: ' + FSecondaryName + ' (' + FSecondaryResolution + ')';
    end
    else
      FSecondaryLabel.Visible := False;
  end;

  if Assigned(FExtendBtn) then
    FExtendBtn.Visible := hasMulti;
  if Assigned(FMirrorBtn) then
    FMirrorBtn.Visible := hasMulti;

  if Assigned(FSettingsBtn) then
  begin
    if hasMulti then
      FSettingsBtn.SetBounds(16, 124, 250 - 32, 24)
    else
      FSettingsBtn.SetBounds(16, 76, 250 - 32, 24);
  end;
end;

procedure TShellDisplayApplet.ShowPopup();
begin
  if not Assigned(FPopupWindow) then
    CreatePopupWindow();
  UpdatePopupContent();
  ApplyThemeStyle();
  if Assigned(FPopupWindow) then
  begin
    FPopupWindow.Show();
    FPopupWindow.GrabPopupInput();
    if Assigned(FPlate) then
      FPlate.Invalidate();
    if Assigned(FButton) then
      FButton.Toggled := True;
  end;
end;

procedure TShellDisplayApplet.HidePopup();
begin
  if Assigned(FPopupWindow) then
  begin
    FPopupWindow.UngrabInput();
    FPopupWindow.Hide();
    if Assigned(FButton) then
      FButton.Toggled := False;
  end;
end;

procedure TShellDisplayApplet.TogglePopup();
begin
  if IsPopupOpen() then
    HidePopup()
  else
    ShowPopup();
end;

function TShellDisplayApplet.IsPopupOpen(): Boolean;
begin
  Result := Assigned(FPopupWindow) and FPopupWindow.Visible;
end;

procedure TShellDisplayApplet.HandleButtonClick(Sender: TFtButton);
begin
  TogglePopup();
end;

procedure TShellDisplayApplet.HandleExtendClick(Sender: TFtButton);
begin
  ExtendDisplays();
end;

procedure TShellDisplayApplet.HandleMirrorClick(Sender: TFtButton);
begin
  MirrorDisplays();
end;

procedure TShellDisplayApplet.HandleSettingsClick(Sender: TFtButton);
begin
  HidePopup();
  ExecShellCmdAsync('configsama Displays || configsama');
end;

procedure TShellDisplayApplet.SetBounds(AX, AY, AW, AH: Integer);
begin
  if Assigned(FButton) then
    FButton.SetBounds(AX, AY, AW, AH);
end;

procedure TShellDisplayApplet.Tick();
var
  nowTick: Int64;
  curCnt: Integer;
  curPri, curPriRes, curSec, curSecRes: string;
begin
  if FMockMode then Exit;
  nowTick := GetTickCount64();
  if (nowTick - FLastCheckTick < 3000) or FQueryBusy then Exit;
  FLastCheckTick := nowTick;
  FQueryBusy := True;
  try
    if QueryDisplays(curCnt, curPri, curPriRes, curSec, curSecRes) then
    begin
      if (curCnt <> FConnectedCount) or (curPri <> FPrimaryName) or (curPriRes <> FPrimaryResolution) or
         (curSec <> FSecondaryName) or (curSecRes <> FSecondaryResolution) then
      begin
        FConnectedCount := curCnt;
        FPrimaryName := curPri;
        FPrimaryResolution := curPriRes;
        FSecondaryName := curSec;
        FSecondaryResolution := curSecRes;
        UpdateUI();
        if IsPopupOpen() then
        begin
          UpdatePopupContent();
          if Assigned(FPlate) then
            FPlate.Invalidate();
        end;
      end;
    end;
  finally
    FQueryBusy := False;
  end;
end;

end.
