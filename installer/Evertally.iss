#ifndef ProjectRoot
  #define ProjectRoot ".."
#endif
#ifndef AppVersion
  #define AppVersion "0.3.0"
#endif

[Setup]
AppId={{E4B4CA9F-1AF0-4D54-9014-134751D724E9}
AppName=Evertally
AppVersion={#AppVersion}
AppPublisher=AF Studio
AppPublisherURL=https://afstudio.dev
AppSupportURL=https://evertally.afstudio.dev
AppUpdatesURL=https://evertally.afstudio.dev/#sync
DefaultDirName={localappdata}\Programs\Evertally
DefaultGroupName=Evertally
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir={#ProjectRoot}\releases
OutputBaseFilename=EvertallySetup
SetupIconFile={#ProjectRoot}\desktop\src-tauri\icons\icon.ico
UninstallDisplayIcon={app}\Evertally.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
CloseApplicationsFilter=Evertally.exe,EvertallyBackground.exe
RestartApplications=no
SetupMutex=EvertallySetup

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "czech"; MessagesFile: "compiler:Languages\Czech.isl"

[CustomMessages]
english.StartWoW=Start Evertally automatically with World of Warcraft Forever
czech.StartWoW=Spouštět Evertally automaticky s World of Warcraft Forever
english.DesktopShortcut=Create a desktop shortcut
czech.DesktopShortcut=Vytvořit zástupce na ploše
english.AddonTask=Install or update the Evertally in-game addons
czech.AddonTask=Nainstalovat nebo aktualizovat herní addony Evertally
english.GameFolderTitle=World of Warcraft Forever folder
czech.GameFolderTitle=Složka World of Warcraft Forever
english.GameFolderInfo=Choose the folder containing Wow.exe, or the World of Warcraft folder containing _forever_. Existing Evertally addons are backed up before updating. SavedVariables are never modified.
czech.GameFolderInfo=Vyber složku s Wow.exe nebo složku World of Warcraft obsahující _forever_. Předchozí addony Evertally se před aktualizací zálohují. SavedVariables se nemění.
english.GameFolderPrompt=World of Warcraft folder:
czech.GameFolderPrompt=Složka World of Warcraft:
english.BadGameFolder=Choose a folder containing Wow.exe or _forever_\Wow.exe, or turn off addon installation.
czech.BadGameFolder=Vyber složku s Wow.exe nebo _forever_\Wow.exe, případně vypni instalaci addonů.
english.StartBackground=Enable the background launcher now (opens Evertally minimized when WoW starts)
czech.StartBackground=Zapnout spouštění na pozadí (při startu WoW otevře Evertally minimalizovaně)

[Tasks]
Name: "startwow"; Description: "{cm:StartWoW}"; GroupDescription: "Evertally:"; Flags: checkedonce
Name: "desktopicon"; Description: "{cm:DesktopShortcut}"; GroupDescription: "Evertally:"; Flags: unchecked
Name: "addon"; Description: "{cm:AddonTask}"; GroupDescription: "World of Warcraft:"; Flags: unchecked

[Files]
Source: "{#ProjectRoot}\desktop\native\target\release\Evertally.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#ProjectRoot}\desktop\native\target\release\EvertallyBackground.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#ProjectRoot}\shared\assets\*"; DestDir: "{app}\resources"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#ProjectRoot}\addon\Evertally\*"; DestDir: "{app}\addon\Evertally"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#ProjectRoot}\addon\Evertally_Export\*"; DestDir: "{app}\addon\Evertally_Export"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#ProjectRoot}\addon\Evertally_Map\*"; DestDir: "{app}\addon\Evertally_Map"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Evertally"; Filename: "{app}\Evertally.exe"
Name: "{group}\{cm:UninstallProgram,Evertally}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Evertally"; Filename: "{app}\Evertally.exe"; Tasks: desktopicon

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "EvertallySync"; ValueData: """{app}\EvertallyBackground.exe"""; Tasks: startwow; Flags: uninsdeletevalue

[Run]
Filename: "{app}\EvertallyBackground.exe"; Description: "{cm:StartBackground}"; Tasks: startwow; Flags: postinstall nowait skipifsilent runhidden

[Code]
var GamePage: TInputDirWizardPage;

function GameRoot: String;
begin
  Result := RemoveBackslashUnlessRoot(GamePage.Values[0]);
  if FileExists(AddBackslash(Result) + '_forever_\Wow.exe') then
    Result := AddBackslash(Result) + '_forever_';
end;

procedure InitializeWizard;
begin
  GamePage := CreateInputDirPage(wpSelectTasks, CustomMessage('GameFolderTitle'),
    CustomMessage('GameFolderTitle'), CustomMessage('GameFolderInfo'), False, '');
  GamePage.Add(CustomMessage('GameFolderPrompt'));
  if DirExists('D:\World of Warcraft\_forever_') then
    GamePage.Values[0] := 'D:\World of Warcraft\_forever_'
  else
    GamePage.Values[0] := ExpandConstant('{pf32}\World of Warcraft\_forever_');
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := (PageID = GamePage.ID) and not WizardIsTaskSelected('addon');
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if (CurPageID = GamePage.ID) and not FileExists(AddBackslash(GameRoot) + 'Wow.exe') then begin
    MsgBox(CustomMessage('BadGameFolder'), mbError, MB_OK);
    Result := False;
  end;
end;

procedure CopyTree(const Source, Dest: String);
var Find: TFindRec;
begin
  { An existing addon directory must not redirect writes outside the selected game. }
  if FindFirst(Dest, Find) then begin
    try
      if (Find.Attributes and $400) <> 0 then RaiseException('Cannot update linked addon directory ' + Dest);
    finally FindClose(Find); end;
  end;
  if not ForceDirectories(Dest) then RaiseException('Cannot create ' + Dest);
  if FindFirst(AddBackslash(Source) + '*', Find) then begin
    try
      repeat
        if (Find.Name <> '.') and (Find.Name <> '..') then begin
          if (Find.Attributes and $400) <> 0 then
            RaiseException('Cannot copy linked addon path ' + Find.Name);
          if (Find.Attributes and FILE_ATTRIBUTE_DIRECTORY) <> 0 then
            CopyTree(AddBackslash(Source) + Find.Name, AddBackslash(Dest) + Find.Name)
          else begin
            if not FileCopy(AddBackslash(Source) + Find.Name, AddBackslash(Dest) + Find.Name, False) then
              RaiseException('Cannot copy addon file ' + Find.Name);
            if GetSHA256OfFile(AddBackslash(Source) + Find.Name) <> GetSHA256OfFile(AddBackslash(Dest) + Find.Name) then
              RaiseException('Addon file verification failed: ' + Find.Name);
          end;
        end;
      until not FindNext(Find);
    finally FindClose(Find); end;
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var Destination, Backup, Name: String; I: Integer;
begin
  if (CurStep = ssPostInstall) and WizardIsTaskSelected('addon') then begin
    if not FileExists(AddBackslash(GameRoot) + 'Wow.exe') then RaiseException(CustomMessage('BadGameFolder'));
    Backup := ExpandConstant('{localappdata}\Evertally\AddonBackups\') + GetDateTimeString('yyyymmdd-hhnnss', '', '');
    for I := 0 to 2 do begin
      if I = 0 then Name := 'Evertally' else if I = 1 then Name := 'Evertally_Export' else Name := 'Evertally_Map';
      Destination := AddBackslash(GameRoot) + 'Interface\AddOns\' + Name;
      if DirExists(Destination) then CopyTree(Destination, AddBackslash(Backup) + Name);
      CopyTree(ExpandConstant('{app}\addon\') + Name, Destination);
    end;
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var ExitCode: Integer;
begin
  if CurUninstallStep = usUninstall then
    Exec(ExpandConstant('{app}\EvertallyBackground.exe'), '--stop', '', SW_HIDE, ewWaitUntilTerminated, ExitCode);
  { User configuration, recorded game data and game addons are intentionally preserved. }
end;
