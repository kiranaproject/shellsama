unit ShellSama.WindowPixmaps.Test;

// Tests for the per-window pixmap lifetime.
//
// The rules are the whole risk here: a wrong one shows up as a preview of a minimized
// window that is blank, a preview that freezes after a resize, or a pixmap leak. They are
// tested as a pure function and through a store that never contacts the server, so the
// assertions describe the behaviour rather than the X calls.
//
// What is NOT tested here is that the X server agrees. scripts/probe-window-pixmap.py
// covers that, and docs/window-previews.md §7.5 records the measurements.

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  Floria.XCB,
  ShellSama.WindowPixmaps;

type
  TWindowPixmapsTest = class(TTestCase)
  private
    function Snap(AWindow: Cardinal; AWidth, AHeight: Integer;
                  AMapped: Boolean = True): TWindowSnapshot;
    function Entry(AWindow: Cardinal; AWidth, AHeight: Integer;
                   AWasMapped: Boolean = True): TWindowPixmapEntry;
  published
    procedure TestNewMappedWindowIsCaptured();
    procedure TestNewUnmappedWindowIsNotCaptured();
    procedure TestResizeRecaptures();
    procedure TestRemapRecapturesEvenAtTheSameSize();
    procedure TestMinimizeKeepsTheLastFrame();
    procedure TestUnchangedWindowIsNotRecaptured();
    procedure TestDepartedWindowIsDropped();
    procedure TestResizeWhileMinimizedWaitsForTheRemap();

    procedure TestStoreCapturesAndLooksUp();
    procedure TestStoreReplacesTheNameOnResize();
    procedure TestStoreKeepsTheNameAcrossAMinimize();
    procedure TestStoreFreesOnDeparture();
    procedure TestStoreDoesNotHoldARefusedName();
    procedure TestStoreClearFreesEverything();
  end;

implementation

function TWindowPixmapsTest.Snap(AWindow: Cardinal; AWidth, AHeight: Integer;
  AMapped: Boolean): TWindowSnapshot;
begin
  Result.Window := AWindow;
  Result.Width := AWidth;
  Result.Height := AHeight;
  Result.Mapped := AMapped;
end;

function TWindowPixmapsTest.Entry(AWindow: Cardinal; AWidth, AHeight: Integer;
  AWasMapped: Boolean): TWindowPixmapEntry;
begin
  Result.Window := AWindow;
  Result.Pixmap := 500 + AWindow;
  Result.Width := AWidth;
  Result.Height := AHeight;
  Result.WasMapped := AWasMapped;
end;

procedure TWindowPixmapsTest.TestNewMappedWindowIsCaptured();
var
  entries: TWindowPixmapEntryArray;
  now: TWindowSnapshotArray;
  plan: TPixmapPlan;
begin
  entries := nil;
  SetLength(now, 1);
  now[0] := Snap(11, 800, 600);

  plan := PlanPixmapRefresh(entries, now);

  AssertEquals('one capture requested', 1, Length(plan.Requests));
  AssertEquals('for the right window', 11, plan.Requests[0].Snapshot.Window);
  AssertEquals('as a first capture', Ord(prNew), Ord(plan.Requests[0].Reason));
  AssertEquals('nothing to drop', 0, Length(plan.Drops));
end;

procedure TWindowPixmapsTest.TestNewUnmappedWindowIsNotCaptured();
var
  entries: TWindowPixmapEntryArray;
  now: TWindowSnapshotArray;
  plan: TPixmapPlan;
begin
  // Naming a pixmap for an unmapped window is refused by the server, so the plan must
  // not even ask. The window gets captured when it is first seen mapped.
  entries := nil;
  SetLength(now, 1);
  now[0] := Snap(12, 800, 600, False);

  plan := PlanPixmapRefresh(entries, now);

  AssertEquals('no capture requested', 0, Length(plan.Requests));
  AssertEquals('nothing to drop', 0, Length(plan.Drops));
end;

procedure TWindowPixmapsTest.TestResizeRecaptures();
var
  entries: TWindowPixmapEntryArray;
  now: TWindowSnapshotArray;
  plan: TPixmapPlan;
begin
  SetLength(entries, 1);
  entries[0] := Entry(13, 800, 600);
  SetLength(now, 1);
  now[0] := Snap(13, 1024, 768);

  plan := PlanPixmapRefresh(entries, now);

  AssertEquals('one capture requested', 1, Length(plan.Requests));
  AssertEquals('because the size changed', Ord(prResized), Ord(plan.Requests[0].Reason));
  AssertEquals('and nothing is dropped', 0, Length(plan.Drops));
end;

procedure TWindowPixmapsTest.TestRemapRecapturesEvenAtTheSameSize();
var
  entries: TWindowPixmapEntryArray;
  now: TWindowSnapshotArray;
  plan: TPixmapPlan;
