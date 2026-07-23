# Ambientes, clientes y ramas

La solución admite exactamente tres ambientes aislados en una misma cuenta AWS:

```text
develop
qa
production
```

`ENVIRONMENT` identifica el ambiente AWS. `DEPLOYMENT_BRANCH` identifica la rama Git que Amplify y el proveedor desplegarán. Son parámetros independientes.

Ejemplo con las ramas base:

```text
ENVIRONMENT=develop
DEPLOYMENT_BRANCH=develop
```

Ejemplo con una variante específica del cliente:

```text
ENVIRONMENT=production
DEPLOYMENT_BRANCH=epico-production
```

Si `DEPLOYMENT_BRANCH` no existe en `.env`, el cargador utiliza el valor de `ENVIRONMENT`. Esta compatibilidad evita modificar archivos locales existentes, pero se recomienda declararlo explícitamente en instalaciones nuevas.

## Identidad de cada cliente

Los siguientes valores del `.env` separan instalaciones de clientes:

```text
CLIENT_CODE=epico
RESOURCE_PREFIX=epico
TAG_CLIENT=EPICO
MENU_MIGRATION_FILE=migrations/menu/menu-migration.csv
```

Para otro cliente se reemplazan de forma coordinada, por ejemplo:

```text
CLIENT_CODE=aprendamos
RESOURCE_PREFIX=aprendamos
TAG_CLIENT=APRENDAMOS
```

Los nombres de carpetas y repositorios no cambian. `RESOURCE_PREFIX` controla nombres de stacks, roles, servicios, secretos, buckets y rutas; `TAG_CLIENT` permite separar costos. `MENU_MIGRATION_FILE` permite seleccionar datos iniciales distintos por cliente sin cambiar el script.

## Valores derivados

`load-environment.ps1` deriva sin escribir el `.env`:

- `RESOURCE_SUFFIX=<ENVIRONMENT>`.
- `TAG_ENVIRONMENT=<ENVIRONMENT>`.
- `RUNTIME_NODE_ENV=production` para la ejecución NestJS en AWS.
- `DEPLOYMENT_BRANCH_DOMAIN_PREFIX`, apto para la URL de Amplify.
- `SSM_BASE_PATH=/<RESOURCE_PREFIX>/<ENVIRONMENT>`.
- nombres de los secretos GitHub y Serverless.

`sync-deployment-parameters.ps1` genera los tres archivos JSON locales ignorados por Git a partir de esos valores. No se deben editar ni confirmar manualmente.

## Matriz de recursos

| Recurso | develop | qa | production |
| --- | --- | --- | --- |
| Stack compartido | `<prefijo>-platform-develop` | `<prefijo>-platform-qa` | `<prefijo>-platform-production` |
| Stack Amplify | `<prefijo>-amplify-develop` | `<prefijo>-amplify-qa` | `<prefijo>-amplify-production` |
| Rol temporal | `<prefijo>-deployment-develop` | `<prefijo>-deployment-qa` | `<prefijo>-deployment-production` |
| Rama base recomendada | `develop` | `qa` | `production` |
| Ruta SSM | `/<prefijo>/develop` | `/<prefijo>/qa` | `/<prefijo>/production` |

Cada ambiente tiene Cognito, S3, CloudFront, Amplify, APIs, Lambdas, tablas, secretos y Outputs independientes. Los archivos `*outputs.develop.env`, `*outputs.qa.env` y `*outputs.production.env` también permanecen separados.

## Promoción

El flujo recomendado es:

```text
develop → qa → production
```

La promoción se realiza con commits o pull requests; no copiando archivos compilados ni datos. Para una personalización, se puede promover hacia una rama como `epico-production`, siempre que `DEPLOYMENT_BRANCH` contenga exactamente ese nombre en la instalación correspondiente.

Antes de cambiar de ambiente o cliente:

1. Cerrar la terminal actual.
2. Editar `ENVIRONMENT`, `DEPLOYMENT_BRANCH`, identidad del cliente y centro de costo cuando corresponda.
3. Abrir una terminal nueva.
4. Ejecutar `load-environment.ps1`, `sync-deployment-parameters.ps1` y el preflight.

No se migran automáticamente usuarios ni datos entre ambientes.
