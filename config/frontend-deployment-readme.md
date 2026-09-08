# README — Publicación de cambios del portal público

Esta guía sirve para publicar una versión ya aprobada de `frontends/aprendamosgye_react` en un ambiente existente. El portal público se identifica por su App ID y rama exportados desde el stack Amplify; no se debe asumir un ID ni una URL.

No crea infraestructura, no despliega microservicios y no modifica los secretos. Para una primera instalación, cambio de rama, cambio de URLs/API/Cognito/CDN o cambio de CORS, seguir primero el [manual del proveedor](provider-project-deployment-manual.md) y [Amplify Hosting](amplify-hosting.md).

## 1. Qué se publica y a dónde

El repositorio de código del portal es `frontends/aprendamosgye_react`. Amplify descarga la rama Git configurada para el ambiente y construye el portal desde ese repositorio.

La promoción ordinaria es la siguiente:

| Ambiente AWS   | Rama habitual  | Finalidad                           |
| -------------- | -------------- | ----------------------------------- |
| `develop`    | `develop`    | Desarrollo e integración técnica. |
| `qa`         | `qa`         | Pruebas y aceptación.              |
| `production` | `production` | Versión aprobada por el cliente.   |

`main` no participa en este flujo: permanece asociado al Amplify heredado. No se debe publicar, fusionar ni forzar cambios sobre `main` para desplegar esta solución.

El nombre de la rama es configurable. Antes de publicar, se toma del `DEPLOYMENT_BRANCH` del `.env` activo; por ejemplo, producción podría usar `epico-production` en vez de `production`. `ENVIRONMENT` solo puede ser `develop`, `qa` o `production`.

## 2. Requisitos antes de publicar

1. El cambio debe estar validado localmente, confirmado y enviado a la rama objetivo del repositorio público.
2. El repositorio padre debe registrar el gitlink del commit exacto del frontend para la misma rama. Amplify no necesita ese gitlink para construir, pero el padre lo conserva como evidencia reproducible de la versión desplegada.
3. El ambiente ya debe tener su stack `<RESOURCE_PREFIX>-amplify-<ENVIRONMENT>`, App de cliente y rama Amplify creados.
4. Debe haber una sesión AWS válida y permiso para `cloudformation:DescribeStacks`, `amplify:GetBranch`, `amplify:StartJob` y `amplify:GetJob` mediante el rol `<RESOURCE_PREFIX>-deployment-<ENVIRONMENT>`.
5. La rama Amplify debe tener configuradas las variables actuales. Para una modificación solamente visual o de lógica que no cambie `VITE_*`, no hay que recargarlas.

No copie `.env.develop` o `.env.qa` encima de `.env` durante una publicación rutinaria: podría perder parámetros locales acordados. Edite únicamente `ENVIRONMENT` y `DEPLOYMENT_BRANCH` de `.env` cuando sea necesario, preservando las demás líneas.

## 3. Preparar y enviar el cambio a `develop`

Desde la raíz del repositorio padre:

```powershell
Set-Location frontends\aprendamosgye_react
git fetch origin --prune
git switch develop
git pull --ff-only origin develop
git status --short --branch
npm ci
npm run lint
npm run build
git add <archivos-modificados>
git commit -m "feat: describir el cambio aprobado"
git push origin develop
```

`git status` debe quedar limpio después del push. Si hay cambios ajenos, no los incluya en este despliegue.

Después, actualice el puntero del submódulo en el repositorio padre, sin modificar otros submódulos:

```powershell
Set-Location ..\..
git switch develop
git pull --ff-only origin develop
git add frontends/aprendamosgye_react
git commit -m "chore: actualizar portal público en develop"
git push origin develop
```

## 4. Seleccionar el ambiente y renovar credenciales

Ejecute estos comandos desde la raíz `fsg-elearning-platform`, en una misma ventana de PowerShell. Sustituya `epico-bootstrap` por el perfil SSO temporal autorizado para la cuenta.

