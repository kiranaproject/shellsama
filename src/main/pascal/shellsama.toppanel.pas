// Unit ShellSama.TopPanel — Desktop Top Panel (Status Bar & Menu) for Samarinda DE

unit ShellSama.TopPanel;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils, Math,
  Floria.XCB,
  ftpas.api, ftpas.types, ftpas,
  ShellSama.DesktopApps,
  ShellSama.Launcher,
  ShellSama.Tray,
  ShellSama.Applets;

type
  PCardinalArray = ^TCardinalArray;
  TCardinalArray = array[0..4] of Cardinal;

  TShellTopPanel = class
  private
    FWindow         : TFtWindow;
    FLauncherBtn    : TFtButton;
    FClockText      : TFtLabel;
    FShowDesktopBtn : TFtButton;
    FSessionApplet  : TShellSessionApplet;
    FVolumeApplet   : TShellVolumeApplet;
    FTray           : TShellSystemTray;
    FLauncher       : TShellLauncher;
    FIsVisible      : Boolean;
    FShowingDesktop : Boolean;
    FPanelHeight    : Integer;
    FPanelWidth     : Integer;

    FLastClockSec   : Integer;
    FAnimTimerActive : Boolean;

    // XCB connection details
    FConn           : Pxcb_connection_t;
    FScreen         : Pxcb_screen_t;
    FRootWindow     : Cardinal;

    // Cached EWMH atoms
    FAtomNetShowingDesktop: Cardinal;

    procedure InitAtoms();
    procedure SetupWindow();

    procedure HandleLauncherButtonClick(Sender: TFtButton);
    procedure HandleShowDesktopButtonClick(Sender: TFtButton);
    procedure HandleTrayLayoutChanged(Sender: TObject);
  public
    constructor Create(ALauncher: TShellLauncher = nil);
    destructor Destroy(); override;

    procedure Show();
    procedure Hide();
    procedure UpdateClock();
    procedure Tick();
    procedure ToggleShowDesktop();
    procedure OnLauncherClicked();

    function PanelX(): Integer;
    function PanelY(): Integer;
    function PanelWidth(): Integer;
    function PanelHeight(): Integer;

    property IsVisible       : Boolean          read FIsVisible;
    property WindowWidget    : TFtWindow        read FWindow;
    property LauncherWidget  : TFtButton        read FLauncherBtn;
    property ClockWidget     : TFtLabel         read FClockText;
    property ShowDesktopWidget: TFtButton       read FShowDesktopBtn;
    property TrayWidget      : TShellSystemTray read FTray;
    property VolumeApplet    : TShellVolumeApplet read FVolumeApplet;
    property SessionApplet   : TShellSessionApplet read FSessionApplet;
    property Launcher        : TShellLauncher   read FLauncher;
  end;

var
  GTopPanelInstance: TShellTopPanel = nil;

implementation

uses
  ShellSama.BottomPanel;

