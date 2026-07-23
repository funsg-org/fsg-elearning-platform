# Manual interno del proveedor para desplegar microservicios y frontends

## 1. Alcance

Este runbook es exclusivo de FSG y se ejecuta en dos momentos. La **Fase A** comienza cuando el cliente ya creó el rol limitado: FSG prepara Amplify sin publicar y devuelve sus URLs. FSG se detiene mientras el cliente crea la infraestructura compartida. La **Fase B** comienza después de que Cognito, S3 y CloudFront existen y continúa con microservicios y frontends. No crea la cuenta AWS ni solicita credenciales root.

## 2. Seleccionar el ambiente antes de operar

Copiar `.env.example` como `.env` y seleccionar el ambiente:

```dotenv
ENVIRONMENT=qa
DEPLOYMENT_BRANCH=qa
```

Los ambientes permitidos son `develop`, `qa` y `production`. `DEPLOYMENT_BRANCH` es independiente y puede ser la rama base del ambiente o una variante de cliente como `epico-production`. Si se omite, adopta el valor de `ENVIRONMENT`.

Para cambiar de ambiente, cliente o rama, cerrar la terminal, modificar los valores correspondientes y abrir una terminal nueva. Los JSON locales se regeneran; los Outputs conservan el ambiente en su nombre para evitar mezclas. Nunca modificar ni eliminar un `.env` o JSON local existente sin autorización de su propietario.

## 3. Información que debe recibir FSG

### Para la Fase A — todavía no existen Cognito, S3 ni CloudFront

- Account ID de 12 dígitos y región `us-east-1`.
- ARN de `<RESOURCE_PREFIX>-deployment-<ambiente>`.
- Método SSO temporal; excepcionalmente Access Keys de un usuario temporal dedicado.
- CostCenter definitivo.
- Ventana autorizada de despliegue.

### Para la Fase B — después de la infraestructura compartida

- Confirmación `CREATE_COMPLETE` de `<RESOURCE_PREFIX>-platform-<ambiente>`.
- Outputs no sensibles de Cognito, S3 y CloudFront, o permiso para consultarlos con AWS CLI.
- Correo y nombre del administrador inicial.
- Copia no sensible de los parámetros aprobados.

Rechazar credenciales root, contraseñas personales o sesiones pertenecientes a otro empleado.

Antes de la instalación, FSG genera el paquete sin código que entrega al cliente:

```powershell
.\scripts\build-client-deployment-package.ps1
```

Revisar `artifacts/client-deployment-kit/SHA256SUMS.txt` y transferir el directorio mediante el canal acordado.

## 3. Configurar acceso temporal

Para SSO:

```powershell
aws configure sso --profile epico-provider
aws sso login --profile epico-provider
aws sts get-caller-identity --profile epico-provider
```

Para credencial temporal excepcional:

```powershell
aws configure --profile epico-provider
aws sts get-caller-identity --profile epico-provider
```

Comprobar el Account ID antes de continuar.

## 4. Preparar el código privado

```powershell
git clone --recurse-submodules https://github.com/funsg-org/fsg-elearning-platform.git
Set-Location fsg-elearning-platform
$deploymentBranch = 'qa' # usar el mismo valor que DEPLOYMENT_BRANCH
git switch $deploymentBranch
git submodule sync --recursive
git submodule update --init --recursive
git status
git submodule status
```

Confirmar que el padre y cada repositorio privado estén en la rama indicada por `DEPLOYMENT_BRANCH`. Las ramas base recomendadas son `develop`, `qa` y `production`; `main` queda fuera del flujo mientras continúe conectado a instalaciones heredadas. Una variante específica debe usar el mismo nombre en todos los repositorios afectados.

El código permanece en infraestructura FSG y no se copia al cliente.

## 5. Asumir el rol limitado

```powershell
. .\scripts\load-environment.ps1 -Quiet
$accountId = aws sts get-caller-identity --query Account --output text --profile epico-provider
$deploymentRoleArn = "arn:aws:iam::$accountId`:role/$($env:RESOURCE_PREFIX)-deployment-$($env:ENVIRONMENT)"

.\scripts\enter-deployment-role.ps1 `
  -RoleArn $deploymentRoleArn `
  -AwsProfile epico-provider
aws sts get-caller-identity
```

Confirmar `assumed-role/<RESOURCE_PREFIX>-deployment-<ambiente>` y la cuenta esperada.

El comando `enter-deployment-role.ps1` y todos los comandos de las fases siguientes deben ejecutarse en **la misma ventana de PowerShell**. Las credenciales STS se guardan solamente en la memoria de ese proceso. Antes de crear secretos, comprobar otra vez:

```powershell
aws sts get-caller-identity --query Arn --output text
```

El resultado debe contener `assumed-role/<RESOURCE_PREFIX>-deployment-<ambiente>/`. Si muestra `user/`, `AWSReservedSSO_` u otro rol, detenerse y volver a ejecutar `enter-deployment-role.ps1`.

## 6. Fase A: preparar Amplify sin publicar

Esta fase no necesita Cognito, S3, CloudFront ni URLs de microservicios.

### 6.1 Instalar la GitHub App oficial de Amplify

Este paso se realiza una sola vez para la organización y región:

1. Iniciar sesión en GitHub con una cuenta que tenga acceso administrativo a `funsg-org`.
2. Abrir `https://github.com/apps/aws-amplify-us-east-1/installations/new`.
3. En **Where do you want to install AWS Amplify (us-east-1)?**, elegir `funsg-org`.
4. Seleccionar **Only select repositories**.
5. Autorizar únicamente:
   - `funsg-org/aprendamosgye_react`
   - `funsg-org/ms-aprendamosgye-admin-web`
