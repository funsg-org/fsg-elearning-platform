[CmdletBinding()]
param(
    [string]$EnvironmentFile
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($EnvironmentFile)) {
    $EnvironmentFile = Join-Path $repositoryRoot '.env'
}

$loadedValues = . (Join-Path $PSScriptRoot 'load-environment.ps1') -EnvironmentFile $EnvironmentFile -Quiet

$requiredVariables = @(
    'SOLUTION_NAME',
    'PROJECT_CODE',
    'CLIENT_CODE',
    'RESOURCE_PREFIX',
    'RESOURCE_SUFFIX',
    'ENVIRONMENT',
    'AWS_REGION',
    'SSM_BASE_PATH',
    'TAG_SOLUTION',
    'TAG_PROJECT',
    'TAG_CLIENT',
    'TAG_ENVIRONMENT',
    'TAG_OWNER',
    'TAG_MANAGED_BY',
    'TAG_COST_CENTER'
)

$errors = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()

foreach ($variable in $requiredVariables) {
    $value = [Environment]::GetEnvironmentVariable($variable, 'Process')
    if ([string]::IsNullOrWhiteSpace($value)) {
        $errors.Add("Falta la variable obligatoria $variable.")
    }
}

foreach ($variable in @('PROJECT_CODE', 'CLIENT_CODE', 'RESOURCE_PREFIX', 'RESOURCE_SUFFIX', 'ENVIRONMENT')) {
    $value = [Environment]::GetEnvironmentVariable($variable, 'Process')
    if ($value -and $value -notmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$') {
        $errors.Add("$variable debe usar minúsculas, números y guiones simples: '$value'.")
    }
}

if ($env:AWS_REGION -ne 'us-east-1') {
    $errors.Add("AWS_REGION debe ser us-east-1 para esta solución; valor recibido: '$($env:AWS_REGION)'.")
}

$expectedSsmPath = "/$($env:RESOURCE_PREFIX)/$($env:ENVIRONMENT)"
if ($env:SSM_BASE_PATH -ne $expectedSsmPath) {
    $errors.Add("SSM_BASE_PATH debe ser '$expectedSsmPath'; valor recibido: '$($env:SSM_BASE_PATH)'.")
}

if ($env:TAG_ENVIRONMENT.ToLowerInvariant() -ne $env:ENVIRONMENT.ToLowerInvariant()) {
    $errors.Add('TAG_ENVIRONMENT debe representar el mismo ambiente que ENVIRONMENT.')
}

if ($env:TAG_CLIENT.ToLowerInvariant() -ne $env:CLIENT_CODE.ToLowerInvariant()) {
    $errors.Add('TAG_CLIENT debe representar el mismo cliente que CLIENT_CODE.')
}

if ($env:TAG_COST_CENTER -eq 'PENDING') {
    $warnings.Add('TAG_COST_CENTER continúa en PENDING; debe definirse antes del primer despliegue con análisis de costos.')
}

$configurationFiles = @(
    (Join-Path $repositoryRoot 'config\naming.env'),
    (Join-Path $repositoryRoot 'config\tags.env'),
    ([System.IO.Path]::GetFullPath($EnvironmentFile))
)

foreach ($file in $configurationFiles) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        continue
    }
    foreach ($line in Get-Content -LiteralPath $file) {
        if ($line -match '^\s*([A-Z][A-Z0-9_]*)\s*=') {
            $key = $Matches[1]
            if ($key -match '(?i)(SECRET|PASSWORD|TOKEN|AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY)') {
                $errors.Add("La variable sensible '$key' no puede almacenarse en $file.")
            }
        }
    }
}

if ($warnings.Count -gt 0) {
    foreach ($warning in $warnings) {
        Write-Warning $warning
    }
}

if ($errors.Count -gt 0) {
    foreach ($validationError in $errors) {
        Write-Error $validationError
    }
    exit 1
}

$resourceExample = "$($env:RESOURCE_PREFIX)-videos-$($env:RESOURCE_SUFFIX)"
Write-Host 'Configuración válida.' -ForegroundColor Green
Write-Host "Cliente: $($env:CLIENT_CODE)"
Write-Host "Región: $($env:AWS_REGION)"
Write-Host "Ejemplo de recurso: $resourceExample"
Write-Host 'Tags obligatorios:'
Write-Host "  Solution=$($env:TAG_SOLUTION)"
Write-Host "  Project=$($env:TAG_PROJECT)"
Write-Host "  Client=$($env:TAG_CLIENT)"
Write-Host "  Environment=$($env:TAG_ENVIRONMENT)"
Write-Host "  Owner=$($env:TAG_OWNER)"
Write-Host "  ManagedBy=$($env:TAG_MANAGED_BY)"
Write-Host "  CostCenter=$($env:TAG_COST_CENTER)"
