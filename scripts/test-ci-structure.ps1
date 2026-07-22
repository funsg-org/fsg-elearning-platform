[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$expectedBranch = 'feature/epico-deployment-readiness'
$requiredFiles = @(
    '.gitmodules',
    '.env.example',
    'config/naming.env',
    'config/tags.env',
    'config/multi-environment.md',
    'config/implementation-manual.md',
    'config/client-installation-manual.md',
    'config/client-aws-prerequisites-manual.md',
    'config/provider-project-deployment-manual.md',
    'config/client-deployment-handover.md',
    'infrastructure/shared-resources.yml',
    'infrastructure/amplify-hosting.yml',
    'infrastructure/deployment-role.yml',
    'infrastructure/parameters.example.json',
    'infrastructure/amplify-parameters.example.json',
    'infrastructure/deployment-role-parameters.example.json',
    'scripts/get-deployment-environment.ps1',
    'scripts/sync-deployment-parameters.ps1',
    'scripts/deploy-platform.ps1',
    'scripts/invoke-cloudformation-change-set.ps1',
    'scripts/capture-service-recovery-manifest.ps1',
    'scripts/write-service-recovery-instructions.ps1',
    'scripts/test-deployment-readiness.ps1'
    'scripts/create-initial-cognito-administrator.ps1'
    'scripts/build-client-deployment-package.ps1'
)
foreach ($relativePath in $requiredFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $repositoryRoot $relativePath) -PathType Leaf)) { throw "Falta el archivo obligatorio '$relativePath'." }
}

$parseErrors = [System.Collections.Generic.List[object]]::new()
$trackedScripts = & git -C $repositoryRoot ls-files 'scripts/*.ps1'
foreach ($relativePath in $trackedScripts) {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $repositoryRoot $relativePath),[ref]$tokens,[ref]$errors) | Out-Null
    foreach ($errorItem in $errors) { $parseErrors.Add([pscustomobject]@{ File=$relativePath; Message=$errorItem.Message }) }
}
if ($parseErrors.Count) { $parseErrors | Format-Table -AutoSize; throw 'Hay scripts PowerShell con errores sintacticos.' }

$changeSetInvoker = Get-Content -LiteralPath (Join-Path $repositoryRoot 'scripts/invoke-cloudformation-change-set.ps1') -Raw
if ($changeSetInvoker -notmatch '\$rows\s*\|\s*Format-Table\s+-AutoSize\s*\|\s*Out-Host') {
    throw 'La tabla del change set debe enviarse a Out-Host para no contaminar el valor devuelto.'
}
$deploymentRoleTemplate = Get-Content -LiteralPath (Join-Path $repositoryRoot 'infrastructure/deployment-role.yml') -Raw
foreach ($requiredCloudFormationAction in @('DescribeStackResource','DescribeStackResources','ListStackResources')) {
    if ($deploymentRoleTemplate -notmatch "cloudformation:$requiredCloudFormationAction") {
        throw "El rol de despliegue no permite cloudformation:$requiredCloudFormationAction requerido por Serverless."
    }
}

foreach ($secretScript in @('scripts/initialize-amplify-github-secret.ps1','scripts/initialize-serverless-access-key-secret.ps1')) {
    $secretScriptText = Get-Content -LiteralPath (Join-Path $repositoryRoot $secretScript) -Raw
    foreach ($requiredCliKey in @('Name','Description','SecretString','Tags')) {
        if ($secretScriptText -cnotmatch "(?m)^\s+$requiredCliKey=") { throw "$secretScript debe usar la clave AWS CLI '$requiredCliKey' respetando mayusculas." }
    }
    if ($secretScriptText -cmatch '(?m)^\s+(name|description|secretString|tags)=') { throw "$secretScript contiene claves create-secret con mayusculas incorrectas." }
}

foreach ($jsonFile in @(
    'infrastructure/parameters.example.json',
    'infrastructure/amplify-parameters.example.json',
    'infrastructure/deployment-role-parameters.example.json'
)) {
    $items = Get-Content -LiteralPath (Join-Path $repositoryRoot $jsonFile) -Raw | ConvertFrom-Json
    $keys = @($items | ForEach-Object { $_.ParameterKey })
    if (-not $items -or $keys.Count -ne (@($keys | Sort-Object -Unique)).Count) { throw "Contrato JSON vacio o con claves duplicadas: $jsonFile" }
}

$configuredPaths = @(& git -C $repositoryRoot config -f .gitmodules --get-regexp '^submodule\..*\.path$' | ForEach-Object { ($_ -split '\s+',2)[1] })
$configuredUrls = @(& git -C $repositoryRoot config -f .gitmodules --get-regexp '^submodule\..*\.url$' | ForEach-Object { ($_ -split '\s+',2)[1] })
$configuredBranches = @(& git -C $repositoryRoot config -f .gitmodules --get-regexp '^submodule\..*\.branch$' | ForEach-Object { ($_ -split '\s+',2)[1] })
$gitlinks = @(& git -C $repositoryRoot ls-files --stage | Where-Object { $_ -match '^160000\s' } | ForEach-Object { ($_ -split "`t",2)[1] })
if ($configuredPaths.Count -ne 10 -or $gitlinks.Count -ne 10) { throw 'Se esperaban exactamente diez submodulos declarados y diez gitlinks.' }
if (@(Compare-Object ($configuredPaths | Sort-Object) ($gitlinks | Sort-Object)).Count) { throw '.gitmodules y los gitlinks rastreados no coinciden.' }
if ($configuredUrls | Where-Object { $_ -notmatch '^https://github\.com/funsg-org/[A-Za-z0-9_.-]+\.git$' }) { throw 'Todos los submodulos deben apuntar por HTTPS a funsg-org.' }
if ($configuredBranches.Count -ne 10 -or ($configuredBranches | Where-Object { $_ -notin @('main','master') })) { throw 'Cada submodulo debe declarar su rama estable main o master.' }

$workflowText = Get-Content -LiteralPath (Join-Path $repositoryRoot '.github/workflows/deployment-readiness.yml') -Raw
if ($workflowText -notmatch [regex]::Escape($expectedBranch)) { throw 'El workflow no referencia la rama de preparacion.' }
if ($workflowText -notmatch 'infrastructure/deployment-role\.yml') { throw 'El workflow no valida la plantilla del rol de despliegue.' }
if ($workflowText -match '(?im)aws-access-key-id|aws-secret-access-key|role-to-assume|cloudformation deploy|serverless deploy') { throw 'El workflow estructural no puede contener credenciales ni comandos de despliegue.' }
Write-Host "Estructura CI valida: $($trackedScripts.Count) scripts, 10 submodulos y un selector .env." -ForegroundColor Green
