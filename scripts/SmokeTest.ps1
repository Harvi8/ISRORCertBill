param(
    [string] $ProjectPath = "src\ISRORUnified\ISRORUnified.csproj",
    [int] $HealthPort = 18081,
    [int] $BillingPort = 18082,
    [int] $PingHttpPort = 18083,
    [int] $PingPort = 12990,
    [int] $CertificationFailurePort = 18084,
    [int] $ConfigurationPort = 18085
)

$ErrorActionPreference = "Stop"

function Invoke-DotNet {
    param([string[]] $Arguments)

    & dotnet @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet $($Arguments -join ' ') failed with exit code $LASTEXITCODE."
    }
}

function Start-UnifiedHost {
    param(
        [string] $Arguments,
        [string] $Name
    )

    $stdout = Join-Path $env:TEMP "isrorunified-$Name-out.log"
    $stderr = Join-Path $env:TEMP "isrorunified-$Name-err.log"
    Remove-Item -LiteralPath $stdout, $stderr -ErrorAction SilentlyContinue

    $processInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $processInfo.FileName = "dotnet"
    $processInfo.Arguments = "run --no-build --project `"$ProjectPath`" -- $Arguments"
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

function Wait-ForHealth {
    param([int] $Port)

    for ($i = 0; $i -lt 40; $i++) {
        Start-Sleep -Milliseconds 250
        try {
            return Invoke-RestMethod -Uri "http://127.0.0.1:$Port/health" -TimeoutSec 2
        }
        catch {
        }
    }

    throw "Host did not respond on /health at port $Port."
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

function Assert-Contains {
    param(
        [string] $Actual,
        [string] $Expected,
        [string] $Message
    )

    if (-not $Actual.Contains($Expected)) {
        throw "$Message Expected content to contain [$Expected], got [$Actual]."
    }
}

function ConvertTo-ResponseText {
    param($Content)

    if ($Content -is [byte[]]) {
        return [System.Text.Encoding]::UTF8.GetString($Content)
    }

    return [string] $Content
}

Write-Host "Building unified project..."
Invoke-DotNet @("build", $ProjectPath, "--no-restore")

Write-Host "Checking /health and /status..."
$hostState = Start-UnifiedHost `
    -Name "health" `
    -Arguments "--Features:Certification=false --Features:NationPing=false --Kestrel:EndPoints:Http:Url=http://127.0.0.1:$HealthPort"
try {
    $health = Wait-ForHealth -Port $HealthPort
    Assert-Equal $health.status "ok" "/health status mismatch."

    $dashboard = Invoke-WebRequest `
        -UseBasicParsing `
        -Uri "http://127.0.0.1:$HealthPort/" `
        -UserAgent "Mozilla/5.0" `
        -TimeoutSec 5
    $dashboardText = ConvertTo-ResponseText $dashboard.Content
    Assert-Contains $dashboardText "ISROR Unified" "Root dashboard title mismatch."
    Assert-Contains $dashboardText "Billing" "Root dashboard billing section mismatch."
    Assert-Contains $dashboardText "Certification" "Root dashboard certification section mismatch."

    $favicon = Invoke-WebRequest `
        -UseBasicParsing `
        -Uri "http://127.0.0.1:$HealthPort/favicon.ico" `
        -UserAgent "Mozilla/5.0" `
        -TimeoutSec 5
    Assert-Equal $favicon.StatusCode 204 "/favicon.ico should not trip Portal CGI guard."

    $status = Invoke-RestMethod -Uri "http://127.0.0.1:$HealthPort/status" -TimeoutSec 2
    Assert-Equal $status.billing.enabled $true "Billing status mismatch."
    Assert-Equal $status.billing.authService "Simple" "Default auth service status mismatch."
    Assert-Equal $status.billing.notificationService "Email" "Default notification service status mismatch."
    Assert-Equal $status.nationPing.enabled $false "NationPing status mismatch."
    Assert-Equal $status.certification.enabled $false "Certification status mismatch."
    Assert-Equal $status.certification.serializer "New" "Default certification serializer status mismatch."
}
finally {
    Stop-UnifiedHost $hostState
}

Write-Host "Checking billing compatibility routes..."
$hostState = Start-UnifiedHost `
    -Name "billing" `
    -Arguments "--Features:Certification=false --Features:NationPing=false --Kestrel:EndPoints:Http:Url=http://127.0.0.1:$BillingPort"
try {
    Wait-ForHealth -Port $BillingPort | Out-Null

    $checkUser = Invoke-WebRequest `
        -UseBasicParsing `
        -Uri "http://127.0.0.1:$BillingPort/Property/Silkroad-r/checkuser.aspx?values=1%7Cuser%7Cpass%7C127.0.0.1%7C0%7Cbad" `
        -UserAgent "Portal_CGI_Agent" `
        -TimeoutSec 5
    Assert-Contains (ConvertTo-ResponseText $checkUser.Content) "-65553" "checkuser.aspx invalid-token response mismatch."

    $emailPassword = Invoke-WebRequest `
        -UseBasicParsing `
        -Uri "http://127.0.0.1:$BillingPort/cgi/EmailPassword.asp?values=1%7C1234%7Cuser@example.com%7Cbad" `
        -UserAgent "Portal_CGI_Agent" `
        -TimeoutSec 5
    Assert-Equal (ConvertTo-ResponseText $emailPassword.Content) "-1" "EmailPassword invalid-token response mismatch."

    $emailCertification = Invoke-WebRequest `
        -UseBasicParsing `
        -Uri "http://127.0.0.1:$BillingPort/cgi/Email_Certification.asp?values=1%7C1234%7Cuser@example.com%7Cbad" `
        -UserAgent "Portal_CGI_Agent" `
        -TimeoutSec 5
    Assert-Equal (ConvertTo-ResponseText $emailCertification.Content) "-1" "Email_Certification invalid-token response mismatch."
}
finally {
    Stop-UnifiedHost $hostState
}

Write-Host "Checking Portal CGI guard and config overrides..."
$hostState = Start-UnifiedHost `
    -Name "configuration" `
    -Arguments "--Features:Billing=true --Features:Certification=false --Features:NationPing=false --AuthService=Bypass --NotificationService:Type=None --CertificationConfig:Serializer=Old --CertificationConfig:ListenAddressOverride=127.0.0.1 --CertificationConfig:ListenPortOverride=15779 --Kestrel:EndPoints:Http:Url=http://127.0.0.1:$ConfigurationPort"
try {
    Wait-ForHealth -Port $ConfigurationPort | Out-Null

    $status = Invoke-RestMethod -Uri "http://127.0.0.1:$ConfigurationPort/status" -TimeoutSec 2
    Assert-Equal $status.billing.enabled $true "Override billing status mismatch."
    Assert-Equal $status.billing.authService "Bypass" "Override auth service status mismatch."
    Assert-Equal $status.billing.notificationService "None" "Override notification service status mismatch."
    Assert-Equal $status.certification.serializer "Old" "Override certification serializer status mismatch."
    Assert-Equal $status.certification.listenAddress "127.0.0.1" "Override certification listen address status mismatch."
    Assert-Equal $status.certification.listenPort 15779 "Override certification listen port status mismatch."

    $browserResponse = Invoke-WebRequest `
        -UseBasicParsing `
        -Uri "http://127.0.0.1:$ConfigurationPort/Property/Silkroad-r/checkuser.aspx?values=1%7Cuser%7Cpass%7C127.0.0.1%7C0%7Cbad" `
        -UserAgent "Mozilla/5.0" `
        -TimeoutSec 5
    Assert-Contains (ConvertTo-ResponseText $browserResponse.Content) "-65562" "Portal CGI user-agent guard response mismatch."
}
finally {
    Stop-UnifiedHost $hostState
}

Write-Host "Checking NationPing TCP responder..."
$hostState = Start-UnifiedHost `
    -Name "ping" `
    -Arguments "--Features:Billing=false --Features:Certification=false --Features:NationPing=true --NationPingService:ListenAddress=127.0.0.1 --NationPingService:ListenPort=$PingPort --Kestrel:EndPoints:Http:Url=http://127.0.0.1:$PingHttpPort"
try {
    $client = $null
    for ($i = 0; $i -lt 40; $i++) {
        Start-Sleep -Milliseconds 250
        try {
            $client = [System.Net.Sockets.TcpClient]::new("127.0.0.1", $PingPort)
            break
        }
        catch {
        }
    }

    if ($null -eq $client) {
        throw "NationPing TCP port $PingPort did not open."
    }

    try {
        $stream = $client.GetStream()
        $request = [byte[]]::new(14)
        $request[2] = [byte][char]"R"
        $request[3] = [byte][char]"E"
        $request[4] = [byte][char]"Q"
        $request[5] = 0
        $stream.Write($request, 0, $request.Length)

        $response = [byte[]]::new(14)
        $offset = 0
        while ($offset -lt 14) {
            $read = $stream.Read($response, $offset, 14 - $offset)
            if ($read -le 0) {
                break
            }
            $offset += $read
        }

        $marker = [System.Text.Encoding]::ASCII.GetString($response, 2, 4)
        Assert-Equal $marker "ACK`0" "NationPing ACK marker mismatch."
    }
    finally {
        $client.Dispose()
    }
}
finally {
    Stop-UnifiedHost $hostState
}

Write-Host "Checking certification database failure status..."
$hostState = Start-UnifiedHost `
    -Name "cert-failure" `
    -Arguments "--Features:Billing=false --Features:Certification=true --Features:NationPing=false --CertificationConfig:DbConfig=Server=127.0.0.1,1;Database=SILKROAD_CERTIFICATION;UID=sa;PWD=1;TrustServerCertificate=True --Kestrel:EndPoints:Http:Url=http://127.0.0.1:$CertificationFailurePort"
try {
    for ($i = 0; $i -lt 60; $i++) {
        Start-Sleep -Milliseconds 250
        try {
            $status = Invoke-RestMethod -Uri "http://127.0.0.1:$CertificationFailurePort/status" -TimeoutSec 2
            break
        }
        catch {
        }
    }

    if ($null -eq $status) {
        throw "Certification failure status endpoint did not respond."
    }

    Assert-Equal $status.certification.enabled $true "Certification enabled status mismatch."
    Assert-Equal $status.certification.refreshed $false "Certification refreshed status mismatch."
}
finally {
    Stop-UnifiedHost $hostState
}

Write-Host "Smoke tests passed."
