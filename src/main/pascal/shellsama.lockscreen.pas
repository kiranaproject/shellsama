unit ShellSama.LockScreen;

// ShellSama.LockScreen
// ====================
// Fullscreen session lock screen and authentication surface for Samarinda Desktop.
// Implements shield curtain (clock/date) and authentication card states with PAM verification.

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  SysUtils, Classes, Math, DateUtils, BaseUnix, ctypes,
  Floria.XCB, Floria.XCB.Keysyms, Floria.X11.KeySym,
  ftpas.api, ftpas.types, ftpas, ftpas.controls, ftpas.creative, ftpas.canvas,
  ftpas.font, ftpas.widget,
  ShellSama.Settings, ShellSama.PAM;

const
  LOCK_CARD_WIDTH    = 380;
  LOCK_CARD_HEIGHT   = 300;
  LOCK_CARD_RADIUS   = 16.0;
  LOCK_SHAKE_MS      = 400;

type
  TShellLockScreenState = (lssShield, lssAuth);

  TShellLockScreen = class
  protected
    FWindow           : TFtWindow;
    FDrawingArea      : TFtDrawingArea;
    FPasswordEntry    : TFtEntry;
    FUnlockButton     : TFtButton;
    FCancelButton     : TFtButton;
    FSuspendButton    : TFtButton;
    FRestartButton    : TFtButton;
    FShutDownButton   : TFtButton;

    FState            : TShellLockScreenState;
    FIsLocked         : Boolean;
    FStandaloneMode   : Boolean;
    FWallpaperBitmap  : TFtBitmap;
    FWallpaperPath    : string;

    FUserName         : string;
    FUserFullName     : string;
    FErrorMessage     : string;
    FCapsLockActive   : Boolean;
    FAuthBusy         : Boolean;

    FShaking          : Boolean;
    FShakeOffset      : Integer;
    FShakeStartMs     : QWord;
    FLastClockSec     : Integer;

    FWidth            : Integer;
    FHeight           : Integer;

    FClockFont        : TFtFontRef;
    FDateFont         : TFtFontRef;
    FUserFont         : TFtFontRef;
    FHintFont         : TFtFontRef;

    FGrabAcquired     : Boolean;

    procedure SetupUI(); virtual;
    procedure UpdateControlPositions(); virtual;
    procedure HandlePaint(Sender: TFtDrawingArea; Canvas: TFtCanvas); virtual;
    procedure HandleDrawingAreaMouseDown(Sender: TFtDrawingArea; X, Y, Button: Integer); virtual;
    procedure HandleWindowKey(Sender: TFtWindow; AKey: LongWord; AIsDown: Boolean); virtual;
    procedure HandlePasswordSubmit(Sender: TFtWidget; const AText: string); virtual;
    procedure HandleUnlockClick(Sender: TFtButton); virtual;
    procedure HandleCancelClick(Sender: TFtButton); virtual;
    procedure HandleSuspendClick(Sender: TFtButton); virtual;
    procedure HandleRestartClick(Sender: TFtButton); virtual;
    procedure HandleShutDownClick(Sender: TFtButton); virtual;

    function  TryAcquireGrab(): Boolean; virtual;
    procedure ReleaseGrab(); virtual;
    procedure RefreshUserInfo(); virtual;
    procedure LoadWallpaper(); virtual;
    procedure SetWindowProperties(); virtual;
  public
    constructor Create(AStandalone: Boolean = False);
    destructor Destroy(); override;

    procedure Lock(); virtual;
    procedure Unlock(); virtual;
    procedure SetState(AState: TShellLockScreenState); virtual;
    procedure StartShake(); virtual;
    procedure DoAuthenticate(); virtual;
    procedure Tick(); virtual;

    property Window: TFtWindow read FWindow;
    property State: TShellLockScreenState read FState write SetState;
    property IsLocked: Boolean read FIsLocked;
    property StandaloneMode: Boolean read FStandaloneMode write FStandaloneMode;
    property PasswordEntry: TFtEntry read FPasswordEntry;
    property ErrorMessage: string read FErrorMessage write FErrorMessage;
    property CapsLockActive: Boolean read FCapsLockActive;
    property UserName: string read FUserName;
    property UserFullName: string read FUserFullName;
    property GrabAcquired: Boolean read FGrabAcquired;
  end;

