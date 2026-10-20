unit ShellSama.Desktop.Test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  ftpas.api, ftpas.types, ftpas,
  ShellSama.Desktop;

type
  TDesktopTest = class(TTestCase)
  private
    FDesktop: TShellDesktop;
  protected
    procedure SetUp(); override;
    procedure TearDown(); override;
  published
    procedure TestDesktopCreationAndGeometry();
    procedure TestWallpaperModes();
    procedure TestSetSolidColor();
    procedure TestSetWallpaperAndFallback();
    procedure TestDesktopVisibilityToggle();
  end;

implementation

procedure TDesktopTest.SetUp();
begin
  if not FtIsLibLoaded() then
  begin
    if not FtLoadLib() then
      Fail('Could not load libft.so');
  end;

  try
    FtApp().Initialize();
  except
    on E: Exception do
      Fail('FtApp.Initialize failed: ' + E.Message);
  end;

  FDesktop := TShellDesktop.Create();
end;

procedure TDesktopTest.TearDown();
begin
  if Assigned(FDesktop) then
  begin
    FDesktop.Free();
    FDesktop := nil;
  end;
end;

procedure TDesktopTest.TestDesktopCreationAndGeometry();
var
  sw, sh: Integer;
begin
  AssertNotNull('Desktop instance should be created', FDesktop);
  sw := FtApp().ScreenWidth;
  sh := FtApp().ScreenHeight;

  AssertEquals('Desktop Width must match screen width', sw, FDesktop.Width);
  AssertEquals('Desktop Height must match screen height', sh, FDesktop.Height);
  AssertNotNull('Desktop Window must be created', FDesktop.Window);
  AssertEquals('WindowType must be ftwtDesktop', Ord(ftwtDesktop), Ord(FDesktop.Window.WindowType));
  AssertTrue('Window must be borderless', FDesktop.Window.Borderless);
  AssertTrue('Window must skip taskbar', FDesktop.Window.SkipTaskbar);
  AssertNotNull('Drawing area must be created', FDesktop.DrawingArea);
end;

procedure TDesktopTest.TestWallpaperModes();
begin
  FDesktop.WallpaperMode := wmFill;
  AssertEquals('Mode should be wmFill', Ord(wmFill), Ord(FDesktop.WallpaperMode));

  FDesktop.WallpaperMode := wmFit;
  AssertEquals('Mode should be wmFit', Ord(wmFit), Ord(FDesktop.WallpaperMode));

  FDesktop.WallpaperMode := wmStretch;
  AssertEquals('Mode should be wmStretch', Ord(wmStretch), Ord(FDesktop.WallpaperMode));

  FDesktop.WallpaperMode := wmCenter;
  AssertEquals('Mode should be wmCenter', Ord(wmCenter), Ord(FDesktop.WallpaperMode));

  FDesktop.WallpaperMode := wmTile;
  AssertEquals('Mode should be wmTile', Ord(wmTile), Ord(FDesktop.WallpaperMode));

  FDesktop.WallpaperMode := wmSolidColor;
  AssertEquals('Mode should be wmSolidColor', Ord(wmSolidColor), Ord(FDesktop.WallpaperMode));
end;

procedure TDesktopTest.TestSetSolidColor();
begin
  FDesktop.SetSolidColor(0.2, 0.3, 0.4);
  // Verify method runs without error and triggers repaint
  AssertNotNull(FDesktop.Window);
end;

procedure TDesktopTest.TestSetWallpaperAndFallback();
begin
  // Non-existent path should be handled gracefully without exception
  FDesktop.SetWallpaper('/path/to/nonexistent/image.png');
  AssertEquals('Nonexistent path leaves WallpaperPath empty', '', FDesktop.WallpaperPath);
  AssertNull('Nonexistent path leaves WallpaperBitmap nil', FDesktop.WallpaperBitmap);
end;

procedure TDesktopTest.TestDesktopVisibilityToggle();
begin
  AssertFalse('Desktop initially not visible', FDesktop.IsVisible);

  FDesktop.Show();
  AssertTrue('Desktop is visible after Show()', FDesktop.IsVisible);

  FDesktop.Hide();
  AssertFalse('Desktop is not visible after Hide()', FDesktop.IsVisible);
end;

initialization
  RegisterTest(TDesktopTest);

end.
