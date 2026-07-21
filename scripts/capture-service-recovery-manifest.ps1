[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$StackName,
    [Parameter(Mandatory = $true)][string]$ServicePath,
    [Parameter(Mandatory = $true)][string]$OutputFile,
    [string]$Region = 'us-east-1',
    [string]$AwsProfile
)
$ErrorActionPreference = 'Stop'
$awsBase=@('--region',$Region)
if ($AwsProfile) { $awsBase+=@('--profile',$AwsProfile) }
$commit=(& git -C $ServicePath rev-parse HEAD).Trim()
$previousPreference=$ErrorActionPreference
$ErrorActionPreference='Continue'
$stackRaw=& aws cloudformation describe-stacks --stack-name $StackName --output json @awsBase 2>&1
$stackExit=$LASTEXITCODE
$ErrorActionPreference=$previousPreference
$manifest=[ordered]@{ capturedAtUtc=(Get-Date).ToUniversalTime().ToString('o'); stackName=$StackName; serviceCommit=$commit; previousStackExists=($stackExit -eq 0) }
if ($stackExit -eq 0) {
    $stack=(($stackRaw -join [Environment]::NewLine)|ConvertFrom-Json).Stacks[0]
    $templateRaw=& aws cloudformation get-template --stack-name $StackName --template-stage Processed --output json @awsBase
    if ($LASTEXITCODE -ne 0) { throw "No se pudo capturar el template de $StackName." }
    $resourcesRaw=& aws cloudformation describe-stack-resources --stack-name $StackName --output json @awsBase
    if ($LASTEXITCODE -ne 0) { throw "No se pudieron capturar recursos de $StackName." }
    $resources=(($resourcesRaw -join [Environment]::NewLine)|ConvertFrom-Json).StackResources
    $lambdaConfigurations=[System.Collections.Generic.List[object]]::new()
    foreach ($resource in ($resources|Where-Object ResourceType -eq 'AWS::Lambda::Function')) {
        $configurationRaw=& aws lambda get-function-configuration --function-name $resource.PhysicalResourceId --output json @awsBase
        if ($LASTEXITCODE -eq 0) { $lambdaConfigurations.Add((($configurationRaw -join [Environment]::NewLine)|ConvertFrom-Json)) }
    }
    $manifest.stackStatus=$stack.StackStatus
    $manifest.parameters=$stack.Parameters
    $manifest.outputs=$stack.Outputs
    $manifest.tags=$stack.Tags
    $manifest.template=(($templateRaw -join [Environment]::NewLine)|ConvertFrom-Json).TemplateBody
    $manifest.resources=$resources
    $manifest.lambdaConfigurations=$lambdaConfigurations
} elseif (($stackRaw -join [Environment]::NewLine) -notmatch 'ValidationError|does not exist') { throw "No se pudo consultar $StackName." }
$directory=Split-Path -Parent ([System.IO.Path]::GetFullPath($OutputFile))
if (-not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory | Out-Null }
[System.IO.File]::WriteAllText([System.IO.Path]::GetFullPath($OutputFile),($manifest|ConvertTo-Json -Depth 100),[System.Text.UTF8Encoding]::new($false))
Write-Host "Manifiesto previo guardado: $OutputFile" -ForegroundColor Green
