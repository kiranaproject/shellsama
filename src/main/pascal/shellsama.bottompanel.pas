{ Unit ShellSama.BottomPanel — Desktop Bottom Panel & Taskbar for Samarinda DE }

unit ShellSama.BottomPanel;

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

  TWindowIdArray = array of Cardinal;

  TWindowIconItem = record
    Window: Cardinal;
    Bitmap: TFtBitmap;
  end;

  TTaskItem = record
    Window     : Cardinal;
    Title      : string;
    IsActive   : Boolean;
    IsMinimized: Boolean;
    IsMaximized: Boolean;
    Button     : TFtButton;
    // Per-task context menu. One menu per task rather than one shared menu,
    // because the toolkit pops a widget's own menu and offers no hook before it
    // opens: a shared menu could not tell which task was right-clicked, and
    // OnPress only fires for the left button, so it is not a usable hook either.
    Menu       : TFtPopupMenu;
    MenuMinimize: TFtMenuItem;
    MenuMaximize: TFtMenuItem;
    MenuClose   : TFtMenuItem;
  end;

  TShellBottomPanel = class
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

    FTasks          : array of TTaskItem;
    FActiveWindow   : Cardinal;
    FLastClockSec   : Integer;
    FLastActiveWin  : Cardinal;
    // Window-id signature of the task set as of the last refresh. Lets Tick notice
    // a window appearing or disappearing without a full query every tick.
    FLastTaskSignature : AnsiString;

    // XCB connection details
    FConn           : Pxcb_connection_t;
    FScreen         : Pxcb_screen_t;
    FRootWindow     : Cardinal;

    // Cached EWMH atoms
    FAtomNetClientList        : Cardinal;
    FAtomNetActiveWindow      : Cardinal;
    FAtomNetWmName            : Cardinal;
    FAtomNetWmIcon            : Cardinal;
    FAtomNetWmState           : Cardinal;
    FAtomNetWmStateHidden     : Cardinal;
    FAtomNetWmStateMaxVert    : Cardinal;
    FAtomNetWmStateMaxHorz    : Cardinal;
    FAtomNetCloseWindow       : Cardinal;
    FAtomNetWmStateSkipTaskbar: Cardinal;
    FAtomNetWmWindowType      : Cardinal;
    FAtomNetWmWindowTypeDock  : Cardinal;
    FAtomNetWmWindowTypeDesk  : Cardinal;
    FAtomNetWmWindowTypeSplash: Cardinal;
    FAtomNetWmWindowTypeUtil  : Cardinal;
    FAtomNetWmWindowTypeTool  : Cardinal;
    FAtomNetWmWindowTypeMenu  : Cardinal;
    FAtomNetWmWindowTypeTip   : Cardinal;
    FAtomNetShowingDesktop    : Cardinal;
    FAtomUtf8String           : Cardinal;
    FAtomWMChangeState        : Cardinal;
    FAtomWMName               : Cardinal;
    FAtomWMClass              : Cardinal;

    // Window icon cache
    FWindowIconCache          : array of TWindowIconItem;

    procedure InitAtoms();
    procedure SetupWindow();
    procedure LayoutButtons();
    function QueryClientList(): TWindowIdArray;
    function QueryActiveWindow(): Cardinal;
    function QueryWindowTitle(AWin: Cardinal): string;
    function ShouldShowTask(AWin: Cardinal): Boolean;
    function IsWindowMinimized(AWin: Cardinal): Boolean;
    function IsWindowMaximized(AWin: Cardinal): Boolean;

    procedure HandleLauncherButtonClick(Sender: TFtButton);
    procedure HandleShowDesktopButtonClick(Sender: TFtButton);
    procedure HandleTaskButtonClick(Sender: TFtButton);
    procedure HandleTrayLayoutChanged(Sender: TObject);

    // Task context menu
    procedure BuildTaskMenu(var ATask: TTaskItem);
    procedure UpdateTaskMenuState(var ATask: TTaskItem);
    procedure HandleTaskMenuMinimize(Sender: TFtMenuItem);
    procedure HandleTaskMenuMaximize(Sender: TFtMenuItem);
    procedure HandleTaskMenuClose(Sender: TFtMenuItem);
  public
    constructor Create(ALauncher: TShellLauncher = nil);
    destructor Destroy(); override;

    procedure Show();
    procedure Hide();
    procedure RefreshTasks();
    procedure UpdateClock();
    procedure Tick();
    // Cheap signature of the current task set, so the panel can notice a window
    // appearing or disappearing without a full refresh.
    function TaskSetSignature(): AnsiString;

    function QueryWindowIcon(AWin: Cardinal; APreferredSize: Integer = 18): TFtBitmap;
    function GetOrLoadWindowIcon(AWin: Cardinal; APreferredSize: Integer = 18): TFtBitmap;

    procedure ActivateWindow(AWin: Cardinal);
    procedure MinimizeWindow(AWin: Cardinal);
    procedure UnminimizeWindow(AWin: Cardinal);
    procedure MaximizeWindow(AWin: Cardinal);
    procedure RestoreWindow(AWin: Cardinal);
    procedure CloseWindow(AWin: Cardinal);
    procedure ToggleShowDesktop();
    procedure OnLauncherClicked();
    procedure OnTaskClicked(AWin: Cardinal);

    function PanelX(): Integer;
    function PanelY(): Integer;
    function PanelWidth(): Integer;
    function PanelHeight(): Integer;
    function GetTaskCount(): Integer;
    function GetIconCacheCount(): Integer;
    function GetTaskIcon(AIndex: Integer): TFtBitmap;

    property IsVisible     : Boolean         read FIsVisible;
    property ActiveWindow  : Cardinal        read FActiveWindow;
    property TaskCount     : Integer         read GetTaskCount;
    property IconCacheCount: Integer         read GetIconCacheCount;
    property WindowWidget  : TFtWindow       read FWindow;
    property LauncherWidget: TFtButton       read FLauncherBtn;
    property ClockWidget   : TFtLabel        read FClockText;
    property TrayWidget    : TShellSystemTray read FTray;
    property VolumeApplet  : TShellVolumeApplet read FVolumeApplet;
    property SessionApplet : TShellSessionApplet read FSessionApplet;
  end;

var
  GBottomPanelInstance: TShellBottomPanel = nil;

implementation

