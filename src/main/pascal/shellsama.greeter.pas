unit ShellSama.Greeter;

// ShellSama.Greeter
// =================
// Pre-session login greeter for Samarinda Desktop Environment.
// Provides user selection, X11 desktop session selection, and dual-mode
// authentication (LightDM client when available, native PAM fallback).

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  SysUtils, Classes, Math, DateUtils, BaseUnix, ctypes,
  Floria.XCB, Floria.XCB.Keysyms, Floria.X11.KeySym,
  ftpas.api, ftpas.types, ftpas, ftpas.controls, ftpas.creative, ftpas.canvas,
  ftpas.font, ftpas.widget, ftpas.menus,
  ShellSama.Settings, ShellSama.PAM, ShellSama.LockScreen, ShellSama.LightDM;

const
  GREETER_CARD_WIDTH  = 400;
  GREETER_CARD_HEIGHT = 330;

type
  TShellGreeter = class(TShellLockScreen)
  private
    FUsers              : TLightDMUserArray;
    FSessions           : TLightDMSessionArray;
    FSelectedUserIndex  : Integer;
    FSelectedSessionIdx : Integer;
    FTestMode           : Boolean;

    FSessionButton      : TFtButton;
    FSessionMenu        : TFtPopupMenu;
    FUserSwitchButton   : TFtButton;
    FUserMenu           : TFtPopupMenu;

    procedure EnumerateUsers();
    procedure EnumerateSessions();
    procedure HandleSessionButtonClick(Sender: TFtButton);
    procedure HandleSessionMenuItemClick(Sender: TFtMenuItem);
    procedure HandleUserSwitchClick(Sender: TFtButton);
    procedure HandleUserMenuItemClick(Sender: TFtMenuItem);
    function  GetCurrentSessionKey(): string;
    function  GetCurrentSessionName(): string;
    procedure LaunchSession(const ASessionKey: string);
  protected
    procedure SetupUI(); override;
    procedure UpdateControlPositions(); override;
    procedure HandlePaint(Sender: TFtDrawingArea; Canvas: TFtCanvas); override;
    procedure RefreshUserInfo(); override;
    procedure DoAuthenticate(); override;
  public
    constructor Create(AStandalone: Boolean = True; ATestMode: Boolean = False);
    destructor Destroy(); override;

    property TestMode: Boolean read FTestMode write FTestMode;
    property SelectedUserIndex: Integer read FSelectedUserIndex write FSelectedUserIndex;
    property SelectedSessionIndex: Integer read FSelectedSessionIdx write FSelectedSessionIdx;
    property Users: TLightDMUserArray read FUsers;
    property Sessions: TLightDMSessionArray read FSessions;
  end;

function GlobalGreeter(): TShellGreeter;
procedure InitGlobalGreeter(ATestMode: Boolean = False);
procedure FreeGlobalGreeter();

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

function getpwent(): PPasswd; cdecl; external 'c' name 'getpwent';
procedure setpwent(); cdecl; external 'c' name 'setpwent';
procedure endpwent(); cdecl; external 'c' name 'endpwent';
function libc_system(cmd: PChar): cint; cdecl; external 'c' name 'system';

var
  GGlobalGreeter: TShellGreeter = nil;

function GlobalGreeter(): TShellGreeter;
begin
  Result := GGlobalGreeter;
end;

procedure InitGlobalGreeter(ATestMode: Boolean = False);
begin
  if GGlobalGreeter = nil then
    GGlobalGreeter := TShellGreeter.Create(True, ATestMode);
end;

procedure FreeGlobalGreeter();
begin
  if Assigned(GGlobalGreeter) then
  begin
    GGlobalGreeter.Free();
    GGlobalGreeter := nil;
  end;
end;

procedure EnumerateNativeSessions(out ASessions: TLightDMSessionArray);
var
  sr: TSearchRec;
  lines: TStringList;
  i: Integer;
  line, sName, sComment, key: string;
  count: Integer;
