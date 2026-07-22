[CmdletBinding()]
param([string]$EnvironmentFile)
$ErrorActionPreference = 'Stop'
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$loadArguments = @{ Quiet = $true }
if ($EnvironmentFile) { $loadArguments.EnvironmentFile = $EnvironmentFile }
. (Join-Path $PSScriptRoot 'load-environment.ps1') @loadArguments | Out-Null

function Write-Contract([string]$Example,[string]$Output,[hashtable]$Overrides) {
    $items = Get-Content -LiteralPath (Join-Path $repositoryRoot $Example) -Raw | ConvertFrom-Json
    foreach ($item in $items) {
        if ($Overrides.ContainsKey($item.ParameterKey)) { $item.ParameterValue = $Overrides[$item.ParameterKey] }
    }
    [IO.File]::WriteAllText((Join-Path $repositoryRoot $Output),($items | ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
}

$common = @{
    ResourcePrefix=$env:RESOURCE_PREFIX; ResourceSuffix=$env:ENVIRONMENT; Environment=$env:ENVIRONMENT
    ClientTag=$env:TAG_CLIENT; CostCenterTag=$env:TAG_COST_CENTER
    MediaCorsAllowedOrigins=$env:MEDIA_CORS_ALLOWED_ORIGINS
}
Write-Contract 'infrastructure\parameters.example.json' 'infrastructure\parameters.json' $common

$branch = if ($env:ENVIRONMENT -eq 'qa') { 'qa' } else { 'main' }
$amplify = $common.Clone()
$amplify.EnvironmentTag = $env:ENVIRONMENT
$amplify.DeploymentBranch = $branch
$amplify.DeploymentBranchDomainPrefix = $branch -replace '[^a-z0-9-]','-'
$amplify.GitHubAccessTokenSecretId = $env:GITHUB_AMPLIFY_SECRET_ID
Write-Contract 'infrastructure\amplify-parameters.example.json' 'infrastructure\amplify-parameters.json' $amplify

$role = $common.Clone()
$role.TrustedPrincipalArn = $env:TRUSTED_PRINCIPAL_ARN
Write-Contract 'infrastructure\deployment-role-parameters.example.json' 'infrastructure\deployment-role-parameters.json' $role
Write-Host "Parámetros locales sincronizados desde .env para $($env:ENVIRONMENT)." -ForegroundColor Green