const
  SVG_PANEL_ICON_COLOR = '#2c3e50';

  // How often the panel's timer fires.
  //
  // The panel's work is all slow-changing: the clock needs 1 Hz, the task list only
  // needs to notice active-window changes, and the volume applet polls only while
  // its popup is open. 250 ms keeps the clock visually exact (it updates on the
  // second boundary, not up to a second late) at a fraction of the cost of a frame
  // rate callback.
  PANEL_TIMER_MS = 250;

  SVG_DESKTOP_ICON =
    '<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="' + SVG_PANEL_ICON_COLOR + '" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">' +
    '<rect x="2" y="3" width="20" height="14" rx="2" ry="2"/>' +
    '<line x1="8" y1="21" x2="16" y2="21"/>' +
    '<line x1="12" y1="17" x2="12" y2="21"/>' +
    '</svg>';

  SVG_LAUNCHER_ICON =
    '<svg width="8.9767046mm" height="8.9767008mm" viewBox="0 0 8.9767046 8.9767008" version="1.1" id="svg1" xml:space="preserve" xmlns="http://www.w3.org/2000/svg" xmlns:svg="http://www.w3.org/2000/svg"><defs id="defs1" /><g id="layer1" transform="translate(-85.829456,-57.641576)"><g id="g33"><path style="fill:#4d4d4d;fill-opacity:1;stroke:none;stroke-width:0.780001;stroke-linecap:round;stroke-linejoin:round;stroke-dasharray:none;stroke-opacity:1" d="m 85.829453,62.129926 v -4.488354 l 2.100851,5e-6 c 1.155467,4e-6 3.175228,0.0045 4.488353,0.01004 l 2.387503,0.01003 v 4.478314 4.478311 h -4.488353 -4.488354 z m 7.87962,4.316799 c 0.0267,-0.01137 0.06268,-0.03684 0.07995,-0.05658 0.01727,-0.01975 0.161539,-0.314534 0.320597,-0.655099 l 0.289194,-0.619206 -5.5e-5,-3.009194 c -5.6e-5,-2.976087 -4.13e-4,-3.009734 -0.03004,-3.058363 -0.01649,-0.02705 -0.0521,-0.06266 -0.07915,-0.07915 -0.04714,-0.02874 -0.07724,-0.02998 -0.728317,-0.03003 -0.773398,-6.6e-5 -0.754634,-0.0029 -0.81823,0.121179 l -0.03395,0.0662 4.12e-4,2.821826 c 4.13e-4,2.736719 0.0012,2.823725 0.02891,2.884769 0.03457,0.07614 0.0852,0.111857 0.172513,0.121699 0.08279,0.0093 0.168354,-0.02902 0.207316,-0.09291 0.02744,-0.04501 0.02834,-0.131857 0.02839,-2.765885 l 5.6e-5,-2.719413 h 0.407346 0.407347 v 2.813606 2.813606 l -0.274617,0.584719 c -0.238838,0.508541 -0.274709,0.594547 -0.275337,0.660154 -0.0015,0.15977 0.150411,0.260846 0.297733,0.198074 z m -3.490265,-0.05307 c 0.02025,-0.0144 0.05039,-0.0444 0.06702,-0.06667 0.04151,-0.0556 0.04134,-0.176558 -4.13e-4,-0.233035 -0.01681,-0.02279 -0.174271,-0.163042 -0.3499,-0.311683 l -0.319324,-0.270252 v -0.199851 -0.199853 l 0.158412,-0.401458 0.158413,-0.401458 V 62.91415 61.518907 h 0.106091 c 0.125373,0 0.189753,-0.02351 0.245384,-0.08963 0.07875,-0.09359 0.04423,-0.268866 -0.06396,-0.324816 -0.04052,-0.02095 -0.171889,-0.02318 -1.153605,-0.0196 l -1.107872,0.0041 -0.04036,0.03771 c -0.06363,0.05946 -0.08709,0.117044 -0.07855,0.192809 0.0091,0.08059 0.04767,0.137387 0.117562,0.173025 0.04718,0.02405 0.117179,0.02638 0.794764,0.0264 l 0.743028,2.5e-5 v 1.347307 1.347309 l -0.15921,0.403148 -0.159214,0.403148 0.0046,0.338017 c 0.0042,0.314837 0.0067,0.340934 0.03599,0.380569 0.02616,0.03544 0.519286,0.464314 0.720243,0.626405 0.09291,0.07494 0.20055,0.08599 0.28086,0.02885 z m -3.302205,-0.08772 c 0.09562,-0.08046 0.08963,0.09776 0.08963,-2.664643 v -2.525353 l 0.105559,-0.0089 c 0.12617,-0.01058 0.188764,-0.04338 0.227786,-0.119392 0.02591,-0.05048 0.02874,-0.09168 0.02874,-0.419263 0,-0.327589 -0.0028,-0.368789 -0.02874,-0.419263 -0.03955,-0.07703 -0.105565,-0.111623 -0.229976,-0.120525 l -0.103369,-0.0074 v -0.18656 -0.186559 h 0.111992 c 0.0997,0 0.117317,-0.0044 0.160464,-0.04079 0.08392,-0.07062 0.08963,-0.102333 0.08963,-0.498323 0,-0.318213 -0.0031,-0.365011 -0.02752,-0.411603 -0.03842,-0.0734 -0.13501,-0.120459 -0.247243,-0.120459 h -0.08732 l -2.5e-5,-0.267793 c -1.9e-5,-0.225136 -0.0042,-0.276033 -0.0264,-0.319525 -0.03564,-0.06989 -0.09243,-0.108479 -0.173026,-0.117563 -0.07925,-0.0089 -0.140424,0.01785 -0.198555,0.08693 l -0.03951,0.04696 v 0.283945 0.283945 l -0.127031,0.0053 c -0.110454,0.0046 -0.132366,0.01023 -0.167902,0.04304 -0.07637,0.07048 -0.08224,0.105462 -0.08224,0.490324 0,0.392173 0.0058,0.424276 0.08963,0.4948 0.04375,0.03682 0.06011,0.04079 0.168007,0.04079 h 0.119537 v 0.188588 0.188584 h -0.11092 c -0.0902,0 -0.120496,0.0064 -0.162185,0.03425 -0.09756,0.06517 -0.104018,0.09623 -0.104045,0.500346 -2e-5,0.328997 0.0027,0.366576 0.02983,0.422764 0.04046,0.08358 0.09853,0.11444 0.234771,0.124742 l 0.112548,0.0085 v 2.540713 c 0,2.264308 0.0026,2.545631 0.02336,2.585894 0.05567,0.107663 0.231181,0.141955 0.324529,0.06341 z m 5.003366,-0.69781 c 0.06476,-0.03948 0.08173,-0.0683 0.174183,-0.295775 l 0.07934,-0.195214 v -3.009838 c 0,-2.982745 -2.07e-4,-3.010298 -0.03017,-3.060934 -0.01659,-0.02811 -0.05383,-0.06375 -0.08274,-0.07921 -0.04904,-0.02622 -0.098,-0.02811 -0.728693,-0.02811 -0.73091,0 -0.716599,-0.0015 -0.79532,0.08276 l -0.03771,0.04037 v 2.88671 2.886713 l 0.03771,0.04037 c 0.115443,0.123552 0.293922,0.104897 0.365834,-0.03824 0.02482,-0.0494 0.02638,-0.212301 0.02641,-2.75683 l 2.3e-5,-2.704328 h 0.399802 0.399804 v 2.825148 2.825148 l -0.06789,0.173248 c -0.03734,0.09529 -0.06786,0.197068 -0.06783,0.22618 1.67e-4,0.157599 0.192105,0.264242 0.327263,0.181832 z m -5.597154,-1.448397 c 0.09998,-0.06096 0.09503,0.01106 0.09503,-1.381061 0,-1.109183 -0.0028,-1.266704 -0.02336,-1.306435 -0.07058,-0.136485 -0.290973,-0.138661 -0.379393,-0.0037 -0.02557,0.03902 -0.0275,0.115251 -0.03173,1.256707 -0.0025,0.668341 -4.13e-4,1.243988 0.0047,1.279216 0.0098,0.068 0.06644,0.148885 0.119297,0.170268 0.05763,0.02331 0.164943,0.01587 0.215486,-0.01494 z m 1.161693,0 c 0.02656,-0.0162 0.06051,-0.05181 0.07543,-0.07915 0.0255,-0.04671 0.02713,-0.124932 0.02713,-1.301912 0,-1.176981 -0.0016,-1.255201 -0.02713,-1.301914 -0.07695,-0.140939 -0.293174,-0.145601 -0.383164,-0.0083 -0.0257,0.03921 -0.02723,0.11281 -0.02723,1.310173 0,1.19736 0.0015,1.27096 0.02723,1.310172 0.06364,0.09713 0.209568,0.130743 0.307729,0.07089 z m 1.55987,-0.657622 c 0.02485,-0.01285 0.05844,-0.0451 0.07463,-0.07166 0.02794,-0.04583 0.02945,-0.07992 0.02945,-0.666864 0,-0.586943 -0.0015,-0.621032 -0.02945,-0.666863 -0.06026,-0.09883 -0.20459,-0.129932 -0.307579,-0.06628 -0.04008,0.02477 -0.06169,0.0536 -0.08105,0.108122 l -0.0264,0.07435 h -0.109612 c -0.103596,0 -0.109614,-0.0019 -0.109666,-0.03395 -8.7e-5,-0.05138 -0.05294,-0.127416 -0.108656,-0.156345 -0.10961,-0.0569 -0.2463,-0.01688 -0.30007,0.08785 -0.02684,0.05227 -0.02874,0.09557 -0.02874,0.653258 0,0.654207 -0.0012,0.644509 0.09114,0.722225 l 0.04696,0.03952 h 0.406939 c 0.337884,0 0.414603,-0.004 0.452116,-0.02336 z m 2.513593,-1.33385 c 0.06016,-0.03668 0.09503,-0.102093 0.09503,-0.17826 0,-0.08877 -0.224821,-1.299499 -0.250539,-1.349232 -0.03365,-0.06508 -0.105663,-0.102382 -0.197771,-0.102448 -0.06648,-4.7e-5 -0.08692,0.0072 -0.131824,0.0466 -0.09878,0.08673 -0.09875,0.08774 0.02106,0.745402 0.05895,0.323614 0.114308,0.624101 0.123016,0.667747 0.01652,0.08278 0.07094,0.163043 0.125553,0.185133 0.05763,0.02332 0.164943,0.01587 0.215485,-0.01494 z m 2.25325,-0.02803 c 0.03168,-0.03168 0.06251,-0.07715 0.0685,-0.101055 0.01407,-0.05602 -0.213496,-1.320293 -0.251142,-1.395301 -0.03457,-0.06889 -0.09963,-0.105609 -0.187091,-0.105609 -0.127741,0 -0.219278,0.08242 -0.219397,0.197536 -9.9e-5,0.09339 0.225071,1.300803 0.252714,1.355121 0.03696,0.07262 0.100207,0.106779 0.197839,0.106847 0.07375,5.2e-5 0.08612,-0.0051 0.138575,-0.05754 z m -3.867547,-1.465572 c 0.06396,-0.03899 0.09502,-0.102999 0.09502,-0.195754 0,-0.06166 -0.0078,-0.08458 -0.04149,-0.121843 -0.02282,-0.02524 -0.211216,-0.162948 -0.418662,-0.306007 l -0.377172,-0.26011 -0.0041,-0.335863 -0.0041,-0.335864 0.177561,0.1228 c 0.3833,0.265081 0.376268,0.261089 0.457639,0.259861 0.08568,-0.0012 0.138485,-0.03042 0.180736,-0.09972 0.0383,-0.06281 0.03849,-0.169074 4.13e-4,-0.231497 -0.01873,-0.03072 -0.16732,-0.142648 -0.420592,-0.316825 l -0.391628,-0.269322 -0.0055,-0.174174 c -0.0062,-0.193038 -0.02155,-0.233798 -0.108212,-0.286641 -0.09508,-0.05797 -0.249141,-0.02512 -0.299955,0.06397 -0.01221,0.02141 -0.02272,0.109799 -0.02736,0.230293 l -0.0076,0.195542 -0.324369,0.231665 c -0.378136,0.270069 -0.387479,0.278094 -0.409553,0.351772 -0.04787,0.15977 0.08577,0.309713 0.248777,0.279134 0.03249,-0.0061 0.136069,-0.06881 0.264883,-0.160364 0.116342,-0.0827 0.215192,-0.150358 0.219667,-0.150358 0.0044,0 0.0081,0.145558 0.0081,0.323461 v 0.323461 l -0.342823,0.24607 c -0.202119,0.145077 -0.356918,0.267111 -0.377172,0.297335 -0.103383,0.154281 0.0415,0.362204 0.228009,0.327216 0.03162,-0.0059 0.173245,-0.09694 0.373302,-0.239889 0.177297,-0.126682 0.330829,-0.235541 0.341183,-0.241908 0.01192,-0.0073 0.155458,0.08273 0.391657,0.245771 0.361928,0.249823 0.375053,0.257346 0.448868,0.257293 0.04878,-3.7e-5 0.09335,-0.01063 0.124338,-0.02951 z m 4.405608,-2.24358 c 0.149262,-0.07083 0.147982,-0.316909 -0.002,-0.388089 -0.04604,-0.02184 -0.232871,-0.02424 -1.894661,-0.02424 -1.66179,0 -1.848623,0.0024 -1.894661,0.02424 -0.148814,0.07062 -0.150268,0.326555 -0.0023,0.390916 0.04094,0.0178 0.343882,0.02128 1.894601,0.02177 1.693766,6.2e-4 1.850241,-0.0015 1.898959,-0.0246 z" id="path25" /><path style="fill:#4d4d4d;fill-opacity:1;stroke:none;stroke-width:0.780001;stroke-linecap:round;stroke-linejoin:round;stroke-dasharray:none;stroke-opacity:1" d="m 86.629245,59.10965 v -0.104338 l 0.06854,0.0058 c 0.0377,0.0032 0.10623,0.0058 0.152295,0.0058 h 0.08375 v 0.09854 0.09854 h -0.15229 -0.152294 z" id="path30" /><path style="fill:#4d4d4d;fill-opacity:1;stroke:none;stroke-width:0.780001;stroke-linecap:round;stroke-linejoin:round;stroke-dasharray:none;stroke-opacity:1" d="m 86.629245,60.562238 v -0.103024 l 0.06495,4.8e-5 c 0.03572,2.4e-5 0.104253,0.0027 0.152293,0.0058 l 0.08735,0.0058 v 0.09719 0.09719 h -0.152295 -0.152294 z" id="path31" /><path style="fill:#4d4d4d;fill-opacity:1;stroke:none;stroke-width:0.780001;stroke-linecap:round;stroke-linejoin:round;stroke-dasharray:none;stroke-opacity:1" d="m 88.483649,62.869045 v -0.223962 h 0.11646 0.116461 v 0.223962 0.223961 h -0.116461 -0.11646 z" id="path32" /></g></g></svg>';

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