const
  SVG_PANEL_ICON_COLOR = '#2c3e50';

  PANEL_TIMER_MS = 250;
  PANEL_ANIM_TIMER_MS = 16;

  SVG_DESKTOP_ICON =
    '<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="' + SVG_PANEL_ICON_COLOR + '" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">' +
    '<rect x="2" y="3" width="20" height="14" rx="2" ry="2"/>' +
    '<line x1="8" y1="21" x2="16" y2="21"/>' +
    '<line x1="12" y1="17" x2="12" y2="21"/>' +
    '</svg>';

  SVG_LAUNCHER_ICON =
    '<svg width="8.9767046mm" height="8.9767008mm" viewBox="0 0 8.9767046 8.9767008" version="1.1" id="svg1" xml:space="preserve" xmlns="http://www.w3.org/2000/svg" xmlns:svg="http://www.w3.org/2000/svg"><defs id="defs1" /><g id="layer1" transform="translate(-85.829456,-57.641576)"><g id="g33"><path style="fill:#4d4d4d;fill-opacity:1;stroke:none;stroke-width:0.780001;stroke-linecap:round;stroke-linejoin:round;stroke-dasharray:none;stroke-opacity:1" d="m 85.829453,62.129926 v -4.488354 l 2.100851,5e-6 c 1.155467,4e-6 3.175228,0.0045 4.488353,0.01004 l 2.387503,0.01003 v 4.478314 4.478311 h -4.488353 -4.488354 z m 7.87962,4.316799 c 0.0267,-0.01137 0.06268,-0.03684 0.07995,-0.05658 0.01727,-0.01975 0.161539,-0.314534 0.320597,-0.655099 l 0.289194,-0.619206 -5.5e-5,-3.009194 c -5.6e-5,-2.976087 -4.13e-4,-3.009734 -0.03004,-3.058363 -0.01649,-0.02705 -0.0521,-0.06266 -0.07915,-0.07915 -0.04714,-0.02874 -0.07724,-0.02998 -0.728317,-0.03003 -0.773398,-6.6e-5 -0.754634,-0.0029 -0.81823,0.121179 l -0.03395,0.0662 4.12e-4,2.821826 c 4.13e-4,2.736719 0.0012,2.823725 0.02891,2.884769 0.03457,0.07614 0.0852,0.111857 0.172513,0.121699 0.08279,0.0093 0.168354,-0.02902 0.207316,-0.09291 0.02744,-0.04501 0.02834,-0.131857 0.02839,-2.765885 l 5.6e-5,-2.719413 h 0.407346 0.407347 v 2.813606 2.813606 l -0.219504,0.0031 c -0.222384,0.0031 -0.225916,0.0024 -0.252718,-0.04639 -0.04949,-0.0901 -0.04351,-0.165435 0.02082,-0.262529 0.05437,-0.08206 0.05408,-0.08573 -0.02084,-0.265225 -0.04403,-0.105504 -0.09706,-0.187313 -0.158285,-0.244301 -0.07705,-0.07172 -0.137831,-0.09761 -0.264879,-0.112837 -0.101739,-0.01219 -0.125208,-0.0076 -0.198305,0.03875 -0.05608,0.03556 -0.07886,0.06828 -0.116523,0.167389 -0.02619,0.06893 -0.04018,0.0854 -0.08865,0.104446 -0.03362,0.01321 -0.07715,0.01579 -0.125553,0.0074 -0.05739,-0.0099 -0.08051,-0.02534 -0.113278,-0.07548 -0.02713,-0.04153 -0.03056,-0.06941 -0.03451,-0.278788 -0.0028,-0.151771 -0.01083,-0.254145 -0.02078,-0.266205 -0.02434,-0.0295 -0.09794,-0.03966 -0.139686,-0.01929 -0.05584,0.02725 -0.06229,0.05581 -0.06229,0.275525 v 0.244439 l -0.241315,-0.0031 -0.241316,-0.0031 v -0.237248 c 0,-0.231908 -0.0035,-0.242862 -0.05436,-0.266589 -0.05367,-0.02507 -0.114755,-0.01633 -0.144403,0.0207 -0.02452,0.03063 -0.02497,0.06013 -0.02497,1.642954 0,1.521855 0.0019,1.614392 0.02497,1.649364 0.03328,0.05045 0.100914,0.06456 0.160416,0.03348 0.03816,-0.01994 0.03838,-0.02294 0.03838,-0.505036 v -0.484218 l 0.244309,-0.0031 0.244309,-0.0031 v 0.478951 c 0,0.474619 4.31e-4,0.480031 0.0378,0.513876 0.04899,0.04437 0.115865,0.04443 0.162791,1.51e-4 0.03774,-0.03561 0.03784,-0.0425 0.03784,-0.514781 v -0.478952 h 0.06224 c 0.03423,0 0.08272,0.01353 0.107755,0.03006 0.0435,0.02873 0.08151,0.08639 0.107931,0.163688 0.02061,0.0603 0.0382,0.08051 0.08581,0.09865 0.0583,0.02221 0.126485,0.01509 0.170668,-0.01784 0.05007,-0.03731 0.06316,-0.07684 0.06316,-0.191068 0,-0.147716 -0.03572,-0.222718 -0.158223,-0.332304 -0.07478,-0.06689 -0.07447,-0.06822 0.04381,-0.187317 0.09337,-0.09403 0.145893,-0.185257 0.182414,-0.316886 0.01925,-0.06938 0.02251,-0.134542 0.02452,-0.489725 l 0.0026,-0.407982 h 0.244903 0.244903 v 1.255201 1.255201 l 0.32049,0.0044 c 0.38096,0.0053 0.368817,0.0028 0.449767,-0.08775 0.03264,-0.03652 0.03612,-0.06173 0.03612,-0.261899 0,-0.237248 -0.0076,-0.268759 -0.08552,-0.354146 -0.0315,-0.03452 -0.08271,-0.05877 -0.174175,-0.08253 -0.116743,-0.03033 -0.169123,-0.06806 -0.203673,-0.146682 -0.03848,-0.08757 -0.03403,-0.188452 0.01168,-0.264426 0.0487,-0.08095 0.117188,-0.104443 0.245842,-0.08422 0.06208,0.0097 0.137839,0.04886 0.184852,0.09546 0.06014,0.05961 0.07342,0.09789 0.08599,0.247852 0.01124,0.134193 0.02029,0.165181 0.07686,0.263595 0.08254,0.143606 0.231948,0.223963 0.436154,0.235122 0.198308,0.01083 0.252062,0.0025 0.324316,-0.05035 0.08736,-0.06387 0.108269,-0.127814 0.108269,-0.331295 0,-0.146206 -0.0069,-0.178652 -0.04944,-0.232304 -0.03577,-0.04509 -0.08985,-0.0743 -0.223847,-0.120785 -0.10842,-0.03761 -0.13328,-0.05602 -0.172605,-0.127622 -0.03816,-0.06949 -0.03866,-0.181297 -0.0012,-0.261882 0.04153,-0.08933 0.117625,-0.125959 0.256034,-0.123307 0.121516,0.0023 0.185253,0.03157 0.241516,0.110793 0.04781,0.06732 0.05193,0.09341 0.05561,0.352467 l 0.0041,0.279864 0.253073,-0.0023 0.253074,-0.0023 0.003,-0.301385 c 0.0036,-0.362145 -0.01047,-0.443194 -0.09241,-0.531818 -0.07223,-0.07812 -0.155702,-0.109598 -0.328328,-0.123791 -0.191147,-0.01572 -0.280145,-0.0039 -0.38096,0.05064 -0.133611,0.07224 -0.225936,0.22104 -0.231945,0.374005 -0.0044,0.112102 -0.0247,0.152341 -0.106846,0.211831 -0.05646,0.04089 -0.08272,0.0461 -0.192534,0.03817 -0.104273,-0.0075 -0.144708,-0.02279 -0.189531,-0.07172 -0.07068,-0.07716 -0.07727,-0.142387 -0.03716,-0.367675 0.03534,-0.198533 0.0222,-0.298135 -0.04944,-0.375126 -0.0693,-0.07447 -0.165489,-0.106401 -0.354146,-0.117498 -0.170669,-0.01 -0.233777,-0.0023 -0.316823,0.03848 -0.117182,0.05753 -0.222378,0.199464 -0.234383,0.316279 -0.0094,0.09139 -0.02102,0.11649 -0.0805,0.173873 -0.08632,0.08328 -0.201886,0.08709 -0.281855,0.0093 -0.03898,-0.03792 -0.05096,-0.08226 -0.05096,-0.188736 0,-0.118671 0.0078,-0.145789 0.05658,-0.197772 0.05739,-0.06117 0.16104,-0.113063 0.254145,-0.127029 0.08278,-0.01242 0.08278,-0.01242 0.08278,-0.227318 0,-0.239308 -0.0069,-0.276495 -0.07328,-0.395634 -0.09633,-0.172935 -0.222684,-0.227653 -0.505298,-0.218816 -0.28096,0.0088 -0.392476,0.06317 -0.490709,0.239097 -0.06733,0.120577 -0.07419,0.16347 -0.07419,0.464673 0,0.301205 0.0069,0.344097 0.07419,0.464674 0.09823,0.175924 0.209749,0.230321 0.490709,0.239097 0.282614,0.0088 0.40897,-0.04588 0.505298,-0.218817 0.06634,-0.119139 0.07328,-0.156326 0.07328,-0.395634 0,-0.214899 1.48e-4,-0.214899 0.07921,-0.214899 0.08253,0 0.104445,0.01353 0.148818,0.09172 0.04437,0.0782 0.04437,0.106517 3.32e-4,0.187317 -0.03848,0.07062 -0.101738,0.105608 -0.223847,0.123806 -0.187314,0.02789 -0.272115,0.120287 -0.272115,0.296332 0,0.117627 0.02029,0.185257 0.07419,0.247852 0.06316,0.07328 0.121696,0.09848 0.260492,0.112002 0.176465,0.01719 0.233077,0.03719 0.312988,0.110597 0.08581,0.07883 0.108269,0.165427 0.108269,0.417242 0,0.313887 -0.02891,0.443196 -0.120894,0.540134 -0.08775,0.09249 -0.164871,0.121699 -0.362143,0.137837 -0.198308,0.01622 -0.268759,0.0076 -0.37038,-0.04509 -0.123808,-0.06429 -0.217316,-0.184852 -0.238914,-0.308298 -0.01168,-0.06679 -0.01994,-0.08375 -0.05436,-0.111857 -0.05267,-0.04297 -0.142385,-0.04358 -0.192534,-0.0013 -0.0487,0.04107 -0.05739,0.08051 -0.05739,0.26253 0,0.252062 0.0051,0.278788 0.0693,0.38096 0.09459,0.150742 0.262529,0.237248 0.505298,0.261899 0.09715,0.0099 0.135245,0.0054 0.218556,-0.02484 0.0693,-0.02517 0.134542,-0.06173 0.179831,-0.101103 l 0.06854,-0.05963 0.0035,0.235948 0.0035,0.235949 h 0.253075 0.253074 v -1.255201 -1.255201 -0.02713,-1.301914 -0.07695,-0.140939 -0.293174,-0.145601 -0.383164,-0.0083 -0.0257,0.03921 -0.02723,0.11281 -0.02723,1.310173 0,1.19736 0.0015,1.27096 0.02723,1.310172 0.06364,0.09713 0.209568,0.130743 0.307729,0.07089 z m 1.55987,-0.657622 c 0.02485,-0.01285 0.05844,-0.0451 0.07463,-0.07166 0.02794,-0.04583 0.02945,-0.07992 0.02945,-0.666864 0,-0.586943 -0.0015,-0.621032 -0.02945,-0.666863 -0.06026,-0.09883 -0.20459,-0.129932 -0.307579,-0.06628 -0.04008,0.02477 -0.06169,0.0536 -0.08105,0.108122 l -0.0264,0.07435 h -0.109612 c -0.103596,0 -0.109614,-0.0019 -0.109666,-0.03395 -8.7e-5,-0.05138 -0.05294,-0.127416 -0.108656,-0.156345 -0.10961,-0.0569 -0.2463,-0.01688 -0.30007,0.08785 -0.02684,0.05227 -0.02874,0.09557 -0.02874,0.653258 0,0.654207 -0.0012,0.644509 0.09114,0.722225 l 0.04696,0.03952 h 0.406939 c 0.337884,0 0.414603,-0.004 0.452116,-0.02336 z m 2.513593,-1.33385 c 0.06016,-0.03668 0.09503,-0.102093 0.09503,-0.17826 0,-0.08877 -0.224821,-1.299499 -0.250539,-1.349232 -0.03365,-0.06508 -0.105663,-0.102382 -0.197771,-0.102448 -0.06648,-4.7e-5 -0.08692,0.0072 -0.131824,0.0466 -0.09878,0.08673 -0.09875,0.08774 0.02106,0.745402 0.05895,0.323614 0.114308,0.624101 0.123016,0.667747 0.01652,0.08278 0.07094,0.163043 0.125553,0.185133 0.05763,0.02332 0.164943,0.01587 0.215485,-0.01494 z m 2.25325,-0.02803 c 0.03168,-0.03168 0.06251,-0.07715 0.0685,-0.101055 0.01407,-0.05602 -0.213496,-1.320293 -0.251142,-1.395301 -0.03457,-0.06889 -0.09963,-0.105609 -0.187091,-0.105609 -0.127741,0 -0.219278,0.08242 -0.219397,0.197536 -9.9e-5,0.09339 0.225071,1.300803 0.252714,1.355121 0.03696,0.07262 0.100207,0.106779 0.197839,0.106847 0.07375,5.2e-5 0.08612,-0.0051 0.138575,-0.05754 z m -3.867547,-1.465572 c 0.06396,-0.03899 0.09502,-0.102999 0.09502,-0.195754 0,-0.06166 -0.0078,-0.08458 -0.04149,-0.121843 -0.02282,-0.02524 -0.211216,-0.162948 -0.418662,-0.306007 l -0.377172,-0.26011 -0.0041,-0.335863 -0.0041,-0.335864 0.177561,0.1228 c 0.3833,0.265081 0.376268,0.261089 0.457639,0.259861 0.08568,-0.0012 0.138485,-0.03042 0.180736,-0.09972 0.0383,-0.06281 0.03849,-0.169074 4.13e-4,-0.231497 -0.01873,-0.03072 -0.16732,-0.142648 -0.420592,-0.316825 l -0.391628,-0.269322 -0.0055,-0.174174 c -0.0062,-0.193038 -0.02155,-0.233798 -0.108212,-0.286641 -0.09508,-0.05797 -0.249141,-0.02512 -0.299955,0.06397 -0.01221,0.02141 -0.02272,0.109799 -0.02736,0.230293 l -0.0076,0.195542 -0.324369,0.231665 c -0.378136,0.270069 -0.387479,0.278094 -0.409553,0.351772 -0.04787,0.15977 0.08577,0.309713 0.248777,0.279134 0.03249,-0.0061 0.136069,-0.06881 0.264883,-0.160364 0.116342,-0.0827 0.215192,-0.150358 0.219667,-0.150358 0.0044,0 0.0081,0.145558 0.0081,0.323461 v 0.323461 l -0.342823,0.24607 c -0.202119,0.145077 -0.356918,0.267111 -0.377172,0.297335 -0.103383,0.154281 0.0415,0.362204 0.228009,0.327216 0.03162,-0.0059 0.173245,-0.09694 0.373302,-0.239889 0.177297,-0.126682 0.330829,-0.235541 0.341183,-0.241908 0.01192,-0.0073 0.155458,0.08273 0.391657,0.245771 0.361928,0.249823 0.375053,0.257346 0.448868,0.257293 0.04878,-3.7e-5 0.09335,-0.01063 0.124338,-0.02951 z m 4.405608,-2.24358 c 0.149262,-0.07083 0.147982,-0.316909 -0.002,-0.388089 -0.04604,-0.02184 -0.232871,-0.02424 -1.894661,-0.02424 -1.66179,0 -1.848623,0.0024 -1.894661,0.02424 -0.148814,0.07062 -0.150268,0.326555 -0.0023,0.390916 0.04094,0.0178 0.343882,0.02128 1.894601,0.02177 1.693766,6.2e-4 1.850241,-0.0015 1.898959,-0.0246 z" id="path25" /><path style="fill:#4d4d4d;fill-opacity:1;stroke:none;stroke-width:0.780001;stroke-linecap:round;stroke-linejoin:round;stroke-dasharray:none;stroke-opacity:1" d="m 86.629245,59.10965 v -0.104338 l 0.06854,0.0058 c 0.0377,0.0032 0.10623,0.0058 0.152295,0.0058 h 0.08375 v 0.09854 0.09854 h -0.15229 -0.152294 z" id="path30" /><path style="fill:#4d4d4d;fill-opacity:1;stroke:none;stroke-width:0.780001;stroke-linecap:round;stroke-linejoin:round;stroke-dasharray:none;stroke-opacity:1" d="m 86.629245,60.562238 v -0.103024 l 0.06495,4.8e-5 c 0.03572,2.4e-5 0.104253,0.0027 0.152293,0.0058 l 0.08735,0.0058 v 0.09719 0.09719 h -0.152295 -0.152294 z" id="path31" /><path style="fill:#4d4d4d;fill-opacity:1;stroke:none;stroke-width:0.780001;stroke-linecap:round;stroke-linejoin:round;stroke-dasharray:none;stroke-opacity:1" d="m 88.483649,62.869045 v -0.223962 h 0.11646 0.116461 v 0.223962 0.223961 h -0.116461 -0.11646 z" id="path32" /></g></g></svg>';

