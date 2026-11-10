param([string]$TestRoot = (Join-Path $PSScriptRoot '..\..\output\installer-test'))
$ErrorActionPreference = 'Stop'
$project = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$test = Join-Path ([IO.Path]::GetFullPath($TestRoot)) ([guid]::NewGuid().ToString('N'))
$game = Join-Path $test 'game'
$package = Join-Path $test 'package'
New-Item -ItemType Directory -Force -Path $game, $package | Out-Null
Set-Content -LiteralPath (Join-Path $game 'Wow.exe') -Value 'test fixture' -Encoding utf8
foreach ($name in @('Evertally', 'Evertally_Export', 'Evertally_Map')) {
    $source = Join-Path $package $name
    $existing = Join-Path $game ('Interface\AddOns\' + $name)
    New-Item -ItemType Directory -Force -Path $source, $existing | Out-Null
    Set-Content -LiteralPath (Join-Path $source 'fixture.lua') -Value 'new fixture' -Encoding utf8
    Set-Content -LiteralPath (Join-Path $existing 'fixture.lua') -Value 'old fixture' -Encoding utf8
}
$original = Get-Content -LiteralPath (Join-Path $project 'installer\Evertally.iss') -Raw -Encoding UTF8
$code = $original.Substring($original.IndexOf('[Code]'))
$code = $code -replace "if DirExists\('D:\\World of Warcraft\\_forever_'\) then\s*GamePage.Values\[0\] := 'D:\\World of Warcraft\\_forever_'\s*else\s*GamePage.Values\[0\] := ExpandConstant\('\{pf32\}\\World of Warcraft\\_forever_'\);", "GamePage.Values[0] := '$game';"
if ($code -notmatch [regex]::Escape("GamePage.Values[0] := '$game';")) { throw 'Could not isolate the game path.' }
$code = $code.Replace("ExpandConstant('{localappdata}\Evertally\AddonBackups\')", "'$test\backup\'")
$head = @"
[Setup]
AppId={{E32A88D4-40A9-4667-90BE-65E544606AC1}
AppName=EvertallyFixture
AppVersion=1
DefaultDirName=$test\installed
PrivilegesRequired=lowest
Uninstallable=no
CloseApplications=no
OutputDir=$test
OutputBaseFilename=fixture-setup
Compression=none
[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
[CustomMessages]
english.GameFolderTitle=Game
english.GameFolderInfo=Game
english.GameFolderPrompt=Game
english.BadGameFolder=Bad game folder
[Tasks]
Name: "addon"; Description: "Addon"
[Files]
Source: "$package\*"; DestDir: "{app}\addon"; Flags: recursesubdirs createallsubdirs
"@
$script = Join-Path $test 'fixture.iss'
Set-Content -LiteralPath $script -Value ($head + "`r`n" + $code) -Encoding utf8
$compiler = Join-Path $project '.tools\innosetup\tools\ISCC.exe'
& $compiler '/Qp' $script
if ($LASTEXITCODE -ne 0) { throw 'Fixture compilation failed' }
$log = Join-Path $test 'setup.log'
$process = Start-Process -FilePath (Join-Path $test 'fixture-setup.exe') -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/NOCLOSEAPPLICATIONS', '/TASKS=addon', "/LOG=$log") -WindowStyle Hidden -Wait -PassThru
$logText = Get-Content -LiteralPath $log -Raw
if ($process.ExitCode -ne 0 -or $logText -match 'raised an exception|Runtime error') { throw "Fixture installer failed. Log: $log" }
foreach ($name in @('Evertally', 'Evertally_Export', 'Evertally_Map')) {
    $installed = Join-Path $game ('Interface\AddOns\' + $name + '\fixture.lua')
    $backup = Get-ChildItem -LiteralPath (Join-Path $test 'backup') -Recurse -Filter 'fixture.lua' | Where-Object { $_.Directory.Name -eq $name } | Select-Object -First 1
    if ((Get-Content -LiteralPath $installed -Raw).Trim() -ne 'new fixture' -or -not $backup -or (Get-Content -LiteralPath $backup.FullName -Raw).Trim() -ne 'old fixture') { throw "Backup or update failed for $name" }
}
Write-Output "Installer updated and backed up all three fixture addons. Log: $log"
