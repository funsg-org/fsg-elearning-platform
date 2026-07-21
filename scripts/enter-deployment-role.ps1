[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$RoleArn,
    [ValidateSet('qa','production')][string]$Environment,
    [string]$AwsProfile,
    [string]$Region = 'us-east-1',
    [int]$DurationSeconds = 3600
)
$ErrorActionPreference = 'Stop'
if (-not $Environment) { $Environment = & (Join-Path $PSScriptRoot 'get-deployment-environment.ps1') }
if ($RoleArn -notmatch "^arn:aws:iam::\d{12}:role/epico-deployment-$Environment$") { throw "RoleArn no corresponde al rol EPICO de $Environment." }
$arguments = @('sts','assume-role','--role-arn',$RoleArn,'--role-session-name',"epico-$Environment-deployment",'--duration-seconds',$DurationSeconds,'--region',$Region,'--output','json')
if ($AwsProfile) { $arguments += @('--profile',$AwsProfile) }
$raw = & aws @arguments
if ($LASTEXITCODE -ne 0) { throw 'No se pudo asumir el rol de despliegue.' }
$session = ($raw -join [Environment]::NewLine) | ConvertFrom-Json
if (-not $session.Credentials.AccessKeyId -or -not $session.Credentials.SecretAccessKey -or -not $session.Credentials.SessionToken) { throw 'STS no devolvio credenciales temporales completas.' }
$env:AWS_ACCESS_KEY_ID = [string]$session.Credentials.AccessKeyId
$env:AWS_SECRET_ACCESS_KEY = [string]$session.Credentials.SecretAccessKey
$env:AWS_SESSION_TOKEN = [string]$session.Credentials.SessionToken
$env:AWS_REGION = $Region
$raw = $null
$session = $null
Write-Host "Rol de despliegue asumido: $RoleArn. Credenciales temporales cargadas en memoria." -ForegroundColor Green