function ResolveLauncherIconSVG(): string;
var
  candidates: array[0..3] of string;
  i: Integer;
  sl: TStringList;
begin
  candidates[0] := ExtractFilePath(ParamStr(0)) + 'assets/kiranalogo.light.svg';
  candidates[1] := 'assets/kiranalogo.light.svg';
  candidates[2] := '../.github/asset/kiranalogo.light.svg';
  candidates[3] := '/usr/share/shellsama/assets/kiranalogo.light.svg';

  for i := 0 to High(candidates) do
  begin
    if (candidates[i] <> '') and FileExists(candidates[i]) then
    begin
      sl := TStringList.Create();
      try
        sl.LoadFromFile(candidates[i]);
        Result := sl.Text;
        if Result <> '' then
          Exit();
      finally
        sl.Free();
      end;
    end;
  end;

  Result := SVG_LAUNCHER_ICON;
end;

procedure c_free(p: Pointer); cdecl; external 'c' name 'free';

function InternAtom(AConn: Pxcb_connection_t; const AName: string): Cardinal;
var
  cookie: xcb_intern_atom_cookie_t;
  reply: Pxcb_intern_atom_reply_t;
begin
  Result := 0;
  if AConn = nil then Exit;
  cookie := xcb_intern_atom(AConn, 0, Length(AName), PChar(AName));
  reply := xcb_intern_atom_reply(AConn, cookie, nil);
  if reply <> nil then
  begin
    Result := reply^.atom;
    c_free(reply);
  end;
