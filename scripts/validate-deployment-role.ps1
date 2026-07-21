[CmdletBinding()]
param([string]$TemplateFile, [string]$Region = 'us-east-1', [string]$AwsProfile)
$ErrorActionPreference = 'Stop'
$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not $TemplateFile) { $TemplateFile = Join-Path $repositoryRoot 'infrastructure\deployment-role.yml' }
$templateText = Get-Content -LiteralPath $TemplateFile -Raw
foreach ($required in @('DeploymentRoleArn','DeploymentRoleName')) {
    if ($templateText -notmatch "(?m)^  ${required}:\s*$") { throw "Falta el Output '$required'." }
}
if ($templateText -match '(?m)^\s+Action:\s*[''"]?(iam|sts):\*') { throw 'La politica no puede conceder iam:* ni sts:*.' }
if ($templateText -notmatch 'iam:PassedToService:\s*lambda\.amazonaws\.com') { throw 'iam:PassRole debe restringirse al servicio Lambda.' }
if ($templateText -notmatch 'TrustedPrincipalArn') { throw 'La confianza del rol debe ser parametrizable.' }
$arguments = @('cloudformation','validate-template','--template-body',"file://$([System.IO.Path]::GetFullPath($TemplateFile))",'--region',$Region)
if ($AwsProfile) { $arguments += @('--profile',$AwsProfile) }
& aws @arguments | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'CloudFormation rechazo la plantilla del rol.' }
Write-Host 'Plantilla del rol de despliegue valida; no se creo ningun recurso.' -ForegroundColor Green