```powershell
# En .env, conservar todos los valores y dejar solo estas dos líneas con el destino deseado.
# ENVIRONMENT=develop
# DEPLOYMENT_BRANCH=develop

. .\scripts\load-environment.ps1 -Quiet
aws sso login --profile epico-bootstrap
$accountId = aws sts get-caller-identity --profile epico-bootstrap --query Account --output text
. .\scripts\enter-deployment-role.ps1 `
  -RoleArn "arn:aws:iam::$accountId`:role/$($env:RESOURCE_PREFIX)-deployment-$($env:ENVIRONMENT)" `
  -Environment $env:ENVIRONMENT `
  -AwsProfile epico-bootstrap `
  -Region $env:AWS_REGION
aws sts get-caller-identity
```

La última identidad debe ser el rol de despliegue del ambiente. Si aparece `ExpiredToken`, renovar el SSO y repetir esta sección; las credenciales asumidas viven solo en esa ventana y expiran.

## 5. Verificar qué App y rama recibirá la publicación

```powershell
$amplifyStack = "$($env:RESOURCE_PREFIX)-amplify-$($env:ENVIRONMENT)"
$clientAppId = aws cloudformation describe-stacks `
  --stack-name $amplifyStack `
  --region $env:AWS_REGION `
  --query "Stacks[0].Outputs[?OutputKey=='ClientAmplifyAppId'].OutputValue | [0]" `
  --output text
$clientBranch = aws cloudformation describe-stacks `
  --stack-name $amplifyStack `
  --region $env:AWS_REGION `
  --query "Stacks[0].Outputs[?OutputKey=='ClientAmplifyBranch'].OutputValue | [0]" `
  --output text
$clientUrl = aws cloudformation describe-stacks `
  --stack-name $amplifyStack `
  --region $env:AWS_REGION `
  --query "Stacks[0].Outputs[?OutputKey=='ClientAmplifyUrl'].OutputValue | [0]" `
  --output text

if ($clientBranch -ne $env:DEPLOYMENT_BRANCH) {
  throw "El stack apunta a '$clientBranch', pero .env exige '$($env:DEPLOYMENT_BRANCH)'. No publicar hasta alinear la infraestructura Amplify."
}

aws amplify get-branch `
  --app-id $clientAppId `
  --branch-name $clientBranch `
  --region $env:AWS_REGION `
  --query 'branch.[branchName,enableAutoBuild]' `
  --output table
```

Confirme que la rama mostrada corresponde al commit que se acaba de enviar. Mantener `enableAutoBuild=false` es válido y recomendado para controlar el momento de publicación; el comando de la siguiente sección inicia el build de forma explícita.

## 6. Publicar solamente el portal público

```powershell
$clientJob = aws amplify start-job `
  --app-id $clientAppId `
  --branch-name $clientBranch `
  --job-type RELEASE `
  --region $env:AWS_REGION `
  --output json | ConvertFrom-Json

$clientJobId = $clientJob.jobSummary.jobId
Write-Host "Build iniciado: $clientJobId"

aws amplify get-job `
  --app-id $clientAppId `
  --branch-name $clientBranch `
  --job-id $clientJobId `
  --region $env:AWS_REGION `
  --output json
