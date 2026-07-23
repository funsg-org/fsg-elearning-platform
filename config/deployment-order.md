# Orquestación de despliegue

> Paso previo nuevo: crear primero el stack `amplify-hosting.yml` con auto-build desactivado. Sus URLs permiten reemplazar el CORS provisional antes de desplegar la infraestructura compartida. La activación de builds ocurre solamente al final y de forma explícita; consulte `config/amplify-hosting.md`.

El script `scripts/deploy-platform.ps1` implementa el orden reproducible completo para una cuenta AWS ya creada: Amplify sin builds, CORS, infraestructura compartida, microservicios, migración inicial opcional del menú y variables públicas de los frontends.

## Vista previa segura

```powershell
.\scripts\deploy-platform.ps1
```

Este modo valida rama, submódulos, plantilla y estructura, y luego muestra el orden. No crea recursos.

## Ejecución futura

1. Copiar los dos archivos de parámetros de ejemplo como `parameters.json` y `amplify-parameters.json`.
2. Definir el mismo `CostCenterTag` definitivo en ambos archivos.
3. Autorizar Amplify GitHub App y crear el secreto indicado por `GitHubAccessTokenSecretId`.
4. Crear el secreto operativo de Serverless documentado en `config/secrets.md`.
5. Configurar credenciales AWS mediante perfil u OIDC.
6. Crear una sola vez el rol descrito en `config/deployment-role.md`.
7. Ejecutar:

```powershell
.\scripts\deploy-platform.ps1 `
  -Execute `
  -ApproveChangeSets `
  -MigrateMenu `
  -AwsProfile epico `
  -ExpectedAccountId 123456789012 `
  -DeploymentRoleArn arn:aws:iam::123456789012:role/<RESOURCE_PREFIX>-deployment-<ENVIRONMENT>
```

Antes de cualquier escritura, `-Execute` ejecuta automáticamente `scripts/test-deployment-readiness.ps1`. El preflight puede ejecutarse también de forma independiente para diagnosticar la estación y las credenciales:

```powershell
.\scripts\enter-deployment-role.ps1 -RoleArn arn:aws:iam::123456789012:role/<RESOURCE_PREFIX>-deployment-<ENVIRONMENT> -AwsProfile epico
.\scripts\test-deployment-readiness.ps1 -ExpectedAccountId 123456789012 -ExpectedDeploymentRoleArn arn:aws:iam::123456789012:role/<RESOURCE_PREFIX>-deployment-<ENVIRONMENT>
```

La opción `-SkipRemoteChecks` omite únicamente `git ls-remote`; no omite identidad AWS, secreto, parámetros ni plantillas.

El preflight verifica los permisos de lectura que puede comprobar sin mutaciones (`STS`, consulta del secreto y validación de CloudFormation). Los permisos de creación específicos de cada recurso se evalúan finalmente cuando CloudFormation crea el change set; comprobarlos por anticipado requeriría simulación IAM adicional o una operación AWS.

Los siete microservicios fijan el paquete npm `serverless` en `4.39.0` y declaran `frameworkVersion: '4'`. El paquete hace reproducible el binario y el contrato impide ejecutar versiones v3 o v5.

## Límites deliberados

- No crea la cuenta AWS.
- No configura dominio personalizado.
- No activa auto-build ni inicia publicaciones Amplify.
- No crea ni almacena Access Keys.
- Se detiene ante el primer error; no continúa con dependencias incompletas.
- Exige que la rama actual coincida con `DEPLOYMENT_BRANCH` y que el repositorio esté limpio.
- Mantiene independientes el ambiente AWS (`develop`, `qa` o `production`) y la rama Git; la rama puede ser la base del ambiente o una variante específica del cliente.
- Compara la identidad AWS activa con `-ExpectedAccountId` antes de crear recursos.
- Rechaza `CostCenterTag=PENDING` y URLs que no sean orígenes HTTPS predeterminados de Amplify.

Al finalizar, las variables quedan cargadas en ambas ramas de preparación. La publicación requiere el comando explícito documentado en `config/amplify-hosting.md`.

Las validaciones estructurales que no requieren cuenta AWS se ejecutan también en GitHub Actions. Consulte `config/continuous-validation.md`.

Los tres stacks CloudFormation directos usan una compuerta de change sets documentada en `config/change-set-approval.md`.

Antes de cada stack Serverless se captura un manifiesto local de recuperación. Consulte `config/recovery.md`.
