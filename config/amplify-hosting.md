# Amplify Hosting parametrizado

`infrastructure/amplify-hosting.yml` declara el portal público y la consola administrativa. El prefijo del cliente, ambiente y rama se reciben como parámetros; ninguna rama Git está asociada de forma fija a un ambiente.

La selección procede del `.env`:

```text
ENVIRONMENT=qa
DEPLOYMENT_BRANCH=qa
```

También es válido:

```text
ENVIRONMENT=production
DEPLOYMENT_BRANCH=epico-production
```

`sync-deployment-parameters.ps1` copia la rama a `DeploymentBranch` y deriva `DeploymentBranchDomainPrefix` reemplazando caracteres incompatibles con la URL. No editar `infrastructure/amplify-parameters.json` manualmente.

Flujo:

1. Cargar `.env` y ejecutar `sync-deployment-parameters.ps1`.
2. Revisar el Change Set del stack `<RESOURCE_PREFIX>-amplify-<ENVIRONMENT>`.
3. Confirmar que las dos aplicaciones utilizan exactamente `DEPLOYMENT_BRANCH`.
4. Crear inicialmente las ramas con `EnableAutoBuild=false`.
5. Exportar App IDs, rama y URLs con `export-amplify-outputs.ps1`.
6. Configurar las variables de rama con `configure-amplify-branches.ps1`.
7. Habilitar o iniciar builds solo después de desplegar infraestructura y microservicios.

Cambiar la rama requiere actualizar el stack Amplify, regenerar Outputs, volver a cargar las variables de rama y revisar CORS. Si cambia la URL resultante, también se actualiza `MEDIA_CORS_ALLOWED_ORIGINS`, el stack compartido y los seis microservicios de negocio.

El token de GitHub se conserva en Secrets Manager. No se escribe en plantillas, JSON, `.env`, logs ni repositorios.
