# Manual de instalación de infraestructura para el cliente EPICO

> Prerrequisito obligatorio: completar primero `config/client-aws-prerequisites-manual.md`. Ese documento explica cómo preparar la identidad AWS, permisos bootstrap, AWS CLI, `TRUSTED_PRINCIPAL_ARN` y la verificación de `SHA256SUMS.txt` desde una cuenta recién creada.

## 1. Propósito y alcance

Este manual permite al cliente preparar su cuenta AWS y desplegar la infraestructura base de FSG E-learning. El cliente mantiene control de su cuenta, facturación, identidades, roles, DNS y recursos CloudFormation.

FSG no entrega el código fuente de los microservicios ni de los frontends. El cliente recibe un paquete de despliegue que contiene únicamente plantillas CloudFormation, scripts operativos necesarios, archivos de parámetros de ejemplo, este manual y sus sumas SHA-256.

Las secciones marcadas **“Corresponde al proveedor de la solución”** son ejecutadas por FSG porque requieren repositorios privados y código fuente. Al terminarlas, el procedimiento vuelve al cliente.

## 2. Selección obligatoria del ambiente

La cuenta puede alojar tres instalaciones aisladas: `develop`, `qa` y `production`. Existe un solo archivo local `.env` activo por ejecución.

```powershell
Copy-Item .env.example .env
# Editar .env y definir ambiente y rama para la primera instalación.
ENVIRONMENT=develop
DEPLOYMENT_BRANCH=develop
.\scripts\sync-deployment-parameters.ps1
```

`ENVIRONMENT` acepta únicamente `develop`, `qa` o `production`. `DEPLOYMENT_BRANCH` es independiente y puede usar la rama base correspondiente o una variante acordada como `epico-production`. Si se omite, adopta el mismo valor del ambiente.

Para cambiar de ambiente se editan ambos valores según la versión aprobada, se abre una terminal nueva y se vuelven a ejecutar los scripts. Los parámetros se regeneran automáticamente. Los stacks usan `<RESOURCE_PREFIX>-*‑<ENVIRONMENT>`. Centros de costo propuestos: `FSG-ELRN-EPICO-DEV`, `FSG-ELRN-EPICO-QA` y `FSG-ELRN-EPICO-PROD`.

## 3. Responsabilidades

| Actividad                                                   | Cliente               | Proveedor FSG                  |
| ----------------------------------------------------------- | --------------------- | ------------------------------ |
| Crear y administrar la cuenta AWS                           | Ejecuta               | Asiste                         |
| Instalar/configurar AWS CLI en equipo del cliente           | Ejecuta               | Asiste                         |
| Configurar identidad AWS y facturación                     | Ejecuta               | No recibe cuenta root          |
| Crear rol limitado de despliegue                            | Ejecuta               | Proporciona plantilla          |
| Ejecutar CloudFormation de infraestructura ...crecompartida | Ejecuta               | Asiste                         |
| Crear Amplify conectado a repositorios privados             | Autoriza recursos AWS | Ejecuta                        |
| Desplegar microservicios y frontends                        | No accede al código  | Ejecuta                        |
| Crear/designar administrador Cognito                        | Designa y valida      | Ejecuta alta técnica o asiste |
| Pruebas y aceptación                                       | Ejecuta con FSG       | Ejecuta con cliente            |

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
config/client-aws-prerequisites-manual.md
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
aws configure sso --profile epico-bootstrap
aws sso login --profile epico-bootstrap
aws sts get-caller-identity --profile epico-bootstrap
```

Si la organización todavía utiliza Access Keys:

```powershell
aws configure --profile epico-bootstrap
aws sts get-caller-identity --profile epico-bootstrap
```

La respuesta debe mostrar la cuenta destino. Nunca utilizar la cuenta root para ejecutar el despliegue.

## 7. Preparar acceso temporal del proveedor

El cliente no debe enviar su contraseña, MFA, credenciales root ni claves de un administrador existente.

Opción recomendada:

1. Crear una identidad temporal FSG en IAM Identity Center.
2. Darle acceso a la cuenta destino.
3. Permitirle asumir posteriormente `<RESOURCE_PREFIX>-deployment-<ENVIRONMENT>`.
4. Entregar URL de inicio SSO, región SSO, nombre de cuenta y nombre del rol; FSG inicia su propia sesión.
5. Deshabilitar esa asignación al finalizar.

Alternativa excepcional: usuario IAM exclusivo de despliegue con Access Keys rotables, sin acceso a consola y sin permisos adicionales. Las claves se entregan por un canal secreto aprobado, se usan en un perfil local FSG y se eliminan inmediatamente después de la instalación.

## 8. Generar parámetros locales desde `.env`

```powershell
.\scripts\sync-deployment-parameters.ps1
```

El script genera los tres `parameters.json` locales. No se editan directamente. Antes de continuar, `.env` debe contener:

- `ENVIRONMENT=develop`, `qa` o `production`.
- `DEPLOYMENT_BRANCH` acordada para ese ambiente.
- `TAG_COST_CENTER=FSG-ELRN-EPICO-QA`.
- `TRUSTED_PRINCIPAL_ARN` con el ARN IAM obtenido en prerrequisitos.
- `MEDIA_CORS_ALLOWED_ORIGINS=PENDING` hasta que el proveedor entregue las URLs Amplify en el paso 10.

## 9. Validar y crear el rol de despliegue

Vista previa:

```powershell
$accountId = aws sts get-caller-identity `
  --query Account --output text --profile epico-bootstrap

.\scripts\deploy-deployment-role.ps1 `
  -AwsProfile epico-bootstrap `
  -ExpectedAccountId $accountId
```

