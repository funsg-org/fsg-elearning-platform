# Manual interno del proveedor para desplegar microservicios y frontends

## 1. Alcance

Este runbook es exclusivo de FSG y se ejecuta en dos momentos. La **Fase A** comienza cuando el cliente ya creó el rol limitado: FSG prepara Amplify sin publicar y devuelve sus URLs. FSG se detiene mientras el cliente crea la infraestructura compartida. La **Fase B** comienza después de que Cognito, S3 y CloudFront existen y continúa con microservicios y frontends. No crea la cuenta AWS ni solicita credenciales root.

## 2. Seleccionar el ambiente antes de operar

Copiar `.env.example` como `.env` y seleccionar el ambiente:

```dotenv
ENVIRONMENT=qa
```

No es necesario pasar `-Environment`: todos los scripts leen `.env`. Para cambiar a producción, cerrar la terminal, cambiar únicamente `ENVIRONMENT=production` y abrir una terminal nueva. Los `parameters.json` se regeneran; los Outputs generados conservan el ambiente en su nombre para evitar mezclas.

## 3. Información que debe recibir FSG

### Para la Fase A — todavía no existen Cognito, S3 ni CloudFront

- Account ID de 12 dígitos y región `us-east-1`.
- ARN de `epico-deployment-<ambiente>`.
- Método SSO temporal; excepcionalmente Access Keys de un usuario temporal dedicado.
- CostCenter definitivo.
- Ventana autorizada de despliegue.

### Para la Fase B — después de la infraestructura compartida

- Confirmación `CREATE_COMPLETE` de `epico-platform-<ambiente>`.
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
git switch feature/epico-deployment-readiness
git submodule sync --recursive
git submodule update --init --recursive
git status
git submodule status
```

El código permanece en infraestructura FSG y no se copia al cliente.

## 5. Asumir el rol limitado

```powershell
. .\scripts\load-environment.ps1 -Quiet
$accountId = aws sts get-caller-identity --query Account --output text --profile epico-provider
$deploymentRoleArn = "arn:aws:iam::$accountId`:role/epico-deployment-$env:ENVIRONMENT"

.\scripts\enter-deployment-role.ps1 `
  -RoleArn $deploymentRoleArn `
  -AwsProfile epico-provider
aws sts get-caller-identity
```

Confirmar `assumed-role/epico-deployment-<ambiente>` y la cuenta esperada.

El comando `enter-deployment-role.ps1` y todos los comandos de las fases siguientes deben ejecutarse en **la misma ventana de PowerShell**. Las credenciales STS se guardan solamente en la memoria de ese proceso. Antes de crear secretos, comprobar otra vez:

```powershell
aws sts get-caller-identity --query Arn --output text
```

El resultado debe contener `assumed-role/epico-deployment-<ambiente>/`. Si muestra `user/`, `AWSReservedSSO_` u otro rol, detenerse y volver a ejecutar `enter-deployment-role.ps1`.

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

Si un intento anterior dejó `epico-amplify-qa` en `ROLLBACK_COMPLETE`, corregir primero el token y luego eliminar únicamente ese stack fallido:

```powershell
aws cloudformation delete-stack --stack-name epico-amplify-qa --region us-east-1
aws cloudformation wait stack-delete-complete --stack-name epico-amplify-qa --region us-east-1
```

La eliminación del stack requiere confirmación consciente. No ejecutar estos comandos si el stack contiene recursos válidos que deban conservarse.

1. Confirmar que se generó `config/amplify-outputs.<ambiente>.env` y que contiene las dos URLs `amplifyapp.com`.
2. Entregar al cliente las URLs, nombre del stack y confirmación de que no se inició ningún build.
3. **DETENERSE.** No ejecutar todavía los pasos siguientes. El cliente debe completar CORS y crear `epico-platform-<ambiente>`.

Después de comprobar que ambas aplicaciones Amplify acceden correctamente a los repositorios, registrar la fecha de expiración. Revocar o rotar el token cuando termine su vigencia o deje de ser necesario; no reutilizarlo para otros clientes.

## 7. Fase B: incorporar Outputs de infraestructura compartida

Reanudar únicamente después de que el cliente confirme `CREATE_COMPLETE`.

Opción recomendada, exportarlos directamente desde CloudFormation:

```powershell
. .\scripts\load-environment.ps1 -Quiet
.\scripts\export-cloudformation-outputs.ps1 `
  -StackName "epico-platform-$env:ENVIRONMENT"
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

Crear localmente, a partir de los ejemplos, `infrastructure/parameters.json` y `infrastructure/amplify-parameters.json` con los mismos valores no sensibles aprobados por el cliente. Estos archivos permanecen ignorados por Git.

```powershell
.\scripts\test-deployment-readiness.ps1 `
  -ExpectedAccountId 123456789012 `
  -ExpectedDeploymentRoleArn arn:aws:iam::123456789012:role/epico-deployment-production
