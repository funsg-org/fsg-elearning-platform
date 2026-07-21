# Orquestación de despliegue

El script `scripts/deploy-platform.ps1` implementa el orden reproducible de instalación para una cuenta AWS ya creada.

## Vista previa segura

```powershell
.\scripts\deploy-platform.ps1
```

Este modo valida rama, submódulos, plantilla y estructura, y luego muestra el orden. No crea recursos.

## Ejecución futura

1. Copiar `infrastructure/parameters.example.json` como `infrastructure/parameters.json`.
2. Definir `CostCenterTag` y reemplazar el CORS provisional.
3. Configurar credenciales AWS mediante perfil u OIDC.
4. Ejecutar:

```powershell
.\scripts\deploy-platform.ps1 `
  -Execute `
  -AwsProfile epico `
  -ExpectedAccountId 123456789012
```

## Límites deliberados

- No crea la cuenta AWS.
- No configura dominio personalizado.
- No actualiza aplicaciones Amplify.
- No crea ni almacena Access Keys.
- Se detiene ante el primer error; no continúa con dependencias incompletas.
- Exige la rama `feature/epico-deployment-readiness` y un repositorio limpio.
- Compara la identidad AWS activa con `-ExpectedAccountId` antes de crear recursos.
- Rechaza `CostCenterTag=PENDING` y `MediaCorsAllowedOrigins=*`.
