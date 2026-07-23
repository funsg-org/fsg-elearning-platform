[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidatePattern('^[^@\s]+@[^@\s]+\.[^@\s]+$')][string]$Email,
    [Parameter(Mandatory = $true)][securestring]$Password,
    [string]$Name = 'Administrador',
    [ValidateSet('develop','qa','production')][string]$Environment,
    [string]$OutputsFile,
    [string]$AwsProfile,
    [string]$Region = 'us-east-1',
    [Parameter(Mandatory = $true)][ValidatePattern('^\d{12}$')][string]$ExpectedAccountId,
    [switch]$Execute
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not $Environment) { $Environment = & (Join-Path $PSScriptRoot 'get-deployment-environment.ps1') }
if (-not $OutputsFile) { $OutputsFile = Join-Path $repositoryRoot "config\platform-outputs.$Environment.env" }
if ($Region -ne 'us-east-1') { throw 'La region obligatoria es us-east-1.' }
if (-not (Test-Path -LiteralPath $OutputsFile -PathType Leaf)) { throw 'Falta config/platform-outputs.env; exporte primero los Outputs del stack compartido.' }

. (Join-Path $PSScriptRoot 'load-environment.ps1') -EnvironmentName $Environment -OutputsFile $OutputsFile -Quiet | Out-Null
foreach ($variableName in @('COGNITO_USER_POOL_ID','COGNITO_ADMINISTRATORS_GROUP')) {
    if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($variableName))) { throw "Falta $variableName en el contrato de plataforma." }
}

$awsBase = @('--region', $Region)
if ($AwsProfile) { $awsBase += @('--profile', $AwsProfile) }
function Invoke-AwsNative {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & aws @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
    [pscustomobject]@{
        ExitCode = $exitCode
        Output = @($output)
        Text = (($output | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine)
    }
}

$identityCall = Invoke-AwsNative (@('sts','get-caller-identity','--output','json') + $awsBase)
if ($identityCall.ExitCode -ne 0) { throw "No se pudo consultar la identidad AWS: $($identityCall.Text)" }
$identity = ($identityCall.Output -join [Environment]::NewLine) | ConvertFrom-Json
if ($identity.Account -ne $ExpectedAccountId) { throw 'La identidad AWS activa no corresponde a la cuenta esperada.' }
$expectedRoleName = "$($env:RESOURCE_PREFIX)-deployment-$Environment"
if ($identity.Arn -notmatch "^arn:aws:sts::$ExpectedAccountId`:assumed-role/$([regex]::Escape($expectedRoleName))/") {
    throw "La identidad activa '$($identity.Arn)' no es una sesión del rol '$expectedRoleName'. Vuelva a ejecutar enter-deployment-role.ps1."
}

if (-not $Execute) {
    Write-Host "Vista previa: crear o actualizar '$Email' en $env:COGNITO_USER_POOL_ID y agregarlo a $env:COGNITO_ADMINISTRATORS_GROUP."
    Write-Host 'No se modifico AWS. Repita con -Execute para confirmar.'
    return
}

$passwordPtr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
try {
    $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordPtr)
    if ($plainPassword.Length -lt 12 -or $plainPassword -notmatch '[a-z]' -or $plainPassword -notmatch '[A-Z]' -or $plainPassword -notmatch '\d' -or $plainPassword -notmatch '[^A-Za-z0-9]') {
        throw 'La clave inicial debe tener al menos 12 caracteres, mayuscula, minuscula, numero y simbolo.'
    }
    $lookup = Invoke-AwsNative (@('cognito-idp','admin-get-user','--user-pool-id',$env:COGNITO_USER_POOL_ID,'--username',$Email) + $awsBase)
    if ($lookup.ExitCode -ne 0) {
        if ($lookup.Text -notmatch 'UserNotFoundException') {
            throw "No se pudo comprobar si existe el usuario Cognito: $($lookup.Text)"
        }
        $create = Invoke-AwsNative (@('cognito-idp','admin-create-user','--user-pool-id',$env:COGNITO_USER_POOL_ID,'--username',$Email,'--user-attributes',"Name=email,Value=$Email",'Name=email_verified,Value=true',"Name=name,Value=$Name",'--message-action','SUPPRESS') + $awsBase)
        if ($create.ExitCode -ne 0) { throw "No se pudo crear el usuario Cognito: $($create.Text)" }
    }
    $setPassword = Invoke-AwsNative (@('cognito-idp','admin-set-user-password','--user-pool-id',$env:COGNITO_USER_POOL_ID,'--username',$Email,'--password',$plainPassword,'--permanent') + $awsBase)
    if ($setPassword.ExitCode -ne 0) { throw "No se pudo establecer la clave inicial: $($setPassword.Text)" }
    $addToGroup = Invoke-AwsNative (@('cognito-idp','admin-add-user-to-group','--user-pool-id',$env:COGNITO_USER_POOL_ID,'--username',$Email,'--group-name',$env:COGNITO_ADMINISTRATORS_GROUP) + $awsBase)
    if ($addToGroup.ExitCode -ne 0) { throw "No se pudo agregar el usuario al grupo administrativo: $($addToGroup.Text)" }
}
finally {
    if ($passwordPtr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPtr) }
    $plainPassword = $null
}

Write-Host "Administrador creado y asignado al grupo: $Email" -ForegroundColor Green
Write-Host 'Entregue la clave por un canal separado y solicite su cambio inmediato.'