end;

procedure TopPanelTickCallback(user_data: Pointer); cdecl;
begin
  if Assigned(user_data) then
    TShellTopPanel(user_data).Tick();
end;

// -----------------------------------------------------------------------------
// TShellTopPanel Implementation
// -----------------------------------------------------------------------------

constructor TShellTopPanel.Create(ALauncher: TShellLauncher = nil);
begin
  inherited Create();
  GTopPanelInstance := Self;
  FLauncher := ALauncher;
  FIsVisible := False;
  FShowingDesktop := False;
  FPanelHeight := 38;
  FLastClockSec := -1;
  FAnimTimerActive := False;

  if FtIsLibLoaded() and Assigned(ft_screen_get_width) then
    FPanelWidth := FtApp().ScreenWidth
  else
    FPanelWidth := 1920;

  if FtIsLibLoaded() and Assigned(ft_backend_get_connection) then
  begin
    FConn := Pxcb_connection_t(ft_backend_get_connection());
    FScreen := Pxcb_screen_t(ft_backend_get_screen());
    if FScreen <> nil then
      FRootWindow := FScreen^.root
    else
      FRootWindow := 0;
  end;

  InitAtoms();
  SetupWindow();

  if FtIsLibLoaded() then
  begin
    if Assigned(ft_set_timer) then
      ft_set_timer(PANEL_TIMER_MS, @TopPanelTickCallback, Self)
    else if Assigned(ft_set_tick_callback) then
      ft_set_tick_callback(@TopPanelTickCallback, Self);
  end;