begin
  SetLength(ASessions, 0);
  count := 0;

  if FindFirst('/usr/share/xsessions/*.desktop', faAnyFile, sr) = 0 then
  begin
    lines := TStringList.Create();
    try
      repeat
        if (sr.Attr and faDirectory) = 0 then
        begin
          lines.Clear();
          try
            lines.LoadFromFile('/usr/share/xsessions/' + sr.Name);
            sName := '';
            sComment := '';
            key := ChangeFileExt(sr.Name, '');

            for i := 0 to lines.Count - 1 do
            begin
              line := Trim(lines[i]);
              if (sName = '') and (Pos('Name=', line) = 1) then
                sName := Copy(line, 6, Length(line))
              else if (sComment = '') and (Pos('Comment=', line) = 1) then
                sComment := Copy(line, 9, Length(line));
            end;

            if sName = '' then sName := key;
            Inc(count);
            SetLength(ASessions, count);
            ASessions[count - 1].Key := key;
            ASessions[count - 1].Name := sName;
            ASessions[count - 1].Comment := sComment;
          except
          end;
        end;
      until FindNext(sr) <> 0;
    finally
      FindClose(sr);
      lines.Free();
    end;
  end;

  if count = 0 then
  begin
    SetLength(ASessions, 1);
    ASessions[0].Key := 'default';
    ASessions[0].Name := 'Default Session';
    ASessions[0].Comment := 'Default system session';
  end;
end;

procedure EnumerateNativeUsers(out AUsers: TLightDMUserArray);
var
  pw: PPasswd;
  count: Integer;
  uName, gecos, realName, home: string;
  commaPos: Integer;
