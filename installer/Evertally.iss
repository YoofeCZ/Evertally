#ifndef ProjectRoot
  #define ProjectRoot ".."
#endif
#ifndef AppVersion
  #define AppVersion "0.3.0"
#endif

[Setup]
AppId={{E4B4CA9F-1AF0-4D54-9014-134751D724E9}
AppName=Evertally Bridge
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
english.StartBackground=Open Evertally and pair this PC with the website (the bridge starts by the clock)
czech.StartBackground=Otevřít Evertally a spárovat počítač s webem (most se spustí vedle hodin)

[Tasks]
Name: "startwow"; Description: "{cm:StartWoW}"; GroupDescription: "Evertally:"; Flags: checkedonce
Name: "desktopicon"; Description: "{cm:DesktopShortcut}"; GroupDescription: "Evertally:"; Flags: unchecked
Name: "addon"; Description: "{cm:AddonTask}"; GroupDescription: "World of Warcraft:"

[Files]
Source: "{#ProjectRoot}\desktop\native\target\release\Evertally.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#ProjectRoot}\desktop\native\target\release\EvertallyBackground.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#ProjectRoot}\addon\Evertally\*"; DestDir: "{app}\addon\Evertally"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#ProjectRoot}\addon\Evertally_Export\*"; DestDir: "{app}\addon\Evertally_Export"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#ProjectRoot}\addon\Evertally_Map\*"; DestDir: "{app}\addon\Evertally_Map"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Evertally — Web sync"; Filename: "{app}\Evertally.exe"; Parameters: "--connection-settings"; AppUserModelID: "AFStudio.Evertally"
Name: "{group}\{cm:UninstallProgram,Evertally}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Evertally"; Filename: "{app}\Evertally.exe"; Parameters: "--connection-settings"; Tasks: desktopicon

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "EvertallySync"; ValueData: """{app}\EvertallyBackground.exe"""; Tasks: startwow; Flags: uninsdeletevalue
; The app's own "Start with Windows" setting writes this value; uninstalling removes it.
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: none; ValueName: "EvertallyStartup"; Flags: uninsdeletevalue dontcreatekey

[Run]
Filename: "{app}\EvertallyBackground.exe"; Tasks: startwow; Flags: nowait runhidden
; The first start shows the connection window with the steps to pair; it starts the tray bridge as well.
Filename: "{app}\Evertally.exe"; Parameters: "--connection-settings"; Description: "{cm:StartBackground}"; Flags: postinstall nowait skipifsilent
; A silent update (the bridge updating itself) must leave the bridge running again: Setup closed it, and nobody clicks "Start" on the last page.
Filename: "{app}\Evertally.exe"; Check: WizardSilent; Flags: nowait
Filename: "{app}\EvertallyBackground.exe"; Check: SilentWithAutostart; Flags: nowait runhidden

[Code]
var GamePage: TInputDirWizardPage;

function OpenEvent(Access: LongWord; Inherit: Boolean; Name: String): THandle;
  external 'OpenEventW@kernel32.dll stdcall';
function SignalEvent(Event: THandle): Boolean;
  external 'SetEvent@kernel32.dll stdcall';
function ReleaseEvent(Event: THandle): Boolean;
  external 'CloseHandle@kernel32.dll stdcall';

procedure StopOwnedEvent(const Name: String);
var Event: THandle;
begin
  Event := OpenEvent(2, False, Name);
  if Event <> 0 then begin
    try SignalEvent(Event); finally ReleaseEvent(Event); end;
  end;
end;

procedure StopBridge;
var I: Integer;
begin
  StopOwnedEvent('Local\EvertallyBackgroundStop');
  StopOwnedEvent('Local\EvertallyBridgeStop');
  StopOwnedEvent('Local\EvertallyConnectionSettingsStop');
  for I := 1 to 30 do begin
    if not CheckForMutexes('Local\EvertallyBackgroundSingleInstance,Local\EvertallySyncSingleInstance,Local\EvertallyConnectionSettings') then Break;
    Sleep(100);
  end;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  { Gracefully stop only this application's processes before Restart Manager checks locks. }
  StopBridge;
  Result := '';
end;

function SilentWithAutostart: Boolean;
begin
  Result := WizardSilent and RegValueExists(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Run', 'EvertallySync');
end;

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

procedure CopyTree(const Source, Dest: String; PreserveForumData: Boolean);
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
            CopyTree(AddBackslash(Source) + Find.Name, AddBackslash(Dest) + Find.Name, PreserveForumData)
          else begin
            { This file is maintained by the running bridge and contains the forum snapshot. }
            if not (PreserveForumData and ((CompareText(Find.Name, 'ForumData.lua') = 0) or (CompareText(Find.Name, 'CommunityData.lua') = 0)) and FileExists(AddBackslash(Dest) + Find.Name)) then begin
              if not FileCopy(AddBackslash(Source) + Find.Name, AddBackslash(Dest) + Find.Name, False) then
                RaiseException('Cannot copy addon file ' + Find.Name);
              if GetSHA256OfFile(AddBackslash(Source) + Find.Name) <> GetSHA256OfFile(AddBackslash(Dest) + Find.Name) then
                RaiseException('Addon file verification failed: ' + Find.Name);
            end;
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
    Backup := ExpandConstant('{localappdata}\Evertally\AddonBackups\') + GetDateTimeString('yyyymmdd-hhnnss', '-', ':');
    for I := 0 to 2 do begin
      if I = 0 then Name := 'Evertally' else if I = 1 then Name := 'Evertally_Export' else Name := 'Evertally_Map';
      Destination := AddBackslash(GameRoot) + 'Interface\AddOns\' + Name;
      if DirExists(Destination) then CopyTree(Destination, AddBackslash(Backup) + Name, False);
      CopyTree(ExpandConstant('{app}\addon\') + Name, Destination, True);
    end;
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then
    StopBridge;
  { User configuration, recorded game data and game addons are intentionally preserved. }
end;
