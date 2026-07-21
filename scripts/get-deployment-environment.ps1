[CmdletBinding()]
param([string]$EnvironmentFile)
$arguments = @{ Quiet = $true }
if ($EnvironmentFile) { $arguments.EnvironmentFile = $EnvironmentFile }
. (Join-Path $PSScriptRoot 'load-environment.ps1') @arguments | Out-Null
Write-Output $env:ENVIRONMENT
