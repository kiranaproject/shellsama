{ Unit ShellSama.WindowPixmaps — the per-window Composite pixmaps a preview needs.

  A window preview is not a screenshot. The server already keeps every redirected window's
  pixels off-screen, and xcb_composite_name_window_pixmap hands out a name for them. That
  name is a live view, not a copy, so holding one costs no memory and no refresh.

  What it does cost is care, because the name's validity depends on events the dock cannot
  see directly:

    - a pixmap can only be named while the window is MAPPED; naming a minimized window
      fails with BadMatch, so the name has to be taken before the minimize and kept;
    - a resize gives the window new storage, so a held name keeps the old contents and
      the old bounds;
    - a re-map does the same, so a window that is minimized and restored needs a new name
      even though its size never changed;
    - a held name outlives its window, so it has to be freed or it leaks.

  The dock learns about these by polling. It already runs a 250ms tick, and the toolkit's
  event loop only routes events to windows it owns, so a foreign window's ConfigureNotify
  would be dropped before the dock could see it. Polling geometry and map state in one
  batch is two round trips for the whole window set, which is cheaper than the alternative
  of asking the toolkit for an event filter.

  The lifetime rules live in PlanPixmapRefresh, which is a pure function over two arrays.
  That is deliberate: the rules are where the bugs are, and they can be tested without an
  X server. The X calls sit behind NamePixmap, which a test double overrides. }

unit ShellSama.WindowPixmaps;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils,
  Floria.XCB,
  Floria.XCB.Composite;

type
  // What the dock saw of a window at one instant.
  TWindowSnapshot = record
    Window : Cardinal;
    Width  : Integer;
    Height : Integer;
    Mapped : Boolean;
  end;
  TWindowSnapshotArray = array of TWindowSnapshot;

  TWindowPixmapEntry = record
    Window   : Cardinal;
    Pixmap   : xcb_pixmap_t;
    Width    : Integer;   // the pixmap's own bounds, recorded when it was named
    Height   : Integer;
    WasMapped: Boolean;   // map state at the previous refresh
  end;
  TWindowPixmapEntryArray = array of TWindowPixmapEntry;

  // Why a window needs a name. Recorded rather than inferred so a caller can tell a
  // first capture from a re-capture; they fail in different ways.
  TPixmapReason = (prNew, prResized, prRemapped);

  TPixmapRequest = record
    Snapshot: TWindowSnapshot;
    Reason  : TPixmapReason;
  end;
  TPixmapRequestArray = array of TPixmapRequest;

  TPixmapPlan = record
    Requests: TPixmapRequestArray;   // windows to name now
    Drops   : array of Cardinal;     // windows whose name must be freed
  end;

  TWindowPixmapStore = class
  protected
    FConn   : Pxcb_connection_t;
    FEntries: TWindowPixmapEntryArray;

    // Names the window's pixmap. Returns 0 when the server refuses, which happens for a
    // window that is not redirected. Overridden by the test double.
    function NamePixmap(const AWindow: Cardinal): xcb_pixmap_t; virtual;
    // Releases a name. Virtual for the same reason as NamePixmap: a test needs to see
    // that the old name was freed, not merely replaced, or a leak is invisible.
    procedure FreePixmap(const APixmap: xcb_pixmap_t); virtual;
  public
    constructor Create(AConn: Pxcb_connection_t);
    destructor Destroy(); override;

    // Brings the held names in line with what was seen. Frees names for windows that
    // are gone, and re-captures the ones that resized or were re-mapped.
    procedure Refresh(const ANow: TWindowSnapshotArray);

    // The pixmap to composite from, with the bounds it was captured at. False when the
    // window has no name, which means it has never been seen mapped.
    function Lookup(const AWindow: Cardinal; out APixmap: xcb_pixmap_t;
                    out AWidth, AHeight: Integer): Boolean;

    function Count(): Integer;
    function Entries(): TWindowPixmapEntryArray;
    // Frees every name without touching the server's windows.
    procedure Clear();
  end;

  { A store that never talks to the server, for testing the lifetime rules. }
  TDebugWindowPixmapStore = class(TWindowPixmapStore)
  public
    NamedWindows : array of Cardinal;   // every window NamePixmap was called for
    RefuseFor    : array of Cardinal;   // windows the fake server refuses
    FreedPixmaps : array of xcb_pixmap_t;
    NextFakeId   : xcb_pixmap_t;
    constructor Create();
    procedure Refuse(AWindow: Cardinal);
    function FreedCount(): Integer;
  protected
    function NamePixmap(const AWindow: Cardinal): xcb_pixmap_t; override;
    procedure FreePixmap(const APixmap: xcb_pixmap_t); override;
  end;

  { Decides what to name and what to free. Pure: no X calls, no state. }
  function PlanPixmapRefresh(const AEntries: TWindowPixmapEntryArray;
                             const ANow: TWindowSnapshotArray): TPixmapPlan;

  { Batched geometry and map state for AWindows. Two round trips for the whole set. }
  function QueryWindowSnapshots(AConn: Pxcb_connection_t;
                                const AWindows: array of Cardinal): TWindowSnapshotArray;