procedure PanelTickCallback(user_data: Pointer); cdecl;
begin
  if Assigned(user_data) then
    TShellBottomPanel(user_data).Tick();
end;

// -----------------------------------------------------------------------------
// TShellBottomPanel Implementation
// -----------------------------------------------------------------------------

constructor TShellBottomPanel.Create(ALauncher: TShellLauncher);
begin
  inherited Create();
  GBottomPanelInstance := Self;
  FLauncher := ALauncher;
  FIsVisible := False;
  FShowingDesktop := False;
  FPanelHeight := 38;
  FLastClockSec := -1;
  FLastActiveWin := 0;
  FLastTaskSignature := '';
  FActiveWindow := 0;

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
  SetLength(FWindowIconCache, 0);

  // Drive the panel from a timer, not the frame loop.
  //
  // Everything in Tick() is slow-changing: the clock needs 1 Hz, the task list
  // needs to refresh when the active window changes, and the volume applet polls
  // only while its popup is open. None of that needs 60 Hz, and asking for it
  // meant 60 wake-ups a second to discover ~59 no-ops.
  //
  // A timer costs wake-ups at its own rate: the loop blocks between frames when
  // there is nothing to animate, so an idle shell now sleeps instead of polling.
  // ft_set_timer is optional, so fall back to the old tick if the loaded libft
  // predates it.
  if FtIsLibLoaded() then
  begin
    if Assigned(ft_set_timer) then
      ft_set_timer(PANEL_TIMER_MS, @PanelTickCallback, Self)
    else if Assigned(ft_set_tick_callback) then
      ft_set_tick_callback(@PanelTickCallback, Self);
  end;
end;

destructor TShellBottomPanel.Destroy();
var
  i: Integer;
begin
  if GBottomPanelInstance = Self then
    GBottomPanelInstance := nil;

  if FtIsLibLoaded() then
  begin
    if Assigned(ft_set_timer) then
      ft_set_timer(0, nil, nil)
    else if Assigned(ft_set_tick_callback) then
      ft_set_tick_callback(nil, nil);
  end;

  for i := 0 to High(FTasks) do
  begin
    if Assigned(FTasks[i].Button) then
    begin
      if Assigned(FTasks[i].Menu) then
        FTasks[i].Button.ContextMenuHandle := nil;
      FTasks[i].Button.Free();
      FTasks[i].Button := nil;
    end;
    if Assigned(FTasks[i].Menu) then
    begin
      FTasks[i].Menu.Free();
      FTasks[i].Menu := nil;
    end;
  end;
  SetLength(FTasks, 0);

  for i := 0 to High(FWindowIconCache) do
  begin
    if Assigned(FWindowIconCache[i].Bitmap) then
    begin
      FWindowIconCache[i].Bitmap.Free();
      FWindowIconCache[i].Bitmap := nil;
    end;
  end;
  SetLength(FWindowIconCache, 0);

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

procedure TShellBottomPanel.HandleLauncherButtonClick(Sender: TFtButton);
begin
  OnLauncherClicked();
end;

procedure TShellBottomPanel.HandleShowDesktopButtonClick(Sender: TFtButton);
begin
  ToggleShowDesktop();
end;