begin
  // A window that was minimized and restored comes back at the same size, but the server
  // gave it new storage, so the held name is frozen at the frame before the minimize.
  // Size alone cannot detect this, which is why map state is recorded too.
  SetLength(entries, 1);
  entries[0] := Entry(14, 800, 600, False);
  SetLength(now, 1);
  now[0] := Snap(14, 800, 600, True);

  plan := PlanPixmapRefresh(entries, now);

  AssertEquals('one capture requested', 1, Length(plan.Requests));
  AssertEquals('because it was re-mapped', Ord(prRemapped), Ord(plan.Requests[0].Reason));
end;

procedure TWindowPixmapsTest.TestMinimizeKeepsTheLastFrame();
var
  entries: TWindowPixmapEntryArray;
  now: TWindowSnapshotArray;
  plan: TPixmapPlan;
begin
  // The whole feature depends on this: a minimized window keeps the name taken before it
  // was unmapped, and nothing is freed.
  SetLength(entries, 1);
  entries[0] := Entry(15, 800, 600, True);
  SetLength(now, 1);
  now[0] := Snap(15, 800, 600, False);

  plan := PlanPixmapRefresh(entries, now);

  AssertEquals('no capture requested', 0, Length(plan.Requests));
  AssertEquals('and the name is kept', 0, Length(plan.Drops));
end;

procedure TWindowPixmapsTest.TestUnchangedWindowIsNotRecaptured();
var
  entries: TWindowPixmapEntryArray;
  now: TWindowSnapshotArray;
  plan: TPixmapPlan;
begin
  // A steady window must not be re-captured every tick, or the dock would take a new
  // name 4 times a second forever.
  SetLength(entries, 1);
  entries[0] := Entry(16, 800, 600);
  SetLength(now, 1);
  now[0] := Snap(16, 800, 600);

  plan := PlanPixmapRefresh(entries, now);

  AssertEquals('no capture requested', 0, Length(plan.Requests));
  AssertEquals('nothing dropped', 0, Length(plan.Drops));
end;

procedure TWindowPixmapsTest.TestDepartedWindowIsDropped();
var
  entries: TWindowPixmapEntryArray;
  now: TWindowSnapshotArray;
  plan: TPixmapPlan;
begin
  // A held name outlives its window, so forgetting the window leaks the pixmap.
  SetLength(entries, 2);
  entries[0] := Entry(17, 800, 600);
  entries[1] := Entry(18, 400, 300);
  SetLength(now, 1);
  now[0] := Snap(17, 800, 600);

  plan := PlanPixmapRefresh(entries, now);

  AssertEquals('no capture requested', 0, Length(plan.Requests));
  AssertEquals('one name dropped', 1, Length(plan.Drops));
  AssertEquals('for the window that left', 18, plan.Drops[0]);
end;

procedure TWindowPixmapsTest.TestResizeWhileMinimizedWaitsForTheRemap();
var
  entries: TWindowPixmapEntryArray;
  now: TWindowSnapshotArray;
  plan: TPixmapPlan;
begin
  // A resize that arrives while the window is minimized cannot be captured, because
  // naming an unmapped window is refused. The plan must not try, and must not drop the
  // old name either: it is still the only frame there is.
  SetLength(entries, 1);
  entries[0] := Entry(19, 800, 600, False);
  SetLength(now, 1);
  now[0] := Snap(19, 1024, 768, False);

  plan := PlanPixmapRefresh(entries, now);

  AssertEquals('no capture attempted while unmapped', 0, Length(plan.Requests));
  AssertEquals('and the last frame is kept', 0, Length(plan.Drops));
end;

procedure TWindowPixmapsTest.TestStoreCapturesAndLooksUp();
var
  store: TDebugWindowPixmapStore;
  now: TWindowSnapshotArray;
  pm: xcb_pixmap_t;
  w, h: Integer;
begin
  store := TDebugWindowPixmapStore.Create();
  try
    SetLength(now, 1);
    now[0] := Snap(21, 800, 600);
    store.Refresh(now);

    AssertEquals('one name held', 1, store.Count());
    AssertTrue('the window is present', store.Lookup(21, pm, w, h));
    AssertTrue('with a pixmap', pm <> 0);
    AssertEquals('at its captured width', 800, w);
    AssertEquals('at its captured height', 600, h);

    AssertFalse('an unknown window has no name', store.Lookup(99, pm, w, h));
  finally
    store.Free();
  end;
end;

procedure TWindowPixmapsTest.TestStoreReplacesTheNameOnResize();
var
  store: TDebugWindowPixmapStore;
  now: TWindowSnapshotArray;
  before, after: xcb_pixmap_t;
  w, h: Integer;
