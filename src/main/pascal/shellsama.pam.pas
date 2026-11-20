unit ShellSama.PAM;

// ShellSama.PAM
// =============
// Native PAM (Pluggable Authentication Modules) integration for Samarinda Desktop.
// Dynamically binds libpam.so.0 via dynlibs with libc-compliant memory allocation.

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, ctypes, dynlibs;

const
  PAM_SUCCESS              = 0;
  PAM_OPEN_ERR             = 1;
  PAM_SYMBOL_ERR           = 2;
  PAM_SERVICE_ERR          = 3;
  PAM_SYSTEM_ERR           = 4;
  PAM_BUF_ERR              = 5;
  PAM_PERM_DENIED          = 6;
  PAM_AUTH_ERR             = 7;
  PAM_CRED_INSUFFICIENT    = 8;
  PAM_AUTHINFO_UNAVAIL     = 9;
  PAM_USER_UNKNOWN         = 10;
  PAM_MAXTRIES             = 11;
  PAM_NEW_AUTHTOK_REQD     = 12;
  PAM_ACCT_EXPIRED         = 13;
  PAM_SESSION_ERR          = 14;
  PAM_CRED_UNAVAIL         = 15;
  PAM_CRED_EXPIRED         = 16;
  PAM_CRED_ERR             = 17;
  PAM_NO_MODULE_DATA       = 18;
  PAM_CONV_ERR             = 19;
  PAM_AUTHTOK_ERR          = 20;
  PAM_AUTHTOK_RECOVERY_ERR = 21;
  PAM_AUTHTOK_LOCK_BUSY    = 22;
  PAM_AUTHTOK_DISABLE_AGING= 23;
  PAM_TRY_AGAIN            = 24;
  PAM_IGNORE               = 25;
  PAM_ABORT                = 26;
  PAM_AUTHTOK_EXPIRED      = 27;
  PAM_MODULE_UNKNOWN       = 28;
  PAM_BAD_ITEM             = 29;
  PAM_CONV_AGAIN           = 30;
  PAM_INCOMPLETE           = 31;

  PAM_PROMPT_ECHO_OFF      = 1;
  PAM_PROMPT_ECHO_ON       = 2;
  PAM_ERROR_MSG            = 3;
  PAM_TEXT_INFO            = 4;

type
  PPamHandle = Pointer;

  PPamMessage = ^TPamMessage;
  TPamMessage = record
    msg_style : cint;
    msg       : PChar;
  end;
  PPPamMessage = ^PPamMessage;

  PPamResponse = ^TPamResponse;
  TPamResponse = record
    resp         : PChar;
    resp_retcode : cint;
  end;
  PPPamResponse = ^PPamResponse;

  TPamConvFunc = function(num_msg: cint; msg: PPPamMessage; var resp: PPamResponse; appdata_ptr: Pointer): cint; cdecl;

  TPamConv = record
    conv        : TPamConvFunc;
    appdata_ptr : Pointer;
  end;
  PPamConv = ^TPamConv;

  TPamAuthenticator = class
  private
    FLibHandle        : TLibHandle;
    FAvailable        : Boolean;
    Fpam_start        : function(service_name: PChar; user: PChar; pam_conversation: PPamConv; out pamh: PPamHandle): cint; cdecl;
    Fpam_authenticate : function(pamh: PPamHandle; flags: cint): cint; cdecl;
    Fpam_acct_mgmt    : function(pamh: PPamHandle; flags: cint): cint; cdecl;
    Fpam_setcred      : function(pamh: PPamHandle; flags: cint): cint; cdecl;
    Fpam_open_session : function(pamh: PPamHandle; flags: cint): cint; cdecl;
    Fpam_close_session: function(pamh: PPamHandle; flags: cint): cint; cdecl;
    Fpam_end          : function(pamh: PPamHandle; pam_status: cint): cint; cdecl;
    Fpam_strerror     : function(pamh: PPamHandle; errnum: cint): PChar; cdecl;

    procedure LoadSymbols();
  public
    constructor Create();
    destructor Destroy(); override;

    function Authenticate(const AUsername, APassword: string; const AService: string; out AErrorMsg: string): Boolean;
    function Authenticate(const AUsername, APassword: string; out AErrorMsg: string): Boolean;

    property Available: Boolean read FAvailable;
  end;

function PamAuth(): TPamAuthenticator;

implementation

function malloc(size: csize_t): Pointer; cdecl; external 'c';
function strdup(const s: PChar): PChar; cdecl; external 'c';

var
  GPamAuthenticator: TPamAuthenticator = nil;

function PamAuth(): TPamAuthenticator;
begin
  if GPamAuthenticator = nil then
    GPamAuthenticator := TPamAuthenticator.Create();
  Result := GPamAuthenticator;
end;

function DefaultPamConversation(num_msg: cint; msg: PPPamMessage; var resp: PPamResponse; appdata_ptr: Pointer): cint; cdecl;
var
  i: cint;
  resps: PPamResponse;
  pw: PChar;
