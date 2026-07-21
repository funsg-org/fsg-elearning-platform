[CmdletBinding()]
param(
    [ValidateSet('qa','production')][string]$EnvironmentName = 'production',
    [string]$EnvironmentFile,
    [string]$OutputsFile,
    [string]$ServiceOutputsFile,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($EnvironmentFile)) {
    $EnvironmentFile = Join-Path $repositoryRoot ".env.$EnvironmentName"
}
if ([string]::IsNullOrWhiteSpace($OutputsFile)) {
    $OutputsFile = Join-Path $repositoryRoot "config\platform-outputs.$EnvironmentName.env"
}
if ([string]::IsNullOrWhiteSpace($ServiceOutputsFile)) {
    $ServiceOutputsFile = Join-Path $repositoryRoot "config\service-outputs.$EnvironmentName.env"
}

function Import-EnvironmentFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [hashtable]$LoadedValues,
        [switch]$Optional
    )

    $resolvedPath = [System.IO.Path]::GetFullPath($Path)
    if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
        if ($Optional) {
            return
        }
        throw "No se encontró el archivo de configuración requerido: $resolvedPath"
    }

    $lineNumber = 0
    foreach ($rawLine in Get-Content -LiteralPath $resolvedPath) {
        $lineNumber++
        $line = $rawLine.Trim()
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) {
            continue
        }

        $separator = $line.IndexOf('=')
        if ($separator -lt 1) {
            throw "Formato inválido en ${resolvedPath}:$lineNumber. Se esperaba CLAVE=VALOR."
        }

        $key = $line.Substring(0, $separator).Trim()
        $value = $line.Substring($separator + 1).Trim()
        if ($value.Length -ge 2) {
            $quotedWithDouble = $value.StartsWith('"') -and $value.EndsWith('"')
            $quotedWithSingle = $value.StartsWith("'") -and $value.EndsWith("'")
            if ($quotedWithDouble -or $quotedWithSingle) {
                $value = $value.Substring(1, $value.Length - 2)
            }
        }

        if ($key -notmatch '^[A-Z][A-Z0-9_]*$') {
            throw "Nombre de variable inválido en ${resolvedPath}:${lineNumber}: $key"
        }

        Set-Item -Path "Env:$key" -Value $value
        $LoadedValues[$key] = $value
    }
}

$loaded = @{}
Import-EnvironmentFile -Path (Join-Path $repositoryRoot 'config\naming.env') -LoadedValues $loaded
Import-EnvironmentFile -Path (Join-Path $repositoryRoot 'config\tags.env') -LoadedValues $loaded
Import-EnvironmentFile -Path (Join-Path $repositoryRoot "config\environments\$EnvironmentName.env") -LoadedValues $loaded
Import-EnvironmentFile -Path $OutputsFile -LoadedValues $loaded -Optional
Import-EnvironmentFile -Path $ServiceOutputsFile -LoadedValues $loaded -Optional
Import-EnvironmentFile -Path $EnvironmentFile -LoadedValues $loaded -Optional
Import-EnvironmentFile -Path (Join-Path $repositoryRoot '.env') -LoadedValues $loaded -Optional

if ($env:ENVIRONMENT -ne $EnvironmentName -or $env:RESOURCE_SUFFIX -ne $EnvironmentName) {
    throw "El perfil solicitado '$EnvironmentName' no coincide con ENVIRONMENT/RESOURCE_SUFFIX."
}

if (-not $Quiet) {
    Write-Host "Configuración cargada para $($env:CLIENT_CODE)/$($env:ENVIRONMENT) en $($env:AWS_REGION)."
    Write-Host "Convención de recursos: $($env:RESOURCE_PREFIX)-<servicio>-$($env:RESOURCE_SUFFIX)"
    Write-Host "Ruta SSM base: $($env:SSM_BASE_PATH)"
}

$loaded
