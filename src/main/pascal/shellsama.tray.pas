{ Unit ShellSama.Tray — Freedesktop.org X11 System Tray (_NET_SYSTEM_TRAY) Host }

unit ShellSama.Tray;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, ctypes,
  Floria.XCB,
  ftpas.api, ftpas.types, ftpas;

type
  PCardinalArray = ^TCardinalArray;
  TCardinalArray = array[0..4] of Cardinal;

  Pxcb_unmap_notify_event_t = ^xcb_unmap_notify_event_t;

  TShellSystemTray = class
  private
    FConn              : Pxcb_connection_t;
    FScreen            : Pxcb_screen_t;
    FRootWindow        : Cardinal;
    FPanelWindow       : TFtWindow;
    FTrayWin           : Cardinal;
    FScreenIdx         : Integer;
    FIsActive          : Boolean;

    FDockedClients     : array of Cardinal;

    // Atoms
    FAtomTraySelection : Cardinal; // _NET_SYSTEM_TRAY_S0
    FAtomTrayOpcode    : Cardinal; // _NET_SYSTEM_TRAY_OPCODE
    FAtomTrayOrientation: Cardinal; // _NET_SYSTEM_TRAY_ORIENTATION
    FAtomTrayVisual    : Cardinal; // _NET_SYSTEM_TRAY_VISUAL
    FAtomXEmbed        : Cardinal; // _XEMBED
    FAtomXEmbedInfo    : Cardinal; // _XEMBED_INFO
    FAtomManager       : Cardinal; // MANAGER

    FStartX            : Integer;
    FStartY            : Integer;
    FIconSize          : Integer;
    FIconGap           : Integer;

    FOnLayoutChanged   : TNotifyEvent;

    procedure InitAtoms();
    function InternAtom(const AName: string): Cardinal;
  public
    constructor Create(APanelWindow: TFtWindow; AScreenIdx: Integer = 0);
    destructor Destroy(); override;

    function ClaimSelection(): Boolean;
    procedure ReleaseSelection();

    procedure DockClient(AWin: Cardinal);
    procedure UndockClient(AWin: Cardinal);
    function IsDocked(AWin: Cardinal): Boolean;
    procedure LayoutIcons();

    procedure SetPosition(AX, AY: Integer);
    function GetWidth(): Integer;
    function GetClientCount(): Integer;
    function GetClient(AIndex: Integer): Cardinal;

    function HandleX11Event(AEvent: Pointer): Boolean;

    property IsActive       : Boolean read FIsActive;
    property ClientCount    : Integer read GetClientCount;
    property Width          : Integer read GetWidth;
    property StartX         : Integer read FStartX write FStartX;
    property StartY         : Integer read FStartY write FStartY;
    property IconSize       : Integer read FIconSize write FIconSize;
    property IconGap        : Integer read FIconGap write FIconGap;
    property AtomTrayOpcode : Cardinal read FAtomTrayOpcode;
    property OnLayoutChanged: TNotifyEvent read FOnLayoutChanged write FOnLayoutChanged;
  end;

var
  GSystemTrayInstance: TShellSystemTray = nil;

function TrayGlobalEventFilter(AEvent: Pointer): cint32; cdecl;

implementation

uses
  ShellSama.Launcher;

procedure c_free(p: Pointer); cdecl; external 'c' name 'free';

function TrayGlobalEventFilter(AEvent: Pointer): cint32; cdecl;
begin
  if (AEvent <> nil) and Assigned(GSystemTrayInstance) then
  begin
    if GSystemTrayInstance.HandleX11Event(AEvent) then
      Exit(1);
  end;

  if Assigned(GLauncherInstance) then
    Exit(LauncherEventFilterCallback(AEvent));

  Result := 0;
end;

// -----------------------------------------------------------------------------
// TShellSystemTray Implementation
// -----------------------------------------------------------------------------

