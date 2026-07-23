[CmdletBinding()]
param(
    [string]$OutputFile,
    [string]$AwsProfile,
    [string]$Region = 'us-east-1',
    [string]$ResourcePrefix,
    [ValidateSet('develop','qa','production')][string]$Environment
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not $Environment) { $Environment = & (Join-Path $PSScriptRoot 'get-deployment-environment.ps1') }
. (Join-Path $PSScriptRoot 'load-environment.ps1') -EnvironmentName $Environment -Quiet | Out-Null
if (-not $ResourcePrefix) { $ResourcePrefix = $env:RESOURCE_PREFIX }
if ([string]::IsNullOrWhiteSpace($OutputFile)) {
    $OutputFile = Join-Path $repositoryRoot "config\service-outputs.$Environment.env"
}
$OutputFile = [System.IO.Path]::GetFullPath($OutputFile)

$services = [ordered]@{
    AUTH_API_URL          = 'auth'
    COURSE_API_URL        = 'course'
    MENU_API_URL          = 'menu'
    METRICS_API_URL       = 'metrics'
    SUBSCRIPTIONS_API_URL = 'subscriptions'
    USERS_API_URL         = 'users'
    VIDEOS_API_URL        = 'videos'
}

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add('# Generado desde los Outputs de los stacks Serverless. No confirmar en Git.')
foreach ($entry in $services.GetEnumerator()) {
    $stackName = "ms-$ResourcePrefix-$($entry.Value)-$Environment"
    $arguments = @(
        'cloudformation', 'describe-stacks',
        '--stack-name', $stackName,
        '--region', $Region,
        '--output', 'json'
    )
    if (-not [string]::IsNullOrWhiteSpace($AwsProfile)) {
        $arguments += @('--profile', $AwsProfile)
    }
    $json = & aws @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "No se pudo consultar el stack '$stackName'."
    }
    $response = ($json -join [Environment]::NewLine) | ConvertFrom-Json
    $outputs = @{}
    foreach ($output in $response.Stacks[0].Outputs) {
        $outputs[$output.OutputKey] = [string]$output.OutputValue
    }
    $url = $outputs['ServiceEndpoint']
    if ([string]::IsNullOrWhiteSpace($url)) {
        $url = $outputs['ApiGatewayRootUrl']
    }
    if ([string]::IsNullOrWhiteSpace($url)) {
        throw "El stack '$stackName' no publica ServiceEndpoint ni ApiGatewayRootUrl."
    }
    $lines.Add("$($entry.Key)=$($url.TrimEnd('/'))")
}

[System.IO.File]::WriteAllLines($OutputFile, $lines, [System.Text.UTF8Encoding]::new($false))
Write-Host "Contrato de servicios generado: $OutputFile" -ForegroundColor Green
