[CmdletBinding()]
param(
    [string]$EnvironmentName,
    [string]$EnvironmentFile,
    [string]$OutputsFile,
    [string]$ServiceOutputsFile,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not $EnvironmentFile) { $EnvironmentFile = Join-Path $repositoryRoot '.env' }

function Import-EnvironmentFile {
    param([string]$Path,[hashtable]$LoadedValues,[switch]$Optional)
    $resolvedPath = [System.IO.Path]::GetFullPath($Path)
    if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
        if ($Optional) { return }
        throw "No se encontró el archivo requerido: $resolvedPath. Copie .env.example como .env."
    }
    $lineNumber = 0
    foreach ($rawLine in Get-Content -LiteralPath $resolvedPath) {
        $lineNumber++
        $line = $rawLine.Trim()
        if (-not $line -or $line.StartsWith('#')) { continue }
        $separator = $line.IndexOf('=')
        if ($separator -lt 1) { throw "Formato inválido en ${resolvedPath}:$lineNumber; se esperaba CLAVE=VALOR." }
        $key = $line.Substring(0,$separator).Trim()
        $value = $line.Substring($separator + 1).Trim().Trim('"').Trim("'")
        if ($key -notmatch '^[A-Z][A-Z0-9_]*$') { throw "Variable inválida en ${resolvedPath}:${lineNumber}: $key" }
        Set-Item -Path "Env:$key" -Value $value
        $LoadedValues[$key] = $value
    }
}

$loaded = @{}
Import-EnvironmentFile (Join-Path $repositoryRoot 'config\naming.env') $loaded
Import-EnvironmentFile (Join-Path $repositoryRoot 'config\tags.env') $loaded
Import-EnvironmentFile $EnvironmentFile $loaded

if ($env:ENVIRONMENT -notin @('develop','qa','production')) { throw 'ENVIRONMENT en .env debe ser develop, qa o production.' }
if ($EnvironmentName -and $EnvironmentName -ne $env:ENVIRONMENT) { throw "El parámetro '$EnvironmentName' no coincide con ENVIRONMENT='$($env:ENVIRONMENT)' en .env." }
$EnvironmentName = $env:ENVIRONMENT
$deploymentBranch = if ($loaded.ContainsKey('DEPLOYMENT_BRANCH') -and -not [string]::IsNullOrWhiteSpace($loaded.DEPLOYMENT_BRANCH)) {
    [string]$loaded.DEPLOYMENT_BRANCH
} else {
    $EnvironmentName
}
if ($deploymentBranch -notmatch '^[A-Za-z0-9][A-Za-z0-9._/-]*$') { throw 'DEPLOYMENT_BRANCH contiene caracteres no permitidos para una rama Git.' }
$derived = [ordered]@{
    RESOURCE_SUFFIX = $EnvironmentName
    RUNTIME_NODE_ENV = 'production'
    DEPLOYMENT_BRANCH = $deploymentBranch
    DEPLOYMENT_BRANCH_DOMAIN_PREFIX = $deploymentBranch.ToLowerInvariant() -replace '[^a-z0-9-]','-'
    SSM_BASE_PATH = "/$($env:RESOURCE_PREFIX)/$EnvironmentName"
    SERVERLESS_ACCESS_KEY_SECRET_ID = "$($env:RESOURCE_PREFIX)/$EnvironmentName/serverless/access-key"
    GITHUB_AMPLIFY_SECRET_ID = "$($env:RESOURCE_PREFIX)/$EnvironmentName/github/amplify-token"
    TAG_ENVIRONMENT = $EnvironmentName
}
foreach ($entry in $derived.GetEnumerator()) {
    Set-Item -Path "Env:$($entry.Key)" -Value $entry.Value
    $loaded[$entry.Key] = $entry.Value
}

if (-not $OutputsFile) { $OutputsFile = Join-Path $repositoryRoot "config\platform-outputs.$EnvironmentName.env" }
if (-not $ServiceOutputsFile) { $ServiceOutputsFile = Join-Path $repositoryRoot "config\service-outputs.$EnvironmentName.env" }
Import-EnvironmentFile $OutputsFile $loaded -Optional
Import-EnvironmentFile $ServiceOutputsFile $loaded -Optional

if (-not $Quiet) {
    Write-Host "Configuración cargada para $($env:CLIENT_CODE)/$EnvironmentName en $($env:AWS_REGION)."
    Write-Host "Recursos: $($env:RESOURCE_PREFIX)-<servicio>-$EnvironmentName"
}
$loaded
