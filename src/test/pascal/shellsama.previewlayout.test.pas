unit ShellSama.PreviewLayout.Test;

// Tests for the preview popup's geometry.
//
// Pure arithmetic, so these run without a display and without libft. The expected sizes
// are the ones docs/window-previews.md §5.2 publishes, so a change in the constants has
// to update the document as well as the test.

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  ShellSama.PreviewLayout;

type
  TPreviewLayoutTest = class(TTestCase)
  published
    procedure TestPublishedSizes();
    procedure TestZeroWindowsHasNoLayout();
    procedure TestTilesAreLaidOutInReadingOrder();
    procedure TestHitTestCoversTileAndTitle();
    procedure TestHitTestRejectsTheGaps();
    procedure TestTallRuleAddsColumnsBeforeOverflowing();
    procedure TestWideRuleDropsColumns();
    procedure TestAnchorIsCentredOnTheIcon();
    procedure TestAnchorStaysOnScreen();
    procedure TestAnchorStaysBelowTheTopInset();
  end;

implementation

procedure TPreviewLayoutTest.TestPublishedSizes();
var
  l: TPreviewLayout;

  procedure Expect(ACount, ACols, ARows, AW, AH: Integer);
  begin
    l := PreviewLayoutFor(ACount, 1920, 4000);   // tall and wide rules cannot interfere
    AssertEquals(Format('%d windows: columns', [ACount]), ACols, l.Columns);
    AssertEquals(Format('%d windows: rows', [ACount]), ARows, l.Rows);
    AssertEquals(Format('%d windows: width', [ACount]), AW, l.Width);
    AssertEquals(Format('%d windows: height', [ACount]), AH, l.Height);
  end;

begin
  Expect(1, 1, 1, 232, 163);
  Expect(2, 2, 1, 450, 163);
  Expect(3, 3, 1, 668, 163);
  Expect(4, 4, 1, 886, 163);
  Expect(5, 4, 2, 886, 314);
  Expect(8, 4, 2, 886, 314);
  Expect(9, 4, 3, 886, 465);
  Expect(12, 4, 3, 886, 465);
end;

procedure TPreviewLayoutTest.TestZeroWindowsHasNoLayout();
var
  l: TPreviewLayout;
begin
  l := PreviewLayoutFor(0, 1920, 1000);
  AssertEquals('no columns', 0, l.Columns);
  AssertEquals('no rows', 0, l.Rows);
  AssertEquals('no width', 0, l.Width);
  AssertEquals('no height', 0, l.Height);
end;

procedure TPreviewLayoutTest.TestTilesAreLaidOutInReadingOrder();
var
  l: TPreviewLayout;
  r0, r1, r2, r3, r4: TPreviewRect;
begin
  l := PreviewLayoutFor(5, 1920, 4000);

  r0 := PreviewTileRect(l, 0);
  r1 := PreviewTileRect(l, 1);
  r4 := PreviewTileRect(l, 4);

  AssertEquals('first tile starts at the padding', PREVIEW_PAD, r0.X);
  AssertEquals('and at the padding vertically', PREVIEW_PAD, r0.Y);

  // Second tile is one tile plus one gap to the right, same row.
  AssertEquals('second tile is to the right', r0.X + PREVIEW_W + PREVIEW_GAP_X, r1.X);
  AssertEquals('second tile is on the same row', r0.Y, r1.Y);

  // Fifth tile wraps to the second row, first column.
  AssertEquals('fifth tile is at the left', r0.X, r4.X);
  AssertEquals('fifth tile is one cell down', r0.Y + PREVIEW_CELL_H + PREVIEW_GAP_Y, r4.Y);

  // The last row must fit inside the popup height, or the bottom row is clipped.
  r2 := PreviewTileRect(l, 2);
  r3 := PreviewTileRect(l, 3);
  AssertTrue('row one fits inside the popup', r2.Y + PREVIEW_CELL_H <= l.Height);
  AssertTrue('row two fits inside the popup', r4.Y + PREVIEW_CELL_H <= l.Height);
  AssertTrue('and nothing overflows to the right', r3.X + PREVIEW_W <= l.Width);
end;

procedure TPreviewLayoutTest.TestHitTestCoversTileAndTitle();
var
  l: TPreviewLayout;
  tile, title: TPreviewRect;
begin
  l := PreviewLayoutFor(3, 1920, 4000);

  tile := PreviewTileRect(l, 1);
  AssertEquals('the middle of a tile hits it', 1,
               PreviewHitTest(l, tile.X + tile.W div 2, tile.Y + tile.H div 2));

  // The title belongs to its tile. Clicking a caption must activate that window, not
  // nothing: the caption is the widest part of the target.
  title := PreviewTitleRect(l, 1);
  AssertEquals('the caption hits the same tile', 1,
               PreviewHitTest(l, title.X + title.W div 2, title.Y + title.H div 2));

  AssertEquals('the very first pixel hits tile 0', 0,
               PreviewHitTest(l, PREVIEW_PAD, PREVIEW_PAD));
