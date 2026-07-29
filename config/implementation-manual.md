# Manual de coordinación de la implementación

> Este documento fue dividido para reflejar correctamente las responsabilidades. No debe utilizarse como runbook operativo. El cliente utiliza `client-installation-manual.md`; el proveedor utiliza `provider-project-deployment-manual.md`; la entrega final se registra en `client-deployment-handover.md`.

Este runbook instala FSG E-learning para EPICO en una cuenta AWS ya creada. Es documentación interna de FSG y debe ser ejecutado exclusivamente por el desarrollador/proveedor responsable. No es un manual para el cliente.

El código fuente, repositorios, submódulos, scripts, archivos locales de parámetros, credenciales de GitHub, credenciales de Serverless y manifiestos técnicos internos permanecen bajo custodia de FSG. El cliente recibe la solución desplegada en su cuenta AWS y la documentación de entrega descrita en `config/client-deployment-handover.md`, sin copia del código fuente.

### División obligatoria de responsabilidades

| Actividad | FSG/proveedor | Cliente |
| --- | --- | --- |
| Custodiar y modificar el código fuente | Responsable exclusivo | Sin acceso |
| Preparar estación, Git, Node, AWS CLI y Serverless | Ejecuta | No instala herramientas |
| Entregar el Account ID y autorizar acceso temporal | Solicita y verifica | Proporciona/autoriza |
| Crear parámetros, roles, secretos y stacks | Ejecuta | No ejecuta scripts |
| Autorizar el uso de la cuenta y políticas de seguridad | Informa impacto | Aprueba |
| Proporcionar dominio/DNS, si aplica | Configura técnicamente | Acredita propiedad y autoriza cambios |
| Crear el administrador inicial | Ejecuta | Designa correo y recibe acceso |
| Probar y documentar la instalación | Ejecuta | Realiza aceptación funcional |
| Recibir inventario, URLs, costos, soporte y operación | Entrega | Recibe |

## 1. Datos y responsables

Registrar antes de comenzar:

- Responsable técnico FSG y responsable autorizador del cliente.
- ID de 12 dígitos de la cuenta AWS destino.
- Correo del primer administrador de EPICO.
- Ventana de despliegue y canal de soporte.
- Centro de costo propuesto: `FSG-ELRN-EPICO-PROD`.

El centro de costo representa empresa, producto, cliente y ambiente. Debe repetirse en todos los archivos de parámetros. Si Finanzas exige otro catálogo, se reemplaza antes del despliegue; nunca se acepta `PENDING`.

## 2. Preparar la estación privada de despliegue FSG

Utilizar una estación FSG o un runner CI/CD administrado por FSG. Si el cliente exige origen de red controlado, se usará una estación FSG autorizada mediante VPN, bastión o mecanismo acordado; no se copiará el repositorio a un equipo del cliente. AWS CLI, Git, Node.js y PowerShell solo se instalan en el entorno de FSG.

## 3. Instalar y comprobar herramientas

```powershell
git --version
node --version
npm --version
aws --version
$PSVersionTable.PSVersion
```

Requisitos:

- Git con lectura de los repositorios privados `funsg-org`.
- Node.js 20.19 o superior.
- AWS CLI v2.
- PowerShell 7 recomendado.
- Acceso HTTPS a GitHub, AWS y Serverless Framework.

No instalar Serverless globalmente: cada microservicio fija `serverless@4.39.0` y usa `npx`.

## 4. Autenticarse en AWS

El mecanismo de autenticación es la forma en que AWS CLI obtiene una sesión inicial. El orden recomendado es AWS IAM Identity Center/SSO, rol corporativo federado y, solo como último recurso, perfil con Access Keys.

### SSO recomendado

```powershell
aws configure sso --profile epico-bootstrap
aws sso login --profile epico-bootstrap
aws sts get-caller-identity --profile epico-bootstrap
```

### Perfil con Access Keys

```powershell
aws configure --profile epico-bootstrap
aws sts get-caller-identity --profile epico-bootstrap
```

