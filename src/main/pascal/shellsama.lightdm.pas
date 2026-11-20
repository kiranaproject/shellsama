unit ShellSama.LightDM;

// ShellSama.LightDM
// =================
// Dynamic bindings and client wrapper for liblightdm-gobject-1.so.0.
// Enables ShellSama to operate as a native LightDM display manager greeter.

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, ctypes, dynlibs;

type
  PGList = ^TGList;
  TGList = record
    data : Pointer;
    next : PGList;
    prev : PGList;
  end;

  TLightDMUserInfo = record
    Name       : string;
    RealName   : string;
    ImagePath  : string;
    Background : string;
    LoggedIn   : Boolean;
  end;
  TLightDMUserArray = array of TLightDMUserInfo;

  TLightDMSessionInfo = record
    Key     : string;
    Name    : string;
    Comment : string;
  end;
  TLightDMSessionArray = array of TLightDMSessionInfo;

  TLightDMClient = class
  private
    FLibHandle   : TLibHandle;
    FAvailable   : Boolean;
    FGreeter     : Pointer;
    FConnected   : Boolean;

    Flightdm_greeter_new                    : function(): Pointer; cdecl;
    Flightdm_greeter_connect_to_daemon_sync : function(greeter: Pointer; error: PPointer): cint; cdecl;
    Flightdm_greeter_authenticate           : function(greeter: Pointer; username: PChar; error: PPointer): cint; cdecl;
    Flightdm_greeter_respond                : function(greeter: Pointer; response: PChar; error: PPointer): cint; cdecl;
    Flightdm_greeter_cancel_authentication  : function(greeter: Pointer; error: PPointer): cint; cdecl;
    Flightdm_greeter_start_session_sync     : function(greeter: Pointer; session: PChar; error: PPointer): cint; cdecl;
    Flightdm_greeter_get_is_authenticated   : function(greeter: Pointer): cint; cdecl;
    Flightdm_greeter_get_in_authentication  : function(greeter: Pointer): cint; cdecl;
    Flightdm_greeter_get_authentication_user: function(greeter: Pointer): PChar; cdecl;
    Flightdm_greeter_get_default_session_hint: function(greeter: Pointer): PChar; cdecl;

    Flightdm_user_list_get_instance         : function(): Pointer; cdecl;
    Flightdm_user_list_get_length           : function(user_list: Pointer): cint; cdecl;
    Flightdm_user_list_get_users            : function(user_list: Pointer): PGList; cdecl;
    Flightdm_user_list_get_user_by_name     : function(user_list: Pointer; name: PChar): Pointer; cdecl;
    Flightdm_user_get_name                  : function(user: Pointer): PChar; cdecl;
    Flightdm_user_get_real_name             : function(user: Pointer): PChar; cdecl;
    Flightdm_user_get_image                 : function(user: Pointer): PChar; cdecl;
    Flightdm_user_get_background            : function(user: Pointer): PChar; cdecl;
    Flightdm_user_get_logged_in             : function(user: Pointer): cint; cdecl;

    Flightdm_get_sessions                   : function(): PGList; cdecl;
    Flightdm_session_get_key                : function(session: Pointer): PChar; cdecl;
    Flightdm_session_get_name               : function(session: Pointer): PChar; cdecl;
    Flightdm_session_get_comment            : function(session: Pointer): PChar; cdecl;

    procedure LoadSymbols();
    function  GetIsAuthenticated(): Boolean;
    function  GetInAuthentication(): Boolean;
    function  GetDefaultSession(): string;
  public
    constructor Create();
    destructor Destroy(); override;

    function Connect(): Boolean;
    function GetUsers(): TLightDMUserArray;
    function GetSessions(): TLightDMSessionArray;
    function Authenticate(const AUsername: string): Boolean;
    function Respond(const APassword: string): Boolean;
    function CancelAuthentication(): Boolean;
    function StartSession(const ASessionKey: string): Boolean;

    property Available: Boolean read FAvailable;
    property Connected: Boolean read FConnected;
    property IsAuthenticated: Boolean read GetIsAuthenticated;
    property InAuthentication: Boolean read GetInAuthentication;
    property DefaultSession: string read GetDefaultSession;
  end;

function LightDM(): TLightDMClient;

implementation

var
  GLightDMInstance: TLightDMClient = nil;

function LightDM(): TLightDMClient;
begin
  if GLightDMInstance = nil then
    GLightDMInstance := TLightDMClient.Create();
  Result := GLightDMInstance;
end;

constructor TLightDMClient.Create();
begin
  inherited Create();
  FAvailable := False;
  FConnected := False;
  FGreeter := nil;

  FLibHandle := SafeLoadLibrary('liblightdm-gobject-1.so.0');
  if FLibHandle = NilHandle then
    FLibHandle := SafeLoadLibrary('liblightdm-gobject-1.so');

  if FLibHandle <> NilHandle then
  begin
    LoadSymbols();
    if Assigned(Flightdm_greeter_new) then
    begin
      try
        FGreeter := Flightdm_greeter_new();
        FAvailable := (FGreeter <> nil);
      except
        FGreeter := nil;
        FAvailable := False;
      end;
    end;
  end;
