unit ShellSama.Test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  ShellSama.Panel;

type
  TShellSamaTest = class(TTestCase)
  published
    procedure TestPanelCreation();
    procedure TestTopPanelGeometryAndStruts();
    procedure TestBottomPanelGeometryAndStruts();
    procedure TestPanelAutoHideStruts();
  end;

implementation

procedure TShellSamaTest.TestPanelCreation();
var
  panel: TShellPanel;
begin
  panel := TShellPanel.Create(1920, 1080);
  try
    AssertNotNull('Panel created', panel);
    AssertEquals('Default screen width', 1920, panel.ScreenWidth);
    AssertEquals('Default screen height', 1080, panel.ScreenHeight);
    AssertEquals('Default panel height', 38, panel.Config.Height);
    AssertEquals('Default theme', 'Amamizu', panel.Config.ThemeName);
    AssertTrue('Panel visible by default', panel.IsVisible);
  finally
    panel.Free();
  end;
end;

procedure TShellSamaTest.TestTopPanelGeometryAndStruts();
var
  panel: TShellPanel;
  cfg: TShellPanelConfig;
  strut: TShellStrut;
begin
  cfg := TShellPanelConfig.Create(sppTop, 40, 'LiquidGlass');
  panel := TShellPanel.Create(1280, 720, cfg);
  try
    AssertEquals('Top panel X', 0, panel.PanelX());
    AssertEquals('Top panel Y', 0, panel.PanelY());
    AssertEquals('Top panel width', 1280, panel.PanelWidth());
    AssertEquals('Top panel height', 40, panel.PanelHeight());

    strut := panel.ComputeStrut();
    AssertEquals('Strut top margin', 40, strut.Top);
    AssertEquals('Strut bottom margin', 0, strut.Bottom);
    AssertEquals('Strut top start X', 0, strut.TopStartX);
    AssertEquals('Strut top end X', 1279, strut.TopEndX);
  finally
    panel.Free();
  end;
end;

procedure TShellSamaTest.TestBottomPanelGeometryAndStruts();
var
  panel: TShellPanel;
  cfg: TShellPanelConfig;
  strut: TShellStrut;
begin
  cfg := TShellPanelConfig.Create(sppBottom, 44, 'Dark');
  panel := TShellPanel.Create(1920, 1080, cfg);
  try
    AssertEquals('Bottom panel X', 0, panel.PanelX());
    AssertEquals('Bottom panel Y', 1080 - 44, panel.PanelY());
    AssertEquals('Bottom panel width', 1920, panel.PanelWidth());
    AssertEquals('Bottom panel height', 44, panel.PanelHeight());

    strut := panel.ComputeStrut();
    AssertEquals('Strut top margin', 0, strut.Top);
    AssertEquals('Strut bottom margin', 44, strut.Bottom);
    AssertEquals('Strut bottom start X', 0, strut.BottomStartX);
    AssertEquals('Strut bottom end X', 1919, strut.BottomEndX);
  finally
    panel.Free();
  end;
end;

procedure TShellSamaTest.TestPanelAutoHideStruts();
var
  panel: TShellPanel;
  cfg: TShellPanelConfig;
  strut: TShellStrut;
begin
  cfg := TShellPanelConfig.Create(sppTop, 36);
  cfg.AutoHide := True;
  panel := TShellPanel.Create(1280, 720, cfg);
  try
    strut := panel.ComputeStrut();
    AssertEquals('AutoHide reserves 0 top strut', 0, strut.Top);
    AssertEquals('AutoHide reserves 0 bottom strut', 0, strut.Bottom);
  finally
    panel.Free();
  end;
end;

initialization
  RegisterTest(TShellSamaTest);

end.
