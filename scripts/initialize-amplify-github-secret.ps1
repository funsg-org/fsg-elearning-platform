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
if (-not $SecretId) { $SecretId = "epico/$Environment/github/amplify-token" }
if ($Region -ne 'us-east-1') { throw 'El secreto de Amplify debe prepararse en us-east-1.' }
if (-not $Execute) {
    Write-Host "Secreto a crear: $SecretId"
    Write-Host "Region: $Region"
    Write-Warning 'Vista previa: no se solicito el token ni se modifico Secrets Manager.'
    exit 0
}
if ($ExpectedAccountId -notmatch '^\d{12}$') { throw 'Indique -ExpectedAccountId con los 12 digitos de la cuenta destino.' }
if ([string]::IsNullOrWhiteSpace($CostCenter) -or $CostCenter -eq 'PENDING') { throw 'Indique un -CostCenter definitivo.' }
$awsBase = @('--region',$Region)
if ($AwsProfile) { $awsBase += @('--profile',$AwsProfile) }
$identityRaw = & aws sts get-caller-identity --output json @awsBase
if ($LASTEXITCODE -ne 0) { throw 'No se pudo verificar la identidad AWS.' }
$identity = ($identityRaw -join [Environment]::NewLine) | ConvertFrom-Json
if ($identity.Account -ne $ExpectedAccountId) { throw "Cuenta activa $($identity.Account); se esperaba $ExpectedAccountId." }

$secretLookup = & aws secretsmanager describe-secret --secret-id $SecretId @awsBase 2>&1
$secretLookupExitCode = $LASTEXITCODE
if ($secretLookupExitCode -eq 0) { throw "El secreto '$SecretId' ya existe; este script no lo sobrescribe ni lo rota." }
if (($secretLookup -join [Environment]::NewLine) -notmatch 'ResourceNotFoundException') { throw "No se pudo comprobar con seguridad si existe el secreto '$SecretId'." }
$secureToken = Read-Host 'Token GitHub para la conexion inicial de Amplify' -AsSecureString
$pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureToken)
$plainToken = $null
$temporaryFile = Join-Path ([System.IO.Path]::GetTempPath()) ("epico-amplify-secret-" + [guid]::NewGuid().ToString('N') + '.json')
try {
    $plainToken = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    if ([string]::IsNullOrWhiteSpace($plainToken)) { throw 'El token no puede estar vacio.' }
    $secretPayload = @{ token=$plainToken } | ConvertTo-Json -Compress
    $request = [ordered]@{
        name=$SecretId
        description='Token de conexion inicial entre AWS Amplify y GitHub.'
        secretString=$secretPayload
        tags=@(
            @{ Key='Solution'; Value='E-Learning' },
            @{ Key='Project'; Value='FSG-Elearning' },
            @{ Key='Client'; Value='EPICO' },
            @{ Key='Environment'; Value=$Environment },
            @{ Key='Owner'; Value='FSG' },
            @{ Key='ManagedBy'; Value='IaC' },
            @{ Key='CostCenter'; Value=$CostCenter }
        )
    }
    [System.IO.File]::WriteAllText($temporaryFile,($request | ConvertTo-Json -Depth 5),[System.Text.UTF8Encoding]::new($false))
    & aws secretsmanager create-secret --cli-input-json "file://$temporaryFile" @awsBase | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo crear el secreto.' }
}
finally {
    $plainToken = $null
    if ($pointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
    Remove-Item -LiteralPath $temporaryFile -Force -ErrorAction SilentlyContinue
}
Write-Host "Secreto '$SecretId' creado sin exponer su valor en la linea de comandos." -ForegroundColor Green
