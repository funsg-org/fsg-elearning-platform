[CmdletBinding()]
param(
    [switch]$Execute,
    [switch]$AllowDirty,
    [string]$AwsProfile,
    [string]$ExpectedAccountId,
    [string]$Region = 'us-east-1',
    [string]$StackName = 'epico-platform-production',
    [string]$ParametersFile
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($ParametersFile)) {
    $ParametersFile = Join-Path $repositoryRoot 'infrastructure\parameters.json'
}
$templateFile = Join-Path $repositoryRoot 'infrastructure\shared-resources.yml'
$platformOutputsFile = Join-Path $repositoryRoot 'config\platform-outputs.env'
$serviceOutputsFile = Join-Path $repositoryRoot 'config\service-outputs.env'

$services = @(
    'services\ms-aprendamosgye-auth',
    'services\ms-aprendamosgye-course',
    'services\ms-aprendamosgye-menu',
    'services\ms-aprendamosgye-metrics',
    'services\ms-aprendamosgye-subscriptions',
    'services\ms-aprendamosgye-users',
    'services\ms-aprendamosgye-videos'
)

function Invoke-CheckedCommand {
    param(
        [Parameter(Mandatory = $true)][string]$Executable,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$FailureMessage,
        [string]$WorkingDirectory = $repositoryRoot
    )
    Push-Location $WorkingDirectory
    try {
        & $Executable @Arguments
        if ($LASTEXITCODE -ne 0) {
            throw $FailureMessage
        }
    }
    finally {
        Pop-Location
    }
}

function Get-CloudFormationParameters {
    param([string]$Path)
    $parameters = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    $arguments = [System.Collections.Generic.List[string]]::new()
    foreach ($parameter in $parameters) {
        if ($parameter.ParameterKey -eq 'CostCenterTag' -and $parameter.ParameterValue -eq 'PENDING') {
            throw 'CostCenterTag continúa en PENDING. Defínalo antes de desplegar.'
        }
        if ($parameter.ParameterKey -eq 'MediaCorsAllowedOrigins' -and $parameter.ParameterValue -eq '*') {
            throw 'MediaCorsAllowedOrigins no puede permanecer en * durante el despliegue.'
        }
        $arguments.Add("$($parameter.ParameterKey)=$($parameter.ParameterValue)")
    }
    return $arguments.ToArray()
}

Write-Host "Modo: $(if ($Execute) { 'EJECUCIÓN' } else { 'PLAN SEGURO' })"
Write-Host "Stack compartido: $StackName"
Write-Host "Región: $Region"

if ($Region -ne 'us-east-1') {
    throw 'La plataforma EPICO debe desplegarse en us-east-1.'
}
if (-not (Test-Path -LiteralPath $templateFile -PathType Leaf)) {
    throw "No se encontró la plantilla compartida: $templateFile"
}

$expectedBranch = 'feature/epico-deployment-readiness'
$currentBranch = (& git -C $repositoryRoot branch --show-current).Trim()
if ($currentBranch -ne $expectedBranch) {
    throw "El despliegue debe prepararse desde '$expectedBranch'; rama actual: '$currentBranch'."
}
if (-not $AllowDirty) {
    $dirty = & git -C $repositoryRoot status --porcelain --untracked-files=no
    if ($dirty) {
        throw 'El repositorio padre tiene cambios rastreados sin confirmar. Use -AllowDirty solo para diagnóstico controlado.'
    }
}

foreach ($service in $services) {
    $servicePath = Join-Path $repositoryRoot $service
    if (-not (Test-Path -LiteralPath (Join-Path $servicePath 'serverless.yml') -PathType Leaf)) {
        throw "Falta serverless.yml en $service."
    }
    $branch = (& git -C $servicePath branch --show-current).Trim()
    if ($branch -ne $expectedBranch) {
        throw "El submódulo $service no está en '$expectedBranch'."
    }
    if (-not $AllowDirty) {
        $serviceDirty = & git -C $servicePath status --porcelain --untracked-files=no
        if ($serviceDirty) {
            throw "El submódulo $service tiene cambios rastreados sin confirmar."
        }
    }
}

& (Join-Path $PSScriptRoot 'validate-infrastructure.ps1') -TemplateFile $templateFile -Region $Region -AwsProfile $AwsProfile

