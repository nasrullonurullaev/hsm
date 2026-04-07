[CmdletBinding()]
param (
    [string]$AwsAccessKeyId,
    [string]$AwsSecretAccessKey,
    [string]$AwsSessionToken,
    [string]$AwsRegion = "eu-central-1",
    [string]$ClusterId = "cluster-zvyumkgp343",
    [string]$AvailabilityZone = "eu-central-1a",
    [int]$PollSeconds = 10,
    [switch]$SkipConfigure
)

$ErrorActionPreference = "Stop"
$PSDefaultParameterValues['*:ErrorAction'] = "Stop"

if ([string]::IsNullOrWhiteSpace($AwsAccessKeyId)) {
    throw "AwsAccessKeyId is required"
}

if ([string]::IsNullOrWhiteSpace($AwsSecretAccessKey)) {
    throw "AwsSecretAccessKey is required"
}

$env:AWS_ACCESS_KEY_ID = $AwsAccessKeyId
$env:AWS_SECRET_ACCESS_KEY = $AwsSecretAccessKey
$env:AWS_DEFAULT_REGION = $AwsRegion

if (-not [string]::IsNullOrWhiteSpace($AwsSessionToken)) {
    $env:AWS_SESSION_TOKEN = $AwsSessionToken
}

function Invoke-AwsCli {
    param (
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $result = & aws @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "AWS CLI command failed: aws $($Arguments -join ' ')"
    }

    return $result
}

function Get-HsmCount {
    Invoke-AwsCli @(
        "cloudhsmv2", "describe-clusters",
        "--query", "length(Clusters[0].Hsms)",
        "--output", "text"
    )
}

function Get-HsmState {
    Invoke-AwsCli @(
        "cloudhsmv2", "describe-clusters",
        "--query", "Clusters[0].Hsms[0].State",
        "--output", "text"
    )
}

function Get-HsmEniIp {
    Invoke-AwsCli @(
        "cloudhsmv2", "describe-clusters",
        "--query", "Clusters[0].Hsms[0].EniIp",
        "--output", "text"
    )
}

while ($true) {
    $HsmCount = (Get-HsmCount).Trim()
    Write-Host "HSM Count: $HsmCount"

    if ($HsmCount -eq "0") {
        Write-Host "Create HSM"

        Invoke-AwsCli @(
            "cloudhsmv2", "create-hsm",
            "--cluster-id", $ClusterId,
            "--availability-zone", $AvailabilityZone
        ) | Out-Null
    }
    else {
        Write-Host "HSM already exists"
    }

    $HsmState = (Get-HsmState).Trim()
    Write-Host "HSM State: $HsmState"

    if ($HsmState -eq "ACTIVE") {
        break
    }

    Start-Sleep -Seconds $PollSeconds
}

$HsmEniIp = (Get-HsmEniIp).Trim()
Write-Host "HSM EniIp: $HsmEniIp"

if (-not $SkipConfigure) {
    & configure-cli -a $HsmEniIp --disable-key-availability-check
    if ($LASTEXITCODE -ne 0) {
        throw "configure-cli failed"
    }

    & configure-pkcs11 -a $HsmEniIp --disable-key-availability-check
    if ($LASTEXITCODE -ne 0) {
        throw "configure-pkcs11 failed"
    }
}
