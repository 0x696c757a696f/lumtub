; Inno Setup script for the YTPlus installer, built by .github/workflows/windows.yml:
;   iscc /DAppVersion=0.1.0 /DSourceDir=<release folder> /DOutputDir=<folder> ytplus.iss
; Installs for the current user only, so no administrator rights are needed,
; the same as the portable ZIP.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\build\installer"
#endif

[Setup]
AppId={{6F1C2E9A-3B7D-4C55-9E2A-8D4F1A7B9C31}
AppName=YTPlus
AppVersion={#AppVersion}
AppVerName=YTPlus {#AppVersion}
AppPublisher=YTPlus
AppPublisherURL=https://github.com/0x696c757a696f/ytplus
AppSupportURL=https://github.com/0x696c757a696f/ytplus/issues
DefaultDirName={autopf}\YTPlus
DefaultGroupName=YTPlus
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
LicenseFile={#SourceDir}\LICENSE
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\ytplus.exe
OutputDir={#OutputDir}
OutputBaseFilename=YTPlus_Setup_x64
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; The app must be closed so its DLLs can be replaced.
CloseApplications=yes

[Languages]
#if FileExists(CompilerPath + "Languages\ChineseSimplified.isl")
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
#endif
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\YTPlus"; Filename: "{app}\ytplus.exe"
Name: "{group}\{cm:UninstallProgram,YTPlus}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\YTPlus"; Filename: "{app}\ytplus.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\ytplus.exe"; Description: "{cm:LaunchProgram,YTPlus}"; Flags: nowait postinstall skipifsilent

; Settings, history, the library and downloaded components live in
; %LOCALAPPDATA%\YTPlus and are kept on uninstall, so reinstalling or
; switching to the portable ZIP keeps them.
