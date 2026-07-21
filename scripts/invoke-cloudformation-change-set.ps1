[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$StackName,
    [Parameter(Mandatory = $true)][string]$TemplateFile,
    [string[]]$ParameterOverrides = @(),
    [string[]]$Capabilities = @(),
    [switch]$ApproveExecution,
    [string]$AwsProfile,
    [string]$Region = 'us-east-1'
)
$ErrorActionPreference = 'Stop'
$TemplateFile = [System.IO.Path]::GetFullPath($TemplateFile)
if (-not (Test-Path -LiteralPath $TemplateFile -PathType Leaf)) { throw "No existe la plantilla: $TemplateFile" }
$awsBase = @('--region',$Region)
if ($AwsProfile) { $awsBase += @('--profile',$AwsProfile) }
$previousPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$stackLookup = & aws cloudformation describe-stacks --stack-name $StackName @awsBase 2>&1
$stackLookupExit = $LASTEXITCODE
$ErrorActionPreference = $previousPreference
if ($stackLookupExit -eq 0) { $changeSetType='UPDATE' }
elseif (($stackLookup -join [Environment]::NewLine) -match 'ValidationError|does not exist') { $changeSetType='CREATE' }
else { throw "No se pudo determinar el estado del stack '$StackName'." }
$changeSetName = 'review-' + $StackName + '-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8)
$arguments = @('cloudformation','create-change-set','--stack-name',$StackName,'--change-set-name',$changeSetName,'--change-set-type',$changeSetType,'--template-body',"file://$TemplateFile")
if ($ParameterOverrides.Count) {
    $arguments += '--parameters'
    foreach ($override in $ParameterOverrides) {
        $separator=$override.IndexOf('=')
        if ($separator -lt 1) { throw "Parametro invalido: $override" }
        $key=$override.Substring(0,$separator)
        $value=$override.Substring($separator+1)
        $arguments += "ParameterKey=$key,ParameterValue=$value"
    }
}
if ($Capabilities.Count) { $arguments += @('--capabilities') + $Capabilities }
$arguments += $awsBase
& aws @arguments | Out-Null
if ($LASTEXITCODE -ne 0) { throw "No se pudo crear el change set '$changeSetName'." }

$previousPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$waitOutput = & aws cloudformation wait change-set-create-complete --stack-name $StackName --change-set-name $changeSetName @awsBase 2>&1
$waitExit = $LASTEXITCODE
$ErrorActionPreference = $previousPreference
$descriptionRaw = & aws cloudformation describe-change-set --stack-name $StackName --change-set-name $changeSetName --output json @awsBase
if ($LASTEXITCODE -ne 0) { throw 'No se pudo describir el change set.' }
$description = ($descriptionRaw -join [Environment]::NewLine) | ConvertFrom-Json
if ($waitExit -ne 0) {
    if ($description.StatusReason -match "didn't contain changes|No updates") {
        Write-Host "Sin cambios para $StackName." -ForegroundColor Green
        & aws cloudformation delete-change-set --stack-name $StackName --change-set-name $changeSetName @awsBase | Out-Null
        return
    }
    throw "El change set fallo: $($description.StatusReason)"
}
$rows = foreach ($change in $description.Changes) {
    $resource=$change.ResourceChange
    [pscustomobject]@{ Action=$resource.Action; LogicalId=$resource.LogicalResourceId; Type=$resource.ResourceType; Replacement=$resource.Replacement; Scope=($resource.Scope -join ',') }
}
Write-Host "Change set: $changeSetName | Stack: $StackName | Tipo: $changeSetType" -ForegroundColor Cyan
$rows | Format-Table -AutoSize
if (-not $ApproveExecution) {
    Write-Warning 'Change set creado pero NO ejecutado. Revíselo y elimínelo o ejecútelo explícitamente.'
    Write-Output $changeSetName
    return
}
Write-Host 'Aprobación explícita recibida; ejecutando change set.' -ForegroundColor Yellow
& aws cloudformation execute-change-set --stack-name $StackName --change-set-name $changeSetName @awsBase
if ($LASTEXITCODE -ne 0) { throw 'No se pudo ejecutar el change set.' }
& aws cloudformation wait "stack-$($changeSetType.ToLowerInvariant())-complete" --stack-name $StackName @awsBase
if ($LASTEXITCODE -ne 0) { throw "El stack '$StackName' no terminó correctamente." }
Write-Host "Stack completado: $StackName" -ForegroundColor Green
