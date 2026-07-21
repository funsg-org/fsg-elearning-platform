# Ambientes QA y producción en una cuenta AWS

Existe una sola configuración local: `.env`. Para seleccionar el destino se cambia únicamente:

```dotenv
ENVIRONMENT=qa
```

o:

```dotenv
ENVIRONMENT=production
```

Preparación inicial:

```powershell
Copy-Item .env.example .env
```

El cargador deriva automáticamente `RESOURCE_SUFFIX`, `TAG_ENVIRONMENT`, la ruta SSM y los nombres de secretos. `sync-deployment-parameters.ps1` genera los tres archivos locales ignorados por Git:

- `infrastructure/parameters.json`
- `infrastructure/amplify-parameters.json`
- `infrastructure/deployment-role-parameters.json`

Los scripts principales ejecutan esa sincronización automáticamente. No se mantienen archivos de parámetros separados por ambiente.

| Recurso derivado | Si ENVIRONMENT=qa | Si ENVIRONMENT=production |
| --- | --- | --- |
| Stack compartido | `epico-platform-qa` | `epico-platform-production` |
| Stack Amplify | `epico-amplify-qa` | `epico-amplify-production` |
| Rol | `epico-deployment-qa` | `epico-deployment-production` |
| Ruta SSM | `/epico/qa` | `/epico/production` |
| Rama Amplify | `qa` | `main` |

Antes de cambiar de ambiente, cerrar la terminal actual, editar `.env`, abrir una terminal nueva y ejecutar primero una vista previa:

```powershell
.\scripts\deploy-platform.ps1
```

Los archivos `*outputs.qa.env` y `*outputs.production.env` son resultados generados y permanecen separados para impedir que una ejecución consuma identificadores AWS del otro ambiente.

El flujo de promoción es QA → aceptación → cambiar `ENVIRONMENT=production` → desplegar exactamente el commit aprobado. Los usuarios y datos no se copian entre ambientes.
