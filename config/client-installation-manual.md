# Manual de instalación de infraestructura para el cliente EPICO

## 1. Propósito y alcance

Este manual permite al cliente preparar su cuenta AWS y desplegar la infraestructura base de FSG E-learning. El cliente mantiene control de su cuenta, facturación, identidades, roles, DNS y recursos CloudFormation.

FSG no entrega el código fuente de los microservicios ni de los frontends. El cliente recibe un paquete de despliegue que contiene únicamente plantillas CloudFormation, scripts operativos necesarios, archivos de parámetros de ejemplo, este manual y sus sumas SHA-256.

Las secciones marcadas **“Corresponde al proveedor de la solución”** son ejecutadas por FSG porque requieren repositorios privados y código fuente. Al terminarlas, el procedimiento vuelve al cliente.

## 2. Responsabilidades

| Actividad | Cliente | Proveedor FSG |
| --- | --- | --- |
| Crear y administrar la cuenta AWS | Ejecuta | Asiste |
| Instalar/configurar AWS CLI en equipo del cliente | Ejecuta | Asiste |
| Configurar identidad AWS y facturación | Ejecuta | No recibe cuenta root |
| Crear rol limitado de despliegue | Ejecuta | Proporciona plantilla |
| Ejecutar CloudFormation de infraestructura compartida | Ejecuta | Asiste |
| Crear Amplify conectado a repositorios privados | Autoriza recursos AWS | Ejecuta |
| Desplegar microservicios y frontends | No accede al código | Ejecuta |
| Crear/designar administrador Cognito | Designa y valida | Ejecuta alta técnica o asiste |
| Pruebas y aceptación | Ejecuta con FSG | Ejecuta con cliente |

## 3. Contenido del paquete entregado

Antes de abrir una terminal, comprobar que el paquete incluya:

```text
infrastructure/deployment-role.yml
infrastructure/shared-resources.yml
infrastructure/deployment-role-parameters.example.json
infrastructure/parameters.example.json
scripts/deploy-deployment-role.ps1
scripts/validate-deployment-role.ps1
scripts/invoke-cloudformation-change-set.ps1
scripts/validate-infrastructure.ps1
config/client-installation-manual.md
config/client-deployment-handover.md
SHA256SUMS.txt
```

El paquete no debe contener carpetas `services`, `frontends`, `.git`, secretos, tokens ni código de aplicación. El cliente verifica las sumas SHA-256 proporcionadas por FSG antes de ejecutar archivos.

## 4. Datos que debe definir el cliente

- Account ID AWS de 12 dígitos.
- Región: `us-east-1`.
- Responsable AWS y responsable de aceptación.
- Correo del primer administrador funcional.
- Centro de costo propuesto: `FSG-ELRN-EPICO-PROD`, o el código exigido por Finanzas.
- Ventana de instalación.
- Dominio, si ya existe.
- Método de acceso temporal para el proveedor.

## 5. Preparar la estación del cliente

Instalar:

- AWS CLI v2.
- PowerShell 7.
- Un navegador con acceso a AWS Console.

Git, Node.js, npm y Serverless no son necesarios para las etapas del cliente.

```powershell
aws --version
$PSVersionTable.PSVersion
```

## 6. Configurar autenticación AWS del cliente

Se recomienda IAM Identity Center/SSO:

```powershell
aws configure sso --profile epico-admin
aws sso login --profile epico-admin
aws sts get-caller-identity --profile epico-admin
```

Si la organización todavía utiliza Access Keys:

```powershell
aws configure --profile epico-admin
aws sts get-caller-identity --profile epico-admin
```

La respuesta debe mostrar la cuenta destino. Nunca utilizar la cuenta root para ejecutar el despliegue.

## 7. Preparar acceso temporal del proveedor

El cliente no debe enviar su contraseña, MFA, credenciales root ni claves de un administrador existente.

Opción recomendada:

1. Crear una identidad temporal FSG en IAM Identity Center.
2. Darle acceso a la cuenta destino.
3. Permitirle asumir posteriormente `epico-deployment-production`.
4. Entregar URL de inicio SSO, región SSO, nombre de cuenta y nombre del rol; FSG inicia su propia sesión.
5. Deshabilitar esa asignación al finalizar.

Alternativa excepcional: usuario IAM exclusivo de despliegue con Access Keys rotables, sin acceso a consola y sin permisos adicionales. Las claves se entregan por un canal secreto aprobado, se usan en un perfil local FSG y se eliminan inmediatamente después de la instalación.

## 8. Crear archivos de parámetros del cliente

```powershell
Copy-Item infrastructure/deployment-role-parameters.example.json infrastructure/deployment-role-parameters.json
Copy-Item infrastructure/parameters.example.json infrastructure/parameters.json
```

En ambos archivos:

- Reemplazar `PENDING` por el centro de costo definitivo.
- Mantener `ResourcePrefix=epico`.
- Mantener región/ambiente de producción según el contrato.

En `deployment-role-parameters.json`, colocar como `TrustedPrincipalArn` el ARN de la identidad temporal creada para FSG. Los archivos no contienen claves secretas.

## 9. Validar y crear el rol de despliegue

Vista previa:

```powershell
.\scripts\deploy-deployment-role.ps1 `
  -AwsProfile epico-admin `
  -ExpectedAccountId 123456789012
```

Después de revisar el Change Set:

```powershell
.\scripts\deploy-deployment-role.ps1 `
  -Execute -ApproveChangeSets `
  -AwsProfile epico-admin `
  -ExpectedAccountId 123456789012
```

Registrar el output:

```text
arn:aws:iam::123456789012:role/epico-deployment-production
```

## 10. Corresponde al proveedor: preparar Amplify sin publicar

En este punto FSG utiliza el acceso temporal para crear las dos aplicaciones Amplify, conectarlas a los repositorios privados y mantener `EnableAutoBuild=false`.

FSG entrega al cliente:

- URL Amplify del portal público.
- URL Amplify de la consola administrativa.
- Nombre/ID del stack Amplify.
- Confirmación de que ningún build fue iniciado.

El cliente no recibe repositorios, token GitHub ni código fuente.

## 11. Completar CORS de infraestructura compartida

En `infrastructure/parameters.json`, agregar las dos URLs exactas entregadas por FSG al parámetro `MediaCorsAllowedOrigins`. No usar `*`, rutas ni barra final.

Ejemplo conceptual:

```text
https://rama.id-publico.amplifyapp.com,https://rama.id-admin.amplifyapp.com
```

## 12. Validar la plantilla compartida

```powershell
.\scripts\validate-infrastructure.ps1 `
  -AwsProfile epico-admin `
  -Region us-east-1
```

La validación no crea recursos.

## 13. Crear y revisar el Change Set compartido

Convertir el JSON local a parámetros del script:

```powershell
$platformParameters = Get-Content infrastructure/parameters.json -Raw |
  ConvertFrom-Json |
  ForEach-Object { "$($_.ParameterKey)=$($_.ParameterValue)" }
```

Crear el Change Set sin ejecutarlo:

```powershell
$changeSetName = .\scripts\invoke-cloudformation-change-set.ps1 `
  -StackName epico-platform-production `
  -TemplateFile infrastructure/shared-resources.yml `
  -ParameterOverrides $platformParameters `
  -Capabilities CAPABILITY_NAMED_IAM `
  -AwsProfile epico-admin `
  -Region us-east-1
```

Antes de aprobar debe comprobar que el Change Set contiene únicamente recursos esperados:

- Cognito User Pool, dos App Clients y grupo administrativo.
- Secrets Manager para el secreto confidencial de Cognito.
- Lambda/rol auxiliar que copia ese secreto sin exponerlo.
- Bucket S3 privado y versionado.
- CloudFront y Origin Access Control.

Revisar que no existan eliminaciones o reemplazos inesperados. Ejecutar el Change Set únicamente después de aprobarlo.

```powershell
aws cloudformation execute-change-set `
  --stack-name epico-platform-production `
  --change-set-name $changeSetName `
  --profile epico-admin `
  --region us-east-1