No copiar literalmente `123456789012`: en todos los ejemplos representa el Account ID real de 12 dígitos. El comando anterior lo consulta automáticamente.

Después de revisar el Change Set:

```powershell
.\scripts\deploy-deployment-role.ps1 `
  -Execute -ApproveChangeSets `
  -AwsProfile epico-bootstrap `
  -ExpectedAccountId $accountId
```

Registrar el output:

```text
arn:aws:iam::123456789012:role/<RESOURCE_PREFIX>-deployment-<ENVIRONMENT>
```

## 10. Corresponde al proveedor: preparar Amplify sin publicar

En este punto FSG utiliza el acceso temporal para crear las dos aplicaciones Amplify, conectarlas a los repositorios privados y mantener `EnableAutoBuild=false`.

FSG entrega al cliente:

- URL Amplify del portal público.
- URL Amplify de la consola administrativa.
- Nombre/ID del stack Amplify.
- Confirmación de que ningún build fue iniciado.

El cliente no recibe repositorios, token GitHub ni código fuente.

Al terminar esta intervención, el proveedor **se detiene** y devuelve el control al cliente. Todavía no debe desplegar microservicios ni frontends porque Cognito, S3 y CloudFront aún no existen.

## 11. Completar CORS de infraestructura compartida

Editar `.env` y reemplazar `MEDIA_CORS_ALLOWED_ORIGINS=PENDING` por las dos URLs exactas entregadas por FSG. No usar `*`, rutas ni barra final.

Ejemplo conceptual:

```text
https://rama.id-publico.amplifyapp.com,https://rama.id-admin.amplifyapp.com
```

Regenerar los parámetros:

```powershell
.\scripts\sync-deployment-parameters.ps1
```

Comprobar que `infrastructure/parameters.json` contiene `MediaCorsAllowedOrigins` con ambas URLs.

## 12. Validar la plantilla compartida

```powershell
.\scripts\validate-infrastructure.ps1 `
  -AwsProfile epico-bootstrap `
  -Region us-east-1