begin
  pw := PChar(appdata_ptr);
  resps := PPamResponse(malloc(num_msg * SizeOf(TPamResponse)));
  if resps = nil then Exit(PAM_BUF_ERR);
  FillChar(resps^, num_msg * SizeOf(TPamResponse), 0);

  for i := 0 to num_msg - 1 do
  begin
    if (msg[i]^.msg_style = PAM_PROMPT_ECHO_OFF) or (msg[i]^.msg_style = PAM_PROMPT_ECHO_ON) then
    begin
      if pw <> nil then
        resps[i].resp := strdup(pw)
      else
        resps[i].resp := nil;
      resps[i].resp_retcode := 0;
    end;
  end;
  resp := resps;
  Result := PAM_SUCCESS;
end;

constructor TPamAuthenticator.Create();
const
  LIB_CANDIDATES: array[0..2] of string = (
    'libpam.so.0',
    'libpam.so',
    '/lib/x86_64-linux-gnu/libpam.so.0'
  );
var
  i: Integer;
begin
  inherited Create();
  FLibHandle := NilHandle;
  FAvailable := False;

  for i := Low(LIB_CANDIDATES) to High(LIB_CANDIDATES) do
  begin
    FLibHandle := SafeLoadLibrary(LIB_CANDIDATES[i]);
    if FLibHandle <> NilHandle then
      Break;
  end;

  if FLibHandle <> NilHandle then
    LoadSymbols();
end;

destructor TPamAuthenticator.Destroy();
begin
  if FLibHandle <> NilHandle then
  begin
    UnloadLibrary(FLibHandle);
    FLibHandle := NilHandle;
  end;
  inherited Destroy();
end;

procedure TPamAuthenticator.LoadSymbols();
begin
  Pointer(Fpam_start)         := GetProcedureAddress(FLibHandle, 'pam_start');
  Pointer(Fpam_authenticate)  := GetProcedureAddress(FLibHandle, 'pam_authenticate');
  Pointer(Fpam_acct_mgmt)     := GetProcedureAddress(FLibHandle, 'pam_acct_mgmt');
  Pointer(Fpam_setcred)       := GetProcedureAddress(FLibHandle, 'pam_setcred');
  Pointer(Fpam_open_session)  := GetProcedureAddress(FLibHandle, 'pam_open_session');
  Pointer(Fpam_close_session) := GetProcedureAddress(FLibHandle, 'pam_close_session');
  Pointer(Fpam_end)           := GetProcedureAddress(FLibHandle, 'pam_end');
  Pointer(Fpam_strerror)      := GetProcedureAddress(FLibHandle, 'pam_strerror');

  FAvailable := Assigned(Fpam_start) and Assigned(Fpam_authenticate) and Assigned(Fpam_end);
end;

function TPamAuthenticator.Authenticate(const AUsername, APassword: string; const AService: string; out AErrorMsg: string): Boolean;
var
  conv: TPamConv;
  pamh: PPamHandle;
  ret: cint;
  errPChar: PChar;
begin
  Result := False;
  AErrorMsg := '';

  if not FAvailable then
  begin
    AErrorMsg := 'PAM library (libpam.so.0) is not available';
    Exit;
  end;

  if AUsername = '' then
  begin
    AErrorMsg := 'Username cannot be empty';
    Exit;
  end;

  conv.conv := @DefaultPamConversation;
  conv.appdata_ptr := PChar(APassword);

  pamh := nil;
  ret := Fpam_start(PChar(AService), PChar(AUsername), @conv, pamh);
  if ret <> PAM_SUCCESS then
  begin
    if Assigned(Fpam_strerror) and (pamh <> nil) then
      errPChar := Fpam_strerror(pamh, ret)
    else
      errPChar := nil;

    if errPChar <> nil then
      AErrorMsg := Format('pam_start error %d: %s', [ret, StrPas(errPChar)])
    else
      AErrorMsg := Format('pam_start error %d', [ret]);

    if pamh <> nil then
      Fpam_end(pamh, ret);
    Exit;
  end;

  try
    ret := Fpam_authenticate(pamh, 0);
    if ret <> PAM_SUCCESS then
    begin
      if Assigned(Fpam_strerror) then
        errPChar := Fpam_strerror(pamh, ret)
      else
        errPChar := nil;

      if errPChar <> nil then
        AErrorMsg := StrPas(errPChar)
      else
        AErrorMsg := Format('Authentication error %d', [ret]);
      Exit;
    end;

    // Optional account check (checks account expiration, etc.)
    if Assigned(Fpam_acct_mgmt) then
    begin
      ret := Fpam_acct_mgmt(pamh, 0);
      if ret <> PAM_SUCCESS then
      begin
        if Assigned(Fpam_strerror) then
          errPChar := Fpam_strerror(pamh, ret)
        else
          errPChar := nil;

        if errPChar <> nil then
          AErrorMsg := StrPas(errPChar)
        else
          AErrorMsg := Format('Account management error %d', [ret]);
        Exit;
      end;
    end;

    Result := True;
  finally
    if pamh <> nil then
      Fpam_end(pamh, ret);
  end;
end;

function TPamAuthenticator.Authenticate(const AUsername, APassword: string; out AErrorMsg: string): Boolean;
begin
  Result := Authenticate(AUsername, APassword, 'mate-screensaver', AErrorMsg);
  if not Result and (Pos('Service', AErrorMsg) > 0) then
    Result := Authenticate(AUsername, APassword, 'other', AErrorMsg);
end;

finalization
  if GPamAuthenticator <> nil then
  begin
    GPamAuthenticator.Free();
    GPamAuthenticator := nil;
  end;

end.