6. Elegir **Install**.

Si GitHub muestra **Request** en lugar de **Install**, un propietario de `funsg-org` debe aprobar la instalación y el acceso a esos repositorios antes de continuar.

### 6.2 Generar el Personal Access Token

La creación mediante CloudFormation requiere además un Personal Access Token:

1. En GitHub abrir la foto de perfil → **Settings**.
2. Al final del menú izquierdo elegir **Developer settings**.
3. Elegir **Personal access tokens** → **Tokens (classic)**.
4. Elegir **Generate new token** → **Generate new token (classic)**.
5. Confirmar la contraseña o segundo factor si GitHub lo solicita.
6. Completar:
   - **Note**: `AWS Amplify EPICO QA bootstrap`.
   - **Expiration**: una vigencia aprobada para la instalación; para la prueba puede utilizarse 30 días.
   - **Select scopes**: marcar `repo` y `admin:repo_hook`. El scope `repo` es necesario para que Amplify pueda leer estos repositorios privados; `admin:repo_hook` permite administrar el webhook de despliegue.
7. Elegir **Generate token**.
8. Copiar el token inmediatamente; GitHub no lo vuelve a mostrar.

No guardar el token en `.env`, JSON, código, historial de comandos, correo o chat. Si la organización exige autorización SSO para tokens, elegir **Configure SSO** junto al token y autorizar `funsg-org`.

### 6.3 Guardar el token en Secrets Manager

Si el script ya está esperando el token, pegarlo directamente en el prompt seguro y presionar Enter. PowerShell no muestra los caracteres. Si se canceló con `Ctrl+C`, volver a ejecutar:

```powershell
$accountId = aws sts get-caller-identity --query Account --output text

.\scripts\initialize-amplify-github-secret.ps1 `
  -Execute `
  -ExpectedAccountId $accountId `
  -CostCenter FSG-ELRN-EPICO-QA
```

Si el secreto ya existe y es necesario sustituir un token inválido o vencido, crear primero un PAT classic nuevo con `repo` y `admin:repo_hook` y ejecutar:

```powershell
.\scripts\initialize-amplify-github-secret.ps1 `
  -Execute -RotateExisting `
  -ExpectedAccountId $accountId `
  -CostCenter FSG-ELRN-EPICO-QA
```

El script reemplaza únicamente el valor del secreto existente; conserva su nombre y etiquetas. No modifica archivos `.env` ni JSON.

El script almacena el token en `epico/qa/github/amplify-token` sin imprimirlo. No enviarlo al cliente ni a FSG por un canal no aprobado.

### 6.4 Crear Amplify sin publicar

Crear las dos aplicaciones y sus ramas con auto-build desactivado:

```powershell
.\scripts\deploy-amplify-bootstrap.ps1 `
  -Execute -ApproveChangeSets `
  -ExpectedAccountId $accountId
```

Antes de crear el change set, el script consulta ambos repositorios con el token almacenado. Si alguno devuelve 404, verificar los scopes `repo` y `admin:repo_hook`, la autorización SSO y que AWS Amplify GitHub App tenga seleccionados ambos repositorios.

Si un intento anterior dejó el stack Amplify actual en `ROLLBACK_COMPLETE`, corregir primero el token y luego eliminar únicamente ese stack fallido:

```powershell
$amplifyStack = "$($env:RESOURCE_PREFIX)-amplify-$($env:ENVIRONMENT)"
aws cloudformation delete-stack --stack-name $amplifyStack --region us-east-1
aws cloudformation wait stack-delete-complete --stack-name $amplifyStack --region us-east-1
```

La eliminación del stack requiere confirmación consciente. No ejecutar estos comandos si el stack contiene recursos válidos que deban conservarse.

1. Confirmar que se generó `config/amplify-outputs.<ambiente>.env` y que contiene las dos URLs `amplifyapp.com`.
2. Entregar al cliente las URLs, nombre del stack y confirmación de que no se inició ningún build.
3. **DETENERSE.** No ejecutar todavía los pasos siguientes. El cliente debe completar CORS y crear `<RESOURCE_PREFIX>-platform-<ambiente>`.

Después de comprobar que ambas aplicaciones Amplify acceden correctamente a los repositorios, registrar la fecha de expiración. Revocar o rotar el token cuando termine su vigencia o deje de ser necesario; no reutilizarlo para otros clientes.