Nunca guardar claves en Git, `.env`, documentos o chats. El Account ID devuelto debe ser exactamente el de la instalación.

## 5. Principal autorizado y roles

El principal autorizado es el ARN de la identidad inicial que podrá ejecutar `sts:AssumeRole` sobre el rol de despliegue. Puede ser un usuario IAM o, preferiblemente, un rol SSO:

```text
arn:aws:iam::123456789012:role/AWSReservedSSO_PlatformDeployers_xxxxx
arn:aws:iam::123456789012:user/bootstrap-admin
```

Hay dos niveles:

- Identidad bootstrap: autorizada temporalmente por el cliente y utilizada por FSG una sola vez para crear el rol limitado.
- `<RESOURCE_PREFIX>-deployment-<ENVIRONMENT>`: rol con permisos acotados al cliente y ambiente en `us-east-1`.

No desplegar permanentemente como root ni con `AdministratorAccess`.

## 6. Clonar la versión aprobada en la estación privada FSG

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

Todos los repositorios deben quedar en los commits registrados y sin cambios locales.

No mostrar, transferir ni clonar estos repositorios en equipos o cuentas Git del cliente.

## 7. Crear archivos locales de parámetros

```powershell
Copy-Item .env.example .env
Copy-Item infrastructure/parameters.example.json infrastructure/parameters.json
Copy-Item infrastructure/amplify-parameters.example.json infrastructure/amplify-parameters.json
Copy-Item infrastructure/deployment-role-parameters.example.json infrastructure/deployment-role-parameters.json
```

- `.env`: sobrescrituras no sensibles.
- `parameters.json`: Cognito, S3, CloudFront y Secrets Manager.
- `amplify-parameters.json`: repositorios, rama y Amplify.
- `deployment-role-parameters.json`: principal de confianza y tags del rol.

Estos archivos están ignorados por Git y no deben contener contraseñas ni claves. Reemplazar `PENDING` por `FSG-ELRN-EPICO-PROD` en todos. Reemplazar también el ARN de ejemplo por el principal real.

## 8. Crear el rol limitado

Vista previa:

```powershell
.\scripts\deploy-deployment-role.ps1 -AwsProfile epico-bootstrap -ExpectedAccountId 123456789012
```

Ejecución, después de revisar:

```powershell
.\scripts\deploy-deployment-role.ps1 -Execute -AwsProfile epico-bootstrap -ExpectedAccountId 123456789012
```

Resultado esperado:

```text
arn:aws:iam::123456789012:role/<RESOURCE_PREFIX>-deployment-<ENVIRONMENT>
```

## 9. Asumir el rol

```powershell
.\scripts\enter-deployment-role.ps1 `
  -RoleArn arn:aws:iam::123456789012:role/<RESOURCE_PREFIX>-deployment-<ENVIRONMENT> `
  -AwsProfile epico-bootstrap
aws sts get-caller-identity
```

Debe aparecer una sesión `assumed-role/<RESOURCE_PREFIX>-deployment-<ENVIRONMENT>` en la cuenta correcta.

## 10. Crear el secreto operativo de Serverless

La Access Key de Serverless autentica Serverless Framework v4; no es una credencial AWS.

