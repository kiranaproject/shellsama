{ Unit ShellSama.PreviewRefresh — the timing rule for live previews.

  Separated from the popup so the rule can be tested without a window. It is small, but
  it has the two failure modes that live timing usually has:

    - an unsigned subtraction that underflows when the clock is not monotonic, turning
      "no time has passed" into "a very long time has passed";
    - an off-by-one at the interval boundary that halves the effective refresh rate.

  Neither would be caught by watching a preview, because both look like normal operation
  from the outside. }

unit ShellSama.PreviewRefresh;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

const
  { Minimum time between refreshes, in milliseconds. Measured: a full eight-tile sheet
    costs ~2.3ms to rebuild (scripts/probe-refresh-cost.py), so ten per second is a few
    percent of one core. Faster buys nothing, because preview content changes at human
    speed. }
  PREVIEW_REFRESH_MS = 100;

type
  TPreviewRefreshState = record
    LastMs: QWord;
    Started: Boolean;
  end;

function PreviewRefreshStateInit(): TPreviewRefreshState;

{ True when a refresh is due at ANowMs. Updates AState when it returns True.

  The first call is always due: a popup that waited a whole interval before its first
  live update would look frozen on opening. }
function PreviewRefreshDue(var AState: TPreviewRefreshState; ANowMs: QWord;
  AIntervalMs: Cardinal = PREVIEW_REFRESH_MS): Boolean;

implementation

function PreviewRefreshStateInit(): TPreviewRefreshState;
begin
  Result.LastMs := 0;
  Result.Started := False;
end;

function PreviewRefreshDue(var AState: TPreviewRefreshState; ANowMs: QWord;
  AIntervalMs: Cardinal): Boolean;
begin
  Result := False;

  if not AState.Started then
  begin
    AState.Started := True;
    AState.LastMs := ANowMs;
    Exit(True);
  end;

  // Checked before the subtraction. In QWord arithmetic `ANowMs - AState.LastMs` with
  // ANowMs < LastMs wraps to a number near 2^64, which is larger than any interval, so
  // the guard below would say "due" on every tick until the clock caught up.
  if ANowMs < AState.LastMs then Exit;

  // Inclusive: exactly one interval later is due. A strict comparison would make a 100ms
  // timer with 100ms of work refresh every other tick.
  if ANowMs - AState.LastMs < AIntervalMs then Exit;

  AState.LastMs := ANowMs;
  Result := True;
end;

end.
