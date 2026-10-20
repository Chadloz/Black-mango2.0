; Black Mango for Windows: the setup .exe, built by Inno Setup in the release workflow.
; Installs for the current user only (no admin password), adds a Start menu entry and an
; uninstaller under Settings > Apps, and offers a desktop shortcut (checked by default).
; Updates run this same installer quietly (/SILENT) and reopen Black Mango afterwards.

#ifndef AppVersion
  #define AppVersion "2.0.0"
#endif
#ifndef OutputName
  #define OutputName "Black-Mango-Setup"
#endif

[Setup]
AppId={{52486583-5902-4B70-9E4B-B806498EA0B9}
AppName=Black Mango
AppVersion={#AppVersion}
AppVerName=Black Mango {#AppVersion}
AppPublisher=Black Mango
AppPublisherURL=https://github.com/Chadloz/Black-mango2.0
AppSupportURL=https://github.com/Chadloz/Black-mango2.0/issues
DefaultDirName={autopf}\Black Mango
DefaultGroupName=Black Mango
DisableProgramGroupPage=yes
DisableDirPage=auto
PrivilegesRequired=lowest
OutputDir=..\dist
OutputBaseFilename={#OutputName}
SetupIconFile=runner\resources\app_icon.ico
UninstallDisplayIcon={app}\black_mango.exe
UninstallDisplayName=Black Mango
WizardStyle=modern
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Black Mango"; Filename: "{app}\black_mango.exe"
Name: "{autodesktop}\Black Mango"; Filename: "{app}\black_mango.exe"; Tasks: desktopicon

[Run]
; After a normal install: a "Launch Black Mango" checkbox on the last page.
Filename: "{app}\black_mango.exe"; Description: "{cm:LaunchProgram,Black Mango}"; Flags: nowait postinstall skipifsilent
; After a quiet update: reopen Black Mango by itself.
Filename: "{app}\black_mango.exe"; Flags: nowait; Check: WizardSilent
