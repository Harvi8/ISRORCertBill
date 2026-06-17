param(
    [Parameter(Mandatory = $true)]
    [string] $DbConfig,
    [string] $ProjectPath = "src\ISRORUnified\ISRORUnified.csproj",
    [int] $HttpPort = 18086,
    [ValidateSet("New", "Old")]
    [string] $Serializer = "New",
    [string] $ListenAddressOverride,
    [int] $ListenPortOverride,
    [int] $TimeoutSeconds = 60,
    [string] $TcpHostOverride,
    [switch] $SkipTcpCheck
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

function Start-UnifiedHost {
    param([string] $Arguments)

    $name = "live-certification"
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

function Wait-ForStatus {
    param(
        [int] $Port,
        [int] $Timeout
    )

    $deadline = [DateTimeOffset]::UtcNow.AddSeconds($Timeout)
    while ([DateTimeOffset]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 500
        try {
            return Invoke-RestMethod -Uri "http://127.0.0.1:$Port/status" -TimeoutSec 2
        }
        catch {
        }
    }

    throw "Host did not respond on /status at port $Port within $Timeout seconds."
}

function Wait-ForCertificationRefresh {
    param(
        [int] $Port,
        [int] $Timeout
    )

    $deadline = [DateTimeOffset]::UtcNow.AddSeconds($Timeout)
    $lastStatus = $null

    while ([DateTimeOffset]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 1000
        try {
            $lastStatus = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/status" -TimeoutSec 2
            if ($lastStatus.certification.refreshed -eq $true) {
                return $lastStatus
            }
        }
        catch {
        }
    }

    if ($null -ne $lastStatus) {
        $lastStatus | ConvertTo-Json -Depth 10
    }

    throw "Certification did not refresh within $Timeout seconds."
}

function Test-TcpListener {
    param(
        [string] $HostName,
        [int] $Port
    )

    $client = [System.Net.Sockets.TcpClient]::new()
    try {
        $connectTask = $client.ConnectAsync($HostName, $Port)
        if (-not $connectTask.Wait(5000)) {
            throw "Timed out connecting to $HostName`:$Port."
        }
    }
    finally {
        $client.Dispose()
    }
}

Write-Host "Building unified project..."
Invoke-DotNet @("build", $ProjectPath, "--no-restore")

$quotedDbConfig = ConvertTo-ProcessArgument $DbConfig
$arguments = "--Features:Billing=false --Features:NationPing=false --Features:Certification=true " +
    "--CertificationConfig:Serializer=$Serializer " +
    "--CertificationConfig:DbConfig=$quotedDbConfig " +
    "--Kestrel:EndPoints:Http:Url=http://127.0.0.1:$HttpPort"

if (-not [string]::IsNullOrWhiteSpace($ListenAddressOverride)) {
    $quotedListenAddress = ConvertTo-ProcessArgument $ListenAddressOverride
    $arguments += " --CertificationConfig:ListenAddressOverride=$quotedListenAddress"
}

if ($ListenPortOverride -gt 0) {
    $arguments += " --CertificationConfig:ListenPortOverride=$ListenPortOverride"
}

Write-Host "Starting unified host with live certification enabled..."
$hostState = Start-UnifiedHost -Arguments $arguments
try {
    Wait-ForStatus -Port $HttpPort -Timeout $TimeoutSeconds | Out-Null

    Write-Host "Waiting for certification data refresh..."
    $status = Wait-ForCertificationRefresh -Port $HttpPort -Timeout $TimeoutSeconds

    if ($status.certification.serializer -ne $Serializer) {
        throw "Serializer mismatch. Expected [$Serializer], got [$($status.certification.serializer)]."
    }

    if ([string]::IsNullOrWhiteSpace($status.certification.listenAddress)) {
        throw "Certification refreshed but did not report a listener address."
    }

    if (-not [string]::IsNullOrWhiteSpace($ListenAddressOverride) -and
        $status.certification.listenAddress -ne $ListenAddressOverride) {
        throw "Listener address override mismatch. Expected [$ListenAddressOverride], got [$($status.certification.listenAddress)]."
    }

    if ($null -eq $status.certification.listenPort -or $status.certification.listenPort -le 0) {
        throw "Certification refreshed but did not report a valid listener port."
    }

    if ($ListenPortOverride -gt 0 -and $status.certification.listenPort -ne $ListenPortOverride) {
        throw "Listener port override mismatch. Expected [$ListenPortOverride], got [$($status.certification.listenPort)]."
    }

    Write-Host "Certification refreshed."
    Write-Host "Listener: $($status.certification.listenAddress):$($status.certification.listenPort)"

    if (-not $SkipTcpCheck) {
        $tcpHost = $status.certification.listenAddress
        if (-not [string]::IsNullOrWhiteSpace($TcpHostOverride)) {
            $tcpHost = $TcpHostOverride
        }

        Write-Host "Checking TCP listener at $tcpHost`:$($status.certification.listenPort)..."
        Test-TcpListener -HostName $tcpHost -Port $status.certification.listenPort
    }

    Write-Host "Live certification validation passed."
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
