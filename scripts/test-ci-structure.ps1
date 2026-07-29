[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$deploymentBranches = @('develop','qa','production')
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
    'scripts/import-menu-migration.ps1'
    'migrations/menu/menu-migration.csv'
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
$configureAmplifyScript = Get-Content -LiteralPath (Join-Path $repositoryRoot 'scripts/configure-amplify-branches.ps1') -Raw
if ($configureAmplifyScript -notmatch 'DEPLOYMENT_BRANCH' -or $configureAmplifyScript -match "feature/epico-deployment-readiness") {
    throw 'La configuración Amplify debe validar DEPLOYMENT_BRANCH sin una rama fija de cliente.'
}
$amplifyTemplate = Get-Content -LiteralPath (Join-Path $repositoryRoot 'infrastructure/amplify-hosting.yml') -Raw
$spaRuleCount = ([regex]::Matches($amplifyTemplate,'(?ms)CustomRules:\s*-\s*Source:.*?Target:\s*/index\.html\s*Status:\s*''200''')).Count
if ($spaRuleCount -ne 2) { throw "Amplify debe declarar una reescritura SPA a /index.html en las dos aplicaciones; encontradas=$spaRuleCount." }
$administratorScript = Get-Content -LiteralPath (Join-Path $repositoryRoot 'scripts/create-initial-cognito-administrator.ps1') -Raw
if ($administratorScript -notmatch 'UserNotFoundException' -or $administratorScript -notmatch 'assumed-role') {
    throw 'El alta inicial Cognito debe manejar usuario inexistente y exigir el rol de despliegue.'
}

$menuMigrationScript = Get-Content -LiteralPath (Join-Path $repositoryRoot 'scripts/import-menu-migration.ps1') -Raw
foreach ($requiredMigrationControl in @('attribute_not_exists\(idMenu\)','ReplaceExisting','CoursesTableName','ExpectedAccountId')) {
    if ($menuMigrationScript -notmatch $requiredMigrationControl) { throw "La migracion de menu no contiene el control '$requiredMigrationControl'." }
}
$menuRows = @([IO.File]::ReadAllText((Join-Path $repositoryRoot 'migrations/menu/menu-migration.csv'),[Text.UTF8Encoding]::new($false,$true)) | ConvertFrom-Csv)
$menuColumns = @($menuRows[0].PSObject.Properties.Name)
$expectedMenuColumns = @('idMenu','createdAt','createdBy','description','icon','idCurso','idPadre','name','nombreCurso','nombrePadre','order','state','updatedAt','updatedBy','url')
if (-not $menuRows.Count -or @($expectedMenuColumns | Where-Object { $_ -notin $menuColumns }).Count) { throw 'El CSV de menu esta vacio o no cumple el contrato de 15 columnas.' }
if (@($menuRows.idMenu | Sort-Object -Unique).Count -ne $menuRows.Count) { throw 'El CSV de menu contiene IDs duplicados.' }

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
foreach ($deploymentBranch in $deploymentBranches) {
    if ($workflowText -notmatch "(?m)^\s+- $([regex]::Escape($deploymentBranch))\s*$") { throw "El workflow no cubre la rama '$deploymentBranch'." }
}
if ($workflowText -notmatch 'infrastructure/deployment-role\.yml') { throw 'El workflow no valida la plantilla del rol de despliegue.' }
if ($workflowText -match '(?im)aws-access-key-id|aws-secret-access-key|role-to-assume|cloudformation deploy|serverless deploy') { throw 'El workflow estructural no puede contener credenciales ni comandos de despliegue.' }
Write-Host "Estructura CI valida: $($trackedScripts.Count) scripts, 10 submodulos y un selector .env." -ForegroundColor Green
