# Infraestructura compartida

`shared-resources.yml` define Cognito, Secrets Manager, el bucket privado S3 y CloudFront para una cuenta AWS ya creada.

La plantilla no configura dominio personalizado. CloudFront utiliza su certificado y dominio predeterminados. S3 bloquea acceso público y permite lectura exclusivamente desde la distribución mediante Origin Access Control.

## Recursos de identidad

- User Pool EPICO.
- App Client público sin secreto para frontends.
- App Client confidencial para Auth.
- Secreto `epico/production/cognito/auth-client-secret`.
- Lambda de recurso personalizado que transfiere el secreto generado por Cognito directamente a Secrets Manager, sin exponerlo como Output.

## Validar sin desplegar

```powershell
.\scripts\validate-infrastructure.ps1
```

La validación local usa AWS CloudFormation `validate-template`; requiere AWS CLI y credenciales con permiso de lectura de plantilla, pero no crea recursos.

## Parámetros pendientes antes del despliegue

- Reemplazar `CostCenterTag=PENDING`.
- Sustituir `MediaCorsAllowedOrigins=*` por las URLs definitivas de Amplify cuando existan.
- Confirmar política de contraseñas y recuperación de Cognito.

Después del despliegue, ejecutar `scripts/export-cloudformation-outputs.ps1` para generar el contrato local consumido por Serverless.
