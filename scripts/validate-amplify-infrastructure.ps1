[CmdletBinding()]
param([string]$TemplateFile, [string]$Region = 'us-east-1', [string]$AwsProfile)
$ErrorActionPreference = 'Stop'
$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($TemplateFile)) { $TemplateFile = Join-Path $repositoryRoot 'infrastructure\amplify-hosting.yml' }
$TemplateFile = [System.IO.Path]::GetFullPath($TemplateFile)
if (-not (Test-Path -LiteralPath $TemplateFile -PathType Leaf)) { throw "No se encontro la plantilla: $TemplateFile" }
$templateText = Get-Content -LiteralPath $TemplateFile -Raw
foreach ($output in @('ClientAmplifyAppId','ClientAmplifyBranch','ClientAmplifyUrl','AdminAmplifyAppId','AdminAmplifyBranch','AdminAmplifyUrl')) {
    if ($templateText -notmatch "(?m)^  $([regex]::Escape($output)):\s*$") { throw "Falta el Output obligatorio '$output'." }
}
if ($templateText -notmatch "AccessToken:\s*!Sub\s+'\{\{resolve:secretsmanager:") { throw 'El acceso a GitHub debe resolverse desde Secrets Manager.' }
if ($templateText -match '(?im)(github_pat_[A-Za-z0-9_]+|ghp_[A-Za-z0-9]+|AKIA[0-9A-Z]{16})') { throw 'La plantilla contiene un patron de credencial.' }
if (($templateText | Select-String -Pattern 'EnableAutoBuild: false' -AllMatches).Matches.Count -ne 2) { throw 'Las dos ramas deben iniciar con auto-build desactivado.' }
$arguments = @('cloudformation','validate-template','--template-body',"file://$TemplateFile",'--region',$Region)
if ($AwsProfile) { $arguments += @('--profile',$AwsProfile) }
& aws @arguments | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'AWS CloudFormation rechazo la plantilla de Amplify.' }
Write-Host 'Plantilla de Amplify valida; no se desplego ningun recurso.' -ForegroundColor Green
