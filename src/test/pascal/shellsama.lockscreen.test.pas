unit ShellSama.LockScreen.Test;

// ShellSama.LockScreen.Test
// =========================
// Automated unit tests for native PAM authentication and ShellSama lock screen.

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  ftpas.api, ftpas.types, ftpas,
  ShellSama.PAM, ShellSama.LockScreen;

type
  TLockScreenTest = class(TTestCase)
  private
    FLockScreen: TShellLockScreen;
  protected
    procedure SetUp(); override;
    procedure TearDown(); override;
  published
    procedure TestPamAuthenticatorAvailable();
    procedure TestPamAuthenticationInvalidCredentials();
    procedure TestLockScreenCreationAndDefaults();
    procedure TestLockScreenStateTransitions();
    procedure TestLockScreenPasswordClearingOnShield();
    procedure TestLockScreenPasswordEntryIsMasked();
    procedure TestLockScreenShakeActivation();
    procedure TestLockScreenUnlockClearsState();
  end;

implementation

procedure TLockScreenTest.SetUp();
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

  FLockScreen := TShellLockScreen.Create(False);
end;

procedure TLockScreenTest.TearDown();
begin
  if Assigned(FLockScreen) then
  begin
    FLockScreen.Free();
    FLockScreen := nil;
  end;
end;

procedure TLockScreenTest.TestPamAuthenticatorAvailable();
begin
  AssertTrue('PAM authenticator must be available on host Linux system', PamAuth().Available);
end;

procedure TLockScreenTest.TestPamAuthenticationInvalidCredentials();
var
  errMsg: string;
  ok: Boolean;
begin
  if not PamAuth().Available then
    Exit;

  errMsg := '';
  ok := PamAuth().Authenticate('invalid_user_never_exist_99999', 'invalid_pwd_99999', errMsg);
  AssertFalse('Authentication with non-existent user must return False', ok);
  AssertTrue('Error message must not be empty on authentication failure', Length(errMsg) > 0);
end;

procedure TLockScreenTest.TestLockScreenCreationAndDefaults();
begin
  AssertNotNull('Lock screen instance must be created', FLockScreen);
  AssertNotNull('Window widget must be initialized', FLockScreen.Window);
  AssertNotNull('Password entry widget must be initialized', FLockScreen.PasswordEntry);
  AssertFalse('Lock screen must not be locked initially', FLockScreen.IsLocked);
  AssertTrue('Lock screen initial state must be lssShield', FLockScreen.State = lssShield);
  AssertFalse('Password entry must be hidden in shield state', FLockScreen.PasswordEntry.Visible);
  AssertTrue('User name must not be empty', Length(FLockScreen.UserName) > 0);
  AssertTrue('User full name must not be empty', Length(FLockScreen.UserFullName) > 0);
end;

procedure TLockScreenTest.TestLockScreenStateTransitions();
begin
  FLockScreen.SetState(lssAuth);
  AssertTrue('State must be lssAuth', FLockScreen.State = lssAuth);
  AssertTrue('Password entry must be visible in auth state', FLockScreen.PasswordEntry.Visible);

  FLockScreen.SetState(lssShield);
  AssertTrue('State must be lssShield', FLockScreen.State = lssShield);
  AssertFalse('Password entry must be hidden in shield state', FLockScreen.PasswordEntry.Visible);
end;

procedure TLockScreenTest.TestLockScreenPasswordClearingOnShield();
begin
  FLockScreen.SetState(lssAuth);
  FLockScreen.PasswordEntry.Text := 'transient_secret';
  AssertEquals('Password entry must hold assigned text', 'transient_secret', FLockScreen.PasswordEntry.Text);

  // Transition back to shield must clear entry text for security
  FLockScreen.SetState(lssShield);
  AssertEquals('Password entry must be cleared upon returning to shield state', '', FLockScreen.PasswordEntry.Text);
end;

procedure TLockScreenTest.TestLockScreenPasswordEntryIsMasked();
begin
  AssertTrue('Password entry widget must have IsPassword enabled', FLockScreen.PasswordEntry.IsPassword);
end;

procedure TLockScreenTest.TestLockScreenShakeActivation();
begin
  FLockScreen.StartShake();
  // Call tick to process first frame of shake
  FLockScreen.Tick();
  // State remains valid and does not crash
  AssertNotNull('Lock screen remains valid during shake', FLockScreen);
end;

procedure TLockScreenTest.TestLockScreenUnlockClearsState();
begin
  FLockScreen.ErrorMessage := 'Failed attempt';
  FLockScreen.PasswordEntry.Text := 'wrong_password';
  FLockScreen.Unlock();

  AssertFalse('IsLocked must be False after Unlock', FLockScreen.IsLocked);
  AssertEquals('PasswordEntry text must be wiped on unlock', '', FLockScreen.PasswordEntry.Text);
  AssertEquals('ErrorMessage must be wiped on unlock', '', FLockScreen.ErrorMessage);
end;

initialization
  RegisterTest(TLockScreenTest);

end.