end;

destructor TShellTopPanel.Destroy();
begin
  if GTopPanelInstance = Self then
    GTopPanelInstance := nil;

  if FtIsLibLoaded() then
  begin
    if Assigned(ft_set_timer) then
      ft_set_timer(0, nil, nil)
    else if Assigned(ft_set_tick_callback) then
      ft_set_tick_callback(nil, nil);
  end;

  if Assigned(FTray) then
  begin
    FTray.Free();
    FTray := nil;
  end;

  if Assigned(FVolumeApplet) then
  begin
    FVolumeApplet.Free();
    FVolumeApplet := nil;
  end;

  if Assigned(FSessionApplet) then
  begin
    FSessionApplet.Free();
    FSessionApplet := nil;
  end;

  if Assigned(FWindow) then
  begin
    FWindow.Free();
    FWindow := nil;
    FLauncherBtn := nil;
    FClockText := nil;
    FShowDesktopBtn := nil;
  end;

  inherited Destroy();
end;

procedure TShellTopPanel.HandleLauncherButtonClick(Sender: TFtButton);
begin
  OnLauncherClicked();
end;

procedure TShellTopPanel.HandleShowDesktopButtonClick(Sender: TFtButton);
begin
  ToggleShowDesktop();
end;

procedure TShellTopPanel.HandleTrayLayoutChanged(Sender: TObject);
var
  trayW, trayX: Integer;
