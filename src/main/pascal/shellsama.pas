program shellsama;

// shellsama
// =========
// Desktop Shell for Samarinda Desktop Environment (Panels, Docks, Taskbars, Menus)

{$mode objfpc}{$H+}

uses
  SysUtils, Classes,
  ShellSama.Panel;

var
  Panel: TShellPanel;
  Config: TShellPanelConfig;
begin
  WriteLn('shellsama — Samarinda Desktop Shell');

  if (ParamCount > 0) and (ParamStr(1) = '--version') then
  begin
    WriteLn('shellsama 0.0.1-SNAPSHOT');
    Halt(0);
  end;

  Config := TShellPanelConfig.Create(sppTop, 38, 'Amamizu');
  Panel := TShellPanel.Create(1920, 1080, Config);
  try
    WriteLn('Initialized Desktop Panel:');
    WriteLn('  Geometry:  ', Panel.PanelWidth(), 'x', Panel.PanelHeight(), ' at (', Panel.PanelX(), ', ', Panel.PanelY(), ')');
    WriteLn('  Theme:     ', Panel.Config.ThemeName);
    WriteLn('  Strut Top: ', Panel.ComputeStrut().Top, ' px');
  finally
    Panel.Free();
  end;
end.
