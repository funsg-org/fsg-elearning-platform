# Ambientes QA y producción en una cuenta AWS

La solución admite `qa` y `production` dentro de la misma cuenta, siempre en `us-east-1`. Cada ejecución debe indicar explícitamente el ambiente y genera recursos, secretos y contratos locales independientes.

| Elemento | QA | Producción |
| --- | --- | --- |
| Stack compartido | `epico-platform-qa` | `epico-platform-production` |
| Stack Amplify | `epico-amplify-qa` | `epico-amplify-production` |
| Rol temporal | `epico-deployment-qa` | `epico-deployment-production` |
| Ruta SSM | `/epico/qa` | `/epico/production` |
| Secreto Serverless | `epico/qa/serverless/access-key` | `epico/production/serverless/access-key` |
| Contratos locales | `*outputs.qa.env` | `*outputs.production.env` |
| Tag Environment | `qa` | `production` |

Los buckets, tablas, funciones, APIs, User Pools, distribuciones y aplicaciones Amplify incorporan el sufijo del ambiente. Los datos y usuarios no se comparten: el administrador inicial debe crearse por separado en cada User Pool.

## Reglas operativas

1. Crear archivos reales a partir de los ejemplos del ambiente elegido; nunca reutilizar un JSON de otro ambiente.
2. Definir centros de costo separados. Propuesta: `FSG-ELRN-EPICO-QA` y `FSG-ELRN-EPICO-PROD`.
3. Desplegar y aprobar primero QA.
4. Ejecutar pruebas funcionales y conservar evidencia.
5. Promover el mismo commit aprobado a la rama estable de producción; no copiar recursos ni datos de QA.
6. Abrir un permiso temporal distinto para cada intervención y ambiente.
7. Ejecutar siempre los scripts con `-Environment qa` o `-Environment production`.

Ejemplo de validación previa:

```powershell
.\scripts\test-deployment-readiness.ps1 `
  -Environment qa `
  -SourceBranch qa `
  -ExpectedAccountId 123456789012 `
  -ExpectedDeploymentRoleArn arn:aws:iam::123456789012:role/epico-deployment-qa
```

Ejemplo del orquestador del proveedor:

```powershell
.\scripts\deploy-platform.ps1 `
  -Environment qa `
  -SourceBranch qa
```

Sin `-Execute`, el comando solamente muestra el plan seguro. La ejecución real exige además la cuenta esperada, ARN del rol, archivos locales completos y aprobación explícita de Change Sets.

## Alcance del aislamiento

Una sola cuenta simplifica facturación, pero no equivale al aislamiento fuerte de cuentas separadas. Los nombres, tags, stacks, datos, secretos y la mayoría de los permisos por ARN quedan separados; las cuotas regionales y los servicios cuyos recursos exigen permisos amplios —como ciertas operaciones de API Gateway, CloudFront, Amplify y Cognito— siguen compartiendo el límite administrativo de la cuenta. Cualquier Change Set debe revisarse para confirmar que solo afecta al ambiente solicitado.
