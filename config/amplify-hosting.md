# Preparacion de Amplify Hosting

`infrastructure/amplify-hosting.yml` declara `epico-client-production` y `epico-admin-production`. Ambas aplicaciones apuntan inicialmente a `feature/epico-deployment-readiness`; sus ramas nacen con `EnableAutoBuild: false` y `main` no se conecta en esta etapa.

## Credencial de GitHub

1. Instalar y autorizar AWS Amplify GitHub App sobre ambos repositorios.
2. Crear el token de conexion inicial requerido por Amplify.
3. Guardarlo como JSON `{ "token": "valor-no-versionado" }` en Secrets Manager, por ejemplo bajo `epico/production/github/amplify-token`.

CloudFormation recibe solamente el nombre o ARN del secreto mediante una referencia dinamica. El valor nunca debe guardarse en Git, `.env`, parametros en texto plano ni Outputs.

El secreto puede inicializarse sin colocar el token en el historial del shell:

```powershell
./scripts/initialize-amplify-github-secret.ps1 -Execute -AwsProfile epico -ExpectedAccountId 123456789012 -CostCenter CODIGO_REAL
```

El script pide el token de forma oculta y no sobrescribe secretos existentes.

## Orden futuro

1. Validar sin crear recursos: `./scripts/validate-amplify-infrastructure.ps1`.
2. Copiar `amplify-parameters.example.json` como `amplify-parameters.json` y completar `CostCenterTag`.
3. Confirmar que `DeploymentBranchDomainPrefix` representa la rama reemplazando `/` por `-`, y crear el stack; sus Outputs entregan las URLs aun sin ejecutar builds.
4. Aplicar esas URLs como orígenes CORS de la infraestructura compartida.
5. Desplegar infraestructura y microservicios, y generar los mapas con `export-amplify-environments.ps1`.
6. Vista previa: `./scripts/configure-amplify-branches.ps1`.
7. Aplicar variables sin compilar: `./scripts/configure-amplify-branches.ps1 -Execute`.
8. Tras aprobar la prueba, activar y lanzar el primer build de forma explicita:

```powershell
./scripts/configure-amplify-branches.ps1 -Execute -EnableAutoBuild -StartBuild
```

No se configura dominio personalizado; se usan los dominios predeterminados de Amplify.

## Bootstrap controlado

El comando siguiente solo valida y muestra las acciones:

```powershell
./scripts/deploy-amplify-bootstrap.ps1
```

Después de autorizar Amplify GitHub App, crear el secreto, completar `amplify-parameters.json` y confirmar la cuenta destino:

```powershell
./scripts/deploy-amplify-bootstrap.ps1 -Execute -ApproveChangeSets -AwsProfile epico -ExpectedAccountId 123456789012
```

El modo de ejecución comprueba la identidad AWS y la existencia del secreto antes de crear el stack. Al terminar genera `config/amplify-outputs.env`, que está ignorado por Git.

Normalmente no es necesario ejecutar el bootstrap por separado: `scripts/deploy-platform.ps1 -Execute` ya lo coordina al inicio y, al final, aplica las variables públicas manteniendo desactivados los builds.
