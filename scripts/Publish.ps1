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
    [switch] $OverwriteAppSettings
)

$ErrorActionPreference = "Stop"

if ($SelfContained -and $FrameworkDependent) {
    throw "Use either -SelfContained or -FrameworkDependent, not both."
}

function Clear-PublishOutput {
    param([string] $Path)

    $workspaceRoot = [System.IO.Path]::GetFullPath((Get-Location).Path).TrimEnd("\", "/")
    $fullPath = [System.IO.Path]::GetFullPath($Path)

    if (-not $fullPath.StartsWith($workspaceRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to clean publish output outside the workspace: $fullPath"
    }

    if (Test-Path -LiteralPath $fullPath) {
        Remove-Item -LiteralPath $fullPath -Recurse -Force
    }

    New-Item -ItemType Directory -Path $fullPath -Force | Out-Null
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
