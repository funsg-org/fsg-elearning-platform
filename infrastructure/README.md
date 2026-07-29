# Infraestructura compartida

La infraestructura de Amplify se mantiene separada en `amplify-hosting.yml`. Las aplicaciones se conectan exclusivamente a la rama de preparación y nacen con auto-build desactivado. Consulte `config/amplify-hosting.md` antes de activarlas.

`shared-resources.yml` define Cognito, Secrets Manager, el bucket privado S3 y CloudFront para una cuenta AWS ya creada.

La plantilla no configura dominio personalizado. CloudFront utiliza su certificado y dominio predeterminados. S3 bloquea acceso público y permite lectura exclusivamente desde la distribución mediante Origin Access Control.

## Recursos de identidad

- User Pool por ambiente con username nativo: la cédula identifica al usuario del portal público y el correo funciona como alias verificado. Los administradores reciben un username interno estable, acceden mediante el alias de correo y pertenecen al grupo administrativo.
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
- Generar `config/amplify-outputs.env`; el orquestador inyecta automáticamente sus dos URLs como orígenes CORS exactos.
- Confirmar política de contraseñas y recuperación de Cognito.

Después del despliegue, ejecutar `scripts/export-cloudformation-outputs.ps1` para generar el contrato local consumido por Serverless.
