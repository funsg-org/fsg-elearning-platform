[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ExpectedAccountId,
    [Parameter(Mandatory = $true)][string]$ExpectedDeploymentRoleArn,
    [string]$AwsProfile,
    [ValidateSet('qa','production')][string]$Environment,
    [string]$SourceBranch,
    [string]$Region = 'us-east-1',
    [string]$ParametersFile,
    [string]$AmplifyParametersFile,
    [switch]$SkipRemoteChecks
)
$ErrorActionPreference = 'Stop'
$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not $Environment) { $Environment = & (Join-Path $PSScriptRoot 'get-deployment-environment.ps1') }
& (Join-Path $PSScriptRoot 'sync-deployment-parameters.ps1')
if (-not $SourceBranch) { $SourceBranch = if ($Environment -eq 'qa') { 'feature/epico-deployment-readiness' } else { 'main' } }
if (-not $ParametersFile) { $ParametersFile = Join-Path $repositoryRoot 'infrastructure\parameters.json' }
if (-not $AmplifyParametersFile) { $AmplifyParametersFile = Join-Path $repositoryRoot 'infrastructure\amplify-parameters.json' }
$expectedBranch = $SourceBranch
$repositories = @(
    '.',
    'frontends\aprendamosgye_react',
    'frontends\ms-aprendamosgye-admin-web',
    'services\ms-aprendamosgye-auth',
    'services\ms-aprendamosgye-course',
    'services\ms-aprendamosgye-menu',
    'services\ms-aprendamosgye-metrics',
    'services\ms-aprendamosgye-subscriptions',
    'services\ms-aprendamosgye-users',
    'services\ms-aprendamosgye-videos'
)
$services = $repositories | Where-Object { $_ -like 'services\*' }
$checks = [System.Collections.Generic.List[string]]::new()
. (Join-Path $PSScriptRoot 'load-environment.ps1') -EnvironmentName $Environment -Quiet | Out-Null
function Add-Check([string]$Message) { $checks.Add($Message) }
function Assert-Command([string]$Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) { throw "No se encontro la herramienta '$Name' en PATH." }
    Add-Check "Herramienta disponible: $Name"
}
function Read-Parameters([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Falta el archivo de parametros: $Path" }
    $result = @{}
    foreach ($item in (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json)) {
        if (-not $item.ParameterKey -or $null -eq $item.ParameterValue) { throw "Parametro invalido en $Path." }
        if ($result.ContainsKey($item.ParameterKey)) { throw "Parametro duplicado '$($item.ParameterKey)' en $Path." }
        $result[$item.ParameterKey] = [string]$item.ParameterValue
    }
    return $result
}

if ($Region -ne 'us-east-1') { throw 'La region obligatoria es us-east-1.' }
if ($ExpectedAccountId -notmatch '^\d{12}$') { throw 'ExpectedAccountId debe contener 12 digitos.' }
$requiredRoleArn = "arn:aws:iam::$ExpectedAccountId`:role/epico-deployment-$Environment"
if ($ExpectedDeploymentRoleArn -ne $requiredRoleArn) { throw "Para el ambiente '$Environment', ExpectedDeploymentRoleArn debe ser '$requiredRoleArn'." }
foreach ($tool in @('git','node','npm','npx','aws')) { Assert-Command $tool }
$nodeVersionText = (& node --version).Trim().TrimStart('v')
$nodeVersion = [version]$nodeVersionText
if ($nodeVersion -lt [version]'20.19.0') { throw "Node.js $nodeVersion no cumple el minimo 20.19.0 requerido por los frontends." }
Add-Check "Node.js compatible: $nodeVersion"
$previousErrorPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$serverlessText = (& npx serverless --version 2>&1 | Out-String)
$serverlessExitCode = $LASTEXITCODE
$ErrorActionPreference = $previousErrorPreference
if ($serverlessExitCode -ne 0 -or $serverlessText -notmatch 'Framework\s+(?<major>\d+)\.') { throw 'No se pudo resolver una version utilizable de Serverless Framework.' }
Add-Check "Serverless Framework disponible: major $($Matches.major)"

foreach ($relative in $repositories) {
    $path = [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot $relative))
    if (-not (Test-Path -LiteralPath (Join-Path $path '.git'))) { throw "No es un repositorio o submodulo inicializado: $relative" }
    $branch = (& git -C $path branch --show-current).Trim()
    if ($branch -ne $expectedBranch) { throw "$relative esta en '$branch'; se esperaba '$expectedBranch'." }
    if (& git -C $path status --porcelain --untracked-files=no) { throw "$relative tiene cambios rastreados sin confirmar." }
    $remote = (& git -C $path remote get-url origin).Trim()
    if ($remote -notmatch '^https://github\.com/funsg-org/') { throw "Remote origin inesperado en ${relative}: $remote" }
    if (-not $SkipRemoteChecks) {
        & git -C $path ls-remote --exit-code origin HEAD | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "No hay acceso de lectura al remote de $relative." }
    }
}
Add-Check "Rama, limpieza y remotes verificados: $($repositories.Count) repositorios"
$submoduleStatus = & git -C $repositoryRoot submodule status
if ($submoduleStatus | Where-Object { $_ -match '^[-+U]' }) { throw 'Hay submodulos no inicializados, divergentes o en conflicto.' }
foreach ($service in $services) {
    foreach ($requiredFile in @('package.json','package-lock.json','serverless.yml')) {
        if (-not (Test-Path -LiteralPath (Join-Path $repositoryRoot "$service\$requiredFile") -PathType Leaf)) { throw "Falta $requiredFile en $service." }
    }
    $serverlessConfiguration = Get-Content -LiteralPath (Join-Path $repositoryRoot "$service\serverless.yml") -Raw
    if ($serverlessConfiguration -notmatch '(?m)^frameworkVersion:\s*[''"]4[''"]\s*$') { throw "$service debe declarar frameworkVersion '4'." }
    $package=Get-Content -LiteralPath (Join-Path $repositoryRoot "$service\package.json") -Raw|ConvertFrom-Json
    if ($package.devDependencies.serverless -ne '4.39.0') { throw "$service debe fijar serverless 4.39.0 como devDependency raiz." }
    if ($package.devDependencies.'serverless-plugin-typescript') { throw "$service conserva serverless-plugin-typescript, incompatible y no utilizado." }
}
Add-Check "Serverless 4.39.0 reproducible y contratos ~4.39.0 verificados en los siete microservicios"
$serverlessDataText=($services|ForEach-Object { Get-Content -LiteralPath (Join-Path $repositoryRoot "$_\serverless.yml") -Raw }) -join [Environment]::NewLine
$tableCount=([regex]::Matches($serverlessDataText,'Type:\s*AWS::DynamoDB::Table')).Count
$retainCount=([regex]::Matches($serverlessDataText,'DeletionPolicy:\s*Retain')).Count
$replaceRetainCount=([regex]::Matches($serverlessDataText,'UpdateReplacePolicy:\s*Retain')).Count
$pitrCount=([regex]::Matches($serverlessDataText,'PointInTimeRecoveryEnabled:\s*true')).Count
if ($tableCount -ne 10 -or $retainCount -lt 10 -or $replaceRetainCount -lt 10 -or $pitrCount -ne 10) { throw "Proteccion DynamoDB incompleta: tables=$tableCount deletion=$retainCount replacement=$replaceRetainCount pitr=$pitrCount." }
Add-Check 'Retencion y PITR verificadas en las diez tablas DynamoDB'
foreach ($frontend in @('frontends\aprendamosgye_react','frontends\ms-aprendamosgye-admin-web\Aprendamos_Admin')) {
    foreach ($requiredFile in @('package.json','package-lock.json')) {
        if (-not (Test-Path -LiteralPath (Join-Path $repositoryRoot "$frontend\$requiredFile") -PathType Leaf)) { throw "Falta $requiredFile en $frontend." }
    }
}
Add-Check 'Manifiestos y lockfiles presentes en los dos frontends'

