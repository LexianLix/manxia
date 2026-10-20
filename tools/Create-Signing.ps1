$ErrorActionPreference = 'Stop'
$workspace = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$privateDirectory = Join-Path $workspace '.private'
$storePath = Join-Path $privateDirectory 'manxia-release.jks'
$propertiesPath = Join-Path $workspace 'android/key.properties'
if ((Test-Path -LiteralPath $storePath) -or (Test-Path -LiteralPath $propertiesPath)) {
    throw 'Signing files already exist. They will not be replaced; an upgrade must use the original key.'
}
$keytoolCommand = Get-Command keytool -ErrorAction SilentlyContinue
$keytoolPath = if ($env:JAVA_HOME -and (Test-Path -LiteralPath (Join-Path $env:JAVA_HOME 'bin/keytool.exe'))) {
    Join-Path $env:JAVA_HOME 'bin/keytool.exe'
} elseif ($keytoolCommand) { $keytoolCommand.Source } else { throw 'Install JDK 17 and set JAVA_HOME for this terminal first.' }
$random = New-Object byte[] 32
$generator = [Security.Cryptography.RandomNumberGenerator]::Create()
$generator.GetBytes($random)
$generator.Dispose()
$env:MANXIA_STORE_PASS = [Convert]::ToBase64String($random)
try {
    New-Item -ItemType Directory -Path $privateDirectory -Force | Out-Null
    & $keytoolPath -genkeypair -alias manxia -keyalg RSA -keysize 3072 -sigalg SHA256withRSA -validity 10000 -storetype JKS -keystore $storePath -storepass:env MANXIA_STORE_PASS -keypass:env MANXIA_STORE_PASS -dname 'CN=Manxia Local Release'
    if ($LASTEXITCODE -ne 0) { throw 'Key generation failed. No build configuration was written.' }
    $normalizedPath = $storePath.Replace('\','/')
    [IO.File]::WriteAllLines($propertiesPath, @(
        '# Private local signing configuration. Do not commit or share this file.'
        "storeFile=$normalizedPath"
        'keyAlias=manxia'
        "storePassword=$env:MANXIA_STORE_PASS"
        "keyPassword=$env:MANXIA_STORE_PASS"
    ), [Text.UTF8Encoding]::new($false))
    Write-Host 'Local release key created. Back up .private/manxia-release.jks and android/key.properties together in a private location.'
} finally {
    Remove-Item Env:MANXIA_STORE_PASS -ErrorAction SilentlyContinue
    [Array]::Clear($random,0,$random.Length)
}
