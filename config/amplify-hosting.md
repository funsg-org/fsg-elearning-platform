# Preparacion de Amplify Hosting

`infrastructure/amplify-hosting.yml` declara `epico-client-production` y `epico-admin-production`. Ambas aplicaciones apuntan inicialmente a `feature/epico-deployment-readiness`; sus ramas nacen con `EnableAutoBuild: false` y `main` no se conecta en esta etapa.

## Credencial de GitHub

1. Instalar y autorizar AWS Amplify GitHub App sobre ambos repositorios.
2. Crear el token de conexion inicial requerido por Amplify.
3. Guardarlo como JSON `{ "token": "valor-no-versionado" }` en Secrets Manager, por ejemplo bajo `epico/production/github/amplify-token`.

CloudFormation recibe solamente el nombre o ARN del secreto mediante una referencia dinamica. El valor nunca debe guardarse en Git, `.env`, parametros en texto plano ni Outputs.

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
