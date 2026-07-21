[CmdletBinding()]
param(
    [string]$TemplateFile,
    [string]$Region = 'us-east-1',
    [string]$AwsProfile
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($TemplateFile)) {
    $TemplateFile = Join-Path $repositoryRoot 'infrastructure\shared-resources.yml'
}
$TemplateFile = [System.IO.Path]::GetFullPath($TemplateFile)
if (-not (Test-Path -LiteralPath $TemplateFile -PathType Leaf)) {
    throw "No se encontró la plantilla: $TemplateFile"
}

$requiredOutputs = @(
    'AwsAccountId',
    'CognitoUserPoolId',
    'CognitoClientId',
    'CognitoAuthClientId',
    'CognitoClientSecretId',
    'MediaBucketName',
    'MediaCdnUrl',
    'MediaCloudFrontDistributionId'
)
$templateText = Get-Content -LiteralPath $TemplateFile -Raw
foreach ($output in $requiredOutputs) {
    if ($templateText -notmatch "(?m)^  $([regex]::Escape($output)):\s*$") {
        throw "La plantilla no define el Output obligatorio '$output'."
    }
}
if ($templateText -match '(?im)(AKIA[0-9A-Z]{16}|AWS_SECRET_ACCESS_KEY\s*:|^\s+ClientSecret\s*:\s*[^!])') {
    throw 'La plantilla contiene un patrón de credencial o Client Secret no permitido.'
}
if ($templateText -match '(?ms)^  MediaCorsAllowedOrigins:\s*.*?^    Default:\s*[''"]?\*[''"]?\s*$') {
    throw 'MediaCorsAllowedOrigins no puede tener un comodín como valor predeterminado.'
}

$arguments = @(
    'cloudformation', 'validate-template',
    '--template-body', "file://$TemplateFile",
    '--region', $Region
)
if (-not [string]::IsNullOrWhiteSpace($AwsProfile)) {
    $arguments += @('--profile', $AwsProfile)
}

& aws @arguments | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw 'AWS CloudFormation rechazó la plantilla.'
}

Write-Host 'Plantilla CloudFormation válida.' -ForegroundColor Green
Write-Host "Archivo: $TemplateFile"
Write-Host "Región de validación: $Region"
