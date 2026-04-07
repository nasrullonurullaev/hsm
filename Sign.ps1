[CmdletBinding()]
param (
    [string]$CertFile,
    [string]$HsmCreds,
    [string]$TimestampServer,
    [string]$File
)

$ErrorActionPreference = "Stop"
$PSDefaultParameterValues['*:ErrorAction'] = "Stop"

if ([string]::IsNullOrWhiteSpace($CertFile)) {
    if (Test-Path "env:WINDOWS_HSM_CERTIFICATE") {
        $CertFile = $env:WINDOWS_HSM_CERTIFICATE
    } else {
        throw "CertFile is not set and WINDOWS_HSM_CERTIFICATE is missing"
    }
}

if ([string]::IsNullOrWhiteSpace($HsmCreds)) {
    if (Test-Path "env:WINDOWS_HSM_USERPASS") {
        $HsmCreds = $env:WINDOWS_HSM_USERPASS
    } else {
        throw "HsmCreds is not set and WINDOWS_HSM_USERPASS is missing"
    }
}

if ([string]::IsNullOrWhiteSpace($TimestampServer)) {
    if (Test-Path "env:WINDOWS_TIMESTAMP_SERVER") {
        $TimestampServer = $env:WINDOWS_TIMESTAMP_SERVER
    } else {
        $TimestampServer = "http://timestamp.digicert.com"
    }
}

if ([string]::IsNullOrWhiteSpace($File)) {
    throw "File parameter is required"
}

$env:OPENSSL_ENGINES = "C:\Program Files\Amazon\CloudHSM\lib"
$FileSigned = "$env:TMP\tmp_signed"

if (Test-Path "$FileSigned") {
    # write "Delete: $FileSigned"
    ri -Force "$FileSigned"
}

write "Sign: $File"
& osslsigncode sign `
    -pkcs11engine "pkcs11" `
    -pkcs11module "C:\Program Files\Amazon\CloudHSM\bin\cloudhsm_pkcs11.dll" `
    -certs "$CertFile" `
    -key "pkcs11:token=hsm1;object=RSASignPriv1;pin-value=$HsmCreds" `
    -t "$TimestampServer" `
    -in "$File" `
    -out "$FileSigned" `
    -nolegacy `
    -h sha256
if (-not $?) { throw }

$Status = (Get-AuthenticodeSignature "$FileSigned").Status
if ($Status -ne 'Valid') { throw }

write "Move: $FileSigned > $File"
mi -Path "$FileSigned" -Destination "$File" -Force
