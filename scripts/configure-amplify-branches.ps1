[CmdletBinding()]
param(
    [switch]$Execute,
    [switch]$EnableAutoBuild,
    [switch]$StartBuild,
    [string]$StackName = 'epico-amplify-production',
    [string]$Region = 'us-east-1',
    [string]$AwsProfile,
    [string]$ClientEnvironmentFile,
    [string]$AdminEnvironmentFile
)
$ErrorActionPreference = 'Stop'
$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not $ClientEnvironmentFile) { $ClientEnvironmentFile = Join-Path $repositoryRoot 'config\amplify-client-env.json' }
if (-not $AdminEnvironmentFile) { $AdminEnvironmentFile = Join-Path $repositoryRoot 'config\amplify-admin-env.json' }
foreach ($path in @($ClientEnvironmentFile,$AdminEnvironmentFile)) { if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Falta el mapa: $path" } }
if (($EnableAutoBuild -or $StartBuild) -and -not $Execute) { throw '-EnableAutoBuild y -StartBuild requieren -Execute.' }
$awsBase = @('--region',$Region)
if ($AwsProfile) { $awsBase += @('--profile',$AwsProfile) }
$raw = & aws cloudformation describe-stacks --stack-name $StackName --query 'Stacks[0].Outputs' --output json @awsBase
if ($LASTEXITCODE -ne 0) { throw "No se pudieron consultar los Outputs de $StackName." }
$outputs = @{}
foreach ($item in (($raw -join [Environment]::NewLine) | ConvertFrom-Json)) { $outputs[$item.OutputKey] = $item.OutputValue }
$targets = @(
    @{ Name='cliente'; AppId=$outputs.ClientAmplifyAppId; Branch=$outputs.ClientAmplifyBranch; File=$ClientEnvironmentFile },
    @{ Name='administrador'; AppId=$outputs.AdminAmplifyAppId; Branch=$outputs.AdminAmplifyBranch; File=$AdminEnvironmentFile }
)
foreach ($target in $targets) {
    if (-not $target.AppId -or -not $target.Branch) { throw "Faltan Outputs para $($target.Name)." }
    Write-Host "$($target.Name): app $($target.AppId), rama $($target.Branch), variables $($target.File)"
}
if (-not $Execute) { Write-Warning 'Vista previa: no se modificaron ramas ni se iniciaron builds.'; exit 0 }
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("epico-amplify-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempDir | Out-Null
try {
    foreach ($target in $targets) {
        $request = [ordered]@{ appId=$target.AppId; branchName=$target.Branch; enableAutoBuild=[bool]$EnableAutoBuild; environmentVariables=(Get-Content -LiteralPath $target.File -Raw | ConvertFrom-Json) }
        $requestFile = Join-Path $tempDir "$($target.Name).json"
        [System.IO.File]::WriteAllText($requestFile,($request | ConvertTo-Json -Depth 5),[System.Text.UTF8Encoding]::new($false))
        & aws amplify update-branch --cli-input-json "file://$requestFile" @awsBase | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "No se pudo configurar $($target.Name)." }
        if ($StartBuild) {
            & aws amplify start-job --app-id $target.AppId --branch-name $target.Branch --job-type RELEASE @awsBase | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "No se pudo iniciar el build de $($target.Name)." }
        }
    }
} finally { Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue }
Write-Host "Ramas configuradas. Auto-build: $([bool]$EnableAutoBuild); builds: $([bool]$StartBuild)" -ForegroundColor Green

