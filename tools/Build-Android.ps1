param([switch]$Release, [switch]$Debug)
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath (Join-Path $PSScriptRoot '..')
$flutterCommand=Get-Command flutter -ErrorAction SilentlyContinue
$flutterPath=if($flutterCommand){$flutterCommand.Source}elseif(Test-Path -LiteralPath 'D:\tools\flutter\bin\flutter.bat'){'D:\tools\flutter\bin\flutter.bat'}else{throw 'Flutter SDK not found.'}
if($Release -and -not(Test-Path -LiteralPath 'android/key.properties')){throw 'Run tools/Create-Signing.ps1 first.'}
if($Release -and $Debug){throw 'Choose either -Release or -Debug.'}
& $flutterPath pub get
if($LASTEXITCODE -ne 0){throw 'Dependency installation failed.'}
$mode=if($Release){'--release'}elseif($Debug){'--debug'}else{'--profile'}
& $flutterPath build apk $mode
if($LASTEXITCODE -ne 0){throw 'Android build failed. Check flutter doctor -v, JDK 17 and Android SDK.'}
Write-Host 'APK: build/app/outputs/flutter-apk/'