## 7. Fase B: incorporar Outputs de infraestructura compartida

Reanudar únicamente después de que el cliente confirme `CREATE_COMPLETE`.

Opción recomendada, exportarlos directamente desde CloudFormation:

```powershell
. .\scripts\load-environment.ps1 -Quiet
.\scripts\export-cloudformation-outputs.ps1 `
  -StackName "$($env:RESOURCE_PREFIX)-platform-$($env:ENVIRONMENT)"
```

Como alternativa, crear localmente `config/platform-outputs.<ambiente>.env`, sin confirmar en Git:

```text
AWS_ACCOUNT_ID=<cuenta>
COGNITO_USER_POOL_ID=<output>
COGNITO_CLIENT_ID=<output público>
COGNITO_ADMINISTRATORS_GROUP=<output>
COGNITO_AUTH_CLIENT_ID=<output confidencial-id, no secreto>
COGNITO_CLIENT_SECRET_ID=<nombre/ARN del secreto, no valor>
MEDIA_BUCKET_NAME=<output>
MEDIA_CDN_URL=<output>
MEDIA_CLOUDFRONT_DISTRIBUTION_ID=<output>
```

Validar:

```powershell
.\scripts\validate-environment.ps1 -RequirePlatformOutputs
```

## 8. Preparar Serverless Framework

Crear una Access Key dedicada desde la organización FSG en Serverless Dashboard (`Settings` → `Access Keys`). No pedir al cliente que la genere ni entregársela.

Guardar la clave en la cuenta del cliente mediante entrada segura:

```powershell
.\scripts\initialize-serverless-access-key-secret.ps1 `
  -Execute -ExpectedAccountId 123456789012 `
  -CostCenter FSG-ELRN-EPICO-PROD
```

El script solicita la clave y crea `epico/production/serverless/access-key` sin mostrarla.

## 9. Preflight de proyectos

Antes del preflight, confirmar que el cliente haya desplegado la versión vigente de `infrastructure/deployment-role.yml`. Si la plantilla cambió después de crear el rol, actualizar primero `<RESOURCE_PREFIX>-deployment-role-<ambiente>` desde una terminal nueva autenticada solamente con el perfil bootstrap; no hacerlo desde una sesión que ya asumió `<RESOURCE_PREFIX>-deployment-<ambiente>`:

```powershell
aws sso login --profile epico-bootstrap
$accountId = aws sts get-caller-identity --profile epico-bootstrap --query Account --output text

.\scripts\deploy-deployment-role.ps1 `
  -Execute -ApproveChangeSets `
  -AwsProfile epico-bootstrap `
  -ExpectedAccountId $accountId
```

Después de la actualización, volver a asumir el rol en la terminal de despliegue. Serverless necesita tanto `cloudformation:DescribeStackResource` como `cloudformation:DescribeStackResources`; son acciones IAM diferentes.

Crear localmente, a partir de los ejemplos, `infrastructure/parameters.json` y `infrastructure/amplify-parameters.json` con los mismos valores no sensibles aprobados por el cliente. Estos archivos permanecen ignorados por Git.

```powershell
.\scripts\test-deployment-readiness.ps1 `
  -ExpectedAccountId 123456789012 `
  -ExpectedDeploymentRoleArn "arn:aws:iam::123456789012:role/$($env:RESOURCE_PREFIX)-deployment-$($env:ENVIRONMENT)"
```

Verificar rama, repositorios limpios, Serverless 4.39.0, secreto, outputs, región y cuenta.

## 10. Instalar dependencias sin tocar AWS

En cada servicio ejecutar `npm ci --ignore-scripts`. Si uno falla, detener la ventana y no desplegar ningún servicio.

## 11. Desplegar los siete microservicios

Antes de entrar al primer repositorio, cargar la configuración desde la raíz. Este comando no modifica `.env`; deriva `RUNTIME_NODE_ENV=production` y conserva `ENVIRONMENT` como el nombre del stage (`develop`, `qa` o `production`):

```powershell
. .\scripts\load-environment.ps1 -Quiet
```

Para los seis servicios de negocio, Serverless toma `MEDIA_CORS_ALLOWED_ORIGINS` del `.env` raíz y lo publica en Lambda como `CORS_ALLOWED_ORIGINS`. Por ello, el `.env` debe contener las URLs Amplify exactas antes de desplegar los microservicios.

Orden obligatorio:

1. Auth
2. Course
3. Menu
4. Metrics
5. Subscriptions
6. Users
7. Videos

Antes de cada `npx serverless deploy`, capturar el manifiesto con `capture-service-recovery-manifest.ps1`. Usar `--stage $env:ENVIRONMENT --region $env:AWS_REGION`. Detenerse ante el primer error y generar las instrucciones de recuperación; no usar `serverless remove` como rollback.

Ejemplo desde cada carpeta de servicio:

```powershell
npx serverless deploy --stage $env:ENVIRONMENT --region $env:AWS_REGION
```

Si cambia una URL de Amplify o se modifica `MEDIA_CORS_ALLOWED_ORIGINS`, volver a cargar el entorno y redesplegar Course, Menu, Metrics, Subscriptions, Users y Videos. Actualizar solamente el stack compartido no cambia el CORS interno de las Lambdas.

## 12. Exportar URLs de servicios

Las variables no se inventan ni se copian manualmente desde API Gateway:

1. `config/platform-outputs.<ambiente>.env` proviene de los Outputs de `<RESOURCE_PREFIX>-platform-<ambiente>` y contiene Cognito, CloudFront, bucket y grupo administrativo.
2. `config/service-outputs.<ambiente>.env` proviene de los siete stacks `ms-epico-<servicio>-<ambiente>` y contiene las siete URLs de API Gateway.
3. `export-amplify-environments.ps1` combina ambos contratos y genera los mapas que se cargarán en las ramas Amplify.

```powershell
.\scripts\export-cloudformation-outputs.ps1 `
  -StackName "$($env:RESOURCE_PREFIX)-platform-$($env:ENVIRONMENT)"
.\scripts\export-serverless-outputs.ps1
.\scripts\validate-environment.ps1 -RequirePlatformOutputs -RequireServiceOutputs
.\scripts\export-amplify-environments.ps1
```

Se generan:

| Archivo local | Destino exacto |
| --- | --- |
| `config/amplify-client-<ambiente>-env.json` | Rama del portal público en `epico-client-<ambiente>` |
| `config/amplify-admin-<ambiente>-env.json` | Rama de la consola administrativa en `epico-admin-<ambiente>` |

El mapa público contiene `VITE_BASE_PATH`, las siete variables `VITE_*_API_URL` y `VITE_MEDIA_CDN_URL`. El mapa administrativo contiene las URLs y además `VITE_COGNITO_USER_POOL_ID`, `VITE_COGNITO_CLIENT_ID` y `VITE_COGNITO_ADMINISTRATORS_GROUP`.

Revisar ambos archivos:

```powershell
Get-Content "config/amplify-client-$($env:ENVIRONMENT)-env.json"
Get-Content "config/amplify-admin-$($env:ENVIRONMENT)-env.json"
```

No son archivos `.env` del código fuente ni se suben a GitHub. Son contratos locales ignorados por Git. Los valores `VITE_*` se incorporan al JavaScript del navegador y, por tanto, son públicos. Nunca deben contener contraseñas, tokens, Access Keys, `COGNITO_CLIENT_SECRET_ID` ni el valor del Client Secret.

Revisar que los JSON de Amplify contengan solamente URLs, IDs públicos, CDN y grupo administrativo; nunca secretos.

## 13. Configurar y publicar frontends

### 13.1 Identificar aplicaciones, ramas y mapas

Ejecutar primero la vista previa:

```powershell
.\scripts\configure-amplify-branches.ps1 `
  -Environment $env:ENVIRONMENT `
  -DeploymentBranch $env:DEPLOYMENT_BRANCH `
  -StackName "$($env:RESOURCE_PREFIX)-amplify-$($env:ENVIRONMENT)"
```

El script consulta los Outputs del stack y debe mostrar:

- `cliente`: App ID, rama y `config/amplify-client-<ambiente>-env.json`.
- `administrador`: App ID, rama y `config/amplify-admin-<ambiente>-env.json`.

Ambas aplicaciones deben apuntar exactamente a `DEPLOYMENT_BRANCH`. Detenerse si la rama no existe en GitHub o un Output muestra otro valor.

#### Cambiar la rama desplegada

1. Publicar primero la rama nueva, con el mismo nombre, en los repositorios padre, portal, administrador y microservicios involucrados.
2. Cambiar `DEPLOYMENT_BRANCH` en `.env`; no editar el JSON generado.
3. Abrir una terminal nueva y ejecutar `sync-deployment-parameters.ps1`.
4. Actualizar `<RESOURCE_PREFIX>-amplify-<ENVIRONMENT>` mediante Change Set.
5. Regenerar `config/amplify-outputs.<ambiente>.env` y confirmar las dos claves `*_AMPLIFY_BRANCH`.
6. Si cambian las URLs, entregar los orígenes nuevos al cliente para actualizar CORS del stack compartido.
7. Redesplegar los seis microservicios de negocio con el nuevo CORS.
8. Regenerar mapas, cargar variables de rama y publicar nuevamente los frontends.

No crear una rama accidental para encubrir una diferencia de configuración. La rama desplegada siempre procede explícitamente de `DEPLOYMENT_BRANCH`.

### 13.2 Cargar las variables en las ramas Amplify

La vía recomendada es el script, no un `.env` y no la escritura manual:

```powershell
.\scripts\configure-amplify-branches.ps1 `
  -Environment $env:ENVIRONMENT `
  -StackName "$($env:RESOURCE_PREFIX)-amplify-$($env:ENVIRONMENT)" `
  -Execute