procedure TShellBottomPanel.HandleTaskButtonClick(Sender: TFtButton);
begin
  if Assigned(Sender) and (Sender.Tag <> 0) then
    OnTaskClicked(Cardinal(Sender.Tag));
end;

// Builds the per-task context menu.
//
// One menu per task rather than one shared menu: the toolkit pops a widget's own
// ContextMenu and gives no hook before it opens, and OnPress only fires for the
// left button, so a shared menu would have no way to learn which task was
// right-clicked. The cost is one native popup window per task, created lazily
// here and freed with the task.
procedure TShellBottomPanel.BuildTaskMenu(var ATask: TTaskItem);
var
  it: TFtMenuItem;
begin
  if ATask.Window = 0 then Exit;
  if Assigned(ATask.Menu) then Exit;
  if not FtIsLibLoaded() then Exit;

  ATask.Menu := TFtPopupMenu.Create(FWindow);
  if ATask.Menu = nil then Exit;

  ATask.MenuMinimize := ATask.Menu.AddItem('Minimize', @HandleTaskMenuMinimize);
  ATask.MenuMaximize := ATask.Menu.AddItem('Maximize', @HandleTaskMenuMaximize);
  ATask.Menu.AddSeparator();
  ATask.MenuClose := ATask.Menu.AddItem('Close', @HandleTaskMenuClose);

  // Every item carries the window id, so one handler shape serves all tasks and
  // the callbacks need no shared mutable state.
  it := ATask.MenuMinimize;
  if it <> nil then it.Tag := Int64(ATask.Window);
  it := ATask.MenuMaximize;
  if it <> nil then it.Tag := Int64(ATask.Window);
  it := ATask.MenuClose;
  if it <> nil then it.Tag := Int64(ATask.Window);

  UpdateTaskMenuState(ATask);
end;

procedure TShellBottomPanel.UpdateTaskMenuState(var ATask: TTaskItem);
begin
  if not Assigned(ATask.Menu) then Exit;

  // Captions reflect current state, the way MATE and KDE do it, so the user is
  // never offered an action that would do nothing.
  //
  // Note: TFtMenuItem.Enabled blocks the click but the toolkit paints enabled and
  // disabled items identically, so a disabled "Minimize" would look clickable and
  // silently do nothing. Toggling the caption avoids that entirely.
  if Assigned(ATask.MenuMinimize) then
  begin
    if ATask.IsMinimized then
      ATask.MenuMinimize.Caption := 'Restore'
    else
      ATask.MenuMinimize.Caption := 'Minimize';
  end;

  if Assigned(ATask.MenuMaximize) then
  begin
    if ATask.IsMaximized then
      ATask.MenuMaximize.Caption := 'Restore'
    else
      ATask.MenuMaximize.Caption := 'Maximize';
  end;
end;

procedure TShellBottomPanel.HandleTaskMenuMinimize(Sender: TFtMenuItem);
var
  win: Cardinal;
begin
  if not Assigned(Sender) then Exit;
  win := Cardinal(Sender.Tag);
  // Re-read the state rather than trusting the cached flag: the window may have
  // been minimized or restored since the menu was built.
  if IsWindowMinimized(win) then
  begin
    UnminimizeWindow(win);
    ActivateWindow(win);
  end
  else
    MinimizeWindow(win);
end;

procedure TShellBottomPanel.HandleTaskMenuMaximize(Sender: TFtMenuItem);
var
  win: Cardinal;
begin
  if not Assigned(Sender) then Exit;
  win := Cardinal(Sender.Tag);
  // Toggle rather than trusting the cached flag: the window may have been
  // maximized or restored by its own titlebar since the menu was built.
  if IsWindowMaximized(win) then
    RestoreWindow(win)
  else
    MaximizeWindow(win);
end;

procedure TShellBottomPanel.HandleTaskMenuClose(Sender: TFtMenuItem);
begin
  if Assigned(Sender) then
    CloseWindow(Cardinal(Sender.Tag));
end;

procedure TShellBottomPanel.HandleTrayLayoutChanged(Sender: TObject);
begin
  LayoutButtons();
end;

procedure TShellBottomPanel.InitAtoms();
begin
  if FConn = nil then Exit;

  FAtomNetClientList         := InternAtom(FConn, '_NET_CLIENT_LIST');
  FAtomNetActiveWindow       := InternAtom(FConn, '_NET_ACTIVE_WINDOW');
  FAtomNetWmName             := InternAtom(FConn, '_NET_WM_NAME');
  FAtomNetWmIcon             := InternAtom(FConn, '_NET_WM_ICON');
  FAtomNetWmState            := InternAtom(FConn, '_NET_WM_STATE');
  FAtomNetWmStateHidden      := InternAtom(FConn, '_NET_WM_STATE_HIDDEN');
  FAtomNetWmStateMaxVert     := InternAtom(FConn, '_NET_WM_STATE_MAXIMIZED_VERT');
  FAtomNetWmStateMaxHorz     := InternAtom(FConn, '_NET_WM_STATE_MAXIMIZED_HORZ');
  FAtomNetCloseWindow        := InternAtom(FConn, '_NET_CLOSE_WINDOW');
  FAtomNetWmStateSkipTaskbar := InternAtom(FConn, '_NET_WM_STATE_SKIP_TASKBAR');
  FAtomNetWmWindowType       := InternAtom(FConn, '_NET_WM_WINDOW_TYPE');
  FAtomNetWmWindowTypeDock   := InternAtom(FConn, '_NET_WM_WINDOW_TYPE_DOCK');
  FAtomNetWmWindowTypeDesk   := InternAtom(FConn, '_NET_WM_WINDOW_TYPE_DESKTOP');
  FAtomNetWmWindowTypeSplash := InternAtom(FConn, '_NET_WM_WINDOW_TYPE_SPLASH');
  FAtomNetWmWindowTypeUtil   := InternAtom(FConn, '_NET_WM_WINDOW_TYPE_UTILITY');
  FAtomNetWmWindowTypeTool   := InternAtom(FConn, '_NET_WM_WINDOW_TYPE_TOOLBAR');
  FAtomNetWmWindowTypeMenu   := InternAtom(FConn, '_NET_WM_WINDOW_TYPE_MENU');
  FAtomNetWmWindowTypeTip    := InternAtom(FConn, '_NET_WM_WINDOW_TYPE_TOOLTIP');
  FAtomNetShowingDesktop     := InternAtom(FConn, '_NET_SHOWING_DESKTOP');
  FAtomUtf8String            := InternAtom(FConn, 'UTF8_STRING');
  FAtomWMChangeState         := InternAtom(FConn, 'WM_CHANGE_STATE');
  FAtomWMName                := InternAtom(FConn, 'WM_NAME');
  FAtomWMClass               := InternAtom(FConn, 'WM_CLASS');
end;

procedure TShellBottomPanel.SetupWindow();
var
  py: Integer;
