[CmdletBinding()]
param(
    [ValidateSet('qa','production')][string]$Environment,
    [string]$AmplifyOutputsFile
)
$ErrorActionPreference = 'Stop'
$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not $Environment) { $Environment = & (Join-Path $PSScriptRoot 'get-deployment-environment.ps1') }
if (-not $AmplifyOutputsFile) { $AmplifyOutputsFile = Join-Path $repositoryRoot "config\amplify-outputs.$Environment.env" }
if (-not (Test-Path -LiteralPath $AmplifyOutputsFile -PathType Leaf)) { throw "Falta el contrato de Amplify: $AmplifyOutputsFile" }
$values = @{}
$lineNumber = 0
foreach ($rawLine in Get-Content -LiteralPath $AmplifyOutputsFile) {
    $lineNumber++
    $line = $rawLine.Trim()
    if (-not $line -or $line.StartsWith('#')) { continue }
    $separator = $line.IndexOf('=')
    if ($separator -lt 1) { throw "Formato invalido en ${AmplifyOutputsFile}:$lineNumber." }
    $key = $line.Substring(0,$separator).Trim()
    $value = $line.Substring($separator + 1).Trim()
    if ($values.ContainsKey($key)) { throw "Clave duplicada '$key' en el contrato Amplify." }
    $values[$key] = $value
}
$origins = [System.Collections.Generic.List[string]]::new()
foreach ($key in @('CLIENT_AMPLIFY_URL','ADMIN_AMPLIFY_URL')) {
    if (-not $values.ContainsKey($key)) { throw "Falta '$key' en el contrato Amplify." }
    $uri = $null
    if (-not [uri]::TryCreate($values[$key],[System.UriKind]::Absolute,[ref]$uri)) { throw "'$key' no contiene una URL absoluta valida." }
    if ($uri.Scheme -ne 'https' -or -not $uri.Host.EndsWith('.amplifyapp.com',[System.StringComparison]::OrdinalIgnoreCase)) { throw "'$key' debe ser un origen HTTPS predeterminado de Amplify." }
    if ($uri.AbsolutePath -ne '/' -or $uri.Query -or $uri.Fragment -or $uri.Port -ne 443) { throw "'$key' debe contener solo el origen, sin ruta, query, fragmento ni puerto personalizado." }
    $origins.Add($uri.GetLeftPart([System.UriPartial]::Authority))
}
if ($origins[0] -eq $origins[1]) { throw 'Los frontends cliente y administrador no pueden compartir el mismo origen Amplify.' }
$origins -join ','
