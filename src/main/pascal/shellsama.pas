program shellsama;

// shellsama
// =========
// Desktop Shell for Samarinda Desktop Environment (Panels, Docks, Taskbars, Menus)

{$mode objfpc}{$H+}

uses
  SysUtils, Classes,
  ShellSama.LibFt,
  ShellSama.Panel,
  ShellSama.DesktopApps,
  ShellSama.Launcher,
  ShellSama.BottomPanel;

var
  Panel: TShellPanel;
  Launcher: TShellLauncher;
  BottomPanel: TShellBottomPanel;
  AutoShowLauncher: Boolean;
  NoBottomPanel: Boolean;
  i: Integer;
  arg: string;
begin
  WriteLn('shellsama — Samarinda Desktop Shell');

  AutoShowLauncher := False;
  NoBottomPanel := False;
  for i := 1 to ParamCount do
  begin
    arg := ParamStr(i);
    if (arg = '--version') or (arg = '-v') then
    begin
      WriteLn('shellsama 0.0.1-SNAPSHOT');
      Halt(0);
    end
    else if (arg = '--help') or (arg = '-h') then
    begin
      WriteLn('Usage: shellsama [options]');
      WriteLn('Options:');
      WriteLn('  --show-launcher    Show the application launcher immediately on start');
      WriteLn('  --no-bottom-panel  Do not display the bottom taskbar panel');
      WriteLn('  --version, -v      Print version and exit');
      WriteLn('  --help, -h         Print this help message and exit');
      Halt(0);
    end
    else if arg = '--show-launcher' then
    begin
      AutoShowLauncher := True;
    end
    else if arg = '--no-bottom-panel' then
    begin
      NoBottomPanel := True;
    end;
  end;

  Panel := TShellPanel.Create(1920, 1080);
  try
    WriteLn('Initialized Desktop Panel:');
    WriteLn('  Geometry:  ', Panel.PanelWidth(), 'x', Panel.PanelHeight(), ' at (', Panel.PanelX(), ', ', Panel.PanelY(), ')');
    WriteLn('  Theme:     ', Panel.Config.ThemeName);
    WriteLn('  Strut Top: ', Panel.ComputeStrut().Top, ' px');

    if not LoadLibFt() then
    begin
      WriteLn('Notice: Cannot load libft.so. Running in non-display mode.');
      Exit;
    end;

    try
      ft_init();
    except
      on E: Exception do
      begin
        WriteLn('Notice: Cannot connect to X11 display (', E.Message, '). Running in non-display mode.');
        Exit;
      end;
    end;

    Launcher := TShellLauncher.Create();
    try
      WriteLn('Application Launcher ready (Super key toggles launcher)');
      WriteLn('Loaded ', Launcher.AppList.AppCount(), ' desktop application(s)');

      if not NoBottomPanel then
      begin
        BottomPanel := TShellBottomPanel.Create(Launcher);
        BottomPanel.Show();
        WriteLn('Bottom Panel & Taskbar ready at (', BottomPanel.PanelX(), ', ', BottomPanel.PanelY(), ') ',
                BottomPanel.PanelWidth(), 'x', BottomPanel.PanelHeight(), ' px');
      end
      else
        BottomPanel := nil;

      try
        if AutoShowLauncher then
          Launcher.Show();

        ft_main_loop();
      finally
        if Assigned(BottomPanel) then
          BottomPanel.Free();
      end;
    finally
      Launcher.Free();
    end;
  finally
    Panel.Free();
  end;
end.