constructor TShellSystemTray.Create(APanelWindow: TFtWindow; AScreenIdx: Integer);
begin
  inherited Create();
  GSystemTrayInstance := Self;
  FPanelWindow := APanelWindow;
  FScreenIdx := AScreenIdx;
  FIsActive := False;
  SetLength(FDockedClients, 0);

  FStartX := 0;
  FStartY := 8;
  FIconSize := 22;
  FIconGap := 4;

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

  if FtIsLibLoaded() and Assigned(ft_register_event_filter) then
    ft_register_event_filter(@TrayGlobalEventFilter);
end;

destructor TShellSystemTray.Destroy();
begin
  if GSystemTrayInstance = Self then
    GSystemTrayInstance := nil;

  if FtIsLibLoaded() and Assigned(ft_register_event_filter) then
  begin
    if Assigned(GLauncherInstance) then
      ft_register_event_filter(@LauncherEventFilterCallback)
    else
      ft_register_event_filter(nil);
  end;

  ReleaseSelection();

  inherited Destroy();
end;

function TShellSystemTray.InternAtom(const AName: string): Cardinal;
var
  cookie: xcb_intern_atom_cookie_t;
  reply: Pxcb_intern_atom_reply_t;
begin
  Result := 0;
  if FConn = nil then Exit;
  cookie := xcb_intern_atom(FConn, 0, Length(AName), PChar(AName));
  reply := xcb_intern_atom_reply(FConn, cookie, nil);
  if reply <> nil then
  begin
    Result := reply^.atom;
    c_free(reply);
  end;
end;

procedure TShellSystemTray.InitAtoms();
var
  selName: string;
begin
  if FConn = nil then Exit;

  selName := '_NET_SYSTEM_TRAY_S' + IntToStr(FScreenIdx);
  FAtomTraySelection  := InternAtom(selName);
  FAtomTrayOpcode     := InternAtom('_NET_SYSTEM_TRAY_OPCODE');
  FAtomTrayOrientation:= InternAtom('_NET_SYSTEM_TRAY_ORIENTATION');
  FAtomTrayVisual     := InternAtom('_NET_SYSTEM_TRAY_VISUAL');
  FAtomXEmbed         := InternAtom('_XEMBED');
  FAtomXEmbedInfo     := InternAtom('_XEMBED_INFO');
  FAtomManager        := InternAtom('MANAGER');
end;

function TShellSystemTray.ClaimSelection(): Boolean;
var
  ev: xcb_client_message_event_t;
  data32: PCardinalArray;
  val32: Cardinal;
  ownerCookie: xcb_get_selection_owner_cookie_t;
  ownerReply: Pxcb_get_selection_owner_reply_t;
begin
  Result := False;
  if (FConn = nil) or (FPanelWindow = nil) then Exit;
  if FAtomTraySelection = 0 then Exit;

  FTrayWin := Cardinal(PtrUInt(FPanelWindow.NativeHandle));
  if FTrayWin = 0 then Exit;

  // 1. Set orientation to HORIZONTAL (0)
  val32 := 0;
  xcb_change_property(FConn, XCB_PROP_MODE_REPLACE, FTrayWin,
                      FAtomTrayOrientation, XCB_ATOM_CARDINAL, 32, 1, @val32);

  // 2. Set visual property (root window visual)
  if FScreen <> nil then
  begin
    val32 := FScreen^.root_visual;
    xcb_change_property(FConn, XCB_PROP_MODE_REPLACE, FTrayWin,
                        FAtomTrayVisual, XCB_ATOM_VISUALID, 32, 1, @val32);
  end;

  // 3. Set selection owner
  xcb_set_selection_owner(FConn, FTrayWin, FAtomTraySelection, XCB_CURRENT_TIME);

  // Verify ownership
  ownerCookie := xcb_get_selection_owner(FConn, FAtomTraySelection);
  ownerReply := xcb_get_selection_owner_reply(FConn, ownerCookie, nil);
  if (ownerReply <> nil) and (ownerReply^.owner = FTrayWin) then
  begin
    FIsActive := True;
    Result := True;
  end;
  if ownerReply <> nil then
    c_free(ownerReply);

  if not FIsActive then Exit;

  // 4. Broadcast MANAGER ClientMessage to root window
  FillChar(ev, SizeOf(ev), 0);
  ev.response_type := XCB_CLIENT_MESSAGE;
  ev.format := 32;
  ev.window := FRootWindow;
  ev.type_ := FAtomManager;
  data32 := PCardinalArray(@ev.data.raw[0]);
  data32^[0] := XCB_CURRENT_TIME;
  data32^[1] := FAtomTraySelection;
  data32^[2] := FTrayWin;
  data32^[3] := 0;
  data32^[4] := 0;

  xcb_send_event(FConn, 0, FRootWindow,
                 XCB_EVENT_MASK_STRUCTURE_NOTIFY,
                 PAnsiChar(@ev));
  xcb_flush(FConn);
