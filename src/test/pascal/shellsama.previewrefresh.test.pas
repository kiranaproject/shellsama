unit ShellSama.PreviewRefresh.Test;

// Tests for the live-refresh timing rule.
//
// Only the timing is unit-testable: it is the part with a real trap (QWord subtraction
// underflow) and no X involvement. Whether the sheet actually updates is a live-server
// question, covered by scripts/probe-refresh-cost.py and the popup probe.

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  ShellSama.PreviewRefresh;

type
  TPreviewRefreshTest = class(TTestCase)
  published
    procedure TestFirstRefreshIsDue();
    procedure TestTooSoonIsNotDue();
    procedure TestExactlyTheIntervalIsDue();
    procedure TestAClockThatGoesBackwardsDoesNotRefresh();
    procedure TestZeroIntervalRefreshesEveryTick();
  end;

implementation

procedure TPreviewRefreshTest.TestFirstRefreshIsDue();
var
  state: TPreviewRefreshState;
begin
  // Nothing has been drawn yet, so the first tick must refresh immediately rather than
  // leave the popup showing its initial sheet for a further interval.
  state := PreviewRefreshStateInit();
  AssertTrue('a fresh state is due', PreviewRefreshDue(state, 1000));
  AssertEquals('and the timestamp moved', QWord(1000), state.LastMs);

  // The same must hold when the clock is small. This is the case a missing first-call
  // special case gets wrong: with LastMs starting at 0, a large ANowMs looks like a long
  // interval has elapsed and passes anyway, so only a small ANowMs exposes it.
  state := PreviewRefreshStateInit();
  AssertTrue('a fresh state is due even at a small clock',
             PreviewRefreshDue(state, 20));
  AssertEquals('and the timestamp moved there too', QWord(20), state.LastMs);
end;

procedure TPreviewRefreshTest.TestTooSoonIsNotDue();
var
  state: TPreviewRefreshState;
begin
  state := PreviewRefreshStateInit();
  PreviewRefreshDue(state, 1000);

  AssertFalse('50ms later is not due', PreviewRefreshDue(state, 1050));
  AssertEquals('and nothing changed', QWord(1000), state.LastMs);
end;

procedure TPreviewRefreshTest.TestExactlyTheIntervalIsDue();
var
  state: TPreviewRefreshState;
begin
  state := PreviewRefreshStateInit();
  PreviewRefreshDue(state, 1000);

  // The boundary is inclusive: an interval of exactly the threshold is due, or a
  // 100ms timer would fire every other tick at 100ms.
  AssertTrue('exactly the interval later is due',
             PreviewRefreshDue(state, 1000 + PREVIEW_REFRESH_MS));
end;

procedure TPreviewRefreshTest.TestAClockThatGoesBackwardsDoesNotRefresh();
var
  state: TPreviewRefreshState;
begin
  // GetTickCount64 is monotonic, but the timestamp is passed in and a caller could hand
  // over something else. Without the explicit check, `ANow < Last` underflows in QWord
  // arithmetic to a huge number and every subsequent tick refreshes at full rate.
  state := PreviewRefreshStateInit();
  PreviewRefreshDue(state, 5000);

  AssertFalse('a backwards clock does not refresh', PreviewRefreshDue(state, 4000));
  AssertEquals('and the timestamp is kept', QWord(5000), state.LastMs);
end;

procedure TPreviewRefreshTest.TestZeroIntervalRefreshesEveryTick();
var
  state: TPreviewRefreshState;
begin
  // Interval 0 is the "as often as asked" case, which the live check uses to avoid
  // waiting. It must not be treated as "never".
  state := PreviewRefreshStateInit();
  AssertTrue('first is due', PreviewRefreshDue(state, 1000, 0));
  AssertTrue('and the next tick is due immediately', PreviewRefreshDue(state, 1000, 0));
end;

initialization
  RegisterTest(TPreviewRefreshTest);

end.
