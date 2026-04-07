[CmdletBinding()]
param (
    [string]$AwsRegion = "eu-central-1",
    [string]$ClusterId = "cluster-zvyumkgp343",
    [string]$AvailabilityZone = "eu-central-1a",
    [int]$PollSeconds = 10,
    [switch]$SkipConfigure
)

$ErrorActionPreference = "Stop"
$PSDefaultParameterValues['*:ErrorAction'] = "Stop"

$env:AWS_DEFAULT_REGION = $AwsRegion

while ($true) {
    $HsmCount = aws cloudhsmv2 describe-clusters --query 'length(Clusters[0].Hsms)' --output text
    Write-Host "HSM Count: $HsmCount"

    if ($HsmCount -eq 0) {
        Write-Host "Create HSM"
        & aws cloudhsmv2 create-hsm --cluster-id $ClusterId --availability-zone $AvailabilityZone
        if (-not $?) { throw }
    }
    else {
        Write-Host "HSM already exists"
    }

    $HsmState = aws cloudhsmv2 describe-clusters --query 'Clusters[0].Hsms[0].State' --output text
    Write-Host "HSM State: $HsmState"

    if ($HsmState -eq "ACTIVE") {
        break
    }

    Start-Sleep -Seconds $PollSeconds
}

$HsmEniIp = aws cloudhsmv2 describe-clusters --query 'Clusters[0].Hsms[0].EniIp' --output text
Write-Host "HSM EniIp: $HsmEniIp"

if (-not $SkipConfigure) {
    & configure-cli -a $HsmEniIp --disable-key-availability-check
    if (-not $?) { throw }

    & configure-pkcs11 -a $HsmEniIp --disable-key-availability-check
    if (-not $?) { throw }
}
