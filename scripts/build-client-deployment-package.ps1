[CmdletBinding()]
param([string]$OutputDirectory)

$ErrorActionPreference = 'Stop'
$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $repositoryRoot 'artifacts\client-deployment-kit' }
$resolvedOutput = [System.IO.Path]::GetFullPath($OutputDirectory)
$allowedRoot = [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot 'artifacts'))
if (-not $resolvedOutput.StartsWith($allowedRoot + [System.IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'El paquete solo puede generarse dentro de artifacts/.'
}

$files = @(
    'infrastructure/deployment-role.yml',
    'infrastructure/shared-resources.yml',
    'infrastructure/deployment-role-parameters.example.json',
    'infrastructure/parameters.example.json',
    'infrastructure/deployment-role-parameters.qa.example.json',
    'infrastructure/deployment-role-parameters.production.example.json',
    'infrastructure/parameters.qa.example.json',
    'infrastructure/parameters.production.example.json',
    'scripts/deploy-deployment-role.ps1',
    'scripts/validate-deployment-role.ps1',
    'scripts/validate-infrastructure.ps1',
    'scripts/invoke-cloudformation-change-set.ps1',
    'config/client-installation-manual.md',
    'config/multi-environment.md',
    'config/client-deployment-handover.md'
)

if (Test-Path -LiteralPath $resolvedOutput) { Remove-Item -LiteralPath $resolvedOutput -Recurse -Force }
New-Item -ItemType Directory -Path $resolvedOutput | Out-Null
foreach ($relative in $files) {
    $source = Join-Path $repositoryRoot $relative
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Falta el archivo permitido: $relative" }
    $destination = Join-Path $resolvedOutput $relative
    New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination
}

$forbidden = Get-ChildItem -LiteralPath $resolvedOutput -Recurse -File | Where-Object {
    $_.FullName -match '[\\/](services|frontends|\.git)[\\/]' -or
    $_.Name -match '^(\.env|parameters\.json|amplify-parameters\.json|deployment-role-parameters\.json)$'
}
if ($forbidden) { throw "El paquete contiene archivos prohibidos: $($forbidden.FullName -join ', ')" }

$hashLines = Get-ChildItem -LiteralPath $resolvedOutput -Recurse -File |
    Sort-Object FullName |
    ForEach-Object {
        $relative = $_.FullName.Substring($resolvedOutput.Length).TrimStart('\','/').Replace('\','/')
        $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        "$hash  $relative"
    }
[System.IO.File]::WriteAllLines((Join-Path $resolvedOutput 'SHA256SUMS.txt'), $hashLines, [Text.UTF8Encoding]::new($false))
Write-Host "Paquete de despliegue del cliente generado: $resolvedOutput" -ForegroundColor Green
Write-Host 'No contiene codigo de microservicios/frontends, Git ni parametros reales.'
