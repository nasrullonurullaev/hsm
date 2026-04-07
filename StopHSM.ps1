[CmdletBinding()]
param (
    [string]$AwsRegion = "eu-central-1",
    [string]$ClusterId = "cluster-zvyumkgp343",
    [int]$PollSeconds = 10,
    [switch]$DeleteAll
)

$ErrorActionPreference = "Stop"
$PSDefaultParameterValues['*:ErrorAction'] = "Stop"

$env:AWS_DEFAULT_REGION = $AwsRegion

while ($true) {
    $HsmCount = aws cloudhsmv2 describe-clusters --query 'length(Clusters[0].Hsms)' --output text
    Write-Host "HSM Count: $HsmCount"

    if ($HsmCount -eq 0 -or $HsmCount -eq "None") {
        Write-Host "No HSM found"
        break
    }

    $HsmState = aws cloudhsmv2 describe-clusters --query 'Clusters[0].Hsms[0].State' --output text
    Write-Host "HSM State: $HsmState"

    if ($HsmState -eq "ACTIVE") {
        $HsmEniIp = aws cloudhsmv2 describe-clusters --query 'Clusters[0].Hsms[0].EniIp' --output text
        Write-Host "Delete HSM with EniIp: $HsmEniIp"

        & aws cloudhsmv2 delete-hsm --cluster-id $ClusterId --eni-ip $HsmEniIp
        if (-not $?) { throw }
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
