[CmdletBinding()]
param(
    [ValidateSet('qa','production')][string]$Environment = 'production',
    [string]$SourceBranch,
    [switch]$Execute,
    [switch]$ApproveChangeSets,
    [switch]$AllowDirty,
    [string]$AwsProfile,
    [string]$ExpectedAccountId,
    [string]$DeploymentRoleArn,
    [string]$Region = 'us-east-1',
    [string]$StackName,
    [string]$AmplifyStackName,
    [string]$ParametersFile,
    [string]$AmplifyParametersFile,
    [string]$AmplifyOutputsFile
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not $SourceBranch) { $SourceBranch = if ($Environment -eq 'qa') { 'qa' } else { 'main' } }
if (-not $StackName) { $StackName = "epico-platform-$Environment" }
if (-not $AmplifyStackName) { $AmplifyStackName = "epico-amplify-$Environment" }
if ([string]::IsNullOrWhiteSpace($ParametersFile)) {
    $ParametersFile = Join-Path $repositoryRoot "infrastructure\parameters.$Environment.json"
}
if ([string]::IsNullOrWhiteSpace($AmplifyOutputsFile)) {
    $AmplifyOutputsFile = Join-Path $repositoryRoot "config\amplify-outputs.$Environment.env"
}
if ([string]::IsNullOrWhiteSpace($AmplifyParametersFile)) {
    $AmplifyParametersFile = Join-Path $repositoryRoot "infrastructure\amplify-parameters.$Environment.json"
}
$templateFile = Join-Path $repositoryRoot 'infrastructure\shared-resources.yml'
$platformOutputsFile = Join-Path $repositoryRoot "config\platform-outputs.$Environment.env"
$serviceOutputsFile = Join-Path $repositoryRoot "config\service-outputs.$Environment.env"

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
    param([string]$Path, [string]$CorsAllowedOrigins)
    $parameters = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    $arguments = [System.Collections.Generic.List[string]]::new()
    foreach ($parameter in $parameters) {
        if ($parameter.ParameterKey -eq 'CostCenterTag' -and $parameter.ParameterValue -eq 'PENDING') {
            throw 'CostCenterTag continúa en PENDING. Defínalo antes de desplegar.'
        }
        if ($parameter.ParameterKey -eq 'MediaCorsAllowedOrigins') {
            continue
        }
        $arguments.Add("$($parameter.ParameterKey)=$($parameter.ParameterValue)")
    }
    $arguments.Add("MediaCorsAllowedOrigins=$CorsAllowedOrigins")
    return $arguments.ToArray()
}

Write-Host "Modo: $(if ($Execute) { 'EJECUCIÓN' } else { 'PLAN SEGURO' })"
Write-Host "Stack compartido: $StackName"
Write-Host "Stack Amplify: $AmplifyStackName"
Write-Host "Región: $Region"

if ($Region -ne 'us-east-1') {
    throw 'La plataforma EPICO debe desplegarse en us-east-1.'
}
if (-not (Test-Path -LiteralPath $templateFile -PathType Leaf)) {
    throw "No se encontró la plantilla compartida: $templateFile"
}

$expectedBranch = $SourceBranch
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
& (Join-Path $PSScriptRoot 'validate-amplify-infrastructure.ps1') -Region $Region -AwsProfile $AwsProfile

if (-not $Execute) {
    Write-Host ''
    Write-Host 'Orden que se ejecutará:' -ForegroundColor Cyan
    Write-Host '1. Crear o actualizar las aplicaciones Amplify con auto-build desactivado.'
    Write-Host '2. Exportar y validar las URLs de ambos frontends.'
    Write-Host '3. Inyectar los orígenes exactos en el CORS y desplegar CloudFormation compartido.'
    Write-Host '4. Exportar Cognito, Secrets Manager, S3 y CloudFront.'
    Write-Host '5. Validar el contrato de plataforma.'
    $step = 6
    foreach ($service in $services) {
        Write-Host "$step. Desplegar $service."
        $step++
    }
    Write-Host "$step. Exportar URLs de API Gateway."
    $step++
    Write-Host "$step. Generar mapas locales para Amplify."
    $step++
    Write-Host "$step. Aplicar variables públicas a ambas ramas manteniendo auto-build desactivado."
    Write-Host ''
    Write-Warning 'No se creó ni modificó ningún recurso. Use -Execute únicamente después de completar ambos archivos parameters.json.'
    exit 0
}