function GlobalLockScreen(): TShellLockScreen;
procedure InitGlobalLockScreen(AStandalone: Boolean = False);
procedure FreeGlobalLockScreen();
function GetCurrentUserName(): string;
function GetCurrentUserFullName(): string;

implementation

type
  PPasswd = ^TPasswd;
  TPasswd = record
    pw_name   : PChar;
    pw_passwd : PChar;
    pw_uid    : cuint;
    pw_gid    : cuint;
    pw_gecos  : PChar;
    pw_dir    : PChar;
    pw_shell  : PChar;
  end;

function getpwuid(uid: cuint): PPasswd; cdecl; external 'c' name 'getpwuid';
function getuid(): cuint; cdecl; external 'c' name 'getuid';
function libc_system(cmd: PChar): cint; cdecl; external 'c' name 'system';
procedure c_free(p: Pointer); cdecl; external 'c' name 'free';

var
  GGlobalLockScreen: TShellLockScreen = nil;

function GlobalLockScreen(): TShellLockScreen;
begin
  Result := GGlobalLockScreen;
end;

procedure InitGlobalLockScreen(AStandalone: Boolean = False);
begin
  if GGlobalLockScreen = nil then
    GGlobalLockScreen := TShellLockScreen.Create(AStandalone);
end;

procedure FreeGlobalLockScreen();
begin
  if Assigned(GGlobalLockScreen) then
  begin
    GGlobalLockScreen.Free();
    GGlobalLockScreen := nil;
  end;
end;

procedure LockScreenTickCallback(AUserData: Pointer); cdecl;
begin
  if Assigned(AUserData) then
    TShellLockScreen(AUserData).Tick();
end;

function GetCurrentUserName(): string;
var
  pw: PPasswd;
