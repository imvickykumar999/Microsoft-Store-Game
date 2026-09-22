param(
    [Parameter(Mandatory = $true)]
    [string]$Publisher,

    [string]$PublisherDisplayName = "Warzone3D",
    [string]$AppDisplayName = "DeathMatch3D",
    [string]$PackageName = "Warzone3D.DeathMatch3D",
    [string]$Version = "1.0.0.0",
    [string]$OutputDirectory = "dist",
    [string]$CertificatePath,
    [string]$CertificatePassword
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$sourceExe = Join-Path $repoRoot "play\client.exe"
$stageDirectory = Join-Path $repoRoot "build\msix"
$outputDirectoryPath = Join-Path $repoRoot $OutputDirectory
$packageDirectory = Join-Path $stageDirectory "package"
$stagedExe = Join-Path $packageDirectory "client.exe"
$manifestPath = Join-Path $packageDirectory "AppxManifest.xml"
$msixPath = Join-Path $outputDirectoryPath "$PackageName-$Version.msix"

if (-not (Test-Path $sourceExe)) {
    throw "Player executable not found: $sourceExe"
}

if ($Version -notmatch '^\d+\.\d+\.\d+\.\d+$') {
    throw "Version must have four numeric components, for example 1.0.0.0."
}

function Get-PeDetails([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    $peOffset = [BitConverter]::ToInt32($bytes, 0x3c)
    if ([Text.Encoding]::ASCII.GetString($bytes, $peOffset, 4) -ne "PE`0`0") {
        throw "Not a valid PE executable: $Path"
    }
    $fileHeaderOffset = $peOffset + 4
    $machine = [BitConverter]::ToUInt16($bytes, $fileHeaderOffset)
    $optionalHeaderOffset = $fileHeaderOffset + 20
    $subsystemOffset = $optionalHeaderOffset + 68
    [PSCustomObject]@{
        Bytes = $bytes
        Machine = $machine
        Subsystem = [BitConverter]::ToUInt16($bytes, $subsystemOffset)
        SubsystemOffset = $subsystemOffset
    }
}

function Set-WindowsSubsystem([string]$InputPath, [string]$OutputPath) {
    $details = Get-PeDetails $InputPath
    if ($details.Machine -ne 0x8664) {
        throw "client.exe is not x64 (machine 0x$('{0:X4}' -f $details.Machine)); update the manifest architecture before packaging."
    }
    if ($details.Subsystem -eq 2) {
        Copy-Item $InputPath $OutputPath -Force
        return
    }
    if ($details.Subsystem -ne 3) {
        throw "Unsupported PE subsystem: $($details.Subsystem)"
    }
    $details.Bytes[$details.SubsystemOffset] = 2
    $details.Bytes[$details.SubsystemOffset + 1] = 0
    [IO.File]::WriteAllBytes($OutputPath, $details.Bytes)
}

function Find-Tool([string]$Name) {
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    $kitsRoot = Join-Path ${env:ProgramFiles(x86)} "Windows Kits\10\bin"
    $candidate = Get-ChildItem $kitsRoot -Filter $Name -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match "\\x64\\$([regex]::Escape($Name))$" } |
        Sort-Object FullName -Descending |
        Select-Object -First 1
    if ($candidate) { return $candidate.FullName }
    throw "$Name was not found. Install the Windows SDK, then run this script again."
}

Remove-Item $stageDirectory -Recurse -Force -ErrorAction SilentlyContinue
New-Item $packageDirectory -ItemType Directory -Force | Out-Null
New-Item $outputDirectoryPath -ItemType Directory -Force | Out-Null

Set-WindowsSubsystem $sourceExe $stagedExe
if ((Get-PeDetails $stagedExe).Subsystem -ne 2) {
    throw "The staged player is still a console application."
}

$manifest = @"
<?xml version="1.0" encoding="utf-8"?>
<Package xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10"
         xmlns:uap="http://schemas.microsoft.com/appx/manifest/uap/windows10"
         xmlns:rescap="http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities"
         IgnorableNamespaces="uap rescap">
  <Identity Name="$PackageName" Publisher="$Publisher" Version="$Version" />
  <Properties>
    <DisplayName>$AppDisplayName</DisplayName>
    <PublisherDisplayName>$PublisherDisplayName</PublisherDisplayName>
    <Description>Deathmatch 3D multiplayer FPS</Description>
    <Logo>logo.png</Logo>
  </Properties>
  <Resources>
    <Resource Language="en-us" />
  </Resources>
  <Dependencies>
    <TargetDeviceFamily Name="Windows.Desktop" MinVersion="10.0.17763.0" MaxVersionTested="10.0.26100.0" />
  </Dependencies>
  <Applications>
        <Application Id="Warzone3D" Executable="client.exe" EntryPoint="Windows.FullTrustApplication">
            <uap:VisualElements AppListEntry="default" DisplayName="$AppDisplayName" Description="Deathmatch 3D multiplayer FPS" BackgroundColor="#111111" Square150x150Logo="logo.png" Square44x44Logo="logo.png" />
    </Application>
  </Applications>
  <Capabilities>
    <Capability Name="internetClient" />
    <Capability Name="privateNetworkClientServer" />
        <rescap:Capability Name="runFullTrust" />
  </Capabilities>
</Package>
"@
[IO.File]::WriteAllText($manifestPath, $manifest, [Text.UTF8Encoding]::new($false))
Copy-Item (Join-Path $repoRoot "assets\logo.png") (Join-Path $packageDirectory "logo.png") -Force

$makeAppx = Find-Tool "makeappx.exe"
& $makeAppx pack /d $packageDirectory /p $msixPath /o
if ($LASTEXITCODE -ne 0) {
    throw "MakeAppx failed with exit code $LASTEXITCODE."
}

if ($CertificatePath) {
    $signTool = Find-Tool "signtool.exe"
    $signArguments = @("sign", "/fd", "SHA256", "/f", $CertificatePath)
    if ($CertificatePassword) { $signArguments += @("/p", $CertificatePassword) }
    $signArguments += $msixPath
    & $signTool @signArguments
    if ($LASTEXITCODE -ne 0) {
        throw "SignTool failed with exit code $LASTEXITCODE."
    }
}

Write-Host "Created: $msixPath"
if (-not $CertificatePath) {
    Write-Warning "The package is unsigned. Sign it with the certificate identity registered in Partner Center before local installation."
}