if (-not (Test-Path -LiteralPath $ParametersFile -PathType Leaf)) {
    throw "Falta el archivo local de parámetros: $ParametersFile. Copie infrastructure/parameters.example.json y complete CostCenter."
}
if (-not $ApproveChangeSets) { throw 'La ejecución requiere -ApproveChangeSets para autorizar los cambios mostrados por CloudFormation.' }
if (-not (Test-Path -LiteralPath $AmplifyParametersFile -PathType Leaf)) {
    throw "Falta el archivo local de parámetros Amplify: $AmplifyParametersFile."
}
if ($ExpectedAccountId -notmatch '^\d{12}$') {
    throw 'Debe indicar -ExpectedAccountId con los 12 dígitos de la cuenta destino.'
}
if (-not $DeploymentRoleArn) { throw 'Debe indicar -DeploymentRoleArn para evitar despliegues con el principal bootstrap.' }
& (Join-Path $PSScriptRoot 'enter-deployment-role.ps1') -RoleArn $DeploymentRoleArn -Environment $Environment -AwsProfile $AwsProfile -Region $Region
$AwsProfile = $null
$preflightArguments = @{
    ExpectedAccountId=$ExpectedAccountId
    ExpectedDeploymentRoleArn=$DeploymentRoleArn
    Environment=$Environment
    SourceBranch=$SourceBranch
    Region=$Region
    ParametersFile=$ParametersFile
    AmplifyParametersFile=$AmplifyParametersFile
}
if (-not [string]::IsNullOrWhiteSpace($AwsProfile)) { $preflightArguments.AwsProfile=$AwsProfile }
& (Join-Path $PSScriptRoot 'test-deployment-readiness.ps1') @preflightArguments

foreach ($service in $services) {
    $servicePath=Join-Path $repositoryRoot $service
    Write-Host "Instalando dependencias bloqueadas de $service..." -ForegroundColor Cyan
    Invoke-CheckedCommand -Executable 'npm' -Arguments @('ci','--ignore-scripts') -WorkingDirectory $servicePath -FailureMessage "npm ci falló en $service. No se modificó AWS."
}

$amplifyBootstrapArguments = @{
    Environment = $Environment
    Execute = $true
    ApproveChangeSets = $true
    StackName = $AmplifyStackName
    ParametersFile = $AmplifyParametersFile
    ExpectedAccountId = $ExpectedAccountId
    Region = $Region
    OutputFile = $AmplifyOutputsFile
}
if (-not [string]::IsNullOrWhiteSpace($AwsProfile)) { $amplifyBootstrapArguments.AwsProfile = $AwsProfile }
& (Join-Path $PSScriptRoot 'deploy-amplify-bootstrap.ps1') @amplifyBootstrapArguments

$corsAllowedOrigins = & (Join-Path $PSScriptRoot 'get-amplify-cors-origins.ps1') -AmplifyOutputsFile $AmplifyOutputsFile
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($corsAllowedOrigins)) {
    throw 'No se pudieron resolver los orígenes CORS desde Amplify.'
}
Write-Host "Orígenes CORS validados: $corsAllowedOrigins" -ForegroundColor Green
$parameterOverrides = Get-CloudFormationParameters -Path $ParametersFile -CorsAllowedOrigins $corsAllowedOrigins

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

$sharedChangeSetArguments = @{ StackName=$StackName; TemplateFile=$templateFile; ParameterOverrides=$parameterOverrides; Capabilities=@('CAPABILITY_NAMED_IAM'); ApproveExecution=$true; Region=$Region }
& (Join-Path $PSScriptRoot 'invoke-cloudformation-change-set.ps1') @sharedChangeSetArguments

