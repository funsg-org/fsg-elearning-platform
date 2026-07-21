# Orquestación de despliegue

> Paso previo nuevo: crear primero el stack `amplify-hosting.yml` con auto-build desactivado. Sus URLs permiten reemplazar el CORS provisional antes de desplegar la infraestructura compartida. La activación de builds ocurre solamente al final y de forma explícita; consulte `config/amplify-hosting.md`.

El script `scripts/deploy-platform.ps1` implementa el orden reproducible completo para una cuenta AWS ya creada: Amplify sin builds, CORS, infraestructura compartida, microservicios y variables públicas de los frontends.

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
6. Ejecutar:

```powershell
.\scripts\deploy-platform.ps1 `
  -Execute `
  -AwsProfile epico `
  -ExpectedAccountId 123456789012
```

Antes de cualquier escritura, `-Execute` ejecuta automáticamente `scripts/test-deployment-readiness.ps1`. El preflight puede ejecutarse también de forma independiente para diagnosticar la estación y las credenciales:

```powershell
.\scripts\test-deployment-readiness.ps1 -AwsProfile epico -ExpectedAccountId 123456789012
```

La opción `-SkipRemoteChecks` omite únicamente `git ls-remote`; no omite identidad AWS, secreto, parámetros ni plantillas.

El preflight verifica los permisos de lectura que puede comprobar sin mutaciones (`STS`, consulta del secreto y validación de CloudFormation). Los permisos de creación específicos de cada recurso se evalúan finalmente cuando CloudFormation crea el change set; comprobarlos por anticipado requeriría simulación IAM adicional o una operación AWS.

Los siete microservicios declaran `frameworkVersion: '~4.39.0'`. Esto evita actualizaciones de minor o major durante un despliegue y permite únicamente parches compatibles de la línea 4.39.

## Límites deliberados

- No crea la cuenta AWS.
- No configura dominio personalizado.
- No activa auto-build ni inicia publicaciones Amplify.
- No crea ni almacena Access Keys.
- Se detiene ante el primer error; no continúa con dependencias incompletas.
- Exige la rama `feature/epico-deployment-readiness` y un repositorio limpio.
- Compara la identidad AWS activa con `-ExpectedAccountId` antes de crear recursos.
- Rechaza `CostCenterTag=PENDING` y URLs que no sean orígenes HTTPS predeterminados de Amplify.

Al finalizar, las variables quedan cargadas en ambas ramas de preparación. La publicación requiere el comando explícito documentado en `config/amplify-hosting.md`.

Las validaciones estructurales que no requieren cuenta AWS se ejecutan también en GitHub Actions. Consulte `config/continuous-validation.md`.
