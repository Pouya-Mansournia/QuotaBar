; QuotaBar for Windows installer (Inno Setup 6).
; Build: dotnet publish first (see Windows/README.md), then
;   ISCC.exe Windows\installer\QuotaBar.iss
; Output: Windows\installer\Output\QuotaBar-Setup-<version>.exe

#define AppName "QuotaBar"
#define AppVersion "1.0.1"
#define AppPublisher "P.Mansournia"
#define AppExe "QuotaBar.exe"

[Setup]
AppId={{6E2C4B1A-7F3D-4C8E-9A51-2B7D0F4E9C31}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
AppVerName={#AppName} {#AppVersion}
; Per-user install: no administrator rights needed.
PrivilegesRequired=lowest
DefaultDirName={localappdata}\Programs\{#AppName}
DisableProgramGroupPage=yes
DisableDirPage=auto
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
SetupIconFile=..\QuotaBar.Windows\QuotaBar.ico
OutputDir=Output
OutputBaseFilename=QuotaBar-Setup-{#AppVersion}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
; Close a running QuotaBar before upgrading or uninstalling.
AppMutex=Local\QuotaBar.SingleInstance
CloseApplications=yes

[Tasks]
Name: "startup"; Description: "Start QuotaBar when I sign in to Windows"; GroupDescription: "Options:"
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Options:"; Flags: unchecked

[Files]
Source: "..\publish\{#AppExe}"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Registry]
; Same value the app writes for Settings > Launch at login, so the two stay in sync.
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "{#AppName}"; \
    ValueData: """{app}\{#AppExe}"""; Tasks: startup; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueName: "{#AppName}"; \
    Flags: deletevalue uninsdeletevalue; Check: not WizardIsTaskSelected('startup')

[Run]
Filename: "{app}\{#AppExe}"; Description: "Launch QuotaBar"; Flags: nowait postinstall skipifsilent

; %APPDATA%\QuotaBar is left in place on uninstall: if the Claude status line
; bridge is installed, Claude Code's settings.json points at the script there.
; Remove the bridge from QuotaBar's Settings first for a fully clean uninstall.
