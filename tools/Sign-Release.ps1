param(
    [Parameter(Mandatory=$true)][string]$InputDirectory,
    [Parameter(Mandatory=$true)][string]$BuildToolsDirectory,
    [Parameter(Mandatory=$true)][string]$OutputDirectory
)
$ErrorActionPreference = 'Stop'
$workspace = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$inputRoot = (Resolve-Path -LiteralPath $InputDirectory).Path
$buildTools = (Resolve-Path -LiteralPath $BuildToolsDirectory).Path
$outputRoot = [IO.Path]::GetFullPath($OutputDirectory)
$signer = Join-Path $buildTools 'lib/apksigner.jar'
$zipalign = Join-Path $buildTools 'zipalign.exe'
$aapt = Join-Path $buildTools 'aapt.exe'
foreach ($tool in @($signer, $zipalign, $aapt)) {
    if (-not (Test-Path -LiteralPath $tool)) { throw 'Use the Windows Android SDK Build Tools directory containing aapt.exe, zipalign.exe and lib/apksigner.jar.' }
}
$java = if ($env:JAVA_HOME) { Join-Path $env:JAVA_HOME 'bin/java.exe' } else { (Get-Command java -ErrorAction Stop).Source }
$provenance = Get-Content -LiteralPath (Join-Path $inputRoot 'build-info.json') -Raw | ConvertFrom-Json
if ($provenance.mode -ne 'release' -or $provenance.signed -ne $false) { throw 'Expected an explicitly unsigned release preparation artifact.' }
if ($provenance.version -notmatch '^(\d+\.\d+\.\d+)\+(\d+)$') { throw 'Invalid release version.' }
$version = $Matches[1]
$buildNumber = [int]$Matches[2]
$sourceVersion = (Select-String -LiteralPath (Join-Path $workspace 'pubspec.yaml') -Pattern '^version:\s*(.+)$').Matches[0].Groups[1].Value.Trim()
if ($sourceVersion -ne $provenance.version) { throw 'Artifact version does not match the checkout.' }
$checkoutCommit = (& git -C $workspace rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $checkoutCommit -ne $provenance.commit) { throw 'Artifact commit does not match the checkout. Check out the release tag before signing.' }
$config = @{}
foreach ($line in (Get-Content -LiteralPath (Join-Path $workspace 'android/key.properties'))) {
    if ($line.TrimStart().StartsWith('#')) { continue }
    $pair = $line -split '=', 2
    if ($pair.Count -eq 2) { $config[$pair[0].Trim()] = $pair[1].Trim() }
}
foreach ($name in @('storeFile', 'keyAlias', 'storePassword', 'keyPassword')) {
    if (-not $config[$name]) { throw 'Incomplete private signing configuration.' }
}
$store = $config['storeFile']
if (-not [IO.Path]::IsPathRooted($store)) { $store = Join-Path $workspace "android/app/$store" }
if (-not (Test-Path -LiteralPath $store)) { throw 'Private keystore not found.' }
$abis = @('arm64-v8a', 'armeabi-v7a', 'x86_64')
foreach ($abi in $abis) {
    $filename = "app-$abi-release.apk"
    $path = Join-Path $inputRoot $filename
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $provenance.files.$filename) { throw "Build artifact hash mismatch: $filename" }
    if (Test-Path -LiteralPath (Join-Path $outputRoot "Manxia-$version-$abi.apk")) { throw 'Output APK already exists. Choose a new output directory.' }
}
New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
$env:MANXIA_SIGN_STORE_PASS = $config['storePassword']
$env:MANXIA_SIGN_KEY_PASS = $config['keyPassword']
$checksums = @()
$packages = @()
$expectedCertificate = $null
try {
    foreach ($abi in $abis) {
        $inputApk = Join-Path $inputRoot "app-$abi-release.apk"
        $aligned = Join-Path $outputRoot "$abi-aligned.unsigned"
        $outputName = "Manxia-$version-$abi.apk"
        $outputApk = Join-Path $outputRoot $outputName
        $badging = (& $aapt dump badging $inputApk) -join "`n"
        if ($LASTEXITCODE -ne 0 -or $badging -notmatch "package: name='io.manxia.manxia'" -or $badging -notmatch "versionName='$([regex]::Escape($version))'" -or $badging -match 'application-debuggable') { throw "Invalid release package: $abi" }
        if ($badging -notmatch "native-code: '$([regex]::Escape($abi))'") { throw "Unexpected package architecture: $abi" }
        if ($badging -notmatch "sdkVersion:'24'") { throw "Unexpected minimum Android SDK: $abi" }
        $versionCode = [int]([regex]::Match($badging, "versionCode='(\d+)'").Groups[1].Value)
        $abiCode = switch ($abi) { 'armeabi-v7a' { 1 }; 'arm64-v8a' { 2 }; 'x86_64' { 4 } }
        if ($versionCode -ne (1000 * $abiCode + $buildNumber)) { throw "Unexpected split APK version code: $abi" }
        & $zipalign -P 16 4 $inputApk $aligned
        if ($LASTEXITCODE -ne 0) { throw "Alignment failed: $abi" }
        & $java -jar $signer sign --ks $store --ks-key-alias $config['keyAlias'] --ks-pass env:MANXIA_SIGN_STORE_PASS --key-pass env:MANXIA_SIGN_KEY_PASS --v4-signing-enabled false --out $outputApk $aligned
        if ($LASTEXITCODE -ne 0) { throw "Signing failed: $abi" }
        $verification = (& $java -jar $signer verify --verbose --print-certs $outputApk) -join "`n"
        if ($LASTEXITCODE -ne 0) { throw "Signature verification failed: $abi" }
        & $zipalign -c -P 16 4 $outputApk
        if ($LASTEXITCODE -ne 0) { throw "Signed APK alignment check failed: $abi" }
        $certificate = [regex]::Match($verification, 'Signer #1 certificate SHA-256 digest: ([0-9a-f]+)').Groups[1].Value
        if ($certificate.Length -ne 64) { throw 'Signing certificate digest missing.' }
        if ($expectedCertificate -and $certificate -ne $expectedCertificate) { throw 'Signing certificates differ between architectures.' }
        $expectedCertificate = $certificate
        $hash = (Get-FileHash -LiteralPath $outputApk -Algorithm SHA256).Hash.ToLowerInvariant()
        $checksums += "$hash  $outputName"
        $packages += [ordered]@{name=$outputName; abi=$abi; versionCode=$versionCode; bytes=(Get-Item -LiteralPath $outputApk).Length; sha256=$hash}
        [IO.File]::WriteAllText((Join-Path $outputRoot "$abi-verification.txt"), $verification, [Text.UTF8Encoding]::new($false))
        Remove-Item -LiteralPath $aligned
    }
    [IO.File]::WriteAllLines((Join-Path $outputRoot 'SHA256SUMS.txt'), $checksums, [Text.UTF8Encoding]::new($false))
    $manifest = [ordered]@{version=$provenance.version; mode='release'; applicationId='io.manxia.manxia'; minSdk=24; commit=$provenance.commit; buildRun="https://github.com/LexianLix/manxia/actions/runs/$($provenance.run)"; signingCertificateSha256=$expectedCertificate; packages=$packages}
    [IO.File]::WriteAllText((Join-Path $outputRoot 'release-manifest.json'), ($manifest | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
    Write-Output ($manifest | ConvertTo-Json -Depth 6)
} finally {
    Remove-Item Env:MANXIA_SIGN_STORE_PASS -ErrorAction SilentlyContinue
    Remove-Item Env:MANXIA_SIGN_KEY_PASS -ErrorAction SilentlyContinue
    $config.Clear()
}