begin
  if Assigned(FTray) then
  begin
    trayW := FTray.Width;
    trayX := (FPanelWidth - 212) - trayW;
    FTray.SetPosition(trayX, (FPanelHeight - FTray.IconSize) div 2);
  end;
end;

procedure TShellTopPanel.InitAtoms();
begin
  if FConn = nil then Exit;
  FAtomNetShowingDesktop := InternAtom(FConn, '_NET_SHOWING_DESKTOP');
end;

procedure TShellTopPanel.SetupWindow();
var
  py: Integer;
begin
  if not FtIsLibLoaded() then Exit;

  py := PanelY();
  FWindow := TFtWindow.Create(FPanelWidth, FPanelHeight, 'shellsama-top-panel');
  if FWindow = nil then Exit;

  FWindow.WindowType := ftwtDock;
  FWindow.Borderless := True;
  FWindow.SkipTaskbar := True;
  FWindow.SetPosition(0, py);

  // Reserve top screen space via _NET_WM_STRUT & _NET_WM_STRUT_PARTIAL
  FWindow.SetStrutPartial(
    0, 0, FPanelHeight, 0,
    0, 0, 0, 0,
    0, FPanelWidth - 1, 0, 0
  );

  // 1. Launcher button on the left
  FLauncherBtn := TFtButton.Create(FWindow, 6, 3, 114, 32, 'Samarinda');
  FLauncherBtn.IsToggle := True;
  FLauncherBtn.CornerRadius := 6.0;
  FLauncherBtn.IconPosition := ftipLeft;
  FLauncherBtn.SetIconSize(18, 18);
  FLauncherBtn.IconGap := 6;
  FLauncherBtn.SetIconSVG(ResolveLauncherIconSVG());
  FLauncherBtn.OnClick := @HandleLauncherButtonClick;

  // 2. Show Desktop button on the extreme right
  FShowDesktopBtn := TFtButton.Create(FWindow, FPanelWidth - 36, 3, 32, 32, '');
  FShowDesktopBtn.CornerRadius := 6.0;
  FShowDesktopBtn.IconPosition := ftipOnly;
  FShowDesktopBtn.SetIconSize(18, 18);
  FShowDesktopBtn.SetIconSVG(SVG_DESKTOP_ICON);
  FShowDesktopBtn.OnClick := @HandleShowDesktopButtonClick;

  // 3. Power / Session Applet (Shutdown button)
  FSessionApplet := TShellSessionApplet.Create(FWindow, FPanelWidth - 70, 3, 32, 32);

  // 4. Clock text label
  FClockText := TFtLabel.Create(FWindow, FPanelWidth - 164, 3, 90, 32, '--:--');
  FClockText.Alignment := ftaCenter;

  // 5. Volume Applet
  FVolumeApplet := TShellVolumeApplet.Create(FWindow, FPanelWidth - 204, 3, 36, 32);

  // 6. System Tray Host
  FTray := TShellSystemTray.Create(FWindow, 0);
  FTray.IconSize := 22;
  FTray.IconGap := 4;
  FTray.StartY := (FPanelHeight - FTray.IconSize) div 2;
  FTray.OnLayoutChanged := @HandleTrayLayoutChanged;
  FTray.ClaimSelection();

  UpdateClock();
