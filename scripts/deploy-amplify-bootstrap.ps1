[CmdletBinding()]
param(
    [switch]$Execute,
    [string]$AwsProfile,
    [string]$ExpectedAccountId,
    [string]$Region = 'us-east-1',
    [string]$StackName = 'epico-amplify-production',
    [string]$ParametersFile,
    [string]$OutputFile
)
$ErrorActionPreference = 'Stop'
$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$templateFile = Join-Path $repositoryRoot 'infrastructure\amplify-hosting.yml'
if (-not $ParametersFile) { $ParametersFile = Join-Path $repositoryRoot 'infrastructure\amplify-parameters.json' }
if ($Region -ne 'us-east-1') { throw 'Amplify debe prepararse en us-east-1.' }
if ((& git -C $repositoryRoot branch --show-current).Trim() -ne 'feature/epico-deployment-readiness') { throw 'Use la rama feature/epico-deployment-readiness.' }
& (Join-Path $PSScriptRoot 'validate-amplify-infrastructure.ps1') -TemplateFile $templateFile -Region $Region -AwsProfile $AwsProfile

Write-Host "Modo: $(if ($Execute) { 'EJECUCION' } else { 'VISTA PREVIA' })"
Write-Host "Stack: $StackName | Region: $Region"
if (-not $Execute) {
    Write-Host '1. Verificar cuenta AWS, secreto GitHub y parametros definitivos.'
    Write-Host '2. Crear las dos aplicaciones y ramas Amplify con auto-build desactivado.'
    Write-Host '3. Exportar App IDs, ramas y URLs a config/amplify-outputs.env.'
    Write-Warning 'No se creo ni modifico ningun recurso AWS.'
    exit 0
}

if (-not (Test-Path -LiteralPath $ParametersFile -PathType Leaf)) { throw 'Copie amplify-parameters.example.json como amplify-parameters.json y complete sus valores.' }
if ($ExpectedAccountId -notmatch '^\d{12}$') { throw 'Indique -ExpectedAccountId con los 12 digitos de la cuenta destino.' }
$parameters = Get-Content -LiteralPath $ParametersFile -Raw | ConvertFrom-Json
$values = @{}
$overrides = [System.Collections.Generic.List[string]]::new()
foreach ($parameter in $parameters) {
    if ($values.ContainsKey($parameter.ParameterKey)) { throw "Parametro duplicado: $($parameter.ParameterKey)." }
    $values[$parameter.ParameterKey] = [string]$parameter.ParameterValue
    $overrides.Add("$($parameter.ParameterKey)=$($parameter.ParameterValue)")
}
foreach ($required in @('CostCenterTag','GitHubAccessTokenSecretId','DeploymentBranch','DeploymentBranchDomainPrefix')) {
    if (-not $values.ContainsKey($required) -or [string]::IsNullOrWhiteSpace($values[$required])) { throw "Falta el parametro '$required'." }
}
if ($values.CostCenterTag -eq 'PENDING') { throw 'CostCenterTag continua en PENDING.' }
$expectedDomainPrefix = $values.DeploymentBranch.ToLowerInvariant() -replace '[^a-z0-9-]','-'
if ($values.DeploymentBranchDomainPrefix -ne $expectedDomainPrefix) { throw "DeploymentBranchDomainPrefix debe ser '$expectedDomainPrefix'." }

$awsBase = @('--region',$Region)
if ($AwsProfile) { $awsBase += @('--profile',$AwsProfile) }
$identityRaw = & aws sts get-caller-identity --output json @awsBase
if ($LASTEXITCODE -ne 0) { throw 'No se pudo verificar la identidad AWS.' }
$identity = ($identityRaw -join [Environment]::NewLine) | ConvertFrom-Json
if ($identity.Account -ne $ExpectedAccountId) { throw "Cuenta activa $($identity.Account); se esperaba $ExpectedAccountId." }
& aws secretsmanager describe-secret --secret-id $values.GitHubAccessTokenSecretId @awsBase | Out-Null
if ($LASTEXITCODE -ne 0) { throw "No existe o no es accesible el secreto '$($values.GitHubAccessTokenSecretId)'." }

$deployArguments = @(
    'cloudformation','deploy','--template-file',$templateFile,'--stack-name',$StackName,
    '--region',$Region,'--no-fail-on-empty-changeset','--parameter-overrides'
) + $overrides.ToArray()
if ($AwsProfile) { $deployArguments += @('--profile',$AwsProfile) }
& aws @deployArguments
if ($LASTEXITCODE -ne 0) { throw 'Fallo el bootstrap de Amplify.' }
$exportArguments = @{ StackName=$StackName; Region=$Region }
if ($AwsProfile) { $exportArguments.AwsProfile=$AwsProfile }
if ($OutputFile) { $exportArguments.OutputFile=$OutputFile }
& (Join-Path $PSScriptRoot 'export-amplify-outputs.ps1') @exportArguments
Write-Host 'Bootstrap completado. Los builds permanecen desactivados.' -ForegroundColor Green
