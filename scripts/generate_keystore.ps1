<#
.SYNOPSIS
    Generates an Android release keystore and optionally writes android/key.properties.

.DESCRIPTION
    Locates keytool.exe from PATH, JAVA_HOME, Android Studio JBR, cached Gradle JDKs,
    or standard Java installations, generates a 2048-bit RSA PKCS12 keystore
    (gitignored), and optionally creates android/key.properties (gitignored).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts/generate_keystore.ps1 -WriteKeyProperties

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts/generate_keystore.ps1 -StorePassword "your-strong-password" -WriteKeyProperties -Force
#>
[CmdletBinding()]
param(
    [string]$KeystorePath = "android/app/clearwash-release.jks",
    [string]$KeyPropertiesPath = "android/key.properties",
    [string]$KeyAlias = "clearwash",
    [string]$StorePassword = "",
    [string]$KeyPassword = "",
    [string]$Dname = "CN=ClearWash POS, OU=Engineering, O=ClearWash, L=Jakarta, ST=DKI Jakarta, C=ID",
    [int]$ValidityDays = 10000,
    [switch]$WriteKeyProperties,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

function Resolve-RepoPath {
    param([string]$PathValue, [string]$RepoRoot)
    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return [System.IO.Path]::GetFullPath($PathValue)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $PathValue))
}

function Find-Keytool {
    $cmd = Get-Command keytool -ErrorAction SilentlyContinue
    if ($cmd -and (Test-Path $cmd.Source)) {
        return $cmd.Source
    }

    $candidates = New-Object System.Collections.Generic.List[string]

    if ($env:JAVA_HOME) {
        $candidates.Add((Join-Path $env:JAVA_HOME "bin\keytool.exe"))
    }

    if ($env:ProgramFiles) {
        $candidates.Add((Join-Path $env:ProgramFiles "Android\Android Studio\jbr\bin\keytool.exe"))
    }
    if ($env:LOCALAPPDATA) {
        $candidates.Add((Join-Path $env:LOCALAPPDATA "Programs\Android Studio\jbr\bin\keytool.exe"))
    }

    $wildcardRoots = @(
        (Join-Path $env:USERPROFILE ".gradle\jdks\*\bin\keytool.exe"),
        (Join-Path $env:ProgramFiles "Java\*\bin\keytool.exe"),
        (Join-Path $env:ProgramFiles "Eclipse Adoptium\*\bin\keytool.exe"),
        (Join-Path $env:ProgramFiles "Microsoft\jdk*\bin\keytool.exe")
    )

    foreach ($pattern in $wildcardRoots) {
        if ($pattern) {
            Get-Item -Path $pattern -ErrorAction SilentlyContinue |
                Sort-Object FullName -Descending |
                ForEach-Object { $candidates.Add($_.FullName) }
        }
    }

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path $candidate)) {
            return $candidate
        }
    }

    return $null
}

function ConvertFrom-SecureStringPlain {
    param([Security.SecureString]$SecureValue)
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureValue)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$resolvedKeystore = Resolve-RepoPath -PathValue $KeystorePath -RepoRoot $repoRoot
$resolvedKeyProperties = Resolve-RepoPath -PathValue $KeyPropertiesPath -RepoRoot $repoRoot

$keytool = Find-Keytool
if (-not $keytool) {
    Write-Error "Could not locate keytool.exe. Install a JDK / Android Studio or add keytool to PATH."
    exit 1
}

if ((Test-Path $resolvedKeystore) -and (-not $Force)) {
    Write-Error "Keystore already exists at '$resolvedKeystore'. Pass -Force to overwrite it."
    exit 1
}

if ([string]::IsNullOrEmpty($StorePassword)) {
    $secureStore = Read-Host -Prompt "Enter keystore password (minimum 6 characters)" -AsSecureString
    $secureConfirm = Read-Host -Prompt "Confirm keystore password" -AsSecureString
    $StorePassword = ConvertFrom-SecureStringPlain -SecureValue $secureStore
    $confirmPassword = ConvertFrom-SecureStringPlain -SecureValue $secureConfirm

    if ($StorePassword -ne $confirmPassword) {
        Write-Error "Passwords do not match."
        exit 1
    }
}

if ($StorePassword.Length -lt 6) {
    Write-Error "Keystore password must be at least 6 characters long."
    exit 1
}

if ([string]::IsNullOrEmpty($KeyPassword)) {
    $KeyPassword = $StorePassword
}

if ($KeyPassword.Length -lt 6) {
    Write-Error "Key password must be at least 6 characters long."
    exit 1
}

$keystoreDir = Split-Path -Parent $resolvedKeystore
if (-not (Test-Path $keystoreDir)) {
    New-Item -ItemType Directory -Path $keystoreDir -Force | Out-Null
}

if ((Test-Path $resolvedKeystore) -and $Force) {
    Remove-Item -Path $resolvedKeystore -Force
}

Write-Host "Using keytool: $keytool"
& $keytool -genkeypair `
    -keystore $resolvedKeystore `
    -alias $KeyAlias `
    -keyalg RSA `
    -keysize 2048 `
    -validity $ValidityDays `
    -storetype PKCS12 `
    -dname $Dname `
    -storepass $StorePassword `
    -keypass $KeyPassword

if ($LASTEXITCODE -ne 0) {
    Write-Error "keytool failed with exit code $LASTEXITCODE."
    exit $LASTEXITCODE
}

Write-Host "Generated keystore at: $resolvedKeystore"

if ($WriteKeyProperties -or (-not (Test-Path $resolvedKeyProperties))) {
    $androidAppDir = [System.IO.Path]::GetFullPath((Join-Path $repoRoot "android\app"))
    $storeFileValue = $resolvedKeystore
    if ($resolvedKeystore.StartsWith($androidAppDir, [System.StringComparison]::OrdinalIgnoreCase)) {
        $storeFileValue = $resolvedKeystore.Substring($androidAppDir.Length).TrimStart('\', '/').Replace('\', '/')
    }
    else {
        $storeFileValue = $resolvedKeystore.Replace('\', '/')
    }

    $propertiesContent = @(
        "storePassword=$StorePassword"
        "keyPassword=$KeyPassword"
        "keyAlias=$KeyAlias"
        "storeFile=$storeFileValue"
    ) -join "`n"
    $propertiesContent += "`n"

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($resolvedKeyProperties, $propertiesContent, $utf8NoBom)
    Write-Host "Wrote key properties to: $resolvedKeyProperties"
}
