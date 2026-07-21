[CmdletBinding()]
param([string]$SecretId, [string]$AwsProfile, [string]$Region = 'us-east-1')
$ErrorActionPreference = 'Stop'
if (-not $SecretId) { $SecretId = $env:SERVERLESS_ACCESS_KEY_SECRET_ID }
if (-not $SecretId) { throw 'Falta SERVERLESS_ACCESS_KEY_SECRET_ID.' }
if ($Region -ne 'us-east-1') { throw 'La clave Serverless debe consultarse en us-east-1.' }
$arguments = @('secretsmanager','get-secret-value','--secret-id',$SecretId,'--query','SecretString','--output','text','--region',$Region)
if ($AwsProfile) { $arguments += @('--profile',$AwsProfile) }
$secretText = & aws @arguments
if ($LASTEXITCODE -ne 0) { throw "No se pudo consultar el secreto operativo '$SecretId'." }
try { $payload = ($secretText -join [Environment]::NewLine) | ConvertFrom-Json } catch { throw "El secreto '$SecretId' no contiene JSON valido." }
if (-not $payload.accessKey -or [string]::IsNullOrWhiteSpace([string]$payload.accessKey)) { throw "El secreto '$SecretId' debe contener la clave JSON 'accessKey'." }
$env:SERVERLESS_ACCESS_KEY = [string]$payload.accessKey
$secretText = $null
$payload = $null
Write-Host 'Credencial operativa de Serverless cargada en memoria; su valor no fue mostrado.' -ForegroundColor Green
