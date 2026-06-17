param(
    [string] $SqlServer = ".\VSRO",
    [switch] $UseSqlAuth,
    [string] $SqlUser = "sa",
    [string] $SqlPassword = "1",
    [string] $AccountDatabase = "SILKROAD_R_ACCOUNT",
    [string] $PortalDatabase = "GB_JoymaxPortal",
    [string] $CertificationDatabase = "SILKROAD_CERTIFICATION",
    [string] $ProjectPath = "src\ISRORUnified\ISRORUnified.csproj",
    [string] $CertificationListenAddressOverride = "127.0.0.1",
    [string] $CertificationTcpHostOverride = "127.0.0.1",
    [int] $CertificationHttpPort = 18086,
    [int] $BillingHttpPort = 18087,
    [int] $TimeoutSeconds = 60,
    [switch] $SkipCertification,
    [switch] $SkipBilling,
    [switch] $SkipFullAuth,
    [switch] $SkipNotification
)

$ErrorActionPreference = "Stop"

function New-SqlConnectionString {
    param([string] $Database)

    $parts = @(
        "Data Source=$SqlServer",
        "Initial Catalog=$Database",
        "Encrypt=False",
        "TrustServerCertificate=True",
        "Connection Timeout=5"
    )

    if ($UseSqlAuth) {
        $parts += "User ID=$SqlUser"
        $parts += "Password=$SqlPassword"
    }
    else {
        $parts += "Integrated Security=True"
    }

    return ($parts -join ";")
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

function Invoke-Scalar {
    param(
        [string] $ConnectionString,
        [string] $CommandText
    )

    $connection = [System.Data.SqlClient.SqlConnection]::new($ConnectionString)
    try {
        $connection.Open()
        $command = $connection.CreateCommand()
        $command.CommandText = $CommandText
        return $command.ExecuteScalar()
    }
    finally {
        $connection.Dispose()
    }
}

function Get-ValidationUser {
    param([string] $ConnectionString)

    $connection = [System.Data.SqlClient.SqlConnection]::new($ConnectionString)
    try {
        $connection.Open()
        $command = $connection.CreateCommand()
        $command.CommandText = @"
SET NOCOUNT ON;
SELECT TOP (1)
    StrUserID,
    [password],
    PortalJID
FROM dbo.TB_User
WHERE ISNULL(StrUserID, '') <> ''
  AND ISNULL([password], '') <> ''
  AND PortalJID > 0
ORDER BY CASE WHEN Active = 1 THEN 0 ELSE 1 END, JID;
"@
        $reader = $command.ExecuteReader()
        try {
            if (-not $reader.Read()) {
                throw "No TB_User row with non-empty StrUserID/password/PortalJID was found."
            }

            return [pscustomobject]@{
                UserId = $reader.GetString(0)
                PasswordHash = $reader.GetString(1)
                PortalJid = $reader.GetInt32(2)
            }
        }
        finally {
            $reader.Dispose()
        }
    }
    finally {
        $connection.Dispose()
    }
}

function Test-NemoSchema {
    param([string] $ConnectionString)

    $count = Invoke-Scalar `
        -ConnectionString $ConnectionString `
        -CommandText @"
SET NOCOUNT ON;
SELECT COUNT(*)
FROM sys.columns c
JOIN sys.objects o ON o.object_id = c.object_id
WHERE o.name = 'TB_User'
  AND c.name IN ('Email', 'EmailCertificationStatus', 'EmailUniqueStatus', 'VIPLv', 'VipExpireTime', 'VipUserType');
"@

    return ([int] $count) -eq 6
}

function Test-FullAuthProcedure {
    param([string] $ConnectionString)

    $count = Invoke-Scalar `
        -ConnectionString $ConnectionString `
        -CommandText "SET NOCOUNT ON; SELECT COUNT(*) FROM sys.objects WHERE type IN ('P', 'PC') AND name = 'A_UserLogin';"

    return ([int] $count) -gt 0
}

function Invoke-LiveCertification {
    param([string] $ConnectionString)

    $arguments = @(
        "powershell",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        "scripts\ValidateLiveCertification.ps1",
        "-ProjectPath",
        $ProjectPath,
        "-DbConfig",
        $ConnectionString,
        "-HttpPort",
        $CertificationHttpPort.ToString(),
        "-TimeoutSeconds",
        $TimeoutSeconds.ToString()
    )

    if (-not [string]::IsNullOrWhiteSpace($CertificationListenAddressOverride)) {
        $arguments += "-ListenAddressOverride"
        $arguments += $CertificationListenAddressOverride
    }

    if (-not [string]::IsNullOrWhiteSpace($CertificationTcpHostOverride)) {
        $arguments += "-TcpHostOverride"
        $arguments += $CertificationTcpHostOverride
    }

    Invoke-External $arguments
}

function Invoke-LiveBilling {
    param(
        [string] $AccountConnectionString,
        [string] $PortalConnectionString,
        [string] $AuthService,
        [pscustomobject] $ValidationUser,
        [switch] $ValidateNotificationRoutes
    )

    $arguments = @(
        "powershell",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        "scripts\ValidateLiveBilling.ps1",
        "-ProjectPath",
        $ProjectPath,
        "-AccountDbConfig",
        $AccountConnectionString,
        "-JoymaxPortalDbConfig",
        $PortalConnectionString,
        "-HttpPort",
        $BillingHttpPort.ToString(),
        "-AuthService",
        $AuthService,
        "-NotificationService",
        "None",
        "-UserId",
        $ValidationUser.UserId,
        "-PasswordHash",
        $ValidationUser.PasswordHash,
        "-TimeoutSeconds",
        $TimeoutSeconds.ToString()
    )

    if ($ValidateNotificationRoutes) {
        $arguments += "-ValidateSecondPassword"
        $arguments += "-ValidateItemLock"
        $arguments += "-NotificationJid"
        $arguments += $ValidationUser.PortalJid.ToString()
        $arguments += "-NotificationEmail"
        $arguments += "validation@example.com"
        $arguments += "-ExpectedNotificationReturnValue"
        $arguments += "-1"
    }

    Invoke-External $arguments
}

$accountConnectionString = New-SqlConnectionString $AccountDatabase
$portalConnectionString = New-SqlConnectionString $PortalDatabase
$certificationConnectionString = New-SqlConnectionString $CertificationDatabase

Write-Host "Live SQL Server: $SqlServer"
Write-Host "Authentication: $(if ($UseSqlAuth) { 'SQL login' } else { 'Integrated Security' })"

if (-not $SkipCertification) {
    Write-Host ""
    Write-Host "== Live certification =="
    Invoke-LiveCertification $certificationConnectionString
}

if (-not $SkipBilling) {
    Write-Host ""
    Write-Host "== Discover billing validation user =="
    $validationUser = Get-ValidationUser $accountConnectionString
    Write-Host "Selected user: $($validationUser.UserId) (JID $($validationUser.PortalJid), password hash length $($validationUser.PasswordHash.Length))."

    Write-Host ""
    Write-Host "== Live billing: Simple auth =="
    Invoke-LiveBilling `
        -AccountConnectionString $accountConnectionString `
        -PortalConnectionString $portalConnectionString `
        -AuthService "Simple" `
        -ValidationUser $validationUser

    Write-Host ""
    Write-Host "== Live billing: Bypass auth =="
    Invoke-LiveBilling `
        -AccountConnectionString $accountConnectionString `
        -PortalConnectionString $portalConnectionString `
        -AuthService "Bypass" `
        -ValidationUser $validationUser

    if (-not $SkipFullAuth) {
        if (Test-FullAuthProcedure $portalConnectionString) {
            Write-Host ""
            Write-Host "== Live billing: Full auth =="
            Invoke-LiveBilling `
                -AccountConnectionString $accountConnectionString `
                -PortalConnectionString $portalConnectionString `
                -AuthService "Full" `
                -ValidationUser $validationUser
        }
        else {
            Write-Host "Skipping Full auth: A_UserLogin procedure was not found."
        }
    }

    if (Test-NemoSchema $accountConnectionString) {
        Write-Host ""
        Write-Host "== Live billing: Nemo auth =="
        Invoke-LiveBilling `
            -AccountConnectionString $accountConnectionString `
            -PortalConnectionString $portalConnectionString `
            -AuthService "Nemo" `
            -ValidationUser $validationUser
    }
    else {
        Write-Host "Skipping Nemo auth: required TB_User extension columns were not found."
    }

    if (-not $SkipNotification) {
        Write-Host ""
        Write-Host "== Live billing: notification routes with None provider =="
        Invoke-LiveBilling `
            -AccountConnectionString $accountConnectionString `
            -PortalConnectionString $portalConnectionString `
            -AuthService "Simple" `
            -ValidationUser $validationUser `
            -ValidateNotificationRoutes
    }
}

Write-Host ""
Write-Host "Live VSRO validation passed."