end;

procedure TShellSystemTray.ReleaseSelection();
var
  i: Integer;
begin
  if (FConn = nil) or not FIsActive then Exit;

  // Undock all clients back to root
  for i := 0 to High(FDockedClients) do
  begin
    xcb_change_save_set(FConn, XCB_SET_MODE_DELETE, FDockedClients[i]);
    xcb_reparent_window(FConn, FDockedClients[i], FRootWindow, 0, 0);
  end;
  SetLength(FDockedClients, 0);

  // Clear selection owner
  xcb_set_selection_owner(FConn, 0, FAtomTraySelection, XCB_CURRENT_TIME);
  xcb_flush(FConn);
  FIsActive := False;
end;

procedure TShellSystemTray.DockClient(AWin: Cardinal);
var
  idx: Integer;
  ev: xcb_client_message_event_t;
  data32: PCardinalArray;
  maskVal: Cardinal;
begin
  if (FConn = nil) or (AWin = 0) then Exit;

  // Check if already docked
  for idx := 0 to High(FDockedClients) do
    if FDockedClients[idx] = AWin then Exit;

  // Add to list
  SetLength(FDockedClients, Length(FDockedClients) + 1);
  FDockedClients[High(FDockedClients)] := AWin;

  // Insert into save set so X11 restores it if tray exits
  xcb_change_save_set(FConn, XCB_SET_MODE_INSERT, AWin);

  // Select structure notify to detect destroy/unmap
  maskVal := XCB_EVENT_MASK_STRUCTURE_NOTIFY or XCB_EVENT_MASK_PROPERTY_CHANGE;
  xcb_change_window_attributes(FConn, AWin, XCB_CW_EVENT_MASK, @maskVal);

  // Reparent into panel window
  xcb_reparent_window(FConn, AWin, FTrayWin, 0, 0);

  // Send XEMBED_EMBEDDED_NOTIFY message
  FillChar(ev, SizeOf(ev), 0);
  ev.response_type := XCB_CLIENT_MESSAGE;
  ev.format := 32;
  ev.window := AWin;
  ev.type_ := FAtomXEmbed;
  data32 := PCardinalArray(@ev.data.raw[0]);
  data32^[0] := XCB_CURRENT_TIME;
  data32^[1] := 0; // XEMBED_EMBEDDED_NOTIFY
  data32^[2] := 0;
  data32^[3] := FTrayWin;
  data32^[4] := 0;

  xcb_send_event(FConn, 0, AWin, 0, PAnsiChar(@ev));

  // Map window
  xcb_map_window(FConn, AWin);
  xcb_flush(FConn);

  LayoutIcons();
  if Assigned(FOnLayoutChanged) then
    FOnLayoutChanged(Self);
end;

procedure TShellSystemTray.UndockClient(AWin: Cardinal);
var
  i, j: Integer;
  found: Boolean;
