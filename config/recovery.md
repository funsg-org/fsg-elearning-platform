# Respaldo y recuperación

## Datos

- Las diez tablas DynamoDB usan `DeletionPolicy: Retain`, `UpdateReplacePolicy: Retain` y recuperación a un punto en el tiempo.
- El bucket multimedia compartido ya usa retención, versionado, bloqueo público y versiones no actuales.
- Una restauración PITR siempre crea primero una tabla nueva; el cambio de consumidores ocurre después de validar integridad.
- La recuperación S3 usa `VersionId`; no se eliminan versiones durante un incidente.

## Antes de cada microservicio

`deploy-platform.ps1` crea una carpeta ignorada `artifacts/recovery/<UTC>/`. Para cada stack captura:

- commit Git del servicio;
- template CloudFormation procesado;
- parámetros, outputs, tags y recursos físicos;
- configuración y versión publicada de cada Lambda.

Si `serverless deploy` falla, el flujo se detiene y genera `<servicio>-RECOVERY.md`. Primero se espera el rollback automático de CloudFormation; el instructivo prohíbe `serverless remove` y eliminaciones manuales sin aprobación específica.

Estos manifiestos pueden contener IDs y configuración operativa, por eso no se versionan. Deben copiarse al repositorio seguro de evidencias definido por operaciones cuando exista.

Antes de modificar AWS, el orquestador ejecuta `npm ci --ignore-scripts` en los siete servicios. Así un lockfile inválido o una dependencia incompatible detiene el proceso antes del primer change set.