```

El comando usa `aws amplify update-branch`: carga cada JSON en **Environment variables de la rama correspondiente**, no modifica los repositorios, no inicia builds y mantiene `EnableAutoBuild=false`.

Para verificarlo en la consola web:

1. AWS Console → **AWS Amplify** → región `us-east-1`.
2. Abrir `epico-admin-<ambiente>` o `epico-client-<ambiente>`.
3. Elegir **Hosting** → **Environment variables** → **Manage variables**.
4. Confirmar las claves del JSON correspondiente y su rama.
5. No añadir secretos ni aplicar accidentalmente valores de otro cliente o ambiente.

La consola se utiliza para verificar o como contingencia. Una corrección manual debe reflejarse después en la automatización para evitar divergencias.

Referencia oficial: [Configurar variables de entorno en AWS Amplify Hosting](https://docs.aws.amazon.com/amplify/latest/userguide/setting-env-vars.html).

### 13.3 Verificar por AWS CLI

```powershell
$amplifyStack = "$($env:RESOURCE_PREFIX)-amplify-$($env:ENVIRONMENT)"

$adminAppId = aws cloudformation describe-stacks `
  --stack-name $amplifyStack --region us-east-1 `
  --query "Stacks[0].Outputs[?OutputKey=='AdminAmplifyAppId'].OutputValue | [0]" `
  --output text
$adminBranch = aws cloudformation describe-stacks `
  --stack-name $amplifyStack --region us-east-1 `
  --query "Stacks[0].Outputs[?OutputKey=='AdminAmplifyBranch'].OutputValue | [0]" `
  --output text

$clientAppId = aws cloudformation describe-stacks `
  --stack-name $amplifyStack --region us-east-1 `
  --query "Stacks[0].Outputs[?OutputKey=='ClientAmplifyAppId'].OutputValue | [0]" `
  --output text
$clientBranch = aws cloudformation describe-stacks `
  --stack-name $amplifyStack --region us-east-1 `
  --query "Stacks[0].Outputs[?OutputKey=='ClientAmplifyBranch'].OutputValue | [0]" `
  --output text

aws amplify get-branch --app-id $adminAppId --branch-name $adminBranch `
  --region us-east-1 --query "branch.environmentVariables"
aws amplify get-branch --app-id $clientAppId --branch-name $clientBranch `
  --region us-east-1 --query "branch.environmentVariables"
```

El administrativo debe contener las tres variables Cognito del punto 12. Ninguna rama debe contener un Client Secret.

### 13.4 Publicar primero el administrativo

```powershell
$adminJob = aws amplify start-job `
  --app-id $adminAppId --branch-name $adminBranch `
  --job-type RELEASE --region us-east-1 `
  --output json | ConvertFrom-Json

$adminJobId = $adminJob.jobSummary.jobId
$adminJobId

aws amplify get-job `
  --app-id $adminAppId --branch-name $adminBranch `
  --job-id $adminJobId --region us-east-1 `
  --query "job.summary.[status,startTime,endTime]" `
  --output table
```

Repetir `get-job` hasta obtener `SUCCEED`. Si termina en `FAILED` o `CANCELLED`, detenerse y revisar el log del job en Amplify. No publicar el portal público. Con el administrativo exitoso, validar login Cognito, pertenencia al grupo administrador y consumo de las siete APIs.

### 13.5 Publicar después el portal público

No reutilizar `$clientAppId` ni `$clientBranch` de un intento anterior. Consultarlos nuevamente desde el stack inmediatamente antes del build y validar la rama:

```powershell
$clientAppId = aws cloudformation describe-stacks `
  --stack-name $amplifyStack --region us-east-1 `
  --query "Stacks[0].Outputs[?OutputKey=='ClientAmplifyAppId'].OutputValue | [0]" `
  --output text

$clientBranch = aws cloudformation describe-stacks `
  --stack-name $amplifyStack --region us-east-1 `
  --query "Stacks[0].Outputs[?OutputKey=='ClientAmplifyBranch'].OutputValue | [0]" `
  --output text

$clientAppId
$clientBranch

if ($clientBranch -ne $env:DEPLOYMENT_BRANCH) {
  throw "La rama cliente '$clientBranch' no corresponde a DEPLOYMENT_BRANCH='$($env:DEPLOYMENT_BRANCH)'."
}

aws amplify get-branch `
  --app-id $clientAppId --branch-name $clientBranch `
  --region us-east-1 `
  --query "branch.[branchName,enableAutoBuild]" `
  --output table

$clientJob = aws amplify start-job `
  --app-id $clientAppId --branch-name $clientBranch `
  --job-type RELEASE --region us-east-1 `
  --output json | ConvertFrom-Json

$clientJobId = $clientJob.jobSummary.jobId
$clientJobId

aws amplify get-job `
  --app-id $clientAppId --branch-name $clientBranch `
  --job-id $clientJobId --region us-east-1 `
  --query "job.summary.[status,startTime,endTime]" `
  --output table
