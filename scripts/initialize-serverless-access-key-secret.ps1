[CmdletBinding()]
param(
    [switch]$Execute,
    [ValidateSet('qa','production')][string]$Environment,
    [string]$SecretId,
    [string]$AwsProfile,
    [string]$ExpectedAccountId,
    [string]$Region = 'us-east-1',
    [string]$CostCenter
)
$ErrorActionPreference = 'Stop'
if (-not $Environment) { $Environment = & (Join-Path $PSScriptRoot 'get-deployment-environment.ps1') }
if (-not $SecretId) { $SecretId = "epico/$Environment/serverless/access-key" }
if ($Region -ne 'us-east-1') { throw 'El secreto Serverless debe crearse en us-east-1.' }
if (-not $Execute) { Write-Host "Secreto a crear: $SecretId"; Write-Warning 'Vista previa: no se solicito la clave ni se modifico Secrets Manager.'; exit 0 }
if ($ExpectedAccountId -notmatch '^\d{12}$') { throw 'Indique -ExpectedAccountId con 12 digitos.' }
if (-not $CostCenter -or $CostCenter -eq 'PENDING') { throw 'Indique un -CostCenter definitivo.' }
$awsBase = @('--region',$Region)
if ($AwsProfile) { $awsBase += @('--profile',$AwsProfile) }
$identityRaw = & aws sts get-caller-identity --output json @awsBase
if ($LASTEXITCODE -ne 0) { throw 'No se pudo verificar la identidad AWS.' }
$identity = ($identityRaw -join [Environment]::NewLine) | ConvertFrom-Json
if ($identity.Account -ne $ExpectedAccountId) { throw "Cuenta activa $($identity.Account); se esperaba $ExpectedAccountId." }
$lookup = & aws secretsmanager describe-secret --secret-id $SecretId @awsBase 2>&1
$lookupExit = $LASTEXITCODE
if ($lookupExit -eq 0) { throw "El secreto '$SecretId' ya existe; este script no lo sobrescribe." }
if (($lookup -join [Environment]::NewLine) -notmatch 'ResourceNotFoundException') { throw "No se pudo comprobar con seguridad el secreto '$SecretId'." }
$secureKey = Read-Host 'SERVERLESS_ACCESS_KEY' -AsSecureString
$pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
$plainKey = $null
$temporaryFile = Join-Path ([System.IO.Path]::GetTempPath()) ("epico-serverless-secret-" + [guid]::NewGuid().ToString('N') + '.json')
try {
    $plainKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    if ([string]::IsNullOrWhiteSpace($plainKey)) { throw 'La clave no puede estar vacia.' }
    $request = [ordered]@{
        name=$SecretId
        description='Access key operativa para autenticar Serverless Framework v4.'
        secretString=(@{ accessKey=$plainKey } | ConvertTo-Json -Compress)
        tags=@(
            @{ Key='Solution'; Value='E-Learning' }, @{ Key='Project'; Value='FSG-Elearning' },
            @{ Key='Client'; Value='EPICO' }, @{ Key='Environment'; Value=$Environment },
            @{ Key='Owner'; Value='FSG' }, @{ Key='ManagedBy'; Value='IaC' }, @{ Key='CostCenter'; Value=$CostCenter }
        )
    }
    [System.IO.File]::WriteAllText($temporaryFile,($request | ConvertTo-Json -Depth 5),[System.Text.UTF8Encoding]::new($false))
    & aws secretsmanager create-secret --cli-input-json "file://$temporaryFile" @awsBase | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo crear el secreto Serverless.' }
} finally {
    $plainKey = $null
    if ($pointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
    Remove-Item -LiteralPath $temporaryFile -Force -ErrorAction SilentlyContinue
}
Write-Host "Secreto '$SecretId' creado sin exponer su valor." -ForegroundColor Green