implementation

// XCB allocates reply buffers with malloc, so FreeMem would corrupt the heap. The WM unit
// declares the same binding privately; there is no shared home for it yet.
procedure XcbFreeReply(P: Pointer); cdecl; external 'c' name 'free';

function PlanPixmapRefresh(const AEntries: TWindowPixmapEntryArray;
  const ANow: TWindowSnapshotArray): TPixmapPlan;
var
  i, j: Integer;
  found: Boolean;
begin
  Result.Requests := nil;
  Result.Drops := nil;

  for i := 0 to High(ANow) do
  begin
    found := False;
    for j := 0 to High(AEntries) do
      if AEntries[j].Window = ANow[i].Window then
      begin
        found := True;

        // A resize replaces the window's storage: the held name keeps the old contents
        // and, worse, the old bounds. Re-capture, but only while the window is mapped:
        // naming an unmapped window is refused, and the re-map rule below will catch it.
        if (AEntries[j].Width <> ANow[i].Width) or
           (AEntries[j].Height <> ANow[i].Height) then
        begin
          if ANow[i].Mapped then
          begin
            SetLength(Result.Requests, Length(Result.Requests) + 1);
            Result.Requests[High(Result.Requests)].Snapshot := ANow[i];
            Result.Requests[High(Result.Requests)].Reason := prResized;
          end;
        end
        // A re-map also replaces the storage. Size alone cannot detect this: a window
        // that is minimized and restored comes back the same size, but its old name is
        // frozen at the frame before the minimize.
        else if ANow[i].Mapped and not AEntries[j].WasMapped then
        begin
          SetLength(Result.Requests, Length(Result.Requests) + 1);
          Result.Requests[High(Result.Requests)].Snapshot := ANow[i];
          Result.Requests[High(Result.Requests)].Reason := prRemapped;
        end;

        Break;
      end;

    if not found and ANow[i].Mapped then
    begin
      SetLength(Result.Requests, Length(Result.Requests) + 1);
      Result.Requests[High(Result.Requests)].Snapshot := ANow[i];
      Result.Requests[High(Result.Requests)].Reason := prNew;
    end;
  end;

  // Anything held for a window that is no longer in the list is a leak: a named pixmap
  // outlives the window it came from.
  for j := 0 to High(AEntries) do
  begin
    found := False;
    for i := 0 to High(ANow) do
      if ANow[i].Window = AEntries[j].Window then
      begin
        found := True;
        Break;
      end;

    if not found then
    begin
      SetLength(Result.Drops, Length(Result.Drops) + 1);
      Result.Drops[High(Result.Drops)] := AEntries[j].Window;
    end;
  end;
end;

function QueryWindowSnapshots(AConn: Pxcb_connection_t;
  const AWindows: array of Cardinal): TWindowSnapshotArray;
var
  i, n: Integer;
  geomCookies: array of xcb_get_geometry_cookie_t;
  attrCookies: array of xcb_get_window_attributes_cookie_t;
  geom: Pxcb_get_geometry_reply_t;
  attr: Pxcb_get_window_attributes_reply_t;
begin
  Result := nil;
  n := Length(AWindows);
  if (AConn = nil) or (n = 0) then Exit;

  SetLength(Result, n);
  SetLength(geomCookies, n);
  SetLength(attrCookies, n);

  // Send everything first, then read everything. Interleaving would be one round trip
  // per window, and this runs on the dock's 250ms tick.
  for i := 0 to n - 1 do
  begin
    geomCookies[i] := xcb_get_geometry(AConn, AWindows[i]);
    attrCookies[i] := xcb_get_window_attributes(AConn, AWindows[i]);
  end;

  for i := 0 to n - 1 do
  begin
    Result[i].Window := AWindows[i];
    Result[i].Width := 0;
    Result[i].Height := 0;
    Result[i].Mapped := False;

    geom := xcb_get_geometry_reply(AConn, geomCookies[i], nil);
    if geom <> nil then
    begin
      Result[i].Width := geom^.width;
      Result[i].Height := geom^.height;
      XcbFreeReply(geom);
    end;

    attr := xcb_get_window_attributes_reply(AConn, attrCookies[i], nil);
    if attr <> nil then
    begin
      Result[i].Mapped := (attr^.map_state = XCB_MAP_STATE_VIEWABLE);
      XcbFreeReply(attr);
    end;
  end;
end;

constructor TWindowPixmapStore.Create(AConn: Pxcb_connection_t);
begin
  inherited Create();
  FConn := AConn;
  FEntries := nil;
end;

destructor TWindowPixmapStore.Destroy();
begin
  Clear();
  inherited Destroy();
end;

function TWindowPixmapStore.NamePixmap(const AWindow: Cardinal): xcb_pixmap_t;
begin
  Result := 0;
  if (FConn = nil) or (AWindow = 0) then Exit;

  Result := xcb_generate_id(FConn);
  xcb_composite_name_window_pixmap(FConn, xcb_window_t(AWindow), Result);
end;