```

Esperar `SUCCEED`, abrir la URL pública y probar navegación, autenticación, APIs y contenido de CloudFront. Registrar App IDs, ramas, Job IDs, commits, estados y URLs. No activar auto-build hasta que QA haya sido aceptado y exista una decisión operativa explícita.

Resumen de control:

1. Cargar las variables generadas en las ramas Amplify.
2. Confirmar `VITE_COGNITO_USER_POOL_ID`, `VITE_COGNITO_CLIENT_ID` y `VITE_COGNITO_ADMINISTRATORS_GROUP` en el administrativo.
3. Mantener Client Secret fuera de variables Vite.
4. Iniciar primero el build administrativo.
5. Validar login y APIs.
6. Iniciar después el build público.
7. Registrar IDs de jobs y resultados.

## 14. Crear el administrador inicial

```powershell
$initialPassword = Read-Host 'Clave inicial' -AsSecureString
.\scripts\create-initial-cognito-administrator.ps1 `
  -Execute -Email administrador@epico.example `
  -Name 'Administrador EPICO' -Password $initialPassword `
  -ExpectedAccountId 123456789012
```

El comando debe ejecutarse con una sesión vigente de `<RESOURCE_PREFIX>-deployment-<ambiente>`. En la primera ejecución, `admin-get-user` devuelve internamente `UserNotFoundException`; el script lo interpreta como alta nueva, crea el usuario con mensajes suprimidos, establece la contraseña permanente y lo agrega al grupo administrativo. Cualquier otro error de consulta detiene el proceso y muestra la causa de AWS.

Entregar usuario y clave por canales separados. No registrar la contraseña. Solicitar cambio inmediato.

## 15. Pruebas y devolución al cliente

Probar salud de APIs, consola administrativa, portal público, rechazo de usuario común, operaciones principales, S3 y CloudFront. Entregar URLs, inventario y resultados para que el cliente continúe con aceptación; no entregar outputs secretos, código o manifiestos internos.

## 16. Cierre

- Confirmar repositorios limpios y bitácora interna.
- Guardar recuperación en almacenamiento FSG restringido.
- Cerrar sesión AWS y limpiar variables del proceso.
- Solicitar al cliente revocar la sesión/asignación temporal.
- Eliminar perfiles locales temporales cuando ya no sean necesarios.
- Conservar únicamente documentación operativa autorizada.

## 17. Procedimiento interno para futuras actualizaciones

La promoción obligatoria es `develop` → `qa` → aceptación del cliente → `production`. Cada paso usa su rama, ambiente y autorización temporal. Registrar el commit aprobado en cada etapa y verificar que sea el mismo que se promueve; no reconstruir desde una rama con cambios adicionales.

### 17.1 Registrar y acotar la solicitud

Crear un ticket interno que enlace la solicitud aprobada del cliente y defina:

- Repositorios/componentes afectados.
- Tipo de cambio: código, configuración, infraestructura, dependencias o datos.
- Criterios de aceptación.
- Riesgos y compatibilidad hacia atrás.
- Ventana, responsables y canal de incidentes.
- Plan de rollback probado.

No iniciar desarrollo o despliegue con alcance ambiguo.

### 17.2 Preparar la versión en repositorios privados

1. Actualizar las ramas estables locales.
2. Crear una rama de feature/corrección con nombre común en los repositorios afectados.
3. Implementar y probar sin modificar `main` directamente.
4. Ejecutar build, pruebas, escaneo de secretos y validaciones de infraestructura.
5. Commit y push primero en cada repositorio hijo.
6. Actualizar los gitlinks del padre con commits exactos.
7. Ejecutar CI del padre y obtener aprobación del cambio.
8. Registrar una versión candidata y la lista exacta de commits internos.

El cliente recibe el alcance y la versión funcional, no hashes internos ni acceso al código salvo obligación contractual expresa.

### 17.3 Solicitar acceso temporal nuevo

Solicitar al cliente una nueva asignación SSO temporal para la ventana. Nunca reutilizar credenciales copiadas de una intervención anterior. Verificar:

```powershell
aws sso login --profile epico-provider
aws sts get-caller-identity --profile epico-provider
```

Luego asumir `<RESOURCE_PREFIX>-deployment-<ambiente>` y confirmar Account ID/región. Si faltan permisos, documentar la acción IAM exacta y enviar al cliente un Change Set de la plantilla; no pedir permisos administrativos genéricos.

### 17.4 Construir el plan de cambio

Clasificar el despliegue:

- Solo microservicio: desplegar únicamente los servicios afectados y dependencias contractuales.
- Solo frontend: publicar únicamente la aplicación/rama afectada.
- Contrato compartido: coordinar primero infraestructura/outputs y después consumidores.
- Infraestructura base: el cliente ejecuta el Change Set con asistencia FSG.
- Cambio destructivo o de datos: requiere aprobación adicional y respaldo verificable.

Documentar orden, duración, verificación y punto de no retorno.

