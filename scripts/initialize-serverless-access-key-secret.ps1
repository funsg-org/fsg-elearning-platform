[CmdletBinding()]
param(
    [switch]$Execute,
    [ValidateSet('develop','qa','production')][string]$Environment,
    [string]$SecretId,
    [string]$AwsProfile,
    [string]$ExpectedAccountId,
    [string]$Region = 'us-east-1',
    [string]$CostCenter
)
$ErrorActionPreference = 'Stop'
if (-not $Environment) { $Environment = & (Join-Path $PSScriptRoot 'get-deployment-environment.ps1') }
. (Join-Path $PSScriptRoot 'load-environment.ps1') -EnvironmentName $Environment -Quiet | Out-Null
if (-not $SecretId) { $SecretId = $env:SERVERLESS_ACCESS_KEY_SECRET_ID }
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
$expectedRoleName = "$($env:RESOURCE_PREFIX)-deployment-$Environment"
if ($identity.Arn -notmatch "^arn:aws:sts::$ExpectedAccountId`:assumed-role/$([regex]::Escape($expectedRoleName))/") {
    throw "La identidad activa '$($identity.Arn)' no es una sesión de $expectedRoleName. Ejecute enter-deployment-role.ps1 en esta misma terminal."
}
$previousErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$lookup = & aws secretsmanager describe-secret --secret-id $SecretId @awsBase 2>&1
$lookupExit = $LASTEXITCODE
$ErrorActionPreference = $previousErrorActionPreference
if ($lookupExit -eq 0) { throw "El secreto '$SecretId' ya existe; este script no lo sobrescribe." }
$lookupText = (($lookup | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine)
if ($lookupText -notmatch 'ResourceNotFoundException') { throw "No se pudo comprobar con seguridad el secreto '$SecretId': $lookupText" }
$secureKey = Read-Host 'SERVERLESS_ACCESS_KEY' -AsSecureString
$pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
$plainKey = $null
$temporaryFile = Join-Path ([System.IO.Path]::GetTempPath()) ("epico-serverless-secret-" + [guid]::NewGuid().ToString('N') + '.json')
try {
    $plainKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    if ([string]::IsNullOrWhiteSpace($plainKey)) { throw 'La clave no puede estar vacia.' }
    $request = [ordered]@{
        Name=$SecretId
        Description='Access key operativa para autenticar Serverless Framework v4.'
        SecretString=(@{ accessKey=$plainKey } | ConvertTo-Json -Compress)
        Tags=@(
            @{ Key='Solution'; Value=$env:TAG_SOLUTION }, @{ Key='Project'; Value=$env:TAG_PROJECT },
            @{ Key='Client'; Value=$env:TAG_CLIENT }, @{ Key='Environment'; Value=$Environment },
            @{ Key='Owner'; Value=$env:TAG_OWNER }, @{ Key='ManagedBy'; Value=$env:TAG_MANAGED_BY }, @{ Key='CostCenter'; Value=$CostCenter }
        )
    }
    [System.IO.File]::WriteAllText($temporaryFile,($request | ConvertTo-Json -Depth 5),[System.Text.UTF8Encoding]::new($false))
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $createOutput = & aws secretsmanager create-secret --cli-input-json "file://$temporaryFile" @awsBase 2>&1
    $createExitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousErrorActionPreference
    if ($createExitCode -ne 0) {
        $createOutputText = (($createOutput | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine)
        throw "No se pudo crear el secreto Serverless: $createOutputText"
    }
} finally {
    $plainKey = $null
    if ($pointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
    Remove-Item -LiteralPath $temporaryFile -Force -ErrorAction SilentlyContinue
}
Write-Host "Secreto '$SecretId' creado sin exponer su valor." -ForegroundColor Green
