#define AppName "PhongVu OpsHub"
#define AppPublisher "PhongVu OpsHub"
#ifndef AppVersion
#define AppVersion "1.0.0"
#endif
#ifndef SourceDir
#define SourceDir "..\..\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
#define OutputDir "..\..\build\windows\x64\runner"
#endif
#ifndef OutputBaseFilename
#define OutputBaseFilename "phongvu-opshub-windows-setup"
#endif
#ifndef VcRedistPath
#error VcRedistPath must point to vc_redist.x64.exe
#endif

[Setup]
AppId={{D3F4B8F6-1F61-4C7E-9E9E-938AF6F38F8F}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={localappdata}\Programs\PhongVu OpsHub
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
OutputDir={#OutputDir}
OutputBaseFilename={#OutputBaseFilename}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
CloseApplications=yes
RestartApplications=no
UninstallDisplayIcon={app}\phongvu_opshub.exe
VersionInfoCompany={#AppPublisher}
VersionInfoDescription={#AppName} installer
VersionInfoProductName={#AppName}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#VcRedistPath}"; DestDir: "{tmp}"; DestName: "vc_redist.x64.exe"; Flags: dontcopy
#ifdef InternalCodeSigningCertPath
Source: "{#InternalCodeSigningCertPath}"; DestDir: "{tmp}"; DestName: "opshub-codesign.cer"; Flags: dontcopy
#endif

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\phongvu_opshub.exe"
Name: "{userdesktop}\{#AppName}"; Filename: "{app}\phongvu_opshub.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\phongvu_opshub.exe"; Description: "Launch {#AppName}"; Flags: nowait postinstall skipifsilent; Check: ShouldLaunchApp

[Code]
function WaveOutGetNumDevs(): Integer;
  external 'waveOutGetNumDevs@winmm.dll stdcall';

var
  VcRedistNeedsRestart: Boolean;

function BoolText(Value: Boolean): String;
begin
  if Value then
    Result := 'true'
  else
    Result := 'false';
end;

#ifdef InternalCodeSigningCertPath
function InternalCodeSigningCertBundled(): Boolean;
begin
  Result := True;
end;
#else
function InternalCodeSigningCertBundled(): Boolean;
begin
  Result := False;
end;
#endif

procedure AddInternalCodeSigningCertToStore(StoreName: String; CertPath: String);
var
  ResultCode: Integer;
begin
  ResultCode := -1;

  if Exec(
    ExpandConstant('{sys}\certutil.exe'),
    '-user -addstore ' + StoreName + ' "' + CertPath + '"',
    '',
    SW_HIDE,
    ewWaitUntilTerminated,
    ResultCode
  ) and (ResultCode = 0) then
    Log('Internal code signing certificate installed in current user store: ' + StoreName + '.')
  else
    Log('Internal code signing certificate install warning. Store: ' + StoreName + '. Exit code: ' + IntToStr(ResultCode) + '.');
end;

procedure InstallInternalCodeSigningCert();
var
  CertPath: String;
begin
  if not InternalCodeSigningCertBundled() then
  begin
    Log('No internal code signing certificate is bundled with this installer.');
    Exit;
  end;

  ExtractTemporaryFile('opshub-codesign.cer');
  CertPath := ExpandConstant('{tmp}\opshub-codesign.cer');
  Log('Installing bundled internal code signing certificate for the current Windows user.');
  AddInternalCodeSigningCertToStore('Root', CertPath);
  AddInternalCodeSigningCertToStore('TrustedPublisher', CertPath);
end;

function IsServiceRunning(ServiceName: String): Boolean;
var
  ResultCode: Integer;
begin
  Result := Exec(
    ExpandConstant('{sys}\cmd.exe'),
    '/C sc query "' + ServiceName + '" | find "RUNNING" >nul',
    '',
    SW_HIDE,
    ewWaitUntilTerminated,
    ResultCode
  ) and (ResultCode = 0);

  if Result then
    Log('Windows audio service is running: ' + ServiceName + '.')
  else
    Log('Windows audio service is not running or unavailable: ' + ServiceName + '. Exit code: ' + IntToStr(ResultCode) + '.');
end;

function AudioServicesRunning(): Boolean;
begin
  Result :=
    IsServiceRunning('Audiosrv') and
    IsServiceRunning('AudioEndpointBuilder');
end;

function AudioOutputAvailable(): Boolean;
var
  DeviceCount: Integer;
begin
  DeviceCount := WaveOutGetNumDevs();
  Result := DeviceCount > 0;
  Log('Windows audio output device count reported by waveOutGetNumDevs: ' + IntToStr(DeviceCount) + '.');
end;

procedure RunAudioPreflight();
var
  ServicesOk: Boolean;
  OutputOk: Boolean;
  Message: String;
begin
  ServicesOk := AudioServicesRunning();
  OutputOk := AudioOutputAvailable();

  if ServicesOk and OutputOk then
  begin
    Log('Windows audio preflight passed.');
    Exit;
  end;

  Log('Windows audio preflight warning. servicesOk=' + BoolText(ServicesOk) + ', outputOk=' + BoolText(OutputOk) + '.');
  Message :=
    'PhongVu OpsHub will continue installing, but payment notification audio may not play on this PC yet.' + #13#10#13#10 +
    'Please check Windows Audio service, audio driver, and the selected speaker/output device before relying on payment voice alerts.';

  if not WizardSilent then
    MsgBox(Message, mbInformation, MB_OK);
end;

function InitializeSetup(): Boolean;
begin
  Result := True;
  InstallInternalCodeSigningCert();
  RunAudioPreflight();
end;

function VcRuntimeDllsPresent(): Boolean;
begin
  Result :=
    FileExists(ExpandConstant('{sys}\msvcp140.dll')) and
    FileExists(ExpandConstant('{sys}\vcruntime140.dll')) and
    FileExists(ExpandConstant('{sys}\vcruntime140_1.dll'));

  if not Result then
    Log('Visual C++ runtime DLL check failed; msvcp140.dll, vcruntime140.dll, or vcruntime140_1.dll is missing.');
end;

function VcRuntimeRegistryCurrent(): Boolean;
var
  Installed: Cardinal;
  Major: Cardinal;
  Minor: Cardinal;
begin
  Result := False;

  if not RegQueryDWordValue(HKLM64, 'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64', 'Installed', Installed) then
  begin
    Log('Visual C++ Redistributable x64 registry value Installed is missing.');
    Exit;
  end;

  if Installed <> 1 then
  begin
    Log(Format('Visual C++ Redistributable x64 registry value Installed is %d.', [Installed]));
    Exit;
  end;

  if not RegQueryDWordValue(HKLM64, 'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64', 'Major', Major) then
  begin
    Log('Visual C++ Redistributable x64 registry value Major is missing.');
    Exit;
  end;

  if not RegQueryDWordValue(HKLM64, 'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64', 'Minor', Minor) then
  begin
    Log('Visual C++ Redistributable x64 registry value Minor is missing.');
    Exit;
  end;

  Result := (Major > 14) or ((Major = 14) and (Minor >= 20));
  if Result then
    Log(Format('Visual C++ Redistributable x64 registry version is current enough: %d.%d.', [Major, Minor]))
  else
    Log(Format('Visual C++ Redistributable x64 registry version is too old: %d.%d.', [Major, Minor]));
end;

function NeedsVcRedist(): Boolean;
begin
  Result := (not VcRuntimeRegistryCurrent()) or (not VcRuntimeDllsPresent());

  if Result then
    Log('Bundled Visual C++ Redistributable x64 will be installed because the prerequisite is missing, old, or incomplete.')
  else
    Log('Visual C++ Redistributable x64 prerequisite is already satisfied.');
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ResultCode: Integer;
  VcRedistExe: String;
  VcRedistLog: String;
begin
  Result := '';
  VcRedistNeedsRestart := False;

  if not NeedsVcRedist() then
    Exit;

  ExtractTemporaryFile('vc_redist.x64.exe');
  VcRedistExe := ExpandConstant('{tmp}\vc_redist.x64.exe');
  VcRedistLog := ExpandConstant('{tmp}\vc_redist_x64.log');

  Log('Starting bundled Visual C++ Redistributable x64 installer.');
  if not ShellExec('runas', VcRedistExe, '/install /quiet /norestart /log "' + VcRedistLog + '"', '', SW_SHOW, ewWaitUntilTerminated, ResultCode) then
  begin
    if ResultCode = 1223 then
      Result := 'PhongVu OpsHub requires Microsoft Visual C++ Redistributable x64. Administrator permission was cancelled, so setup cannot continue.'
    else
      Result := 'PhongVu OpsHub could not start Microsoft Visual C++ Redistributable x64 setup. Windows error code: ' + IntToStr(ResultCode) + '.';
    Exit;
  end;

  case ResultCode of
    0:
      begin
        if NeedsVcRedist() then
          Result := 'Microsoft Visual C++ Redistributable x64 setup finished, but required runtime files are still missing. Please restart Windows and run setup again.'
        else
          Log('Microsoft Visual C++ Redistributable x64 installed successfully.');
      end;
    3010, 1641:
      begin
        VcRedistNeedsRestart := True;
        NeedsRestart := True;
        Log(Format('Microsoft Visual C++ Redistributable x64 installed and requested a restart. Exit code: %d.', [ResultCode]));
      end;
    1638:
      begin
        if NeedsVcRedist() then
          Result := 'Microsoft Visual C++ Redistributable x64 setup reported another version is installed, but required runtime files are still missing. Please install the latest Microsoft Visual C++ Redistributable x64 manually, then rerun setup.'
        else
          Log('Microsoft Visual C++ Redistributable x64 setup reported another version is installed; runtime check is satisfied.');
      end;
  else
    Result := 'Microsoft Visual C++ Redistributable x64 setup failed with exit code ' + IntToStr(ResultCode) + '. Please restart Windows and run setup again as administrator.';
  end;
end;

function ShouldLaunchApp(): Boolean;
begin
  Result := not VcRedistNeedsRestart;
  if not Result then
    Log('Skipping postinstall app launch because Microsoft Visual C++ Redistributable x64 requested a restart.');
end;
