# Manual de prerrequisitos AWS para el cliente

## 1. Objetivo

Este documento comienza con una cuenta AWS ya creada y termina cuando el cliente tiene una identidad administrativa temporal, AWS CLI funcionando, el paquete FSG verificado y el archivo `.env` listo. Todavía no despliega la solución.

AWS recomienda que las personas usen identidades federadas y credenciales temporales. Por ello, el procedimiento principal utiliza IAM Identity Center. No se deben crear Access Keys para el usuario root.

## 2. Responsables

- El propietario de la cuenta ejecuta estas actividades.
- FSG puede acompañar por videollamada, pero no recibe contraseña root, MFA ni credenciales personales.
- Si el cliente tiene un equipo de seguridad, ese equipo debe aprobar la identidad y los permisos.

## 3. Asegurar el usuario root

Iniciar sesión como root únicamente para preparar la administración de la cuenta:

1. Confirmar que el correo root sea corporativo y recuperable.
2. Configurar MFA; se recomienda registrar más de un mecanismo.
3. Verificar teléfono y datos de recuperación.
4. No crear Access Keys para root.
5. Cerrar la sesión root al terminar esta sección.

## 4. Opción recomendada: IAM Identity Center

Crear un usuario **no le asigna permisos automáticamente**. La consola separa tres procesos: crear la identidad, crear el conjunto de permisos y asignar ambos a una cuenta AWS. Es normal que las opciones de permisos no aparezcan en el formulario **Add user**.

### 4.1 Confirmar que sea una instancia de organización

1. Iniciar sesión en AWS Console con una identidad capaz de administrar IAM Identity Center. Para la configuración inicial de una cuenta nueva puede ser necesario usar root temporalmente.
2. Buscar y abrir **IAM Identity Center**.
3. En la página **Settings** u **Overview**, comprobar el tipo de instancia.
4. Debe ser una **Organization instance**. En el menú izquierdo debe existir el bloque **Multi-account permissions**, con las opciones **AWS accounts** y **Permission sets**.

Si no aparecen **AWS accounts** y **Permission sets**, detenerse: probablemente se habilitó una **Account instance**, que sirve para ciertas aplicaciones pero no para asignar acceso a cuentas AWS mediante Permission Sets. Habilitar la instancia de organización o solicitar al administrador de AWS Organizations que lo haga.

### 4.2 Crear el usuario — proceso que el cliente ya realizó

1. En el menú izquierdo elegir **Users**.
2. Elegir **Add user**.
3. Completar:
   - **Username**: nombre nominal, por ejemplo `danie.admin`; no usar una cuenta compartida.
   - **Email address** y confirmación del correo.
   - **First name**, **Last name** y **Display name**.
4. En **Password setup**, dejar **Send an email to this user with password setup instructions**, salvo que la política del cliente requiera contraseña de un solo uso.
5. Elegir **Next**, revisar y finalmente **Add user**.
6. Abrir el correo de invitación y completar la contraseña del usuario.

Al terminar esta pantalla, el usuario existe en el directorio pero todavía **no puede entrar a la cuenta AWS**.

### 4.3 Crear el Permission Set administrativo temporal

Este paso se realiza fuera del usuario:

1. Volver al panel principal de **IAM Identity Center**.
2. En el menú izquierdo, bajo **Multi-account permissions**, elegir **Permission sets**.
3. Elegir **Create permission set**.
4. En **Select permission set type** seleccionar **Predefined permission set**.
5. En **Policy for predefined permission set** seleccionar **AdministratorAccess**.
6. Elegir **Next**.
7. En **Specify permission set details** verificar:
   - **Permission set name**: `AdministratorAccess` o `EpicoBootstrapAdministrator`.
   - **Session duration**: para la prueba puede conservarse `1 hour`.
   - **Relay state**: dejar vacío.
8. Elegir **Next**.
9. En **Review and create**, confirmar que la política AWS administrada sea `AdministratorAccess`.
10. Elegir **Create**.

Crear el Permission Set tampoco concede acceso todavía. Solo crea la plantilla de permisos que se asignará en el paso siguiente.

### 4.4 Asignar el usuario y Permission Set a la cuenta