begin
  if not FtIsLibLoaded() then Exit;

  py := PanelY();
  FWindow := TFtWindow.Create(FPanelWidth, FPanelHeight, 'shellsama-bottom-panel');
  if FWindow = nil then Exit;

  FWindow.WindowType := ftwtDock;
  FWindow.Borderless := True;
  FWindow.SkipTaskbar := True;
  FWindow.SetPosition(0, py);

  // Reserve bottom screen space via _NET_WM_STRUT & _NET_WM_STRUT_PARTIAL
  FWindow.SetStrutPartial(
    0, 0, 0, FPanelHeight,
    0, 0, 0, 0, 0, 0,
    0, FPanelWidth - 1
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

  // 3. Power / Session Applet
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
  RefreshTasks();
end;

function TShellBottomPanel.PanelX(): Integer;
begin
  Result := 0;
end;

function TShellBottomPanel.PanelY(): Integer;
var
  sh: Integer;
begin
  if FtIsLibLoaded() and Assigned(ft_screen_get_height) then
    sh := FtApp().ScreenHeight
  else
    sh := 1080;
  Result := sh - FPanelHeight;
end;

function TShellBottomPanel.PanelWidth(): Integer;
begin
  Result := FPanelWidth;
end;

function TShellBottomPanel.PanelHeight(): Integer;
begin
  Result := FPanelHeight;
end;

function TShellBottomPanel.GetTaskCount(): Integer;
begin
  Result := Length(FTasks);
end;

function TShellBottomPanel.GetIconCacheCount(): Integer;
begin
  Result := Length(FWindowIconCache);
end;

function TShellBottomPanel.GetTaskIcon(AIndex: Integer): TFtBitmap;
begin
  Result := nil;
  if (AIndex >= 0) and (AIndex < Length(FTasks)) then
    Result := GetOrLoadWindowIcon(FTasks[AIndex].Window, 18);
end;

procedure TShellBottomPanel.Show();
begin
  if FWindow = nil then Exit;
  FWindow.Show();
  FIsVisible := True;
  RefreshTasks();
  UpdateClock();
end;

procedure TShellBottomPanel.Hide();
begin
  if FWindow = nil then Exit;
  FWindow.Hide();
  FIsVisible := False;
end;

function TShellBottomPanel.QueryClientList(): TWindowIdArray;
var
  cookie: xcb_get_property_cookie_t;
  reply: Pxcb_get_property_reply_t;
  len, i: Integer;
  pWins: Pxcb_window_t;
begin
  SetLength(Result, 0);
  if (FConn = nil) or (FRootWindow = 0) or (FAtomNetClientList = 0) then Exit;

  cookie := xcb_get_property(FConn, 0, FRootWindow, FAtomNetClientList, XCB_ATOM_WINDOW, 0, 1024);
  reply := xcb_get_property_reply(FConn, cookie, nil);
  if reply = nil then Exit;

  try
    len := xcb_get_property_value_length(reply) div SizeOf(xcb_window_t);
    if len > 0 then
    begin
      pWins := Pxcb_window_t(xcb_get_property_value(reply));
      SetLength(Result, len);
      for i := 0 to len - 1 do
        Result[i] := pWins[i];
    end;
  finally
    c_free(reply);
  end;
end;

function TShellBottomPanel.QueryActiveWindow(): Cardinal;
var
  cookie: xcb_get_property_cookie_t;
  reply: Pxcb_get_property_reply_t;
begin
  Result := 0;
  if (FConn = nil) or (FRootWindow = 0) or (FAtomNetActiveWindow = 0) then Exit;

  cookie := xcb_get_property(FConn, 0, FRootWindow, FAtomNetActiveWindow, XCB_ATOM_WINDOW, 0, 1);
  reply := xcb_get_property_reply(FConn, cookie, nil);
  if reply = nil then Exit;

  try
    if xcb_get_property_value_length(reply) >= SizeOf(xcb_window_t) then
      Result := Pxcb_window_t(xcb_get_property_value(reply))^;
  finally
    c_free(reply);
  end;
end;

function TShellBottomPanel.QueryWindowTitle(AWin: Cardinal): string;
var
  cookie: xcb_get_property_cookie_t;
  reply: Pxcb_get_property_reply_t;
  len: Integer;
  pStr: PChar;
begin
  Result := '';
  if (FConn = nil) or (AWin = 0) then Exit;

  // 1. Try _NET_WM_NAME (UTF8_STRING)
  if (FAtomNetWmName <> 0) and (FAtomUtf8String <> 0) then
  begin
    cookie := xcb_get_property(FConn, 0, AWin, FAtomNetWmName, FAtomUtf8String, 0, 256);
    reply := xcb_get_property_reply(FConn, cookie, nil);
    if reply <> nil then
    begin
      try
        len := xcb_get_property_value_length(reply);
        if len > 0 then
        begin
          pStr := PChar(xcb_get_property_value(reply));
          SetString(Result, pStr, len);
          Exit;
        end;
      finally
        c_free(reply);
      end;
    end;
  end;

  // 2. Fallback to WM_NAME (STRING)
  if FAtomWMName <> 0 then
  begin
    cookie := xcb_get_property(FConn, 0, AWin, FAtomWMName, XCB_ATOM_STRING, 0, 256);
    reply := xcb_get_property_reply(FConn, cookie, nil);
    if reply <> nil then
    begin
      try
        len := xcb_get_property_value_length(reply);
        if len > 0 then
        begin
          pStr := PChar(xcb_get_property_value(reply));
          SetString(Result, pStr, len);
        end;
      finally
        c_free(reply);
      end;
    end;
  end;
end;

function TShellBottomPanel.QueryWindowIcon(AWin: Cardinal; APreferredSize: Integer = 18): TFtBitmap;
var
  cookie: xcb_get_property_cookie_t;
  reply: Pxcb_get_property_reply_t;
  pData: PCardinal;
  valLen, numCards, offset, w, h, iconLen: Integer;
  bestW, bestH, bestOffset: Integer;
  candFound: Boolean;
  rawBmp: TFtBitmap;
  resName, resClass, iconPath: string;
  pStr, pNext: PChar;
  strLen: Integer;
  desktopApp: TDesktopApp;
begin
  Result := nil;
  if not FtIsLibLoaded() then Exit;

  // 1. Try _NET_WM_ICON
  if (FConn <> nil) and (AWin <> 0) and (FAtomNetWmIcon <> 0) then
  begin
    cookie := xcb_get_property(FConn, 0, AWin, FAtomNetWmIcon, XCB_ATOM_CARDINAL, 0, 131072);
    reply := xcb_get_property_reply(FConn, cookie, nil);
    if reply <> nil then
    begin
      try
        valLen := xcb_get_property_value_length(reply);
        numCards := valLen div SizeOf(Cardinal);
        if numCards >= 2 then
        begin
          pData := PCardinal(xcb_get_property_value(reply));
          offset := 0;
          candFound := False;
          bestW := 0;
          bestH := 0;
          bestOffset := 0;

          while offset + 2 <= numCards do
          begin
            w := Integer(pData[offset]);
            h := Integer(pData[offset + 1]);
            if (w <= 0) or (h <= 0) or (w > 1024) or (h > 1024) then Break;
            iconLen := w * h;
            if (offset + 2 + iconLen > numCards) or (iconLen < 0) then Break;

            if (w = APreferredSize) and (h = APreferredSize) then
            begin
              candFound := True;
              bestW := w;
              bestH := h;
              bestOffset := offset;
              Break;
            end;

            if not candFound then
            begin
              candFound := True;
              bestW := w;
              bestH := h;
              bestOffset := offset;
            end
            else if bestW < APreferredSize then
            begin
              if (w >= APreferredSize) or (w > bestW) then
              begin
                bestW := w;
                bestH := h;
                bestOffset := offset;
              end;
            end
            else
            begin
              if (w >= APreferredSize) and (w < bestW) then
              begin
                bestW := w;
                bestH := h;
                bestOffset := offset;
              end;
            end;

            Inc(offset, 2 + iconLen);
          end;

          if candFound and (bestW > 0) and (bestH > 0) then
          begin
            try
              rawBmp := TFtBitmap.CreateFromBGRA(@pData[bestOffset + 2], bestW, bestH);
              if Assigned(rawBmp) then
              begin
                if (bestW = APreferredSize) and (bestH = APreferredSize) then
                  Result := rawBmp
                else
                begin
                  Result := rawBmp.CreateScaled(APreferredSize, APreferredSize);
                  rawBmp.Free();
                end;
              end;
            except
              Result := nil;
            end;
            if Result <> nil then Exit;
          end;
        end;
      finally
        c_free(reply);
      end;
    end;
  end;

  // 2. Try WM_CLASS match to desktop apps / pixmaps
  if (FConn <> nil) and (AWin <> 0) then
  begin
    cookie := xcb_get_property(FConn, 0, AWin, XCB_ATOM_WM_CLASS, XCB_ATOM_STRING, 0, 256);
    reply := xcb_get_property_reply(FConn, cookie, nil);
    if reply <> nil then
    begin
      try
        strLen := xcb_get_property_value_length(reply);
        if strLen > 0 then
        begin
          pStr := PChar(xcb_get_property_value(reply));
          resName := StrPas(pStr);
          resClass := '';
          pNext := pStr + Length(resName) + 1;
          if (pNext - pStr) < strLen then
            resClass := StrPas(pNext);

          // A. Match against TDesktopAppList
          if Assigned(FLauncher) and Assigned(FLauncher.AppList) then
          begin
            if FLauncher.AppList.FindAppByClass(resName, resClass, desktopApp) then
            begin
              if desktopApp.Icon <> '' then
              begin
                iconPath := ResolveIconPath(desktopApp.Icon, APreferredSize);
                if iconPath <> '' then
                  Result := LoadIconBitmap(iconPath, APreferredSize, APreferredSize);
              end;
            end;
          end;

          // B. Direct name resolution from resName
          if (Result = nil) and (resName <> '') then
          begin
            iconPath := ResolveIconPath(LowerCase(resName), APreferredSize);
            if iconPath <> '' then
              Result := LoadIconBitmap(iconPath, APreferredSize, APreferredSize);
          end;

          // C. Direct name resolution from resClass
          if (Result = nil) and (resClass <> '') then
          begin
            iconPath := ResolveIconPath(LowerCase(resClass), APreferredSize);
            if iconPath <> '' then
              Result := LoadIconBitmap(iconPath, APreferredSize, APreferredSize);
          end;
        end;
      finally
        c_free(reply);
      end;
    end;
  end;

  // 3. Fallback generic window icon
  if Result = nil then
    Result := CreateFallbackIcon(APreferredSize, APreferredSize);
end;

function TShellBottomPanel.GetOrLoadWindowIcon(AWin: Cardinal; APreferredSize: Integer = 18): TFtBitmap;
var
  i: Integer;
begin
  Result := nil;
  if AWin = 0 then Exit;

  for i := 0 to High(FWindowIconCache) do
  begin
    if FWindowIconCache[i].Window = AWin then
    begin
      Result := FWindowIconCache[i].Bitmap;
      Exit;
    end;
  end;

  Result := QueryWindowIcon(AWin, APreferredSize);
  SetLength(FWindowIconCache, Length(FWindowIconCache) + 1);
  FWindowIconCache[High(FWindowIconCache)].Window := AWin;
  FWindowIconCache[High(FWindowIconCache)].Bitmap := Result;
end;

function TShellBottomPanel.ShouldShowTask(AWin: Cardinal): Boolean;
var
  cookie: xcb_get_property_cookie_t;
  reply: Pxcb_get_property_reply_t;
  atoms: Pxcb_atom_t;
  count, i: Integer;
begin
  if (FConn = nil) or (AWin = 0) then Exit(False);

  // 1. Exclude self panel window
  if Assigned(FWindow) and (AWin = Cardinal(PtrUInt(FWindow.NativeHandle))) then
    Exit(False);

  // 2. Exclude launcher window if active
  if Assigned(FLauncher) and Assigned(FLauncher.Window) and
     (AWin = Cardinal(PtrUInt(FLauncher.Window.NativeHandle))) then
    Exit(False);

  // 3. Check _NET_WM_STATE for _NET_WM_STATE_SKIP_TASKBAR
  if (FAtomNetWmState <> 0) and (FAtomNetWmStateSkipTaskbar <> 0) then
  begin
    cookie := xcb_get_property(FConn, 0, AWin, FAtomNetWmState, XCB_ATOM_ATOM, 0, 64);
    reply := xcb_get_property_reply(FConn, cookie, nil);
    if reply <> nil then
    begin
      count := xcb_get_property_value_length(reply) div SizeOf(xcb_atom_t);
      if count > 0 then
      begin
        atoms := Pxcb_atom_t(xcb_get_property_value(reply));
        for i := 0 to count - 1 do
        begin
          if atoms[i] = FAtomNetWmStateSkipTaskbar then
          begin
            c_free(reply);
            Exit(False);
          end;
        end;
      end;
      c_free(reply);
    end;
  end;

  // 4. Check _NET_WM_WINDOW_TYPE (ignore docks, desktop, splash, utilities, toolbars, menus, tooltips)
  if FAtomNetWmWindowType <> 0 then
  begin
    cookie := xcb_get_property(FConn, 0, AWin, FAtomNetWmWindowType, XCB_ATOM_ATOM, 0, 16);
    reply := xcb_get_property_reply(FConn, cookie, nil);
    if reply <> nil then
    begin
      count := xcb_get_property_value_length(reply) div SizeOf(xcb_atom_t);
      if count > 0 then
      begin
        atoms := Pxcb_atom_t(xcb_get_property_value(reply));
        for i := 0 to count - 1 do
        begin
          if (atoms[i] = FAtomNetWmWindowTypeDock) or
             (atoms[i] = FAtomNetWmWindowTypeDesk) or
             (atoms[i] = FAtomNetWmWindowTypeSplash) or
             (atoms[i] = FAtomNetWmWindowTypeUtil) or
             (atoms[i] = FAtomNetWmWindowTypeTool) or
             (atoms[i] = FAtomNetWmWindowTypeMenu) or
             (atoms[i] = FAtomNetWmWindowTypeTip) then
          begin
            c_free(reply);
            Exit(False);
          end;
        end;
      end;
      c_free(reply);
    end;
  end;

  Result := True;
end;

function TShellBottomPanel.IsWindowMinimized(AWin: Cardinal): Boolean;
var
  cookie: xcb_get_property_cookie_t;
  reply: Pxcb_get_property_reply_t;
  atoms: Pxcb_atom_t;
  count, i: Integer;
begin
  Result := False;
  if (FConn = nil) or (AWin = 0) or (FAtomNetWmState = 0) or (FAtomNetWmStateHidden = 0) then Exit;

  cookie := xcb_get_property(FConn, 0, AWin, FAtomNetWmState, XCB_ATOM_ATOM, 0, 64);
  reply := xcb_get_property_reply(FConn, cookie, nil);
  if reply = nil then Exit;

  try
    count := xcb_get_property_value_length(reply) div SizeOf(xcb_atom_t);
    if count > 0 then
    begin
      atoms := Pxcb_atom_t(xcb_get_property_value(reply));
      for i := 0 to count - 1 do
      begin
        if atoms[i] = FAtomNetWmStateHidden then
          Exit(True);
      end;
    end;
  finally
    c_free(reply);
  end;
end;

function TShellBottomPanel.IsWindowMaximized(AWin: Cardinal): Boolean;
var
  cookie: xcb_get_property_cookie_t;
  reply: Pxcb_get_property_reply_t;
  atoms: Pxcb_atom_t;
  count, i: Integer;
begin
  Result := False;
  if (FConn = nil) or (AWin = 0) or (FAtomNetWmState = 0) then Exit;
  if (FAtomNetWmStateMaxVert = 0) and (FAtomNetWmStateMaxHorz = 0) then Exit;

  cookie := xcb_get_property(FConn, 0, AWin, FAtomNetWmState, XCB_ATOM_ATOM, 0, 64);
  reply := xcb_get_property_reply(FConn, cookie, nil);
  if reply = nil then Exit;

  try
    count := xcb_get_property_value_length(reply) div SizeOf(xcb_atom_t);
    if count > 0 then
    begin
      atoms := Pxcb_atom_t(xcb_get_property_value(reply));
      for i := 0 to count - 1 do
      begin
        // Either axis counts as maximized for menu purposes: the WM sets both,
        // and a half-maximized window should still offer "Restore".
        if (atoms[i] = FAtomNetWmStateMaxVert) or (atoms[i] = FAtomNetWmStateMaxHorz) then
          Exit(True);
      end;
    end;
  finally
    c_free(reply);
  end;
end;

procedure TShellBottomPanel.RefreshTasks();
var
  rawWins: array of Cardinal;
  validWins: array of Cardinal;
  i, j: Integer;
  title: string;
  found: Boolean;
  oldTasks: array of TTaskItem;
begin
  rawWins := QueryClientList();
  FActiveWindow := QueryActiveWindow();

  // Filter windows eligible for taskbar
  SetLength(validWins, 0);
  for i := 0 to High(rawWins) do
  begin
    if ShouldShowTask(rawWins[i]) then
    begin
      SetLength(validWins, Length(validWins) + 1);
      validWins[High(validWins)] := rawWins[i];
    end;
  end;

  // Preserve existing task items if matching
  oldTasks := Copy(FTasks);
  SetLength(FTasks, Length(validWins));

  for i := 0 to High(validWins) do
  begin
    FTasks[i].Window := validWins[i];
    FTasks[i].IsActive := (validWins[i] = FActiveWindow);
    FTasks[i].IsMinimized := IsWindowMinimized(validWins[i]);
    FTasks[i].IsMaximized := IsWindowMaximized(validWins[i]);

    // Check if previously existed
    found := False;
    for j := 0 to High(oldTasks) do
    begin
      if oldTasks[j].Window = validWins[i] then
      begin
        FTasks[i].Title := oldTasks[j].Title;
        FTasks[i].Button := oldTasks[j].Button;
        FTasks[i].Menu := oldTasks[j].Menu;
        FTasks[i].MenuMinimize := oldTasks[j].MenuMinimize;
        FTasks[i].MenuMaximize := oldTasks[j].MenuMaximize;
        FTasks[i].MenuClose := oldTasks[j].MenuClose;
        oldTasks[j].Button := nil; // transfer ownership
        oldTasks[j].Menu := nil;
        found := True;
        Break;
      end;
    end;

    title := QueryWindowTitle(validWins[i]);
    if title = '' then
      title := 'Window ' + IntToStr(validWins[i]);
    FTasks[i].Title := title;

    if not found then
    begin
      // SetLength reuses the array, so an overwritten slot still holds the old
      // record's pointers. Clear them or the panel would free a menu twice.
      FTasks[i].Button := nil;
      FTasks[i].Menu := nil;
      FTasks[i].MenuMinimize := nil;
      FTasks[i].MenuMaximize := nil;
      FTasks[i].MenuClose := nil;
    end;
  end;

  // Destroy remaining unused buttons
  for j := 0 to High(oldTasks) do
  begin
    if Assigned(oldTasks[j].Button) then
    begin
      // Detach before freeing: the button holds a raw pointer to the menu and
      // must not outlive it.
      if Assigned(oldTasks[j].Menu) then
        oldTasks[j].Button.ContextMenuHandle := nil;
      oldTasks[j].Button.Free();
      oldTasks[j].Button := nil;
    end;
    if Assigned(oldTasks[j].Menu) then
    begin
      oldTasks[j].Menu.Free();
      oldTasks[j].Menu := nil;
    end;
  end;

  // Evict stale entries from icon cache
  i := 0;
  while i < Length(FWindowIconCache) do
  begin
    found := False;
    for j := 0 to High(validWins) do
    begin
      if validWins[j] = FWindowIconCache[i].Window then
      begin
        found := True;
        Break;
      end;
    end;
    if not found then
    begin
      if Assigned(FWindowIconCache[i].Bitmap) then
        FWindowIconCache[i].Bitmap.Free();
      for j := i to Length(FWindowIconCache) - 2 do
        FWindowIconCache[j] := FWindowIconCache[j + 1];
      SetLength(FWindowIconCache, Length(FWindowIconCache) - 1);
    end
    else
      Inc(i);
  end;

  // Every task gets a context menu, and its captions are refreshed here so a
  // window maximized via its own titlebar is still offered "Restore".
  for i := 0 to High(FTasks) do
  begin
    BuildTaskMenu(FTasks[i]);
    UpdateTaskMenuState(FTasks[i]);
  end;

  LayoutButtons();
end;

procedure TShellBottomPanel.LayoutButtons();
var
  startX, endX, availW, numTasks: Integer;
  trayW, trayX: Integer;
  btnW, btnX, i: Integer;
  dispTitle: string;
  iconBmp: TFtBitmap;
begin
  if FWindow = nil then Exit;

  startX := 122;

  // Calculate dynamic endX based on System Tray and Applets
  if Assigned(FTray) then
  begin
    trayW := FTray.Width;
    trayX := (FPanelWidth - 212) - trayW;
    FTray.SetPosition(trayX, (FPanelHeight - FTray.IconSize) div 2);
    endX := trayX - 8;
  end
  else
    endX := FPanelWidth - 212;

  availW := Max(100, endX - startX);
  numTasks := Length(FTasks);

  if numTasks = 0 then
  begin
    // Nothing to lay out, but the area still has to be repainted: the last task's
    // button was just freed and its pixels would otherwise stay on screen.
    if FWindow <> nil then
      FWindow.Invalidate();
    Exit;
  end;

  btnW := Min(160, Max(70, (availW - (numTasks - 1) * 4) div numTasks));

  for i := 0 to numTasks - 1 do
  begin
    btnX := startX + i * (btnW + 4);
    dispTitle := FTasks[i].Title;
    if Length(dispTitle) > 22 then
      dispTitle := Copy(dispTitle, 1, 20) + '..';

    iconBmp := GetOrLoadWindowIcon(FTasks[i].Window, 18);

    if FTasks[i].Button = nil then
    begin
      FTasks[i].Button := TFtButton.Create(FWindow, btnX, 3, btnW, 32, dispTitle);
      FTasks[i].Button.IsToggle := True;
      FTasks[i].Button.CornerRadius := 6.0;
      FTasks[i].Button.Alignment := ftaLeft;
      FTasks[i].Button.PaddingX := 8.0;
      FTasks[i].Button.Tag := PtrInt(FTasks[i].Window);
      FTasks[i].Button.OnClick := @HandleTaskButtonClick;
    end
    else
    begin
      FTasks[i].Button.SetBounds(btnX, 3, btnW, 32);
      FTasks[i].Button.Caption := dispTitle;
      FTasks[i].Button.Alignment := ftaLeft;
      FTasks[i].Button.PaddingX := 8.0;
    end;

    // Right-click on the task button opens its context menu. The toolkit walks up
    // from the hit widget to find this, so it must be attached to the button.
    if Assigned(FTasks[i].Menu) then
      FTasks[i].Button.ContextMenuHandle := FTasks[i].Menu.Handle;

    if Assigned(iconBmp) then
    begin
      FTasks[i].Button.SetIconBitmap(iconBmp, False);
      FTasks[i].Button.SetIconSize(18, 18);
      FTasks[i].Button.IconGap := 6;
    end
    else
      FTasks[i].Button.ClearIcon();

    FTasks[i].Button.Toggled := FTasks[i].IsActive;
  end;

  // Repaint the task area explicitly.
  //
  // Freeing a task button does not invalidate the panel: the button is gone before
  // the parent is asked to redraw, so its pixels stay on screen as a ghost. With
  // several tasks closing at once the whole strip ends up showing dead buttons.
  if FWindow <> nil then
    FWindow.Invalidate();
end;

procedure TShellBottomPanel.UpdateClock();
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

procedure TShellBottomPanel.Tick();
var
  curActive: Cardinal;
  sig: AnsiString;
begin
  UpdateClock();

  if Assigned(FVolumeApplet) then
    FVolumeApplet.Tick();

  // Sync launcher button toggled state
  if Assigned(FLauncherBtn) and Assigned(FLauncher) then
    FLauncherBtn.Toggled := FLauncher.IsVisible;

  // Refresh when EITHER the active window changes OR the set of windows changes.
  //
  // Watching only the active window (the original behaviour) left the taskbar
  // stale whenever a window that was not active disappeared: its button stayed,
  // pointing at a dead window id. Closing a window from the task menu made that
  // very visible - the button remained and clicking it did nothing.
  sig := TaskSetSignature();
  if sig <> FLastTaskSignature then
  begin
    FLastTaskSignature := sig;
    FLastActiveWin := QueryActiveWindow();
    RefreshTasks();
    Exit;
  end;

  curActive := QueryActiveWindow();
  if curActive <> FLastActiveWin then
  begin
    FLastActiveWin := curActive;
    RefreshTasks();
  end;
end;

// Identity of the current task set, cheap enough to compute every tick.
//
// Built from the window ids only: titles and states change far more often than
// the set itself, and those are handled by RefreshTasks' own state refresh.
function TShellBottomPanel.TaskSetSignature(): AnsiString;
var
  wins: array of Cardinal;
  i: Integer;
begin
  wins := QueryClientList();
  Result := '';
  for i := 0 to High(wins) do
  begin
    if not ShouldShowTask(wins[i]) then Continue;
    Result := Result + IntToHex(QWord(wins[i]), 8) + ',';
  end;
end;

procedure TShellBottomPanel.OnLauncherClicked();
begin
  if Assigned(FLauncher) then
  begin
    FLauncher.Toggle();
    if Assigned(FLauncherBtn) then
      FLauncherBtn.Toggled := FLauncher.IsVisible;
  end;
end;

procedure TShellBottomPanel.OnTaskClicked(AWin: Cardinal);
begin
  if AWin = 0 then Exit;

  if AWin = QueryActiveWindow() then
  begin
    // Active window clicked -> minimize it
    MinimizeWindow(AWin);
  end
  else
  begin
    // Inactive or minimized window clicked -> activate it
    ActivateWindow(AWin);
  end;
  RefreshTasks();
end;

procedure TShellBottomPanel.ActivateWindow(AWin: Cardinal);
var
  ev: xcb_client_message_event_t;
  data32: PCardinalArray;
begin
  if (FConn = nil) or (AWin = 0) or (FAtomNetActiveWindow = 0) then Exit;

  FillChar(ev, SizeOf(ev), 0);
  ev.response_type := XCB_CLIENT_MESSAGE;
  ev.format := 32;
  ev.window := AWin;
  ev.type_ := FAtomNetActiveWindow;
  data32 := PCardinalArray(@ev.data.raw[0]);
  data32^[0] := 1; // 1 = application request
  data32^[1] := XCB_CURRENT_TIME;

  xcb_send_event(FConn, 0, FRootWindow,
                 XCB_EVENT_MASK_SUBSTRUCTURE_REDIRECT or XCB_EVENT_MASK_SUBSTRUCTURE_NOTIFY,
                 PAnsiChar(@ev));
  xcb_flush(FConn);
end;

procedure TShellBottomPanel.MinimizeWindow(AWin: Cardinal);
var
  ev: xcb_client_message_event_t;
  data32: PCardinalArray;
begin
  if (FConn = nil) or (AWin = 0) then Exit;

  // 1. Send EWMH _NET_WM_STATE add _NET_WM_STATE_HIDDEN
  if (FAtomNetWmState <> 0) and (FAtomNetWmStateHidden <> 0) then
  begin
    FillChar(ev, SizeOf(ev), 0);
    ev.response_type := XCB_CLIENT_MESSAGE;
    ev.format := 32;
    ev.window := AWin;
    ev.type_ := FAtomNetWmState;
    data32 := PCardinalArray(@ev.data.raw[0]);
    data32^[0] := 1; // _NET_WM_STATE_ADD
    data32^[1] := FAtomNetWmStateHidden;
    data32^[2] := 0;
    data32^[3] := 1; // application
    xcb_send_event(FConn, 0, FRootWindow,
                   XCB_EVENT_MASK_SUBSTRUCTURE_REDIRECT or XCB_EVENT_MASK_SUBSTRUCTURE_NOTIFY,
                   PAnsiChar(@ev));
  end;

  // 2. Also send ICCCM WM_CHANGE_STATE IconicState (3)
  if FAtomWMChangeState <> 0 then
  begin
    FillChar(ev, SizeOf(ev), 0);
    ev.response_type := XCB_CLIENT_MESSAGE;
    ev.format := 32;
    ev.window := AWin;
    ev.type_ := FAtomWMChangeState;
    data32 := PCardinalArray(@ev.data.raw[0]);
    data32^[0] := 3; // IconicState
    xcb_send_event(FConn, 0, FRootWindow,
                   XCB_EVENT_MASK_SUBSTRUCTURE_REDIRECT or XCB_EVENT_MASK_SUBSTRUCTURE_NOTIFY,
                   PAnsiChar(@ev));
  end;

  xcb_flush(FConn);
end;

procedure TShellBottomPanel.UnminimizeWindow(AWin: Cardinal);
var
  ev: xcb_client_message_event_t;
  data32: PCardinalArray;
begin
  if (FConn = nil) or (AWin = 0) or (FAtomNetWmState = 0) or (FAtomNetWmStateHidden = 0) then Exit;

  // _NET_WM_STATE_REMOVE of _NET_WM_STATE_HIDDEN. The WM maps the window and
  // clears the flag; the caller also activates, because unminimizing alone does
  // not raise or focus on every window manager.
  FillChar(ev, SizeOf(ev), 0);
  ev.response_type := XCB_CLIENT_MESSAGE;
  ev.format := 32;
  ev.window := AWin;
  ev.type_ := FAtomNetWmState;
  data32 := PCardinalArray(@ev.data.raw[0]);
  data32^[0] := 0; // _NET_WM_STATE_REMOVE
  data32^[1] := FAtomNetWmStateHidden;
  data32^[2] := 0;
  data32^[3] := 2; // source indication: pager
  xcb_send_event(FConn, 0, FRootWindow,
                 XCB_EVENT_MASK_SUBSTRUCTURE_REDIRECT or XCB_EVENT_MASK_SUBSTRUCTURE_NOTIFY,
                 PAnsiChar(@ev));
  xcb_flush(FConn);
end;

procedure TShellBottomPanel.MaximizeWindow(AWin: Cardinal);
var
  ev: xcb_client_message_event_t;
  data32: PCardinalArray;
begin
  if (FConn = nil) or (AWin = 0) or (FAtomNetWmState = 0) then Exit;

  // _NET_WM_STATE_ADD with both maximized atoms. The WM only checks that either
  // atom appears in the property list, so one message is enough.
  FillChar(ev, SizeOf(ev), 0);
  ev.response_type := XCB_CLIENT_MESSAGE;
  ev.format := 32;
  ev.window := AWin;
  ev.type_ := FAtomNetWmState;
  data32 := PCardinalArray(@ev.data.raw[0]);
  data32^[0] := 1; // _NET_WM_STATE_ADD
  data32^[1] := FAtomNetWmStateMaxVert;
  data32^[2] := FAtomNetWmStateMaxHorz;
  data32^[3] := 2; // source indication: pager
  xcb_send_event(FConn, 0, FRootWindow,
                 XCB_EVENT_MASK_SUBSTRUCTURE_REDIRECT or XCB_EVENT_MASK_SUBSTRUCTURE_NOTIFY,
                 PAnsiChar(@ev));
  xcb_flush(FConn);
end;

procedure TShellBottomPanel.RestoreWindow(AWin: Cardinal);
var
  ev: xcb_client_message_event_t;
  data32: PCardinalArray;
begin
  if (FConn = nil) or (AWin = 0) or (FAtomNetWmState = 0) then Exit;

  FillChar(ev, SizeOf(ev), 0);
  ev.response_type := XCB_CLIENT_MESSAGE;
  ev.format := 32;
  ev.window := AWin;
  ev.type_ := FAtomNetWmState;
  data32 := PCardinalArray(@ev.data.raw[0]);
  data32^[0] := 0; // _NET_WM_STATE_REMOVE
  data32^[1] := FAtomNetWmStateMaxVert;
  data32^[2] := FAtomNetWmStateMaxHorz;
  data32^[3] := 2;
  xcb_send_event(FConn, 0, FRootWindow,
                 XCB_EVENT_MASK_SUBSTRUCTURE_REDIRECT or XCB_EVENT_MASK_SUBSTRUCTURE_NOTIFY,
                 PAnsiChar(@ev));
  xcb_flush(FConn);
end;

procedure TShellBottomPanel.CloseWindow(AWin: Cardinal);
var
  ev: xcb_client_message_event_t;
  data32: PCardinalArray;
begin
  if (FConn = nil) or (AWin = 0) or (FAtomNetCloseWindow = 0) then Exit;

  // _NET_CLOSE_WINDOW asks the WM to close the window politely, which lets the
  // application prompt about unsaved work. Deliberately not xcb_kill_client:
  // that would terminate the connection and lose the user's data.
  FillChar(ev, SizeOf(ev), 0);
  ev.response_type := XCB_CLIENT_MESSAGE;
  ev.format := 32;
  ev.window := AWin;
  ev.type_ := FAtomNetCloseWindow;
  data32 := PCardinalArray(@ev.data.raw[0]);
  data32^[0] := 2; // source indication: pager
  data32^[1] := XCB_CURRENT_TIME;
  xcb_send_event(FConn, 0, FRootWindow,
                 XCB_EVENT_MASK_SUBSTRUCTURE_REDIRECT or XCB_EVENT_MASK_SUBSTRUCTURE_NOTIFY,
                 PAnsiChar(@ev));
  xcb_flush(FConn);
end;

procedure TShellBottomPanel.ToggleShowDesktop();
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
