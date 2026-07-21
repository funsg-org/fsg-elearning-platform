[CmdletBinding(DefaultParameterSetName = 'Aws')]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'Aws')]
    [string]$StackName,

    [Parameter(Mandatory = $true, ParameterSetName = 'Json')]
    [string]$InputJsonFile,

    [string]$OutputFile,
    [ValidateSet('qa','production')][string]$Environment,
    [string]$AwsProfile,
    [string]$Region = 'us-east-1'
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not $Environment) { $Environment = & (Join-Path $PSScriptRoot 'get-deployment-environment.ps1') }
if ([string]::IsNullOrWhiteSpace($OutputFile)) {
    $OutputFile = Join-Path $repositoryRoot "config\platform-outputs.$Environment.env"
}
$OutputFile = [System.IO.Path]::GetFullPath($OutputFile)

if ($PSCmdlet.ParameterSetName -eq 'Aws') {
    $awsArguments = @(
        'cloudformation', 'describe-stacks',
        '--stack-name', $StackName,
        '--region', $Region,
        '--output', 'json'
    )
    if (-not [string]::IsNullOrWhiteSpace($AwsProfile)) {
        $awsArguments += @('--profile', $AwsProfile)
    }

    $json = & aws @awsArguments
    if ($LASTEXITCODE -ne 0) {
        throw "AWS CLI no pudo consultar el stack '$StackName'."
    }
    $response = ($json -join [Environment]::NewLine) | ConvertFrom-Json
}
else {
    $resolvedInput = [System.IO.Path]::GetFullPath($InputJsonFile)
    if (-not (Test-Path -LiteralPath $resolvedInput -PathType Leaf)) {
        throw "No se encontró el JSON de CloudFormation: $resolvedInput"
    }
    $response = Get-Content -LiteralPath $resolvedInput -Raw | ConvertFrom-Json
}

if (-not $response.Stacks -or $response.Stacks.Count -ne 1) {
    throw 'La respuesta debe contener exactamente un stack de CloudFormation.'
}

$outputsByKey = @{}
foreach ($output in $response.Stacks[0].Outputs) {
    $outputsByKey[$output.OutputKey] = [string]$output.OutputValue
}

$contract = [ordered]@{
    AWS_ACCOUNT_ID                         = 'AwsAccountId'
    COGNITO_USER_POOL_ID                   = 'CognitoUserPoolId'
    COGNITO_CLIENT_ID                      = 'CognitoClientId'
    COGNITO_ADMINISTRATORS_GROUP           = 'CognitoAdministratorsGroupName'
    COGNITO_AUTH_CLIENT_ID                 = 'CognitoAuthClientId'
    COGNITO_CLIENT_SECRET_ID               = 'CognitoClientSecretId'
    MEDIA_BUCKET_NAME                      = 'MediaBucketName'
    MEDIA_CDN_URL                          = 'MediaCdnUrl'
    MEDIA_CLOUDFRONT_DISTRIBUTION_ID       = 'MediaCloudFrontDistributionId'
}

$missing = [System.Collections.Generic.List[string]]::new()
$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add('# Generado desde Outputs de CloudFormation. No editar ni confirmar en Git.')
foreach ($entry in $contract.GetEnumerator()) {
    $outputKey = $entry.Value
    if (-not $outputsByKey.ContainsKey($outputKey) -or [string]::IsNullOrWhiteSpace($outputsByKey[$outputKey])) {
        $missing.Add($outputKey)
        continue
    }
    $value = $outputsByKey[$outputKey]
    if ($value -match "[`r`n]") {
        throw "El Output '$outputKey' contiene saltos de línea y no puede exportarse."
    }
    $lines.Add("$($entry.Key)=$value")
}

if ($missing.Count -gt 0) {
    throw "Faltan Outputs obligatorios en CloudFormation: $($missing -join ', ')."
}

$outputDirectory = Split-Path -Parent $OutputFile
if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $outputDirectory | Out-Null
}
[System.IO.File]::WriteAllLines($OutputFile, $lines, [System.Text.UTF8Encoding]::new($false))

Write-Host "Contrato generado: $OutputFile" -ForegroundColor Green
Write-Host 'El archivo contiene identificadores y URLs, nunca el valor del Client Secret.'