end;

function TShellTopPanel.PanelX(): Integer;
begin
  Result := 0;
end;

function TShellTopPanel.PanelY(): Integer;
begin
  Result := 0;
end;

function TShellTopPanel.PanelWidth(): Integer;
begin
  Result := FPanelWidth;
end;

function TShellTopPanel.PanelHeight(): Integer;
begin
  Result := FPanelHeight;
end;

procedure TShellTopPanel.Show();
begin
  if FWindow = nil then Exit;
  FWindow.Show();
  FIsVisible := True;
  UpdateClock();
end;

procedure TShellTopPanel.Hide();
begin
  if FWindow = nil then Exit;
  FWindow.Hide();
  FIsVisible := False;
end;

procedure TShellTopPanel.UpdateClock();
var
  dt: TDateTime;
  sec: Integer;
  timeStr: string;
begin
  dt := Now();
  sec := DateTimeToTimeStamp(dt).Time div 1000;
  if sec = FLastClockSec then Exit;
  FLastClockSec := sec;

  timeStr := FormatDateTime('hh:nn:ss', dt);
  if Assigned(FClockText) then
    FClockText.Text := timeStr;
end;

procedure TShellTopPanel.Tick();
begin
  UpdateClock();

  if Assigned(FVolumeApplet) then
    FVolumeApplet.Tick();

  // Sync launcher button toggled state
  if Assigned(FLauncherBtn) and Assigned(FLauncher) then
    FLauncherBtn.Toggled := FLauncher.IsVisible;

  // Drive the launcher's scroll animation, and switch the panel's own timer to frame rate
  if Assigned(FLauncher) and FLauncher.IsVisible then
  begin
    FLauncher.Tick();
    if Assigned(ft_set_timer) then
    begin
      if FLauncher.IsAnimating and not FAnimTimerActive then
      begin
        FAnimTimerActive := True;
        ft_set_timer(PANEL_ANIM_TIMER_MS, @TopPanelTickCallback, Self);
      end
      else if not FLauncher.IsAnimating and FAnimTimerActive then
      begin
        FAnimTimerActive := False;
        ft_set_timer(PANEL_TIMER_MS, @TopPanelTickCallback, Self);
      end;
    end;
  end
  else if FAnimTimerActive then
  begin
    FAnimTimerActive := False;
    if Assigned(ft_set_timer) then
      ft_set_timer(PANEL_TIMER_MS, @TopPanelTickCallback, Self);
  end;

  // Also drive the bottom panel if active
  if Assigned(GBottomPanelInstance) then
    GBottomPanelInstance.Tick();
