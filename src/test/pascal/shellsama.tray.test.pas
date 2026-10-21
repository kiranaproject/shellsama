unit ShellSama.Tray.Test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  Floria.XCB,
  ftpas.api, ftpas.types, ftpas,
  ShellSama.Tray;

type
  TTrayTest = class(TTestCase)
  private
    FPanelWin        : TFtWindow;
    FTray            : TShellSystemTray;
    FLayoutFiredCount: Integer;

    procedure OnTrayLayoutChanged(Sender: TObject);
  protected
    procedure SetUp(); override;
    procedure TearDown(); override;
  published
    procedure TestTrayCreationAndDefaults();
    procedure TestTrayWidthCalculations();
    procedure TestTrayDockAndUndockLifecycle();
    procedure TestTrayAtomsAndProperties();
  end;

implementation

procedure TTrayTest.OnTrayLayoutChanged(Sender: TObject);
begin
  Inc(FLayoutFiredCount);
end;

procedure TTrayTest.SetUp();
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

  FPanelWin := TFtWindow.Create(600, 38, 'test-tray-panel');
  FTray := TShellSystemTray.Create(FPanelWin, 0);
  FLayoutFiredCount := 0;
  FTray.OnLayoutChanged := @OnTrayLayoutChanged;
end;

procedure TTrayTest.TearDown();
begin
  if Assigned(FTray) then
  begin
    FTray.Free();
    FTray := nil;
  end;

  if Assigned(FPanelWin) then
  begin
    FPanelWin.Free();
    FPanelWin := nil;
  end;
end;

procedure TTrayTest.TestTrayCreationAndDefaults();
begin
  AssertNotNull('System tray host must be created', FTray);
  AssertEquals('Initial client count must be 0', 0, FTray.ClientCount);
  AssertEquals('Initial tray width must be 0', 0, FTray.Width);
  AssertEquals('Default icon size must be 22', 22, FTray.IconSize);
  AssertEquals('Default icon gap must be 4', 4, FTray.IconGap);
end;

procedure TTrayTest.TestTrayWidthCalculations();
begin
  FTray.SetPosition(450, 8);
  AssertEquals('StartX should be 450', 450, FTray.StartX);
  AssertEquals('StartY should be 8', 8, FTray.StartY);

  // When count is 0, width is 0 regardless of sizes
  AssertEquals('Empty width is 0', 0, FTray.Width);
end;

procedure TTrayTest.TestTrayDockAndUndockLifecycle();
var
  clientWin: TFtWindow;
  clientX11Id: Cardinal;
begin
  clientWin := TFtWindow.Create(22, 22, 'test-tray-icon');
  try
    clientX11Id := Cardinal(PtrUInt(clientWin.NativeHandle));
    AssertTrue('Native window ID must be valid', clientX11Id <> 0);

    // Initial state
    AssertFalse('Window not docked initially', FTray.IsDocked(clientX11Id));
    AssertEquals('Initial layout fired count is 0', 0, FLayoutFiredCount);

    // 1. Dock client
    FTray.DockClient(clientX11Id);
    AssertTrue('Window should now be docked', FTray.IsDocked(clientX11Id));
    AssertEquals('Client count must be 1', 1, FTray.ClientCount);
    AssertEquals('First client ID matches', clientX11Id, FTray.GetClient(0));
    AssertEquals('Tray width for 1 icon is 26', 26, FTray.Width);
    AssertTrue('Layout changed callback must have fired', FLayoutFiredCount >= 1);

    // Docking again should be idempotent (no duplicate)
    FTray.DockClient(clientX11Id);
    AssertEquals('Client count remains 1 after duplicate dock', 1, FTray.ClientCount);

    // 2. Undock client
    FTray.UndockClient(clientX11Id);
    AssertFalse('Window should no longer be docked', FTray.IsDocked(clientX11Id));
    AssertEquals('Client count must be 0 after undock', 0, FTray.ClientCount);
    AssertEquals('Tray width must be 0 after undock', 0, FTray.Width);
    AssertTrue('Layout callback must fire on undock', FLayoutFiredCount >= 2);
  finally
    clientWin.Free();
  end;
end;

procedure TTrayTest.TestTrayAtomsAndProperties();
begin
  AssertTrue('AtomTrayOpcode must be registered', FTray.AtomTrayOpcode <> 0);
  AssertEquals('Non-existent client returns 0', 0, FTray.GetClient(99));
end;

initialization
  RegisterTest(TTrayTest);
end.
