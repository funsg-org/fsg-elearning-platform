# Manual interno del proveedor para desplegar microservicios y frontends

## 1. Alcance

Este runbook es exclusivo de FSG. Comienza cuando el cliente ya creó el rol y la infraestructura compartida, y entregó acceso temporal y outputs no sensibles. No crea la cuenta AWS ni solicita credenciales root.

## 2. Información que debe recibir FSG

- Account ID de 12 dígitos y región `us-east-1`.
- ARN de `epico-deployment-production`.
- Método SSO temporal; excepcionalmente Access Keys de un usuario temporal dedicado.
- Outputs de Cognito, S3 y CloudFront.
- IDs/URLs de las dos aplicaciones Amplify.
- Correo y nombre del administrador inicial.
- CostCenter definitivo.
- Copia no sensible de los parámetros aprobados para poder ejecutar el preflight local.
- Ventana autorizada de despliegue.

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
.\scripts\enter-deployment-role.ps1 `
  -RoleArn arn:aws:iam::123456789012:role/epico-deployment-production `
  -AwsProfile epico-provider
aws sts get-caller-identity
```

Confirmar `assumed-role/epico-deployment-production` y la cuenta esperada.

## 6. Incorporar outputs entregados

Crear localmente `config/platform-outputs.env`, sin confirmar en Git:

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

## 7. Preparar Serverless Framework

Crear una Access Key dedicada desde la organización FSG en Serverless Dashboard (`Settings` → `Access Keys`). No pedir al cliente que la genere ni entregársela.

Guardar la clave en la cuenta del cliente mediante entrada segura:

```powershell
.\scripts\initialize-serverless-access-key-secret.ps1 `
  -Execute -ExpectedAccountId 123456789012 `
  -CostCenter FSG-ELRN-EPICO-PROD
```

El script solicita la clave y crea `epico/production/serverless/access-key` sin mostrarla.

## 8. Preflight de proyectos

Crear localmente, a partir de los ejemplos, `infrastructure/parameters.json` y `infrastructure/amplify-parameters.json` con los mismos valores no sensibles aprobados por el cliente. Estos archivos permanecen ignorados por Git.

```powershell
.\scripts\test-deployment-readiness.ps1 `
  -ExpectedAccountId 123456789012 `
  -ExpectedDeploymentRoleArn arn:aws:iam::123456789012:role/epico-deployment-production
```

Verificar rama, repositorios limpios, Serverless 4.39.0, secreto, outputs, región y cuenta.

## 9. Instalar dependencias sin tocar AWS

En cada servicio ejecutar `npm ci --ignore-scripts`. Si uno falla, detener la ventana y no desplegar ningún servicio.

## 10. Desplegar los siete microservicios

Orden obligatorio:

1. Auth
2. Course
3. Menu
4. Metrics
5. Subscriptions
6. Users
7. Videos

Antes de cada `npx serverless deploy`, capturar el manifiesto con `capture-service-recovery-manifest.ps1`. Usar `--stage production --region us-east-1`. Detenerse ante el primer error y generar las instrucciones de recuperación; no usar `serverless remove` como rollback.

## 11. Exportar URLs de servicios

```powershell
.\scripts\export-serverless-outputs.ps1
.\scripts\validate-environment.ps1 -RequirePlatformOutputs -RequireServiceOutputs
.\scripts\export-amplify-environments.ps1
```

Revisar que los JSON de Amplify contengan solamente URLs, IDs públicos, CDN y grupo administrativo; nunca secretos.

## 12. Configurar y publicar frontends

1. Cargar las variables generadas en las ramas Amplify.
2. Confirmar `VITE_COGNITO_USER_POOL_ID`, `VITE_COGNITO_CLIENT_ID` y `VITE_COGNITO_ADMINISTRATORS_GROUP` en el administrativo.
3. Mantener Client Secret fuera de variables Vite.
4. Iniciar primero el build administrativo.
5. Validar login y APIs.
6. Iniciar después el build público.
7. Registrar IDs de jobs y resultados.

## 13. Crear el administrador inicial

```powershell
$initialPassword = Read-Host 'Clave inicial' -AsSecureString
.\scripts\create-initial-cognito-administrator.ps1 `
  -Execute -Email administrador@epico.example `
  -Name 'Administrador EPICO' -Password $initialPassword `
  -ExpectedAccountId 123456789012
```

Entregar usuario y clave por canales separados. No registrar la contraseña. Solicitar cambio inmediato.

## 14. Pruebas y devolución al cliente

Probar salud de APIs, consola administrativa, portal público, rechazo de usuario común, operaciones principales, S3 y CloudFront. Entregar URLs, inventario y resultados para que el cliente continúe con aceptación; no entregar outputs secretos, código o manifiestos internos.

## 15. Cierre

- Confirmar repositorios limpios y bitácora interna.
- Guardar recuperación en almacenamiento FSG restringido.
- Cerrar sesión AWS y limpiar variables del proceso.
- Solicitar al cliente revocar la sesión/asignación temporal.
- Eliminar perfiles locales temporales cuando ya no sean necesarios.
- Conservar únicamente documentación operativa autorizada.
