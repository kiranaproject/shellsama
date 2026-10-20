program TestRunner;

{$mode objfpc}{$H+}

uses
  Classes, SysUtils, fpcunit, testregistry, consoletestrunner,
  ShellSama.Test,
  ShellSama.DesktopApps.Test,
  ShellSama.Launcher.Test,
  ShellSama.BottomPanel.Test,
  ShellSama.Desktop.Test;

var
  Application: TTestRunner;

begin
  Application := TTestRunner.Create(nil);
  try
    Application.Initialize();
    Application.Run();
  finally
    Application.Free();
  end;
end.
