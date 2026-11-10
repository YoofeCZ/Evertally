param([string]$Server = 'https://evertally.afstudio.dev')
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath($PSScriptRoot)
$serverUri = [Uri]$Server
if ($serverUri.Scheme -ne 'https' -and -not ($serverUri.Scheme -eq 'http' -and $serverUri.IsLoopback)) {
    throw 'Server musi pouzivat HTTPS nebo lokalni HTTP.'
}
$cargoPath = Join-Path $env:USERPROFILE '.cargo\bin\cargo.exe'
if (-not (Test-Path -LiteralPath $cargoPath)) { $cargoPath = (Get-Command cargo -ErrorAction Stop).Source }
$nativeRoot = Join-Path $projectRoot 'desktop\native'
$previousServer = $env:EVERTALLY_SERVER
try {
    $env:EVERTALLY_SERVER = $Server.TrimEnd('/')
    Push-Location -LiteralPath $nativeRoot
    try { & $cargoPath build --release; if ($LASTEXITCODE -ne 0) { throw 'Sestaveni aplikace selhalo.' } }
    finally { Pop-Location }
    $binary = Join-Path $nativeRoot 'target\release\Evertally.exe'
    $releaseRoot = Join-Path $projectRoot 'releases'
    New-Item -ItemType Directory -Path $releaseRoot -Force | Out-Null
    @{server=$env:EVERTALLY_SERVER;sha256=(Get-FileHash -LiteralPath $binary -Algorithm SHA256).Hash.ToLowerInvariant()} |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $releaseRoot 'app-build.json') -Encoding utf8
    Write-Output ('Sestaveno pro server: ' + $env:EVERTALLY_SERVER)
} finally { $env:EVERTALLY_SERVER = $previousServer }
