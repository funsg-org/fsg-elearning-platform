[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$StackName,
    [string]$OutputFile,
    [string]$AwsProfile,
    [string]$Region = 'us-east-1'
)
$ErrorActionPreference = 'Stop'
$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not $OutputFile) { $OutputFile = Join-Path $repositoryRoot 'config\amplify-outputs.env' }
$arguments = @('cloudformation','describe-stacks','--stack-name',$StackName,'--region',$Region,'--output','json')
if ($AwsProfile) { $arguments += @('--profile',$AwsProfile) }
$raw = & aws @arguments
if ($LASTEXITCODE -ne 0) { throw "No se pudo consultar el stack '$StackName'." }
$response = ($raw -join [Environment]::NewLine) | ConvertFrom-Json
if (-not $response.Stacks -or $response.Stacks.Count -ne 1) { throw 'La respuesta debe contener exactamente un stack.' }
$outputs = @{}
foreach ($item in $response.Stacks[0].Outputs) { $outputs[$item.OutputKey] = [string]$item.OutputValue }
$contract = [ordered]@{
    CLIENT_AMPLIFY_APP_ID='ClientAmplifyAppId'
    CLIENT_AMPLIFY_BRANCH='ClientAmplifyBranch'
    CLIENT_AMPLIFY_URL='ClientAmplifyUrl'
    ADMIN_AMPLIFY_APP_ID='AdminAmplifyAppId'
    ADMIN_AMPLIFY_BRANCH='AdminAmplifyBranch'
    ADMIN_AMPLIFY_URL='AdminAmplifyUrl'
}
$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add('# Generado desde Outputs de CloudFormation. No editar ni confirmar en Git.')
foreach ($entry in $contract.GetEnumerator()) {
    if (-not $outputs.ContainsKey($entry.Value) -or [string]::IsNullOrWhiteSpace($outputs[$entry.Value])) { throw "Falta el Output '$($entry.Value)'." }
    if ($outputs[$entry.Value] -match "[`r`n]") { throw "El Output '$($entry.Value)' contiene saltos de linea." }
    $lines.Add("$($entry.Key)=$($outputs[$entry.Value])")
}
[System.IO.File]::WriteAllLines([System.IO.Path]::GetFullPath($OutputFile),$lines,[System.Text.UTF8Encoding]::new($false))
Write-Host "Contrato Amplify generado: $OutputFile" -ForegroundColor Green