begin
  SetLength(AUsers, 0);
  count := 0;

  setpwent();
  try
    pw := getpwent();
    while pw <> nil do
    begin
      if (pw^.pw_uid >= 1000) and (pw^.pw_uid < 65000) and (string(pw^.pw_name) <> 'nobody') then
      begin
        uName := string(pw^.pw_name);
        home := string(pw^.pw_dir);
        realName := uName;
        if (pw^.pw_gecos <> nil) and (pw^.pw_gecos[0] <> #0) then
        begin
          gecos := string(pw^.pw_gecos);
          commaPos := Pos(',', gecos);
          if commaPos > 0 then
            gecos := Copy(gecos, 1, commaPos - 1);
          gecos := Trim(gecos);
          if gecos <> '' then
            realName := gecos;
        end;

        Inc(count);
        SetLength(AUsers, count);
        AUsers[count - 1].Name := uName;
        AUsers[count - 1].RealName := realName;
        if FileExists(home + '/.face') then
          AUsers[count - 1].ImagePath := home + '/.face'
        else if FileExists('/var/lib/AccountsService/icons/' + uName) then
          AUsers[count - 1].ImagePath := '/var/lib/AccountsService/icons/' + uName
        else
          AUsers[count - 1].ImagePath := '';
        AUsers[count - 1].Background := '';
        AUsers[count - 1].LoggedIn := False;
      end;
      pw := getpwent();
    end;
  finally
    endpwent();
  end;

  if count = 0 then
  begin
    SetLength(AUsers, 1);
    AUsers[0].Name := GetCurrentUserName();
    AUsers[0].RealName := GetCurrentUserFullName();
    AUsers[0].ImagePath := '';
    AUsers[0].Background := '';
    AUsers[0].LoggedIn := False;
  end;
end;

// -----------------------------------------------------------------------------
// TShellGreeter Implementation
// -----------------------------------------------------------------------------

constructor TShellGreeter.Create(AStandalone: Boolean = True; ATestMode: Boolean = False);
begin
  FTestMode := ATestMode;
  FSelectedUserIndex := 0;
  FSelectedSessionIdx := 0;

  // Initialize data structures prior to SetupUI
  EnumerateUsers();
  EnumerateSessions();

  inherited Create(AStandalone);

  // Apply user information from enumerated accounts
  if Length(FUsers) > 0 then
  begin
    FUserName := FUsers[0].Name;
    FUserFullName := FUsers[0].RealName;
  end;
end;

destructor TShellGreeter.Destroy();
begin
  if Assigned(FSessionMenu) then
  begin
    FSessionMenu.Free();
    FSessionMenu := nil;
  end;

  if Assigned(FUserMenu) then
  begin
    FUserMenu.Free();
    FUserMenu := nil;
  end;

  if Assigned(FSessionButton) then
  begin
    FSessionButton.Free();
    FSessionButton := nil;
  end;

  if Assigned(FUserSwitchButton) then
  begin
    FUserSwitchButton.Free();
    FUserSwitchButton := nil;
  end;

  inherited Destroy();
end;

procedure TShellGreeter.EnumerateUsers();
begin
  if LightDM().Available then
  begin
    FUsers := LightDM().GetUsers();
    if Length(FUsers) > 0 then Exit;
  end;

  EnumerateNativeUsers(FUsers);
end;

procedure TShellGreeter.EnumerateSessions();
var
  defHint: string;
  i: Integer;
begin
  if LightDM().Available then
  begin
    FSessions := LightDM().GetSessions();
    if Length(FSessions) > 0 then
    begin
      defHint := LightDM().DefaultSession;
      if defHint <> '' then
      begin
        for i := 0 to High(FSessions) do
          if SameText(FSessions[i].Key, defHint) then
          begin
            FSelectedSessionIdx := i;
            Break;
          end;
      end;
      Exit;
    end;
  end;

  EnumerateNativeSessions(FSessions);
end;

function TShellGreeter.GetCurrentSessionKey(): string;
begin
  if (FSelectedSessionIdx >= 0) and (FSelectedSessionIdx < Length(FSessions)) then
    Result := FSessions[FSelectedSessionIdx].Key
  else
    Result := 'default';
end;

function TShellGreeter.GetCurrentSessionName(): string;
begin
  if (FSelectedSessionIdx >= 0) and (FSelectedSessionIdx < Length(FSessions)) then
    Result := FSessions[FSelectedSessionIdx].Name
  else
    Result := 'Default';
end;

procedure TShellGreeter.SetupUI();
begin
  inherited SetupUI();
  if FWindow = nil then Exit;

  // Session selector pill button
  FSessionButton := TFtButton.Create(FWindow, 0, 0, 180, 28, '⚙ ' + GetCurrentSessionName() + ' ▾');
  FSessionButton.CornerRadius := 14.0;
  FSessionButton.Flat := True;
  FSessionButton.OnClick := @HandleSessionButtonClick;
  FSessionButton.Visible := False;

  // User switcher pill button
  FUserSwitchButton := TFtButton.Create(FWindow, 0, 0, 140, 26, '⇄ Switch User');
  FUserSwitchButton.CornerRadius := 13.0;
  FUserSwitchButton.Flat := True;
  FUserSwitchButton.OnClick := @HandleUserSwitchClick;
  FUserSwitchButton.Visible := False;

  UpdateControlPositions();
end;

procedure TShellGreeter.UpdateControlPositions();
var
  centerX, centerY, entryY: Integer;
begin
  inherited UpdateControlPositions();

  centerX := (FWidth div 2) + FShakeOffset;
  centerY := (FHeight div 2);
  entryY := centerY + 30;

  // Align session pill button below password input capsule
  if Assigned(FSessionButton) then
  begin
    FSessionButton.SetBounds(centerX - 90, entryY + 46, 180, 28);
    FSessionButton.Visible := (FState = lssAuth);
    FSessionButton.Caption := '⚙ ' + GetCurrentSessionName() + ' ▾';
  end;

  // Align user switcher button below session selector
  if Assigned(FUserSwitchButton) then
  begin
    FUserSwitchButton.SetBounds(centerX - 70, entryY + 80, 140, 26);
    FUserSwitchButton.Visible := (FState = lssAuth) and (Length(FUsers) > 1);
  end;

  if Assigned(FCancelButton) and (Length(FUsers) > 1) then
    FCancelButton.Visible := False;
end;

procedure TShellGreeter.HandleSessionButtonClick(Sender: TFtButton);
var
  i: Integer;
  item: TFtMenuItem;
begin
  if FSessionMenu <> nil then
    FSessionMenu.Free();

  FSessionMenu := TFtPopupMenu.Create(FWindow);
  for i := 0 to High(FSessions) do
  begin
    item := FSessionMenu.AddItem(FSessions[i].Name, @HandleSessionMenuItemClick);
    if item <> nil then
      item.Tag := i;
  end;

  if Assigned(FSessionButton) then
    FSessionMenu.Show(FSessionButton.X, FSessionButton.Y + FSessionButton.Height + 4);
end;

procedure TShellGreeter.HandleSessionMenuItemClick(Sender: TFtMenuItem);
begin
  if Sender = nil then Exit;
  FSelectedSessionIdx := Sender.Tag;
  if Assigned(FSessionButton) then
    FSessionButton.Caption := '⚙ ' + GetCurrentSessionName();
end;

procedure TShellGreeter.HandleUserSwitchClick(Sender: TFtButton);
var
  i: Integer;
  item: TFtMenuItem;
begin
  if FUserMenu <> nil then
    FUserMenu.Free();

  FUserMenu := TFtPopupMenu.Create(FWindow);
  for i := 0 to High(FUsers) do
  begin
    item := FUserMenu.AddItem(FUsers[i].RealName + ' (' + FUsers[i].Name + ')', @HandleUserMenuItemClick);
    if item <> nil then
      item.Tag := i;
  end;

  if Assigned(FUserSwitchButton) then
    FUserMenu.Show(FUserSwitchButton.X, FUserSwitchButton.Y + FUserSwitchButton.Height + 4);
end;

procedure TShellGreeter.HandleUserMenuItemClick(Sender: TFtMenuItem);
begin
  if Sender = nil then Exit;
  FSelectedUserIndex := Sender.Tag;
  if (FSelectedUserIndex >= 0) and (FSelectedUserIndex < Length(FUsers)) then
  begin
    FUserName := FUsers[FSelectedUserIndex].Name;
    FUserFullName := FUsers[FSelectedUserIndex].RealName;
    if Assigned(FPasswordEntry) then
    begin
      FPasswordEntry.Text := '';
      FPasswordEntry.SetFocus();
    end;
    if Assigned(FDrawingArea) then
      FDrawingArea.Invalidate();
  end;
end;

procedure TShellGreeter.HandlePaint(Sender: TFtDrawingArea; Canvas: TFtCanvas);
begin
  inherited HandlePaint(Sender, Canvas);
end;

procedure TShellGreeter.LaunchSession(const ASessionKey: string);
var
  sr: TSearchRec;
  lines: TStringList;
  i: Integer;
  line, execCmd: string;
begin
  execCmd := '';
  if FindFirst('/usr/share/xsessions/' + ASessionKey + '.desktop', faAnyFile, sr) = 0 then
  begin
    lines := TStringList.Create();
    try
      lines.LoadFromFile('/usr/share/xsessions/' + ASessionKey + '.desktop');
      for i := 0 to lines.Count - 1 do
      begin
        line := Trim(lines[i]);
        if Pos('Exec=', line) = 1 then
        begin
          execCmd := Copy(line, 6, Length(line));
          Break;
        end;
      end;
    finally
      FindClose(sr);
      lines.Free();
    end;
  end;

  if execCmd = '' then
    execCmd := 'x-session-manager || mate-session || shellsama';

  libc_system(PChar(execCmd + ' &'));
end;

procedure TShellGreeter.RefreshUserInfo();
begin
  if (FSelectedUserIndex >= 0) and (FSelectedUserIndex < Length(FUsers)) then
  begin
    FUserName := FUsers[FSelectedUserIndex].Name;
    FUserFullName := FUsers[FSelectedUserIndex].RealName;
  end;
end;

procedure TShellGreeter.DoAuthenticate();
var
  pw: string;
  errMsg: string;
  ok: Boolean;
  sessKey: string;
  sessionFile: TStringList;
begin
  if FAuthBusy then Exit;
  if FPasswordEntry = nil then Exit;

  pw := FPasswordEntry.Text;
  if pw = '' then Exit;

  FAuthBusy := True;
  try
    errMsg := '';
    sessKey := GetCurrentSessionKey();

    // 1. LightDM Daemon Authentication Path
    if LightDM().Available and LightDM().Connected then
    begin
      ok := LightDM().Authenticate(FUserName);
      if ok then
        ok := LightDM().Respond(pw);

      if ok then
      begin
        LightDM().StartSession(sessKey);
        Unlock();
        Exit;
      end
      else
        errMsg := 'Authentication failed. Please try again.';
    end
    // 2. Native PAM / Standalone Path
    else
    begin
      ok := PamAuth().Authenticate(FUserName, pw, errMsg);
      if ok then
      begin
        if FTestMode then
        begin
          FErrorMessage := 'Authenticated successfully (Test Mode)';
          if Assigned(FDrawingArea) then
            FDrawingArea.Invalidate();
          Exit;
        end
        else
        begin
          // Notify dmsama of successful authentication
          try
            sessionFile := TStringList.Create();
            try
              sessionFile.Values['user'] := FUserName;
              sessionFile.Values['session'] := sessKey;
              if DirectoryExists('/var/run/dmsama') then
                sessionFile.SaveToFile('/var/run/dmsama/session.target')
              else if DirectoryExists('/tmp') then
                sessionFile.SaveToFile('/tmp/dmsama-session.target');
            finally
              sessionFile.Free();
            end;
          except
            // Fallback to direct launch if file notification fails
            LaunchSession(sessKey);
          end;

          Unlock();
          Exit;
        end;
      end;
    end;

    // Failure Path
    if errMsg <> '' then
      FErrorMessage := errMsg
    else
      FErrorMessage := 'Authentication failed. Please try again.';

    FPasswordEntry.Text := '';
    StartShake();
    FPasswordEntry.SetFocus();
    if Assigned(FDrawingArea) then
      FDrawingArea.Invalidate();
  finally
    FAuthBusy := False;
  end;
end;

end.
