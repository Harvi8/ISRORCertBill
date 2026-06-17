param(
    [string] $ProjectPath = "src\ISRORUnified\ISRORUnified.csproj",
    [string] $PublishPath = "artifacts\publish\win-x64",
    [int] $ExpectedPublishTopLevelCount = 4,
    [int] $ExpectedPatchFileCount = 8,
    [int] $ExpectedDatabaseFileCount = 8,
    [switch] $SkipPublish,
    [switch] $SkipVulnerabilityScan,
    [switch] $KeepLogs
)

$ErrorActionPreference = "Stop"

function Invoke-Step {
    param(
        [string] $Name,
        [scriptblock] $Action
    )

    Write-Host ""
    Write-Host "== $Name =="
    & $Action
}

function Invoke-External {
    param([string[]] $Arguments)

    if ($Arguments.Length -eq 0) {
        throw "No command was provided."
    }

    $fileName = $Arguments[0]
    $commandArguments = @()
    if ($Arguments.Length -gt 1) {
        $commandArguments = $Arguments[1..($Arguments.Length - 1)]
    }

    & $fileName @commandArguments
    if ($LASTEXITCODE -ne 0) {
        throw "$($Arguments -join ' ') failed with exit code $LASTEXITCODE."
    }
}

function Assert-PathExists {
    param([string] $Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Expected path to exist: $Path"
    }
}

function Assert-Equal {
    param(
        [object] $Actual,
        [object] $Expected,
        [string] $Message
    )

    if ($Actual -ne $Expected) {
        throw "$Message Expected [$Expected], got [$Actual]."
    }
}

function Assert-ScriptParses {
    param([string] $Path)

    Assert-PathExists $Path
    $code = Get-Content -LiteralPath $Path -Raw
    [scriptblock]::Create($code) | Out-Null
}

function Invoke-PowerShellFile {
    param([string] $Path)

    Assert-PathExists $Path
    Invoke-External @("powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $Path)
}

function Invoke-VulnerabilityScan {
    $output = & dotnet list $ProjectPath package --vulnerable --include-transitive 2>&1
    $exitCode = $LASTEXITCODE
    $output | ForEach-Object { Write-Host $_ }

    if ($exitCode -ne 0) {
        throw "dotnet vulnerability scan failed with exit code $exitCode."
    }

    $text = $output -join [Environment]::NewLine
    if ($text -notmatch "has no vulnerable packages") {
        throw "Vulnerability scan did not confirm that the project has no vulnerable packages."
    }
}

function Assert-PublishOutput {
    Assert-PathExists (Join-Path $PublishPath "ISRORUnified.exe")
    Assert-PathExists (Join-Path $PublishPath "appsettings.json")
    Assert-PathExists (Join-Path $PublishPath "Database\SILKROAD_CERTIFICATION.sql")
    Assert-PathExists (Join-Path $PublishPath "Patches\patch_gateway.1337")

    $allowedTopLevelNames = @("ISRORUnified.exe", "appsettings.json", "Database", "Patches")
    $topLevelItems = @(Get-ChildItem -LiteralPath $PublishPath -Force)
    $unexpectedTopLevelItems = @($topLevelItems | Where-Object { $allowedTopLevelNames -notcontains $_.Name })

    if ($unexpectedTopLevelItems.Count -gt 0) {
        throw "Published output has unexpected top-level items: $($unexpectedTopLevelItems.Name -join ', ')"
    }

    Assert-Equal $topLevelItems.Count $ExpectedPublishTopLevelCount "Published top-level item count mismatch."

    $patchCount = (Get-ChildItem -LiteralPath (Join-Path $PublishPath "Patches") -File | Measure-Object).Count
    $databaseCount = (Get-ChildItem -LiteralPath (Join-Path $PublishPath "Database") -Recurse -File | Measure-Object).Count

    Assert-Equal $patchCount $ExpectedPatchFileCount "Published patch file count mismatch."
    Assert-Equal $databaseCount $ExpectedDatabaseFileCount "Published database file count mismatch."
}

function Clear-GeneratedLogs {
    $logFiles = @(Get-ChildItem -LiteralPath "src\ISRORUnified" -File -Filter "UnifiedLog*.txt" -ErrorAction SilentlyContinue)
    if ($logFiles.Count -eq 0) {
        return
    }

    Remove-Item -LiteralPath $logFiles.FullName
}

Invoke-Step "Parse validation scripts" {
    Assert-ScriptParses "scripts\ValidateLiveBilling.ps1"
    Assert-ScriptParses "scripts\ValidateLiveCertification.ps1"
    Assert-ScriptParses "scripts\ValidateLiveVsro.ps1"
}

Invoke-Step "Compatibility audit" {
    Invoke-PowerShellFile "scripts\CompatibilityAudit.ps1"
}

Invoke-Step "Smoke tests" {
    Invoke-PowerShellFile "scripts\SmokeTest.ps1"
}

if (-not $SkipVulnerabilityScan) {
    Invoke-Step "Dependency vulnerability scan" {
        Invoke-VulnerabilityScan
    }
}

if (-not $SkipPublish) {
    Invoke-Step "Publish bundle" {
        Invoke-External @(
            "powershell",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            "scripts\Publish.ps1",
            "-ProjectPath",
            $ProjectPath,
            "-OutputPath",
            $PublishPath
        )
    }

    Invoke-Step "Published artifact check" {
        Assert-PublishOutput
    }
}

if (-not $KeepLogs) {
    Invoke-Step "Clean generated logs" {
        Clear-GeneratedLogs
    }
}

Write-Host ""
Write-Host "Local verification passed."