$platform = Read-Parameters $ParametersFile
$amplify = Read-Parameters $AmplifyParametersFile
foreach ($key in @('ResourcePrefix','ResourceSuffix','SolutionTag','ProjectTag','ClientTag','OwnerTag','ManagedByTag','CostCenterTag')) {
    if (-not $platform.ContainsKey($key) -or -not $amplify.ContainsKey($key)) { throw "Falta '$key' en uno de los archivos de parametros." }
    if ($platform[$key] -ne $amplify[$key]) { throw "'$key' no coincide entre infraestructura y Amplify." }
}
if ($platform.CostCenterTag -eq 'PENDING') { throw 'CostCenterTag continua en PENDING.' }
if ($platform.ResourcePrefix -ne 'epico' -or $platform.ResourceSuffix -ne $Environment) { throw "El destino esperado debe usar epico/$Environment." }
if ($platform.Environment -ne $Environment) { throw "El archivo de plataforma no corresponde a $Environment." }
if ($platform.Environment -ne $amplify.EnvironmentTag) { throw 'Environment y EnvironmentTag no coinciden entre ambos stacks.' }
if ($amplify.DeploymentBranch -ne $expectedBranch) { throw 'DeploymentBranch no coincide con la rama de preparacion.' }
$expectedDomainPrefix = $expectedBranch -replace '[^a-z0-9-]','-'
if ($amplify.DeploymentBranchDomainPrefix -ne $expectedDomainPrefix) { throw "DeploymentBranchDomainPrefix debe ser '$expectedDomainPrefix'." }
if (-not $amplify.GitHubAccessTokenSecretId) { throw 'Falta GitHubAccessTokenSecretId.' }
if ($amplify.GitHubAccessTokenSecretId -notmatch "^epico/$Environment/") { throw 'El secreto GitHub pertenece a otro ambiente.' }
if ($env:SERVERLESS_ACCESS_KEY_SECRET_ID -notmatch "^epico/$Environment/") { throw 'El secreto Serverless pertenece a otro ambiente.' }
Add-Check 'Parametros, tags, prefijo, sufijo y rama consistentes'

