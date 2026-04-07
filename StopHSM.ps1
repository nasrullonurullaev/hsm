[CmdletBinding()]
param (
    [string]$AwsAccessKeyId,
    [string]$AwsSecretAccessKey,
    [string]$AwsSessionToken,
    [string]$AwsRegion = "eu-central-1",
    [string]$ClusterId = "cluster-zvyumkgp343",
    [int]$PollSeconds = 10,
    [switch]$DeleteAll
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

    if ($HsmCount -eq "0" -or $HsmCount -eq "None") {
        Write-Host "No HSM found"
        break
    }

    $HsmState = (Get-HsmState).Trim()
    Write-Host "HSM State: $HsmState"

    if ($HsmState -eq "ACTIVE") {
        $HsmEniIp = (Get-HsmEniIp).Trim()
        Write-Host "Delete HSM with EniIp: $HsmEniIp"

        Invoke-AwsCli @(
            "cloudhsmv2", "delete-hsm",
            "--cluster-id", $ClusterId,
            "--eni-ip", $HsmEniIp
        ) | Out-Null
    }
    elseif ($HsmState -eq "DELETE_IN_PROGRESS") {
        Write-Host "Deletion already in progress"
    }
    else {
        Write-Host "HSM is in state: $HsmState"
    }

    if (-not $DeleteAll) {
        break
    }

    Start-Sleep -Seconds $PollSeconds
}
