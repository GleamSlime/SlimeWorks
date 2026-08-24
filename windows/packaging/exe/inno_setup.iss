[Setup]
AppId={{APP_ID}}
AppVersion={{APP_VERSION}}
AppName=史莱姆工坊
AppPublisher=GleamSlime
AppPublisherURL=https://github.com/GleamSlime/slime_works
AppSupportURL=https://github.com/GleamSlime/slime_works
AppUpdatesURL=https://github.com/GleamSlime/slime_works/releases
DefaultDirName={autopf}\SlimeWorks
DefaultGroupName=史莱姆工坊
DisableProgramGroupPage=yes
OutputDir=.
OutputBaseFilename=史莱姆工坊_{{APP_VERSION}}_windows_x64
Compression=lzma2/ultra64
SolidCompression=yes
SetupIconFile={{SETUP_ICON_FILE}}
WizardStyle=modern
PrivilegesRequired=lowest
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
CloseApplications=force
UninstallDisplayIcon={app}\slime_works.exe

[Languages]
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: checkedonce
Name: "launchatstartup"; Description: "开机自动启动"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{{SOURCE_DIR}}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\史莱姆工坊"; Filename: "{app}\slime_works.exe"
Name: "{autodesktop}\史莱姆工坊"; Filename: "{app}\slime_works.exe"; Tasks: desktopicon
Name: "{userstartup}\史莱姆工坊"; Filename: "{app}\slime_works.exe"; Tasks: launchatstartup; WorkingDir: "{app}"

[Run]
Filename: "{app}\slime_works.exe"; Description: "{cm:LaunchProgram,史莱姆工坊}"; Flags: nowait postinstall skipifsilent