$awsBase = @('--region',$Region)
if ($AwsProfile) { $awsBase += @('--profile',$AwsProfile) }
$identityRaw = & aws sts get-caller-identity --output json @awsBase
if ($LASTEXITCODE -ne 0) { throw 'No se pudo consultar la identidad AWS.' }
$identity = ($identityRaw -join [Environment]::NewLine) | ConvertFrom-Json
if ($identity.Account -ne $ExpectedAccountId) { throw "Cuenta AWS activa $($identity.Account); se esperaba $ExpectedAccountId." }
$expectedRoleName = ($ExpectedDeploymentRoleArn -split '/')[-1]
if ($identity.Arn -notmatch "^arn:aws:sts::$ExpectedAccountId`:assumed-role/$([regex]::Escape($expectedRoleName))/") { throw "La identidad activa no es una sesión del rol '$ExpectedDeploymentRoleArn'." }
Add-Check "Cuenta AWS verificada: $($identity.Account)"
Add-Check "Sesion STS del rol de despliegue verificada: $expectedRoleName"
& (Join-Path $PSScriptRoot 'import-serverless-access-key.ps1') -SecretId $env:SERVERLESS_ACCESS_KEY_SECRET_ID -AwsProfile $AwsProfile -Region $Region
if (-not $env:SERVERLESS_ACCESS_KEY) { throw 'SERVERLESS_ACCESS_KEY no quedo disponible en memoria.' }
Add-Check 'SERVERLESS_ACCESS_KEY cargada desde Secrets Manager (valor no mostrado)'
& aws secretsmanager describe-secret --secret-id $amplify.GitHubAccessTokenSecretId @awsBase | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'El secreto GitHub de Amplify no existe o no es accesible.' }
Add-Check 'Secreto GitHub de Amplify accesible (valor no consultado)'

& (Join-Path $PSScriptRoot 'validate-amplify-infrastructure.ps1') -Region $Region -AwsProfile $AwsProfile
& (Join-Path $PSScriptRoot 'validate-infrastructure.ps1') -Region $Region -AwsProfile $AwsProfile
Write-Host ''
foreach ($check in $checks) { Write-Host "[OK] $check" -ForegroundColor Green }
Write-Host 'PREFLIGHT APROBADO: no se modifico ningun recurso AWS.' -ForegroundColor Green