begin
  store := TDebugWindowPixmapStore.Create();
  try
    SetLength(now, 1);
    now[0] := Snap(22, 800, 600);
    store.Refresh(now);
    store.Lookup(22, before, w, h);

    now[0] := Snap(22, 1024, 768);
    store.Refresh(now);
    store.Lookup(22, after, w, h);

    AssertTrue('the name was replaced', before <> after);
    AssertEquals('the old name was freed, not leaked', 1, store.FreedCount());
    AssertEquals('and it was the old one', before, store.FreedPixmaps[0]);
    AssertEquals('one name held, not two', 1, store.Count());
    AssertEquals('the bounds are the new ones', 1024, w);
    AssertEquals('height too', 768, h);
    AssertEquals('two captures were asked for', 2, Length(store.NamedWindows));
  finally
    store.Free();
  end;
end;

procedure TWindowPixmapsTest.TestStoreKeepsTheNameAcrossAMinimize();
var
  store: TDebugWindowPixmapStore;
  now: TWindowSnapshotArray;
  before, after: xcb_pixmap_t;
  w, h: Integer;
begin
  store := TDebugWindowPixmapStore.Create();
  try
    SetLength(now, 1);
    now[0] := Snap(23, 800, 600, True);
    store.Refresh(now);
    store.Lookup(23, before, w, h);

    // Minimized: still listed, no longer viewable.
    now[0] := Snap(23, 800, 600, False);
    store.Refresh(now);
    AssertTrue('the name is still there', store.Lookup(23, after, w, h));
    AssertEquals('and it is the same name', before, after);
    AssertEquals('still one name', 1, store.Count());

    // Restored: the server gave the window new storage, so a new name is needed.
    now[0] := Snap(23, 800, 600, True);
    store.Refresh(now);
    store.Lookup(23, after, w, h);
    AssertTrue('the restore re-captured', before <> after);
    AssertEquals('two captures in total', 2, Length(store.NamedWindows));
    AssertEquals('and the pre-minimize name was freed', 1, store.FreedCount());
  finally
    store.Free();
  end;
end;

procedure TWindowPixmapsTest.TestStoreFreesOnDeparture();
var
  store: TDebugWindowPixmapStore;
  now: TWindowSnapshotArray;
  pm: xcb_pixmap_t;
  w, h: Integer;
begin
  store := TDebugWindowPixmapStore.Create();
  try
    SetLength(now, 2);
    now[0] := Snap(24, 800, 600);
    now[1] := Snap(25, 400, 300);
    store.Refresh(now);
    AssertEquals('two names held', 2, store.Count());

    SetLength(now, 1);
    now[0] := Snap(24, 800, 600);
    store.Refresh(now);

    AssertEquals('one name left', 1, store.Count());
    AssertEquals('the name of the departed window was freed', 1, store.FreedCount());
    AssertFalse('the departed window is gone', store.Lookup(25, pm, w, h));
    AssertTrue('the survivor is still there', store.Lookup(24, pm, w, h));
  finally
    store.Free();
  end;
end;

procedure TWindowPixmapsTest.TestStoreDoesNotHoldARefusedName();
var
  store: TDebugWindowPixmapStore;
  now: TWindowSnapshotArray;
  pm: xcb_pixmap_t;
  w, h: Integer;
begin
  // The server can refuse: the window may have stopped being redirected, or unmapped
  // between the poll and the request. A refusal must leave no entry, or the dock would
  // composite from pixmap 0 and the preview would be blank forever.
  store := TDebugWindowPixmapStore.Create();
  try
    store.Refuse(26);
    SetLength(now, 1);
    now[0] := Snap(26, 800, 600);
    store.Refresh(now);

    AssertEquals('no name held', 0, store.Count());
    AssertFalse('and none to look up', store.Lookup(26, pm, w, h));
  finally
    store.Free();
  end;
end;

procedure TWindowPixmapsTest.TestStoreClearFreesEverything();
var
  store: TDebugWindowPixmapStore;
  now: TWindowSnapshotArray;
begin
  store := TDebugWindowPixmapStore.Create();
  try
    SetLength(now, 3);
    now[0] := Snap(27, 800, 600);
    now[1] := Snap(28, 640, 480);
    now[2] := Snap(29, 320, 240);
    store.Refresh(now);
    AssertEquals('three names held', 3, store.Count());

    store.Clear();
    AssertEquals('none left', 0, store.Count());
    AssertEquals('every name was freed', 3, store.FreedCount());

    // Refreshing after a clear must start over rather than trust a stale table.
    store.Refresh(now);
    AssertEquals('three names held again', 3, store.Count());
  finally
    store.Free();
  end;
end;

initialization
  RegisterTest(TWindowPixmapsTest);

end.