end;

procedure TShellTopPanel.OnLauncherClicked();
begin
  if FLauncher = nil then Exit;
  if FLauncher.IsVisible then
    FLauncher.Hide()
  else
    FLauncher.Show();
  if Assigned(FLauncherBtn) then
    FLauncherBtn.Toggled := FLauncher.IsVisible;
end;

procedure TShellTopPanel.ToggleShowDesktop();
var
  ev: xcb_client_message_event_t;
  data32: PCardinalArray;
begin
  if (FConn = nil) or (FRootWindow = 0) or (FAtomNetShowingDesktop = 0) then Exit;

  FShowingDesktop := not FShowingDesktop;

  FillChar(ev, SizeOf(ev), 0);
  ev.response_type := XCB_CLIENT_MESSAGE;
  ev.format := 32;
  ev.window := FRootWindow;
  ev.type_ := FAtomNetShowingDesktop;
  data32 := PCardinalArray(@ev.data.raw[0]);
  if FShowingDesktop then
    data32^[0] := 1
  else
    data32^[0] := 0;

  xcb_send_event(FConn, 0, FRootWindow,
                 XCB_EVENT_MASK_SUBSTRUCTURE_REDIRECT or XCB_EVENT_MASK_SUBSTRUCTURE_NOTIFY,
                 PAnsiChar(@ev));
  xcb_flush(FConn);
end;

end.