1. En el menú izquierdo, bajo **Multi-account permissions**, elegir **AWS accounts**.
2. En el árbol de cuentas marcar la casilla de la cuenta donde se instalará EPICO. En una cuenta nueva normalmente será la **Management account**.
3. Elegir **Assign users or groups**.
4. En **Step 1: Select users and groups**:
   - Abrir la pestaña **Users**.
   - Buscar el usuario creado.
   - Marcar su casilla.
   - Elegir **Next**.
5. En **Step 2: Select permission sets**:
   - Marcar `AdministratorAccess` o `EpicoBootstrapAdministrator`.
   - Elegir **Next**.
6. En **Step 3: Review and submit** comprobar el usuario, la cuenta y el Permission Set.
7. Elegir **Submit**.
8. Mantener la página abierta hasta que la asignación termine correctamente; puede tardar algunos minutos.

### 4.5 Verificar visualmente la asignación

Puede verificarse por cualquiera de estas rutas:

- **IAM Identity Center → AWS accounts → seleccionar la cuenta**: el usuario debe aparecer en **Assigned users and groups** y el Permission Set en su asignación.
- **IAM Identity Center → Users → seleccionar el usuario → AWS accounts**: debe aparecer la cuenta y el Permission Set aplicado.

### 4.6 Configurar MFA y obtener la URL del portal

1. Abrir **IAM Identity Center → Settings**.
2. Buscar la sección **Authentication** o **Multi-factor authentication** y elegir **Configure** si aún no está configurada.
3. Aplicar la política MFA aprobada por el cliente. Si se usa un proveedor de identidad externo, el MFA se administra en ese proveedor.
4. Volver a **Settings** o **Dashboard** y copiar **AWS access portal URL**.
5. Confirmar la **IAM Identity Center Region**; esta región pertenece al directorio y puede ser distinta de `us-east-1`, que sigue siendo la región donde se despliega EPICO.
6. Iniciar sesión en la URL del portal con el usuario creado.
7. Abrir la pestaña **Accounts**, seleccionar la cuenta y confirmar que aparece el rol `AdministratorAccess` o `EpicoBootstrapAdministrator`.

Para una cuenta nueva de prueba se utiliza `AdministratorAccess` únicamente durante la creación del rol limitado `epico-deployment-qa`. Debe retirarse al finalizar el bootstrap. En una organización empresarial, el equipo de seguridad puede sustituirlo por una política bootstrap personalizada.

### 4.7 Problemas frecuentes

- **El usuario existe, pero el portal no muestra ninguna cuenta**: falta la asignación de la sección 4.4.
- **No aparece Multi-account permissions**: la instancia puede ser de cuenta y no de organización, o la identidad actual no tiene permisos para administrar la organización.
- **El Permission Set existe, pero no aparece en el portal**: todavía no fue asignado al usuario y a la cuenta.
- **La asignación a la Management account falla por permisos**: la identidad configuradora necesita `IAMFullAccess` o permisos equivalentes para esta operación privilegiada.
- **No llega el correo del usuario**: revisar spam y la dirección registrada; desde el usuario se puede reenviar o restablecer la invitación según las opciones visibles.

## 5. Alternativa excepcional: usuario IAM

Utilizar esta opción solamente cuando IAM Identity Center no esté disponible:

1. En **IAM → Users**, crear un usuario nominal, por ejemplo `epico-bootstrap-admin`.
2. Habilitar acceso a consola solo si es necesario.
3. Exigir MFA.
4. Conceder permisos administrativos únicamente durante el bootstrap.
5. Crear Access Keys solo si el cliente ha aprobado expresamente credenciales de larga duración para AWS CLI.
6. Desactivar o eliminar las Access Keys y retirar el permiso administrativo después de crear el rol de despliegue.

Nunca utilizar el usuario root desde AWS CLI.

## 6. Instalar herramientas en la computadora del cliente

Instalar:

- AWS CLI v2.
- PowerShell 7 recomendado; Windows PowerShell 5.1 es aceptable para los scripts actuales.
- Navegador actualizado.

Validar:

```powershell
aws --version
$PSVersionTable.PSVersion
```

El cliente no necesita Git, Node.js, npm ni Serverless Framework para ejecutar su parte.

## 7. Configurar AWS CLI con Identity Center

```powershell
aws configure sso --profile epico-bootstrap
aws sso login --profile epico-bootstrap
aws sts get-caller-identity --profile epico-bootstrap
```

