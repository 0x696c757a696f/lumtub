; Inno Setup script for the Lumtub installer, built by .github/workflows/build.yml:
;   iscc /DAppVersion=0.1.0 /DSourceDir=<release folder> /DOutputDir=<folder> lumtub.iss
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
#ifndef PackageArch
  #define PackageArch "x64"
#endif
#ifndef InstallArch
  #define InstallArch "x64"
#endif

[Setup]
AppId={{6F1C2E9A-3B7D-4C55-9E2A-8D4F1A7B9C31}
AppName=Lumtub
AppVersion={#AppVersion}
AppVerName=Lumtub {#AppVersion}
AppPublisher=Lumtub
AppPublisherURL=https://github.com/0x696c757a696f/lumtub
AppSupportURL=https://github.com/0x696c757a696f/lumtub/issues
DefaultDirName={autopf}\Lumtub
DefaultGroupName=Lumtub
DisableProgramGroupPage=yes
UsePreviousGroup=no
PrivilegesRequired=lowest
ArchitecturesAllowed={#InstallArch}
ArchitecturesInstallIn64BitMode={#InstallArch}
MinVersion=10.0
LicenseFile={#SourceDir}\LICENSE
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\lumtub.exe
OutputDir={#OutputDir}
OutputBaseFilename=Lumtub_{#AppVersion}_windows-{#PackageArch}-setup
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; The app must be closed so its DLLs can be replaced.
CloseApplications=yes

[Languages]
; The first language is the one used when none matches Windows.
Name: "english"; MessagesFile: "compiler:Default.isl"
; Inno Setup 6 ships no Simplified Chinese, so the translation from its
; unofficial set is kept here for compilers without one.
#if FileExists(CompilerPath + "Languages\ChineseSimplified.isl")
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
#else
Name: "chinesesimplified"; MessagesFile: "Languages\ChineseSimplified.isl"
#endif
#if FileExists(CompilerPath + "Languages\Japanese.isl")
Name: "japanese"; MessagesFile: "compiler:Languages\Japanese.isl"
#endif
#if FileExists(CompilerPath + "Languages\Korean.isl")
Name: "korean"; MessagesFile: "compiler:Languages\Korean.isl"
#endif
#if FileExists(CompilerPath + "Languages\German.isl")
Name: "german"; MessagesFile: "compiler:Languages\German.isl"
#endif
#if FileExists(CompilerPath + "Languages\French.isl")
Name: "french"; MessagesFile: "compiler:Languages\French.isl"
#endif
#if FileExists(CompilerPath + "Languages\Spanish.isl")
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"
#endif
#if FileExists(CompilerPath + "Languages\BrazilianPortuguese.isl")
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"
#endif
#if FileExists(CompilerPath + "Languages\Russian.isl")
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
#endif

[CustomMessages]
Downgrade=Lumtub %1 is installed, which is newer than this installer's %2.%n%nInstall the older version anyway? Your settings and library are kept.
OtherInstall=Lumtub is also installed for all users in:%n%1%n%nThis installer puts a second copy in your own account. You can uninstall the other one in Windows Settings › Apps.%n%nContinue?
RunningElsewhere=Lumtub is running from another folder, likely a portable copy:%n%1%n%nClose it first, or the installed copy and that one may both run at once.%n%nContinue?
NeedsAdmin=Installing into this folder needs administrator rights:%n%1%n%nStart the installer again as administrator?
NeedsAdminFolder=Lumtub cannot write to %1 without administrator rights. Run the installer as administrator, or install into another folder.
chinesesimplified.Downgrade=已安装的 Lumtub %1 比这个安装包的 %2 更新。%n%n仍要安装旧版本吗？设置和资料库会保留。
chinesesimplified.OtherInstall=Lumtub 还为所有用户装在：%n%1%n%n这个安装包会在你的账户里另装一份。另一份可以在 Windows 设置 › 应用 中卸载。%n%n继续吗？
chinesesimplified.RunningElsewhere=有一个 Lumtub 正在从别的文件夹运行，可能是便携版：%n%1%n%n请先关掉它，否则安装版和它可能同时运行。%n%n继续吗？
chinesesimplified.NeedsAdmin=安装到这个文件夹需要管理员权限：%n%1%n%n以管理员身份重新启动安装程序吗？
chinesesimplified.NeedsAdminFolder=没有管理员权限，Lumtub 无法写入 %1。请以管理员身份运行安装程序，或者装到别的文件夹。
#if FileExists(CompilerPath + "Languages\Japanese.isl")
japanese.Downgrade=インストール済みの Lumtub %1 は、このインストーラーの %2 より新しいバージョンです。%n%n古いバージョンをインストールしますか？設定とライブラリは残ります。
japanese.OtherInstall=Lumtub はすべてのユーザー用に次の場所にもインストールされています:%n%1%n%nこのインストーラーはあなたのアカウントにもう 1 つインストールします。もう一方は Windows の設定 › アプリ からアンインストールできます。%n%n続行しますか？
japanese.RunningElsewhere=別のフォルダーから Lumtub が実行中です（ポータブル版の可能性があります）:%n%1%n%n先に閉じてください。閉じないと両方が同時に動くことがあります。%n%n続行しますか？
japanese.NeedsAdmin=このフォルダーへのインストールには管理者権限が必要です:%n%1%n%n管理者としてインストーラーを起動し直しますか？
japanese.NeedsAdminFolder=管理者権限がないため、Lumtub は %1 に書き込めません。インストーラーを管理者として実行するか、別のフォルダーにインストールしてください。
#endif
#if FileExists(CompilerPath + "Languages\Korean.isl")
korean.Downgrade=설치된 Lumtub %1이(가) 이 설치 프로그램의 %2보다 최신입니다.%n%n그래도 이전 버전을 설치할까요? 설정과 라이브러리는 유지됩니다.
korean.OtherInstall=Lumtub이 모든 사용자용으로 다음 위치에도 설치되어 있습니다:%n%1%n%n이 설치 프로그램은 내 계정에 하나 더 설치합니다. 다른 하나는 Windows 설정 › 앱에서 제거할 수 있습니다.%n%n계속할까요?
korean.RunningElsewhere=다른 폴더에서 Lumtub이 실행 중입니다(포터블 버전일 수 있음):%n%1%n%n먼저 닫아 주세요. 그렇지 않으면 두 개가 동시에 실행될 수 있습니다.%n%n계속할까요?
korean.NeedsAdmin=이 폴더에 설치하려면 관리자 권한이 필요합니다:%n%1%n%n관리자 권한으로 설치 프로그램을 다시 시작할까요?
korean.NeedsAdminFolder=관리자 권한이 없어 Lumtub이 %1에 쓸 수 없습니다. 설치 프로그램을 관리자 권한으로 실행하거나 다른 폴더에 설치하세요.
#endif
#if FileExists(CompilerPath + "Languages\German.isl")
german.Downgrade=Installiert ist Lumtub %1, neuer als %2 aus diesem Installationsprogramm.%n%nTrotzdem die ältere Version installieren? Einstellungen und Bibliothek bleiben erhalten.
german.OtherInstall=Lumtub ist außerdem für alle Benutzer installiert in:%n%1%n%nDieses Installationsprogramm legt eine zweite Kopie in Ihrem Konto an. Die andere können Sie unter Windows-Einstellungen › Apps deinstallieren.%n%nFortfahren?
german.RunningElsewhere=Lumtub läuft aus einem anderen Ordner, vermutlich eine portable Kopie:%n%1%n%nBitte zuerst schließen, sonst laufen womöglich beide gleichzeitig.%n%nFortfahren?
german.NeedsAdmin=Für die Installation in diesen Ordner sind Administratorrechte nötig:%n%1%n%nDas Installationsprogramm als Administrator neu starten?
german.NeedsAdminFolder=Ohne Administratorrechte kann Lumtub nicht in %1 schreiben. Starten Sie das Installationsprogramm als Administrator oder wählen Sie einen anderen Ordner.
#endif
#if FileExists(CompilerPath + "Languages\French.isl")
french.Downgrade=Lumtub %1 est installé, plus récent que la version %2 de ce programme d'installation.%n%nInstaller quand même l'ancienne version ? Vos réglages et votre bibliothèque sont conservés.
french.OtherInstall=Lumtub est aussi installé pour tous les utilisateurs dans :%n%1%n%nCe programme d'installation en place une seconde copie dans votre compte. Vous pouvez désinstaller l'autre dans Paramètres Windows › Applications.%n%nContinuer ?
french.RunningElsewhere=Lumtub tourne depuis un autre dossier, sans doute une copie portable :%n%1%n%nFermez-le d'abord, sinon les deux pourraient tourner en même temps.%n%nContinuer ?
french.NeedsAdmin=L'installation dans ce dossier demande les droits d'administrateur :%n%1%n%nRelancer le programme d'installation en tant qu'administrateur ?
french.NeedsAdminFolder=Sans droits d'administrateur, Lumtub ne peut pas écrire dans %1. Lancez le programme d'installation en tant qu'administrateur, ou installez dans un autre dossier.
#endif
#if FileExists(CompilerPath + "Languages\Spanish.isl")
spanish.Downgrade=Está instalado Lumtub %1, más reciente que la versión %2 de este instalador.%n%n¿Instalar la versión anterior de todos modos? Se conservan los ajustes y la biblioteca.
spanish.OtherInstall=Lumtub también está instalado para todos los usuarios en:%n%1%n%nEste instalador pondrá una segunda copia en tu cuenta. Puedes desinstalar la otra en Configuración de Windows › Aplicaciones.%n%n¿Continuar?
spanish.RunningElsewhere=Lumtub se está ejecutando desde otra carpeta, probablemente una copia portátil:%n%1%n%nCiérralo antes, o las dos copias podrían ejecutarse a la vez.%n%n¿Continuar?
spanish.NeedsAdmin=Instalar en esta carpeta requiere permisos de administrador:%n%1%n%n¿Volver a abrir el instalador como administrador?
spanish.NeedsAdminFolder=Sin permisos de administrador, Lumtub no puede escribir en %1. Ejecuta el instalador como administrador o instala en otra carpeta.
#endif
#if FileExists(CompilerPath + "Languages\BrazilianPortuguese.isl")
brazilianportuguese.Downgrade=O Lumtub %1 está instalado e é mais novo que a versão %2 deste instalador.%n%nInstalar a versão mais antiga mesmo assim? Suas configurações e biblioteca são mantidas.
brazilianportuguese.OtherInstall=O Lumtub também está instalado para todos os usuários em:%n%1%n%nEste instalador colocará uma segunda cópia na sua conta. Você pode desinstalar a outra em Configurações do Windows › Aplicativos.%n%nContinuar?
brazilianportuguese.RunningElsewhere=O Lumtub está rodando de outra pasta, provavelmente uma cópia portátil:%n%1%n%nFeche-o antes, ou as duas cópias podem rodar ao mesmo tempo.%n%nContinuar?
brazilianportuguese.NeedsAdmin=Instalar nesta pasta exige direitos de administrador:%n%1%n%nAbrir o instalador de novo como administrador?
brazilianportuguese.NeedsAdminFolder=Sem direitos de administrador, o Lumtub não consegue gravar em %1. Execute o instalador como administrador ou instale em outra pasta.
#endif
#if FileExists(CompilerPath + "Languages\Russian.isl")
russian.Downgrade=Установлен Lumtub %1 — новее, чем версия %2 в этом установщике.%n%nВсё равно установить старую версию? Настройки и библиотека сохранятся.
russian.OtherInstall=Lumtub также установлен для всех пользователей в:%n%1%n%nЭтот установщик поставит вторую копию в вашу учётную запись. Другую можно удалить в Параметры Windows › Приложения.%n%nПродолжить?
russian.RunningElsewhere=Lumtub запущен из другой папки, вероятно, это переносная копия:%n%1%n%nСначала закройте её, иначе обе копии могут работать одновременно.%n%nПродолжить?
russian.NeedsAdmin=Для установки в эту папку нужны права администратора:%n%1%n%nПерезапустить установщик от имени администратора?
russian.NeedsAdminFolder=Без прав администратора Lumtub не может записывать в %1. Запустите установщик от имени администратора или выберите другую папку.
#endif

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[InstallDelete]
; Left by versions released as YTPlus.
Type: files; Name: "{app}\ytplus.exe"
Type: files; Name: "{app}\ytplus_core.dll"
Type: filesandordirs; Name: "{autoprograms}\YTPlus"
Type: files; Name: "{autodesktop}\YTPlus.lnk"

[Icons]
Name: "{group}\Lumtub"; Filename: "{app}\lumtub.exe"
Name: "{group}\{cm:UninstallProgram,Lumtub}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Lumtub"; Filename: "{app}\lumtub.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\lumtub.exe"; Description: "{cm:LaunchProgram,Lumtub}"; Flags: nowait postinstall skipifsilent
; An update Lumtub started asks for Lumtub again. Through Explorer, so it
; runs as the signed-in user even when this installer runs as administrator.
Filename: "{win}\explorer.exe"; Parameters: """{app}\lumtub.exe"""; Flags: nowait; Check: Relaunch

; Settings, history, the library and downloaded components live in
; %LOCALAPPDATA%\Lumtub and are kept on uninstall, so reinstalling or
; switching to the portable ZIP keeps them.

[Code]
// Lumtub starts its update installer itself, with /WAITPID= its own process
// so files are replaced only after it has ended, /UPDATELOG= the file noting
// success that Lumtub reads at its next start, and /RELAUNCH=1 to be started
// again afterwards.
function OpenProcess(Access: Cardinal; Inherit: Boolean; ProcessId: Cardinal): THandle;
  external 'OpenProcess@kernel32.dll stdcall';
function WaitForSingleObject(Waited: THandle; Milliseconds: Cardinal): Cardinal;
  external 'WaitForSingleObject@kernel32.dll stdcall';
function CloseHandle(Closed: THandle): Boolean;
  external 'CloseHandle@kernel32.dll stdcall';

const
  SYNCHRONIZE = $00100000;

const
  UninstallKey = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{6F1C2E9A-3B7D-4C55-9E2A-8D4F1A7B9C31}_is1';

// Compares the numbers of two versions such as 0.2.34, one by one, and
// answers -1, 0 or 1.
function CompareVersions(A, B: String): Integer;
var
  PartA, PartB, Dot: Integer;
begin
  Result := 0;
  while (Result = 0) and ((A <> '') or (B <> '')) do
  begin
    Dot := Pos('.', A);
    if Dot = 0 then Dot := Length(A) + 1;
    PartA := StrToIntDef(Copy(A, 1, Dot - 1), 0);
    Delete(A, 1, Dot);
    Dot := Pos('.', B);
    if Dot = 0 then Dot := Length(B) + 1;
    PartB := StrToIntDef(Copy(B, 1, Dot - 1), 0);
    Delete(B, 1, Dot);
    if PartA < PartB then Result := -1
    else if PartA > PartB then Result := 1;
  end;
end;

// The leading digits and dots of a version: 0.2.34 of 0.2.34-abcdef0.
function NumbersOf(Version: String): String;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Length(Version) do
  begin
    if ((Version[I] < '0') or (Version[I] > '9')) and (Version[I] <> '.') then Break;
    Result := Result + Version[I];
  end;
end;

// The folder of an install for all users, or ''.
function MachineInstall(): String;
begin
  Result := '';
  if IsWin64 then
    RegQueryStringValue(HKLM64, UninstallKey, 'InstallLocation', Result);
  if Result = '' then
    RegQueryStringValue(HKLM32, UninstallKey, 'InstallLocation', Result);
end;

// The folder of a lumtub.exe running from anywhere but [Mine], or ''.
function RunningElsewhere(Mine: String): String;
var
  Locator, Service, Processes, Process: Variant;
  I: Integer;
  Path: String;
begin
  Result := '';
  try
    Locator := CreateOleObject('WbemScripting.SWbemLocator');
    Service := Locator.ConnectServer('.', 'root\CIMV2');
    Processes := Service.ExecQuery('SELECT ExecutablePath FROM Win32_Process WHERE Name = ' + #39 + 'lumtub.exe' + #39);
    for I := 0 to Processes.Count - 1 do
    begin
      Process := Processes.ItemIndex(I);
      if not VarIsNull(Process.ExecutablePath) then
      begin
        Path := ExtractFileDir(Process.ExecutablePath);
        if (Path <> '') and (CompareText(AddBackslash(Path), AddBackslash(Mine)) <> 0) then
        begin
          Result := Path;
          Exit;
        end;
      end;
    end;
  except
  end;
end;

// Asked only when a person runs the installer: an update Lumtub starts runs
// silently and has already checked the version.
function CheckOtherCopies(): Boolean;
var
  Installed, Folder, Mine: String;
begin
  Result := True;
  if RegQueryStringValue(HKCU, UninstallKey, 'DisplayVersion', Installed) and
     (CompareVersions(NumbersOf(Installed), NumbersOf('{#AppVersion}')) > 0) then
    Result := SuppressibleMsgBox(FmtMessage(CustomMessage('Downgrade'), [Installed, '{#AppVersion}']),
      mbConfirmation, MB_YESNO or MB_DEFBUTTON2, IDYES) = IDYES;
  if not Result then Exit;
  Folder := MachineInstall();
  if Folder <> '' then
    Result := SuppressibleMsgBox(FmtMessage(CustomMessage('OtherInstall'), [Folder]),
      mbConfirmation, MB_YESNO, IDYES) = IDYES;
  if not Result then Exit;
  Mine := '';
  RegQueryStringValue(HKCU, UninstallKey, 'InstallLocation', Mine);
  if Mine = '' then Mine := ExpandConstant('{autopf}\Lumtub');
  Folder := RunningElsewhere(Mine);
  if Folder <> '' then
    Result := SuppressibleMsgBox(FmtMessage(CustomMessage('RunningElsewhere'), [Folder]),
      mbConfirmation, MB_YESNO, IDYES) = IDYES;
end;

function InitializeSetup(): Boolean;
var
  ProcessId: Cardinal;
  Process: THandle;
begin
  ProcessId := StrToIntDef(ExpandConstant('{param:WAITPID|0}'), 0);
  if ProcessId <> 0 then
  begin
    Process := OpenProcess(SYNCHRONIZE, False, ProcessId);
    if Process <> 0 then
    begin
      WaitForSingleObject(Process, 120000);
      CloseHandle(Process);
    end;
    Result := True;
  end
  else
    Result := WizardSilent() or CheckOtherCopies();
end;

function Relaunch(): Boolean;
begin
  Result := ExpandConstant('{param:RELAUNCH|0}') = '1';
end;

// Whether this account can create files in [Folder], or in the nearest folder
// above it that exists when it is not there yet. A folder such as
// D:\Program Files lets everyone read but only administrators write, and the
// uninstaller is the first file Setup writes, so without this the install
// stops on "Access denied" for unins000.exe.
function CanWriteTo(Folder: String): Boolean;
var
  Probe: String;
begin
  Folder := RemoveBackslashUnlessRoot(Folder);
  while not DirExists(Folder) and (ExtractFileDir(Folder) <> Folder) and (ExtractFileDir(Folder) <> '') do
    Folder := ExtractFileDir(Folder);
  Probe := AddBackslash(Folder) + 'lumtub-setup-write-check.tmp';
  Result := SaveStringToFile(Probe, '', False);
  if Result then DeleteFile(Probe);
end;

var
  RestartedAsAdmin: Boolean;

// A person who runs the installer without administrator rights into a folder
// that needs them is offered to start it again as administrator, with the
// same folder and language.
function NextButtonClick(CurPageID: Integer): Boolean;
var
  Folder: String;
  ErrorCode: Integer;
begin
  Result := True;
  if (CurPageID <> wpReady) or WizardSilent() or IsAdmin() then Exit;
  Folder := WizardDirValue();
  if CanWriteTo(Folder) then Exit;
  Result := False;
  if MsgBox(FmtMessage(CustomMessage('NeedsAdmin'), [Folder]), mbConfirmation, MB_YESNO) <> IDYES then Exit;
  if ShellExec('runas', ExpandConstant('{srcexe}'), '/DIR="' + Folder + '" /LANG=' + ActiveLanguage(), '', SW_SHOWNORMAL, ewNoWait, ErrorCode) then
  begin
    RestartedAsAdmin := True;
    WizardForm.Close;
  end;
end;

procedure CancelButtonClick(CurPageID: Integer; var Cancel, Confirm: Boolean);
begin
  if RestartedAsAdmin then Confirm := False;
end;

// A silent install, or one that got past the question, stops with this
// message in place of "Access denied".
function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';
  if not IsAdmin() and not CanWriteTo(ExpandConstant('{app}')) then
    Result := FmtMessage(CustomMessage('NeedsAdminFolder'), [ExpandConstant('{app}')]);
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  UpdateLog: String;
begin
  UpdateLog := ExpandConstant('{param:UPDATELOG|}');
  if (CurStep = ssPostInstall) and (UpdateLog <> '') then
    SaveStringToFile(UpdateLog, GetDateTimeString('yyyy-mm-dd hh:nn:ss', '-', ':') + ' updated' + #13#10, True);
end;