end;

destructor TLightDMClient.Destroy();
begin
  if FLibHandle <> NilHandle then
  begin
    UnloadLibrary(FLibHandle);
    FLibHandle := NilHandle;
  end;
  inherited Destroy();
end;

procedure TLightDMClient.LoadSymbols();
begin
  Pointer(Flightdm_greeter_new)                    := GetProcedureAddress(FLibHandle, 'lightdm_greeter_new');
  Pointer(Flightdm_greeter_connect_to_daemon_sync) := GetProcedureAddress(FLibHandle, 'lightdm_greeter_connect_to_daemon_sync');
  Pointer(Flightdm_greeter_authenticate)           := GetProcedureAddress(FLibHandle, 'lightdm_greeter_authenticate');
  Pointer(Flightdm_greeter_respond)                := GetProcedureAddress(FLibHandle, 'lightdm_greeter_respond');
  Pointer(Flightdm_greeter_cancel_authentication)  := GetProcedureAddress(FLibHandle, 'lightdm_greeter_cancel_authentication');
  Pointer(Flightdm_greeter_start_session_sync)     := GetProcedureAddress(FLibHandle, 'lightdm_greeter_start_session_sync');
  Pointer(Flightdm_greeter_get_is_authenticated)   := GetProcedureAddress(FLibHandle, 'lightdm_greeter_get_is_authenticated');
  Pointer(Flightdm_greeter_get_in_authentication)  := GetProcedureAddress(FLibHandle, 'lightdm_greeter_get_in_authentication');
  Pointer(Flightdm_greeter_get_authentication_user):= GetProcedureAddress(FLibHandle, 'lightdm_greeter_get_authentication_user');
  Pointer(Flightdm_greeter_get_default_session_hint):= GetProcedureAddress(FLibHandle, 'lightdm_greeter_get_default_session_hint');

  Pointer(Flightdm_user_list_get_instance)         := GetProcedureAddress(FLibHandle, 'lightdm_user_list_get_instance');
  Pointer(Flightdm_user_list_get_length)           := GetProcedureAddress(FLibHandle, 'lightdm_user_list_get_length');
  Pointer(Flightdm_user_list_get_users)            := GetProcedureAddress(FLibHandle, 'lightdm_user_list_get_users');
  Pointer(Flightdm_user_list_get_user_by_name)     := GetProcedureAddress(FLibHandle, 'lightdm_user_list_get_user_by_name');
  Pointer(Flightdm_user_get_name)                  := GetProcedureAddress(FLibHandle, 'lightdm_user_get_name');
  Pointer(Flightdm_user_get_real_name)             := GetProcedureAddress(FLibHandle, 'lightdm_user_get_real_name');
  Pointer(Flightdm_user_get_image)                 := GetProcedureAddress(FLibHandle, 'lightdm_user_get_image');
  Pointer(Flightdm_user_get_background)            := GetProcedureAddress(FLibHandle, 'lightdm_user_get_background');
  Pointer(Flightdm_user_get_logged_in)             := GetProcedureAddress(FLibHandle, 'lightdm_user_get_logged_in');

  Pointer(Flightdm_get_sessions)                   := GetProcedureAddress(FLibHandle, 'lightdm_get_sessions');
  Pointer(Flightdm_session_get_key)                := GetProcedureAddress(FLibHandle, 'lightdm_session_get_key');
  Pointer(Flightdm_session_get_name)               := GetProcedureAddress(FLibHandle, 'lightdm_session_get_name');
  Pointer(Flightdm_session_get_comment)            := GetProcedureAddress(FLibHandle, 'lightdm_session_get_comment');
end;

function TLightDMClient.Connect(): Boolean;
var
  err: Pointer;
begin
  Result := False;
  if not FAvailable or (FGreeter = nil) or not Assigned(Flightdm_greeter_connect_to_daemon_sync) then
    Exit;

  err := nil;
  try
    Result := (Flightdm_greeter_connect_to_daemon_sync(FGreeter, @err) <> 0);
    FConnected := Result;
  except
    FConnected := False;
    Result := False;
  end;
end;

function TLightDMClient.GetUsers(): TLightDMUserArray;
var
  ulist: Pointer;
  node: PGList;
  userPtr: Pointer;
  count: Integer;
  pStr: PChar;