En el asistente indicar la URL de inicio, región SSO, Account ID y Permission Set entregados por el administrador. Configurar `us-east-1` como región predeterminada de trabajo.

La respuesta de `get-caller-identity` debe mostrar el Account ID correcto. El ARN SSO será de tipo `arn:aws:sts::...:assumed-role/...`; ese ARN de sesión no se copia directamente en `.env`.

## 8. Obtener TRUSTED_PRINCIPAL_ARN

### Si utiliza IAM Identity Center

Resolver el rol IAM permanente correspondiente a la sesión SSO:

```powershell
$identity = aws sts get-caller-identity --profile epico-bootstrap | ConvertFrom-Json
$ssoRoleName = ($identity.Arn -split '/')[1]
$trustedPrincipalArn = aws iam get-role `
  --role-name $ssoRoleName `
  --query 'Role.Arn' `
  --output text `
  --profile epico-bootstrap
$trustedPrincipalArn
```

El resultado esperado comienza con:

```text
arn:aws:iam::<ACCOUNT_ID>:role/aws-reserved/sso.amazonaws.com/
```

### Si utiliza un usuario IAM excepcional

```powershell
$trustedPrincipalArn = aws sts get-caller-identity `
  --query Arn --output text --profile epico-bootstrap
$trustedPrincipalArn
```

El resultado comienza con `arn:aws:iam::<ACCOUNT_ID>:user/`.

No utilizar un ARN `arn:aws:sts::...:assumed-role/...` como `TRUSTED_PRINCIPAL_ARN`.

## 9. Verificar el paquete entregado por FSG

`SHA256SUMS.txt` contiene una huella SHA-256 de cada archivo permitido. Sirve para detectar archivos modificados, incompletos o dañados durante la transferencia. No es una contraseña, firma digital ni secreto.

Desde la raíz del paquete:

```powershell
$failures = @()
Get-Content SHA256SUMS.txt | ForEach-Object {
  $expectedHash, $relativePath = $_ -split '  ', 2
  $actualHash = (Get-FileHash -LiteralPath $relativePath -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($actualHash -ne $expectedHash) { $failures += $relativePath }
}
if ($failures.Count) { throw "Archivos inválidos: $($failures -join ', ')" }
'Paquete íntegro'
```

Si falla una huella, detenerse y solicitar nuevamente el paquete a FSG. No ejecutar el archivo afectado.

## 10. Crear el único archivo de configuración

```powershell
Copy-Item .env.example .env
```

Para la primera prueba:

```dotenv
ENVIRONMENT=qa
TAG_COST_CENTER=FSG-ELRN-EPICO-QA
TRUSTED_PRINCIPAL_ARN=arn:aws:iam::<ACCOUNT_ID>:role/<RUTA-Y-NOMBRE-DEL-ROL>
CLIENT_CODE=epico
RESOURCE_PREFIX=epico
TAG_CLIENT=EPICO
```

El archivo `.env` es local, no contiene contraseñas y no se entrega de vuelta a FSG. Para producción se cambia posteriormente solo `ENVIRONMENT` y el código de costo correspondiente; el ARN puede conservarse si el cliente autoriza la misma identidad.

## 11. Validación final de prerrequisitos

```powershell
.\scripts\sync-deployment-parameters.ps1
.\scripts\validate-environment.ps1
aws sts get-caller-identity --profile epico-bootstrap
```

Antes de continuar debe cumplirse:

- Account ID confirmado.
- Root protegido y fuera de uso cotidiano.
- Identidad nominal con MFA.
- Perfil `epico-bootstrap` autenticado.
- `TRUSTED_PRINCIPAL_ARN` de tipo IAM `role` o `user`, nunca STS.
- Región de despliegue `us-east-1`.
- Paquete SHA-256 íntegro.
- `ENVIRONMENT=qa` y CostCenter definitivo.

Con estos puntos completos, continuar con el **Manual de instalación de infraestructura para el cliente EPICO**.

## 12. Cierre del permiso bootstrap

Después de crear y comprobar `epico-deployment-qa`:

1. Retirar `AdministratorAccess` del usuario o Permission Set temporal.
2. Si se utilizó IAM user con Access Keys, desactivarlas y eliminarlas.
3. Conservar únicamente acceso para asumir el rol limitado cuando exista una ventana autorizada.
4. Registrar quién realizó el bootstrap y cuándo.