```

La validación no crea recursos.

## 13. Crear y revisar el Change Set compartido

Convertir el JSON local a parámetros del script:

```powershell
$parameterData = Get-Content infrastructure/parameters.json -Raw | ConvertFrom-Json
$platformParameters = foreach ($parameter in $parameterData) {
  "$($parameter.ParameterKey)=$($parameter.ParameterValue)"
}
```

Crear el Change Set sin ejecutarlo:

```powershell
$environment = .\scripts\get-deployment-environment.ps1
. .\scripts\load-environment.ps1 -Quiet
$platformStack = "$($env:RESOURCE_PREFIX)-platform-$environment"

$changeSetName = .\scripts\invoke-cloudformation-change-set.ps1 `
  -StackName $platformStack `
  -TemplateFile infrastructure/shared-resources.yml `
  -ParameterOverrides $platformParameters `
  -Capabilities CAPABILITY_NAMED_IAM `
  -AwsProfile epico-bootstrap `
  -Region us-east-1
```

Comprobar inmediatamente que la variable contiene un único texto y no objetos internos de PowerShell:

```powershell
$changeSetName
$changeSetName.GetType().FullName
```

El tipo esperado es `System.String` y el valor debe comenzar con `review-<RESOURCE_PREFIX>-platform-<ambiente>-`. No continuar si aparecen textos como `FormatEntryData`, `FormatStartData` o varios valores.

Como recuperación de una ejecución realizada con una versión anterior del script, extraer únicamente el nombre generado en esa misma ejecución:

```powershell
$changeSetName = @(
  $changeSetName | Where-Object {
    $_ -is [string] -and $_ -match "^review-$([regex]::Escape($platformStack))-"
  }
) | Select-Object -Last 1

if ([string]::IsNullOrWhiteSpace($changeSetName)) {
  throw 'No se pudo recuperar el nombre del Change Set; créelo nuevamente.'
}
```

No copiar el nombre de otro ambiente o intento. Antes de ejecutarlo, AWS debe mostrar estado `CREATE_COMPLETE` y ejecución `AVAILABLE`:

```powershell
aws cloudformation describe-change-set `
  --stack-name $platformStack `
  --change-set-name $changeSetName `
  --profile epico-bootstrap `
  --region us-east-1 `
  --query "[Status,ExecutionStatus,ChangeSetName]" `
  --output table
```

Antes de aprobar debe comprobar que el Change Set contiene únicamente recursos esperados:

- Cognito User Pool, dos App Clients y grupo administrativo.
- Secrets Manager para el secreto confidencial de Cognito.
- Lambda/rol auxiliar que copia ese secreto sin exponerlo.
- Bucket S3 privado y versionado.
- CloudFront y Origin Access Control.

Revisar que no existan eliminaciones o reemplazos inesperados. Ejecutar el Change Set únicamente después de aprobarlo.

Para una instalación limpia, Cognito debe crear un User Pool con username nativo y correo como alias. Si se está corrigiendo una instalación de prueba creada anteriormente por correo, el Change Set debe crear el nuevo pool `<RESOURCE_PREFIX>-identity-<RESOURCE_SUFFIX>`, reemplazar los App Clients y el grupo, y conservar el pool anterior `<RESOURCE_PREFIX>-users-<RESOURCE_SUFFIX>` mediante `Retain`. Esta sustitución requiere confirmación expresa de que los usuarios anteriores pueden descartarse; S3, CloudFront y las tablas no deben reemplazarse.

```powershell
aws cloudformation execute-change-set `
  --stack-name $platformStack `
  --change-set-name $changeSetName `
  --profile epico-bootstrap `
  --region us-east-1