begin
  SetLength(Result, 0);
  if not FAvailable or not Assigned(Flightdm_user_list_get_instance) or not Assigned(Flightdm_user_list_get_users) then
    Exit;

  ulist := Flightdm_user_list_get_instance();
  if ulist = nil then Exit;

  node := Flightdm_user_list_get_users(ulist);
  count := 0;
  while node <> nil do
  begin
    userPtr := node^.data;
    if userPtr <> nil then
    begin
      Inc(count);
      SetLength(Result, count);

      if Assigned(Flightdm_user_get_name) then
      begin
        pStr := Flightdm_user_get_name(userPtr);
        if pStr <> nil then Result[count - 1].Name := string(pStr);
      end;

      if Assigned(Flightdm_user_get_real_name) then
      begin
        pStr := Flightdm_user_get_real_name(userPtr);
        if pStr <> nil then Result[count - 1].RealName := string(pStr);
      end;

      if Assigned(Flightdm_user_get_image) then
      begin
        pStr := Flightdm_user_get_image(userPtr);
        if pStr <> nil then Result[count - 1].ImagePath := string(pStr);
      end;

      if Assigned(Flightdm_user_get_background) then
      begin
        pStr := Flightdm_user_get_background(userPtr);
        if pStr <> nil then Result[count - 1].Background := string(pStr);
      end;

      if Assigned(Flightdm_user_get_logged_in) then
        Result[count - 1].LoggedIn := (Flightdm_user_get_logged_in(userPtr) <> 0);
    end;
    node := node^.next;
  end;
end;

function TLightDMClient.GetSessions(): TLightDMSessionArray;
var
  node: PGList;
  sessPtr: Pointer;
  count: Integer;
  pStr: PChar;
begin
  SetLength(Result, 0);
  if not FAvailable or not Assigned(Flightdm_get_sessions) then Exit;

  node := Flightdm_get_sessions();
  count := 0;
  while node <> nil do
  begin
    sessPtr := node^.data;
    if sessPtr <> nil then
    begin
      Inc(count);
      SetLength(Result, count);

      if Assigned(Flightdm_session_get_key) then
      begin
        pStr := Flightdm_session_get_key(sessPtr);
        if pStr <> nil then Result[count - 1].Key := string(pStr);
      end;

      if Assigned(Flightdm_session_get_name) then
      begin
        pStr := Flightdm_session_get_name(sessPtr);
        if pStr <> nil then Result[count - 1].Name := string(pStr);
      end;

      if Assigned(Flightdm_session_get_comment) then
      begin
        pStr := Flightdm_session_get_comment(sessPtr);
        if pStr <> nil then Result[count - 1].Comment := string(pStr);
      end;
    end;
    node := node^.next;
  end;
end;

function TLightDMClient.Authenticate(const AUsername: string): Boolean;
var
  err: Pointer;
begin
  Result := False;
  if not FAvailable or (FGreeter = nil) or not Assigned(Flightdm_greeter_authenticate) then
    Exit;

  err := nil;
  try
    Result := (Flightdm_greeter_authenticate(FGreeter, PChar(AUsername), @err) <> 0);
  except
    Result := False;
  end;
end;

function TLightDMClient.Respond(const APassword: string): Boolean;
var
  err: Pointer;
begin
  Result := False;
  if not FAvailable or (FGreeter = nil) or not Assigned(Flightdm_greeter_respond) then
    Exit;

  err := nil;
  try
    Result := (Flightdm_greeter_respond(FGreeter, PChar(APassword), @err) <> 0);
  except
    Result := False;
  end;
end;

function TLightDMClient.CancelAuthentication(): Boolean;
var
  err: Pointer;
begin
  Result := False;
  if not FAvailable or (FGreeter = nil) or not Assigned(Flightdm_greeter_cancel_authentication) then
    Exit;

  err := nil;
  try
    Result := (Flightdm_greeter_cancel_authentication(FGreeter, @err) <> 0);
  except
    Result := False;
  end;
end;

function TLightDMClient.StartSession(const ASessionKey: string): Boolean;
var
  err: Pointer;
  pKey: PChar;
begin
  Result := False;
  if not FAvailable or (FGreeter = nil) or not Assigned(Flightdm_greeter_start_session_sync) then
    Exit;

  err := nil;
  if ASessionKey <> '' then
    pKey := PChar(ASessionKey)
  else
    pKey := nil;

  try
    Result := (Flightdm_greeter_start_session_sync(FGreeter, pKey, @err) <> 0);
  except
    Result := False;
  end;
end;

function TLightDMClient.GetIsAuthenticated(): Boolean;
begin
  Result := False;
  if FAvailable and (FGreeter <> nil) and Assigned(Flightdm_greeter_get_is_authenticated) then
    Result := (Flightdm_greeter_get_is_authenticated(FGreeter) <> 0);
end;

function TLightDMClient.GetInAuthentication(): Boolean;
begin
  Result := False;
  if FAvailable and (FGreeter <> nil) and Assigned(Flightdm_greeter_get_in_authentication) then
    Result := (Flightdm_greeter_get_in_authentication(FGreeter) <> 0);
end;

function TLightDMClient.GetDefaultSession(): string;
var
  pStr: PChar;
begin
  Result := '';
  if FAvailable and (FGreeter <> nil) and Assigned(Flightdm_greeter_get_default_session_hint) then
  begin
    pStr := Flightdm_greeter_get_default_session_hint(FGreeter);
    if pStr <> nil then
      Result := string(pStr);
  end;
end;

initialization

finalization
  if Assigned(GLightDMInstance) then
  begin
    GLightDMInstance.Free();
    GLightDMInstance := nil;
  end;

end.
