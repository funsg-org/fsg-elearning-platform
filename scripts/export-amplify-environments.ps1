[CmdletBinding()]
param(
    [ValidateSet('qa','production')][string]$Environment,
    [string]$ClientOutputFile,
    [string]$AdminOutputFile,
    [string]$PlatformOutputsFile,
    [string]$ServiceOutputsFile
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not $Environment) { $Environment = & (Join-Path $PSScriptRoot 'get-deployment-environment.ps1') }
if ([string]::IsNullOrWhiteSpace($ClientOutputFile)) {
    $ClientOutputFile = Join-Path $repositoryRoot "config\amplify-client-$Environment-env.json"
}
if ([string]::IsNullOrWhiteSpace($AdminOutputFile)) {
    $AdminOutputFile = Join-Path $repositoryRoot "config\amplify-admin-$Environment-env.json"
}

$validationArguments = @{
    EnvironmentName = $Environment
    RequirePlatformOutputs = $true
    RequireServiceOutputs = $true
}
if (-not [string]::IsNullOrWhiteSpace($PlatformOutputsFile)) {
    $validationArguments.OutputsFile = $PlatformOutputsFile
}
if (-not [string]::IsNullOrWhiteSpace($ServiceOutputsFile)) {
    $validationArguments.ServiceOutputsFile = $ServiceOutputsFile
}
& (Join-Path $PSScriptRoot 'validate-environment.ps1') @validationArguments

$common = [ordered]@{
    VITE_AUTH_API_URL          = $env:AUTH_API_URL
    VITE_COURSE_API_URL        = $env:COURSE_API_URL
    VITE_MENU_API_URL          = $env:MENU_API_URL
    VITE_METRICS_API_URL       = $env:METRICS_API_URL
    VITE_SUBSCRIPTIONS_API_URL = $env:SUBSCRIPTIONS_API_URL
    VITE_USERS_API_URL         = $env:USERS_API_URL
    VITE_VIDEOS_API_URL        = $env:VIDEOS_API_URL
    VITE_MEDIA_CDN_URL         = $env:MEDIA_CDN_URL
}
$client = [ordered]@{ VITE_BASE_PATH = '/' }
foreach ($entry in $common.GetEnumerator()) { $client[$entry.Key] = $entry.Value }
$admin = [ordered]@{}
foreach ($entry in $common.GetEnumerator()) { $admin[$entry.Key] = $entry.Value }
$admin['VITE_COGNITO_USER_POOL_ID'] = $env:COGNITO_USER_POOL_ID
$admin['VITE_COGNITO_CLIENT_ID'] = $env:COGNITO_CLIENT_ID
$admin['VITE_COGNITO_ADMINISTRATORS_GROUP'] = $env:COGNITO_ADMINISTRATORS_GROUP

[System.IO.File]::WriteAllText([System.IO.Path]::GetFullPath($ClientOutputFile), ($client | ConvertTo-Json), [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::WriteAllText([System.IO.Path]::GetFullPath($AdminOutputFile), ($admin | ConvertTo-Json), [System.Text.UTF8Encoding]::new($false))
Write-Host 'Mapas locales para Amplify generados. No contienen secretos.' -ForegroundColor Green