aws cloudformation wait stack-create-complete `
  --stack-name $platformStack `
  --profile epico-bootstrap `
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
- User Pool configurado con username nativo y alias de correo: los clientes ingresan con cédula y los administradores con correo.
- Tags y CostCenter en recursos compatibles.

## 15. Entregar datos al proveedor para los proyectos

El cliente entrega a FSG por canal aprobado:

- Account ID y región.
- ARN de `<RESOURCE_PREFIX>-deployment-<ENVIRONMENT>`.
- Datos de acceso SSO temporal o, excepcionalmente, credenciales del usuario temporal dedicado.
- Outputs no sensibles de CloudFormation listados arriba.
- URLs Amplify.
- Correo y nombre del administrador inicial.
- Confirmación del CSV de menú aprobado para el cliente y ambiente.

No entregar: contraseña root, MFA, contraseña personal, acceso de otro empleado ni valor del Client Secret Cognito.

## 16. Corresponde al proveedor: desplegar proyectos privados

Esta es la **segunda intervención del proveedor**. Solo comienza después de que el cliente confirme `CREATE_COMPLETE` y entregue los Outputs del paso 14.

FSG realiza, desde su estación privada:

1. Verificación de cuenta y rol.
2. Instalación reproducible de dependencias.
3. Carga segura de la credencial operativa Serverless.
4. Despliegue secuencial de Auth, Course, Menu, Metrics, Subscriptions, Users y Videos.
5. Validación y migración idempotente del menú inicial; las referencias a cursos deben existir previamente.
6. Captura de manifiestos de recuperación.
7. Configuración de variables públicas `VITE_*` en Amplify.
8. Creación del primer administrador Cognito.
9. Build y publicación controlada de ambos frontends.
10. Entrega de URLs, cantidad de menús migrados y resultado técnico al cliente.

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

En la prueba de registro, el cliente ingresa su cédula como usuario y confirma el correo con el código más reciente. Si el código venció o Cognito lo invalidó, se utiliza **Reenviar código**; cada reenvío invalida todos los códigos anteriores.

## 18. Dominio opcional

El cliente acredita la propiedad del dominio y autoriza DNS. FSG configura técnicamente Amplify/CloudFront. Para CloudFront el certificado ACM debe emitirse en `us-east-1`. Se recomiendan subdominios separados `app`, `admin` y `media`; luego se actualiza CORS con orígenes exactos.

## 19. Costos y entrega

Activar en Billing las etiquetas definidas por usuario y revisar Cost Explorer cuando AWS procese los datos. Completar inventario, URLs, pruebas, seguridad, soporte y aceptación. El cliente recibe documentación de lo desplegado, no código fuente.

## 20. Cierre del acceso FSG

Después de aceptación:

1. Deshabilitar la asignación SSO temporal o eliminar Access Keys temporales.
2. Mantener el rol `<RESOURCE_PREFIX>-deployment-<ENVIRONMENT>` solo si habrá soporte futuro; su confianza debe apuntar a una identidad controlada.
3. Confirmar que FSG no conserva credenciales del cliente.
4. Mantener procedimientos de soporte para autorizar nuevas sesiones temporales.

## 21. Futuras actualizaciones solicitadas al proveedor

Cada actualización se trata como una nueva intervención controlada. El permiso temporal usado en la instalación inicial no debe permanecer abierto indefinidamente.

Toda actualización se promueve por `develop`, luego `qa` y finalmente `production`, con la rama configurada para cada ambiente. Cada ambiente requiere su rol y autorización temporal; una autorización para un ambiente no autoriza los demás.

### 21.1 Solicitud y aprobación

El cliente entrega a FSG una solicitud que incluya:

- Descripción funcional o técnica del cambio.
- Ambiente afectado.
- Usuarios o procesos impactados.
- Fecha objetivo y ventana autorizada.
- Responsable de aceptación del cliente.
- Restricciones de indisponibilidad.
- Dominio, integraciones o datos afectados, si corresponde.

FSG devuelve alcance, componentes que cambiarán, riesgos, duración estimada, plan de pruebas y plan de reversión. El cliente aprueba por escrito antes de abrir acceso AWS.

### 21.2 Crear un nuevo acceso temporal

El cliente crea una nueva sesión o asignación temporal siguiendo la sección 7. Se recomienda reutilizar el rol limitado `<RESOURCE_PREFIX>-deployment-<ENVIRONMENT>`, pero autorizar nuevamente a una identidad temporal FSG.

Antes de la ventana, entregar únicamente:

- Account ID y región.
- ARN del rol de despliegue.
- Datos SSO de la nueva asignación temporal.
- Número o identificador de la solicitud aprobada.
- Ventana durante la cual el acceso estará habilitado.

Si el cambio exige permisos que el rol actual no posee, FSG debe justificar las acciones y recursos exactos. El cliente revisa una actualización de la plantilla IAM mediante Change Set. No se concede `AdministratorAccess` para resolver un permiso faltante.

### 21.3 Estado y respaldos previos

Antes de autorizar cambios, el cliente y FSG verifican:

- Stacks CloudFormation en estado estable.
- Alarmas/incidentes abiertos.
- PITR activo en DynamoDB.
- Versionado activo en S3.
- Estado de Amplify, Lambda y APIs.
- Fecha del último respaldo o manifiesto de recuperación.
- Costos o cuotas que puedan bloquear el cambio.

Para cambios de datos de alto riesgo, solicitar respaldo/exportación adicional antes de continuar.

### 21.4 Corresponde al proveedor: publicar la actualización

FSG desarrolla y prueba el cambio en sus repositorios privados. Durante la ventana autorizada:

1. Verifica cuenta y rol temporal.
2. Confirma los commits y componentes aprobados.
3. Ejecuta preflight y captura recuperación.
4. Revisa cualquier Change Set de infraestructura.
5. Despliega solamente los microservicios afectados.
6. Configura y publica únicamente los frontends afectados.
7. Ejecuta pruebas técnicas y entrega resultados.

El cliente no recibe ni ejecuta código fuente. Si la actualización incluye infraestructura base, el cliente ejecuta el Change Set correspondiente con asistencia FSG, igual que en la instalación inicial.

### 21.5 Pruebas y aceptación

El cliente ejecuta las pruebas funcionales acordadas y registra:

- Versión/fecha instalada.
- Funcionalidades verificadas.
- Resultado de regresión.
- Incidentes encontrados.
- Aceptación, rechazo o decisión de rollback.

No cerrar la ventana hasta confirmar monitoreo básico de APIs, frontends, autenticación, datos y contenido multimedia.

### 21.6 Fallo y reversión

Ante un fallo, FSG detiene despliegues posteriores y aplica el plan aprobado. Según el componente puede implicar rollback de CloudFormation, redeploy del commit anterior, restauración DynamoDB a una tabla nueva o recuperación de una versión S3. No usar `serverless remove` como rollback.

El cliente autoriza cualquier restauración que cambie datos y registra el incidente.

### 21.7 Cierre de la actualización

Después de la aceptación:

1. El cliente revoca la asignación SSO o elimina las Access Keys temporales.
2. FSG cierra sesión y elimina perfiles/variables temporales.
3. FSG entrega inventario de componentes actualizados, fecha, resultado y observaciones.
4. El cliente actualiza el acta operativa y conserva la aprobación.
5. Ambas partes registran pendientes o deuda técnica para una intervención futura.

## 22. Desinstalación definitiva de un ambiente

La desinstalación no es una actualización ni una reversión. El cliente debe solicitarla por escrito e identificar cuenta, cliente, ambiente (`develop`, `qa` o `production`), fecha y tratamiento de los datos.

Antes de autorizar:

1. Definir respaldos de Cognito, S3 y DynamoDB.
2. Confirmar si algún dato debe conservarse y durante cuánto tiempo.
3. Autorizar temporalmente al proveedor para eliminar los recursos privados.
4. Designar a un administrador del cliente para revisar y aprobar las eliminaciones retenidas.

El proveedor elimina Amplify y los siete stacks Serverless. El stack compartido conserva deliberadamente User Pool, secreto Cognito, bucket multimedia y tablas DynamoDB; el cliente y el proveedor verifican sus nombres, tags y respaldos antes de eliminarlos explícitamente. El rol temporal se elimina al final desde el perfil bootstrap del cliente.

La cuenta se considera limpia únicamente cuando la revisión de stacks y la búsqueda por tags `Client` y `Environment` no encuentran recursos de la solución. El proveedor entrega el inventario de eliminación; el cliente revoca accesos AWS y GitHub y conserva el acta y respaldos acordados.
