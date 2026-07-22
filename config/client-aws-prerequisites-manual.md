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

Desde AWS Console:

1. Abrir **IAM Identity Center**.
2. Elegir **Enable** si todavía no está habilitado.
3. Crear un usuario nominal para el administrador del cliente; no usar una cuenta compartida.
4. Crear o seleccionar un Permission Set administrativo para el bootstrap.
5. Asignar el usuario a la cuenta AWS con ese Permission Set.
6. Exigir MFA según la política del cliente.
7. Guardar la URL del portal de acceso y la región de IAM Identity Center.

Para una cuenta nueva de prueba puede utilizarse temporalmente `AdministratorAccess` durante la creación del rol limitado. Debe retirarse al finalizar el bootstrap. En una organización empresarial, el equipo de seguridad puede reemplazarlo por una política bootstrap personalizada que permita CloudFormation e IAM para crear `epico-deployment-<ambiente>`.

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