begin
  pw := getpwuid(getuid());
  if (pw <> nil) and (pw^.pw_name <> nil) and (pw^.pw_name[0] <> #0) then
    Result := string(pw^.pw_name)
  else
    Result := GetEnvironmentVariable('USER');
  if Result = '' then
    Result := 'user';
end;

function GetCurrentUserFullName(): string;
var
  pw: PPasswd;
  gecos: string;
  commaPos: Integer;
begin
  pw := getpwuid(getuid());
  if (pw <> nil) and (pw^.pw_gecos <> nil) and (pw^.pw_gecos[0] <> #0) then
  begin
    gecos := string(pw^.pw_gecos);
    commaPos := Pos(',', gecos);
    if commaPos > 0 then
      gecos := Copy(gecos, 1, commaPos - 1);
    gecos := Trim(gecos);
    if gecos <> '' then
      Exit(gecos);
  end;
  Result := GetEnvironmentVariable('USER');
  if Result = '' then
    Result := 'User';
end;

// -----------------------------------------------------------------------------
// TShellLockScreen Implementation
// -----------------------------------------------------------------------------

constructor TShellLockScreen.Create(AStandalone: Boolean = False);
begin
  inherited Create();
  FStandaloneMode := AStandalone;
  FIsLocked := False;
  FState := lssShield;
  FWallpaperBitmap := nil;
  FWallpaperPath := '';
  FErrorMessage := '';
  FCapsLockActive := False;
  FAuthBusy := False;
  FShaking := False;
  FShakeOffset := 0;
  FShakeStartMs := 0;
  FLastClockSec := -1;
  FGrabAcquired := False;

  if FtIsLibLoaded() and Assigned(ft_screen_get_width) then
  begin
    FWidth := FtApp().ScreenWidth;
    FHeight := FtApp().ScreenHeight;
  end
  else
  begin
    FWidth := 1920;
    FHeight := 1080;
  end;

  RefreshUserInfo();
  SetupUI();
end;

destructor TShellLockScreen.Destroy();
begin
  if FIsLocked then
    ReleaseGrab();

  if FStandaloneMode and FtIsLibLoaded() and Assigned(ft_set_timer) then
    ft_set_timer(0, nil, nil);

  if Assigned(FWallpaperBitmap) then
  begin
    FWallpaperBitmap.Free();
    FWallpaperBitmap := nil;
  end;

  if Assigned(FClockFont) then
    FClockFont.Free();
  if Assigned(FDateFont) then
    FDateFont.Free();
  if Assigned(FUserFont) then
    FUserFont.Free();
  if Assigned(FHintFont) then
    FHintFont.Free();

  if Assigned(FPasswordEntry) then
    FPasswordEntry.Free();
  if Assigned(FUnlockButton) then
    FUnlockButton.Free();
  if Assigned(FCancelButton) then
    FCancelButton.Free();
  if Assigned(FSuspendButton) then
    FSuspendButton.Free();
  if Assigned(FRestartButton) then
    FRestartButton.Free();
  if Assigned(FShutDownButton) then
    FShutDownButton.Free();
  if Assigned(FDrawingArea) then
    FDrawingArea.Free();
  if Assigned(FWindow) then
    FWindow.Free();

  inherited Destroy();
end;

procedure TShellLockScreen.RefreshUserInfo();
begin
  FUserName := GetCurrentUserName();
  FUserFullName := GetCurrentUserFullName();
end;

procedure TShellLockScreen.SetupUI();
begin
  if not FtIsLibLoaded() then Exit;

  FWindow := TFtWindow.Create(FWidth, FHeight, 'shellsama-lockscreen');
  if FWindow = nil then Exit;

  FWindow.Borderless := True;
  FWindow.SkipTaskbar := True;
  FWindow.WindowType := ftwtNormal;
  FWindow.SetPosition(0, 0);
  FWindow.OnKey := @HandleWindowKey;

  // Background surface
  FDrawingArea := TFtDrawingArea.Create(FWindow, 0, 0, FWidth, FHeight);
  FDrawingArea.Cursor := ftcDefault;
  FDrawingArea.OnPaint := @HandlePaint;
  FDrawingArea.OnMouseDown := @HandleDrawingAreaMouseDown;

  // Masked password entry
  FPasswordEntry := TFtEntry.Create(FWindow, 0, 0, 100, 36, '');
  FPasswordEntry.Placeholder := 'Password';
  FPasswordEntry.IsPassword := True;
  FPasswordEntry.CornerRadius := 8.0;
  FPasswordEntry.OnSubmit := @HandlePasswordSubmit;
  FPasswordEntry.Visible := False;

  // Action buttons
  FUnlockButton := TFtButton.Create(FWindow, 0, 0, 38, 36, '→');
  FUnlockButton.CornerRadius := 8.0;
  FUnlockButton.OnClick := @HandleUnlockClick;
  FUnlockButton.Visible := False;

  FCancelButton := TFtButton.Create(FWindow, 0, 0, 100, 32, 'Cancel');
  FCancelButton.CornerRadius := 6.0;
  FCancelButton.OnClick := @HandleCancelClick;
  FCancelButton.Visible := False;

  // Top-right power controls
  FSuspendButton := TFtButton.Create(FWindow, FWidth - 130, 14, 34, 34, '⏾');
  FSuspendButton.CornerRadius := 6.0;
  FSuspendButton.OnClick := @HandleSuspendClick;

  FRestartButton := TFtButton.Create(FWindow, FWidth - 90, 14, 34, 34, '⟳');
  FRestartButton.CornerRadius := 6.0;
  FRestartButton.OnClick := @HandleRestartClick;

  FShutDownButton := TFtButton.Create(FWindow, FWidth - 50, 14, 34, 34, '⏻');
  FShutDownButton.CornerRadius := 6.0;
  FShutDownButton.OnClick := @HandleShutDownClick;

  // Fonts
  FClockFont := TFtFontRef.Create('Sans 72');
  FDateFont := TFtFontRef.Create('Sans 18');
  FUserFont := TFtFontRef.Create('Sans Bold 16');
  FHintFont := TFtFontRef.Create('Sans 12');

  UpdateControlPositions();
end;

procedure TShellLockScreen.SetWindowProperties();
var
  conn: Pxcb_connection_t;
  winHandle: xcb_window_t;
  atomNetWmState, atomNetWmStateAbove, atomNetWmStateFs: xcb_atom_t;
  cookie: xcb_intern_atom_cookie_t;
  reply: Pxcb_intern_atom_reply_t;
  stateAtoms: array[0..1] of xcb_atom_t;
begin
  if (FWindow = nil) or not FtIsLibLoaded() then Exit;

  winHandle := xcb_window_t(PtrUInt(FWindow.NativeHandle));
  conn := Pxcb_connection_t(ft_backend_get_connection());
  if (winHandle = 0) or (conn = nil) then Exit;

  // Intern _NET_WM_STATE
  cookie := xcb_intern_atom(conn, 0, Length('_NET_WM_STATE'), '_NET_WM_STATE');
  reply := xcb_intern_atom_reply(conn, cookie, nil);
  if reply <> nil then
  begin
    atomNetWmState := reply^.atom;
    c_free(reply);
  end
  else
    atomNetWmState := 0;

  // Intern _NET_WM_STATE_ABOVE
  cookie := xcb_intern_atom(conn, 0, Length('_NET_WM_STATE_ABOVE'), '_NET_WM_STATE_ABOVE');
  reply := xcb_intern_atom_reply(conn, cookie, nil);
  if reply <> nil then
  begin
    atomNetWmStateAbove := reply^.atom;
    c_free(reply);
  end
  else
    atomNetWmStateAbove := 0;

  // Intern _NET_WM_STATE_FULLSCREEN
  cookie := xcb_intern_atom(conn, 0, Length('_NET_WM_STATE_FULLSCREEN'), '_NET_WM_STATE_FULLSCREEN');
  reply := xcb_intern_atom_reply(conn, cookie, nil);
  if reply <> nil then
  begin
    atomNetWmStateFs := reply^.atom;
    c_free(reply);
  end
  else
    atomNetWmStateFs := 0;

  if atomNetWmState <> 0 then
  begin
    stateAtoms[0] := atomNetWmStateAbove;
    stateAtoms[1] := atomNetWmStateFs;
    xcb_change_property(conn, XCB_PROP_MODE_REPLACE, winHandle,
                        atomNetWmState, XCB_ATOM_ATOM, 32, 2, @stateAtoms[0]);
    xcb_flush(conn);
  end;
end;

procedure TShellLockScreen.LoadWallpaper();
var
  wpPath: string;
begin
  wpPath := ShellSettings().WallpaperPath;
  if (wpPath <> FWallpaperPath) or (FWallpaperBitmap = nil) then
  begin
    if Assigned(FWallpaperBitmap) then
    begin
      FWallpaperBitmap.Free();
      FWallpaperBitmap := nil;
    end;

    if (wpPath <> '') and FileExists(wpPath) then
    begin
      try
        FWallpaperBitmap := TFtBitmap.CreateFromFile(wpPath);
        FWallpaperPath := wpPath;
      except
        FWallpaperBitmap := nil;
        FWallpaperPath := '';
      end;
    end
    else
      FWallpaperPath := '';
  end;
end;

procedure TShellLockScreen.UpdateControlPositions();
var
  cardX, cardY, cardW, cardH: Integer;
begin
  cardW := LOCK_CARD_WIDTH;
  cardH := LOCK_CARD_HEIGHT;
  cardX := ((FWidth - cardW) div 2) + FShakeOffset;
  cardY := (FHeight - cardH) div 2;

  if Assigned(FPasswordEntry) then
    FPasswordEntry.SetBounds(cardX + 36, cardY + 144, cardW - 72 - 44, 36);

  if Assigned(FUnlockButton) then
    FUnlockButton.SetBounds(cardX + cardW - 36 - 38, cardY + 144, 38, 36);

  if Assigned(FCancelButton) then
    FCancelButton.SetBounds(cardX + (cardW - 100) div 2, cardY + 242, 100, 32);

  if Assigned(FSuspendButton) then
    FSuspendButton.SetBounds(FWidth - 130, 14, 34, 34);

  if Assigned(FRestartButton) then
    FRestartButton.SetBounds(FWidth - 90, 14, 34, 34);

  if Assigned(FShutDownButton) then
    FShutDownButton.SetBounds(FWidth - 50, 14, 34, 34);
end;

function TShellLockScreen.TryAcquireGrab(): Boolean;
var
  mask: Word;
  cookie: xcb_grab_pointer_cookie_t;
  reply: Pxcb_grab_pointer_reply_t;
  err: Pxcb_generic_error_t;
  winHandle: xcb_window_t;
  conn: Pxcb_connection_t;
begin
  Result := False;
  if (FWindow = nil) or not FtIsLibLoaded() then Exit;

  winHandle := xcb_window_t(PtrUInt(FWindow.NativeHandle));
  conn := Pxcb_connection_t(ft_backend_get_connection());
  if (winHandle = 0) or (conn = nil) then Exit;

  mask := XCB_EVENT_MASK_BUTTON_PRESS or
          XCB_EVENT_MASK_BUTTON_RELEASE or
          XCB_EVENT_MASK_POINTER_MOTION;

  err := nil;
  cookie := xcb_grab_pointer(conn, 1, winHandle, mask,
                             XCB_GRAB_MODE_ASYNC, XCB_GRAB_MODE_ASYNC, 0, 0,
                             XCB_CURRENT_TIME);
  reply := xcb_grab_pointer_reply(conn, cookie, @err);
  if reply <> nil then
  begin
    Result := (reply^.status = 0);
    c_free(reply);
  end;
  if err <> nil then
    c_free(err);

  if Result then
  begin
    xcb_grab_keyboard(conn, 1, winHandle, XCB_CURRENT_TIME,
                      XCB_GRAB_MODE_ASYNC, XCB_GRAB_MODE_ASYNC);
    xcb_flush(conn);
    FGrabAcquired := True;
  end;
end;

procedure TShellLockScreen.ReleaseGrab();
var
  conn: Pxcb_connection_t;
begin
  if FGrabAcquired and FtIsLibLoaded() then
  begin
    conn := Pxcb_connection_t(ft_backend_get_connection());
    if conn <> nil then
    begin
      xcb_ungrab_pointer(conn, XCB_CURRENT_TIME);
      xcb_ungrab_keyboard(conn, XCB_CURRENT_TIME);
      xcb_flush(conn);
    end;
    FGrabAcquired := False;
  end;
end;

procedure TShellLockScreen.Lock();
begin
  if FWindow = nil then Exit;

  RefreshUserInfo();
  LoadWallpaper();
  SetState(lssShield);

  FErrorMessage := '';
  FShaking := False;
  FShakeOffset := 0;
  if Assigned(FPasswordEntry) then
    FPasswordEntry.Text := '';

  FWindow.Show();
  FWindow.BringToFront();
  SetWindowProperties();

  TryAcquireGrab();
  FIsLocked := True;

  if FStandaloneMode and Assigned(ft_set_timer) then
    ft_set_timer(16, @LockScreenTickCallback, Self);

  if Assigned(FDrawingArea) then
    FDrawingArea.Invalidate();
end;

procedure TShellLockScreen.Unlock();
begin
  ReleaseGrab();
  FIsLocked := False;

  if Assigned(FPasswordEntry) then
    FPasswordEntry.Text := '';
  FErrorMessage := '';

  if Assigned(FWindow) then
    FWindow.Hide();

  if FStandaloneMode then
  begin
    if Assigned(ft_set_timer) then
      ft_set_timer(0, nil, nil);
    if FtIsLibLoaded() then
      FtApp().Terminate();
  end;
end;

procedure TShellLockScreen.SetState(AState: TShellLockScreenState);
begin
  FState := AState;
  if FState = lssShield then
  begin
    if Assigned(FPasswordEntry) then
    begin
      FPasswordEntry.Visible := False;
      FPasswordEntry.Text := '';
    end;
    if Assigned(FUnlockButton) then
      FUnlockButton.Visible := False;
    if Assigned(FCancelButton) then
      FCancelButton.Visible := False;
    FErrorMessage := '';
  end
  else
  begin
    if Assigned(FPasswordEntry) then
    begin
      FPasswordEntry.Visible := True;
      FPasswordEntry.SetFocus();
    end;
    if Assigned(FUnlockButton) then
      FUnlockButton.Visible := True;
    if Assigned(FCancelButton) then
      FCancelButton.Visible := True;
  end;

  UpdateControlPositions();
  if Assigned(FDrawingArea) then
    FDrawingArea.Invalidate();
end;

procedure TShellLockScreen.StartShake();
begin
  FShaking := True;
  FShakeStartMs := GetTickCount64();
  FShakeOffset := 0;
end;

procedure TShellLockScreen.DoAuthenticate();
var
  pw: string;
  errMsg: string;
  ok: Boolean;
begin
  if FAuthBusy then Exit;
  if FPasswordEntry = nil then Exit;

  pw := FPasswordEntry.Text;
  if pw = '' then Exit;

  FAuthBusy := True;
  try
    errMsg := '';
    ok := PamAuth().Authenticate(FUserName, pw, errMsg);
    if ok then
    begin
      Unlock();
    end
    else
    begin
      if errMsg <> '' then
        FErrorMessage := errMsg
      else
        FErrorMessage := 'Authentication failed. Please try again.';
      FPasswordEntry.Text := '';
      StartShake();
      FPasswordEntry.SetFocus();
      if Assigned(FDrawingArea) then
        FDrawingArea.Invalidate();
    end;
  finally
    FAuthBusy := False;
  end;
end;

procedure TShellLockScreen.Tick();
var
  mods: Cardinal;
  caps: Boolean;
  elapsed: QWord;
  sec: Integer;
begin
  if not FIsLocked then Exit;

  // Retry grab if window was not viewable on initial show
  if not FGrabAcquired then
    TryAcquireGrab();

  // Monitor Caps Lock status
  if FtIsLibLoaded() then
  begin
    mods := FtApp().GetKeyboardModifiers();
    caps := (mods and XCB_KEY_BUT_MASK_LOCK) <> 0;
    if caps <> FCapsLockActive then
    begin
      FCapsLockActive := caps;
      if (FState = lssAuth) and Assigned(FDrawingArea) then
        FDrawingArea.Invalidate();
    end;
  end;

  // Clock updates in Shield mode
  if FState = lssShield then
  begin
    sec := SecondOf(Now);
    if sec <> FLastClockSec then
    begin
      FLastClockSec := sec;
      if Assigned(FDrawingArea) then
        FDrawingArea.Invalidate();
    end;
  end;

  // Shake animation processing
  if FShaking then
  begin
    elapsed := GetTickCount64() - FShakeStartMs;
    if elapsed < LOCK_SHAKE_MS then
    begin
      FShakeOffset := Round(Sin(elapsed * 0.05) * 12.0 * (1.0 - (elapsed / LOCK_SHAKE_MS)));
      UpdateControlPositions();
      if Assigned(FDrawingArea) then
        FDrawingArea.Invalidate();
    end
    else
    begin
      FShaking := False;
      FShakeOffset := 0;
      UpdateControlPositions();
      if Assigned(FDrawingArea) then
        FDrawingArea.Invalidate();
    end;
  end;
end;

// -----------------------------------------------------------------------------
// Paint & Event Callbacks
// -----------------------------------------------------------------------------

procedure TShellLockScreen.HandlePaint(Sender: TFtDrawingArea; Canvas: TFtCanvas);
var
  sw, sh, bw, bh: Integer;
  scale: Double;
  dw, dh, dx, dy: Integer;
  timeStr, dateStr, hintStr, initialChar: string;
  cardX, cardY, cardW, cardH: Integer;
  cardRad: Double;
  avatarX, avatarY: Integer;
begin
  if Canvas = nil then Exit;
  sw := FWidth;
  sh := FHeight;

  // 1. Draw base solid backdrop (#1e1e2e)
  Canvas.DrawRect(0, 0, sw, sh, 30 / 255, 30 / 255, 46 / 255, 1.0);

  // 2. Draw wallpaper if loaded
  if FWallpaperBitmap <> nil then
  begin
    bw := FWallpaperBitmap.Width;
    bh := FWallpaperBitmap.Height;
    if (bw > 0) and (bh > 0) then
    begin
      scale := Max(sw / bw, sh / bh);
      dw := Round(bw * scale);
      dh := Round(bh * scale);
      dx := (sw - dw) div 2;
      dy := (sh - dh) div 2;
      Canvas.DrawImageScaled(dx, dy, dw, dh, FWallpaperBitmap, 1.0);
      // Dark acrylic tint scrim
      Canvas.DrawRect(0, 0, sw, sh, 15 / 255, 15 / 255, 25 / 255, 0.45);
    end;
  end
  else
  begin
    // Ambient fallback accents
    Canvas.DrawCircle(sw div 2, sh div 2, Min(sw, sh) div 3, 40 / 255, 42 / 255, 62 / 255, 0.45);
    Canvas.DrawCircle(sw div 2, sh div 2, Min(sw, sh) div 5, 48 / 255, 52 / 255, 78 / 255, 0.35);
  end;

  // 3. Render Shield state
  if FState = lssShield then
  begin
    if SameText(ShellSettings().ClockFormat, '12h') then
      timeStr := FormatDateTime('h:nn am/pm', Now)
    else
      timeStr := FormatDateTime('hh:nn', Now);

    dateStr := FormatDateTime('dddd, mmmm d', Now);
    hintStr := 'Press any key or click to unlock';

    if Assigned(FClockFont) then
      Canvas.DrawTextCentered(0, (sh div 3) - 70, sw, 80, timeStr, 1.0, 1.0, 1.0, FClockFont.Handle);

    if Assigned(FDateFont) then
      Canvas.DrawTextCentered(0, (sh div 3) + 20, sw, 30, dateStr, 0.85, 0.88, 0.95, FDateFont.Handle);

    if Assigned(FHintFont) then
      Canvas.DrawTextCentered(0, sh - 110, sw, 24, hintStr, 0.70, 0.75, 0.82, FHintFont.Handle);
  end
  // 4. Render Auth state
  else
  begin
    cardW := LOCK_CARD_WIDTH;
    cardH := LOCK_CARD_HEIGHT;
    cardX := ((sw - cardW) div 2) + FShakeOffset;
    cardY := (sh - cardH) div 2;
    cardRad := LOCK_CARD_RADIUS;

    // Ambient drop shadow
    Canvas.DrawShadow(cardX, cardY, cardW, cardH, cardRad, 0, 8, 28, 0, 0, 0, 0.50);
    // Frosted card plate
    Canvas.DrawRoundedRect(cardX, cardY, cardW, cardH, cardRad, 24 / 255, 25 / 255, 38 / 255, 0.94);
    // Outline border
    Canvas.DrawRoundedRectOutline(cardX, cardY, cardW, cardH, cardRad, 1.2, 69 / 255, 71 / 255, 90 / 255, 0.75);

    // User Avatar Circle
    avatarX := cardX + (cardW div 2);
    avatarY := cardY + 54;
    Canvas.DrawCircle(avatarX, avatarY, 32, 137 / 255, 180 / 255, 250 / 255, 0.85);
    Canvas.DrawCircle(avatarX, avatarY, 30, 49 / 255, 50 / 255, 68 / 255, 1.0);

    // Avatar Initial
    initialChar := UpperCase(Copy(FUserName, 1, 1));
    if initialChar = '' then initialChar := 'U';
    if Assigned(FUserFont) then
      Canvas.DrawTextCentered(avatarX - 20, avatarY - 14, 40, 28, initialChar, 0.95, 0.95, 0.98, FUserFont.Handle);

    // User Display Name
    if Assigned(FUserFont) then
      Canvas.DrawTextCentered(cardX + 20, cardY + 95, cardW - 40, 24, FUserFullName, 0.95, 0.95, 0.98, FUserFont.Handle);

    // Caps Lock indicator
    if FCapsLockActive and Assigned(FHintFont) then
      Canvas.DrawTextCentered(cardX + 20, cardY + 188, cardW - 40, 18, '⇪ Caps Lock is on', 0.96, 0.78, 0.35, FHintFont.Handle);

    // Error message indicator
    if (FErrorMessage <> '') and Assigned(FHintFont) then
      Canvas.DrawTextCentered(cardX + 20, cardY + 208, cardW - 40, 18, FErrorMessage, 0.96, 0.40, 0.40, FHintFont.Handle);
  end;
end;

procedure TShellLockScreen.HandleDrawingAreaMouseDown(Sender: TFtDrawingArea; X, Y, Button: Integer);
var
  cardX, cardY, cardW, cardH: Integer;
begin
  if Button <> 1 then Exit;

  if FState = lssShield then
  begin
    SetState(lssAuth);
  end
  else
  begin
    cardW := LOCK_CARD_WIDTH;
    cardH := LOCK_CARD_HEIGHT;
    cardX := ((FWidth - cardW) div 2) + FShakeOffset;
    cardY := (FHeight - cardH) div 2;

    // Clicking outside auth card transitions back to shield mode
    if (X < cardX) or (X >= cardX + cardW) or (Y < cardY) or (Y >= cardY + cardH) then
      SetState(lssShield);
  end;
end;

procedure TShellLockScreen.HandleWindowKey(Sender: TFtWindow; AKey: LongWord; AIsDown: Boolean);
begin
  if not AIsDown then Exit;

  if FState = lssShield then
  begin
    // Filter modifier keys
    if (AKey = XK_Shift_L) or (AKey = XK_Shift_R) or
       (AKey = XK_Control_L) or (AKey = XK_Control_R) or
       (AKey = XK_Alt_L) or (AKey = XK_Alt_R) or
       (AKey = XK_Super_L) or (AKey = XK_Super_R) or
       (AKey = XK_Caps_Lock) or (AKey = XK_Num_Lock) then
      Exit;

    SetState(lssAuth);
    if (AKey >= 32) and (AKey <= 126) and Assigned(FPasswordEntry) then
    begin
      FPasswordEntry.Text := Chr(AKey);
      FPasswordEntry.SetFocus();
    end;
  end
  else
  begin
    if AKey = XK_Escape then
      SetState(lssShield)
    else if (AKey = XK_Return) or (AKey = XK_KP_Enter) then
      DoAuthenticate();
  end;
end;

procedure TShellLockScreen.HandlePasswordSubmit(Sender: TFtWidget; const AText: string);
begin
  DoAuthenticate();
end;

procedure TShellLockScreen.HandleUnlockClick(Sender: TFtButton);
begin
  DoAuthenticate();
end;

procedure TShellLockScreen.HandleCancelClick(Sender: TFtButton);
begin
  SetState(lssShield);
end;

procedure TShellLockScreen.HandleSuspendClick(Sender: TFtButton);
begin
  libc_system('systemctl suspend &');
end;

procedure TShellLockScreen.HandleRestartClick(Sender: TFtButton);
begin
  libc_system('systemctl reboot &');
end;

procedure TShellLockScreen.HandleShutDownClick(Sender: TFtButton);
begin
  libc_system('systemctl poweroff &');
end;

end.
