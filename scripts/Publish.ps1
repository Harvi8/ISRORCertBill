param(
    [string] $ProjectPath = "src\ISRORUnified\ISRORUnified.csproj",
    [string] $Configuration = "Release",
    [string] $Runtime = "win-x64",
    [string] $OutputPath = "artifacts\publish\win-x64",
    [switch] $SelfContained,
    [switch] $FrameworkDependent,
    [switch] $KeepSymbols,
    [switch] $KeepIisWebConfig,
    [switch] $KeepStaticWebAssets,
    [switch] $OverwriteAppSettings,
    [switch] $ReleaseZip,
    [string] $ReleasePath = "artifacts\release",
    [string] $ReleaseFileName = ""
)

$ErrorActionPreference = "Stop"

if ($SelfContained -and $FrameworkDependent) {
    throw "Use either -SelfContained or -FrameworkDependent, not both."
}

if ($ReleaseZip -and $FrameworkDependent) {
    throw "Release zip must be self-contained so it can run without a separate .NET runtime. Remove -FrameworkDependent."
}

function Get-WorkspacePath {
    param([string] $Path)

    $workspaceRoot = [System.IO.Path]::GetFullPath((Get-Location).Path).TrimEnd("\", "/")
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $workspacePrefix = $workspaceRoot + [System.IO.Path]::DirectorySeparatorChar

    if ($fullPath -ne $workspaceRoot -and -not $fullPath.StartsWith($workspacePrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to use path outside the workspace: $fullPath"
    }

    return $fullPath
}

function Clear-PublishOutput {
    param([string] $Path)

    $fullPath = Get-WorkspacePath $Path

    if (Test-Path -LiteralPath $fullPath) {
        Remove-Item -LiteralPath $fullPath -Recurse -Force
    }

    New-Item -ItemType Directory -Path $fullPath -Force | Out-Null
}

function Assert-CompactReleaseLayout {
    param([string] $Path)

    $requiredItems = @("ISRORUnified.exe", "appsettings.json", "Database", "Patches")
    foreach ($name in $requiredItems) {
        $itemPath = Join-Path $Path $name
        if (-not (Test-Path -LiteralPath $itemPath)) {
            throw "Missing expected release item: $name"
        }
    }

    $allowedTopLevelFiles = @("ISRORUnified.exe", "appsettings.json")
    $unexpectedFiles = Get-ChildItem -LiteralPath $Path -File |
        Where-Object { $allowedTopLevelFiles -notcontains $_.Name }

    if ($unexpectedFiles) {
        $names = ($unexpectedFiles | Select-Object -ExpandProperty Name) -join ", "
        throw "Unexpected top-level release files: $names"
    }
}

function New-ReleaseZip {
    param(
        [string] $PublishPath,
        [string] $DestinationPath,
        [string] $FileName
    )

    $publishFullPath = Get-WorkspacePath $PublishPath
    $destinationFullPath = Get-WorkspacePath $DestinationPath
    $zipFullPath = Get-WorkspacePath (Join-Path $destinationFullPath $FileName)

    New-Item -ItemType Directory -Path $destinationFullPath -Force | Out-Null
    if (Test-Path -LiteralPath $zipFullPath) {
        Remove-Item -LiteralPath $zipFullPath -Force
    }

    Compress-Archive -Path (Join-Path $publishFullPath "*") -DestinationPath $zipFullPath -Force
    return $zipFullPath
}

$selfContainedValue = -not $FrameworkDependent
$publishedAppSettingsPath = Join-Path $OutputPath "appsettings.json"
$existingAppSettings = $null
if (-not $OverwriteAppSettings -and (Test-Path -LiteralPath $publishedAppSettingsPath)) {
    $existingAppSettings = Get-Content -LiteralPath $publishedAppSettingsPath -Raw
}

$arguments = @(
    "publish",
    $ProjectPath,
    "--configuration",
    $Configuration,
    "--runtime",
    $Runtime,
    "--output",
    $OutputPath
)

$arguments += "--self-contained"
$arguments += $selfContainedValue.ToString().ToLowerInvariant()
$arguments += "/p:PublishSingleFile=true"
$arguments += "/p:IncludeNativeLibrariesForSelfExtract=true"
$arguments += "/p:DebugType=$(if ($KeepSymbols) { 'portable' } else { 'None' })"
$arguments += "/p:DebugSymbols=$(if ($KeepSymbols) { 'true' } else { 'false' })"
$arguments += "/p:IsTransformWebConfigDisabled=$(if ($KeepIisWebConfig) { 'false' } else { 'true' })"
$arguments += "/p:StaticWebAssetsEnabled=$(if ($KeepStaticWebAssets) { 'true' } else { 'false' })"

Write-Host "Publishing $ProjectPath to $OutputPath..."
Write-Host "Mode: $(if ($selfContainedValue) { 'self-contained single-file' } else { 'framework-dependent single-file' })"
Clear-PublishOutput $OutputPath
& dotnet @arguments
if ($LASTEXITCODE -ne 0) {
    throw "dotnet $($arguments -join ' ') failed with exit code $LASTEXITCODE."
}

if ($null -ne $existingAppSettings) {
    Set-Content -LiteralPath $publishedAppSettingsPath -Value $existingAppSettings -NoNewline
    Write-Host "Preserved existing published appsettings.json. Use -OverwriteAppSettings to replace it from source."
}

Write-Host "Publish complete: $OutputPath"

if ($ReleaseZip) {
    if ([string]::IsNullOrWhiteSpace($ReleaseFileName)) {
        $projectName = [System.IO.Path]::GetFileNameWithoutExtension($ProjectPath)
        $ReleaseFileName = "$projectName-$Runtime.zip"
    }

    if ([System.IO.Path]::GetExtension($ReleaseFileName) -ne ".zip") {
        $ReleaseFileName = "$ReleaseFileName.zip"
    }

    Write-Host "Verifying compact release layout..."
    Assert-CompactReleaseLayout $OutputPath

    Write-Host "Packing release zip..."
    $zipPath = New-ReleaseZip -PublishPath $OutputPath -DestinationPath $ReleasePath -FileName $ReleaseFileName
    Write-Host "Release zip complete: $zipPath"
}