end;

procedure TPreviewLayoutTest.TestHitTestRejectsTheGaps();
var
  l: TPreviewLayout;
  tile0: TPreviewRect;
begin
  l := PreviewLayoutFor(4, 1920, 4000);
  tile0 := PreviewTileRect(l, 0);

  // Between two tiles.
  AssertEquals('the gap between columns is not a target', -1,
               PreviewHitTest(l, tile0.X + PREVIEW_W + 1, tile0.Y + 10));

  // Inside the padding.
  AssertEquals('the left padding is not a target', -1, PreviewHitTest(l, 2, 40));
  AssertEquals('the top padding is not a target', -1, PreviewHitTest(l, 40, 2));

  // Outside the popup entirely.
  AssertEquals('past the right edge is not a target', -1,
               PreviewHitTest(l, l.Width + 5, 40));
  AssertEquals('past the bottom edge is not a target', -1,
               PreviewHitTest(l, 40, l.Height + 5));
end;

procedure TPreviewLayoutTest.TestTallRuleAddsColumnsBeforeOverflowing();
var
  l: TPreviewLayout;
begin
  // Twelve windows want 4x3 = 465px. With only 350px of room the grid must lose a row
  // by widening to 6 columns, which gives 6x2 = 314px.
  l := PreviewLayoutFor(12, 1920, 350);
  AssertEquals('widened to six columns', 6, l.Columns);
  AssertEquals('two rows', 2, l.Rows);
  AssertTrue('and it now fits', l.Height <= 350);

  // Nine windows: 4x3 needs 465, but 5 columns gives 5x2 = 314, so 5 is enough and the
  // rule must stop there rather than jumping to 6.
  l := PreviewLayoutFor(9, 1920, 350);
  AssertEquals('widened only as far as needed', 5, l.Columns);
  AssertEquals('two rows', 2, l.Rows);

  // With plenty of room the rule does nothing.
  l := PreviewLayoutFor(12, 1920, 4000);
  AssertEquals('stays at four columns when it fits', 4, l.Columns);
end;

procedure TPreviewLayoutTest.TestWideRuleDropsColumns();
var
  l: TPreviewLayout;
begin
  // The tall rule widened the grid, and now it is too wide for a narrow screen.
  l := PreviewLayoutFor(12, 900, 350);
  AssertTrue('the grid fits the screen', l.Width <= 900 - 2 * PREVIEW_SCREEN_EDGE);
  AssertTrue('and still has at least one column', l.Columns >= 1);

  // Four tiles on a screen narrower than one four-column grid.
  l := PreviewLayoutFor(4, 700, 4000);
  AssertTrue('narrowed to fit', l.Width <= 700 - 2 * PREVIEW_SCREEN_EDGE);
  AssertEquals('which takes fewer columns', 3, l.Columns);
end;

procedure TPreviewLayoutTest.TestAnchorIsCentredOnTheIcon();
var
  l: TPreviewLayout;
  x: Integer;
begin
  l := PreviewLayoutFor(2, 1920, 4000);
  x := PreviewAnchorX(l, 960, 1920);
  AssertEquals('centred on the icon', 960 - (l.Width div 2), x);
end;

procedure TPreviewLayoutTest.TestAnchorStaysOnScreen();
var
  l: TPreviewLayout;
begin
  l := PreviewLayoutFor(4, 1920, 4000);

  // An icon hard against the left edge would push the popup off screen.
  AssertEquals('clamped to the left edge', PREVIEW_SCREEN_EDGE,
               PreviewAnchorX(l, 2, 1920));

  // And against the right edge.
  AssertEquals('clamped to the right edge', 1920 - PREVIEW_SCREEN_EDGE - l.Width,
               PreviewAnchorX(l, 1918, 1920));

  // An icon in the middle is untouched.
  AssertTrue('a centred icon is not clamped',
             PreviewAnchorX(l, 960, 1920) > PREVIEW_SCREEN_EDGE);
end;

procedure TPreviewLayoutTest.TestAnchorStaysBelowTheTopInset();
var
  l: TPreviewLayout;
begin
  l := PreviewLayoutFor(2, 1920, 4000);

  // Plenty of room: it sits above the icon.
  AssertEquals('above the icon', 700 - l.Height - PREVIEW_ICON_CLEARANCE,
               PreviewAnchorY(l, 700, 38));

  // Not enough room: it must not go under the top panel.
  AssertEquals('clamped below the top inset', 38, PreviewAnchorY(l, 100, 38));
end;

initialization
  RegisterTest(TPreviewLayoutTest);

end.
