[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SecretId,
    [Parameter(Mandatory)][string[]]$RepositoryUrls,
    [string]$AwsProfile,
    [string]$Region = 'us-east-1'
)
$ErrorActionPreference = 'Stop'
$awsBase = @('--region',$Region)
if ($AwsProfile) { $awsBase += @('--profile',$AwsProfile) }

$secretRaw = & aws secretsmanager get-secret-value --secret-id $SecretId --query SecretString --output text @awsBase
if ($LASTEXITCODE -ne 0) { throw "No se pudo leer el secreto '$SecretId' para validar el acceso a GitHub." }
$secret = (($secretRaw -join [Environment]::NewLine) | ConvertFrom-Json)
$token = [string]$secret.token
if ([string]::IsNullOrWhiteSpace($token)) { throw "El secreto '$SecretId' no contiene la propiedad 'token'." }

try {
    $headers = @{ Authorization="Bearer $token"; Accept='application/vnd.github+json'; 'X-GitHub-Api-Version'='2022-11-28' }
    foreach ($repositoryUrl in $RepositoryUrls) {
        $uri = [uri]$repositoryUrl
        if ($uri.Host -ne 'github.com') { throw "Repositorio GitHub no valido: $repositoryUrl" }
        $repositoryPath = $uri.AbsolutePath.Trim('/').Replace('.git','')
        if ($repositoryPath.Split('/').Count -ne 2) { throw "Repositorio GitHub no valido: $repositoryUrl" }
        try {
            Invoke-RestMethod -Uri "https://api.github.com/repos/$repositoryPath" -Headers $headers -Method Get | Out-Null
        } catch {
            throw "El token de '$SecretId' no puede leer el repositorio privado '$repositoryPath'. Cree un PAT classic con los scopes 'repo' y 'admin:repo_hook', autorice SSO si aplica y rote el secreto. Detalle GitHub: $($_.Exception.Message)"
        }
        Write-Host "Acceso GitHub verificado: $repositoryPath"
    }
} finally {
    $token = $null
    $secret = $null
    $secretRaw = $null
}