### 17.5 Preflight y recuperación

Antes de escribir en AWS:

- Confirmar repositorios limpios y commits aprobados.
- Ejecutar `npm ci`, builds y pruebas.
- Validar outputs y secretos sin mostrar valores.
- Consultar estado de stacks y jobs Amplify.
- Capturar manifiesto de recuperación de cada servicio afectado.
- Confirmar PITR de tablas y versionado S3.
- Guardar la referencia del último despliegue exitoso.

### 17.6 Desplegar selectivamente

Durante la ventana:

1. Anunciar inicio al cliente.
2. Desplegar un componente a la vez.
3. Revisar estado CloudFormation/Lambda/API antes del siguiente.
4. Exportar outputs si cambió algún contrato.
5. Actualizar variables Amplify solamente si corresponde.
6. Publicar el frontend afectado después de sus APIs.
7. Ejecutar smoke tests inmediatamente.
8. Detenerse ante el primer error.

No ejecutar el despliegue completo si el alcance aprobado es parcial, salvo dependencia técnica documentada.

### 17.7 Reversión

Si falla una verificación:

- No continuar con componentes pendientes.
- Esperar/validar rollback automático de CloudFormation.
- Para código, redeployar el commit anterior aprobado.
- Para frontend, reconstruir la versión anterior o revertir la rama autorizada.
- Para DynamoDB, restaurar PITR a una tabla nueva y coordinar el cambio de referencia.
- Para S3, recuperar por `VersionId`.
- No usar `serverless remove`.

Registrar tiempos, causa, recursos afectados y decisión del cliente cuando existan datos involucrados.

### 17.8 Entrega y cierre

Después de pruebas técnicas, entregar al cliente:

- Componentes y funcionalidades actualizadas.
- Hora inicial/final y resultado.
- URLs o cambios operativos visibles.
- Resultado de pruebas y monitoreo.
- Incidentes, rollback o pendientes.
- Recomendación de observación posterior.

Solicitar aceptación funcional y revocación del permiso temporal. Cerrar sesión AWS, limpiar variables/perfiles temporales, proteger manifiestos y actualizar la bitácora interna de FSG.

## 18. Fase final: desinstalar completamente un ambiente

Esta fase es destructiva y no forma parte de una actualización ni de un rollback. Se ejecuta únicamente con una solicitud escrita del cliente que identifique `AWS Account ID`, `RESOURCE_PREFIX`, `ENVIRONMENT`, ventana y autorización para eliminar datos. Repetirla por separado para `develop`, `qa` y `production`; nunca utilizar comodines entre clientes o ambientes.

### 18.1 Aprobar respaldo y alcance

Antes de borrar:

1. Confirmar si deben exportarse usuarios Cognito, objetos/versiones S3 o tablas DynamoDB.
2. Entregar y verificar los respaldos acordados.
3. Registrar Outputs, App IDs, nombres de stacks, buckets, User Pool, secretos y tablas.
4. Cargar `.env` y comprobar cuenta, rol, prefijo y ambiente:

```powershell
. .\scripts\load-environment.ps1 -Quiet
aws sts get-caller-identity

$resourcePrefix = $env:RESOURCE_PREFIX
$environment = $env:ENVIRONMENT
$amplifyStack = "$resourcePrefix-amplify-$environment"
$platformStack = "$resourcePrefix-platform-$environment"
$roleStack = "$resourcePrefix-deployment-role-$environment"
```

Detenerse si algún valor no coincide con la autorización. La retención de datos existe precisamente para impedir que eliminar un stack borre silenciosamente información.

### 18.2 Eliminar frontends Amplify

Conservar el secreto GitHub hasta terminar este punto:

```powershell
aws cloudformation delete-stack `
  --stack-name $amplifyStack --region $env:AWS_REGION
aws cloudformation wait stack-delete-complete `
  --stack-name $amplifyStack --region $env:AWS_REGION
```

Confirmar en Amplify que las dos aplicaciones del ambiente ya no existen. Esto no elimina ramas ni repositorios GitHub.

### 18.3 Eliminar microservicios

Cargar la clave Serverless y eliminar en orden inverso al despliegue:

```powershell
.\scripts\import-serverless-access-key.ps1 `
  -SecretId $env:SERVERLESS_ACCESS_KEY_SECRET_ID `
  -Region $env:AWS_REGION

$services = @(
  'ms-aprendamosgye-videos',
  'ms-aprendamosgye-users',
  'ms-aprendamosgye-subscriptions',
  'ms-aprendamosgye-metrics',
  'ms-aprendamosgye-menu',
  'ms-aprendamosgye-course',
  'ms-aprendamosgye-auth'
)

foreach ($service in $services) {
  Push-Location "services\$service"
  npx serverless remove --stage $environment --region $env:AWS_REGION
  $removeExitCode = $LASTEXITCODE
  Pop-Location
  if ($removeExitCode -ne 0) { throw "Falló la eliminación de $service" }
}
```