begin
  found := False;
  for i := 0 to High(FDockedClients) do
  begin
    if FDockedClients[i] = AWin then
    begin
      for j := i to High(FDockedClients) - 1 do
        FDockedClients[j] := FDockedClients[j + 1];
      SetLength(FDockedClients, Length(FDockedClients) - 1);
      found := True;
      Break;
    end;
  end;

  if found then
  begin
    LayoutIcons();
    if Assigned(FOnLayoutChanged) then
      FOnLayoutChanged(Self);
  end;
end;

function TShellSystemTray.IsDocked(AWin: Cardinal): Boolean;
var
  i: Integer;
begin
  for i := 0 to High(FDockedClients) do
    if FDockedClients[i] = AWin then Exit(True);
  Result := False;
end;

procedure TShellSystemTray.LayoutIcons();
var
  i, x, y: Integer;
  values: array[0..3] of Cardinal;
  valMask: Word;
begin
  if (FConn = nil) or (Length(FDockedClients) = 0) then Exit;

  y := FStartY;
  valMask := XCB_CONFIG_WINDOW_X or XCB_CONFIG_WINDOW_Y or
             XCB_CONFIG_WINDOW_WIDTH or XCB_CONFIG_WINDOW_HEIGHT;

  for i := 0 to High(FDockedClients) do
  begin
    x := FStartX + i * (FIconSize + FIconGap);
    values[0] := x;
    values[1] := y;
    values[2] := FIconSize;
    values[3] := FIconSize;

    xcb_configure_window(FConn, FDockedClients[i], valMask, @values[0]);
  end;
  xcb_flush(FConn);
end;

procedure TShellSystemTray.SetPosition(AX, AY: Integer);
begin
  if (FStartX <> AX) or (FStartY <> AY) then
  begin
    FStartX := AX;
    FStartY := AY;
    LayoutIcons();
  end;
end;

function TShellSystemTray.GetWidth(): Integer;
begin
  if Length(FDockedClients) = 0 then
    Result := 0
  else
    Result := Length(FDockedClients) * (FIconSize + FIconGap);
end;

function TShellSystemTray.GetClientCount(): Integer;
begin
  Result := Length(FDockedClients);
end;

function TShellSystemTray.GetClient(AIndex: Integer): Cardinal;
begin
  if (AIndex >= 0) and (AIndex <= High(FDockedClients)) then
    Result := FDockedClients[AIndex]
  else
    Result := 0;
end;

function TShellSystemTray.HandleX11Event(AEvent: Pointer): Boolean;
var
  evType: Byte;
  cme: Pxcb_client_message_event_t;
  data32: PCardinalArray;
  dne: Pxcb_destroy_notify_event_t;
  une: Pxcb_unmap_notify_event_t;
begin
  Result := False;
  if AEvent = nil then Exit;

  evType := Pxcb_generic_event_t(AEvent)^.response_type and $7F;

  case evType of
    XCB_CLIENT_MESSAGE:
    begin
      cme := Pxcb_client_message_event_t(AEvent);
      if (FAtomTrayOpcode <> 0) and (cme^.type_ = FAtomTrayOpcode) then
      begin
        data32 := PCardinalArray(@cme^.data.raw[0]);
        if data32^[1] = 0 then // SYSTEM_TRAY_REQUEST_DOCK
        begin
          DockClient(data32^[2]);
          Result := True;
        end;
      end;
    end;

    XCB_DESTROY_NOTIFY:
    begin
      dne := Pxcb_destroy_notify_event_t(AEvent);
      if IsDocked(dne^.window) then
      begin
        UndockClient(dne^.window);
        Result := True;
      end;
    end;

    XCB_UNMAP_NOTIFY:
    begin
      une := Pxcb_unmap_notify_event_t(AEvent);
      if IsDocked(une^.window) then
      begin
        UndockClient(une^.window);
        Result := True;
      end;
    end;
  end;
end;

end.