```

Verificar rama, repositorios limpios, Serverless 4.39.0, secreto, outputs, región y cuenta.

## 10. Instalar dependencias sin tocar AWS

En cada servicio ejecutar `npm ci --ignore-scripts`. Si uno falla, detener la ventana y no desplegar ningún servicio.

## 11. Desplegar los siete microservicios

Orden obligatorio:

1. Auth
2. Course
3. Menu
4. Metrics
5. Subscriptions
6. Users
7. Videos

Antes de cada `npx serverless deploy`, capturar el manifiesto con `capture-service-recovery-manifest.ps1`. Usar `--stage production --region us-east-1`. Detenerse ante el primer error y generar las instrucciones de recuperación; no usar `serverless remove` como rollback.

## 12. Exportar URLs de servicios

```powershell
.\scripts\export-serverless-outputs.ps1
.\scripts\validate-environment.ps1 -RequirePlatformOutputs -RequireServiceOutputs
.\scripts\export-amplify-environments.ps1
```

Revisar que los JSON de Amplify contengan solamente URLs, IDs públicos, CDN y grupo administrativo; nunca secretos.

## 13. Configurar y publicar frontends

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

La promoción obligatoria es QA → aceptación del cliente → producción. Deben ser dos ventanas y dos permisos temporales diferenciados. Registrar el commit aprobado en QA y verificar que sea el mismo que se despliega en producción; no reconstruir desde una rama con cambios adicionales.

### 16.1 Registrar y acotar la solicitud

Crear un ticket interno que enlace la solicitud aprobada del cliente y defina:

- Repositorios/componentes afectados.
- Tipo de cambio: código, configuración, infraestructura, dependencias o datos.
- Criterios de aceptación.
- Riesgos y compatibilidad hacia atrás.
- Ventana, responsables y canal de incidentes.
- Plan de rollback probado.

No iniciar desarrollo o despliegue con alcance ambiguo.

### 16.2 Preparar la versión en repositorios privados

1. Actualizar las ramas estables locales.
2. Crear una rama de feature/corrección con nombre común en los repositorios afectados.
3. Implementar y probar sin modificar `main` directamente.
4. Ejecutar build, pruebas, escaneo de secretos y validaciones de infraestructura.
5. Commit y push primero en cada repositorio hijo.
6. Actualizar los gitlinks del padre con commits exactos.
7. Ejecutar CI del padre y obtener aprobación del cambio.
8. Registrar una versión candidata y la lista exacta de commits internos.

El cliente recibe el alcance y la versión funcional, no hashes internos ni acceso al código salvo obligación contractual expresa.

### 16.3 Solicitar acceso temporal nuevo

Solicitar al cliente una nueva asignación SSO temporal para la ventana. Nunca reutilizar credenciales copiadas de una intervención anterior. Verificar:

```powershell
aws sso login --profile epico-provider
aws sts get-caller-identity --profile epico-provider
```

Luego asumir `epico-deployment-production` y confirmar Account ID/región. Si faltan permisos, documentar la acción IAM exacta y enviar al cliente un Change Set de la plantilla; no pedir permisos administrativos genéricos.

### 16.4 Construir el plan de cambio

Clasificar el despliegue:

- Solo microservicio: desplegar únicamente los servicios afectados y dependencias contractuales.
- Solo frontend: publicar únicamente la aplicación/rama afectada.
- Contrato compartido: coordinar primero infraestructura/outputs y después consumidores.
- Infraestructura base: el cliente ejecuta el Change Set con asistencia FSG.
- Cambio destructivo o de datos: requiere aprobación adicional y respaldo verificable.

Documentar orden, duración, verificación y punto de no retorno.

### 16.5 Preflight y recuperación

Antes de escribir en AWS:

- Confirmar repositorios limpios y commits aprobados.
- Ejecutar `npm ci`, builds y pruebas.
- Validar outputs y secretos sin mostrar valores.
- Consultar estado de stacks y jobs Amplify.
- Capturar manifiesto de recuperación de cada servicio afectado.
- Confirmar PITR de tablas y versionado S3.
- Guardar la referencia del último despliegue exitoso.

### 16.6 Desplegar selectivamente

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

### 16.7 Reversión

Si falla una verificación:

- No continuar con componentes pendientes.
- Esperar/validar rollback automático de CloudFormation.
- Para código, redeployar el commit anterior aprobado.
- Para frontend, reconstruir la versión anterior o revertir la rama autorizada.
- Para DynamoDB, restaurar PITR a una tabla nueva y coordinar el cambio de referencia.
- Para S3, recuperar por `VersionId`.
- No usar `serverless remove`.

Registrar tiempos, causa, recursos afectados y decisión del cliente cuando existan datos involucrados.

### 16.8 Entrega y cierre

Después de pruebas técnicas, entregar al cliente:

- Componentes y funcionalidades actualizadas.
- Hora inicial/final y resultado.
- URLs o cambios operativos visibles.
- Resultado de pruebas y monitoreo.
- Incidentes, rollback o pendientes.
- Recomendación de observación posterior.

Solicitar aceptación funcional y revocación del permiso temporal. Cerrar sesión AWS, limpiar variables/perfiles temporales, proteger manifiestos y actualizar la bitácora interna de FSG.