```

Repita `get-job` hasta que `job.summary.status` sea `SUCCEED`. Si es `FAILED`, conserve el `jobId`, revise `job.summary.logUrl` en la respuesta o el enlace de build de la consola Amplify y corrija el error antes de iniciar otro job. No publique el portal administrativo por un cambio exclusivo del portal público.

## 7. Verificación posterior

Abra `$clientUrl` y valide, como mínimo:

1. Raíz del portal y la funcionalidad modificada.
2. Inicio de sesión y una recarga directa de `$clientUrl/login/` (debe responder la aplicación React, no 404).
3. Una ruta autenticada pertinente y la llamada API afectada, si la hay.
4. Vista móvil o de escritorio afectada por el cambio visual.

Registre ambiente, rama, SHA del commit, `clientJobId`, hora y resultado. La URL final también puede consultarse sin adivinarla con:

```powershell
Write-Host $clientUrl
```

## 8. Promover exactamente la versión aprobada

No reconstruya QA o producción desde `develop` si esa rama ya recibió cambios adicionales. Promueva el commit aprobado usando una fusión de avance rápido. El primer comando se ejecuta dentro de `frontends/aprendamosgye_react`:

```powershell
git fetch origin --prune
git switch qa
git pull --ff-only origin qa
git merge --ff-only origin/develop
git push origin qa
```

Actualice después el gitlink del padre en la rama `qa`:

```powershell
Set-Location ..\..
git switch qa
git pull --ff-only origin qa
git add frontends/aprendamosgye_react
git commit -m "chore: promover portal público a qa"
git push origin qa
```

Edite en `.env` únicamente `ENVIRONMENT=qa` y `DEPLOYMENT_BRANCH=qa`, ejecute las secciones 4 a 7 y obtenga aceptación de QA. Para producción, repita el mismo patrón `qa` → `production`, actualice el gitlink en el padre `production`, cambie `.env` a `ENVIRONMENT=production` y `DEPLOYMENT_BRANCH=production`, y ejecute las secciones 4 a 7.

Si el cliente usa una rama específica, reemplace solo la rama destino por la acordada y configure el mismo valor en `DEPLOYMENT_BRANCH`. Por ejemplo, para `epico-production`: el ambiente continúa siendo `production`, mientras que la rama Git y el `DEPLOYMENT_BRANCH` son `epico-production`.

Si `git merge --ff-only` se detiene, las historias divergen. No fuerce el push: revise los commits y cree una promoción explícita aprobada antes de continuar.

## 9. Cambios que sí requieren un flujo adicional

No use la publicación rápida si ocurre alguno de estos casos:

| Cambio                                                 | Paso adicional obligatorio antes del build                                                                                             |
| ------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------- |
| Variables`VITE_*`, URLs de API, Cognito o CloudFront | Exportar Outputs de plataforma y servicios, regenerar los mapas Amplify y cargarlos con`configure-amplify-branches.ps1 -Execute`.    |
| `DEPLOYMENT_BRANCH` o repositorio/rama de Amplify    | Actualizar por Change Set el stack Amplify, exportar Outputs, regenerar mapas y configurar las ramas.                                  |
| Nueva URL Amplify o cambio de origen                   | Actualizar`MEDIA_CORS_ALLOWED_ORIGINS`, desplegar infraestructura compartida y los microservicios que aplican CORS antes del portal. |
| API o microservicio modificado                         | Desplegar y probar primero esa API; publicar el portal después.                                                                       |
| Primera publicación del ambiente                      | Completar el orden de instalación del manual del proveedor; no crear App o rama manualmente desde este README.                        |

Para regenerar y cargar variables públicas después de un cambio de contrato, desde la raíz y con el rol del ambiente activo:

```powershell
.\scripts\export-cloudformation-outputs.ps1 `
  -StackName "$($env:RESOURCE_PREFIX)-platform-$($env:ENVIRONMENT)"
.\scripts\export-serverless-outputs.ps1
.\scripts\validate-environment.ps1 -RequirePlatformOutputs -RequireServiceOutputs
.\scripts\export-amplify-environments.ps1
.\scripts\configure-amplify-branches.ps1 `
  -Environment $env:ENVIRONMENT `
  -DeploymentBranch $env:DEPLOYMENT_BRANCH `
  -StackName "$($env:RESOURCE_PREFIX)-amplify-$($env:ENVIRONMENT)" `
  -Execute
```

Los archivos `config/amplify-client-<ambiente>-env.json` son locales e ignorados por Git. Contienen únicamente configuración pública que quedará incorporada al JavaScript; nunca deben contener tokens, contraseñas, Access Keys ni el secreto de Cognito.

## 10. Recuperación ante una publicación fallida

Si el build falló antes de `SUCCEED`, Amplify continúa sirviendo el último artefacto exitoso. Corrija el problema y vuelva a ejecutar la sección 6.

Si el build fue exitoso pero la validación funcional falla, detenga la promoción. Para restaurar el código en la misma rama, cree un revert nuevo y publicable; no use `git reset --hard` ni `push --force`:

```powershell
Set-Location frontends\aprendamosgye_react
git switch <rama-del-ambiente>
git revert <commit-a-revertir>
git push origin <rama-del-ambiente>

Set-Location ..\..
git switch <rama-del-ambiente>
git add frontends/aprendamosgye_react
git commit -m "revert: restaurar portal público"
git push origin <rama-del-ambiente>
```

Después, renueve las credenciales si hace falta, obtenga de nuevo `clientAppId` y `clientBranch` con la sección 5 y ejecute la sección 6. Registre el incidente y la versión restaurada.
