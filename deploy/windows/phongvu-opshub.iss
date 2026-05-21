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

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\phongvu_opshub.exe"
Name: "{userdesktop}\{#AppName}"; Filename: "{app}\phongvu_opshub.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\phongvu_opshub.exe"; Description: "Launch {#AppName}"; Flags: nowait postinstall skipifsilent
