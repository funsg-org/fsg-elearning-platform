[CmdletBinding()]
param(
    [switch]$Execute,
    [string]$AwsProfile,
    [string]$ExpectedAccountId,
    [string]$Region = 'us-east-1',
    [string]$StackName = 'epico-deployment-role-production',
    [string]$ParametersFile
)
$ErrorActionPreference = 'Stop'
$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$templateFile = Join-Path $repositoryRoot 'infrastructure\deployment-role.yml'
if (-not $ParametersFile) { $ParametersFile = Join-Path $repositoryRoot 'infrastructure\deployment-role-parameters.json' }
& (Join-Path $PSScriptRoot 'validate-deployment-role.ps1') -TemplateFile $templateFile -Region $Region -AwsProfile $AwsProfile
if (-not $Execute) { Write-Warning 'Vista previa: no se creo el rol. La ejecucion requiere un principal bootstrap con permisos IAM.'; exit 0 }
if ($ExpectedAccountId -notmatch '^\d{12}$') { throw 'Indique -ExpectedAccountId con 12 digitos.' }
if (-not (Test-Path -LiteralPath $ParametersFile -PathType Leaf)) { throw 'Falta deployment-role-parameters.json.' }
$parameters = Get-Content -LiteralPath $ParametersFile -Raw | ConvertFrom-Json
$overrides = [System.Collections.Generic.List[string]]::new()
$values = @{}
foreach ($item in $parameters) { $values[$item.ParameterKey]=[string]$item.ParameterValue; $overrides.Add("$($item.ParameterKey)=$($item.ParameterValue)") }
if ($values.CostCenterTag -eq 'PENDING') { throw 'CostCenterTag continua en PENDING.' }
if ($values.TrustedPrincipalArn -notmatch "^arn:aws:iam::$ExpectedAccountId`:(user|role)/") { throw 'TrustedPrincipalArn debe pertenecer a la cuenta destino.' }
$awsBase=@('--region',$Region)
if ($AwsProfile) { $awsBase+=@('--profile',$AwsProfile) }
$identityRaw=& aws sts get-caller-identity --output json @awsBase
if ($LASTEXITCODE -ne 0) { throw 'No se pudo verificar la cuenta bootstrap.' }
$identity=($identityRaw -join [Environment]::NewLine)|ConvertFrom-Json
if ($identity.Account -ne $ExpectedAccountId) { throw "Cuenta activa $($identity.Account); se esperaba $ExpectedAccountId." }
$arguments=@('cloudformation','deploy','--template-file',$templateFile,'--stack-name',$StackName,'--region',$Region,'--capabilities','CAPABILITY_NAMED_IAM','--no-fail-on-empty-changeset','--parameter-overrides')+$overrides.ToArray()
if ($AwsProfile) { $arguments+=@('--profile',$AwsProfile) }
& aws @arguments
if ($LASTEXITCODE -ne 0) { throw 'No se pudo crear o actualizar el rol de despliegue.' }
$roleArn=& aws cloudformation describe-stacks --stack-name $StackName --query "Stacks[0].Outputs[?OutputKey=='DeploymentRoleArn'].OutputValue | [0]" --output text @awsBase
if ($LASTEXITCODE -ne 0 -or -not $roleArn) { throw 'El stack no devolvio DeploymentRoleArn.' }
Write-Host "Rol listo: $roleArn" -ForegroundColor Green
