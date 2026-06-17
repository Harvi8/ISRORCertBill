param(
    [Parameter(Mandatory = $true)]
    [string] $AccountDbConfig,
    [string] $JoymaxPortalDbConfig,
    [string] $ProjectPath = "src\ISRORUnified\ISRORUnified.csproj",
    [int] $HttpPort = 18087,
    [ValidateSet("Simple", "Full", "Bypass", "Nemo")]
    [string] $AuthService = "Simple",
    [ValidateSet("None", "Email", "Ferre")]
    [string] $NotificationService = "None",
    [string] $SaltKey = "eset5ag.nsy-g6ky5.mp",
    [int] $ServiceCompany = 11,
    [int] $RequestTimeoutSeconds = 60,
    [int16] $ChannelId = 1,
    [Parameter(Mandatory = $true)]
    [string] $UserId,
    [Parameter(Mandatory = $true)]
    [string] $PasswordHash,
    [string] $UserIp = "127.0.0.1",
    [int] $ExpectedLoginReturnValue = 0,
    [switch] $ValidateSecondPassword,
    [switch] $ValidateItemLock,
    [int] $NotificationJid,
    [string] $NotificationCode = "1234",
    [string] $NotificationEmail,
    [int] $ExpectedNotificationReturnValue = -1,
    [int] $TimeoutSeconds = 45
)

$ErrorActionPreference = "Stop"

function Invoke-DotNet {
    param([string[]] $Arguments)

    & dotnet @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet $($Arguments -join ' ') failed with exit code $LASTEXITCODE."
    }
}

function ConvertTo-ProcessArgument {
    param([string] $Value)

    return '"' + ($Value -replace '"', '\"') + '"'
}

function Get-Md5Hex {
    param([string] $Value)

    $bytes = [System.Text.Encoding]::ASCII.GetBytes($Value)
    $md5 = [System.Security.Cryptography.MD5]::Create()
    try {
        $hash = $md5.ComputeHash($bytes)
        return ([System.BitConverter]::ToString($hash) -replace "-", "").ToUpperInvariant()
    }
    finally {
        $md5.Dispose()
    }
}

function ConvertTo-ResponseText {
    param($Content)

    if ($Content -is [byte[]]) {
        return [System.Text.Encoding]::UTF8.GetString($Content)
    }

    return [string] $Content
}

function Start-UnifiedHost {
    param([string] $Arguments)

    $name = "live-billing"
    $stdout = Join-Path $env:TEMP "isrorunified-$name-out.log"
    $stderr = Join-Path $env:TEMP "isrorunified-$name-err.log"
    Remove-Item -LiteralPath $stdout, $stderr -ErrorAction SilentlyContinue

    $processInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $processInfo.FileName = "dotnet"
    $processInfo.Arguments = "run --no-build --project $(ConvertTo-ProcessArgument $ProjectPath) -- $Arguments"
    $processInfo.UseShellExecute = $false
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true
    $processInfo.WorkingDirectory = (Get-Location).Path

    $process = [System.Diagnostics.Process]::Start($processInfo)
    return @{
        Process = $process
        Stdout = $stdout
        Stderr = $stderr
    }
}

function Stop-UnifiedHost {
    param($HostState)

    if ($null -eq $HostState) {
        return
    }

    $process = $HostState.Process
    if ($process -and -not $process.HasExited) {
        $process.Kill()
        $process.WaitForExit()
    }

    $out = $process.StandardOutput.ReadToEnd()
    $err = $process.StandardError.ReadToEnd()
    Set-Content -LiteralPath $HostState.Stdout -Value $out
    Set-Content -LiteralPath $HostState.Stderr -Value $err
}

function Get-HostDiagnostics {
    param($HostState)

    $process = $HostState.Process
    $summary = @()
    if ($process -and $process.HasExited) {
        $summary += "Process exited with code $($process.ExitCode)."
    }

    foreach ($path in @($HostState.Stdout, $HostState.Stderr)) {
        if (Test-Path -LiteralPath $path) {
            $summary += "----- $path -----"
            $summary += Get-Content -LiteralPath $path -Raw
        }
    }

    return $summary -join [Environment]::NewLine
}