procedure TWindowPixmapStore.FreePixmap(const APixmap: xcb_pixmap_t);
begin
  if (FConn <> nil) and (APixmap <> 0) then
    xcb_free_pixmap(FConn, APixmap);
end;

procedure TWindowPixmapStore.Refresh(const ANow: TWindowSnapshotArray);
var
  plan: TPixmapPlan;
  i, j, k, shift: Integer;
  newPixmap: xcb_pixmap_t;
begin
  plan := PlanPixmapRefresh(FEntries, ANow);

  // Drops first, so a window that was replaced does not briefly hold two names.
  for i := 0 to High(plan.Drops) do
    for j := 0 to High(FEntries) do
      if FEntries[j].Window = plan.Drops[i] then
      begin
        FreePixmap(FEntries[j].Pixmap);
        for shift := j to High(FEntries) - 1 do
          FEntries[shift] := FEntries[shift + 1];
        SetLength(FEntries, Length(FEntries) - 1);
        Break;
      end;

  // Then the captures.
  for i := 0 to High(plan.Requests) do
  begin
    j := -1;
    for k := 0 to High(FEntries) do
      if FEntries[k].Window = plan.Requests[i].Snapshot.Window then
      begin
        j := k;
        Break;
      end;

    newPixmap := NamePixmap(plan.Requests[i].Snapshot.Window);

    if j >= 0 then
    begin
      // Replace an existing name. The old one must go whether or not the new one
      // worked, otherwise a resize that fails to re-capture leaks the old pixmap.
      FreePixmap(FEntries[j].Pixmap);
      FEntries[j].Pixmap := newPixmap;
      FEntries[j].Width := plan.Requests[i].Snapshot.Width;
      FEntries[j].Height := plan.Requests[i].Snapshot.Height;
      FEntries[j].WasMapped := True;
    end
    else if newPixmap <> 0 then
    begin
      SetLength(FEntries, Length(FEntries) + 1);
      j := High(FEntries);
      FEntries[j].Window := plan.Requests[i].Snapshot.Window;
      FEntries[j].Pixmap := newPixmap;
      FEntries[j].Width := plan.Requests[i].Snapshot.Width;
      FEntries[j].Height := plan.Requests[i].Snapshot.Height;
      FEntries[j].WasMapped := True;
    end;
  end;

  // Record the map state of every window still held, so the next refresh can tell a
  // minimize from a restore. This has to happen after the captures above, or a window
  // captured this pass would look like it had just been re-mapped next pass.
  for j := 0 to High(FEntries) do
    for i := 0 to High(ANow) do
      if ANow[i].Window = FEntries[j].Window then
      begin
        FEntries[j].WasMapped := ANow[i].Mapped;
        Break;
      end;
end;

function TWindowPixmapStore.Lookup(const AWindow: Cardinal; out APixmap: xcb_pixmap_t;
  out AWidth, AHeight: Integer): Boolean;
var
  i: Integer;
begin
  APixmap := 0;
  AWidth := 0;
  AHeight := 0;
  Result := False;

  for i := 0 to High(FEntries) do
    if FEntries[i].Window = AWindow then
    begin
      APixmap := FEntries[i].Pixmap;
      AWidth := FEntries[i].Width;
      AHeight := FEntries[i].Height;
      Exit(FEntries[i].Pixmap <> 0);
    end;
end;

function TWindowPixmapStore.Count(): Integer;
begin
  Result := Length(FEntries);
end;

function TWindowPixmapStore.Entries(): TWindowPixmapEntryArray;
begin
  Result := Copy(FEntries);
end;

procedure TWindowPixmapStore.Clear();
var
  i: Integer;
begin
  for i := 0 to High(FEntries) do
    FreePixmap(FEntries[i].Pixmap);
  SetLength(FEntries, 0);
end;

constructor TDebugWindowPixmapStore.Create();
begin
  inherited Create(nil);
  NextFakeId := 1000;
end;

procedure TDebugWindowPixmapStore.Refuse(AWindow: Cardinal);
begin
  SetLength(RefuseFor, Length(RefuseFor) + 1);
  RefuseFor[High(RefuseFor)] := AWindow;
end;

function TDebugWindowPixmapStore.FreedCount(): Integer;
begin
  Result := Length(FreedPixmaps);
end;

procedure TDebugWindowPixmapStore.FreePixmap(const APixmap: xcb_pixmap_t);
begin
  if APixmap = 0 then Exit;
  SetLength(FreedPixmaps, Length(FreedPixmaps) + 1);
  FreedPixmaps[High(FreedPixmaps)] := APixmap;
end;

function TDebugWindowPixmapStore.NamePixmap(const AWindow: Cardinal): xcb_pixmap_t;
var
  i: Integer;
begin
  SetLength(NamedWindows, Length(NamedWindows) + 1);
  NamedWindows[High(NamedWindows)] := AWindow;

  for i := 0 to High(RefuseFor) do
    if RefuseFor[i] = AWindow then
      Exit(0);

  Result := NextFakeId;
  Inc(NextFakeId);
end;

end.
