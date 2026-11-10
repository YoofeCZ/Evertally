param([switch]$SkipBuild, [string]$Server = 'https://evertally.afstudio.dev')
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath($PSScriptRoot)
if (-not $SkipBuild) { & (Join-Path $projectRoot 'Build-Release.ps1') -Server $Server }
$nativeRoot = Join-Path $projectRoot 'desktop\native'
foreach ($binaryName in @('Evertally.exe','EvertallyBackground.exe')) {
    if (-not (Test-Path -LiteralPath (Join-Path $nativeRoot ('target\release\' + $binaryName)))) {
        throw ('Chybi sestaveny soubor: ' + $binaryName)
    }
}
$compilerDir = Join-Path $projectRoot '.tools\innosetup'
$compiler = Join-Path $compilerDir 'tools\ISCC.exe'
if (-not (Test-Path -LiteralPath $compiler)) {
    New-Item -ItemType Directory -Path $compilerDir -Force | Out-Null
    $archive = Join-Path $compilerDir 'tools.innosetup.6.7.1.nupkg'
    Invoke-WebRequest -Uri 'https://api.nuget.org/v3-flatcontainer/tools.innosetup/6.7.1/tools.innosetup.6.7.1.nupkg' -OutFile $archive
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::ExtractToDirectory($archive, $compilerDir)
}
$signature = Get-AuthenticodeSignature -LiteralPath $compiler
if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'Pyrsys B\.V\.|Jordan Russell') {
    throw 'Overeni podpisu kompilatoru Inno Setup selhalo.'
}
$versionLine = Get-Content -LiteralPath (Join-Path $nativeRoot 'Cargo.toml') | Where-Object { $_ -match '^version = "([^"]+)"' } | Select-Object -First 1
if ($versionLine -notmatch '^version = "([^"]+)"') { throw 'Nelze nacist verzi aplikace.' }
$appVersion = $Matches[1]
& $compiler '/Qp' ('/DProjectRoot=' + $projectRoot) ('/DAppVersion=' + $appVersion) (Join-Path $projectRoot 'installer\Evertally.iss')
if ($LASTEXITCODE -ne 0) { throw 'Sestaveni instalatoru selhalo.' }
$setup = Join-Path $projectRoot 'releases\EvertallySetup.exe'
$manifest = @{file='EvertallySetup.exe';version=$appVersion;bytes=(Get-Item -LiteralPath $setup).Length;sha256=(Get-FileHash -LiteralPath $setup -Algorithm SHA256).Hash.ToLowerInvariant();kind='per-user-windows-installer';launchesDuringBuild=$false}
$manifest | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $projectRoot 'releases\installer-manifest.json') -Encoding utf8
Write-Output ('Sestaven instalator: ' + $setup)
