param (
    [Parameter(Mandatory = $true)]
    [string]$filePath
)

$trace = $ENV:TRACE
if (-Not [string]::IsNullOrWhiteSpace($trace)) {
    if ([System.Convert]::ToBoolean($trace)) {
        Set-PSDebug -Trace 2
    }
}

# Sovereign Zed supports a PFX/signtool signing mode in addition to the upstream
# Azure Trusted Signing mode. The mode is selected by
# `SOVEREIGN_WINDOWS_SIGNING_MODE`:
#
#   pfx     - sign with `signtool.exe` using a PFX cert provided via
#             `SOVEREIGN_WINDOWS_CERT_PFX_B64` (base64 PFX) and
#             `SOVEREIGN_WINDOWS_CERT_PASSWORD`. Optional environment knobs:
#             `FILE_DIGEST` (default SHA256), `TIMESTAMP_SERVER` (default
#             http://timestamp.digicert.com).
#   azure   - upstream Azure Trusted Signing path; requires `ENDPOINT`,
#             `ACCOUNT_NAME`, `CERT_PROFILE_NAME`, `FILE_DIGEST`,
#             `TIMESTAMP_DIGEST`, `TIMESTAMP_SERVER`.
#
# If unset, the script defaults to `azure` to preserve upstream behaviour.

$signingMode = $ENV:SOVEREIGN_WINDOWS_SIGNING_MODE
if ([string]::IsNullOrWhiteSpace($signingMode)) {
    $signingMode = 'azure'
}
$signingMode = $signingMode.ToLowerInvariant()

switch ($signingMode) {
    'pfx' {
        $pfxB64 = $ENV:SOVEREIGN_WINDOWS_CERT_PFX_B64
        if ([string]::IsNullOrWhiteSpace($pfxB64)) {
            throw "The 'SOVEREIGN_WINDOWS_CERT_PFX_B64' env is required for pfx signing mode."
        }

        $pfxPassword = $ENV:SOVEREIGN_WINDOWS_CERT_PASSWORD
        if ([string]::IsNullOrWhiteSpace($pfxPassword)) {
            throw "The 'SOVEREIGN_WINDOWS_CERT_PASSWORD' env is required for pfx signing mode."
        }

        $fileDigest = $ENV:FILE_DIGEST
        if ([string]::IsNullOrWhiteSpace($fileDigest)) {
            $fileDigest = 'SHA256'
        }

        $timeStampServer = $ENV:TIMESTAMP_SERVER
        if ([string]::IsNullOrWhiteSpace($timeStampServer)) {
            $timeStampServer = 'http://timestamp.digicert.com'
        }

        $pfxDir = Join-Path $env:TEMP "sovereign-signing"
        New-Item -ItemType Directory -Force -Path $pfxDir | Out-Null
        $pfxPath = Join-Path $pfxDir "sovereign-codesign.pfx"

        try {
            [System.IO.File]::WriteAllBytes($pfxPath, [Convert]::FromBase64String($pfxB64))

            $signtool = (Get-Command signtool.exe -ErrorAction Stop).Source
            $signtoolArgs = @(
                'sign',
                '/fd', $fileDigest,
                '/tr', $timeStampServer,
                '/td', $fileDigest,
                '/f', $pfxPath,
                '/p', $pfxPassword,
                $filePath
            )

            & $signtool @signtoolArgs
            if ($LASTEXITCODE -ne 0) {
                throw "signtool.exe failed with exit code $LASTEXITCODE while signing $filePath."
            }
        }
        finally {
            if (Test-Path $pfxPath) {
                Remove-Item -Path $pfxPath -Force
            }
        }
    }
    'azure' {
        $params = @{}

        $endpoint = $ENV:ENDPOINT
        if ([string]::IsNullOrWhiteSpace($endpoint)) {
            throw "The 'ENDPOINT' env is required."
        }
        $params["Endpoint"] = $endpoint

        $trustedSigningAccountName = $ENV:ACCOUNT_NAME
        if ([string]::IsNullOrWhiteSpace($trustedSigningAccountName)) {
            throw "The 'ACCOUNT_NAME' env is required."
        }
        $params["CodeSigningAccountName"] = $trustedSigningAccountName

        $certificateProfileName = $ENV:CERT_PROFILE_NAME
        if ([string]::IsNullOrWhiteSpace($certificateProfileName)) {
            throw "The 'CERT_PROFILE_NAME' env is required."
        }
        $params["CertificateProfileName"] = $certificateProfileName

        $fileDigest = $ENV:FILE_DIGEST
        if ([string]::IsNullOrWhiteSpace($fileDigest)) {
            throw "The 'FILE_DIGEST' env is required."
        }
        $params["FileDigest"] = $fileDigest

        $timeStampDigest = $ENV:TIMESTAMP_DIGEST
        if ([string]::IsNullOrWhiteSpace($timeStampDigest)) {
            throw "The 'TIMESTAMP_DIGEST' env is required."
        }
        $params["TimestampDigest"] = $timeStampDigest

        $timeStampServer = $ENV:TIMESTAMP_SERVER
        if ([string]::IsNullOrWhiteSpace($timeStampServer)) {
            throw "The 'TIMESTAMP_SERVER' env is required."
        }
        $params["TimestampRfc3161"] = $timeStampServer

        $params["Files"] = $filePath

        Invoke-TrustedSigning @params
    }
    default {
        throw "Unknown SOVEREIGN_WINDOWS_SIGNING_MODE '$signingMode'; expected 'pfx' or 'azure'."
    }
}