`serverless remove` está prohibido como mecanismo de rollback, pero es correcto en esta fase de desinstalación expresamente autorizada. Las tablas con `DeletionPolicy: Retain` continuarán existiendo y se atienden en el punto 18.5.

### 18.4 Eliminar infraestructura compartida

Antes de borrar el stack, conservar localmente sus Outputs para identificar los recursos retenidos:

```powershell
$platform = aws cloudformation describe-stacks `
  --stack-name $platformStack --region $env:AWS_REGION `
  --query 'Stacks[0].Outputs' --output json | ConvertFrom-Json

$userPoolId = ($platform | Where-Object OutputKey -eq 'CognitoUserPoolId').OutputValue
$mediaBucket = ($platform | Where-Object OutputKey -eq 'MediaBucketName').OutputValue
$clientSecretId = ($platform | Where-Object OutputKey -eq 'CognitoClientSecretId').OutputValue

aws cloudformation delete-stack `
  --stack-name $platformStack --region $env:AWS_REGION
aws cloudformation wait stack-delete-complete `
  --stack-name $platformStack --region $env:AWS_REGION
```

CloudFront puede tardar varios minutos en deshabilitar y eliminar la distribución. No continuar si el stack termina en `DELETE_FAILED`; revisar sus eventos y resolver el recurso exacto.

### 18.5 Eliminar recursos retenidos

CloudFormation conserva deliberadamente Cognito, el secreto del cliente confidencial, el bucket multimedia y diez tablas DynamoDB. Después de validar los respaldos:

1. Vaciar el bucket S3 incluyendo **todas las versiones y marcadores de eliminación**; comprobar que quede vacío y eliminarlo.
2. Eliminar el User Pool identificado por `$userPoolId`.
3. Eliminar el secreto identificado por `$clientSecretId`.
4. Enumerar las tablas cuyo nombre termine en `-$environment`, confirmar sus tags `Client` y `Environment`, y eliminar únicamente las pertenecientes a `$resourcePrefix`.

Ejemplos para los recursos ya identificados:

```powershell
aws cognito-idp delete-user-pool `
  --user-pool-id $userPoolId --region $env:AWS_REGION

aws secretsmanager delete-secret `
  --secret-id $clientSecretId `
  --force-delete-without-recovery `
  --region $env:AWS_REGION
```

Para S3 y DynamoDB se recomienda usar la consola AWS durante esta operación excepcional: mostrar versiones, tags y nombre completo antes de confirmar. No ejecutar eliminaciones por prefijos parciales, globs ni resultados sin revisar.

### 18.6 Eliminar secretos operativos y residuos

Solo después de eliminar Amplify y todos los microservicios:

```powershell
aws secretsmanager delete-secret `
  --secret-id $env:GITHUB_AMPLIFY_SECRET_ID `
  --force-delete-without-recovery `
  --region $env:AWS_REGION

aws secretsmanager delete-secret `
  --secret-id $env:SERVERLESS_ACCESS_KEY_SECRET_ID `
  --force-delete-without-recovery `
  --region $env:AWS_REGION
```

Revisar y eliminar, si existen y coinciden exactamente con cliente/ambiente:

- parámetros bajo `/$resourcePrefix/$environment`;
- log groups de Lambdas y API Gateway;
- buckets de despliegue Serverless;
- alarmas, dashboards o suscripciones creadas fuera de CloudFormation;
- versiones de Lambda o capas no asociadas.

Revocar también el token o autorización GitHub utilizada por Amplify si no sirve para otro ambiente autorizado.

### 18.7 Eliminar el rol temporal al final

Cerrar la sesión del rol de despliegue. En una terminal nueva, iniciar sesión con el perfil bootstrap del cliente y eliminar el stack del rol:

```powershell
aws sso login --profile epico-bootstrap
aws cloudformation delete-stack `
  --stack-name $roleStack `
  --profile epico-bootstrap `
  --region $env:AWS_REGION
aws cloudformation wait stack-delete-complete `
  --stack-name $roleStack `
  --profile epico-bootstrap `
  --region $env:AWS_REGION
```

El nombre del perfil es local y puede variar; no es un nombre de recurso AWS.

### 18.8 Verificación de cuenta limpia

Confirmar con el cliente:

- no existen stacks `<RESOURCE_PREFIX>-*‑<ENVIRONMENT>` ni `ms-<RESOURCE_PREFIX>-*‑<ENVIRONMENT>`;
- no existen aplicaciones Amplify, APIs, Lambdas, distribuciones, User Pools, buckets, tablas, secretos, parámetros ni roles del ambiente;
- la búsqueda por tags `Client=<TAG_CLIENT>` y `Environment=<ENVIRONMENT>` no devuelve recursos de la solución;
- GitHub no conserva autorizaciones innecesarias;
- los respaldos y el acta de eliminación tienen ubicación y retención acordadas.

Entregar un inventario final de lo eliminado y de cualquier elemento conservado por decisión expresa del cliente. Solo entonces cerrar y revocar el acceso temporal.
