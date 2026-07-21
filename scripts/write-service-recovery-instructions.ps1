[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ServiceName,
    [Parameter(Mandatory = $true)][string]$ServicePath,
    [Parameter(Mandatory = $true)][string]$StackName,
    [Parameter(Mandatory = $true)][string]$ManifestFile,
    [Parameter(Mandatory = $true)][string]$OutputFile
)
$commit=(& git -C $ServicePath rev-parse HEAD).Trim()
$content=@"
# Recuperación de $ServiceName

El despliegue se detuvo en `$ServiceName`. CloudFormation intentará su rollback automático antes de cualquier acción manual.

1. Revisar el estado: `aws cloudformation describe-stacks --stack-name $StackName`.
2. No ejecutar otro despliegue mientras el stack esté en `*_IN_PROGRESS`.
3. Revisar eventos: `aws cloudformation describe-stack-events --stack-name $StackName`.
4. Usar el manifiesto previo: `$ManifestFile`.
5. Código usado en el intento: `$commit`.
6. Si el rollback automático termina correctamente, corregir la causa y volver a desplegar este commit o el commit previamente aprobado.
7. Para datos DynamoDB, restaurar PITR a una tabla nueva y validar antes de cambiar consumidores; no sobrescribir la tabla retenida.
8. Para objetos S3, recuperar una versión anterior por VersionId; no borrar versiones durante el incidente.

La recuperación manual nunca debe incluir `serverless remove`, eliminación de stacks, tablas o buckets sin aprobación específica.
"@
$directory=Split-Path -Parent ([System.IO.Path]::GetFullPath($OutputFile))
if (-not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory | Out-Null }
[System.IO.File]::WriteAllText([System.IO.Path]::GetFullPath($OutputFile),$content,[System.Text.UTF8Encoding]::new($false))
Write-Host "Instrucciones de recuperación: $OutputFile" -ForegroundColor Yellow