if (-not $Execute) {
    Write-Host ''
    Write-Host 'Orden que se ejecutará:' -ForegroundColor Cyan
    Write-Host '1. Desplegar CloudFormation compartido.'
    Write-Host '2. Exportar Cognito, Secrets Manager, S3 y CloudFront.'
    Write-Host '3. Validar el contrato de plataforma.'
    $step = 4
    foreach ($service in $services) {
        Write-Host "$step. Desplegar $service."
        $step++
    }
    Write-Host "$step. Exportar URLs de API Gateway."
    $step++
    Write-Host "$step. Generar mapas locales para Amplify."
    Write-Host ''
    Write-Warning 'No se creó ni modificó ningún recurso. Use -Execute únicamente después de completar parameters.json.'
    exit 0
}

if (-not (Test-Path -LiteralPath $ParametersFile -PathType Leaf)) {
    throw "Falta el archivo local de parámetros: $ParametersFile. Copie infrastructure/parameters.example.json y complete CostCenter/CORS."
}
if ($ExpectedAccountId -notmatch '^\d{12}$') {
    throw 'Debe indicar -ExpectedAccountId con los 12 dígitos de la cuenta destino.'
}
$parameterOverrides = Get-CloudFormationParameters -Path $ParametersFile

$awsBaseArguments = @()
if (-not [string]::IsNullOrWhiteSpace($AwsProfile)) {
    $awsBaseArguments = @('--profile', $AwsProfile)
    $env:AWS_PROFILE = $AwsProfile
}

$identityArguments = @('sts', 'get-caller-identity', '--output', 'json') + $awsBaseArguments
$identityJson = & aws @identityArguments
if ($LASTEXITCODE -ne 0) {
    throw 'No se pudo verificar la identidad AWS activa.'
}
$identity = ($identityJson -join [Environment]::NewLine) | ConvertFrom-Json
if ($identity.Account -ne $ExpectedAccountId) {
    throw "La sesión AWS pertenece a $($identity.Account), pero se esperaba $ExpectedAccountId."
}
Write-Host "Cuenta AWS verificada: $($identity.Account) ($($identity.Arn))" -ForegroundColor Green

$deployArguments = @(
    'cloudformation', 'deploy',
    '--template-file', $templateFile,
    '--stack-name', $StackName,
    '--region', $Region,
    '--capabilities', 'CAPABILITY_NAMED_IAM',
    '--no-fail-on-empty-changeset',
    '--parameter-overrides'
) + $parameterOverrides + $awsBaseArguments
Invoke-CheckedCommand -Executable 'aws' -Arguments $deployArguments -FailureMessage 'Falló el despliegue de la infraestructura compartida.'

$exportPlatformArguments = @{ StackName = $StackName; Region = $Region; OutputFile = $platformOutputsFile }
if (-not [string]::IsNullOrWhiteSpace($AwsProfile)) { $exportPlatformArguments.AwsProfile = $AwsProfile }
& (Join-Path $PSScriptRoot 'export-cloudformation-outputs.ps1') @exportPlatformArguments
& (Join-Path $PSScriptRoot 'validate-environment.ps1') -OutputsFile $platformOutputsFile -RequirePlatformOutputs

. (Join-Path $PSScriptRoot 'load-environment.ps1') -OutputsFile $platformOutputsFile -Quiet | Out-Null
foreach ($service in $services) {
    $servicePath = Join-Path $repositoryRoot $service
    Write-Host "Desplegando $service..." -ForegroundColor Cyan
    Invoke-CheckedCommand -Executable 'npx' -Arguments @('serverless', 'deploy', '--stage', $env:ENVIRONMENT, '--region', $Region) -WorkingDirectory $servicePath -FailureMessage "Falló el despliegue de $service."
}

$exportServicesArguments = @{ Region = $Region; ResourcePrefix = $env:RESOURCE_PREFIX; Environment = $env:ENVIRONMENT; OutputFile = $serviceOutputsFile }
if (-not [string]::IsNullOrWhiteSpace($AwsProfile)) { $exportServicesArguments.AwsProfile = $AwsProfile }
& (Join-Path $PSScriptRoot 'export-serverless-outputs.ps1') @exportServicesArguments
& (Join-Path $PSScriptRoot 'validate-environment.ps1') -OutputsFile $platformOutputsFile -ServiceOutputsFile $serviceOutputsFile -RequirePlatformOutputs -RequireServiceOutputs
& (Join-Path $PSScriptRoot 'export-amplify-environments.ps1') -PlatformOutputsFile $platformOutputsFile -ServiceOutputsFile $serviceOutputsFile

Write-Host 'Despliegue de infraestructura y microservicios completado.' -ForegroundColor Green
Write-Host 'Amplify no fue modificado. Revise config/amplify-*-env.json antes de aplicarlo manualmente.'