1. FSG crea o utiliza su organización en [Serverless Dashboard](https://app.serverless.com).
2. Inicia sesión con una cuenta corporativa FSG.
3. Abre `Settings` → `Access Keys`.
4. Crea una clave dedicada, por ejemplo `epico-production-deployer`.
5. Copia el valor una sola vez y revisa las condiciones comerciales aplicables a FSG.

La documentación oficial indica que v4 exige autenticación y que las Access Keys son apropiadas para ejecución no interactiva. También existen License Keys para organizaciones con suscripción.

```powershell
.\scripts\initialize-serverless-access-key-secret.ps1 `
  -Execute -ExpectedAccountId 123456789012 `
  -CostCenter FSG-ELRN-EPICO-PROD
```

El script solicita la Access Key mediante una entrada segura, sin recibirla como argumento.

Se guarda en `epico/production/serverless/access-key`; nunca en `.env` o Git.

## 11. Autorizar GitHub para Amplify

1. Usar una cuenta GitHub con lectura de los dos frontends privados.
2. Instalar/autorizar AWS Amplify GitHub App para `funsg-org`.
3. Limitarla a los repositorios necesarios cuando sea posible.
4. Crear `epico/production/github/amplify-token` mediante el script de inicialización:

```powershell
.\scripts\initialize-amplify-github-secret.ps1 `
  -Execute -ExpectedAccountId 123456789012 `
  -CostCenter FSG-ELRN-EPICO-PROD
```

El token se solicita mediante entrada segura. Para los repositorios privados debe ser un PAT classic con los scopes `repo` y `admin:repo_hook`; si la organización usa SSO, también debe autorizarse para `funsg-org`.
5. Confirmar que la rama coincida con `DEPLOYMENT_BRANCH` en el padre y los repositorios involucrados; no usar `main` mientras continúe asociado a la instalación heredada.

Amplify se crea con auto-build desactivado; autorizarlo todavía no publica las páginas.

## 12. Aprobar políticas Cognito

Configuración inicial:

- Usuario cliente: username nativo igual a la cédula; el claim `cognito:username` conserva la cédula.
- Usuario administrativo: username interno estable, acceso visible mediante alias de correo y pertenencia obligatoria al grupo administrativo.
- El correo es obligatorio, se verifica y funciona como alias; no reemplaza la cédula del usuario cliente.
- Recuperación por correo verificado.
- Contraseña Cognito mínima de 8 caracteres, con mayúscula, minúscula, número y símbolo.
- El administrador inicial requiere al menos 12 caracteres.
- Access e ID token: 1 hora; refresh token: 30 días.
- Contraseña temporal: 7 días.
- MFA desactivado inicialmente.
- User Pool protegido con `Retain`.
- Grupo: `epico-administrators-production`.

El responsable de seguridad debe aceptar MFA desactivado o solicitar una fase posterior para habilitarlo y probar recuperación.

La modalidad de inicio de sesión de Cognito es inmutable. Si una instalación existente fue creada con `UsernameAttributes: [email]`, no debe actualizarse como si fuera un cambio en sitio: se crea un User Pool nuevo, se regeneran App Clients y secreto, se exportan nuevamente los Outputs, se redespliega Auth, se actualizan las variables Cognito de Amplify y se recrea el administrador. El pool anterior permanece retenido hasta comprobar la migración y eliminarlo de forma explícita.

## 13. Ejecutar preflight sin desplegar

```powershell
.\scripts\test-deployment-readiness.ps1 `
  -ExpectedAccountId 123456789012 `
  -ExpectedDeploymentRoleArn arn:aws:iam::123456789012:role/<RESOURCE_PREFIX>-deployment-<ENVIRONMENT>
```

Corregir todos los errores. No continuar con cuenta, secreto, parámetros, rama, CORS o CostCenter inválidos.

## 14. Ver el orden sin crear recursos

```powershell
.\scripts\deploy-platform.ps1
```

## 15. Desplegar

```powershell
.\scripts\deploy-platform.ps1 `
  -Execute -ApproveChangeSets `
  -MigrateMenu `
  -ExpectedAccountId 123456789012 `
  -DeploymentRoleArn arn:aws:iam::123456789012:role/<RESOURCE_PREFIX>-deployment-<ENVIRONMENT>
```

El proceso valida, instala dependencias, crea Amplify sin builds, obtiene sus URLs, crea infraestructura compartida, exporta outputs, despliega secuencialmente siete servicios, captura recuperación, exporta APIs y configura variables `VITE_*`. Se detiene ante el primer error.

## 16. Crear el primer administrador

Si no se utilizó `-MigrateMenu` en el despliegue completo, migrar el menú después de Course y Menu y antes de publicar los frontends:

```powershell
.\scripts\import-menu-migration.ps1

.\scripts\import-menu-migration.ps1 `
  -Execute `
  -ExpectedAccountId 123456789012
```

El primer comando valida localmente el CSV. El segundo verifica cuenta, rol, tablas, jerarquía y cursos referenciados antes de insertar. Los elementos idénticos se omiten y los diferentes detienen la operación.

Después del stack compartido:

```powershell
$initialPassword = Read-Host 'Clave inicial del administrador' -AsSecureString
.\scripts\create-initial-cognito-administrator.ps1 `
  -Email administrador@epico.example -Password $initialPassword `
  -ExpectedAccountId 123456789012
```

Eso es vista previa. Para confirmar:

```powershell
.\scripts\create-initial-cognito-administrator.ps1 `
  -Execute -Email administrador@epico.example `
  -Name 'Administrador EPICO' -Password $initialPassword `
  -ExpectedAccountId 123456789012
```

El script deriva del correo normalizado un username interno estable con formato `admin-<hash>`, crea o actualiza el usuario, verifica su correo, establece la clave y lo incorpora al grupo administrativo. El administrador escribe su correo para acceder porque este funciona como alias; no necesita conocer el username interno. Esto no cambia el acceso por cédula de los usuarios cliente. La consola rechaza usuarios fuera del grupo. Entregar correo y contraseña por canales separados y solicitar cambio inmediato mediante recuperación de contraseña.

## 17. Activar y probar frontends

1. Revisar variables Amplify y confirmar que no contienen secretos.
2. Iniciar primero el build administrativo.
3. Probar acceso del administrador y rechazo de un usuario común.
4. Probar usuarios, cursos, menús, videos, métricas y suscripciones.
5. Iniciar el frontend público.
6. Probar carga S3 y entrega CloudFront.
7. No integrar a `main` hasta aprobar estas pruebas.

En el registro público, confirmar que el usuario recibe el código por correo y que la cédula permanece como `cognito:username`. Si Cognito responde `ExpiredCodeException` o indica que el código no es válido, usar `POST /auth/resend-confirmation-code` o el botón **Reenviar código** de la pantalla de verificación. Cada reenvío invalida los códigos anteriores: siempre debe ingresarse el código del correo más reciente.

## 18. Dominio personalizado opcional

La primera instalación funciona con dominios Amplify y CloudFront. Para agregar uno:

1. Usar preferentemente un dominio ya propiedad del cliente.
2. Si no existe, registrarlo con Route 53 Domains u otro registrador, siempre a nombre del cliente.
3. Administrar DNS en Route 53 o en el proveedor actual.
4. Para CloudFront, solicitar un certificado ACM en `us-east-1` y validarlo por DNS.
5. En Amplify, usar `Domain management` y crear los registros solicitados.
6. Separar `app`, `admin` y `media` en subdominios.
7. Actualizar CORS con orígenes HTTPS exactos; nunca `*`.
8. Probar HTTPS antes de retirar URLs anteriores.

La plantilla actual no automatiza dominio porque aún no existe. Se incorporará mediante un cambio IaC revisado, no durante el primer despliegue.

## 19. Preparar la entrega al cliente sin código fuente

Completar `config/client-deployment-handover.md` con Account ID, región, inventario de stacks y servicios, URLs, pruebas, correo del administrador, CostCenter, operación, costos y soporte. Nunca incluir contraseñas, repositorios, commits internos, scripts, archivos de parámetros, manifiestos de recuperación internos o secretos.

Los commits y evidencias técnicas completas se registran únicamente en el expediente interno de FSG. Activar las etiquetas de asignación de costos definidas por usuario en Billing si la cuenta todavía no lo hizo y verificar Cost Explorer cuando AWS procese los datos.

## 20. Cierre de seguridad

- Cerrar sesiones bootstrap y despliegue.
- Limpiar variables temporales de la terminal.
- Confirmar que `.env`, parámetros y outputs estén ignorados.
- Rotar cualquier credencial expuesta durante pruebas.
- Conservar manifiestos de recuperación en almacenamiento FSG restringido.

La implementación concluye solamente cuando infraestructura, siete APIs, dos frontends, administrador, pruebas, tags y recuperación estén verificados. `CREATE_COMPLETE` por sí solo no significa que la solución esté lista.
