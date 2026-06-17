param(
    [string] $UnifiedRoot = "src\ISRORUnified",
    [string] $BillingSourceRoot = "sources\devtekve-ISRORBilling\ISRORBilling-master",
    [string] $CertificationSourceRoot = "sources\Harvi8-ISRORCertBill\ISRORCertBill-master"
)

$ErrorActionPreference = "Stop"

function Resolve-RequiredPath {
    param([string] $Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Required path does not exist: $Path"
    }

    return (Resolve-Path -LiteralPath $Path).Path
}

function Get-RelativePath {
    param(
        [string] $BasePath,
        [string] $Path
    )

    $baseFullPath = [System.IO.Path]::GetFullPath($BasePath).TrimEnd("\", "/")
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    Assert-True $fullPath.StartsWith($baseFullPath, [StringComparison]::OrdinalIgnoreCase) "Path [$Path] is not under [$BasePath]."

    $relative = $fullPath.Substring($baseFullPath.Length).TrimStart("\", "/")
    return $relative -replace "\\", "/"
}

function Assert-True {
    param(
        [bool] $Condition,
        [string] $Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Assert-TextContains {
    param(
        [string] $Path,
        [string] $Expected
    )

    $text = Get-Content -LiteralPath $Path -Raw
    Assert-True $text.Contains($Expected) "Expected [$Path] to contain [$Expected]."
}

function Assert-TextNotContains {
    param(
        [string] $Path,
        [string] $Unexpected
    )

    $text = Get-Content -LiteralPath $Path -Raw
    Assert-True (-not $text.Contains($Unexpected)) "Expected [$Path] to not contain [$Unexpected]."
}

function Assert-FileSame {
    param(
        [string] $SourcePath,
        [string] $DestinationPath
    )

    Assert-True (Test-Path -LiteralPath $DestinationPath) "Missing merged file: $DestinationPath"

    $sourceHash = (Get-FileHash -LiteralPath $SourcePath -Algorithm SHA256).Hash
    $destinationHash = (Get-FileHash -LiteralPath $DestinationPath -Algorithm SHA256).Hash

    Assert-True ($sourceHash -eq $destinationHash) "Merged file differs from source: $DestinationPath"
}

function Assert-DirectoryMirror {
    param(
        [string] $SourceDir,
        [string] $DestinationDir,
        [string[]] $ExcludedRelatives = @()
    )

    $sourceBase = Resolve-RequiredPath $SourceDir
    $destinationBase = Resolve-RequiredPath $DestinationDir
    $excluded = @{}
    foreach ($relative in $ExcludedRelatives) {
        $excluded[$relative] = $true
    }

    $sourceRelatives = @{}
    foreach ($sourceFile in Get-ChildItem -LiteralPath $sourceBase -Recurse -File) {
        $relative = Get-RelativePath $sourceBase $sourceFile.FullName
        $sourceRelatives[$relative] = $true

        if ($excluded.ContainsKey($relative)) {
            continue
        }

        $destinationFile = Join-Path $destinationBase ($relative -replace "/", [System.IO.Path]::DirectorySeparatorChar)
        Assert-FileSame $sourceFile.FullName $destinationFile
    }

    foreach ($destinationFile in Get-ChildItem -LiteralPath $destinationBase -Recurse -File) {
        $relative = Get-RelativePath $destinationBase $destinationFile.FullName

        if ($excluded.ContainsKey($relative)) {
            continue
        }

        Assert-True $sourceRelatives.ContainsKey($relative) "Merged directory has unexpected file: $destinationFile"
    }
}

function Assert-RequiredStrings {
    param(
        [string] $Path,
        [string[]] $ExpectedStrings
    )

    foreach ($expected in $ExpectedStrings) {
        Assert-TextContains $Path $expected
    }
}

$unifiedRootPath = Resolve-RequiredPath $UnifiedRoot
$billingSourcePath = Resolve-RequiredPath $BillingSourceRoot
$certificationSourcePath = Resolve-RequiredPath $CertificationSourceRoot

Write-Host "Checking copied billing source..."
Assert-DirectoryMirror `
    -SourceDir (Join-Path $billingSourcePath "Database") `
    -DestinationDir (Join-Path $unifiedRootPath "Billing\Database")
Assert-DirectoryMirror `
    -SourceDir (Join-Path $billingSourcePath "Models") `
    -DestinationDir (Join-Path $unifiedRootPath "Billing\Models") `
    -ExcludedRelatives @("Authentication/CheckUserRequest.cs", "Ping/NationPingServiceOptions.cs")
Assert-DirectoryMirror `
    -SourceDir (Join-Path $billingSourcePath "Services") `
    -DestinationDir (Join-Path $unifiedRootPath "Billing\Services") `
    -ExcludedRelatives @(
        "Authentication/IAuthService.cs",
        "Notification/CommunityProvided/FerreNotificationService.cs"
    )

Write-Host "Checking copied certification source..."
Assert-DirectoryMirror `
    -SourceDir (Join-Path $certificationSourcePath "src\ISRORCert\Database") `
    -DestinationDir (Join-Path $unifiedRootPath "Certification\Database") `
    -ExcludedRelatives @("SqlDbAdapter.cs")
Assert-DirectoryMirror `
    -SourceDir (Join-Path $certificationSourcePath "src\ISRORCert\Logic") `
    -DestinationDir (Join-Path $unifiedRootPath "Certification\Logic") `
    -ExcludedRelatives @("CertificationNetworkInterface.cs")
Assert-DirectoryMirror `
    -SourceDir (Join-Path $certificationSourcePath "src\ISRORCert\Model") `
    -DestinationDir (Join-Path $unifiedRootPath "Certification\Model") `
    -ExcludedRelatives @("ServerMachine.cs")
Assert-DirectoryMirror `
    -SourceDir (Join-Path $certificationSourcePath "src\ISRORCert\Network") `
    -DestinationDir (Join-Path $unifiedRootPath "Certification\Network") `
    -ExcludedRelatives @(
        "AsyncClient.cs",
        "AsyncContext.cs",
        "AsyncServer.cs",
        "AsyncState.cs",
        "AsyncToken.cs",
        "IAsyncInterface.cs"
    )
Assert-DirectoryMirror `
    -SourceDir (Join-Path $certificationSourcePath "src\ISRORCert\Services") `
    -DestinationDir (Join-Path $unifiedRootPath "Certification\Services") `
    -ExcludedRelatives @("AsyncServerTickService.cs", "CertificationService.cs")

Write-Host "Checking preserved assets..."
Assert-FileSame `
    -SourcePath (Join-Path $certificationSourcePath "Database\SILKROAD_CERTIFICATION.sql") `
    -DestinationPath "Database\SILKROAD_CERTIFICATION.sql"
Assert-DirectoryMirror `
    -SourceDir (Join-Path $certificationSourcePath "Patches") `
    -DestinationDir "Patches"
Assert-DirectoryMirror `
    -SourceDir (Join-Path $billingSourcePath "Database\CommunityProvided") `
    -DestinationDir "Database\CommunityProvided"

Write-Host "Checking intentional merge differences..."
$sqlAdapterPath = Join-Path $unifiedRootPath "Certification\Database\SqlDbAdapter.cs"
Assert-TextContains $sqlAdapterPath "Microsoft.Data.SqlClient"
Assert-TextNotContains $sqlAdapterPath "System.Data.SqlClient"

$certificationConfigPath = Join-Path $unifiedRootPath "Certification\CertificationConfig.cs"
Assert-RequiredStrings $certificationConfigPath @(
    "public string DbConfig",
    "public string Serializer",
    "public int TickIntervalMs",
    "public string ListenAddressOverride",
    "public int ListenPortOverride"
)

$certificationServicePath = Join-Path $unifiedRootPath "Certification\Services\CertificationService.cs"
Assert-RequiredStrings $certificationServicePath @(
    "ListenAddressOverride",
    "ListenPortOverride",
    "database endpoint",
    "_server.Accept(host, port, 128, _serverInterface)"
)

$tickServicePath = Join-Path $unifiedRootPath "Certification\Services\AsyncServerTickService.cs"
Assert-RequiredStrings $tickServicePath @(
    "IOptions<CertificationConfig>",
    "TickIntervalMs",
    "PeriodicTimer"
)

$certificationInterfacePath = Join-Path $unifiedRootPath "Certification\Logic\CertificationNetworkInterface.cs"
Assert-RequiredStrings $certificationInterfacePath @(
    "public void OnError(AsyncContext? context)"
)

$serverMachinePath = Join-Path $unifiedRootPath "Certification\Model\ServerMachine.cs"
Assert-RequiredStrings $serverMachinePath @(
    "public IPAddress? GetIPAddress"
)

$asyncClientPath = Join-Path $unifiedRootPath "Certification\Network\AsyncClient.cs"
Assert-RequiredStrings $asyncClientPath @(
    "if (!IPAddress.TryParse(host, out var address))",
    "object? sender",
    "Missing async client token"
)

$asyncServerPath = Join-Path $unifiedRootPath "Certification\Network\AsyncServer.cs"
Assert-RequiredStrings $asyncServerPath @(
    "private void DispatchAccept(object? param)",
    "object? sender",
    "Missing async server token"
)

$asyncStatePath = Join-Path $unifiedRootPath "Certification\Network\AsyncState.cs"
Assert-RequiredStrings $asyncStatePath @(
    "e.UserToken is not AsyncState state",
    "if (m_current_write_buffer == null)"
)

$asyncContextPath = Join-Path $unifiedRootPath "Certification\Network\AsyncContext.cs"
Assert-RequiredStrings $asyncContextPath @(
    "public AsyncState State { get; init; } = null!;",
    "public IAsyncInterface Interface { get; set; } = null!;"
)

$asyncTokenPath = Join-Path $unifiedRootPath "Certification\Network\AsyncToken.cs"
Assert-RequiredStrings $asyncTokenPath @(
    "public Socket Socket { get; set; } = null!;",
    "public IAsyncInterface Interface { get; set; } = null!;"
)

$asyncInterfacePath = Join-Path $unifiedRootPath "Certification\Network\IAsyncInterface.cs"
Assert-RequiredStrings $asyncInterfacePath @(
    "void OnError(AsyncContext? context);"
)

$nationPingOptionsPath = Join-Path $unifiedRootPath "Billing\Models\Ping\NationPingServiceOptions.cs"
Assert-RequiredStrings $nationPingOptionsPath @(
    "public string ListenAddress { get; set; } = default!;",
    "public int ListenPort { get; set; }"
)

$checkUserRequestPath = Join-Path $unifiedRootPath "Billing\Models\Authentication\CheckUserRequest.cs"
Assert-RequiredStrings $checkUserRequestPath @(
    "public CheckUserRequest(string values, string? saltKey, int serviceCompany, int requestTimeout)"
)
Assert-TextNotContains $checkUserRequestPath "serviceCompany = 11"
Assert-TextNotContains $checkUserRequestPath "requestTimeout = 60"

$authServicePath = Join-Path $unifiedRootPath "Billing\Services\Authentication\IAuthService.cs"
Assert-RequiredStrings $authServicePath @(
    "requires a complete gateway request"
)
Assert-TextNotContains $authServicePath 'new CheckUserRequest($"{channel}|{userId}|{userPw}")'

$ferreNotificationServicePath = Join-Path $unifiedRootPath "Billing\Services\Notification\CommunityProvided\FerreNotificationService.cs"
Assert-RequiredStrings $ferreNotificationServicePath @(
    "SqlQueryRaw<int?>",
    "new SqlParameter(",
    "request.jid, request.email, request.code"
)
Assert-TextNotContains $ferreNotificationServicePath 'SqlQuery<int?>($"EXEC'
Assert-TextNotContains $ferreNotificationServicePath "request.jid.ToString()"

$publishScriptPath = "scripts\Publish.ps1"
Assert-RequiredStrings $publishScriptPath @(
    "-ReleaseZip",
    "/p:NoWarn=CS8600%3BCS8602%3BCS8603%3BCS8618%3BCS8625",
    "Release zip complete"
)

$compactReleaseWorkflowPath = ".github\workflows\build-compact-release.yml"
Assert-RequiredStrings $compactReleaseWorkflowPath @(
    "uses: actions/checkout@v6",
    "uses: actions/setup-dotnet@v5",
    "uses: actions/upload-artifact@v7",
    "-ReleaseZip"
)

Write-Host "Checking unified registrations and routes..."
$billingRegistrationPath = Join-Path $unifiedRootPath "Infrastructure\ServiceRegistration\BillingRegistration.cs"
Assert-RequiredStrings $billingRegistrationPath @(
    "/Property/Silkroad-r/checkuser.aspx",
    "/cgi/EmailPassword.asp",
    "/cgi/Email_Certification.asp",
    "AddHostedService<NationPingService>",
    "NotificationServiceType.Email",
    "NotificationServiceType.Ferre",
    "NotificationServiceType.None",
    "SupportedLoginServicesEnum.Full",
    "SupportedLoginServicesEnum.Bypass",
    "SupportedLoginServicesEnum.Nemo",
    "SupportedLoginServicesEnum.Simple"
)

$certificationRegistrationPath = Join-Path $unifiedRootPath "Infrastructure\ServiceRegistration\CertificationRegistration.cs"
Assert-RequiredStrings $certificationRegistrationPath @(
    "CertificationSerializerOld",
    "CertificationSerializerNew",
    "PacketHandlerSetupCord",
    "PacketHandlerCertificate",
    "PacketHandlerNotify",
    "PacketHandlerRelay",
    "PacketHandlerChangeShardData",
    "AddHostedService<CertificationService>",
    "AddHostedService<AsyncServerTickService>"
)

$middlewarePath = Join-Path $unifiedRootPath "Billing\GenericHandlerMiddleware.cs"
Assert-RequiredStrings $middlewarePath @(
    'request.Path == "/"',
    "PortalCGIAgentHeader",
    "BrowserAgentNotMatch",
    "/favicon.ico",
    "/health",
    "/status"
)

$healthPath = Join-Path $unifiedRootPath "Infrastructure\ServiceRegistration\HealthRegistration.cs"
Assert-RequiredStrings $healthPath @(
    'MapGet("/",',
    "/health",
    "/status",
    "AuthService",
    "NotificationService",
    "Serializer",
    "Refreshed"
)

$projectPath = Join-Path $unifiedRootPath "ISRORUnified.csproj"
Assert-RequiredStrings $projectPath @(
    "<TargetFramework>net8.0</TargetFramework>",
    "Microsoft.Data.SqlClient",
    "..\..\Database\**\*",
    "..\..\Patches\**\*"
)

Write-Host "Compatibility audit passed."