$exportPlatformArguments = @{ StackName = $StackName; Environment = $Environment; Region = $Region; OutputFile = $platformOutputsFile }
if (-not [string]::IsNullOrWhiteSpace($AwsProfile)) { $exportPlatformArguments.AwsProfile = $AwsProfile }
& (Join-Path $PSScriptRoot 'export-cloudformation-outputs.ps1') @exportPlatformArguments
& (Join-Path $PSScriptRoot 'validate-environment.ps1') -EnvironmentName $Environment -OutputsFile $platformOutputsFile -RequirePlatformOutputs

. (Join-Path $PSScriptRoot 'load-environment.ps1') -EnvironmentName $Environment -OutputsFile $platformOutputsFile -Quiet | Out-Null
$recoveryRunDirectory=Join-Path $repositoryRoot ("artifacts\recovery\$Environment\"+(Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss'))
foreach ($service in $services) {
    $servicePath = Join-Path $repositoryRoot $service
    $component=(Split-Path $servicePath -Leaf) -replace '^ms-aprendamosgye-',''
    $serverlessStackName="ms-$($env:RESOURCE_PREFIX)-$component-$($env:ENVIRONMENT)"
    $manifestFile=Join-Path $recoveryRunDirectory "$component-before.json"
    & (Join-Path $PSScriptRoot 'capture-service-recovery-manifest.ps1') -StackName $serverlessStackName -ServicePath $servicePath -OutputFile $manifestFile -Region $Region
    Write-Host "Desplegando $service..." -ForegroundColor Cyan
    try {
        Invoke-CheckedCommand -Executable 'npx' -Arguments @('serverless', 'deploy', '--stage', $env:ENVIRONMENT, '--region', $Region) -WorkingDirectory $servicePath -FailureMessage "Falló el despliegue de $service."
    } catch {
        $instructionsFile=Join-Path $recoveryRunDirectory "$component-RECOVERY.md"
        & (Join-Path $PSScriptRoot 'write-service-recovery-instructions.ps1') -ServiceName $service -ServicePath $servicePath -StackName $serverlessStackName -ManifestFile $manifestFile -OutputFile $instructionsFile
        throw
    }
}

$exportServicesArguments = @{ Region = $Region; ResourcePrefix = $env:RESOURCE_PREFIX; Environment = $env:ENVIRONMENT; OutputFile = $serviceOutputsFile }
if (-not [string]::IsNullOrWhiteSpace($AwsProfile)) { $exportServicesArguments.AwsProfile = $AwsProfile }
& (Join-Path $PSScriptRoot 'export-serverless-outputs.ps1') @exportServicesArguments
& (Join-Path $PSScriptRoot 'validate-environment.ps1') -EnvironmentName $Environment -OutputsFile $platformOutputsFile -ServiceOutputsFile $serviceOutputsFile -RequirePlatformOutputs -RequireServiceOutputs
& (Join-Path $PSScriptRoot 'export-amplify-environments.ps1') -Environment $Environment -PlatformOutputsFile $platformOutputsFile -ServiceOutputsFile $serviceOutputsFile -ClientOutputFile (Join-Path $repositoryRoot "config\amplify-client-$Environment-env.json") -AdminOutputFile (Join-Path $repositoryRoot "config\amplify-admin-$Environment-env.json")

$configureAmplifyArguments = @{ Environment=$Environment; Execute=$true; StackName=$AmplifyStackName; Region=$Region; ClientEnvironmentFile=(Join-Path $repositoryRoot "config\amplify-client-$Environment-env.json"); AdminEnvironmentFile=(Join-Path $repositoryRoot "config\amplify-admin-$Environment-env.json") }
if (-not [string]::IsNullOrWhiteSpace($AwsProfile)) { $configureAmplifyArguments.AwsProfile=$AwsProfile }
& (Join-Path $PSScriptRoot 'configure-amplify-branches.ps1') @configureAmplifyArguments

Write-Host 'Despliegue de infraestructura y microservicios completado.' -ForegroundColor Green
Write-Host 'Las ramas Amplify recibieron sus variables públicas, pero los builds permanecen desactivados.'
Write-Host 'Active el primer build únicamente después de revisar los mapas generados y aprobar el despliegue.'