function Wait-ForHealth {
    param(
        [int] $Port,
        [int] $Timeout
    )

    $deadline = [DateTimeOffset]::UtcNow.AddSeconds($Timeout)
    while ([DateTimeOffset]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 500
        try {
            return Invoke-RestMethod -Uri "http://127.0.0.1:$Port/health" -TimeoutSec 2
        }
        catch {
        }
    }

    throw "Host did not respond on /health at port $Port within $Timeout seconds."
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

function Invoke-BillingGet {
    param([string] $PathAndQuery)

    $response = Invoke-WebRequest `
        -UseBasicParsing `
        -Uri "http://127.0.0.1:$HttpPort$PathAndQuery" `
        -UserAgent "Portal_CGI_Agent" `
        -TimeoutSec 15
    return ConvertTo-ResponseText $response.Content
}

function Get-LoginValues {
    $unixTime = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $token = Get-Md5Hex "$ChannelId$UserId$PasswordHash$UserIp$unixTime$SaltKey"
    return "$ChannelId|$UserId|$PasswordHash|$UserIp|$unixTime|$token"
}

function Get-NotificationValues {
    param(
        [int] $Jid,
        [string] $Code,
        [string] $Email
    )

    $token = Get-Md5Hex "$Jid$Code$Email$SaltKey"
    return "$Jid|$Code|$Email|$token"
}

if ([string]::IsNullOrWhiteSpace($JoymaxPortalDbConfig)) {
    $JoymaxPortalDbConfig = $AccountDbConfig
}

if (($ValidateSecondPassword -or $ValidateItemLock) -and
    ($NotificationJid -le 0 -or [string]::IsNullOrWhiteSpace($NotificationEmail))) {
    throw "Notification validation requires -NotificationJid and -NotificationEmail."
}

Write-Host "Building unified project..."
Invoke-DotNet @("build", $ProjectPath, "--no-restore")

$quotedAccountDb = ConvertTo-ProcessArgument $AccountDbConfig
$quotedPortalDb = ConvertTo-ProcessArgument $JoymaxPortalDbConfig
$quotedSaltKey = ConvertTo-ProcessArgument $SaltKey
$arguments = "--Features:Billing=true --Features:NationPing=false --Features:Certification=false " +
    "--AuthService=$AuthService " +
    "--NotificationService:Type=$NotificationService " +
    "--DbConfig:AccountDB=$quotedAccountDb " +
    "--DbConfig:JoymaxPortalDB=$quotedPortalDb " +
    "--SaltKey=$quotedSaltKey " +
    "--ServiceCompany=$ServiceCompany " +
    "--RequestTimeoutSeconds=$RequestTimeoutSeconds " +
    "--Kestrel:EndPoints:Http:Url=http://127.0.0.1:$HttpPort"

Write-Host "Starting unified host with live billing enabled..."
$hostState = Start-UnifiedHost -Arguments $arguments
try {
    Wait-ForHealth -Port $HttpPort -Timeout $TimeoutSeconds | Out-Null

    $status = Invoke-RestMethod -Uri "http://127.0.0.1:$HttpPort/status" -TimeoutSec 5
    Assert-Equal $status.billing.enabled $true "Billing status mismatch."
    Assert-Equal $status.billing.authService $AuthService "Auth service status mismatch."
    Assert-Equal $status.billing.notificationService $NotificationService "Notification service status mismatch."

    Write-Host "Checking login route with $AuthService auth..."
    $loginValues = [uri]::EscapeDataString((Get-LoginValues))
    $loginResponse = Invoke-BillingGet "/Property/Silkroad-r/checkuser.aspx?values=$loginValues"
    $loginReturnValue = [int](($loginResponse -split "\|")[0])
    Assert-Equal $loginReturnValue $ExpectedLoginReturnValue "Login return value mismatch."

    if ($ValidateSecondPassword) {
        Write-Host "Checking EmailPassword notification route with $NotificationService notification..."
        $values = [uri]::EscapeDataString((Get-NotificationValues -Jid $NotificationJid -Code $NotificationCode -Email $NotificationEmail))
        $response = Invoke-BillingGet "/cgi/EmailPassword.asp?values=$values"
        Assert-Equal ([int]$response) $ExpectedNotificationReturnValue "EmailPassword return value mismatch."
    }

    if ($ValidateItemLock) {
        Write-Host "Checking Email_Certification notification route with $NotificationService notification..."
        $values = [uri]::EscapeDataString((Get-NotificationValues -Jid $NotificationJid -Code $NotificationCode -Email $NotificationEmail))
        $response = Invoke-BillingGet "/cgi/Email_Certification.asp?values=$values"
        Assert-Equal ([int]$response) $ExpectedNotificationReturnValue "Email_Certification return value mismatch."
    }

    Write-Host "Live billing validation passed."
}
catch {
    Stop-UnifiedHost $hostState
    $diagnostics = Get-HostDiagnostics $hostState
    $hostState = $null
    if (-not [string]::IsNullOrWhiteSpace($diagnostics)) {
        Write-Host $diagnostics
    }

    throw
}
finally {
    Stop-UnifiedHost $hostState
}
