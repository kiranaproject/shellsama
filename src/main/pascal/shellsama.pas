program shellsama;

// shellsama
// =========
// Desktop Shell for Samarinda Desktop Environment (Panels, Docks, Taskbars, Menus)

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, Math,
  ftpas, ftpas.api,
  ShellSama.Panel,
  ShellSama.DesktopApps,
  ShellSama.Launcher,
  ShellSama.BottomPanel,
  ShellSama.Desktop;

var
  Panel: TShellPanel;
  Launcher: TShellLauncher;
  BottomPanel: TShellBottomPanel;
  Desktop: TShellDesktop;
  AutoShowLauncher: Boolean;
  NoBottomPanel: Boolean;
  NoDesktop: Boolean;
  CustomWallpaper: string;
  i: Integer;
  arg: string;
begin
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  WriteLn('shellsama — Samarinda Desktop Shell');

  AutoShowLauncher := False;
  NoBottomPanel := False;
  NoDesktop := False;
  CustomWallpaper := '';
  i := 1;
  while i <= ParamCount do
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
      WriteLn('  --show-launcher        Show the application launcher immediately on start');
      WriteLn('  --no-bottom-panel      Do not display the bottom taskbar panel');
      WriteLn('  --no-desktop           Do not display the desktop wallpaper surface');
      WriteLn('  --wallpaper <path>     Load and display the specified wallpaper image');
      WriteLn('  --version, -v          Print version and exit');
      WriteLn('  --help, -h             Print this help message and exit');
      Halt(0);
    end
    else if arg = '--show-launcher' then
    begin
      AutoShowLauncher := True;
    end
    else if arg = '--no-bottom-panel' then
    begin
      NoBottomPanel := True;
    end
    else if arg = '--no-desktop' then
    begin
      NoDesktop := True;
    end
    else if (arg = '--wallpaper') and (i < ParamCount) then
    begin
      Inc(i);
      CustomWallpaper := ParamStr(i);
    end;
    Inc(i);
  end;

  Panel := TShellPanel.Create(1920, 1080);
  try
    WriteLn('Initialized Desktop Panel:');
    WriteLn('  Geometry:  ', Panel.PanelWidth(), 'x', Panel.PanelHeight(), ' at (', Panel.PanelX(), ', ', Panel.PanelY(), ')');
    WriteLn('  Theme:     ', Panel.Config.ThemeName);
    WriteLn('  Strut Top: ', Panel.ComputeStrut().Top, ' px');

    if not FtLoadLib() then
    begin
      WriteLn('Notice: Cannot load libft.so. Running in non-display mode.');
      Exit;
    end;

    try
      FtApp().Initialize();
    except
      on E: Exception do
      begin
        WriteLn('Notice: Cannot connect to X11 display (', E.Message, '). Running in non-display mode.');
        Exit;
      end;
    end;

    try
      if not NoDesktop then
      begin
        Desktop := TShellDesktop.Create();
        if CustomWallpaper <> '' then
          Desktop.SetWallpaper(CustomWallpaper);
        Desktop.Show();
        WriteLn('Desktop Wallpaper ready (', Desktop.Width, 'x', Desktop.Height, ')');
      end
      else
        Desktop := nil;

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

          FtApp().Run();
        finally
          if Assigned(BottomPanel) then
            BottomPanel.Free();
        end;
      finally
        Launcher.Free();
      end;
    finally
      if Assigned(Desktop) then
        Desktop.Free();
    end;
  finally
    Panel.Free();
  end;
end.
