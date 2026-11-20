unit ShellSama.Greeter.Test;

// ShellSama.Greeter.Test
// ======================
// Automated unit tests for pre-session login greeter and LightDM integration.

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  ftpas.api, ftpas.types, ftpas,
  ShellSama.PAM, ShellSama.LockScreen, ShellSama.LightDM, ShellSama.Greeter;

type
  TGreeterTest = class(TTestCase)
  private
    FGreeter: TShellGreeter;
  protected
    procedure SetUp(); override;
    procedure TearDown(); override;
  published
    procedure TestLightDMAvailability();
    procedure TestLightDMOrNativeSessionsEnumerated();
    procedure TestLightDMOrNativeUsersEnumerated();
    procedure TestGreeterCreationAndDefaults();
    procedure TestGreeterSessionSelection();
    procedure TestGreeterStateTransitions();
    procedure TestGreeterPasswordEntryIsMasked();
  end;

implementation

procedure TGreeterTest.SetUp();
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

  FGreeter := TShellGreeter.Create(True, True);
end;

procedure TGreeterTest.TearDown();
begin
  if Assigned(FGreeter) then
  begin
    FGreeter.Free();
    FGreeter := nil;
  end;
end;

procedure TGreeterTest.TestLightDMAvailability();
begin
  // When liblightdm-gobject-1 is installed on Linux host, client should report Available = True
  if FileExists('/usr/lib/x86_64-linux-gnu/liblightdm-gobject-1.so.0') then
    AssertTrue('LightDM client should be available when library is installed', LightDM().Available);
end;

procedure TGreeterTest.TestLightDMOrNativeSessionsEnumerated();
begin
  AssertNotNull('Greeter instance must be valid', FGreeter);
  AssertTrue('At least one desktop session must be enumerated from /usr/share/xsessions', Length(FGreeter.Sessions) > 0);
  AssertTrue('Primary session key must not be empty', Length(FGreeter.Sessions[0].Key) > 0);
  AssertTrue('Primary session name must not be empty', Length(FGreeter.Sessions[0].Name) > 0);
end;

procedure TGreeterTest.TestLightDMOrNativeUsersEnumerated();
begin
  AssertNotNull('Greeter instance must be valid', FGreeter);
  AssertTrue('At least one user account must be enumerated for login', Length(FGreeter.Users) > 0);
  AssertTrue('Primary user name must not be empty', Length(FGreeter.Users[0].Name) > 0);
end;

procedure TGreeterTest.TestGreeterCreationAndDefaults();
begin
  AssertTrue('Greeter test mode must be enabled', FGreeter.TestMode);
  AssertFalse('Greeter must not be locked prior to activation', FGreeter.IsLocked);
  AssertTrue('Greeter initial state must be lssShield', FGreeter.State = lssShield);
  AssertFalse('Password entry must be hidden in shield state', FGreeter.PasswordEntry.Visible);
  AssertEquals('Default user index should be 0', 0, FGreeter.SelectedUserIndex);
  AssertEquals('Default session index should be 0', 0, FGreeter.SelectedSessionIndex);
end;

procedure TGreeterTest.TestGreeterSessionSelection();
begin
  if Length(FGreeter.Sessions) > 1 then
  begin
    FGreeter.SelectedSessionIndex := 1;
    AssertEquals('Selected session index should update', 1, FGreeter.SelectedSessionIndex);
    FGreeter.SelectedSessionIndex := 0;
    AssertEquals('Selected session index should restore to 0', 0, FGreeter.SelectedSessionIndex);
  end
  else
    AssertEquals('Single session must remain index 0', 0, FGreeter.SelectedSessionIndex);
end;

procedure TGreeterTest.TestGreeterStateTransitions();
begin
  FGreeter.SetState(lssAuth);
  AssertTrue('State must be lssAuth', FGreeter.State = lssAuth);
  AssertTrue('Password entry must be visible in auth state', FGreeter.PasswordEntry.Visible);

  FGreeter.SetState(lssShield);
  AssertTrue('State must be lssShield', FGreeter.State = lssShield);
  AssertFalse('Password entry must be hidden in shield state', FGreeter.PasswordEntry.Visible);
end;

procedure TGreeterTest.TestGreeterPasswordEntryIsMasked();
begin
  AssertTrue('Password entry widget in greeter must have IsPassword enabled', FGreeter.PasswordEntry.IsPassword);
end;

initialization
  RegisterTest(TGreeterTest);

end.