aws cloudformation wait stack-create-complete `
  --stack-name epico-platform-production `
  --profile epico-admin `
  --region us-east-1
```

Si el stack ya existía y el Change Set era `UPDATE`, utilizar `aws cloudformation wait stack-update-complete`.

## 14. Verificar infraestructura compartida

En CloudFormation confirmar `CREATE_COMPLETE`. Registrar, sin copiar valores secretos:

- `CognitoUserPoolId`
- `CognitoClientId`
- `CognitoAuthClientId`
- `CognitoClientSecretId`
- `CognitoAdministratorsGroupName`
- `MediaBucketName`
- `MediaCdnUrl`
- `MediaCloudFrontDistributionId`

Verificar además:

- S3 con bloqueo público y versionado.
- CloudFront habilitado.
- User Pool y secreto con retención.
- Tags y CostCenter en recursos compatibles.

## 15. Entregar datos al proveedor para los proyectos

El cliente entrega a FSG por canal aprobado:

- Account ID y región.
- ARN de `epico-deployment-production`.
- Datos de acceso SSO temporal o, excepcionalmente, credenciales del usuario temporal dedicado.
- Outputs no sensibles de CloudFormation listados arriba.
- URLs Amplify.
- Correo y nombre del administrador inicial.

No entregar: contraseña root, MFA, contraseña personal, acceso de otro empleado ni valor del Client Secret Cognito.

## 16. Corresponde al proveedor: desplegar proyectos privados

FSG realiza, desde su estación privada:

1. Verificación de cuenta y rol.
2. Instalación reproducible de dependencias.
3. Carga segura de la credencial operativa Serverless.
4. Despliegue secuencial de Auth, Course, Menu, Metrics, Subscriptions, Users y Videos.
5. Captura de manifiestos de recuperación.
6. Configuración de variables públicas `VITE_*` en Amplify.
7. Creación del primer administrador Cognito.
8. Build y publicación controlada de ambos frontends.
9. Entrega de URLs y resultado técnico al cliente.

El procedimiento interno está en el manual del proveedor. El cliente no ejecuta comandos de esta sección ni recibe el código.

## 17. Pruebas conjuntas

Después de la intervención de FSG, el cliente continúa:

1. Abrir portal público y consola administrativa.
2. Cambiar la contraseña del administrador inicial.
3. Confirmar que un usuario común no acceda a la consola.
4. Probar usuarios, cursos, menús, videos, métricas y suscripciones.
5. Probar carga multimedia y entrega por CloudFront.
6. Revisar logs/estados de stacks con asistencia FSG.
7. Registrar resultados en `client-deployment-handover.md`.

## 18. Dominio opcional

El cliente acredita la propiedad del dominio y autoriza DNS. FSG configura técnicamente Amplify/CloudFront. Para CloudFront el certificado ACM debe emitirse en `us-east-1`. Se recomiendan subdominios separados `app`, `admin` y `media`; luego se actualiza CORS con orígenes exactos.

## 19. Costos y entrega

Activar en Billing las etiquetas definidas por usuario y revisar Cost Explorer cuando AWS procese los datos. Completar inventario, URLs, pruebas, seguridad, soporte y aceptación. El cliente recibe documentación de lo desplegado, no código fuente.

## 20. Cierre del acceso FSG

Después de aceptación:

1. Deshabilitar la asignación SSO temporal o eliminar Access Keys temporales.
2. Mantener el rol `epico-deployment-production` solo si habrá soporte futuro; su confianza debe apuntar a una identidad controlada.
3. Confirmar que FSG no conserva credenciales del cliente.
4. Mantener procedimientos de soporte para autorizar nuevas sesiones temporales.
